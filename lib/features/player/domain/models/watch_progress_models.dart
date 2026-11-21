import 'package:equatable/equatable.dart';

import '../../../details/data/tmdb_models.dart';
import '../../../home/data/models/meta_model.dart';

String formatRemainingTime(int remainingMs) {
  final clamped = remainingMs < 0 ? 0 : remainingMs;
  final totalMin = (clamped / 60000).ceil();
  if (totalMin <= 1) return '<1m left';
  if (totalMin < 60) return '${totalMin}m left';
  final hours = totalMin ~/ 60;
  final mins = totalMin % 60;
  return mins == 0 ? '${hours}h left' : '${hours}h ${mins}m left';
}

bool isPositionCompleted(int positionMs, int durationMs) {
  if (durationMs <= 0) return false;
  final ratio = positionMs / durationMs;
  final remainingMs = durationMs - positionMs;
  return ratio >= 0.90 || (remainingMs <= 45000 && ratio >= 0.80);
}

bool isPositionResumable(int positionMs, int durationMs) {
  if (positionMs <= 0) return false;
  if (isPositionCompleted(positionMs, durationMs)) return false;
  if (positionMs >= 30000) return true;
  if (durationMs > 0 && (positionMs / durationMs) >= 0.02 && positionMs >= 10000) {
    return true;
  }
  return false;
}

class EpisodeProgress extends Equatable {
  const EpisodeProgress({
    required this.season,
    required this.episode,
    required this.positionMs,
    required this.durationMs,
    required this.updatedAtMs,
    this.completed = false,
  });

  final int season;
  final int episode;
  final int positionMs;
  final int durationMs;
  final int updatedAtMs;
  final bool completed;

  String get key => makeKey(season, episode);

  static String makeKey(int season, int episode) => 'S${season}E$episode';

  double get progressFraction {
    if (completed) return 1.0;
    if (durationMs <= 0) return 0.0;
    return (positionMs / durationMs).clamp(0.0, 1.0);
  }

  bool get isResumable =>
      !completed && isPositionResumable(positionMs, durationMs);

  EpisodeProgress copyWith({
    int? positionMs,
    int? durationMs,
    int? updatedAtMs,
    bool? completed,
  }) =>
      EpisodeProgress(
        season: season,
        episode: episode,
        positionMs: positionMs ?? this.positionMs,
        durationMs: durationMs ?? this.durationMs,
        updatedAtMs: updatedAtMs ?? this.updatedAtMs,
        completed: completed ?? this.completed,
      );

  Map<String, dynamic> toJson() => {
        'season': season,
        'episode': episode,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'updatedAtMs': updatedAtMs,
        'completed': completed,
      };

  factory EpisodeProgress.fromJson(Map<String, dynamic> json) =>
      EpisodeProgress(
        season: (json['season'] as num?)?.toInt() ?? 1,
        episode: (json['episode'] as num?)?.toInt() ?? 1,
        positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
        durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
        updatedAtMs: (json['updatedAtMs'] as num?)?.toInt() ?? 0,
        completed: json['completed'] == true,
      );

  @override
  List<Object?> get props => [
        season,
        episode,
        positionMs,
        durationMs,
        updatedAtMs,
        completed,
      ];
}

class WatchProgressEntry extends Equatable {
  const WatchProgressEntry({
    required this.canonicalId,
    required this.mediaType,
    required this.title,
    this.imdbId,
    this.tmdbId,
    this.anilistId,
    this.rawId,
    this.isAnime = false,
    this.posterUrl,
    this.backdropUrl,
    this.logoUrl,
    this.logoAspectRatio,
    this.genres = const [],
    this.imdbRating,
    this.releaseYear,
    this.expectedRuntimeMinutes,
    this.positionMs = 0,
    this.durationMs = 0,
    this.updatedAtMs = 0,
    this.completed = false,
    this.lastWatchedSeason,
    this.lastWatchedEpisode,
    this.nextSeason,
    this.nextEpisode,
    this.nextEpisodeRuntimeMinutes,
    this.seriesCompleted = false,
    this.episodes = const {},
  });

