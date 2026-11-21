import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/watch_progress_storage.dart';
import '../../domain/models/watch_progress_models.dart';

String canonicalWatchId({
  String? imdbId,
  int? tmdbId,
  int? anilistId,
  String? rawId,
  required String mediaType,
}) {
  final normType = mediaType == 'tv' ? 'series' : mediaType;
  if (imdbId != null && imdbId.trim().isNotEmpty) {
    return 'imdb:${imdbId.trim()}';
  }
  if (tmdbId != null && tmdbId > 0) {
    return 'tmdb:$normType:$tmdbId';
  }
  if (anilistId != null && anilistId > 0) {
    return 'anilist:$anilistId';
  }
  if (rawId != null && rawId.trim().isNotEmpty) {
    return 'raw:$normType:${rawId.trim()}';
  }
  return 'raw:$normType:unknown';
}

class WatchProgressController extends AsyncNotifier<WatchProgressStoreState> {
  WatchProgressStorage get _storage => ref.read(watchProgressStorageProvider);

  @override
  Future<WatchProgressStoreState> build() async => _storage.load();

  WatchProgressEntry? lookup({
    String? imdbId,
    int? tmdbId,
    int? anilistId,
    String? rawId,
    required String mediaType,
  }) {
    final store = state.valueOrNull;
    if (store == null) return null;
    return store.lookup(
      imdbId: imdbId,
      tmdbId: tmdbId,
      anilistId: anilistId,
      rawId: rawId,
      mediaType: mediaType,
    );
  }

