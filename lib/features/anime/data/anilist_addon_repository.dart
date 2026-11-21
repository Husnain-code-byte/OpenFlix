import 'dart:async';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/api_constants.dart';
import '../../home/data/models/manifest_model.dart';
import '../../home/data/models/meta_model.dart';
import '../../home/domain/repositories/addon_repository.dart';
import '../../personalization/data/recommendation_scoring_engine.dart';
import 'anilist_models.dart';
import 'anime_resolver.dart';

class _PendingCatalogRequest {
  _PendingCatalogRequest(this.catalog, this.completer, this.cancelToken);
  final CatalogItemModel catalog;
  final Completer<List<MetaModel>> completer;
  final CancelToken? cancelToken;
}

class AniListAddonRepository implements AddonRepository {
  AniListAddonRepository({
    required Dio dio,
    required AnimeResolver resolver,
    DateTime Function()? clock,
  })  : _dio = dio,
        _resolver = resolver,
        _clock = clock;

  final Dio _dio;
  final AnimeResolver _resolver;
  final DateTime Function()? _clock;

  DateTime _now() => (_clock ?? DateTime.now)();

  static const List<String> genres = [
    'Action',
    'Adventure',
    'Comedy',
    'Drama',
    'Ecchi',
    'Fantasy',
    'Horror',
    'Mahou Shoujo',
    'Mecha',
    'Music',
    'Mystery',
    'Psychological',
    'Romance',
    'Sci-Fi',
    'Slice of Life',
    'Sports',
    'Supernatural',
    'Thriller',
  ];

  static const List<String> tags = [
    'Isekai',
    'Time Travel',
    'Reincarnation',
    'Super Power',
    'Magic',
    'School',
    'Military',
    'Mythology',
    'Post-Apocalyptic',
    'Cyberpunk',
    'Martial Arts',
    'Detective',
    'Survival',
    'Space',
    'Samurai',
    'Vampire',
    'Video Games',
    'Coming of Age',
    'Iyashikei',
    'Female Protagonist',
  ];

  DateTime? _cooldownUntil;
  final Map<String, List<MetaModel>> _catalogCache = {};
  final Map<String, Future<List<MetaModel>>> _inflightCatalogs = {};

  final List<_PendingCatalogRequest> _pendingRequests = [];
  Timer? _batchTimer;

  void clearCache() {
    _catalogCache.clear();
  }