  final String canonicalId;
  final String mediaType; // 'movie' | 'series'
  final String title;
  final String? imdbId;
  final int? tmdbId;
  final int? anilistId;
  final String? rawId;
  final bool isAnime;
  final String? posterUrl;
  final String? backdropUrl;
  final String? logoUrl;
  final double? logoAspectRatio;
  final List<String> genres;
  final String? imdbRating;
  final String? releaseYear;
  final int? expectedRuntimeMinutes;
  final int positionMs;
  final int durationMs;
  final int updatedAtMs;
  final bool completed;
  final int? lastWatchedSeason;
  final int? lastWatchedEpisode;
  final int? nextSeason;
  final int? nextEpisode;
  final int? nextEpisodeRuntimeMinutes;
  final bool seriesCompleted;
  final Map<String, EpisodeProgress> episodes;

  bool get isMovieResumable =>
      mediaType == 'movie' &&
      !completed &&
      isPositionResumable(positionMs, durationMs);

  double get movieProgressFraction {
    if (completed) return 1.0;
    if (durationMs <= 0) return 0.0;
    return (positionMs / durationMs).clamp(0.0, 1.0);
  }

  EpisodeProgress? get latestEpisodeProgress {
    if (lastWatchedSeason != null && lastWatchedEpisode != null) {
      final hit = episodeFor(lastWatchedSeason!, lastWatchedEpisode!);
      if (hit != null) return hit;
    }
    if (episodes.isEmpty) return null;
    final sorted = episodes.values.toList()
      ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
    return sorted.first;
  }

  /// True when this entry should appear in the Continue Watching row.
  bool get isInContinueWatching {
    if (mediaType == 'series') {
      final latest = latestEpisodeProgress;
      if (latest == null) return false;
      if (latest.completed) {
        // Hide series from Continue Watching once its confirmed finale is done.
        return !seriesCompleted;
      }
      return latest.positionMs >= 10000;
    }
    if (completed) return false;
    if (positionMs < 10000) return false;
    if (durationMs > 0 && isPositionCompleted(positionMs, durationMs)) {
      return false;
    }
    return true;
  }

  /// Compact episode code (`"S1E2"`) for series Continue Watching footer; `null` for movies.
  String? get continueWatchingEpisodeBadge {
    if (mediaType != 'series') return null;
    final target = resolveSeriesPlaybackTarget(entry: this);
    return 'S${target.season}E${target.episode}';
  }

  /// Remaining time text (`"34m left"` / `"Up Next"`) for Continue Watching footer.
  String get continueWatchingRemainingLabel {
    if (mediaType == 'series') {
      final target = resolveSeriesPlaybackTarget(entry: this);
      if (target.isResume && target.durationMs > target.resumePositionMs) {
        return formatRemainingTime(target.durationMs - target.resumePositionMs);
      }
      final latest = latestEpisodeProgress;
      if (latest != null &&
          !latest.completed &&
          latest.durationMs > latest.positionMs) {
        return formatRemainingTime(latest.durationMs - latest.positionMs);
      }
      return 'Up Next';
    }
    if (durationMs > positionMs) {
      return formatRemainingTime(durationMs - positionMs);
    }
    return 'Resume';
  }

  /// Progress fraction (`0.0..1.0`) for the white bottom bar on Continue Watching cards.
  double get continueWatchingProgressFraction {
    if (mediaType == 'series') {
      final target = resolveSeriesPlaybackTarget(entry: this);
      if (target.isResume && target.durationMs > 0) {
        return (target.resumePositionMs / target.durationMs).clamp(0.0, 1.0);
      }
      final latest = latestEpisodeProgress;
      if (latest != null && !latest.completed && latest.durationMs > 0) {
        return latest.progressFraction;
      }
      return 0.0;
    }
    return movieProgressFraction;
  }

