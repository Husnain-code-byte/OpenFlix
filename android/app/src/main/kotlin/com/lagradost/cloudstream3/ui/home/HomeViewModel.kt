package com.lagradost.cloudstream3.ui.home

import com.lagradost.cloudstream3.utils.DataStoreHelper

open class HomeViewModel {
    companion object {
        suspend fun getResumeWatching(): List<DataStoreHelper.ResumeWatchingResult> = emptyList()
    }
}
