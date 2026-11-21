import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/perf/image_perf.dart';
import '../../home/data/models/meta_model.dart';
import 'anilist_models.dart';
import 'anime_id_map.dart';

class AnimeResolver {
  AnimeResolver({
    required AnimeIdMap animeIdMap,
    required Dio tmdbDio,
  })  : _animeIdMap = animeIdMap,
        _tmdbDio = tmdbDio;

  final AnimeIdMap _animeIdMap;
  final Dio _tmdbDio;

  // Memoize TMDB fallback lookups (queryKey -> ({int tmdbId, String? posterUrl}) or null)
  final Map<String, ({int tmdbId, String? posterUrl})?> _tmdbSearchCache = {};
  final Map<String, Future<({int tmdbId, String? posterUrl})?>> _inflightTmdbSearches = {};

  static const int _maxFallbackSearchesPerList = 20;

  static final RegExp _seasonSuffixRe = RegExp(
    r'(?::\s*|\s+)(?:Season\s+\d+|Part\s+\d+|Cour\s+\d+|\d+(?:st|nd|rd|th)\s+Season)\s*$',
    caseSensitive: false,
  );

  String? _fallbackCacheKey(AniListMedia media, {required bool isMovie}) {
    final query = media.title.english ?? media.title.romaji;
    if (query == null || query.trim().isEmpty) return null;
    return '${isMovie ? "m" : "t"}:${query.trim()}:${media.seasonYear ?? 0}';
  }

  Future<List<MetaModel>> resolveMediaList(
    List<AniListMedia> mediaList, {
    CancelToken? cancelToken,
    int maxResults = 25,
    DateTime? now,
  }) async {
    await _animeIdMap.ensureLoaded();

    final results = <MetaModel>[];
    final seenKeys = <String>{};
    var fallbackAttempts = 0;

    for (final media in mediaList) {
      if (results.length >= maxResults) break;
      if (media.isAdult || !media.isReleased(now: now)) continue;

      final ids = _animeIdMap.lookupByAnilistId(media.id);
      String? imdbId = ids?.imdbId;
      int? tmdbId = ids?.tmdbId;
      String? tmdbPosterUrl;
      bool isMovie = ids?.isMovie ?? (media.format == 'MOVIE');

      if (imdbId == null && tmdbId == null) {
        final cacheKey = _fallbackCacheKey(media, isMovie: isMovie);
        final isCached = cacheKey != null && _tmdbSearchCache.containsKey(cacheKey);
        if (isCached || fallbackAttempts < _maxFallbackSearchesPerList) {
          if (!isCached) {
            fallbackAttempts++;
          }
          final hit = await _fallbackTmdbSearch(
            media,
            isMovie: isMovie,
            cancelToken: cancelToken,
          );
          tmdbId = hit?.tmdbId;
          tmdbPosterUrl = hit?.posterUrl;
          if (tmdbId != null) {
            _animeIdMap.registerRuntimeMapping(
              anilistId: media.id,
              tmdbId: tmdbId,
              isMovie: isMovie,
            );
          }
        }
        if (tmdbId == null && ids?.fallbackTvTmdbId != null) {
          tmdbId = ids!.fallbackTvTmdbId;
          isMovie = false;
        }
      }

      if (imdbId == null && tmdbId == null) {
        // Unmapped item cannot be safely displayed in TMDB details screen
        continue;
      }

      final cleanImdb = imdbId != null
          ? (imdbId.startsWith('tt') ? imdbId : 'tt$imdbId')
          : null;
      final key = cleanImdb ?? 'tmdb:$tmdbId';
      if (!seenKeys.add(key)) continue;

      final targetId = cleanImdb ?? '$tmdbId';
      final rating = media.averageScore != null && media.averageScore! > 0
          ? (media.averageScore! >= 100
              ? '10'
              : (media.averageScore! / 10.0).toStringAsFixed(1))
          : null;
      final meta = MetaModel(
        id: targetId,
        type: isMovie ? 'movie' : 'series',
        name: media.title.displayTitle,
        poster: cleanImdb != null ? betterPosterUrl(cleanImdb) : tmdbPosterUrl,
        posterFallback: media.coverLarge ?? tmdbPosterUrl,
        background: media.bannerImage,
        releaseInfo: media.seasonYear?.toString(),
        genres: media.genres,
        imdbRating: rating,
      );
      results.add(meta);
    }

    return results;
  }

