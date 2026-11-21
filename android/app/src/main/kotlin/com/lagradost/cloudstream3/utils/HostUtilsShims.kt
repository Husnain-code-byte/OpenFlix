package com.lagradost.cloudstream3.utils

object DataStoreHelper {
    data class ResumeWatchingResult(
        val name: String = "",
        val url: String = "",
        val apiName: String = "",
        val episode: Int? = null,
        val season: Int? = null,
    )
}

object AppContextUtils {
    fun loadResult(
        url: String,
        apiName: String,
        startAction: String? = null,
        startValue: Int = 0,
        extra: Int = 0,
    ) {
        // No-op host shim; playback/details navigation is owned by Flutter.
    }
}

object UIHelper
