package com.lagradost.cloudstream3.plugins

data class PluginData(
    val internalName: String = "",
    val filePath: String = "",
)

object PluginManager {
    @Volatile
    var onlinePluginsProvider: (() -> Array<PluginData>)? = null

    @Volatile
    var unloadPluginHandler: ((String) -> Unit)? = null

    fun getPluginsOnline(): Array<PluginData> =
        onlinePluginsProvider?.invoke() ?: emptyArray()

    fun unloadPlugin(filePath: String) {
        unloadPluginHandler?.invoke(filePath)
    }
}
