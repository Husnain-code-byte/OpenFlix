package com.lagradost.cloudstream3.ui.player

enum class PlayerEventSource {
    UI,
    Sync,
    Player,
}

enum class CSPlayerEvent {
    Pause,
    Play,
    SeekForward,
    SeekBack,
    PlayPauseToggle,
    NextEpisode,
    PrevEpisode,
    Restart,
}

data class SubtitleData(
    val originalName: String = "",
    val name: String = "",
    val url: String = "",
)

interface IPlayer {
    fun isActive(): Boolean
    fun getIsPlaying(): Boolean
    fun getPosition(): Long?
    fun getDuration(): Long?
    fun getCurrentPreferredSubtitle(): SubtitleData?
    fun setPreferredSubtitles(subtitle: SubtitleData?): Boolean
    fun seekTo(ms: Long, source: PlayerEventSource)
    fun handleEvent(event: CSPlayerEvent, source: PlayerEventSource)
}