  /// Converts this watch-progress record to a [MetaModel] for opening Details or cards.
  MetaModel toMetaModel() {
    final resolvedId = (imdbId != null && imdbId!.trim().isNotEmpty)
        ? imdbId!.trim()
        : (tmdbId != null && tmdbId! > 0)
            ? '$tmdbId'
            : (anilistId != null && anilistId! > 0)
                ? 'anilist:$anilistId'
                : (rawId != null && rawId!.trim().isNotEmpty)
                    ? rawId!.trim()
                    : canonicalId;
    return MetaModel(
      id: resolvedId,
      type: mediaType,
      name: title,
      poster: posterUrl,
      posterFallback: posterUrl,
      background: backdropUrl ?? posterUrl,
      landscapePoster: backdropUrl ?? posterUrl,
      logo: logoUrl,
      logoAspectRatio: logoAspectRatio,
      genres: genres,
      imdbRating: imdbRating,
      releaseInfo: releaseYear,
    );
  }

  EpisodeProgress? episodeFor(int season, int episode) =>
      episodes[EpisodeProgress.makeKey(season, episode)];

  List<String> get aliasKeys {
    final keys = <String>[canonicalId];
    if (imdbId != null && imdbId!.trim().isNotEmpty) {
      keys.add('imdb:${imdbId!.trim()}');
    }
    if (tmdbId != null && tmdbId! > 0) {
      keys.add('tmdb:$mediaType:$tmdbId');
    }
    if (anilistId != null && anilistId! > 0) {
      keys.add('anilist:$anilistId');
    }
    if (rawId != null && rawId!.trim().isNotEmpty) {
      keys.add('raw:$mediaType:${rawId!.trim()}');
    }
    return keys.toSet().toList(growable: false);
  }

  WatchProgressEntry copyWith({
    String? canonicalId,
    String? title,
    String? imdbId,
    int? tmdbId,
    int? anilistId,
    String? rawId,
    bool? isAnime,
    String? posterUrl,
    String? backdropUrl,
    String? logoUrl,
    double? logoAspectRatio,
    List<String>? genres,
    String? imdbRating,
    String? releaseYear,
    int? expectedRuntimeMinutes,
    int? positionMs,
    int? durationMs,
    int? updatedAtMs,
    bool? completed,
    int? lastWatchedSeason,
    int? lastWatchedEpisode,
    int? nextSeason,
    int? nextEpisode,
    int? nextEpisodeRuntimeMinutes,
    bool? seriesCompleted,
    Map<String, EpisodeProgress>? episodes,
  }) =>
      WatchProgressEntry(
        canonicalId: canonicalId ?? this.canonicalId,
        mediaType: mediaType,
        title: title ?? this.title,
        imdbId: imdbId ?? this.imdbId,
        tmdbId: tmdbId ?? this.tmdbId,
        anilistId: anilistId ?? this.anilistId,
        rawId: rawId ?? this.rawId,
        isAnime: isAnime ?? this.isAnime,
        posterUrl: posterUrl ?? this.posterUrl,
        backdropUrl: backdropUrl ?? this.backdropUrl,
        logoUrl: logoUrl ?? this.logoUrl,
        logoAspectRatio: logoAspectRatio ?? this.logoAspectRatio,
        genres: genres ?? this.genres,
        imdbRating: imdbRating ?? this.imdbRating,
        releaseYear: releaseYear ?? this.releaseYear,
        expectedRuntimeMinutes:
            expectedRuntimeMinutes ?? this.expectedRuntimeMinutes,
        positionMs: positionMs ?? this.positionMs,
        durationMs: durationMs ?? this.durationMs,
        updatedAtMs: updatedAtMs ?? this.updatedAtMs,
        completed: completed ?? this.completed,
        lastWatchedSeason: lastWatchedSeason ?? this.lastWatchedSeason,
        lastWatchedEpisode: lastWatchedEpisode ?? this.lastWatchedEpisode,
        nextSeason: nextSeason ?? this.nextSeason,
        nextEpisode: nextEpisode ?? this.nextEpisode,
        nextEpisodeRuntimeMinutes:
            nextEpisodeRuntimeMinutes ?? this.nextEpisodeRuntimeMinutes,
        seriesCompleted: seriesCompleted ?? this.seriesCompleted,
        episodes: episodes ?? this.episodes,
      );

