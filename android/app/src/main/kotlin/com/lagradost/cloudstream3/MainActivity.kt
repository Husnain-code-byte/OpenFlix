package com.lagradost.cloudstream3

import com.lagradost.cloudstream3.utils.Event

open class MainActivity {
    companion object {
        val afterPluginsLoadedEvent = Event<Boolean>()
        val reloadHomeEvent = Event<Boolean>()
        var lastError: String? = null
    }
}
