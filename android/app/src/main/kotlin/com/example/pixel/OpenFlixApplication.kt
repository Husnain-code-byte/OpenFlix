package com.example.pixel

import com.lagradost.cloudstream3.APIHolder
import com.lagradost.cloudstream3.AcraApplication
import com.lagradost.cloudstream3.USER_AGENT
import com.lagradost.cloudstream3.app
import com.lagradost.cloudstream3.insecureApp
import com.lagradost.cloudstream3.network.buildDefaultClient
import com.lagradost.nicehttp.Requests
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class OpenFlixApplication : AcraApplication() {
    private val initScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onCreate() {
        super.onCreate()
        bindHostContext(applicationContext)

        val defaultClient = buildDefaultClient(applicationContext)
        app = Requests(
            baseClient = defaultClient,
            defaultHeaders = mapOf("user-agent" to USER_AGENT),
        )
        insecureApp = Requests(
            baseClient = defaultClient,
            defaultHeaders = mapOf("user-agent" to USER_AGENT),
        )

        initScope.launch {
            runCatching { APIHolder.initAll() }
        }
    }
}
