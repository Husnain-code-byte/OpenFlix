package com.lagradost.cloudstream3.network

import android.util.Log
import android.webkit.CookieManager
import androidx.annotation.AnyThread
import com.lagradost.cloudstream3.app
import com.lagradost.nicehttp.Requests.Companion.await
import com.lagradost.nicehttp.cookies
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeoutOrNull
import okhttp3.Headers
import okhttp3.Interceptor
import okhttp3.Request
import okhttp3.Response
import java.net.URI
import java.util.concurrent.ConcurrentHashMap

@AnyThread
class CloudflareKiller : Interceptor {
    companion object {
        const val TAG = "CloudflareKiller"
        private val ERROR_CODES = listOf(403, 503)
        private val CLOUDFLARE_SERVERS = listOf("cloudflare-nginx", "cloudflare")

        fun parseCookieMap(cookie: String): Map<String, String> =
            cookie.split(";").associate {
                val split = it.split("=", limit = 2)
                (split.getOrNull(0)?.trim() ?: "") to (split.getOrNull(1)?.trim() ?: "")
            }.filter { it.key.isNotBlank() && it.value.isNotBlank() }
    }

    val savedCookies: MutableMap<String, Map<String, String>> = ConcurrentHashMap()

    fun getCookieHeaders(url: String): Headers {
        val userAgentHeaders = WebViewResolver.webViewUserAgent?.let {
            mapOf("user-agent" to it)
        } ?: emptyMap()
        val host = runCatching { URI(url).host }.getOrNull()
        return getHeaders(userAgentHeaders, host?.let { savedCookies[it] } ?: emptyMap())
    }

    override fun intercept(chain: Interceptor.Chain): Response = runBlocking {
        val request = chain.request()
        val cookies = savedCookies[request.url.host]
        if (cookies == null) {
            val response = chain.proceed(request)
            val isCf = response.header("Server") in CLOUDFLARE_SERVERS &&
                response.code in ERROR_CODES
            if (!isCf) {
                return@runBlocking response
            }
            response.close()
            bypassCloudflare(request)?.let {
                Log.d(TAG, "Bypassed Cloudflare for ${request.url}")
                return@runBlocking it
            }
            return@runBlocking chain.proceed(request)
        }
        proceed(request, cookies)
    }

    private fun getWebViewCookie(url: String): String? = runCatching {
        CookieManager.getInstance()?.getCookie(url)
    }.getOrNull()

    private fun trySolveWithSavedCookies(request: Request): Boolean {
        val cookie = getWebViewCookie(request.url.toString()) ?: return false
        val solved = cookie.contains("cf_clearance")
        if (solved) {
            savedCookies[request.url.host] = parseCookieMap(cookie)
        }
        return solved
    }

    private suspend fun proceed(request: Request, cookies: Map<String, String>): Response {
        val userAgentMap = WebViewResolver.webViewUserAgent?.let {
            mapOf("user-agent" to it)
        } ?: emptyMap()
        val headers = getHeaders(request.headers.toMap() + userAgentMap, cookies + request.cookies)
        return app.baseClient.newCall(
            request.newBuilder().headers(headers).build(),
        ).await()
    }

    private suspend fun bypassCloudflare(request: Request): Response? {
        val url = request.url.toString()
        if (!trySolveWithSavedCookies(request)) {
            withTimeoutOrNull(12_000L) {
                runCatching {
                    WebViewResolver(
                        interceptUrl = Regex(".^"),
                        additionalUrls = listOf(Regex(".")),
                        userAgent = null,
                        useOkhttp = false,
                        timeout = 12_000L,
                    ).resolveUsingWebView(url) {
                        trySolveWithSavedCookies(request)
                    }
                }
            }
        }
        val cookies = savedCookies[request.url.host] ?: return null
        return runCatching { proceed(request, cookies) }.getOrNull()
    }
}