  Map<String, dynamic> toJson() => {
        'canonicalId': canonicalId,
        'mediaType': mediaType,
        'title': title,
        'imdbId': imdbId,
        'tmdbId': tmdbId,
        'anilistId': anilistId,
        'rawId': rawId,
        'isAnime': isAnime,
        'posterUrl': posterUrl,
        'backdropUrl': backdropUrl,
        'logoUrl': logoUrl,
        'logoAspectRatio': logoAspectRatio,
        'genres': genres,
        'imdbRating': imdbRating,
        'releaseYear': releaseYear,
        'expectedRuntimeMinutes': expectedRuntimeMinutes,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'updatedAtMs': updatedAtMs,
        'completed': completed,
        'lastWatchedSeason': lastWatchedSeason,
        'lastWatchedEpisode': lastWatchedEpisode,
        'nextSeason': nextSeason,
        'nextEpisode': nextEpisode,
        'nextEpisodeRuntimeMinutes': nextEpisodeRuntimeMinutes,
        'seriesCompleted': seriesCompleted,
        'episodes': {
          for (final e in episodes.entries) e.key: e.value.toJson(),
        },
      };

  factory WatchProgressEntry.fromJson(Map<String, dynamic> json) {
    final rawEpisodes = json['episodes'];
    final epMap = <String, EpisodeProgress>{};
    if (rawEpisodes is Map) {
      rawEpisodes.forEach((k, v) {
        if (v is Map) {
          epMap[k.toString()] =
              EpisodeProgress.fromJson(Map<String, dynamic>.from(v));
        }
      });
    }
    final rawGenres = json['genres'];
    final genresList = rawGenres is List
        ? rawGenres.map((e) => e.toString()).where((s) => s.isNotEmpty).toList()
        : const <String>[];
    return WatchProgressEntry(
      canonicalId: json['canonicalId']?.toString() ?? '',
      mediaType: json['mediaType']?.toString() ?? 'movie',
      title: json['title']?.toString() ?? '',
      imdbId: json['imdbId']?.toString(),
      tmdbId: (json['tmdbId'] as num?)?.toInt(),
      anilistId: (json['anilistId'] as num?)?.toInt(),
      rawId: json['rawId']?.toString(),
      isAnime: json['isAnime'] == true ||
          ((json['anilistId'] as num?)?.toInt() ?? 0) > 0,
      posterUrl: json['posterUrl']?.toString(),
      backdropUrl: json['backdropUrl']?.toString(),
      logoUrl: json['logoUrl']?.toString(),
      logoAspectRatio: (json['logoAspectRatio'] as num?)?.toDouble(),
      genres: genresList,
      imdbRating: json['imdbRating']?.toString(),
      releaseYear: json['releaseYear']?.toString(),
      expectedRuntimeMinutes: (json['expectedRuntimeMinutes'] as num?)?.toInt(),
      positionMs: (json['positionMs'] as num?)?.toInt() ?? 0,
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      updatedAtMs: (json['updatedAtMs'] as num?)?.toInt() ?? 0,
      completed: json['completed'] == true,
      lastWatchedSeason: (json['lastWatchedSeason'] as num?)?.toInt(),
      lastWatchedEpisode: (json['lastWatchedEpisode'] as num?)?.toInt(),
      nextSeason: (json['nextSeason'] as num?)?.toInt(),
      nextEpisode: (json['nextEpisode'] as num?)?.toInt(),
      nextEpisodeRuntimeMinutes:
          (json['nextEpisodeRuntimeMinutes'] as num?)?.toInt(),
      seriesCompleted: json['seriesCompleted'] == true,
      episodes: epMap,
    );
  }

