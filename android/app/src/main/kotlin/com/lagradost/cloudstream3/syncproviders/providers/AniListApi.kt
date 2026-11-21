package com.lagradost.cloudstream3.syncproviders.providers

import com.fasterxml.jackson.annotation.JsonProperty
import com.lagradost.cloudstream3.syncproviders.SyncAPI

open class AniListApi : SyncAPI {
    override val name: String = "AniList"

    data class Title(
        @JsonProperty("english") val english: String? = null,
        @JsonProperty("romaji") val romaji: String? = null,
        @JsonProperty("native") val native: String? = null,
    ) {
        companion object {
            @JvmField
            val `$stable`: Int = 8
        }
    }

    data class CoverImage(
        @JsonProperty("extraLarge") val extraLarge: String? = null,
        @JsonProperty("large") val large: String? = null,
        @JsonProperty("medium") val medium: String? = null,
    ) {
        companion object {
            @JvmField
            val `$stable`: Int = 8
        }
    }

    data class LikePageInfo(
        @JsonProperty("total") val total: Int? = null,
        @JsonProperty("perPage") val perPage: Int? = null,
        @JsonProperty("currentPage") val currentPage: Int? = null,
        @JsonProperty("lastPage") val lastPage: Int? = null,
        @JsonProperty("hasNextPage") val hasNextPage: Boolean? = null,
    ) {
        companion object {
            @JvmField
            val `$stable`: Int = 8
        }
    }

    data class SeasonNextAiringEpisode(
        @JsonProperty("episode") val episode: Int? = null,
        @JsonProperty("timeUntilAiring") val timeUntilAiring: Int? = null,
    ) {
        companion object {
            @JvmField
            val `$stable`: Int = 8
        }
    }

    data class MediaCoverImage(
        @JsonProperty("extraLarge") val extraLarge: String? = null,
        @JsonProperty("large") val large: String? = null,
        @JsonProperty("medium") val medium: String? = null,
    ) {
        companion object {
            @JvmField
            val `$stable`: Int = 8
        }
    }

    data class MediaTitle(
        @JsonProperty("english") val english: String? = null,
        @JsonProperty("romaji") val romaji: String? = null,
        @JsonProperty("native") val native: String? = null,
    ) {
        companion object {
            @JvmField
            val `$stable`: Int = 8
        }
    }

    data class RecommendedMedia(
        @JsonProperty("id") val id: Int? = null,
        @JsonProperty("title") val title: MediaTitle? = null,
        @JsonProperty("coverImage") val coverImage: MediaCoverImage? = null,
    ) {
        companion object {
            @JvmField
            val `$stable`: Int = 8
        }
    }

    data class Recommendation(
        @JsonProperty("mediaRecommendation") val mediaRecommendation: RecommendedMedia? = null,
    ) {
        companion object {
            @JvmField
            val `$stable`: Int = 8
        }
    }

    data class RecommendationEdge(
        @JsonProperty("node") val node: Recommendation? = null,
    ) {
        companion object {
            @JvmField
            val `$stable`: Int = 8
        }
    }

    data class RecommendationConnection(
        @JsonProperty("edges") val edges: List<RecommendationEdge>? = null,
    ) {
        companion object {
            @JvmField
            val `$stable`: Int = 8
        }
    }
}

open class SimklApi : SyncAPI {
    override val name: String = "Simkl"
}
