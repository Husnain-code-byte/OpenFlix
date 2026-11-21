import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/api_constants.dart';

@immutable
class AnimeIds {
  const AnimeIds({
    this.imdbId,
    this.tmdbId,
    this.malId,
    this.fallbackTvTmdbId,
    this.isMovie = false,
    this.season,
  });

  final String? imdbId;
  final int? tmdbId;
  final int? malId;
  final int? fallbackTvTmdbId;
  final bool isMovie;
  final int? season;
}

class _ParsedFribbData {
  _ParsedFribbData({
    required this.forwardMap,
    required this.reverseMap,
    required this.imdbMap,
  });

  final Map<int, AnimeIds> forwardMap;
  final Map<String, int> reverseMap;
  final Map<String, AnimeIds> imdbMap;
}

_ParsedFribbData _parseFribbFile(String filePath) {
  final rawJson = File(filePath).readAsStringSync();
  return _parseFribbRaw(rawJson);
}

_ParsedFribbData _parseFribbRaw(String rawJson) {
  final forward = <int, AnimeIds>{};
  final reverse = <String, int>{};
  final imdbMap = <String, AnimeIds>{};
  final preferredReverseKeys = <String>{};
  final preferredImdbKeys = <String>{};

  final dynamic decoded = jsonDecode(rawJson);
  if (decoded is! List) {
    return _ParsedFribbData(
      forwardMap: forward,
      reverseMap: reverse,
      imdbMap: imdbMap,
    );
  }

  for (final item in decoded) {
    if (item is! Map<String, dynamic>) continue;
    final anilistId = item['anilist_id'];
    if (anilistId is! int) continue;

    String? imdbId;
    final imdbRaw = item['imdb_id'];
    if (imdbRaw is List && imdbRaw.isNotEmpty && imdbRaw.first is String) {
      final s = (imdbRaw.first as String).trim();
      if (s.isNotEmpty) imdbId = s;
    } else if (imdbRaw is String && imdbRaw.trim().isNotEmpty) {
      imdbId = imdbRaw.trim();
    }
    final cleanImdb = imdbId != null
        ? (imdbId.startsWith('tt') ? imdbId : 'tt$imdbId')
        : null;

    final rawType = (item['type'] as String?)?.toUpperCase();
    int? tmdbId;
    int? fallbackTvTmdbId;
    bool isMovie = rawType == 'MOVIE';
    final tmdbRaw = item['themoviedb_id'];
    if (tmdbRaw is Map) {
      if (tmdbRaw['movie'] is List && (tmdbRaw['movie'] as List).isNotEmpty) {
        final first = (tmdbRaw['movie'] as List).first;
        if (first is num) {
          tmdbId = first.toInt();
          isMovie = true;
        }
      } else if (tmdbRaw['movie'] is num) {
        tmdbId = (tmdbRaw['movie'] as num).toInt();
        isMovie = true;
      } else if (tmdbRaw['tv'] is num) {
        final tvId = (tmdbRaw['tv'] as num).toInt();
        if (rawType == 'MOVIE') {
          // Anime movies mapped under parent TV Season 0 keep isMovie=true
          // so IMDb/title lookup finds the standalone TMDB movie first.
          fallbackTvTmdbId = tvId;
        } else {
          tmdbId = tvId;
          isMovie = false;
        }
      }
    } else if (tmdbRaw is num) {
      tmdbId = tmdbRaw.toInt();
    }

    int? malId;
    final malRaw = item['mal_id'];
    if (malRaw is num && malRaw > 0) {
      malId = malRaw.toInt();
    }

    int? seasonNum;
    final s = item['season'];
    if (s is Map && s['tmdb'] is num) {
      seasonNum = (s['tmdb'] as num).toInt();
    }

    if (cleanImdb != null ||
        tmdbId != null ||
        fallbackTvTmdbId != null ||
        malId != null) {
      final animeIds = AnimeIds(
        imdbId: cleanImdb,
        tmdbId: tmdbId,
        malId: malId,
        fallbackTvTmdbId: fallbackTvTmdbId,
        isMovie: isMovie,
        season: seasonNum,
      );
      forward.putIfAbsent(anilistId, () => animeIds);

      // Prefer main TV Season 1 or Movie entries for reverse lookup so
      // DetailsScreen "Anime Picks" queries the primary AniList entry.
      final isPrimary = isMovie
          ? rawType == 'MOVIE'
          : (rawType == 'TV' && (seasonNum == null || seasonNum == 1));

      void setReverse(String key) {
        if (isPrimary && preferredReverseKeys.add(key)) {
          reverse[key] = anilistId;
        } else {
          reverse.putIfAbsent(key, () => anilistId);
        }
      }

      if (cleanImdb != null) {
        setReverse('imdb:$cleanImdb');
        final existingImdb = imdbMap[cleanImdb];
        if (existingImdb == null ||
            (isPrimary && preferredImdbKeys.add(cleanImdb)) ||
            (existingImdb.tmdbId == null && animeIds.tmdbId != null)) {
          imdbMap[cleanImdb] = animeIds;
        }
      }
      if (tmdbId != null) {
        final kind = isMovie ? 'movie' : 'series';
        setReverse('$kind:$tmdbId');
        if (!isMovie) {
          setReverse('tv:$tmdbId');
        }
      }
    }
  }

  return _ParsedFribbData(
    forwardMap: forward,
    reverseMap: reverse,
    imdbMap: imdbMap,
  );
}

