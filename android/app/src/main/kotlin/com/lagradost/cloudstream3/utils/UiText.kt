package com.lagradost.cloudstream3.utils

import android.content.Context
import androidx.annotation.StringRes

sealed class UiText {
    data class DynamicString(val value: String) : UiText() {
        override fun toString(): String = value
    }

    class StringResource(
        @StringRes val resId: Int,
        val args: List<Any>,
    ) : UiText() {
        override fun equals(other: Any?): Boolean {
            if (other !is StringResource) return false
            return resId == other.resId && args == other.args
        }

        override fun hashCode(): Int = 31 * resId + args.hashCode()
    }

    fun asStringNull(context: Context?): String? =
        runCatching { asString(context ?: return null) }.getOrNull()

    fun asString(context: Context): String = when (this) {
        is DynamicString -> value
        is StringResource -> {
            val str = context.getString(resId)
            if (args.isEmpty()) {
                str
            } else {
                str.format(
                    *args.map {
                        if (it is UiText) it.asString(context) else it
                    }.toTypedArray(),
                )
            }
        }
    }
}

fun txt(value: String): UiText = UiText.DynamicString(value)

@JvmName("txtNull")
fun txt(value: String?): UiText? = value?.let { UiText.DynamicString(it) }

fun txt(@StringRes resId: Int, vararg args: Any): UiText =
    UiText.StringResource(resId, args.toList())
