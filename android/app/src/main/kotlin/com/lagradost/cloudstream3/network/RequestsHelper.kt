package com.lagradost.cloudstream3.network

import android.content.Context
import com.lagradost.cloudstream3.USER_AGENT
import okhttp3.Cache
import okhttp3.Headers
import okhttp3.Headers.Companion.toHeaders
import okhttp3.OkHttpClient
import java.io.File
import java.util.concurrent.TimeUnit

private val DEFAULT_CS3_HEADERS = mapOf("user-agent" to USER_AGENT)

fun buildDefaultClient(context: Context): OkHttpClient =
    OkHttpClient.Builder()
        .followRedirects(true)
        .followSslRedirects(true)
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(25, TimeUnit.SECONDS)
        .writeTimeout(25, TimeUnit.SECONDS)
        .cache(Cache(directory = File(context.cacheDir, "cs3_http_cache"), maxSize = 32L * 1024L * 1024L))
        .build()

fun getHeaders(
    headers: Map<String, String>,
    cookie: Map<String, String>,
): Headers {
    val cookieMap = if (cookie.isNotEmpty()) {
        mapOf(
            "Cookie" to cookie.entries.joinToString(" ") { "${it.key}=${it.value};" },
        )
    } else {
        emptyMap()
    }
    return (DEFAULT_CS3_HEADERS + headers + cookieMap).toHeaders()
}
