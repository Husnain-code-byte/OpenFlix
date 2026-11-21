package com.lagradost.cloudstream3.network

import androidx.annotation.AnyThread
import com.lagradost.cloudstream3.app
import com.lagradost.nicehttp.cookies
import kotlinx.coroutines.runBlocking
import okhttp3.Interceptor
import okhttp3.Request
import okhttp3.Response
import java.util.concurrent.ConcurrentHashMap

@AnyThread
class DdosGuardKiller(private val alwaysBypass: Boolean) : Interceptor {
    val savedCookiesMap: MutableMap<String, Map<String, String>> = ConcurrentHashMap()
    private var ddosBypassPath: String? = null

    override fun intercept(chain: Interceptor.Chain): Response = runBlocking {
        val request = chain.request()
        if (alwaysBypass) return@runBlocking bypassDdosGuard(request)
        val response = chain.proceed(request)
        if (response.code == 403) {
            response.close()
            bypassDdosGuard(request)
        } else {
            response
        }
    }

    private suspend fun bypassDdosGuard(request: Request): Response {
        val host = request.url.host
        val cookies = savedCookiesMap[host] ?: run {
            val checkJs = runCatching {
                app.get("https://check.ddos-guard.net/check.js").text
            }.getOrNull()
            val path = checkJs?.substringAfter("'")?.substringBefore("'")
                ?: "/.well-known/ddos-guard/id/"
            ddosBypassPath = path
            val bypassUrl = "${request.url.scheme}://$host$path"
            val resp = runCatching { app.get(bypassUrl) }.getOrNull()
            val fetched = resp?.cookies ?: emptyMap()
            if (fetched.isNotEmpty()) savedCookiesMap[host] = fetched
            fetched
        }
        val mergedHeaders = getHeaders(
            request.headers.toMap(),
            cookies + request.cookies,
        )
        return app.baseClient.newCall(
            request.newBuilder().headers(mergedHeaders).build(),
        ).execute()
    }
}
