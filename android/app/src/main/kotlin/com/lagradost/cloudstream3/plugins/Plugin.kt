package com.lagradost.cloudstream3.plugins

import android.content.Context
import android.content.res.Resources

/**
 * Host compatibility subclass of [BasePlugin] expected by Android CloudStream 3
 * `.cs3` plugins (`@CloudstreamPlugin class Foo : Plugin()`).
 */
abstract class Plugin : BasePlugin() {
    @Throws(Throwable::class)
    open fun load(context: Context) {
        load()
    }

    var resources: Resources? = null

    var openSettings: ((context: Context) -> Unit)? = null

    companion object {
        @JvmField
        val `$stable`: Int = 8
    }
}