  Future<({int tmdbId, String? posterUrl})?> _queryTmdbSearch(
    String query, {
    required bool isMovie,
    int? year,
    CancelToken? cancelToken,
  }) async {
    final endpoint = isMovie ? '/search/movie' : '/search/tv';
    final queryParams = <String, dynamic>{
      'api_key': ApiConstants.tmdbApiKey,
      'query': query,
      'include_adult': false,
    };
    if (year != null) {
      queryParams[isMovie ? 'year' : 'first_air_date_year'] = year;
    }

    final res = await _tmdbDio.get<dynamic>(
      '${ApiConstants.tmdbBaseUrl}$endpoint',
      queryParameters: queryParams,
      cancelToken: cancelToken,
    );

    final data = res.data;
    if (data is! Map<String, dynamic>) return null;
    final results = data['results'];
    if (results is! List || results.isEmpty) return null;

    Map<String, dynamic>? chosen;
    for (final item in results) {
      if (item is! Map<String, dynamic> || item['id'] is! num) continue;
      final genres = item['genre_ids'];
      if (genres is List && genres.contains(16)) {
        chosen = item;
        break;
      }
      chosen ??= item;
    }
    if (chosen == null) return null;

    final id = (chosen['id'] as num).toInt();
    final posterPath = chosen['poster_path'];
    final posterUrl = (posterPath is String && posterPath.isNotEmpty)
        ? '${ApiConstants.tmdbImageUrl}/w500$posterPath'
        : null;
    return (tmdbId: id, posterUrl: posterUrl);
  }

  Future<({int tmdbId, String? posterUrl})?> _fallbackTmdbSearch(
    AniListMedia media, {
    required bool isMovie,
    CancelToken? cancelToken,
  }) {
    final query = media.title.english ?? media.title.romaji;
    if (query == null || query.trim().isEmpty) return Future.value(null);

    final cleanQuery = query.trim();
    final cacheKey = '${isMovie ? "m" : "t"}:$cleanQuery:${media.seasonYear ?? 0}';
    if (_tmdbSearchCache.containsKey(cacheKey)) {
      return Future.value(_tmdbSearchCache[cacheKey]);
    }

    return _inflightTmdbSearches.putIfAbsent(cacheKey, () async {
      try {
        // 1. Primary title with year constraint.
        var hit = await _queryTmdbSearch(
          cleanQuery,
          isMovie: isMovie,
          year: media.seasonYear,
          cancelToken: cancelToken,
        );

        // 2. Retry stripped season/part suffix without year constraint.
        if (hit == null) {
          final stripped = cleanQuery.replaceAll(_seasonSuffixRe, '').trim();
          if (stripped.isNotEmpty && (stripped != cleanQuery || media.seasonYear != null)) {
            hit = await _queryTmdbSearch(
              stripped,
              isMovie: isMovie,
              cancelToken: cancelToken,
            );
          }
        }

        // 3. Retry romaji title without year constraint if distinct.
        final romaji = media.title.romaji?.trim();
        if (hit == null && romaji != null && romaji.isNotEmpty && romaji != cleanQuery) {
          final strippedRomaji = romaji.replaceAll(_seasonSuffixRe, '').trim();
          hit = await _queryTmdbSearch(
            strippedRomaji.isNotEmpty ? strippedRomaji : romaji,
            isMovie: isMovie,
            cancelToken: cancelToken,
          );
        }

        _tmdbSearchCache[cacheKey] = hit;
        return hit;
      } catch (_) {
        return null;
      } finally {
        _inflightTmdbSearches.remove(cacheKey);
      }
    });
  }
}

final animeResolverProvider = Provider<AnimeResolver>((ref) {
  final idMap = ref.watch(animeIdMapProvider);
  final dio = Dio(BaseOptions(
    connectTimeout: ApiConstants.connectTimeout,
    receiveTimeout: ApiConstants.receiveTimeout,
    responseType: ResponseType.json,
  ));
  dio.transformer = BackgroundTransformer();
  ref.onDispose(() => dio.close(force: true));
  return AnimeResolver(animeIdMap: idMap, tmdbDio: dio);
});
