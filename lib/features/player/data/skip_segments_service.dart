import 'dart:collection';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../addons/domain/models/stream_models.dart';
import '../../anime/data/anime_id_map.dart';
import '../domain/models/skip_segment.dart';
import '../presentation/controllers/stream_prefetch_controller.dart';

/// Pure Dart parser for `libmpv`'s `chapter-list` JSON property.
class MpvChapterParser {
  static final _introRegex = RegExp(
    r'^(?:intro(?:\s+(?:credits|theme|song))?|opening(?:\s+(?:credits|theme|song))?|op(?:\s*\d+)?|intro\s*/\s*op|op\s*/\s*intro|title\s+sequence|main\s+titles?|theme(?:\s+song)?)$',
    caseSensitive: false,
  );
  static final _recapRegex = RegExp(
    r'^(?:recap|previously(?:\s+on.*)?|last\s+time(?:\s+on.*)?|prologue\s+recap)$',
    caseSensitive: false,
  );
  static final _outroRegex = RegExp(
    r'^(?:outro(?:\s+(?:credits|theme|song))?|ending(?:\s+(?:credits|theme|song))?|ed(?:\s*\d+)?|outro\s*/\s*ed|ed\s*/\s*outro|credits\s*/\s*ed|end\s+credits|credits|closing(?:\s+(?:credits|theme|song))?)$',
    caseSensitive: false,
  );
  static final _postCreditsRegex = RegExp(
    r'^(?:post[- ]?credits|after[- ]?credits|stinger|epilogue|c[- ]?part|(?:next\s+episode\s+)?preview|next\s+(?:episode|time))$',
    caseSensitive: false,
  );

  /// Parses `chapter-list` JSON (`[{"title":"Opening","time":45.2}, ...]`)
  /// into sanitized [SkipSegment]s using the known video [durationMs].
  static List<SkipSegment> parse(
    String? rawJson, {
    required int durationMs,
  }) {
    if (rawJson == null || rawJson.trim().isEmpty || durationMs <= 0) {
      return const [];
    }
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! List || decoded.isEmpty) return const [];

