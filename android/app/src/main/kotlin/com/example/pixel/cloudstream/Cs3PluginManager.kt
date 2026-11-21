package com.example.pixel.cloudstream

import android.content.ContentResolver
import android.content.Context
import android.content.SharedPreferences
import android.content.res.AssetManager
import android.content.res.Resources
import android.util.Log
import androidx.appcompat.app.AppCompatActivity
import com.fasterxml.jackson.databind.DeserializationFeature
import com.fasterxml.jackson.module.kotlin.jacksonObjectMapper
import com.lagradost.cloudstream3.APIHolder
import com.lagradost.cloudstream3.MainAPI
import com.lagradost.cloudstream3.plugins.BasePlugin
import com.lagradost.cloudstream3.plugins.Plugin
import com.lagradost.cloudstream3.plugins.PluginData
import com.lagradost.cloudstream3.plugins.PluginManager
import com.lagradost.cloudstream3.utils.ExtractorApi
import com.lagradost.cloudstream3.utils.extractorApis
import dalvik.system.PathClassLoader
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.TimeUnit
import java.util.zip.ZipFile

data class Cs3Manifest(
    val name: String? = null,
    val pluginClassName: String? = null,
    val requiresResources: Boolean = false,
    val version: Int? = null,
)

data class LoadedPluginHandle(
    val uid: String,
    val filePath: String,
    val plugin: BasePlugin,
    val classLoader: PathClassLoader,
    val providers: List<MainAPI>,
    val extractors: List<ExtractorApi>,
    @Volatile var enabled: Boolean,
)

class Cs3PluginManager(private val appContext: Context) {
    companion object {
        private const val TAG = "OpenFlixCs3Manager"
    }

    private val mapper = jacksonObjectMapper().configure(
        DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES,
        false,
    )

    private val httpClient = OkHttpClient.Builder()
        .followRedirects(true)
        .followSslRedirects(true)
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(35, TimeUnit.SECONDS)
        .build()

    private val mutex = Mutex()
    private val loadedHandles = ConcurrentHashMap<String, LoadedPluginHandle>()

    @Volatile
    private var pluginHostContext: Context? = null

    /**
     * Lightweight [AppCompatActivity] context backed by [appContext] so `.cs3`
     * plugins that cast `context as AppCompatActivity` during `load(context)`
     * (e.g. CNC/Raghav settings lambdas) succeed without a ClassCastException.
     */
    private class Cs3HostAppCompatContext(private val base: Context) : AppCompatActivity() {
        init {
            attachBaseContext(base)
        }

        override fun getApplicationContext(): Context = base.applicationContext
        override fun getSharedPreferences(name: String?, mode: Int): SharedPreferences =
            base.getSharedPreferences(name, mode)
        override fun getResources(): Resources = base.resources
        override fun getAssets(): AssetManager = base.assets
        override fun getFilesDir(): File = base.filesDir
        override fun getCacheDir(): File = base.cacheDir
        override fun getPackageName(): String = base.packageName
        override fun getContentResolver(): ContentResolver = base.contentResolver
        override fun getSystemService(name: String): Any? = base.getSystemService(name)
    }

    private suspend fun getOrCreatePluginHostContext(): Context {
        pluginHostContext?.let { return it }
        return withContext(Dispatchers.Main) {
            pluginHostContext ?: runCatching {
                Cs3HostAppCompatContext(appContext)
            }.getOrElse {
                Log.w(TAG, "Falling back to appContext for plugin host", it)
                appContext
            }.also { pluginHostContext = it }
        }
    }

    init {
        PluginManager.onlinePluginsProvider = {
            loadedHandles.values.map { handle ->
                PluginData(
                    internalName = handle.uid.substringAfter(':', handle.uid),
                    filePath = handle.filePath,
                )
            }.toTypedArray()
        }
    }

    private fun pluginsRootDir(): File =
        File(appContext.filesDir, "cs3_plugins").apply { mkdirs() }

    private fun sanitizeSegment(raw: String): String =
        raw.replace(Regex("[^A-Za-z0-9._-]"), "_").ifBlank { "plugin" }

    fun targetPluginFile(repoId: String, internalName: String): File {
        val repoDir = File(pluginsRootDir(), sanitizeSegment(repoId)).apply { mkdirs() }
        return File(repoDir, "${sanitizeSegment(internalName)}.cs3")
    }

    fun getEnabledProviders(): List<MainAPI> =
        loadedHandles.values
            .filter { it.enabled }
            .flatMap { it.providers }

    fun getLoadedSummary(): Map<String, Map<String, Any?>> =
        loadedHandles.mapValues { (_, h) ->
            mapOf(
                "uid" to h.uid,
                "localFilePath" to h.filePath,
                "enabled" to h.enabled,
                "providers" to h.providers.map { it.name },
                "extractors" to h.extractors.map { it.name },
            )
        }

