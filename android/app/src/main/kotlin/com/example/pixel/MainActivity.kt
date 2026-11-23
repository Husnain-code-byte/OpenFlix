package com.example.pixel

import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
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
        private const val CONNECTIVITY_CHANNEL = "openflix/connectivity"
    }

    private var launcherChannel: MethodChannel? = null
    private var connectivityChannel: MethodChannel? = null
    private var networkCallback: ConnectivityManager.NetworkCallback? = null
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

    override fun onDestroy() {
        unregisterConnectivityCallback()
        super.onDestroy()
    }

    private fun hasActiveInternetInterface(): Boolean {
        val cm = applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return true
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val active = cm.activeNetwork ?: return false
                val caps = cm.getNetworkCapabilities(active) ?: return false
                caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                    (caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) ||
                        caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) ||
                        caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) ||
                        caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN))
            } else {
                @Suppress("DEPRECATION")
                cm.activeNetworkInfo?.isConnected == true
            }
        } catch (_: Exception) {
            true
        }
    }

    private fun registerConnectivityCallback() {
        if (networkCallback != null || Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return
        val cm = applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                runOnUiThread {
                    connectivityChannel?.invokeMethod("onConnectivityChanged", true)
                }
            }

            override fun onLost(network: Network) {
                runOnUiThread {
                    val stillOnline = hasActiveInternetInterface()
                    connectivityChannel?.invokeMethod("onConnectivityChanged", stillOnline)
                }
            }

            override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) {
                val online = caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                runOnUiThread {
                    connectivityChannel?.invokeMethod("onConnectivityChanged", online)
                }
            }
        }
        try {
            cm.registerDefaultNetworkCallback(cb)
            networkCallback = cb
        } catch (_: Exception) {
            networkCallback = null
        }
    }

    private fun unregisterConnectivityCallback() {
        val cb = networkCallback ?: return
        networkCallback = null
        try {
            val cm = applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            cm?.unregisterNetworkCallback(cb)
        } catch (_: Exception) {}
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

        connectivityChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CONNECTIVITY_CHANNEL,
        )
        registerConnectivityCallback()

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
                    "hasNetworkConnection" -> result.success(hasActiveInternetInterface())
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