      final chapters = <_RawChapter>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final timeNum = item['time'];
        if (timeNum is! num) continue;
        final title = (item['title']?.toString() ?? '').trim();
        final startMs = (timeNum.toDouble() * 1000).round();
        if (startMs < 0 || startMs >= durationMs) continue;
        chapters.add(_RawChapter(title: title, startMs: startMs));
      }
      if (chapters.isEmpty) return const [];
      chapters.sort((a, b) => a.startMs.compareTo(b.startMs));

      final results = <SkipSegment>[];
      final seenTypes = <SkipSegmentType>{};

      for (var i = 0; i < chapters.length; i++) {
        final ch = chapters[i];
        final type = classifyTitle(ch.title);
        if (type == null || seenTypes.contains(type)) continue;

        final endMs = i + 1 < chapters.length
            ? chapters[i + 1].startMs
            : durationMs;
        final segLen = endMs - ch.startMs;

        // Guard against mislabeled full-episode acts (<5s or >60% of video).
        if (segLen < 5000 || segLen > (durationMs * 0.60).round()) continue;
        // Intro/Recap must start in the first 45% of the video.
        if ((type == SkipSegmentType.intro || type == SkipSegmentType.recap) &&
            ch.startMs > (durationMs * 0.45).round()) {
          continue;
        }
        // Outro/PostCredits must start in the second half of the video.
        if ((type == SkipSegmentType.outro ||
                type == SkipSegmentType.postCredits) &&
            ch.startMs < (durationMs * 0.50).round()) {
          continue;
        }

        seenTypes.add(type);
        results.add(
          SkipSegment(
            type: type,
            startMs: ch.startMs,
            endMs: endMs,
            source: SkipSegmentSource.embeddedChapters,
            confidence: 1.0,
            label: ch.title,
          ),
        );
      }

      return results;
    } catch (_) {
      return const [];
    }
  }

  @visibleForTesting
  static SkipSegmentType? classifyTitle(String title) {
    final cleaned = title
        .trim()
        .replaceAll(RegExp(r'^[\d\.\-\)\]:\s]+'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return null;
    if (_introRegex.hasMatch(cleaned)) return SkipSegmentType.intro;
    if (_recapRegex.hasMatch(cleaned)) return SkipSegmentType.recap;
    if (_outroRegex.hasMatch(cleaned)) return SkipSegmentType.outro;
    if (_postCreditsRegex.hasMatch(cleaned)) return SkipSegmentType.postCredits;
    return null;
  }
}

class _RawChapter {
  const _RawChapter({required this.title, required this.startMs});
  final String title;
  final int startMs;
}

/// Client for free anonymous IntroDB API (`https://api.introdb.app/segments`).
class IntroDbClient {
  IntroDbClient(this._dio);

  static const _endpoint = 'https://api.introdb.app/segments';
  final Dio _dio;

  Future<List<SkipSegment>> fetchSegments({
    required String imdbId,
    required bool isMovie,
    int? season,
    int? episode,
  }) async {
    final cleanImdb = imdbId.trim().startsWith('tt')
        ? imdbId.trim()
        : 'tt${imdbId.trim()}';
    if (cleanImdb.length < 4) return const [];
    if (!isMovie && (season == null || episode == null)) return const [];

    try {
      final resp = await _dio.get<dynamic>(
        _endpoint,
        queryParameters: isMovie
            ? {'imdb_id': cleanImdb, 'is_movie': 'true'}
            : {'imdb_id': cleanImdb, 'season': season, 'episode': episode},
      );
      final data = resp.data;
      if (data is Map) {
        return parseResponse(Map<String, dynamic>.from(data));
      }
      if (data is String && data.isNotEmpty) {
        final decoded = jsonDecode(data);
        if (decoded is Map) {
          return parseResponse(Map<String, dynamic>.from(decoded));
        }
      }
    } catch (_) {
      // Silent fail: 404 or network issues must never disrupt playback.
    }
    return const [];
  }

  @visibleForTesting
  static List<SkipSegment> parseResponse(Map<String, dynamic> json) {
    final segments = <SkipSegment>[];

    void addIfValid(String key, SkipSegmentType type) {
      final raw = json[key];
      if (raw is! Map) return;
      final map = Map<String, dynamic>.from(raw);
      final startMs = _readMs(map, 'start_ms', 'start_sec');
      final endMs = _readMs(map, 'end_ms', 'end_sec');
      final conf = (map['confidence'] as num?)?.toDouble();
      if (startMs == null || endMs == null) return;
      if (endMs - startMs < 5000) return;
      if (conf != null && conf < 0.45) return;
      segments.add(
        SkipSegment(
          type: type,
          startMs: startMs,
          endMs: endMs,
          source: SkipSegmentSource.introDb,
          confidence: conf,
        ),
      );
    }

    addIfValid('recap', SkipSegmentType.recap);
    addIfValid('intro', SkipSegmentType.intro);
    addIfValid('outro', SkipSegmentType.outro);
    addIfValid('post_credits', SkipSegmentType.postCredits);

    segments.sort((a, b) => a.startMs.compareTo(b.startMs));
    return segments;
  }

  static int? _readMs(Map<String, dynamic> map, String msKey, String secKey) {
    final ms = map[msKey];
    if (ms is num) return ms.round();
    final sec = map[secKey];
    if (sec is num) return (sec.toDouble() * 1000).round();
    return null;
  }
}

/// Client for free anonymous AniSkip v2 API (`https://api.aniskip.com/v2/skip-times`).
class AniSkipClient {
  AniSkipClient(this._dio);

  final Dio _dio;

  Future<List<SkipSegment>> fetchSegments({
    required int malId,
    required int episode,
    int episodeLengthSec = 0,
    int? actualDurationSec,
  }) async {
    if (malId <= 0 || episode <= 0) return const [];
    try {
      final url =
          'https://api.aniskip.com/v2/skip-times/$malId/$episode'
          '?types=op&types=ed&types=mixed-op&types=mixed-ed&types=recap'
          '&episodeLength=${episodeLengthSec > 0 ? episodeLengthSec : 0}';
      final resp = await _dio.get<dynamic>(url);
      final data = resp.data;
      if (data is Map) {
        return parseResponse(
          Map<String, dynamic>.from(data),
          actualDurationSec: actualDurationSec ??
              (episodeLengthSec > 0 ? episodeLengthSec : null),
        );
      }
      if (data is String && data.isNotEmpty) {
        final decoded = jsonDecode(data);
        if (decoded is Map) {
          return parseResponse(
            Map<String, dynamic>.from(decoded),
            actualDurationSec: actualDurationSec ??
                (episodeLengthSec > 0 ? episodeLengthSec : null),
          );
        }
      }
    } catch (_) {
      // Silent fail: 404 when no timestamps exist for this episode.
    }
    return const [];
  }

  @visibleForTesting
  static List<SkipSegment> parseResponse(
    Map<String, dynamic> json, {
    int? actualDurationSec,
  }) {
    if (json['found'] != true) return const [];
    final rawResults = json['results'];
    if (rawResults is! List) return const [];

    final byType = <SkipSegmentType, SkipSegment>{};
    for (final item in rawResults) {
      if (item is! Map) continue;
      final skipType = (item['skipType']?.toString() ?? '').toLowerCase();
      final interval = item['interval'];
      if (interval is! Map) continue;
      final startSec = (interval['startTime'] as num?)?.toDouble();
      final endSec = (interval['endTime'] as num?)?.toDouble();
      if (startSec == null || endSec == null) continue;

      // Reject AniSkip records from a mismatched release cut (e.g. TV vs Blu-ray
      // or different recap/cold-open length) when actual video duration is known.
      final itemEpisodeLen = (item['episodeLength'] as num?)?.toDouble();
      if (actualDurationSec != null &&
          actualDurationSec > 0 &&
          itemEpisodeLen != null &&
          itemEpisodeLen > 0 &&
          (itemEpisodeLen - actualDurationSec).abs() > 15.0) {
        continue;
      }

      final startMs = (startSec * 1000).round();
      final endMs = (endSec * 1000).round();
      if (endMs - startMs < 5000) continue;

      final SkipSegmentType? mapped = switch (skipType) {
        'op' || 'mixed-op' => SkipSegmentType.intro,
        'ed' || 'mixed-ed' => SkipSegmentType.outro,
        'recap' => SkipSegmentType.recap,
        _ => null,
      };
      if (mapped == null) continue;

      // Prefer pure `op`/`ed` over `mixed-op`/`mixed-ed` if both exist.
      final isMixed = skipType.startsWith('mixed-');
      if (!byType.containsKey(mapped) || !isMixed) {
        byType[mapped] = SkipSegment(
          type: mapped,
          startMs: startMs,
          endMs: endMs,
          source: SkipSegmentSource.aniSkip,
          confidence: isMixed ? 0.85 : 1.0,
        );
      }
    }

    final list = byType.values.toList()
      ..sort((a, b) => a.startMs.compareTo(b.startMs));
    return list;
  }
}

/// Multi-source skip segment repository with bounded LRU cache & priority merge.
class SkipSegmentsRepository {
  SkipSegmentsRepository({
    required AnimeIdMap animeIdMap,
    Dio? dio,
  })  : _animeIdMap = animeIdMap,
        _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 3),
                receiveTimeout: const Duration(seconds: 4),
                headers: const {'Accept': 'application/json'},
              ),
            ) {
    _introDb = IntroDbClient(_dio);
    _aniSkip = AniSkipClient(_dio);
  }

  final AnimeIdMap _animeIdMap;
  final Dio _dio;
  late final IntroDbClient _introDb;
  late final AniSkipClient _aniSkip;

  static const int _maxCacheEntries = 40;
  final LinkedHashMap<String, List<SkipSegment>> _cache = LinkedHashMap();
  final Map<int, int?> _anilistToMalCache = {};

  /// Fetches online skip timestamps (IntroDB + AniSkip for anime) with caching.
  Future<List<SkipSegment>> fetchOnlineSegments(
    StreamQuery query, {
    int? durationSec,
  }) async {
    final durBucket = durationSec != null && durationSec > 0
        ? (durationSec ~/ 5) * 5
        : 0;
    final cacheKey = '${prefetchKeyForQuery(query)}|d$durBucket';
    final cached = _cache[cacheKey];
    if (cached != null) {
      // Touch LRU order.
      _cache.remove(cacheKey);
      _cache[cacheKey] = cached;
      return cached;
    }

    final isMovie = query.mediaType == 'movie';
    final imdbId = query.imdbId?.trim();
    final futures = <Future<List<SkipSegment>>>[];

    Future<List<SkipSegment>>? introDbFuture;
    if (imdbId != null && imdbId.isNotEmpty) {
      introDbFuture = _introDb.fetchSegments(
        imdbId: imdbId,
        isMovie: isMovie,
        season: query.season,
        episode: query.episode,
      );
      futures.add(introDbFuture);
    }

    Future<List<SkipSegment>>? aniSkipFuture;
    if (query.isAnime && !isMovie && query.episode != null) {
      aniSkipFuture = _fetchAniSkipForQuery(query, durationSec: durationSec);
      futures.add(aniSkipFuture);
    }

    if (futures.isEmpty) return const [];

    await Future.wait(futures);
    final introDbSegs = introDbFuture != null ? await introDbFuture : const <SkipSegment>[];
    final aniSkipSegs = aniSkipFuture != null ? await aniSkipFuture : const <SkipSegment>[];

    // For anime, AniSkip takes precedence over IntroDB per segment type,
    // while IntroDB fills any missing types (e.g. post_credits or multi-season anime).
    final merged = <SkipSegmentType, SkipSegment>{};
    if (query.isAnime) {
      for (final s in aniSkipSegs) {
        merged.putIfAbsent(s.type, () => s);
      }
      for (final s in introDbSegs) {
        merged.putIfAbsent(s.type, () => s);
      }
    } else {
      for (final s in introDbSegs) {
        merged.putIfAbsent(s.type, () => s);
      }
      for (final s in aniSkipSegs) {
        merged.putIfAbsent(s.type, () => s);
      }
    }

    final result = merged.values.toList()
      ..sort((a, b) => a.startMs.compareTo(b.startMs));

    _putCache(cacheKey, result);
    return result;
  }

  Future<List<SkipSegment>> _fetchAniSkipForQuery(
    StreamQuery query, {
    int? durationSec,
  }) async {
    final malId = await _resolveMalId(query);
    if (malId == null || malId <= 0) return const [];
    final exactDur = durationSec != null && durationSec > 0 ? durationSec : null;
    final expectedSec = exactDur ??
        ((query.expectedRuntimeMinutes ?? 0) > 0
            ? query.expectedRuntimeMinutes! * 60
            : 0);
    // Try with exact video duration first; if AniSkip has no cut matching that
    // length, retry with episodeLength=0 while STILL validating the returned
    // item's episodeLength against exactDur to reject mismatched cuts.
    final first = await _aniSkip.fetchSegments(
      malId: malId,
      episode: query.episode!,
      episodeLengthSec: expectedSec,
      actualDurationSec: exactDur,
    );
    if (first.isNotEmpty || expectedSec == 0) return first;
    return _aniSkip.fetchSegments(
      malId: malId,
      episode: query.episode!,
      episodeLengthSec: 0,
      actualDurationSec: exactDur,
    );
  }

  Future<int?> _resolveMalId(StreamQuery query) async {
    if (query.malId != null && query.malId! > 0) return query.malId;

    await _animeIdMap.ensureLoaded();

    int? anilistId = query.anilistId;
    if (anilistId != null) {
      final ids = _animeIdMap.lookupByAnilistId(anilistId);
      if (ids?.malId != null && ids!.malId! > 0) return ids.malId;
    }

    if (anilistId == null && query.imdbId != null && query.imdbId!.isNotEmpty) {
      final ids = _animeIdMap.lookupByImdbId(query.imdbId!);
      if (ids?.malId != null && ids!.malId! > 0) return ids.malId;
      anilistId = _animeIdMap.lookupAnilistIdByImdb(query.imdbId!);
    }
    if (anilistId == null && query.tmdbId != null && query.tmdbId! > 0) {
      anilistId = _animeIdMap.lookupAnilistIdByTmdb(
        tmdbId: query.tmdbId!,
        type: query.mediaType,
      );
    }

    if (anilistId == null || anilistId <= 0) return null;
    if (_anilistToMalCache.containsKey(anilistId)) {
      return _anilistToMalCache[anilistId];
    }

    // Lightweight 1-field GraphQL lookup on AniList (free, no key) cached in RAM.
    try {
      final resp = await _dio.post<dynamic>(
        'https://graphql.anilist.co',
        data: {
          'query': 'query (\$id: Int) { Media(id: \$id, type: ANIME) { idMal } }',
          'variables': {'id': anilistId},
        },
        options: Options(contentType: Headers.jsonContentType),
      );
      final data = resp.data;
      Object? mal;
      if (data is Map) {
        final innerData = data['data'];
        if (innerData is Map) {
          final media = innerData['Media'];
          if (media is Map) {
            mal = media['idMal'];
          }
        }
      }
      final malInt = (mal is num && mal > 0) ? mal.toInt() : null;
      _anilistToMalCache[anilistId] = malInt;
      return malInt;
    } catch (_) {
      return null;
    }
  }

  void _putCache(String key, List<SkipSegment> value) {
    if (_cache.length >= _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = value;
  }

  /// Merges Tier 1 ([embedded] MKV/MP4 chapters) over Tier 2/3 ([online] APIs)
  /// per [SkipSegmentType], clamping bounds to [durationMs] and discarding
  /// invalid or mismatched-cut segments.
  static List<SkipSegment> mergeAndSanitize({
    required List<SkipSegment> embedded,
    required List<SkipSegment> online,
    required int durationMs,
    bool isAnime = false,
  }) {
    final byType = <SkipSegmentType, SkipSegment>{};

    // Tier 1: Embedded chapters win per type (zero release-cut drift).
    for (final seg in embedded) {
      final clean = _sanitize(seg, durationMs, isAnime: isAnime);
      if (clean != null) {
        byType.putIfAbsent(clean.type, () => clean);
      }
    }

    // Tier 2/3: Online APIs fill any segment types not covered by chapters.
    for (final seg in online) {
      if (byType.containsKey(seg.type)) continue;
      final clean = _sanitize(seg, durationMs, isAnime: isAnime);
      if (clean != null) {
        byType[clean.type] = clean;
      }
    }

    final result = byType.values.toList()
      ..sort((a, b) => a.startMs.compareTo(b.startMs));
    return result;
  }

  static SkipSegment? _sanitize(
    SkipSegment seg,
    int durationMs, {
    required bool isAnime,
  }) {
    var start = seg.startMs < 0 ? 0 : seg.startMs;
    var end = seg.endMs;
    if (durationMs > 0) {
      // Discard segments that start past the actual video end (wrong cut).
      if (start >= durationMs - 2000) return null;
      // If segment end overshoots duration by >25s, likely a different cut.
      if (end > durationMs + 25000) return null;
      if (end > durationMs) end = durationMs;

      final len = end - start;
      // Reject pathological segments covering >60% of total runtime.
      if (len > (durationMs * 0.60).round()) return null;

      // Per-type position & length guardrails to reject bogus/mismatched ranges.
      switch (seg.type) {
        case SkipSegmentType.intro:
          if (start > (durationMs * 0.45).round()) return null;
          final maxIntroMs = isAnime ? 210000 : 300000;
          if (len > maxIntroMs || len > (durationMs * 0.30).round()) return null;
        case SkipSegmentType.recap:
          if (start > (durationMs * 0.35).round()) return null;
          if (len > 300000 || len > (durationMs * 0.30).round()) return null;
        case SkipSegmentType.outro:
          if (start < (durationMs * 0.50).round()) return null;
          final maxOutroMs = isAnime ? 240000 : (durationMs * 0.40).round();
          if (len > maxOutroMs) return null;
        case SkipSegmentType.postCredits:
          if (start < (durationMs * 0.55).round()) return null;
      }
    }
    if (end - start < 5000) return null;
    return seg.copyWith(startMs: start, endMs: end);
  }
}

final skipSegmentsRepositoryProvider = Provider<SkipSegmentsRepository>((ref) {
  final idMap = ref.watch(animeIdMapProvider);
  return SkipSegmentsRepository(animeIdMap: idMap);
});
