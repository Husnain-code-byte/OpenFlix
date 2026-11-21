package com.example.pixel.cloudstream

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class CloudStreamChannelHandler(appContext: Context) :
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    companion object {
        const val METHOD_CHANNEL = "openflix/cloudstream"
        const val EVENT_CHANNEL = "openflix/cloudstream_events"
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val pluginManager = Cs3PluginManager(appContext)
    @Volatile
    private var eventSink: EventChannel.EventSink? = null

    private val streamMatcher = Cs3StreamMatcher(pluginManager) { event ->
        eventSink?.success(event)
    }

    fun registerWith(flutterEngine: FlutterEngine) {
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler(this)
        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "loadSavedPlugins" -> {
                @Suppress("UNCHECKED_CAST")
                val plugins = call.argument<List<Map<String, Any?>>>("plugins") ?: emptyList()
                scope.launch {
                    val statuses = mutableMapOf<String, Map<String, Any?>>()
                    for (entry in plugins) {
                        val uid = entry["uid"]?.toString() ?: continue
                        val localPath = entry["localFilePath"]?.toString() ?: continue
                        val enabled = entry["enabled"] != false
                        statuses[uid] = pluginManager.loadSavedPlugin(uid, localPath, enabled)
                    }
                    result.success(statuses)
                }
            }
            "installPlugin" -> {
                val uid = call.argument<String>("uid") ?: ""
                val repoId = call.argument<String>("repoId") ?: ""
                val internalName = call.argument<String>("internalName") ?: ""
                val downloadUrl = call.argument<String>("downloadUrl") ?: ""
                val expectedSha256 = call.argument<String>("expectedSha256")
                val enabled = call.argument<Boolean>("enabled") ?: true
                if (uid.isBlank() || downloadUrl.isBlank()) {
                    result.error("INVALID_ARGS", "uid and downloadUrl are required", null)
                    return
                }
                scope.launch {
                    val outcome = pluginManager.installAndLoad(
                        uid = uid,
                        repoId = repoId,
                        internalName = internalName,
                        downloadUrl = downloadUrl,
                        expectedSha256 = expectedSha256,
                        enabled = enabled,
                    )
                    result.success(outcome)
                }
            }
            "setPluginEnabled" -> {
                val uid = call.argument<String>("uid") ?: ""
                val enabled = call.argument<Boolean>("enabled") ?: true
                scope.launch {
                    result.success(pluginManager.setPluginEnabled(uid, enabled))
                }
            }
            "uninstallPlugin" -> {
                val uid = call.argument<String>("uid") ?: ""
                val localFilePath = call.argument<String>("localFilePath")
                scope.launch {
                    result.success(pluginManager.uninstallPlugin(uid, localFilePath))
                }
            }
            "getLoadedStatus" -> {
                result.success(pluginManager.getLoadedSummary())
            }
            "startStreamResolution" -> {
                @Suppress("UNCHECKED_CAST")
                val args = (call.arguments as? Map<String, Any?>) ?: emptyMap()
                streamMatcher.startResolution(args)
                result.success(true)
            }
            "cancelStreamResolution" -> {
                val requestId = call.argument<String>("requestId")
                if (!requestId.isNullOrBlank()) {
                    streamMatcher.cancel(requestId)
                }
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }
}