class AnimeIdMap {
  AnimeIdMap({BaseCacheManager? cacheManager}) : _customCacheManager = cacheManager;

  final BaseCacheManager? _customCacheManager;
  late final BaseCacheManager _cacheManager = _customCacheManager ??
      CacheManager(
        Config(
          'anime_id_map_cache',
          stalePeriod: const Duration(days: 7),
          maxNrOfCacheObjects: 2,
        ),
      );
  Map<int, AnimeIds> _forward = {};
  Map<String, int> _reverse = {};
  Map<String, AnimeIds> _imdbToIds = {};
  bool _isLoaded = false;
  Future<void>? _loadingFuture;

  bool get isLoaded => _isLoaded;

  Future<void> ensureLoaded() {
    if (_isLoaded) return Future.value();
    return _loadingFuture ??= _loadInternal().whenComplete(() {
      _loadingFuture = null;
    });
  }

  Future<void> _loadInternal() async {
    // 1. Fast path: load bundled compact asset in ~25ms with zero network wait.
    if (_customCacheManager == null) {
      try {
        final bundledRaw = await rootBundle.loadString('assets/anime_id_map.json');
        if (bundledRaw.isNotEmpty) {
          final parsed = await compute(_parseFribbRaw, bundledRaw);
          _forward = parsed.forwardMap;
          _reverse = parsed.reverseMap;
          _imdbToIds = parsed.imdbMap;
          _isLoaded = true;
          return;
        }
      } catch (_) {
        // Fall through to cache manager if asset bundle is unavailable in unit test.
      }
    }

    // 2. Fallback / custom cache manager path (reads file on worker isolate).
    try {
      final fileInfo = await _cacheManager
          .getFileFromCache(ApiConstants.fribbAnimeListMiniUrl)
          .timeout(const Duration(seconds: 3));
      File? file;
      if (fileInfo != null && await fileInfo.file.exists()) {
        file = fileInfo.file;
      } else {
        final downloaded = await _cacheManager
            .downloadFile(ApiConstants.fribbAnimeListMiniUrl)
            .timeout(const Duration(seconds: 6));
        file = downloaded.file;
      }

      if (await file.exists()) {
        final parsed = await compute(_parseFribbFile, file.path);
        _forward = parsed.forwardMap;
        _reverse = parsed.reverseMap;
        _imdbToIds = parsed.imdbMap;
        _isLoaded = true;
      }
    } catch (_) {
      // Offline fallback: continue with empty map, TMDB fallback resolver will be used.
    }
  }