  static String _formatDayKey(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static int _dailyHash(String input) {
    var hash = 0x811c9dc5;
    for (var i = 0; i < input.length; i++) {
      hash ^= input.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }

  /// Selects [targetCount] anime from the 50-item popularity-sorted [pool] by
  /// partitioning [pool] into [targetCount] popularity-rank buckets, picking 1 anime
  /// per bucket using [todayKey] while avoiding [yesterdayKey]'s pick in each bucket,
  /// and preserving strict popularity-descending order across the 20 selected items.
  static List<AniListMedia> _selectDailyAnimeCohort({
    required List<AniListMedia> pool,
    required String catalogId,
    required String todayKey,
    required String yesterdayKey,
    int targetCount = 20,
  }) {
    if (pool.length <= targetCount) return List<AniListMedia>.from(pool);

    final selected = <AniListMedia>[];
    final total = pool.length;

    for (var b = 0; b < targetCount; b++) {
      final start = (b * total) ~/ targetCount;
      var end = ((b + 1) * total) ~/ targetCount;
      if (end <= start) end = start + 1;
      if (end > total) end = total;
      final bucketSize = end - start;

      if (bucketSize <= 1) {
        selected.add(pool[start]);
      } else {
        final yIdx = _dailyHash('$yesterdayKey|$catalogId|b:$b') % bucketSize;
        var tIdx = _dailyHash('$todayKey|$catalogId|b:$b') % bucketSize;
        if (tIdx == yIdx) {
          tIdx = (tIdx + 1) % bucketSize;
        }
        selected.add(pool[start + tIdx]);
      }
    }

    selected.sort((a, b) => (b.popularity ?? 0).compareTo(a.popularity ?? 0));
    return selected;
  }

  static final ManifestModel staticManifest = ManifestModel(
    id: 'anilist',
    name: 'AniList',
    version: '1.0.0',
    description: 'Anime discovery powered by AniList',
    types: const ['series', 'movie'],
    catalogs: [
      const CatalogItemModel(
        id: 'anilist.popular',
        type: 'series',
        name: 'Popular Anime',
        showInHome: true,
      ),
      const CatalogItemModel(
        id: 'anilist.airing',
        type: 'series',
        name: 'Airing Now',
        showInHome: true,
      ),
      const CatalogItemModel(
        id: 'anilist.upcoming',
        type: 'series',
        name: 'Upcoming',
        showInHome: true,
      ),
      for (final g in genres)
        CatalogItemModel(
          id: 'anilist.genre.$g',
          type: 'series',
          name: g,
          showInHome: true,
        ),
      for (final t in tags)
        CatalogItemModel(
          id: 'anilist.tag.$t',
          type: 'series',
          name: t,
          showInHome: true,
        ),
      const CatalogItemModel(
        id: 'anilist.search.series',
        type: 'series',
        name: 'AniList',
        extraRequired: ['search'],
        showInHome: false,
      ),
      const CatalogItemModel(
        id: 'anilist.search.movie',
        type: 'movie',
        name: 'AniList',
        extraRequired: ['search'],
        showInHome: false,
      ),
    ],
  );

  @override
  Future<ManifestModel> fetchManifest({CancelToken? cancelToken}) async {
    return staticManifest;
  }

  @override
  Future<List<MetaModel>> fetchCatalog(
    CatalogItemModel catalog, {
    int skip = 0,
    CancelToken? cancelToken,
  }) {
    final now = _now();
    final todayKey = _formatDayKey(now);
    final cacheKey = '$todayKey|${catalog.id}';
    final cached = _catalogCache[cacheKey];
    if (cached != null) return Future.value(cached);

    final inflight = _inflightCatalogs[cacheKey];
    if (inflight != null) return inflight;

    if (_cooldownUntil != null && now.isBefore(_cooldownUntil!)) {
      throw DioException(
        requestOptions: RequestOptions(path: ApiConstants.anilistGraphQLUrl),
        response: Response(
          requestOptions: RequestOptions(path: ApiConstants.anilistGraphQLUrl),
          statusCode: 429,
          statusMessage: 'Rate limited (cooldown active)',
        ),
      );
    }

    final completer = Completer<List<MetaModel>>();
    final future = completer.future.whenComplete(() {
      _inflightCatalogs.remove(cacheKey);
    });
    _inflightCatalogs[cacheKey] = future;

    _pendingRequests.add(_PendingCatalogRequest(catalog, completer, cancelToken));

    if (_pendingRequests.length >= ApiConstants.anilistMaxAliases) {
      _batchTimer?.cancel();
      _batchTimer = null;
      _flushBatch();
    } else {
      _batchTimer ??= Timer(ApiConstants.anilistBatchWindow, _flushBatch);
    }

    return future;
  }

  void _flushBatch() {
    _batchTimer?.cancel();
    _batchTimer = null;

    while (_pendingRequests.isNotEmpty) {
      final count = _pendingRequests.length > ApiConstants.anilistMaxAliases
          ? ApiConstants.anilistMaxAliases
          : _pendingRequests.length;
      final batch = _pendingRequests.sublist(0, count);
      _pendingRequests.removeRange(0, count);
      unawaited(_executeCoalescedBatch(batch));
    }
  }

  Future<void> _executeCoalescedBatch(List<_PendingCatalogRequest> batch) async {
    final varDefs = <String>[];
    final variables = <String, dynamic>{};
    final fragments = <String>[];

    for (var i = 0; i < batch.length; i++) {
      final req = batch[i];
      final catId = req.catalog.id;
      final alias = 'c$i';

      if (catId == 'anilist.popular') {
        fragments.add(
          '$alias: Page(page: 1, perPage: 50) { media(type: ANIME, isAdult: false, status_not: NOT_YET_RELEASED, averageScore_greater: 64, format_in: [TV, TV_SHORT, ONA], sort: [POPULARITY_DESC]) { ...M } }',
        );
      } else if (catId == 'anilist.airing') {
        fragments.add(
          '$alias: Page(page: 1, perPage: 50) { media(type: ANIME, isAdult: false, format_in: [TV, TV_SHORT, ONA], status: RELEASING, sort: [POPULARITY_DESC]) { ...M } }',
        );
      } else if (catId == 'anilist.upcoming') {
        fragments.add(
          '$alias: Page(page: 1, perPage: 50) { media(type: ANIME, isAdult: false, format_in: [TV, TV_SHORT, ONA], status: NOT_YET_RELEASED, sort: [POPULARITY_DESC]) { ...M } }',
        );
      } else if (catId == 'anilist.movie.popular') {
        fragments.add(
          '$alias: Page(page: 1, perPage: 50) { media(type: ANIME, isAdult: false, status_not: NOT_YET_RELEASED, averageScore_greater: 64, format_in: [MOVIE], sort: [POPULARITY_DESC]) { ...M } }',
        );
      } else if (catId == 'anilist.movie.top_rated') {
        fragments.add(
          '$alias: Page(page: 1, perPage: 50) { media(type: ANIME, isAdult: false, status_not: NOT_YET_RELEASED, averageScore_greater: 74, format_in: [MOVIE], sort: [SCORE_DESC, POPULARITY_DESC]) { ...M } }',
        );
      } else if (catId == 'anilist.movie.latest') {
        fragments.add(
          '$alias: Page(page: 1, perPage: 50) { media(type: ANIME, isAdult: false, averageScore_greater: 60, format_in: [MOVIE], status: FINISHED, startDate_greater: 20210101, sort: [POPULARITY_DESC]) { ...M } }',
        );
      } else if (catId.startsWith('anilist.movie.genre.')) {
        final genreName = catId.substring('anilist.movie.genre.'.length);
        final varName = 'g$i';
        varDefs.add('\$$varName: String');
        variables[varName] = genreName;
        fragments.add(
          '$alias: Page(page: 1, perPage: 50) { media(type: ANIME, isAdult: false, status_not: NOT_YET_RELEASED, averageScore_greater: 60, format_in: [MOVIE], sort: [POPULARITY_DESC], genre: \$$varName) { ...M } }',
        );
      } else if (catId.startsWith('anilist.genre.')) {
        final genreName = catId.substring('anilist.genre.'.length);
        final varName = 'g$i';
        varDefs.add('\$$varName: String');
        variables[varName] = genreName;
        fragments.add(
          '$alias: Page(page: 1, perPage: 50) { media(type: ANIME, isAdult: false, status_not: NOT_YET_RELEASED, averageScore_greater: 62, format_in: [TV, TV_SHORT, ONA], sort: [POPULARITY_DESC], genre: \$$varName) { ...M } }',
        );
      } else if (catId.startsWith('anilist.tag.')) {
        final tagName = catId.substring('anilist.tag.'.length);
        final varName = 't$i';
        varDefs.add('\$$varName: String');
        variables[varName] = tagName;
        fragments.add(
          '$alias: Page(page: 1, perPage: 50) { media(type: ANIME, isAdult: false, status_not: NOT_YET_RELEASED, averageScore_greater: 62, format_in: [TV, TV_SHORT, ONA], sort: [POPULARITY_DESC], tag: \$$varName, minimumTagRank: 60) { ...M } }',
        );
      } else {
        fragments.add(
          '$alias: Page(page: 1, perPage: 50) { media(type: ANIME, isAdult: false, status_not: NOT_YET_RELEASED, averageScore_greater: 64, format_in: [TV, TV_SHORT, ONA], sort: [POPULARITY_DESC]) { ...M } }',
        );
      }
    }

    final varHeader = varDefs.isNotEmpty ? '(${varDefs.join(', ')})' : '';
    final query = '''
query $varHeader {
  ${fragments.join('\n  ')}
}
fragment M on Media {
  id
  idMal
  title { romaji english }
  format
  status
  seasonYear
  startDate { year month day }
  genres
  averageScore
  popularity
  isAdult
  coverImage { large }
}
''';

    try {
      final res = await _dio.post<dynamic>(
        ApiConstants.anilistGraphQLUrl,
        data: {
          'query': query,
          'variables': variables,
        },
      );

      final data = res.data;
      if (data is Map<String, dynamic> && data['data'] is Map<String, dynamic>) {
        final dataMap = data['data'] as Map<String, dynamic>;
        await Future.wait([
          for (var i = 0; i < batch.length; i++)
            () async {
              final req = batch[i];
              try {
                final now = _now();
                final alias = 'c$i';
                final section = dataMap[alias];
                final mediaList = <AniListMedia>[];
                if (section is Map<String, dynamic> && section['media'] is List) {
                  for (final m in section['media'] as List) {
                    if (m is Map<String, dynamic>) {
                      final parsed = AniListMedia.tryParse(m);
                      if (parsed != null && parsed.isReleased(now: now)) {
                        mediaList.add(parsed);
                      }
                    }
                  }
                }

                final todayKey = _formatDayKey(now);
                final yesterdayKey = _formatDayKey(now.subtract(const Duration(days: 1)));
                final dailyCohort = _selectDailyAnimeCohort(
                  pool: mediaList,
                  catalogId: req.catalog.id,
                  todayKey: todayKey,
                  yesterdayKey: yesterdayKey,
                  targetCount: 20,
                );

                final resolved = await _resolver.resolveMediaList(
                  dailyCohort,
                  cancelToken: req.cancelToken,
                  now: now,
                );
                _catalogCache['$todayKey|${req.catalog.id}'] = resolved;
                if (!req.completer.isCompleted) {
                  req.completer.complete(resolved);
                }
              } catch (e) {
                if (!req.completer.isCompleted) {
                  req.completer.completeError(e);
                }
              }
            }(),
        ]);
      } else {
        throw const FormatException('Invalid GraphQL response');
      }
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 429) {
        final retryAfter = int.tryParse(e.response?.headers.value('retry-after') ?? '') ?? 60;
        _cooldownUntil = DateTime.now().add(Duration(seconds: retryAfter));
      }
      for (final req in batch) {
        if (!req.completer.isCompleted) {
          req.completer.completeError(e);
        }
      }
    }
  }

  @override
  Future<List<MetaModel>> searchCatalog(
    CatalogItemModel catalog,
    String query, {
    CancelToken? cancelToken,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return const [];

    final isMovie = catalog.type == 'movie';
    final formatFragment = isMovie
        ? 'format: MOVIE'
        : 'format_in: [TV, TV_SHORT, ONA]';

    final gql = '''
query (\$q: String) {
  Page(perPage: 25) {
    media(search: \$q, type: ANIME, isAdult: false, status_not: NOT_YET_RELEASED, $formatFragment, sort: [SEARCH_MATCH]) {
      id
      idMal
      title { romaji english }
      format
      status
      seasonYear
      startDate { year month day }
      genres
      isAdult
      coverImage { large }
    }
  }
}
''';

    try {
      final res = await _dio.post<dynamic>(
        ApiConstants.anilistGraphQLUrl,
        data: {
          'query': gql,
          'variables': {'q': cleanQuery},
        },
        cancelToken: cancelToken,
      );

      final data = res.data;
      final mediaList = <AniListMedia>[];
      if (data is Map<String, dynamic> &&
          data['data'] is Map<String, dynamic> &&
          data['data']['Page'] is Map<String, dynamic> &&
          data['data']['Page']['media'] is List) {
        for (final m in data['data']['Page']['media'] as List) {
          if (m is Map<String, dynamic>) {
            final parsed = AniListMedia.tryParse(m);
            if (parsed != null && parsed.isReleased(now: _now())) mediaList.add(parsed);
          }
        }
      }

      return await _resolver.resolveMediaList(
        mediaList,
        cancelToken: cancelToken,
        now: _now(),
      );
    } catch (e) {
      if (e is DioException && e.response?.statusCode == 429) {
        final retryAfter = int.tryParse(e.response?.headers.value('retry-after') ?? '') ?? 60;
        _cooldownUntil = DateTime.now().add(Duration(seconds: retryAfter));
      }
      return const [];
    }
  }

  /// Fetches 2-hop AniList community recommendations + genre/tag metadata in a
  /// single GraphQL round-trip, applies Modern-First + Classics quality gating,
  /// deduplicates franchises, and ranks candidates before resolving IDs/artwork.
  Future<List<MetaModel>> fetchRecommendations(
    int anilistId, {
    CancelToken? cancelToken,
  }) async {
    const mediaFields = '''
      id
      idMal
      title { romaji english }
      format
      status
      seasonYear
      startDate { year month day }
      genres
      averageScore
      popularity
      isAdult
      bannerImage
      coverImage { extraLarge large }
    ''';

    const gqlTwoHop = '''
query (\$id: Int) {
  Media(id: \$id, type: ANIME) {
    title { romaji english }
    seasonYear
    genres
    tags { name rank isMediaSpoiler }
    recommendations(sort: RATING_DESC, perPage: 20) {
      nodes {
        rating
        mediaRecommendation {
          $mediaFields
          tags { name rank isMediaSpoiler }
          recommendations(sort: RATING_DESC, perPage: 5) {
            nodes {
              rating
              mediaRecommendation {
                $mediaFields
              }
            }
          }
        }
      }
    }
  }
}
''';

    const gqlFallback = '''
query (\$id: Int) {
  Media(id: \$id, type: ANIME) {
    title { romaji english }
    seasonYear
    genres
    tags { name rank isMediaSpoiler }
    recommendations(sort: RATING_DESC, perPage: 25) {
      nodes {
        rating
        mediaRecommendation {
          $mediaFields
          tags { name rank isMediaSpoiler }
        }
      }
    }
  }
}
''';

    try {
      dynamic data;
      try {
        final res = await _dio.post<dynamic>(
          ApiConstants.anilistGraphQLUrl,
          data: {
            'query': gqlTwoHop,
            'variables': {'id': anilistId},
          },
          cancelToken: cancelToken,
        );
        data = res.data;
        if (data is Map<String, dynamic> &&
            data['errors'] != null &&
            data['data']?['Media'] == null) {
          throw const FormatException('Fallback to 1-hop query');
        }
      } catch (e) {
        if (cancelToken?.isCancelled ?? false) return const [];
        final res = await _dio.post<dynamic>(
          ApiConstants.anilistGraphQLUrl,
          data: {
            'query': gqlFallback,
            'variables': {'id': anilistId},
          },
          cancelToken: cancelToken,
        );
        data = res.data;
      }

      if (data is! Map<String, dynamic>) return const [];
      final seedMedia = data['data']?['Media'];
      if (seedMedia is! Map<String, dynamic>) return const [];

      final seedYear = seedMedia['seasonYear'] as int?;
      final seedTitleRaw = seedMedia['title'] is Map<String, dynamic>
          ? (((seedMedia['title']['english'] as String?)?.trim().isNotEmpty ?? false)
              ? (seedMedia['title']['english'] as String)
              : ((seedMedia['title']['romaji'] as String?) ?? ''))
          : '';
      final seedGenres = (seedMedia['genres'] is List)
          ? (seedMedia['genres'] as List)
              .whereType<String>()
              .map((g) => g.toLowerCase())
              .toSet()
          : const <String>{};
      final seedTags = _extractAniListTagNames(seedMedia['tags']);

      final pool = <int, ({
        AniListMedia media,
        int hop1Rating,
        int hop2Bridges,
        int hop2RatingSum,
        Set<String> tags,
      })>{};

      bool isAllowedAnime(AniListMedia m) {
        if (m.id == anilistId || m.isAdult || !m.isReleased(now: _now())) return false;
        return m.format == 'TV' ||
            m.format == 'TV_SHORT' ||
            m.format == 'ONA' ||
            m.format == 'MOVIE';
      }

      final hop1Nodes = seedMedia['recommendations']?['nodes'];
      if (hop1Nodes is List) {
        for (final n in hop1Nodes) {
          if (n is! Map<String, dynamic>) continue;
          final rating = (n['rating'] as num? ?? 0).toInt();
          if (rating <= 0) continue;
          final recJson = n['mediaRecommendation'];
          if (recJson is! Map<String, dynamic>) continue;
          final parsed = AniListMedia.tryParse(recJson);
          if (parsed == null || !isAllowedAnime(parsed)) continue;

          final recTags = _extractAniListTagNames(recJson['tags']);
          final prev = pool[parsed.id];
          pool[parsed.id] = (
            media: parsed,
            hop1Rating: prev == null ? rating : math.max(prev.hop1Rating, rating),
            hop2Bridges: prev?.hop2Bridges ?? 0,
            hop2RatingSum: prev?.hop2RatingSum ?? 0,
            tags: {...?prev?.tags, ...recTags},
          );

          // Collect Hop-2 graph expansions bundled in the same GraphQL payload.
          final hop2Nodes = recJson['recommendations']?['nodes'];
          if (hop2Nodes is List) {
            for (final n2 in hop2Nodes) {
              if (n2 is! Map<String, dynamic>) continue;
              final r2 = (n2['rating'] as num? ?? 0).toInt();
              if (r2 <= 0) continue;
              final rec2Json = n2['mediaRecommendation'];
              if (rec2Json is! Map<String, dynamic>) continue;
              final parsed2 = AniListMedia.tryParse(rec2Json);
              if (parsed2 == null || !isAllowedAnime(parsed2)) continue;
              if (pool.length >= 100 && !pool.containsKey(parsed2.id)) continue;

              final prev2 = pool[parsed2.id];
              pool[parsed2.id] = (
                media: parsed2,
                hop1Rating: prev2?.hop1Rating ?? 0,
                hop2Bridges: (prev2?.hop2Bridges ?? 0) + 1,
                hop2RatingSum: (prev2?.hop2RatingSum ?? 0) + r2,
                tags: prev2?.tags ?? const <String>{},
              );
            }
          }
        }
      }

      if (pool.isEmpty) return const [];

      bool passesAnimeGate(AniListMedia m, {bool relaxed = false}) {
        final avg = m.averageScore ?? 0;
        if (relaxed) return avg >= 60;
        final year = m.seasonYear;
        if (year == null) return avg >= 68;
        if (year >= 2012) return avg >= 65;
        if (avg >= 78 && (m.popularity ?? 0) >= 35000) return true;
        if (seedYear != null &&
            seedYear < 2012 &&
            (year - seedYear).abs() <= 8 &&
            avg >= 72) {
          return true;
        }
        return false;
      }

      var gated = pool.values.where((e) => passesAnimeGate(e.media)).toList();
      if (gated.length < 12) {
        gated = pool.values.where((e) => passesAnimeGate(e.media, relaxed: true)).toList();
      }
      if (gated.isEmpty) gated = pool.values.toList();

      final scored = <({AniListMedia media, double score})>[];
      for (final e in gated) {
        final m = e.media;
        final hop1Norm = e.hop1Rating > 0
            ? (math.log(1 + e.hop1Rating) / math.log(1 + 120)).clamp(0.0, 1.0)
            : 0.0;
        final hop2Boost = e.hop2Bridges > 0
            ? math.min(0.45, e.hop2Bridges * 0.16 +
                (math.log(1 + e.hop2RatingSum) / math.log(1 + 100)) * 0.12)
            : 0.0;
        final graphScore = (0.72 * hop1Norm + hop2Boost).clamp(0.0, 1.0);

        final mGenres = m.genres.map((g) => g.toLowerCase()).toSet();
        final genreOverlap = (seedGenres.isEmpty || mGenres.isEmpty)
            ? 0.45
            : (mGenres.intersection(seedGenres).length /
                    math.max(1, math.min(mGenres.length, seedGenres.length)))
                .clamp(0.0, 1.0);
        final tagOverlap = (seedTags.isEmpty || e.tags.isEmpty)
            ? 0.40
            : (e.tags.intersection(seedTags).length /
                    math.max(1, math.min(e.tags.length, seedTags.length)))
                .clamp(0.0, 1.0);
        final contentScore = (0.60 * genreOverlap + 0.40 * tagOverlap).clamp(0.0, 1.0);

        final scoreNorm = (((m.averageScore ?? 70) - 55.0) / 35.0).clamp(0.0, 1.0);
        final popNorm =
            (math.log(1.0 + math.max(0, m.popularity ?? 0)) / math.log(1.0 + 300000))
                .clamp(0.0, 1.0);
        final year = m.seasonYear;
        final recencyNorm = year == null
            ? 0.65
            : (year >= 2018 ? 0.92 : (year >= 2012 ? 0.75 : 0.60));
        final qualityScore = (0.50 * scoreNorm + 0.30 * recencyNorm + 0.20 * popNorm);

        final total = 0.45 * graphScore + 0.28 * contentScore + 0.27 * qualityScore;
        scored.add((media: m, score: total));
      }

      scored.sort((a, b) {
        final cmp = b.score.compareTo(a.score);
        if (cmp != 0) return cmp;
        return (b.media.popularity ?? 0).compareTo(a.media.popularity ?? 0);
      });

      final seedStem = RecommendationScoringEngine.normalizeFranchiseStem(seedTitleRaw);
      final seenStems = <String>{
        if (seedStem.isNotEmpty && scored.length > 4) seedStem,
      };
      final deduped = <AniListMedia>[];
      for (final entry in scored) {
        final stem = RecommendationScoringEngine.normalizeFranchiseStem(
          entry.media.title.displayTitle,
        );
        if (stem.isNotEmpty && seenStems.contains(stem)) continue;
        if (stem.isNotEmpty) seenStems.add(stem);
        deduped.add(entry.media);
      }

      return await _resolver.resolveMediaList(
        deduped,
        cancelToken: cancelToken,
        now: _now(),
      );
    } catch (_) {
      return const [];
    }
  }

  static Set<String> _extractAniListTagNames(dynamic rawTags) {
    if (rawTags is! List) return const {};
    final out = <String>{};
    for (final t in rawTags) {
      if (t is Map<String, dynamic> && t['isMediaSpoiler'] != true) {
        final rank = (t['rank'] as num?)?.toInt() ?? 0;
        final name = (t['name'] as String?)?.trim().toLowerCase();
        if (name != null && name.isNotEmpty && rank >= 60) {
          out.add(name);
        }
      }
    }
    return out;
  }
}

final aniListDioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    connectTimeout: ApiConstants.connectTimeout,
    receiveTimeout: ApiConstants.receiveTimeout,
    responseType: ResponseType.json,
    headers: const {'Content-Type': 'application/json', 'Accept': 'application/json'},
  ));
  dio.transformer = BackgroundTransformer();
  ref.onDispose(() => dio.close(force: true));
  return dio;
});

final aniListAddonRepositoryProvider = Provider<AniListAddonRepository>((ref) {
  return AniListAddonRepository(
    dio: ref.watch(aniListDioProvider),
    resolver: ref.watch(animeResolverProvider),
  );
});