  Future<void> recordProgress({
    required String mediaType,
    required String title,
    String? imdbId,
    int? tmdbId,
    int? anilistId,
    String? rawId,
    bool isAnime = false,
    String? posterUrl,
    String? backdropUrl,
    String? logoUrl,
    double? logoAspectRatio,
    List<String> genres = const [],
    String? imdbRating,
    String? releaseYear,
    int? expectedRuntimeMinutes,
    int? season,
    int? episode,
    required int positionMs,
    required int durationMs,
    bool forceCompleted = false,
    int? nextSeason,
    int? nextEpisode,
    int? nextEpisodeRuntimeMinutes,
    bool seriesCompleted = false,
  }) async {
    final store = state.valueOrNull ?? await _storage.load();
    final normType = mediaType == 'tv' ? 'series' : mediaType;
    final existing = store.lookup(
      imdbId: imdbId,
      tmdbId: tmdbId,
      anilistId: anilistId,
      rawId: rawId,
      mediaType: normType,
    );

    final mergedImdb = (imdbId?.trim().isNotEmpty == true)
        ? imdbId!.trim()
        : existing?.imdbId;
    final mergedTmdb =
        (tmdbId != null && tmdbId > 0) ? tmdbId : existing?.tmdbId;
    final mergedAnilist =
        (anilistId != null && anilistId > 0) ? anilistId : existing?.anilistId;
    final mergedRaw =
        (rawId?.trim().isNotEmpty == true) ? rawId!.trim() : existing?.rawId;
    final mergedIsAnime =
        isAnime || (existing?.isAnime ?? false) || (mergedAnilist != null);
    final mergedPoster =
        (posterUrl?.trim().isNotEmpty == true) ? posterUrl : existing?.posterUrl;
    final mergedBackdrop = (backdropUrl?.trim().isNotEmpty == true)
        ? backdropUrl
        : existing?.backdropUrl;
    final mergedLogo =
        (logoUrl?.trim().isNotEmpty == true) ? logoUrl : existing?.logoUrl;
    final mergedLogoRatio = logoAspectRatio ?? existing?.logoAspectRatio;
    final mergedGenres = genres.isNotEmpty ? genres : (existing?.genres ?? const []);
    final mergedRating =
        (imdbRating?.trim().isNotEmpty == true) ? imdbRating : existing?.imdbRating;
    final mergedYear = (releaseYear?.trim().isNotEmpty == true)
        ? releaseYear
        : existing?.releaseYear;
    final mergedRuntime =
        expectedRuntimeMinutes ?? existing?.expectedRuntimeMinutes;

    final cid = canonicalWatchId(
      imdbId: mergedImdb,
      tmdbId: mergedTmdb,
      anilistId: mergedAnilist,
      rawId: mergedRaw,
      mediaType: normType,
    );

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final isDone = forceCompleted || isPositionCompleted(positionMs, durationMs);
    final nextMap = {...store.entriesById};
    if (existing != null && existing.canonicalId != cid) {
      nextMap.remove(existing.canonicalId);
    }

    if (normType == 'series') {
      final sNum = season ?? existing?.lastWatchedSeason ?? 1;
      final eNum = episode ?? existing?.lastWatchedEpisode ?? 1;
      final epKey = EpisodeProgress.makeKey(sNum, eNum);
      final prevEp = existing?.episodes[epKey];
      final effectiveDur = durationMs > 0 ? durationMs : (prevEp?.durationMs ?? 0);
      final epProg = EpisodeProgress(
        season: sNum,
        episode: eNum,
        positionMs: isDone ? effectiveDur : positionMs,
        durationMs: effectiveDur,
        updatedAtMs: nowMs,
        completed: isDone,
      );
      final nextEpisodes = {
        ...?existing?.episodes,
        epKey: epProg,
      };
      nextMap[cid] = WatchProgressEntry(
        canonicalId: cid,
        mediaType: 'series',
        title: title.isNotEmpty ? title : (existing?.title ?? ''),
        imdbId: mergedImdb,
        tmdbId: mergedTmdb,
        anilistId: mergedAnilist,
        rawId: mergedRaw,
        isAnime: mergedIsAnime,
        posterUrl: mergedPoster,
        backdropUrl: mergedBackdrop,
        logoUrl: mergedLogo,
        logoAspectRatio: mergedLogoRatio,
        genres: mergedGenres,
        imdbRating: mergedRating,
        releaseYear: mergedYear,
        expectedRuntimeMinutes: mergedRuntime,
        updatedAtMs: nowMs,
        lastWatchedSeason: sNum,
        lastWatchedEpisode: eNum,
        nextSeason: isDone ? nextSeason : null,
        nextEpisode: isDone ? nextEpisode : null,
        nextEpisodeRuntimeMinutes: isDone ? nextEpisodeRuntimeMinutes : null,
        seriesCompleted: isDone ? seriesCompleted : false,
        episodes: nextEpisodes,
      );
    } else {
      final effectiveDur =
          durationMs > 0 ? durationMs : (existing?.durationMs ?? 0);
      nextMap[cid] = WatchProgressEntry(
        canonicalId: cid,
        mediaType: 'movie',
        title: title.isNotEmpty ? title : (existing?.title ?? ''),
        imdbId: mergedImdb,
        tmdbId: mergedTmdb,
        anilistId: mergedAnilist,
        rawId: mergedRaw,
        isAnime: mergedIsAnime,
        posterUrl: mergedPoster,
        backdropUrl: mergedBackdrop,
        logoUrl: mergedLogo,
        logoAspectRatio: mergedLogoRatio,
        genres: mergedGenres,
        imdbRating: mergedRating,
        releaseYear: mergedYear,
        expectedRuntimeMinutes: mergedRuntime,
        positionMs: isDone ? effectiveDur : positionMs,
        durationMs: effectiveDur,
        updatedAtMs: nowMs,
        completed: isDone,
      );
    }

    final nextStore = WatchProgressStoreState(entriesById: nextMap);
    state = AsyncData(nextStore);
    await _storage.save(nextStore);
  }

  Future<void> clearProgress(String canonicalId) async {
    final store = state.valueOrNull ?? const WatchProgressStoreState();
    if (!store.entriesById.containsKey(canonicalId)) return;
    final nextMap = {...store.entriesById}..remove(canonicalId);
    final nextStore = WatchProgressStoreState(entriesById: nextMap);
    state = AsyncData(nextStore);
    await _storage.save(nextStore);
  }
}

final watchProgressControllerProvider =
    AsyncNotifierProvider<WatchProgressController, WatchProgressStoreState>(
  WatchProgressController.new,
);