  @visibleForTesting
  void populate(
    Map<int, AnimeIds> forward,
    Map<String, int> reverse, {
    Map<String, AnimeIds>? imdbToIds,
  }) {
    _forward = Map<int, AnimeIds>.from(forward);
    _reverse = Map<String, int>.from(reverse);
    _imdbToIds = imdbToIds != null
        ? Map<String, AnimeIds>.from(imdbToIds)
        : {
            for (final entry in _forward.values)
              if (entry.imdbId != null && entry.imdbId!.isNotEmpty)
                (entry.imdbId!.startsWith('tt')
                    ? entry.imdbId!
                    : 'tt${entry.imdbId!}'): entry,
          };
    _isLoaded = true;
  }

  /// Registers a runtime-resolved mapping (e.g. from TMDB title fallback search)
  /// without overwriting curated entries already loaded from [anime_id_map.json].
  void registerRuntimeMapping({
    required int anilistId,
    int? tmdbId,
    String? imdbId,
    required bool isMovie,
  }) {
    if (anilistId <= 0) return;
    final cleanImdb = (imdbId != null && imdbId.trim().isNotEmpty)
        ? (imdbId.trim().startsWith('tt') ? imdbId.trim() : 'tt${imdbId.trim()}')
        : null;
    if (cleanImdb == null && (tmdbId == null || tmdbId <= 0)) return;

    final existing = _forward[anilistId];
    if (existing == null) {
      final created = AnimeIds(
        imdbId: cleanImdb,
        tmdbId: tmdbId,
        isMovie: isMovie,
      );
      _forward[anilistId] = created;
      if (cleanImdb != null) {
        _imdbToIds.putIfAbsent(cleanImdb, () => created);
      }
    } else if (existing.tmdbId == null && tmdbId != null && tmdbId > 0) {
      final upgraded = AnimeIds(
        imdbId: existing.imdbId ?? cleanImdb,
        tmdbId: tmdbId,
        malId: existing.malId,
        fallbackTvTmdbId: existing.fallbackTvTmdbId,
        isMovie: isMovie,
        season: existing.season,
      );
      _forward[anilistId] = upgraded;
      final effectiveImdb = upgraded.imdbId;
      if (effectiveImdb != null) {
        _imdbToIds[effectiveImdb] = upgraded;
      }
    }

    if (cleanImdb != null) {
      _reverse.putIfAbsent('imdb:$cleanImdb', () => anilistId);
    }
    if (tmdbId != null && tmdbId > 0) {
      final kind = isMovie ? 'movie' : 'series';
      _reverse.putIfAbsent('$kind:$tmdbId', () => anilistId);
      if (!isMovie) {
        _reverse.putIfAbsent('tv:$tmdbId', () => anilistId);
      }
    }
  }

  AnimeIds? lookupByAnilistId(int anilistId) => _forward[anilistId];

  AnimeIds? lookupByImdbId(String imdbId) {
    final trimmed = imdbId.trim();
    if (trimmed.isEmpty || trimmed.startsWith('anilist:')) return null;
    final clean = trimmed.startsWith('tt') ? trimmed : 'tt$trimmed';
    return _imdbToIds[clean];
  }

  int? lookupAnilistIdByImdb(String imdbId) {
    final trimmed = imdbId.trim();
    if (trimmed.isEmpty || trimmed.startsWith('anilist:')) return null;
    final clean = trimmed.startsWith('tt') ? trimmed : 'tt$trimmed';
    return _reverse['imdb:$clean'];
  }

  int? lookupAnilistIdByTmdb({required int tmdbId, required String type}) {
    final norm = type.toLowerCase() == 'movie' ? 'movie' : 'series';
    if (norm == 'movie') return _reverse['movie:$tmdbId'];
    return _reverse['series:$tmdbId'] ?? _reverse['tv:$tmdbId'];
  }
}

final animeIdMapProvider = Provider<AnimeIdMap>((ref) => AnimeIdMap());