  @override
  List<Object?> get props => [
        canonicalId,
        mediaType,
        title,
        imdbId,
        tmdbId,
        anilistId,
        rawId,
        isAnime,
        posterUrl,
        backdropUrl,
        logoUrl,
        logoAspectRatio,
        genres,
        imdbRating,
        releaseYear,
        expectedRuntimeMinutes,
        positionMs,
        durationMs,
        updatedAtMs,
        completed,
        lastWatchedSeason,
        lastWatchedEpisode,
        nextSeason,
        nextEpisode,
        nextEpisodeRuntimeMinutes,
        seriesCompleted,
        episodes,
      ];
}

class SeriesPlaybackTarget extends Equatable {
  const SeriesPlaybackTarget({
    required this.season,
    required this.episode,
    this.episodeTitle,
    this.resumePositionMs = 0,
    this.durationMs = 0,
    this.isResume = false,
  });

  final int season;
  final int episode;
  final String? episodeTitle;
  final int resumePositionMs;
  final int durationMs;
  final bool isResume;

  String get buttonLabel =>
      isResume ? 'Resume S$season · E$episode' : 'Play S$season · E$episode';

  String? get remainingLabel {
    if (!isResume || durationMs <= resumePositionMs) return null;
    return formatRemainingTime(durationMs - resumePositionMs);
  }

  double? get progressFraction {
    if (!isResume || durationMs <= 0) return null;
    return (resumePositionMs / durationMs).clamp(0.0, 1.0);
  }

  @override
  List<Object?> get props => [
        season,
        episode,
        episodeTitle,
        resumePositionMs,
        durationMs,
        isResume,
      ];
}

