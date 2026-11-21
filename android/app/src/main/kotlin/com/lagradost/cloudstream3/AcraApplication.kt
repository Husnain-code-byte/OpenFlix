package com.lagradost.cloudstream3

/**
 * Backwards-compatible alias for legacy `.cs3` plugins compiled against
 * `AcraApplication`. Extended by [com.example.pixel.OpenFlixApplication].
 */
open class AcraApplication : CloudStreamApp() {
    companion object {
        val context get() = CloudStreamApp.context

        fun removeKeys(folder: String): Int? = CloudStreamApp.removeKeys(folder)

        fun <T> setKey(path: String, value: T) = CloudStreamApp.setKey(path, value)

        fun <T> setKey(folder: String, path: String, value: T) =
            CloudStreamApp.setKey(folder, path, value)

        inline fun <reified T : Any> getKey(path: String, defVal: T?): T? =
            CloudStreamApp.getKey(path, defVal)

        inline fun <reified T : Any> getKey(path: String): T? =
            CloudStreamApp.getKey(path)

        inline fun <reified T : Any> getKey(folder: String, path: String): T? =
            CloudStreamApp.getKey(folder, path)

        inline fun <reified T : Any> getKey(folder: String, path: String, defVal: T?): T? =
            CloudStreamApp.getKey(folder, path, defVal)
    }
}
