import 'dart:async';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/perf/image_perf.dart';
import '../../anime/data/anilist_addon_repository.dart';
import '../../anime/data/anime_id_map.dart';
import '../../details/data/tmdb_models.dart';
import '../../details/data/tmdb_repository.dart';
import '../../home/data/models/meta_model.dart';
import 'personalized_slots.dart';
import 'recommendation_scoring_engine.dart';

/// Orchestrates daily source selection, TMDB / AniList recommendation fetching,
/// popularity sorting, cross-row deduplication, and strict Tall/Landscape artwork
/// resolution for personalized rows.
class PersonalizationRepository {
  PersonalizationRepository({
    required TmdbRepository tmdbRepo,
    required AniListAddonRepository aniListRepo,
    required AnimeIdMap animeIdMap,
  })  : _tmdbRepo = tmdbRepo,
        _aniListRepo = aniListRepo,
        _animeIdMap = animeIdMap;

  final TmdbRepository _tmdbRepo;
  final AniListAddonRepository _aniListRepo;
  final AnimeIdMap _animeIdMap;

  // Memoized resolved rows keyed by `"$dateKey|${bucket.key}|${source.id}"`.
  final Map<String, List<MetaModel>> _rowMemo = {};

  static String todayKey([DateTime? now]) {
    final d = (now ?? DateTime.now()).toLocal();
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  /// Ensures local interactions, Likes, My List, and the Anime ID map are loaded.
  Future<void> ensureReady({CancelToken? cancelToken}) async {
    await _tmdbRepo.ensureInteractionsLoaded();
    await _animeIdMap.ensureLoaded();
    if (_tmdbRepo.hasUnresolvedMyListEntries) {
      await _tmdbRepo.syncAndResolveMyList(cancelToken: cancelToken);
    }
    if (_tmdbRepo.hasUnresolvedLikedEntries) {
      await _tmdbRepo.syncAndResolveLikes(cancelToken: cancelToken);
    }
  }

  /// Returns the eligible candidate pool for [bucket], strictly separating Anime
  /// from Movies and TV Shows.
  List<MetaModel> candidatesForBucket(PersonalizationBucket bucket) {
    final sourcePool = bucket.isLikedSource
        ? _tmdbRepo.getCachedLikedMetas()
        : _tmdbRepo.getCachedMyListMetas();

    return sourcePool.where((m) {
      final isAnime = _tmdbRepo.isMetaAnime(m, _animeIdMap);
      if (bucket.isAnime) {
        return isAnime;
      }
      if (isAnime) return false;
      final isSeries = m.type == 'series' || m.type == 'tv';
      return bucket.mediaType == 'series' ? isSeries : !isSeries;
    }).toList(growable: false);
  }

  /// Returns true when two [MetaModel]s represent the same title (even if one
  /// uses a numeric TMDB ID and the other resolved to an IMDb `tt...` ID).
  bool matchesCandidate(MetaModel a, MetaModel b) {
    if (a.id == b.id) return true;
    final normA = a.name.trim().toLowerCase();
    final normB = b.name.trim().toLowerCase();
    if (normA.isEmpty || normA != normB) return false;
    final isSeriesA = a.type == 'series' || a.type == 'tv';
    final isSeriesB = b.type == 'series' || b.type == 'tv';
    return isSeriesA == isSeriesB;
  }

  /// Returns today's persisted daily row snapshot for [bucket] if it was already
  /// locked today (`yyyy-MM-dd`) and has non-empty items.
  ({MetaModel sourceMeta, List<MetaModel> items})? getPersistedDailyRow(
    PersonalizationBucket bucket, {
    DateTime? now,
  }) {
    final today = todayKey(now);
    final snap = _tmdbRepo.getDailyRowSnapshot(bucket.key);
    if (snap == null || snap.dateKey != today || snap.items.isEmpty) {
      return null;
    }
    return (sourceMeta: snap.sourceMeta, items: snap.items);
  }

  /// Persists today's resolved row (`sourceMeta` + exact ordered `items`) to disk
  /// so app restarts never re-fetch or shuffle the row until tomorrow.
  Future<void> saveDailyRow(
    PersonalizationBucket bucket, {
    required MetaModel sourceMeta,
    required List<MetaModel> items,
    DateTime? now,
  }) async {
    if (items.isEmpty) return;
    final today = todayKey(now);
    await _tmdbRepo.setDailyRowSnapshot(
      bucket.key,
      dateKey: today,
      sourceMeta: sourceMeta,
      items: items,
    );
  }

  /// Clears a persisted daily row snapshot (e.g. if the user unliked or removed
  /// today's source title from My List).
  Future<void> clearDailyRow(PersonalizationBucket bucket) =>
      _tmdbRepo.removeDailyRowSnapshot(bucket.key);

  /// Picks or reuses today's stable daily source title for [bucket].
  ///
  /// - Stays locked to the same source all day (`yyyy-MM-dd`).
  /// - Avoids repeating yesterday's source when `> 1` candidate exists.
  /// - Avoids picking the same source as [avoidSourceId] (e.g. when a title is
  ///   both Liked and in My List) when `> 1` candidate exists.
  /// - Immediately picks a new source if the bucket transitions `0 -> 1` mid-day
  ///   or if the previously picked source was unliked / removed from My List.
  Future<MetaModel?> pickDailySource(
    PersonalizationBucket bucket, {
    String? avoidSourceId,
    DateTime? now,
  }) async {
    final candidates = candidatesForBucket(bucket);
    if (candidates.isEmpty) return null;

    final today = todayKey(now);
    final savedMap = _tmdbRepo.getDailyPicksMap();
    final rawEntry = savedMap[bucket.key];

    String? savedDate;
    String? savedId;
    String? prevDayId;
    if (rawEntry != null && rawEntry.isNotEmpty) {
      final parts = rawEntry.split('|');
      if (parts.length >= 2) {
        savedDate = parts[0];
        savedId = parts[1];
        if (parts.length >= 3 && parts[2].isNotEmpty) {
          prevDayId = parts[2];
        }
      }
    }

    // If today's persisted row snapshot already locked a valid candidate (even if
    // its ID normalized between TMDB and IMDb after sync), keep it locked.
    final persistedRow = getPersistedDailyRow(bucket, now: now);
    if (persistedRow != null) {
      final idx = candidates.indexWhere(
        (m) => matchesCandidate(m, persistedRow.sourceMeta),
      );
      if (idx >= 0) {
        final matched = candidates[idx];
        if (avoidSourceId == null ||
            matched.id != avoidSourceId ||
            candidates.length == 1) {
          return matched;
        }
      }
    }

    // If today's pick is still valid in the current candidate pool (and doesn't
    // collide with avoidSourceId when alternatives exist), keep it locked.
    if (savedDate == today && savedId != null) {
      final matchIdx = candidates.indexWhere((m) => m.id == savedId);
      if (matchIdx >= 0) {
        final matched = candidates[matchIdx];
        if (avoidSourceId == null ||
            matched.id != avoidSourceId ||
            candidates.length == 1) {
          return matched;
        }
      }
    }

    final yesterdayId = (savedDate != null && savedDate != today) ? savedId : prevDayId;

    final tasteProfile = _buildTasteProfile(isAnime: bucket.isAnime);
    final chosen = RecommendationScoringEngine.selectSmartDailySeed(
      candidates: candidates,
      tasteProfile: tasteProfile,
      dateKey: today,
      bucketKey: bucket.key,
      yesterdayId: yesterdayId,
      avoidSourceId: avoidSourceId,
    );

    final encoded = '$today|${chosen.id}|${yesterdayId ?? ''}';
    await _tmdbRepo.setDailyPicks({bucket.key: encoded});
    return chosen;
  }

  UserTasteProfile _buildTasteProfile({required bool isAnime}) {
    final liked = _tmdbRepo
        .getCachedLikedMetas()
        .where((m) => _tmdbRepo.isMetaAnime(m, _animeIdMap) == isAnime)
        .toList(growable: false);
    final myList = _tmdbRepo
        .getCachedMyListMetas()
        .where((m) => _tmdbRepo.isMetaAnime(m, _animeIdMap) == isAnime)
        .toList(growable: false);
    final dislikedGenres = _tmdbRepo.getDislikedGenresSnapshot(isAnime: isAnime);
    return UserTasteProfile.fromInteractions(
      likedMetas: liked,
      myListMetas: myList,
      dislikedGenreCounts: dislikedGenres,
      isAnime: isAnime,
    );
  }

  /// Resolves the recommendation items for [bucket] and [sourceMeta], sorted
  /// most-popular-first, with strict Tall or Landscape artwork.
  Future<List<MetaModel>> fetchRecommendationsForSource({
    required PersonalizationBucket bucket,
    required MetaModel sourceMeta,
    required Set<String> seenIds,
    CancelToken? cancelToken,
    void Function(List<MetaModel>)? onWave1Ready,
  }) async {
    final cacheKey = '${todayKey()}|${bucket.key}|${sourceMeta.id}';
    final cached = _rowMemo[cacheKey];
    if (cached != null && cached.isNotEmpty) {
      final deduplicated = cached
          .where((m) => !_tmdbRepo.isMetaDisliked(m) && seenIds.add(m.id))
          .take(PersonalizedSlots.maxRowItems)
          .toList(growable: false);
      if (deduplicated.isNotEmpty) return deduplicated;
    }

    if (bucket.isAnime) {
      final items = await _fetchAnimeRecommendations(
        bucket: bucket,
        sourceMeta: sourceMeta,
        seenIds: seenIds,
        cancelToken: cancelToken,
        onWave1Ready: onWave1Ready,
      );
      if (items.isNotEmpty) _rowMemo[cacheKey] = items;
      return items;
    }

    final items = await _fetchTmdbRecommendations(
      bucket: bucket,
      sourceMeta: sourceMeta,
      seenIds: seenIds,
      cancelToken: cancelToken,
      onWave1Ready: onWave1Ready,
    );
    if (items.isNotEmpty) _rowMemo[cacheKey] = items;
    return items;
  }

  Future<List<MetaModel>> _fetchTmdbRecommendations({
    required PersonalizationBucket bucket,
    required MetaModel sourceMeta,
    required Set<String> seenIds,
    CancelToken? cancelToken,
    void Function(List<MetaModel>)? onWave1Ready,
  }) async {
    final details = await _tmdbRepo.fetchCoreDetails(
      sourceMeta.id,
      type: bucket.mediaType,
      cancelToken: cancelToken,
    );
    if (cancelToken?.isCancelled ?? false) return const [];

    const maxPoolSize = 120;
    final seedYear = int.tryParse(details.releaseYear ?? '');
    final seedGenres = details.genres.isNotEmpty ? details.genres : sourceMeta.genres;
    final seedGenreSet = seedGenres.map((g) => g.toLowerCase()).toSet();
    final tasteProfile = _buildTasteProfile(isAnime: bucket.isAnime);

    bool isEligibleCandidate(TmdbRecommendation rec) {
      if (rec.id == details.tmdbId) return false;
      final candidateMeta = MetaModel(
        id: rec.imdbId ?? '${rec.id}',
        type: rec.mediaType.isNotEmpty ? rec.mediaType : bucket.mediaType,
        name: rec.title,
      );
      if (_tmdbRepo.isMetaDisliked(candidateMeta)) return false;
      if (_tmdbRepo.isMetaLikedOrInMyList(candidateMeta)) return false;
      if (_tmdbRepo.isMetaAnime(candidateMeta, _animeIdMap)) return false;
      return true;
    }

    final candidateMap = <int, CandidateSignalData>{};
    final eligibleHop1 = <TmdbRecommendation>[];

    for (var i = 0; i < details.recommendations.length; i++) {
      final rec = details.recommendations[i];
      if (!isEligibleCandidate(rec)) continue;
      eligibleHop1.add(rec);
      final existing = candidateMap[rec.id];
      if (existing == null) {
        candidateMap[rec.id] = CandidateSignalData(item: rec, hop1Rank: i);
      } else {
        existing.hop1Rank ??= i;
      }
    }

    // Select up to 3 high-quality Hop-1 bridge nodes (matching seed genre & quality
    // gate first) to traverse Hop-2 in parallel.
    final gatedBridges = eligibleHop1
        .where((r) => RecommendationScoringEngine.passesModernOrClassicGate(
              r,
              seedReleaseYear: seedYear,
            ))
        .toList();
    if (seedGenreSet.isNotEmpty && gatedBridges.length > 3) {
      gatedBridges.sort((a, b) {
        final aOverlap = a.genres.any((g) => seedGenreSet.contains(g.toLowerCase())) ? 1 : 0;
        final bOverlap = b.genres.any((g) => seedGenreSet.contains(g.toLowerCase())) ? 1 : 0;
        if (aOverlap != bOverlap) return bOverlap.compareTo(aOverlap);
        return b.popularity.compareTo(a.popularity);
      });
    }
    final bridges = (gatedBridges.isNotEmpty ? gatedBridges : eligibleHop1).take(3).toList();

    final needsPage2 = candidateMap.length < PersonalizedSlots.candidateFetchLimit &&
        details.recommendations.isNotEmpty;
    final hasDiscoverSignals = details.genreIds.isNotEmpty || details.keywordIds.isNotEmpty;

    final page2Future = needsPage2
        ? _tmdbRepo.fetchRecommendationsPage(
            details.tmdbId,
            bucket.mediaType,
            page: 2,
            cancelToken: cancelToken,
          )
        : Future<List<TmdbRecommendation>>.value(const []);

    final hop2Futures = [
      for (final b in bridges)
        _tmdbRepo.fetchRecommendationsPage(
          b.id,
          b.mediaType.isNotEmpty ? b.mediaType : bucket.mediaType,
          page: 1,
          cancelToken: cancelToken,
        ),
    ];

    final discoverFuture = hasDiscoverSignals
        ? _tmdbRepo.fetchDiscoverRecommendations(
            mediaType: bucket.mediaType,
            genreIds: details.genreIds,
            keywordIds: details.keywordIds,
            minReleaseYear: (seedYear != null && seedYear < 2012) ? (seedYear - 5) : 2012,
            excludeAnimation: !bucket.isAnime &&
                !seedGenres.any((g) => g.toLowerCase() == 'animation'),
            originalLanguage: details.originalLanguage,
            cancelToken: cancelToken,
          )
        : Future<List<TmdbRecommendation>>.value(const []);

    final results = await Future.wait<List<TmdbRecommendation>>([
      page2Future,
      discoverFuture,
      ...hop2Futures,
    ]);
    if (cancelToken?.isCancelled ?? false) return const [];

    final page2 = results[0];
    final discoverHits = results[1];
    final hop2Lists = results.sublist(2);

    final page1Offset = details.recommendations.length;
    for (var i = 0; i < page2.length; i++) {
      if (candidateMap.length >= maxPoolSize) break;
      final rec = page2[i];
      if (!isEligibleCandidate(rec)) continue;
      final existing = candidateMap[rec.id];
      if (existing == null) {
        candidateMap[rec.id] = CandidateSignalData(item: rec, hop1Rank: page1Offset + i);
      } else {
        existing.hop1Rank ??= page1Offset + i;
      }
    }

    for (final list in hop2Lists) {
      for (var j = 0; j < list.length; j++) {
        final rec = list[j];
        if (!isEligibleCandidate(rec)) continue;
        final rankScore = 1.0 / (1.0 + j * 0.1);
        final existing = candidateMap[rec.id];
        if (existing == null) {
          if (candidateMap.length >= maxPoolSize) continue;
          candidateMap[rec.id] = CandidateSignalData(
            item: rec,
            hop2BridgeCount: 1,
            hop2BestRankScore: rankScore,
          );
        } else {
          existing.hop2BridgeCount++;
          existing.hop2BestRankScore = math.max(existing.hop2BestRankScore, rankScore);
        }
      }
    }

    for (final rec in discoverHits) {
      if (!isEligibleCandidate(rec)) continue;
      final existing = candidateMap[rec.id];
      if (existing == null) {
        if (candidateMap.length >= maxPoolSize) continue;
        candidateMap[rec.id] = CandidateSignalData(
          item: rec,
          fromDiscover: true,
        );
      } else {
        existing.fromDiscover = true;
      }
    }

    final candidates = RecommendationScoringEngine.rankCandidates(
      candidates: candidateMap.values.toList(growable: false),
      seedTitle: details.title.isNotEmpty ? details.title : sourceMeta.name,
      seedGenres: seedGenres,
      seedReleaseYear: seedYear,
      seedOriginalLanguage: details.originalLanguage,
      seedCollectionId: details.collectionId,
      tasteProfile: tasteProfile,
      limit: PersonalizedSlots.candidateFetchLimit,
    );
    if (candidates.isEmpty) return const [];

    return _resolveArtworkForTmdbCandidates(
      bucket: bucket,
      sourceMeta: sourceMeta,
      candidates: candidates,
      seenIds: seenIds,
      cancelToken: cancelToken,
      onWave1Ready: onWave1Ready,
    );
  }

  Future<List<MetaModel>> _resolveArtworkForTmdbCandidates({
    required PersonalizationBucket bucket,
    required MetaModel sourceMeta,
    required List<TmdbRecommendation> candidates,
    required Set<String> seenIds,
    CancelToken? cancelToken,
    void Function(List<MetaModel>)? onWave1Ready,
  }) async {
    final selected = <TmdbRecommendation>[];
    final localSeen = <String>{};

    for (final c in candidates) {
      if (cancelToken?.isCancelled ?? false) break;
      if (selected.length >= PersonalizedSlots.maxRowItems) break;
      final candidateKey = c.imdbId ?? '${c.id}';
      if (seenIds.contains(candidateKey) || !localSeen.add(candidateKey)) {
        continue;
      }
      selected.add(c);
    }

    if (selected.isEmpty) return const [];

    // Resolve IMDb IDs in parallel so every personalized card gets our
    // Better Posters (`btttr.cc`) style, falling back cleanly to TMDB artwork.
    final resolvedImdbs = await Future.wait<String?>(
      selected.map((c) async {
        final existing = c.imdbId?.trim();
        if (existing != null && existing.isNotEmpty) {
          return existing.startsWith('tt') ? existing : 'tt$existing';
        }
        final normType = c.mediaType.isNotEmpty ? c.mediaType : bucket.mediaType;
        return _tmdbRepo.resolveImdbId(
          c.id,
          mediaType: normType,
          cancelToken: cancelToken,
        );
      }),
    );
    if (cancelToken?.isCancelled ?? false) return const [];

    final orderedMatches = <MetaModel>[];
    for (var i = 0; i < selected.length; i++) {
      final c = selected[i];
      final imdbId = resolvedImdbs[i];
      final normType = c.mediaType.isNotEmpty ? c.mediaType : bucket.mediaType;
      final id = imdbId ?? '${c.id}';
      if (seenIds.contains(id)) continue;

      final rating = c.voteAverage != null && c.voteAverage! > 0
          ? (c.voteAverage! >= 10.0 ? '10' : c.voteAverage!.toStringAsFixed(1))
          : null;
      final styledPoster =
          imdbId != null ? betterPosterUrl(imdbId) : c.posterUrl;
      final genres = c.genres.isNotEmpty ? c.genres : sourceMeta.genres;

      orderedMatches.add(
        MetaModel(
          id: id,
          type: normType,
          name: c.title,
          poster: styledPoster,
          posterFallback: c.posterUrl,
          background: c.backdropUrl ?? c.posterUrl,
          genres: genres,
          imdbRating: rating,
          releaseInfo: c.releaseYear?.toString(),
        ),
      );
    }

    final result = orderedMatches.take(PersonalizedSlots.maxRowItems).toList();
    if (onWave1Ready != null && result.isNotEmpty) {
      onWave1Ready(List<MetaModel>.unmodifiable(result));
    }
    seenIds.addAll(result.map((m) => m.id));
    return result;
  }

  /// Upgrades any [items] missing our Better Posters (`btttr.cc`) poster URL
  /// in place while preserving exact order and fallback artwork.
  Future<List<MetaModel>> ensureStyledPosters(
    List<MetaModel> items, {
    CancelToken? cancelToken,
  }) async {
    if (items.isEmpty) return items;
    await _animeIdMap.ensureLoaded();

    final upgraded = await Future.wait<MetaModel>(
      items.map((item) async {
        if (item.poster != null && item.poster!.contains('btttr.cc')) {
          return item;
        }
        String? imdbId;
        final rawId = item.id.trim();
        if (rawId.startsWith('tt')) {
          imdbId = rawId;
        } else if (rawId.startsWith('anilist:')) {
          final aid = int.tryParse(rawId.substring('anilist:'.length));
          if (aid != null) {
            final ids = _animeIdMap.lookupByAnilistId(aid);
            imdbId = ids?.imdbId;
            if ((imdbId == null || imdbId.isEmpty) &&
                ids?.tmdbId != null &&
                ids!.tmdbId! > 0) {
              imdbId = await _tmdbRepo.resolveImdbId(
                ids.tmdbId!,
                mediaType: ids.isMovie ? 'movie' : 'series',
                cancelToken: cancelToken,
              );
            }
          }
        } else {
          final tmdbId = int.tryParse(rawId);
          if (tmdbId != null && tmdbId > 0) {
            final normType =
                (item.type == 'series' || item.type == 'tv') ? 'series' : 'movie';
            imdbId = await _tmdbRepo.resolveImdbId(
              tmdbId,
              mediaType: normType,
              cancelToken: cancelToken,
            );
          }
        }

        if (imdbId == null || imdbId.isEmpty) return item;
        final cleanImdb = imdbId.startsWith('tt') ? imdbId : 'tt$imdbId';
        return item.copyWith(
          id: rawId.startsWith('anilist:') ? rawId : cleanImdb,
          poster: betterPosterUrl(cleanImdb),
          posterFallback: item.posterFallback ?? item.poster,
        );
      }),
    );

    return upgraded;
  }

  Future<List<MetaModel>> _fetchAnimeRecommendations({
    required PersonalizationBucket bucket,
    required MetaModel sourceMeta,
    required Set<String> seenIds,
    CancelToken? cancelToken,
    void Function(List<MetaModel>)? onWave1Ready,
  }) async {
    var anilistId = _tmdbRepo.resolveAnilistIdForMeta(sourceMeta, _animeIdMap);
    if (anilistId == null) {
      try {
        final details = await _tmdbRepo.fetchCoreDetails(
          sourceMeta.id,
          type: sourceMeta.type,
          cancelToken: cancelToken,
        );
        anilistId = _animeIdMap.lookupAnilistIdByImdb(details.imdbId ?? '') ??
            _animeIdMap.lookupAnilistIdByTmdb(
              tmdbId: details.tmdbId,
              type: details.mediaType,
            );
        if (anilistId != null) {
          _tmdbRepo.markAsAnime(
            tmdbId: details.tmdbId,
            imdbId: details.imdbId,
            mediaType: details.mediaType,
            anilistId: anilistId,
          );
        }
      } catch (_) {}
    }
    if (anilistId == null || (cancelToken?.isCancelled ?? false)) return const [];

    final rawMetas = await _aniListRepo.fetchRecommendations(
      anilistId,
      cancelToken: cancelToken,
    );
    if (cancelToken?.isCancelled ?? false || rawMetas.isEmpty) return const [];

    final filteredRaw = rawMetas.where((m) {
      if (m.id == sourceMeta.id) return false;
      if (_tmdbRepo.isMetaDisliked(m)) return false;
      if (_tmdbRepo.isMetaLikedOrInMyList(m)) return false;
      return true;
    }).toList(growable: false);

    final candidates = RecommendationScoringEngine.rerankAndDeduplicateAnimeMetas(
      candidates: filteredRaw,
      seedTitle: sourceMeta.name,
      tasteProfile: _buildTasteProfile(isAnime: true),
      limit: PersonalizedSlots.candidateFetchLimit,
    );

    if (candidates.isEmpty) return const [];

    final selected = <MetaModel>[];
    for (final item in candidates) {
      if (selected.length >= PersonalizedSlots.maxRowItems) break;
      if (seenIds.contains(item.id)) continue;
      selected.add(item);
    }

    final ordered = await ensureStyledPosters(
      selected,
      cancelToken: cancelToken,
    );
    if (cancelToken?.isCancelled ?? false) return const [];

    if (onWave1Ready != null && ordered.isNotEmpty) {
      onWave1Ready(List<MetaModel>.unmodifiable(ordered));
    }

    seenIds.addAll(ordered.map((m) => m.id));
    return ordered;
  }
}

final personalizationRepositoryProvider = Provider<PersonalizationRepository>((ref) {
  return PersonalizationRepository(
    tmdbRepo: ref.watch(tmdbRepositoryProvider),
    aniListRepo: ref.watch(aniListAddonRepositoryProvider),
    animeIdMap: ref.watch(animeIdMapProvider),
  );
});
