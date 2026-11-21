package com.lagradost.cloudstream3.syncproviders

import com.lagradost.cloudstream3.syncproviders.providers.AniListApi
import com.lagradost.cloudstream3.syncproviders.providers.SimklApi
import com.lagradost.cloudstream3.utils.UiText

open class AuthUser(
    open val id: Int = 0,
    open val name: String? = null,
    open val profilePicture: String? = null,
)

interface SyncAPI {
    val name: String
        get() = ""

    data class LibraryMetadata(
        val allLibraryLists: List<LibraryList> = emptyList(),
    )

    data class LibraryList(
        val name: UiText,
        val items: List<Any> = emptyList(),
    )
}

open class SyncRepo(val api: SyncAPI) {
    fun authUser(): AuthUser? = null
}

abstract class AccountManager {
    companion object {
        val aniListApi: AniListApi = AniListApi()
        val simklApi: SimklApi = SimklApi()
    }
}
