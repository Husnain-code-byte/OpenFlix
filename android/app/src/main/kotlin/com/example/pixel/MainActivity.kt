package com.example.pixel

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.core.content.FileProvider
import com.example.pixel.cloudstream.CloudStreamChannelHandler
import com.lagradost.cloudstream3.CommonActivity
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    companion object {
        private const val LAUNCHER_CHANNEL = "openflix/launcher"
    }

    private var launcherChannel: MethodChannel? = null
    private var pendingDeepLink: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captureDeepLink(intent, deliverImmediately = false)
    }

    override fun onResume() {
        super.onResume()
        CommonActivity.setActivityInstance(this)
    }

    override fun onPause() {
        CommonActivity.setActivityInstance(null)
        super.onPause()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureDeepLink(intent, deliverImmediately = true)
    }

    private fun captureDeepLink(intent: Intent?, deliverImmediately: Boolean) {
        val data = intent?.data ?: return
        if (!data.scheme.equals("stremio", ignoreCase = true)) return
        val uriString = data.toString()
        if (deliverImmediately && launcherChannel != null) {
            launcherChannel?.invokeMethod("onDeepLink", uriString)
        } else {
            pendingDeepLink = uriString
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        CloudStreamChannelHandler(applicationContext).registerWith(flutterEngine)

        launcherChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            LAUNCHER_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "openUrl" -> {
                        val url = call.argument<String>("url")
                        if (!url.isNullOrBlank()) {
                            try {
                                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                startActivity(intent)
                                result.success(true)
                            } catch (_: Exception) {
                                result.success(false)
                            }
                        } else {
                            result.success(false)
                        }
                    }
                    "getFilesDir" -> result.success(applicationContext.filesDir.absolutePath)
                    "getCacheDir" -> result.success(applicationContext.cacheDir.absolutePath)
                    "installApk" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.success(false)
                        } else {
                            try {
                                val file = File(path)
                                if (!file.exists()) {
                                    result.success(false)
                                } else {
                                    val apkUri = FileProvider.getUriForFile(
                                        this,
                                        "${applicationContext.packageName}.fileprovider",
                                        file,
                                    )
                                    val installIntent = Intent(Intent.ACTION_VIEW).apply {
                                        setDataAndType(apkUri, "application/vnd.android.package-archive")
                                        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    }
                                    startActivity(installIntent)
                                    result.success(true)
                                }
                            } catch (_: Exception) {
                                result.success(false)
                            }
                        }
                    }
                    "getInitialDeepLink" -> {
                        val link = pendingDeepLink
                        pendingDeepLink = null
                        result.success(link)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }
}