    suspend fun installAndLoad(
        uid: String,
        repoId: String,
        internalName: String,
        downloadUrl: String,
        expectedSha256: String?,
        enabled: Boolean = true,
    ): Map<String, Any?> = withContext(Dispatchers.IO) {
        val targetFile = targetPluginFile(repoId, internalName)
        val tempFile = File(targetFile.parentFile, "${targetFile.name}.${System.nanoTime()}.tmp")
        try {
            // 1. Download .cs3 binary to temp file OUTSIDE mutex for parallel repo installs
            val request = Request.Builder().url(downloadUrl).build()
            httpClient.newCall(request).execute().use { response ->
                if (!response.isSuccessful) {
                    return@withContext failureResult(
                        "Download failed (HTTP ${response.code})",
                    )
                }
                val body = response.body
                FileOutputStream(tempFile).use { out ->
                    body.byteStream().copyTo(out)
                }
            }

            // 2. Verify SHA-256 if provided (supports "sha256-<hex>" or raw hex)
            val normalizedExpected = expectedSha256
                ?.trim()
                ?.removePrefix("sha256-")
                ?.lowercase()
            if (!normalizedExpected.isNullOrBlank()) {
                val actualHash = sha256Hex(tempFile)
                if (actualHash != normalizedExpected) {
                    tempFile.delete()
                    return@withContext failureResult(
                        "SHA-256 checksum mismatch for $internalName",
                    )
                }
            }

            // 3. Validate ZIP structure (classes.dex + manifest.json)
            val manifest = readAndValidateCs3Archive(tempFile)
            if (manifest.pluginClassName.isNullOrBlank()) {
                tempFile.delete()
                return@withContext failureResult(
                    "Invalid .cs3 archive: missing pluginClassName in manifest.json",
                )
            }

            // 4-5. Hold mutex only for atomic file swap + PathClassLoader + APIHolder registration
            val hostCtx = getOrCreatePluginHostContext()
            mutex.withLock {
                unloadPluginLocked(uid)
                if (targetFile.exists()) {
                    targetFile.setWritable(true)
                    targetFile.delete()
                }
                if (!tempFile.renameTo(targetFile)) {
                    tempFile.copyTo(targetFile, overwrite = true)
                    tempFile.delete()
                }
                loadFileLocked(uid, targetFile, manifest, enabled, hostCtx)
            }
        } catch (t: Throwable) {
            runCatching { tempFile.delete() }
            Log.e(TAG, "installAndLoad failed for $uid", t)
            failureResult("${t::class.java.simpleName}: ${t.message ?: "Unknown error"}")
        }
    }

    suspend fun loadSavedPlugin(
        uid: String,
        localFilePath: String,
        enabled: Boolean,
    ): Map<String, Any?> = withContext(Dispatchers.IO) {
        val hostCtx = getOrCreatePluginHostContext()
        mutex.withLock {
            val file = File(localFilePath)
            if (!file.exists()) {
                return@withLock failureResult("Plugin file missing on disk: $localFilePath")
            }
            try {
                if (loadedHandles.containsKey(uid)) {
                    loadedHandles[uid]?.enabled = enabled
                    val h = loadedHandles[uid]!!
                    return@withLock successResult(h)
                }
                val manifest = readAndValidateCs3Archive(file)
                loadFileLocked(uid, file, manifest, enabled, hostCtx)
            } catch (t: Throwable) {
                Log.e(TAG, "loadSavedPlugin failed for $uid", t)
                failureResult("${t::class.java.simpleName}: ${t.message ?: "Load failed"}")
            }
        }
    }

    suspend fun setPluginEnabled(uid: String, enabled: Boolean): Boolean =
        withContext(Dispatchers.IO) {
            mutex.withLock {
                val handle = loadedHandles[uid] ?: return@withLock false
                handle.enabled = enabled
                true
            }
        }

    suspend fun uninstallPlugin(uid: String, localFilePath: String?): Boolean =
        withContext(Dispatchers.IO) {
            mutex.withLock {
                val handle = loadedHandles[uid]
                unloadPluginLocked(uid)
                val targetPath = localFilePath ?: handle?.filePath
                if (!targetPath.isNullOrBlank()) {
                    val file = File(targetPath)
                    if (file.exists()) {
                        file.setWritable(true)
                        file.delete()
                    }
                }
                true
            }
        }

    private fun readAndValidateCs3Archive(file: File): Cs3Manifest {
        ZipFile(file).use { zip ->
            val dexEntry = zip.getEntry("classes.dex")
                ?: throw IllegalStateException("Archive does not contain classes.dex")
            if (dexEntry.size == 0L) {
                throw IllegalStateException("Empty classes.dex")
            }
            val manifestEntry = zip.getEntry("manifest.json")
                ?: throw IllegalStateException("Archive does not contain manifest.json")
            val json = zip.getInputStream(manifestEntry).bufferedReader().use { it.readText() }
            return mapper.readValue(json, Cs3Manifest::class.java)
        }
    }

