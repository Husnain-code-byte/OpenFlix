package com.lagradost.cloudstream3

import android.app.Activity
import android.content.res.Resources
import android.util.DisplayMetrics
import android.util.Log
import androidx.annotation.MainThread
import androidx.annotation.StringRes
import com.lagradost.cloudstream3.utils.UiText
import java.lang.ref.WeakReference

object CommonActivity {
    private const val TAG = "OpenFlixCs3Host"

    private var _activity: WeakReference<Activity>? = null
    var activity: Activity?
        get() = _activity?.get()
        private set(value) {
            _activity = value?.let { WeakReference(it) }
        }

    @MainThread
    fun setActivityInstance(newActivity: Activity?) {
        activity = newActivity
    }

    val displayMetrics: DisplayMetrics = Resources.getSystem().displayMetrics

    fun showToast(@StringRes message: Int, duration: Int? = null) {
        val act = activity ?: return
        Log.i(TAG, "Plugin toast: ${act.getString(message)}")
    }

    fun showToast(message: String?, duration: Int? = null) {
        if (!message.isNullOrBlank()) {
            Log.i(TAG, "Plugin toast: $message")
        }
    }

    fun showToast(message: UiText?, duration: Int? = null) {
        val text = message?.asStringNull(activity ?: CloudStreamApp.context)
        if (!text.isNullOrBlank()) {
            Log.i(TAG, "Plugin toast: $text")
        }
    }

    @MainThread
    fun showToast(act: Activity?, text: UiText, duration: Int) {
        showToast(text, duration)
    }

    @MainThread
    fun showToast(act: Activity?, @StringRes message: Int, duration: Int? = null) {
        if (act != null) showToast(act.getString(message), duration)
    }

    @MainThread
    fun showToast(act: Activity?, message: String?, duration: Int? = null) {
        showToast(message, duration)
    }
}
