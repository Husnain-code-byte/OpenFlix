import 'package:equatable/equatable.dart';
import 'package:media_kit/media_kit.dart';

import '../../../addons/domain/models/stream_models.dart';
import '../../../details/data/tmdb_models.dart';
import 'ranked_stream.dart';

enum VideoFitMode {
  fit('Fit'),
  fill('Fill'),
  stretch16x9('16:9');

  const VideoFitMode(this.label);
  final String label;
}

class PlayerAudioOption extends Equatable {
  const PlayerAudioOption({
    required this.track,
    required this.displayLabel,
    this.codecDetail,
    this.normalizedLang,
  });

  final AudioTrack track;
  final String displayLabel;
  final String? codecDetail;
  final String? normalizedLang;

  String get id => track.id;

  @override
  List<Object?> get props => [id, displayLabel, codecDetail, normalizedLang];
}

class PlayerSubtitleOption extends Equatable {
  const PlayerSubtitleOption({
    required this.id,
    required this.displayLabel,
    this.detail,
    this.normalizedLang,
    this.isOff = false,
    this.isExternal = false,
    this.embeddedTrack,
    this.externalSubtitle,
  });

  final String id;
  final String displayLabel;
  final String? detail;
  final String? normalizedLang;
  final bool isOff;
  final bool isExternal;
  final SubtitleTrack? embeddedTrack;
  final ResolvedSubtitle? externalSubtitle;

  @override
  List<Object?> get props => [
        id,
        displayLabel,
        detail,
        normalizedLang,
        isOff,
        isExternal,
      ];
}

class PlaybackLaunchArgs extends Equatable {
  const PlaybackLaunchArgs({
    required this.query,
    this.initialPositionMs = 0,
    this.seasons = const [],
    this.seasonsCache = const {},
    this.posterUrl,
    this.backdropUrl,
    this.logoUrl,
    this.logoAspectRatio,
    this.genres = const [],
    this.imdbRating,
    this.releaseYear,
  });

  final StreamQuery query;
  final int initialPositionMs;
  final List<TmdbSeasonSummary> seasons;
  final Map<int, TmdbSeasonDetails> seasonsCache;
  final String? posterUrl;
  final String? backdropUrl;
  final String? logoUrl;
  final double? logoAspectRatio;
  final List<String> genres;
  final String? imdbRating;
  final String? releaseYear;

  @override
  List<Object?> get props => [
        query,
        initialPositionMs,
        seasons,
        posterUrl,
        backdropUrl,
        logoUrl,
        logoAspectRatio,
        genres,
        imdbRating,
        releaseYear,
      ];
}

class PlayerTimelineState extends Equatable {
  const PlayerTimelineState({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffered = Duration.zero,
  });

  final Duration position;
  final Duration duration;
  final Duration buffered;

  PlayerTimelineState copyWith({
    Duration? position,
    Duration? duration,
    Duration? buffered,
  }) =>
      PlayerTimelineState(
        position: position ?? this.position,
        duration: duration ?? this.duration,
        buffered: buffered ?? this.buffered,
      );

  @override
  List<Object?> get props => [position, duration, buffered];
}

class PlayerUiState extends Equatable {
  const PlayerUiState({
    required this.query,
    this.isInitializing = true,
    this.isResolvingLinks = true,
    this.hasMoreSources = false,
    this.isSwitchingSource = false,
    this.isBuffering = false,
    this.isPlaying = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffered = Duration.zero,
    this.playbackSpeed = 1.0,
    this.fitMode = VideoFitMode.fit,
    this.activeStream,
    this.rankedStreams = const [],
    this.audioOptions = const [],
    this.selectedAudioId,
    this.subtitleOptions = const [],
    this.selectedSubtitleId = 'off',
    this.errorMessage,
    this.statusBanner,
    this.nextEpisodeQuery,
    this.showNextEpisodePrompt = false,
  });

  final StreamQuery query;
  final bool isInitializing;
  final bool isResolvingLinks;
  final bool hasMoreSources;
  final bool isSwitchingSource;
  final bool isBuffering;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final Duration buffered;
  final double playbackSpeed;
  final VideoFitMode fitMode;
  final RankedStream? activeStream;
  final List<RankedStream> rankedStreams;
  final List<PlayerAudioOption> audioOptions;
  final String? selectedAudioId;
  final List<PlayerSubtitleOption> subtitleOptions;
  final String selectedSubtitleId;
  final String? errorMessage;
  final String? statusBanner;
  final StreamQuery? nextEpisodeQuery;
  final bool showNextEpisodePrompt;

  PlayerUiState copyWith({
    StreamQuery? query,
    bool? isInitializing,
    bool? isResolvingLinks,
    bool? hasMoreSources,
    bool? isSwitchingSource,
    bool? isBuffering,
    bool? isPlaying,
    Duration? position,
    Duration? duration,
    Duration? buffered,
    double? playbackSpeed,
    VideoFitMode? fitMode,
    RankedStream? activeStream,
    List<RankedStream>? rankedStreams,
    List<PlayerAudioOption>? audioOptions,
    String? selectedAudioId,
    List<PlayerSubtitleOption>? subtitleOptions,
    String? selectedSubtitleId,
    String? errorMessage,
    bool clearError = false,
    String? statusBanner,
    bool clearStatusBanner = false,
    StreamQuery? nextEpisodeQuery,
    bool clearNextEpisode = false,
    bool? showNextEpisodePrompt,
  }) =>
      PlayerUiState(
        query: query ?? this.query,
        isInitializing: isInitializing ?? this.isInitializing,
        isResolvingLinks: isResolvingLinks ?? this.isResolvingLinks,
        hasMoreSources: hasMoreSources ?? this.hasMoreSources,
        isSwitchingSource: isSwitchingSource ?? this.isSwitchingSource,
        isBuffering: isBuffering ?? this.isBuffering,
        isPlaying: isPlaying ?? this.isPlaying,
        position: position ?? this.position,
        duration: duration ?? this.duration,
        buffered: buffered ?? this.buffered,
        playbackSpeed: playbackSpeed ?? this.playbackSpeed,
        fitMode: fitMode ?? this.fitMode,
        activeStream: activeStream ?? this.activeStream,
        rankedStreams: rankedStreams ?? this.rankedStreams,
        audioOptions: audioOptions ?? this.audioOptions,
        selectedAudioId: selectedAudioId ?? this.selectedAudioId,
        subtitleOptions: subtitleOptions ?? this.subtitleOptions,
        selectedSubtitleId: selectedSubtitleId ?? this.selectedSubtitleId,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
        statusBanner:
            clearStatusBanner ? null : (statusBanner ?? this.statusBanner),
        nextEpisodeQuery: clearNextEpisode
            ? null
            : (nextEpisodeQuery ?? this.nextEpisodeQuery),
        showNextEpisodePrompt:
            showNextEpisodePrompt ?? this.showNextEpisodePrompt,
      );

  @override
  List<Object?> get props => [
        query,
        isInitializing,
        isResolvingLinks,
        hasMoreSources,
        isSwitchingSource,
        isBuffering,
        isPlaying,
        position,
        duration,
        buffered,
        playbackSpeed,
        fitMode,
        activeStream,
        rankedStreams,
        audioOptions,
        selectedAudioId,
        subtitleOptions,
        selectedSubtitleId,
        errorMessage,
        statusBanner,
        nextEpisodeQuery,
        showNextEpisodePrompt,
      ];
}
