package com.lagradost.cloudstream3

import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.net.Uri
import com.lagradost.api.setContext
import com.lagradost.cloudstream3.utils.DataStore.getKey
import com.lagradost.cloudstream3.utils.DataStore.getKeys
import com.lagradost.cloudstream3.utils.DataStore.removeKey
import com.lagradost.cloudstream3.utils.DataStore.removeKeys
import com.lagradost.cloudstream3.utils.DataStore.setKey
import java.lang.ref.WeakReference

/**
 * Host compatibility [Application] shim providing static `context`, DataStore
 * key/value helpers, and activity lookup expected by CloudStream `.cs3` plugins.
 */
open class CloudStreamApp : Application() {
    override fun attachBaseContext(base: Context?) {
        super.attachBaseContext(base)
        context = base
    }

    override fun onCreate() {
        super.onCreate()
        context = applicationContext
    }

    companion object {
        tailrec fun Context.getActivity(): Activity? = when (this) {
            is Activity -> this
            is ContextWrapper -> baseContext.getActivity()
            else -> null
        }

        private var _context: WeakReference<Context>? = null
        var context: Context?
            get() = _context?.get()
            protected set(value) {
                _context = value?.let { WeakReference(it) }
                setContext(value)
            }

        fun bindHostContext(ctx: Context) {
            context = ctx
        }

        fun <T : Any> getKeyClass(path: String, valueType: Class<T>): T? =
            context?.getKey(path, valueType)

        fun <T : Any> setKeyClass(path: String, value: T) {
            context?.setKey(path, value)
        }

        fun removeKeys(folder: String): Int? = context?.removeKeys(folder)

        fun <T> setKey(path: String, value: T) {
            context?.setKey(path, value)
        }

        fun <T> setKey(folder: String, path: String, value: T) {
            context?.setKey(folder, path, value)
        }

        inline fun <reified T : Any> getKey(path: String, defVal: T?): T? =
            context?.getKey(path, defVal)

        inline fun <reified T : Any> getKey(path: String): T? =
            context?.getKey(path)

        inline fun <reified T : Any> getKey(folder: String, path: String): T? =
            context?.getKey(folder, path)

        inline fun <reified T : Any> getKey(folder: String, path: String, defVal: T?): T? =
            context?.getKey(folder, path, defVal)

        fun getKeys(folder: String): List<String>? = context?.getKeys(folder)

        fun removeKey(folder: String, path: String) {
            context?.removeKey(folder, path)
        }

        fun removeKey(path: String) {
            context?.removeKey(path)
        }

        fun openBrowser(url: String, fallbackWebView: Boolean = false, fragment: Any? = null) {
            val ctx = context ?: return
            runCatching {
                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                ctx.startActivity(intent)
            }
        }

        fun openBrowser(url: String, activity: Activity?) {
            openBrowser(url)
        }
    }
}