    private fun loadFileLocked(
        uid: String,
        file: File,
        manifest: Cs3Manifest,
        enabled: Boolean,
        hostContext: Context,
    ): Map<String, Any?> {
        // Android 14+ (API 34+) strictly rejects writable DEX/JAR/APK code paths.
        if (!file.setReadOnly()) {
            Log.w(TAG, "setReadOnly returned false for ${file.absolutePath}")
        }

        val className = manifest.pluginClassName
            ?: return failureResult("Missing pluginClassName")
        val loader = PathClassLoader(file.absolutePath, appContext.classLoader)

        val pluginClass = loader.loadClass(className)
        val instance = pluginClass.getDeclaredConstructor().newInstance()
        if (instance !is BasePlugin) {
            return failureResult("$className does not extend BasePlugin")
        }

        instance.filename = file.absolutePath

        if (manifest.requiresResources && instance is Plugin) {
            runCatching {
                val assets = AssetManager::class.java.getDeclaredConstructor().newInstance()
                val addAssetPath =
                    AssetManager::class.java.getMethod("addAssetPath", String::class.java)
                addAssetPath.invoke(assets, file.absolutePath)
                @Suppress("DEPRECATION")
                instance.resources = Resources(
                    assets,
                    appContext.resources.displayMetrics,
                    appContext.resources.configuration,
                )
            }
        }

        val beforeProviders = synchronized(APIHolder.allProviders) {
            APIHolder.allProviders.toSet()
        }
        val beforeExtractors = synchronized(extractorApis) {
            extractorApis.toSet()
        }

        try {
            if (instance is Plugin) {
                instance.load(hostContext)
            } else {
                instance.load()
            }
        } catch (t: Throwable) {
            // Roll back any partial registrations made before failure.
            rollbackDelta(file.absolutePath, beforeProviders, beforeExtractors)
            return failureResult(
                "${t::class.java.simpleName}: ${t.message ?: "Plugin load() failed"}",
            )
        }

        val addedProviders = synchronized(APIHolder.allProviders) {
            APIHolder.allProviders.filter {
                it !in beforeProviders || it.sourcePlugin == file.absolutePath
            }
        }
        val addedExtractors = synchronized(extractorApis) {
            extractorApis.filter {
                it !in beforeExtractors || it.sourcePlugin == file.absolutePath
            }
        }

        addedProviders.forEach { if (it.sourcePlugin.isNullOrBlank()) it.sourcePlugin = file.absolutePath }
        addedExtractors.forEach { if (it.sourcePlugin.isNullOrBlank()) it.sourcePlugin = file.absolutePath }

        val handle = LoadedPluginHandle(
            uid = uid,
            filePath = file.absolutePath,
            plugin = instance,
            classLoader = loader,
            providers = addedProviders,
            extractors = addedExtractors,
            enabled = enabled,
        )
        loadedHandles[uid] = handle
        Log.i(
            TAG,
            "Loaded .cs3 [$uid] -> ${addedProviders.size} providers, ${addedExtractors.size} extractors",
        )
        return successResult(handle)
    }

    private fun unloadPluginLocked(uid: String) {
        val handle = loadedHandles.remove(uid) ?: return
        runCatching { handle.plugin.beforeUnload() }

        handle.providers.forEach { provider ->
            runCatching { APIHolder.removePluginMapping(provider) }
        }
        synchronized(APIHolder.allProviders) {
            APIHolder.allProviders.removeAll {
                it in handle.providers || it.sourcePlugin == handle.filePath
            }
        }
        synchronized(extractorApis) {
            extractorApis.removeAll {
                it in handle.extractors || it.sourcePlugin == handle.filePath
            }
        }
    }

    private fun rollbackDelta(
        filePath: String,
        beforeProviders: Set<MainAPI>,
        beforeExtractors: Set<ExtractorApi>,
    ) {
        synchronized(APIHolder.allProviders) {
            APIHolder.allProviders.removeAll {
                it !in beforeProviders || it.sourcePlugin == filePath
            }
        }
        synchronized(extractorApis) {
            extractorApis.removeAll {
                it !in beforeExtractors || it.sourcePlugin == filePath
            }
        }
    }

    private fun successResult(h: LoadedPluginHandle): Map<String, Any?> = mapOf(
        "status" to "loaded",
        "localFilePath" to h.filePath,
        "providers" to h.providers.map { it.name },
        "extractors" to h.extractors.map { it.name },
        "error" to null,
    )

    private fun failureResult(error: String): Map<String, Any?> = mapOf(
        "status" to "failed",
        "localFilePath" to null,
        "providers" to emptyList<String>(),
        "extractors" to emptyList<String>(),
        "error" to error,
    )

    private fun sha256Hex(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buf = ByteArray(8192)
            while (true) {
                val n = input.read(buf)
                if (n <= 0) break
                digest.update(buf, 0, n)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }
}