/// Computes which Season & Episode should open by default on Details and start
/// when the primary Play/Resume button is tapped.
SeriesPlaybackTarget resolveSeriesPlaybackTarget({
  WatchProgressEntry? entry,
  List<TmdbSeasonSummary> seasons = const [],
  Map<int, TmdbSeasonDetails> seasonsCache = const {},
}) {
  final regularSeasons = seasons.where((s) => s.seasonNumber > 0).toList()
    ..sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));
  final fallbackSeason = regularSeasons.isNotEmpty
      ? regularSeasons.first.seasonNumber
      : (seasons.isNotEmpty ? seasons.first.seasonNumber : 1);

  if (entry == null) {
    final cachedEp = seasonsCache[fallbackSeason]?.episodes.firstOrNull;
    return SeriesPlaybackTarget(
      season: cachedEp?.seasonNumber ?? fallbackSeason,
      episode: cachedEp?.episodeNumber ?? 1,
      episodeTitle: cachedEp?.name,
    );
  }

  var lastS = entry.lastWatchedSeason;
  var lastE = entry.lastWatchedEpisode;
  EpisodeProgress? lastProg = (lastS != null && lastE != null)
      ? entry.episodeFor(lastS, lastE)
      : null;

  if (lastProg == null && entry.episodes.isNotEmpty) {
    final sorted = entry.episodes.values.toList()
      ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
    lastProg = sorted.first;
    lastS = lastProg.season;
    lastE = lastProg.episode;
  }

  if (lastS == null || lastE == null || lastProg == null) {
    return SeriesPlaybackTarget(season: fallbackSeason, episode: 1);
  }

  String? epTitleFor(int s, int e) {
    final cached = seasonsCache[s]?.episodes;
    if (cached == null) return null;
    for (final ep in cached) {
      if (ep.episodeNumber == e) return ep.name;
    }
    return null;
  }

  // Case 1: User stopped mid-episode -> resume that exact episode & open its season.
  if (lastProg.isResumable) {
    return SeriesPlaybackTarget(
      season: lastS,
      episode: lastE,
      episodeTitle: epTitleFor(lastS, lastE),
      resumePositionMs: lastProg.positionMs,
      durationMs: lastProg.durationMs,
      isResume: true,
    );
  }

  // Case 2: Episode completed (>=90%) -> advance to the next released episode.
  if (lastProg.completed ||
      isPositionCompleted(lastProg.positionMs, lastProg.durationMs)) {
    final cachedSeason = seasonsCache[lastS];
    if (cachedSeason != null && cachedSeason.episodes.isNotEmpty) {
      final sortedEps = [...cachedSeason.episodes]
        ..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
      for (final ep in sortedEps) {
        if (ep.episodeNumber > lastE) {
          final existingNext = entry.episodeFor(lastS, ep.episodeNumber);
          return SeriesPlaybackTarget(
            season: lastS,
            episode: ep.episodeNumber,
            episodeTitle: ep.name,
            resumePositionMs:
                existingNext != null && existingNext.isResumable
                    ? existingNext.positionMs
                    : 0,
            durationMs: existingNext?.durationMs ?? 0,
            isResume: existingNext?.isResumable ?? false,
          );
        }
      }
      // Reached end of cached season -> check if next season exists.
      final nextSeason =
          regularSeasons.where((s) => s.seasonNumber > lastS!).firstOrNull;
      if (nextSeason != null) {
        final nextSeasonFirstEp =
            seasonsCache[nextSeason.seasonNumber]?.episodes.firstOrNull;
        final nextEpNum = nextSeasonFirstEp?.episodeNumber ?? 1;
        final existingNext = entry.episodeFor(nextSeason.seasonNumber, nextEpNum);
        return SeriesPlaybackTarget(
          season: nextSeason.seasonNumber,
          episode: nextEpNum,
          episodeTitle: nextSeasonFirstEp?.name,
          resumePositionMs: existingNext != null && existingNext.isResumable
              ? existingNext.positionMs
              : 0,
          durationMs: existingNext?.durationMs ?? 0,
          isResume: existingNext?.isResumable ?? false,
        );
      }
      // Series finale finished -> stay on last watched season, next button replays last ep or E+1.
      return SeriesPlaybackTarget(
        season: lastS,
        episode: lastE,
        episodeTitle: epTitleFor(lastS, lastE),
      );
    }

    // Season details not yet cached -> check summary episode count if known.
    final summary =
        seasons.where((s) => s.seasonNumber == lastS).firstOrNull;
    if (summary != null &&
        summary.episodeCount > 0 &&
        lastE >= summary.episodeCount) {
      final nextSeason =
          regularSeasons.where((s) => s.seasonNumber > lastS!).firstOrNull;
      if (nextSeason != null) {
        return SeriesPlaybackTarget(
          season: nextSeason.seasonNumber,
          episode: 1,
        );
      }
      return SeriesPlaybackTarget(season: lastS, episode: lastE);
    }

    // Use player-resolved exact next episode (handles season boundaries on Home
    // Continue Watching where season lists aren't loaded).
    if (entry.nextSeason != null && entry.nextEpisode != null) {
      final existingNext =
          entry.episodeFor(entry.nextSeason!, entry.nextEpisode!);
      return SeriesPlaybackTarget(
        season: entry.nextSeason!,
        episode: entry.nextEpisode!,
        resumePositionMs: existingNext != null && existingNext.isResumable
            ? existingNext.positionMs
            : 0,
        durationMs: existingNext?.durationMs ??
            ((entry.nextEpisodeRuntimeMinutes ?? 0) * 60000),
        isResume: existingNext?.isResumable ?? false,
      );
    }

    if (entry.seriesCompleted) {
      return SeriesPlaybackTarget(season: lastS, episode: lastE);
    }

    // Default: assume next episode in same season until season list overrides.
    return SeriesPlaybackTarget(season: lastS, episode: lastE + 1);
  }

  // Case 3: User barely started (<30s) -> start cleanly on that season/episode.
  return SeriesPlaybackTarget(
    season: lastS,
    episode: lastE,
    episodeTitle: epTitleFor(lastS, lastE),
  );
}
