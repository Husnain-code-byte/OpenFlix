package com.example.pixel.cloudstream

import android.os.Handler
import android.os.Looper
import android.util.Log
import com.lagradost.cloudstream3.AnimeLoadResponse
import com.lagradost.cloudstream3.DubStatus
import com.lagradost.cloudstream3.Episode
import com.lagradost.cloudstream3.LoadResponse
import com.lagradost.cloudstream3.MainAPI
import com.lagradost.cloudstream3.MovieLoadResponse
import com.lagradost.cloudstream3.SearchResponse
import com.lagradost.cloudstream3.SubtitleFile
import com.lagradost.cloudstream3.TorrentLoadResponse
import com.lagradost.cloudstream3.TvSeriesLoadResponse
import com.lagradost.cloudstream3.TvType
import com.lagradost.cloudstream3.syncproviders.SyncIdName
import com.lagradost.cloudstream3.utils.ExtractorLink
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.withTimeoutOrNull
import java.text.Normalizer
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

class Cs3StreamMatcher(
    private val pluginManager: Cs3PluginManager,
    private val emitEvent: (Map<String, Any?>) -> Unit,
) {
    companion object {
        private const val TAG = "OpenFlixCs3Matcher"
        private const val MAX_CONCURRENT_PROVIDERS = 2
        private const val SEARCH_TIMEOUT_MS = 6_000L
        private const val LOAD_TIMEOUT_MS = 6_000L
        private const val LINKS_TIMEOUT_MS = 9_000L
        private const val PROVIDER_BUDGET_MS = 14_000L
        private const val CACHE_TTL_MS = 20 * 60 * 1000L
        private const val MAX_CACHE_ENTRIES = 24
        private const val MIN_MATCH_SCORE = 0.72

        private val SEASON_IN_TEXT = Regex(
            """(?:\bseason|\bs)\s*0?(\d{1,2})\b""",
            RegexOption.IGNORE_CASE,
        )
        private val S_E_IN_TEXT = Regex(
            """\bs0?(\d{1,2})\s*[-._ ]?\s*e(?:p|pisode)?\s*0?(\d{1,3})\b""",
            RegexOption.IGNORE_CASE,
        )
        private val EP_IN_TEXT = Regex(
            """\b(?:episode|ep\.?|e)\s*0?(\d{1,3})\b""",
            RegexOption.IGNORE_CASE,
        )
        private val NOISE_TOKENS = Regex(
            """\b(season\s*\d+|s\d{1,2}|complete|hindi|english|dual\s*audio|multi\s*audio|dubbed|subbed|web-dl|webrip|hdrip|4k|1080p|720p)\b""",
            RegexOption.IGNORE_CASE,
        )
    }

    private data class CachedLoad(
        val response: LoadResponse,
        val storedAtMs: Long,
    )

    private data class ParsedEpisode(
        val ep: Episode,
        val season: Int?,
        val episode: Int?,
    )

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val activeJobs = ConcurrentHashMap<String, Job>()
    private val loadCache = ConcurrentHashMap<String, CachedLoad>()
    private val mainHandler = Handler(Looper.getMainLooper())

    private fun putLoadCache(key: String, resp: LoadResponse) {
        val now = System.currentTimeMillis()
        if (loadCache.size >= MAX_CACHE_ENTRIES) {
            val expired = loadCache.entries
                .filter { now - it.value.storedAtMs > CACHE_TTL_MS }
                .map { it.key }
            expired.forEach { loadCache.remove(it) }
            while (loadCache.size >= MAX_CACHE_ENTRIES) {
                val oldestKey = loadCache.entries.minByOrNull { it.value.storedAtMs }?.key ?: break
                loadCache.remove(oldestKey)
            }
        }
        loadCache[key] = CachedLoad(resp, now)
    }

    private fun postEvent(payload: Map<String, Any?>) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            emitEvent(payload)
        } else {
            mainHandler.post { emitEvent(payload) }
        }
    }

    fun cancel(requestId: String) {
        activeJobs.remove(requestId)?.cancel()
    }

    fun startResolution(args: Map<String, Any?>) {
        val requestId = args["requestId"]?.toString() ?: return
        cancel(requestId)

        val mediaType = args["mediaType"]?.toString() ?: "movie"
        val title = args["title"]?.toString()?.trim().orEmpty()
        val originalTitle = args["originalTitle"]?.toString()?.trim()
        val year = (args["year"] as? Number)?.toInt()
        val imdbId = args["imdbId"]?.toString()?.trim()
        val tmdbId = args["tmdbId"]?.toString()?.trim()
        val anilistId = args["anilistId"]?.toString()?.trim()
        val malId = args["malId"]?.toString()?.trim()
        val season = (args["season"] as? Number)?.toInt()
        val episode = (args["episode"] as? Number)?.toInt()
        val isAnime = args["isAnime"] == true
        val preferredLanguages = (args["preferredLanguages"] as? List<*>)
            ?.mapNotNull { it?.toString()?.lowercase()?.trim() }
            ?.filter { it.isNotEmpty() }
            .orEmpty()
        val skipProviders = (args["skipProviders"] as? List<*>)
            ?.mapNotNull { it?.toString()?.lowercase()?.trim() }
            ?.filter { it.isNotEmpty() }
            ?.toSet()
            .orEmpty()

        val providers = filterProvidersForQuery(
            providers = pluginManager.getEnabledProviders(),
            mediaType = mediaType,
            isAnime = isAnime,
            preferredLanguages = preferredLanguages,
            skipProviders = skipProviders,
        )

        val job = scope.launch {
            try {
                val semaphore = Semaphore(MAX_CONCURRENT_PROVIDERS)
                providers.map { provider ->
                    async {
                        semaphore.withPermit {
                            resolveForSingleProvider(
                                requestId = requestId,
                                provider = provider,
                                mediaType = mediaType,
                                title = title,
                                originalTitle = originalTitle,
                                year = year,
                                imdbId = imdbId,
                                tmdbId = tmdbId,
                                anilistId = anilistId,
                                malId = malId,
                                season = season,
                                episode = episode,
                                isAnime = isAnime,
                            )
                        }
                    }
                }.awaitAll()
                postEvent(
                    mapOf(
                        "requestId" to requestId,
                        "eventType" to "complete",
                    ),
                )
            } catch (_: CancellationException) {
            } catch (t: Throwable) {
                Log.e(TAG, "Resolution loop error", t)
            } finally {
                activeJobs.remove(requestId)
            }
        }
        activeJobs[requestId] = job
    }

    private fun filterProvidersForQuery(
        providers: List<MainAPI>,
        mediaType: String,
        isAnime: Boolean,
        preferredLanguages: List<String>,
        skipProviders: Set<String>,
    ): List<MainAPI> {
        val wantedTypes = buildSet {
            if (mediaType == "movie") {
                add(TvType.Movie)
                add(TvType.AnimeMovie)
                add(TvType.Documentary)
                add(TvType.Torrent)
            } else {
                add(TvType.TvSeries)
                add(TvType.AsianDrama)
                add(TvType.Cartoon)
                add(TvType.Anime)
                add(TvType.OVA)
                add(TvType.Documentary)
                add(TvType.Torrent)
            }
            if (isAnime) {
                add(TvType.Anime)
                add(TvType.AnimeMovie)
                add(TvType.OVA)
            }
        }
        val primaryLang = preferredLanguages.getOrNull(0)
        val fallbackLang = preferredLanguages.getOrNull(1)
        val multiLangTags = setOf("uni", "multi", "all", "")

        return providers
            .filter { p ->
                p.supportedTypes.any { it in wantedTypes } &&
                    p.name.trim().lowercase() !in skipProviders
            }
            .sortedBy { p ->
                val lang = p.lang.trim().lowercase()
                when {
                    primaryLang != null && lang == primaryLang -> 0
                    lang in multiLangTags -> 1
                    fallbackLang != null && lang == fallbackLang -> 2
                    else -> 3
                }
            }
    }

    private suspend fun resolveForSingleProvider(
        requestId: String,
        provider: MainAPI,
        mediaType: String,
        title: String,
        originalTitle: String?,
        year: Int?,
        imdbId: String?,
        tmdbId: String?,
        anilistId: String?,
        malId: String?,
        season: Int?,
        episode: Int?,
        isAnime: Boolean,
    ) {
        val startNs = System.nanoTime()
        var streamCount = 0
        try {
            val result = withTimeoutOrNull(PROVIDER_BUDGET_MS) {
                val loadResp = getOrLoadMedia(
                    provider = provider,
                    mediaType = mediaType,
                    title = title,
                    originalTitle = originalTitle,
                    year = year,
                    imdbId = imdbId,
                    tmdbId = tmdbId,
                    anilistId = anilistId,
                    malId = malId,
                    season = season,
                    isAnime = isAnime,
                ) ?: return@withTimeoutOrNull false

                val dataUrl = selectDataUrl(loadResp, mediaType, season, episode)
                    ?: return@withTimeoutOrNull false

                withTimeout(LINKS_TIMEOUT_MS) {
                    provider.loadLinks(
                        data = dataUrl,
                        isCasting = false,
                        subtitleCallback = { sub ->
                            emitSubtitleEvent(requestId, provider.name, sub)
                        },
                        callback = { link ->
                            streamCount++
                            emitStreamEvent(requestId, provider, link)
                        },
                    )
                }
                true
            }

            val elapsedMs = ((System.nanoTime() - startNs) / 1_000_000L).toInt()
            if (result == null) {
                postEvent(
                    mapOf(
                        "requestId" to requestId,
                        "eventType" to "providerError",
                        "providerName" to provider.name,
                        "error" to "Timed out after ${PROVIDER_BUDGET_MS / 1000}s",
                        "elapsedMs" to elapsedMs,
                    ),
                )
            } else {
                postEvent(
                    mapOf(
                        "requestId" to requestId,
                        "eventType" to "providerDone",
                        "providerName" to provider.name,
                        "streamCount" to streamCount,
                        "elapsedMs" to elapsedMs,
                    ),
                )
            }
        } catch (ce: CancellationException) {
            throw ce
        } catch (t: Throwable) {
            val elapsedMs = ((System.nanoTime() - startNs) / 1_000_000L).toInt()
            Log.w(TAG, "Provider ${provider.name} failed", t)
            postEvent(
                mapOf(
                    "requestId" to requestId,
                    "eventType" to "providerError",
                    "providerName" to provider.name,
                    "error" to "${t::class.java.simpleName}: ${t.message ?: "Execution failed"}",
                    "elapsedMs" to elapsedMs,
                ),
            )
        }
    }

    private suspend fun getOrLoadMedia(
        provider: MainAPI,
        mediaType: String,
        title: String,
        originalTitle: String?,
        year: Int?,
        imdbId: String?,
        tmdbId: String?,
        anilistId: String?,
        malId: String?,
        season: Int?,
        isAnime: Boolean,
    ): LoadResponse? {
        val seasonSuffix = if (mediaType != "movie") "::s${season ?: 1}" else ""
        val mediaIdentity = imdbId ?: tmdbId ?: anilistId ?: "$mediaType:${normalize(title)}:$year"
        val cacheKey = "${provider.name}::$mediaIdentity$seasonSuffix"
        val cached = loadCache[cacheKey]
        if (cached != null && System.currentTimeMillis() - cached.storedAtMs < CACHE_TTL_MS) {
            return cached.response
        }

        // 1. Direct Sync-ID fast path when provider advertises sync support
        val syncCandidates = buildList {
            if (!imdbId.isNullOrBlank()) add(SyncIdName.Imdb to imdbId)
            if (!anilistId.isNullOrBlank()) add(SyncIdName.Anilist to anilistId)
            if (!malId.isNullOrBlank()) add(SyncIdName.MyAnimeList to malId)
        }
        for ((syncName, syncVal) in syncCandidates) {
            if (syncName in provider.supportedSyncNames) {
                val url = runCatching {
                    withTimeout(LOAD_TIMEOUT_MS) { provider.getLoadUrl(syncName, syncVal) }
                }.getOrNull()
                if (!url.isNullOrBlank()) {
                    val loaded = runCatching {
                        withTimeout(LOAD_TIMEOUT_MS) { provider.load(url) }
                    }.getOrNull()
                    if (loaded != null) {
                        putLoadCache(cacheKey, loaded)
                        return loaded
                    }
                }
            }
        }

        // 2. Search by primary title (plus season-specific title for multi-season series), fallback to originalTitle
        val queries = buildList {
            if (title.isNotBlank()) {
                add(title)
                if (mediaType != "movie" && season != null && season > 1) {
                    add("$title Season $season")
                }
            }
            if (!originalTitle.isNullOrBlank() && !originalTitle.equals(title, ignoreCase = true)) {
                add(originalTitle)
            }
        }

        var bestHit: SearchResponse? = null
        var bestScore = 0.0
        for (q in queries) {
            val hits = runCatching {
                withTimeout(SEARCH_TIMEOUT_MS) { provider.search(q) }
            }.getOrNull().orEmpty()
            for (hit in hits) {
                val score = scoreSearchResult(
                    queryTitle = title,
                    queryYear = year,
                    mediaType = mediaType,
                    targetSeason = if (mediaType != "movie") season else null,
                    isAnime = isAnime,
                    candidate = hit,
                )
                if (score > bestScore) {
                    bestScore = score
                    bestHit = hit
                }
            }
            if (bestScore >= 0.96) break
        }

        if (bestHit == null || bestScore < MIN_MATCH_SCORE) return null

        val loaded = withTimeout(LOAD_TIMEOUT_MS) { provider.load(bestHit.url) } ?: return null
        // Guard against wrong year matches (e.g. 2012 Jack Reacher vs 2022 Reacher)
        if (year != null && loaded.year != null && abs(loaded.year!! - year) > 2) {
            return null
        }
        putLoadCache(cacheKey, loaded)
        return loaded
    }

    private fun selectDataUrl(
        resp: LoadResponse,
        mediaType: String,
        season: Int?,
        episode: Int?,
    ): String? {
        return when (resp) {
            is MovieLoadResponse -> if (mediaType == "movie") resp.dataUrl else null
            is TorrentLoadResponse -> resp.magnet ?: resp.torrent
            is TvSeriesLoadResponse -> {
                if (mediaType == "movie") null
                else pickEpisode(resp.episodes, season, episode, resp.name)?.data
            }
            is AnimeLoadResponse -> {
                if (mediaType == "movie") return null
                val subbed = resp.episodes[DubStatus.Subbed].orEmpty()
                val dubbed = resp.episodes[DubStatus.Dubbed].orEmpty()
                val none = resp.episodes[DubStatus.None].orEmpty()
                val pool = subbed.ifEmpty { none }.ifEmpty { dubbed }
                pickEpisode(pool, season, episode, resp.name)?.data
            }
            else -> {
                if (mediaType == "movie") {
                    runCatching {
                        resp.javaClass.getMethod("getDataUrl").invoke(resp) as? String
                    }.getOrNull()
                } else {
                    null
                }
            }
        }
    }

    private fun extractSeasonNumber(text: String?): Int? {
        if (text.isNullOrBlank()) return null
        S_E_IN_TEXT.find(text)?.groupValues?.getOrNull(1)?.toIntOrNull()?.let { return it }
        return SEASON_IN_TEXT.find(text)?.groupValues?.getOrNull(1)?.toIntOrNull()
    }

    private fun extractEpisodeNumber(text: String?): Int? {
        if (text.isNullOrBlank()) return null
        S_E_IN_TEXT.find(text)?.groupValues?.getOrNull(2)?.toIntOrNull()?.let { return it }
        return EP_IN_TEXT.find(text)?.groupValues?.getOrNull(1)?.toIntOrNull()
    }

    private fun pickEpisode(
        episodes: List<Episode>,
        targetSeason: Int?,
        targetEpisode: Int?,
        pageTitle: String? = null,
    ): Episode? {
        if (episodes.isEmpty()) return null
        val s = targetSeason ?: 1
        val e = targetEpisode ?: 1

        // Check if the loaded page itself is explicitly scoped to a single season
        // (very common on Indian/Hindi/CS3 sites: "Mirzapur Season 2", "Stranger Things S03").
        val pageSeason = extractSeasonNumber(pageTitle)
        if (pageSeason != null && pageSeason != s) {
            return null
        }

        // Resolve (season, episode) for each episode using structured fields + name parsing fallback.
        val parsed = episodes.map { ep ->
            val inferredS = ep.season?.takeIf { it > 0 } ?: extractSeasonNumber(ep.name)
            val inferredE = ep.episode?.takeIf { it > 0 } ?: extractEpisodeNumber(ep.name)
            ParsedEpisode(ep, inferredS, inferredE)
        }

        // 1. Exact (season, episode) match
        parsed.firstOrNull { it.season == s && it.episode == e }?.let { return it.ep }

        // 2. If page title already explicitly confirmed target season (e.g. "Show Season 3"),
        //    providers often leave ep.season null or 1 on the season-specific page.
        if (pageSeason == s) {
            parsed.firstOrNull { it.episode == e }?.let { return it.ep }
            if (parsed.all { it.episode == null } && e in 1..episodes.size) {
                return episodes[e - 1]
            }
            return null
        }

        // 3. Single-season / flat episode list (no explicit season numbers anywhere on episodes)
        val hasAnySeasonNumber = parsed.any { it.season != null }
        if (!hasAnySeasonNumber) {
            if (s == 1) {
                parsed.firstOrNull { it.episode == e }?.let { return it.ep }
                if (parsed.all { it.episode == null } && e in 1..episodes.size) {
                    return episodes[e - 1]
                }
            }
            // Do NOT guess Season 2+ from an unseasoned flat list unless exact match exists.
            return null
        }

        // 4. Multi-season list where requested season/episode doesn't exist on this provider:
        //    return null instead of playing the wrong season or Episode 1.
        return null
    }

    private fun scoreSearchResult(
        queryTitle: String,
        queryYear: Int?,
        mediaType: String,
        targetSeason: Int?,
        isAnime: Boolean,
        candidate: SearchResponse,
    ): Double {
        val normQ = normalize(queryTitle)
        val normRawC = normalize(candidate.name)
        val normCoreC = normalize(NOISE_TOKENS.replace(candidate.name, " "))
        val normC = normCoreC.ifEmpty { normRawC }
        if (normQ.isEmpty() || normC.isEmpty()) return 0.0

        val qTokens = normQ.split(' ').filter { it.isNotEmpty() }.toSet()
        val cTokens = normC.split(' ').filter { it.isNotEmpty() }.toSet()
        val sharedTokens = qTokens.intersect(cTokens)

        val textScore = when {
            normQ == normC || normQ == normRawC -> 1.0
            // Prevent false matches like "Preacher" matching "Reacher" (zero shared tokens!).
            sharedTokens.isEmpty() -> 0.0
            // For single-word titles like "Reacher" / "Dark" / "From", reject multi-word
            // different titles like "Jack Reacher" unless core title matched exactly above.
            qTokens.size == 1 && cTokens.size > 1 -> 0.40
            else -> {
                val jaccard = tokenJaccard(normQ, normC)
                val lev = levenshteinRatio(normQ, normC)
                val base = if (jaccard >= 0.5) max(jaccard, lev) else jaccard
                val ratio = min(normQ.length, normC.length).toDouble() / max(normQ.length, normC.length).toDouble()
                val qBounded = Regex("""\b${Regex.escape(normQ)}\b""").containsMatchIn(normC)
                val cBounded = Regex("""\b${Regex.escape(normC)}\b""").containsMatchIn(normQ)
                if ((qBounded || cBounded) && ratio >= 0.65 && jaccard >= 0.65) {
                    max(base, 0.85)
                } else {
                    base
                }
            }
        }
        if (textScore < 0.55) return 0.0

        var bonus = 0.0
        val type = candidate.type
        if (type != null) {
            val isMovieCandidate = type == TvType.Movie || type == TvType.AnimeMovie
            val wantsMovie = mediaType == "movie"
            bonus += if (isMovieCandidate == wantsMovie) 0.08 else -0.30
            if (isAnime && (type == TvType.Anime || type == TvType.AnimeMovie)) bonus += 0.05
        }

        // Season affinity for season-split sites ("Show Season 3" vs "Show Season 1")
        if (targetSeason != null) {
            val candSeason = extractSeasonNumber(candidate.name)
            if (candSeason != null) {
                bonus += if (candSeason == targetSeason) 0.12 else -0.45
            }
        }

        // Try extracting trailing 4-digit year if present in candidate title
        if (queryYear != null) {
            val yrMatch = Regex("""\b(19|20)\d{2}\b""").find(candidate.name)?.value?.toIntOrNull()
            if (yrMatch != null) {
                val diff = abs(yrMatch - queryYear)
                bonus += when {
                    diff == 0 -> 0.12
                    diff == 1 -> 0.05
                    diff > 2 -> -0.25
                    else -> 0.0
                }
            }
        }
        return textScore + bonus
    }

    private fun emitStreamEvent(requestId: String, provider: MainAPI, link: ExtractorLink) {
        val allHeaders = runCatching { link.getAllHeaders() }.getOrElse { link.headers }
        postEvent(
            mapOf(
                "requestId" to requestId,
                "eventType" to "stream",
                "providerName" to provider.name,
                "providerLang" to provider.lang,
                "sourcePlugin" to (provider.sourcePlugin ?: provider.name),
                "linkSource" to link.source,
                "linkName" to link.name,
                "url" to link.url,
                "referer" to link.referer,
                "quality" to link.quality,
                "type" to link.type.name,
                "isM3u8" to link.isM3u8,
                "isDash" to link.isDash,
                "headers" to allHeaders,
            ),
        )
    }

    private fun emitSubtitleEvent(requestId: String, providerName: String, sub: SubtitleFile) {
        postEvent(
            mapOf(
                "requestId" to requestId,
                "eventType" to "subtitle",
                "providerName" to providerName,
                "lang" to sub.lang,
                "url" to sub.url,
                "headers" to (sub.headers ?: emptyMap<String, String>()),
            ),
        )
    }

    private fun normalize(input: String): String {
        val decomposed = Normalizer.normalize(input, Normalizer.Form.NFD)
        return decomposed
            .replace(Regex("""\p{InCombiningDiacriticalMarks}+"""), "")
            .lowercase()
            .replace(Regex("""\b(19|20)\d{2}\b"""), " ")
            .replace(Regex("""[^a-z0-9 ]"""), " ")
            .replace(Regex("""\s+"""), " ")
            .trim()
    }

    private fun tokenJaccard(a: String, b: String): Double {
        val ta = a.split(' ').filter { it.isNotEmpty() }.toSet()
        val tb = b.split(' ').filter { it.isNotEmpty() }.toSet()
        if (ta.isEmpty() || tb.isEmpty()) return 0.0
        val inter = ta.intersect(tb).size.toDouble()
        val union = ta.union(tb).size.toDouble()
        return inter / union
    }

    private fun levenshteinRatio(a: String, b: String): Double {
        val maxLen = max(a.length, b.length)
        if (maxLen == 0) return 1.0
        var prev = IntArray(b.length + 1) { it }
        var curr = IntArray(b.length + 1)
        for (i in 1..a.length) {
            curr[0] = i
            for (j in 1..b.length) {
                val cost = if (a[i - 1] == b[j - 1]) 0 else 1
                curr[j] = min(min(curr[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost)
            }
            val tmp = prev
            prev = curr
            curr = tmp
        }
        return 1.0 - (prev[b.length].toDouble() / maxLen.toDouble())
    }
}
