import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/perf/image_perf.dart';
import '../../anime/data/anime_id_map.dart';
import '../../collections/data/collection_models.dart';
import '../../home/data/models/manifest_model.dart';
import '../../home/data/models/meta_model.dart';
import 'tmdb_models.dart';

typedef PersonalizedArtwork = ({
  String? tallPosterUrl,
  String? standardPosterUrl,
  String? landscapeBackdropUrl,
  String? logoUrl,
  double? logoAspectRatio,
  String? ageRating,
  String? notchText,
});

class TmdbException implements Exception {
  const TmdbException(
    this.message, {
    this.statusCode,
    this.dioType,
    this.cause,
  });
  final String message;
  final int? statusCode;
  final DioExceptionType? dioType;
  final Object? cause;

  @override
  String toString() => message;
}

/// Number of cards visible in a horizontal [PosterRow] plus its 2-card
/// `cacheExtent` (393dp viewport / 121dp stride + 2 ≈ 6 cards).
const int kViewportPriorityCount = 6;

/// Maximum concurrent `/external_ids` requests in background Wave 2 to prevent
/// saturating the host socket pool.
const int kMaxBackgroundConcurrency = 8;

/// Duration after a confirmed TMDB `POST`/`DELETE` during which stale `GET`
/// account snapshots or `/account_states` responses cannot erase that write.
const Duration kTmdbWriteConfirmationWindow = Duration(minutes: 3);

/// Resolves Stremio `tt…` or TMDB numeric IDs into Movie and Series metadata.
///
/// Architecture:
/// 1. **Bidirectional ID Cache**: Maps `imdbId <-> (tmdbId, mediaType)` so
///    navigating to any related/recommended item skips `/find/{imdb}` completely.
/// 2. **Two-Phase Non-Blocking Pipeline**:
///    - [fetchCoreDetails]: Resolves primary metadata, backdrop, logo, cast,
///      seasons, bundled Season 1 episodes, and initial related lists in 1–2 RTTs
///      without waiting for secondary `/external_ids` lookups.
///    - [enrichExternalIds]: Resolves `btttr.cc` IMDb IDs in two prioritized,
///      deduplicated waves (Wave 1: the 6 mounted viewport cards per row;
///      Wave 2: off-screen rail cards in bounded batches of 8).
/// 3. **Series Contract**: Supports `/tv/{id}` metadata, seasons summaries,
///    inline `season/1` bundling, and memoized per-season episode fetching via
///    [fetchSeasonDetails].
class TmdbRepository {
  TmdbRepository(
    this._dio, {
    File? interactionsFileOverride,
    AnimeIdMap? animeIdMap,
    DateTime Function()? clock,
    bool enableRetryTimer = false,
  })  : _interactionsFileOverride = interactionsFileOverride,
        _animeIdMap = animeIdMap,
        _clock = clock,
        _enableRetryTimer = enableRetryTimer;

  final Dio _dio;
  final File? _interactionsFileOverride;
  final AnimeIdMap? _animeIdMap;
  final DateTime Function()? _clock;
  final bool _enableRetryTimer;

  int _nowMs() => (_clock ?? DateTime.now)().millisecondsSinceEpoch;

  /// Current wall-clock time (injectable in tests for deterministic release-day checks).
  DateTime get currentNow => (_clock ?? DateTime.now)();

  // Session caches for full, core, season, and movie collection payloads.
  final Map<String, TmdbMovieDetails> _memo = {};
  final Map<String, TmdbMovieDetails> _coreMemo = {};
  final Map<String, TmdbSeasonDetails> _seasonMemo = {};
  final Map<int, List<TmdbRecommendation>> _movieCollectionMemo = {};

  // In-flight request deduplication maps.
  final Map<String, Future<TmdbMovieDetails>> _inflight = {};
  final Map<String, Future<TmdbMovieDetails>> _inflightCore = {};
  final Map<String, Future<TmdbSeasonDetails>> _inflightSeasons = {};
  final Map<int, Future<List<TmdbRecommendation>>> _inflightMovieCollections = {};
  final Map<String, Future<String?>> _inflightExternalIds = {};

  // Bidirectional ID caches: eliminates redundant `/find/tt...` round-trips
  // when opening a recommended or similar title.
  final Map<String, String> _tmdbToImdbCache = {};
  final Map<String, ({int tmdbId, String mediaType})> _imdbToTmdbCache = {};

  // User interactions: personal TMDB ratings (0.5..10.0), Likes, "My List" state,
  // anime classification keys, daily personalization picks, and pending TMDB writes,
  // persisted to disk.
  static const String _interactionsCacheKey = 'openflix_user_interactions_v1';
  final Map<String, double> _ratingsCache = {};
  final Set<String> _myListCache = {};
  final List<MetaModel> _myListMetas = [];
  final List<MetaModel> _likedMetas = [];
  final Set<String> _animeKeys = {};
  final Map<String, int> _keyToAnilistCache = {};
  final Map<int, ({int tmdbId, String mediaType})> _anilistToTmdbCache = {};
  final Map<String, String> _dailyPicksCache = {};
  final Map<String, ({String dateKey, MetaModel sourceMeta, List<MetaModel> items})>
      _dailyRowsCache = {};
  final Map<String, bool> _pendingWatchlistOps = {};
  final Map<String, double> _pendingRatingOps = {};
  final Map<String, ({bool value, int updatedAtMs})> _recentWatchlistMutations = {};
  final Map<String, ({double value, int updatedAtMs})> _recentRatingMutations = {};
  final Map<String, PersonalizedArtwork> _personalizedArtworkCache = {};
  final Map<String, Future<PersonalizedArtwork>> _inflightPersonalizedArtwork = {};
  List<CatalogItemModel>? _categoryCatalogsCache;
  final Map<String, List<MetaModel>> _categoryCatalogItemsCache = {};
  final Map<String, Future<List<MetaModel>>> _inflightCategoryCatalogs = {};
  final Map<String, List<MetaModel>> _standardCatalogItemsCache = {};
  final Map<String, Future<List<MetaModel>>> _inflightStandardCatalogs = {};
  final Map<String, List<MetaModel>> _collectionCatalogItemsCache = {};
  final Map<String, Future<List<MetaModel>>> _inflightCollectionCatalogs = {};
  final Set<void Function()> _myListListeners = {};
  String? _userSessionId;
  TmdbAccountProfile? _accountProfile;
  int? _lastSyncedAccountId;
  bool _needsLocalPush = false;
  bool _sessionExpired = false;
  bool _lastSyncSucceeded = true;
  String? _lastSyncError;
  DateTime? _lastSuccessfulSyncAt;
  String? _resolvedAndroidFilesDir;
  Future<void>? _loadInteractionsFuture;
  bool _interactionsLoaded = false;
  Future<void>? _inflightSync;
  Future<void> _writeQueue = Future<void>.value();
  int _persistSeq = 0;
  int _persistVersion = 0;
  Timer? _pendingFlushTimer;
  int _pendingFlushAttempts = 0;
  bool _disposed = false;

  /// Whether the user has connected their personal TMDB account (`session_id`).
  bool get isAuthenticated =>
      _userSessionId != null && _userSessionId!.trim().isNotEmpty;

  /// The active TMDB v3 user `session_id`, if authenticated.
  String? get userSessionId => _userSessionId;

  /// The authenticated TMDB user's profile (`id`, `username`, `name`, `avatarUrl`).
  TmdbAccountProfile? get accountProfile => _accountProfile;

  /// Whether the most recent account sync completed cleanly without errors.
  bool get lastSyncSucceeded => _lastSyncSucceeded;

  /// Error message from the most recent failed TMDB sync/write, if any.
  String? get lastSyncError => _lastSyncError;

  /// Timestamp of the last completed TMDB account sync.
  DateTime? get lastSuccessfulSyncAt => _lastSuccessfulSyncAt;

  /// Number of Watchlist / Rating writes waiting to be flushed to TMDB.
  int get pendingSyncCount =>
      _pendingWatchlistOps.length + _pendingRatingOps.length;

  /// True when local mutations have not yet been confirmed on TMDB.
  bool get hasPendingSyncOps =>
      _pendingWatchlistOps.isNotEmpty ||
      _pendingRatingOps.isNotEmpty ||
      _needsLocalPush;

  /// True when TMDB returned HTTP 401 (`session_id` expired or revoked).
  bool get isSessionExpired => _sessionExpired;

  /// Cancels any scheduled background flush timer when the repository is disposed.
  void dispose() {
    _disposed = true;
    _pendingFlushTimer?.cancel();
    _pendingFlushTimer = null;
  }

  /// Waits for all queued interaction persistence writes to finish (for tests).
  Future<void> flushDiskWritesForTesting() => _writeQueue;

  void addMyListListener(void Function() listener) => _myListListeners.add(listener);

  void removeMyListListener(void Function() listener) => _myListListeners.remove(listener);

  void _notifyMyListListeners() {
    for (final listener in List<void Function()>.from(_myListListeners)) {
      listener();
    }
  }

  /// Synchronously returns the currently resolved [MetaModel] items in "My List".
  List<MetaModel> getCachedMyListMetas() => List<MetaModel>.unmodifiable(_myListMetas);

  /// Synchronously returns the currently resolved [MetaModel] items that the user liked (`rating >= 5.0`).
  List<MetaModel> getCachedLikedMetas() => List<MetaModel>.unmodifiable(_likedMetas);

  /// Synchronously returns the persisted daily personalization picks map.
  Map<String, String> getDailyPicksMap() => Map<String, String>.unmodifiable(_dailyPicksCache);

  /// Updates a daily personalization pick entry and persists it to disk.
  Future<void> setDailyPicks(Map<String, String> updates) async {
    await ensureInteractionsLoaded();
    _dailyPicksCache.addAll(updates);
    await _persistInteractionsToDisk();
  }

  /// Returns today's persisted daily personalized row snapshot for [bucketKey], if any.
  ({String dateKey, MetaModel sourceMeta, List<MetaModel> items})? getDailyRowSnapshot(
    String bucketKey,
  ) =>
      _dailyRowsCache[bucketKey];

  /// Persists the complete daily personalized row (`dateKey`, `sourceMeta`, and exact
  /// ordered `items`) atomically to disk so rows never shuffle across app restarts
  /// until the calendar date rolls over.
  Future<void> setDailyRowSnapshot(
    String bucketKey, {
    required String dateKey,
    required MetaModel sourceMeta,
    required List<MetaModel> items,
  }) async {
    await ensureInteractionsLoaded();
    _dailyRowsCache[bucketKey] = (
      dateKey: dateKey,
      sourceMeta: sourceMeta,
      items: List<MetaModel>.unmodifiable(items),
    );
    await _persistInteractionsToDisk();
  }

  /// Removes a persisted daily personalized row snapshot (e.g. when its source was removed).
  Future<void> removeDailyRowSnapshot(String bucketKey) async {
    await ensureInteractionsLoaded();
    if (_dailyRowsCache.remove(bucketKey) != null) {
      await _persistInteractionsToDisk();
    }
  }

  /// True when [_myListCache] has saved ID keys that have not yet been resolved
  /// into [_myListMetas].
  bool get hasUnresolvedMyListEntries {
    if (_myListCache.isEmpty) return false;
    final covered = <String>{
      for (final m in _myListMetas) ..._keysForMeta(m),
    };
    return _myListCache.any((k) => !covered.contains(k));
  }

  /// True when [_ratingsCache] has liked ID keys (`rating >= 5.0`) not yet resolved
  /// into [_likedMetas].
  bool get hasUnresolvedLikedEntries {
    final likedKeys = _ratingsCache.entries
        .where((e) => e.value >= 5.0)
        .map((e) => e.key)
        .toList();
    if (likedKeys.isEmpty) return false;
    final covered = <String>{
      for (final m in _likedMetas) ..._keysForMeta(m),
    };
    return likedKeys.any((k) => !covered.contains(k));
  }

  /// Marks a title as Anime and optionally records its AniList ID for fast lookup.
  void markAsAnime({
    int? tmdbId,
    String? imdbId,
    required String mediaType,
    int? anilistId,
    bool notify = true,
  }) {
    final keys = _interactionKeys(tmdbId: tmdbId, imdbId: imdbId, mediaType: mediaType);
    if (keys.isEmpty) return;
    var changed = false;
    for (final k in keys) {
      if (_animeKeys.add(k)) changed = true;
      if (anilistId != null && anilistId > 0 && _keyToAnilistCache[k] != anilistId) {
        _keyToAnilistCache[k] = anilistId;
        changed = true;
      }
    }
    if (changed) {
      if (notify) _notifyMyListListeners();
      unawaited(_persistInteractionsToDisk());
    }
  }

  int? _lookupAnilistFromMap({
    int? tmdbId,
    String? imdbId,
    required String mediaType,
    AnimeIdMap? animeIdMap,
  }) {
    final effectiveMap = animeIdMap ?? _animeIdMap;
    if (effectiveMap == null) return null;
    final normType = _normalizeType(mediaType);
    if (imdbId != null && imdbId.trim().isNotEmpty) {
      final trimmed = imdbId.trim();
      if (trimmed.startsWith('anilist:')) {
        return int.tryParse(trimmed.substring('anilist:'.length));
      }
      final byImdb = effectiveMap.lookupAnilistIdByImdb(trimmed);
      if (byImdb != null && byImdb > 0) return byImdb;
      final clean = trimmed.startsWith('tt') ? trimmed : 'tt$trimmed';
      final mappedTmdb = _imdbToTmdbCache[clean];
      if (mappedTmdb != null) {
        final byMapped = effectiveMap.lookupAnilistIdByTmdb(
          tmdbId: mappedTmdb.tmdbId,
          type: mappedTmdb.mediaType,
        );
        if (byMapped != null && byMapped > 0) return byMapped;
      }
    }
    if (tmdbId != null && tmdbId > 0) {
      final byTmdb = effectiveMap.lookupAnilistIdByTmdb(tmdbId: tmdbId, type: normType);
      if (byTmdb != null && byTmdb > 0) return byTmdb;
      final mappedImdb = _cachedImdbFor(tmdbId, normType);
      if (mappedImdb != null) {
        final byImdb = effectiveMap.lookupAnilistIdByImdb(mappedImdb);
        if (byImdb != null && byImdb > 0) return byImdb;
      }
    }
    return null;
  }

  bool _hasAnimeSignal({
    int? tmdbId,
    String? imdbId,
    required String mediaType,
    List<String>? keys,
    MetaModel? meta,
    AnimeIdMap? animeIdMap,
  }) {
    final normType = _normalizeType(mediaType);
    final checkKeys = keys ??
        _interactionKeys(
          tmdbId: tmdbId,
          imdbId: imdbId,
          mediaType: normType,
        );
    for (final k in checkKeys) {
      if (_animeKeys.contains(k) || (_keyToAnilistCache[k] ?? 0) > 0) return true;
      final d = _memo[k] ?? _coreMemo[k];
      if (d != null && d.isJapaneseAnimation) return true;
    }
    if (meta != null && meta.id.trim().startsWith('anilist:')) return true;
    return _lookupAnilistFromMap(
          tmdbId: tmdbId,
          imdbId: imdbId,
          mediaType: normType,
          animeIdMap: animeIdMap,
        ) !=
        null;
  }

  /// Synchronously returns true if any identifier for this title is classified as Anime.
  bool isKeyOrAnime({
    int? tmdbId,
    String? imdbId,
    required String mediaType,
    MetaModel? meta,
    AnimeIdMap? animeIdMap,
  }) =>
      _hasAnimeSignal(
        tmdbId: tmdbId,
        imdbId: imdbId,
        mediaType: mediaType,
        meta: meta,
        animeIdMap: animeIdMap,
      );

  /// Resolves the AniList ID for [m] using cached mappings or [animeIdMap].
  int? resolveAnilistIdForMeta(MetaModel m, [AnimeIdMap? animeIdMap]) {
    final keys = _keysForMeta(m);
    for (final k in keys) {
      final cached = _keyToAnilistCache[k];
      if (cached != null && cached > 0) return cached;
    }
    final effectiveMap = animeIdMap ?? _animeIdMap;
    final trimmed = m.id.trim();
    if (trimmed.startsWith('anilist:')) {
      final parsed = int.tryParse(trimmed.substring('anilist:'.length));
      if (parsed != null && parsed > 0) {
        for (final k in keys) {
          _animeKeys.add(k);
          _keyToAnilistCache[k] = parsed;
        }
        return parsed;
      }
    }
    final parsedTmdb = int.tryParse(trimmed);
    final found = _lookupAnilistFromMap(
      tmdbId: parsedTmdb,
      imdbId: parsedTmdb == null ? trimmed : null,
      mediaType: m.type,
      animeIdMap: effectiveMap,
    );
    if (found != null && found > 0) {
      for (final k in keys) {
        _animeKeys.add(k);
        _keyToAnilistCache[k] = found;
      }
    }
    return found;
  }

  /// Returns true if [m] is classified as an Anime (strictly separated from Movies & TV Shows).
  bool isMetaAnime(MetaModel m, [AnimeIdMap? animeIdMap]) {
    for (final k in _keysForMeta(m)) {
      if (_animeKeys.contains(k)) return true;
      final cached = _memo[k] ?? _coreMemo[k];
      if (cached != null && cached.isJapaneseAnimation) return true;
    }
    if (m.id.trim().startsWith('anilist:')) return true;
    return resolveAnilistIdForMeta(m, animeIdMap) != null;
  }

  /// Returns true if [m] is marked "Not for me" (`rating < 5.0`).
  bool isMetaDisliked(MetaModel m) {
    for (final k in _keysForMeta(m)) {
      final r = _ratingsCache[k];
      if (r != null && r > 0 && r < kTmdbHalfRatingThreshold) return true;
    }
    return false;
  }

  /// Returns true if [m] is liked (`rating >= 5.0`) or saved in "My List".
  bool isMetaLikedOrInMyList(MetaModel m) {
    for (final k in _keysForMeta(m)) {
      if (_myListCache.contains(k)) return true;
      final r = _ratingsCache[k];
      if (r != null && r >= 5.0) return true;
    }
    return false;
  }

  Future<void> ensureInteractionsLoaded() =>
      _loadInteractionsFuture ??= _loadInteractionsFromDisk();

  static const MethodChannel _storageChannel = MethodChannel('openflix/launcher');

  Future<void> _ensureAndroidFilesDirResolved() async {
    if (_interactionsFileOverride != null || !Platform.isAndroid) return;
    if (_resolvedAndroidFilesDir != null) return;
    for (final basePath in const [
      '/data/user/0/app.openflix.client',
      '/data/data/app.openflix.client',
      '/data/user/0/com.example.pixel',
      '/data/data/com.example.pixel',
    ]) {
      if (Directory(basePath).existsSync()) return;
    }
    try {
      final path = await _storageChannel.invokeMethod<String>('getFilesDir');
      if (path != null && path.trim().isNotEmpty) {
        _resolvedAndroidFilesDir = path.trim();
      }
    } catch (_) {}
  }

  File? _resolveInteractionsFile() {
    if (_interactionsFileOverride != null) return _interactionsFileOverride;
    final dynamicDir = _resolvedAndroidFilesDir;
    if (dynamicDir != null && dynamicDir.isNotEmpty) {
      final filesDir = Directory(dynamicDir);
      if (!filesDir.existsSync()) {
        try {
          filesDir.createSync(recursive: true);
        } catch (_) {}
      }
      return File('${filesDir.path}/$_interactionsCacheKey.json');
    }
    for (final basePath in const [
      '/data/user/0/app.openflix.client',
      '/data/data/app.openflix.client',
      '/data/user/0/com.example.pixel',
      '/data/data/com.example.pixel',
    ]) {
      final baseDir = Directory(basePath);
      if (baseDir.existsSync()) {
        final filesDir = Directory('$basePath/files');
        if (!filesDir.existsSync()) {
          try {
            filesDir.createSync(recursive: true);
          } catch (_) {}
        }
        return File('${filesDir.path}/$_interactionsCacheKey.json');
      }
    }
    return null;
  }

  static Future<Map<String, dynamic>?> _tryDecodeInteractionsFile(File candidate) async {
    try {
      if (!await candidate.exists()) return null;
      final raw = await candidate.readAsString();
      if (raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return null;
  }

  static int _payloadPersistVersion(Map<String, dynamic>? payload) {
    if (payload == null) return -1;
    final v = payload['persistVersion'];
    return v is num ? v.toInt() : 0;
  }

  static int _payloadInteractionScore(Map<String, dynamic>? payload) {
    if (payload == null) return -1;
    var score = 0;
    final userSession = payload['userSessionId'];
    if (userSession is String && userSession.trim().isNotEmpty) score += 100;
    final ratings = payload['ratings'];
    if (ratings is Map) score += ratings.length * 2;
    final myList = payload['myList'];
    if (myList is List) score += myList.length * 2;
    final myListMetas = payload['myListMetas'];
    if (myListMetas is List) score += myListMetas.length * 3;
    final likedMetas = payload['likedMetas'];
    if (likedMetas is List) score += likedMetas.length * 3;
    final pendingWatch = payload['pendingWatchlist'];
    if (pendingWatch is Map) score += pendingWatch.length * 2;
    final pendingRatings = payload['pendingRatings'];
    if (pendingRatings is Map) score += pendingRatings.length * 2;
    return score;
  }

  /// Picks between atomic [primary] and recovery candidates ([bak], [tmp]).
  ///
  /// When [primary] is valid JSON, only a [tmp] file with a strictly higher
  /// monotonic `persistVersion` (interrupted between temp write and rename) may
  /// supersede it; `.bak` is never allowed to overwrite a valid [primary], so
  /// intentional deletions or disconnecting TMDB are never rolled back.
  static Map<String, dynamic>? _selectBestInteractionsPayload({
    required Map<String, dynamic>? primary,
    required Map<String, dynamic>? bak,
    required Map<String, dynamic>? tmp,
  }) {
    if (primary != null) {
      final primaryVer = _payloadPersistVersion(primary);
      final tmpVer = _payloadPersistVersion(tmp);
      if (tmp != null && tmpVer > primaryVer) {
        return tmp;
      }
      return primary;
    }
    if (bak == null) return tmp;
    if (tmp == null) return bak;
    final bakVer = _payloadPersistVersion(bak);
    final tmpVer = _payloadPersistVersion(tmp);
    if (tmpVer != bakVer) return tmpVer > bakVer ? tmp : bak;
    return _payloadInteractionScore(tmp) > _payloadInteractionScore(bak) ? tmp : bak;
  }

  Future<void> _loadInteractionsFromDisk() async {
    try {
      await _ensureAndroidFilesDirResolved();
      final file = _resolveInteractionsFile();
      if (file == null) return;

      final primaryDecoded = await _tryDecodeInteractionsFile(file);
      final bakFile = File('${file.path}.bak');
      final tmpFile = File('${file.path}.tmp');
      final bakDecoded = await _tryDecodeInteractionsFile(bakFile);
      final tmpDecoded = await _tryDecodeInteractionsFile(tmpFile);

      final decoded = _selectBestInteractionsPayload(
        primary: primaryDecoded,
        bak: bakDecoded,
        tmp: tmpDecoded,
      );
      if (decoded == null) return;

      final loadedVersion = _payloadPersistVersion(decoded);
      if (loadedVersion > _persistVersion) {
        _persistVersion = loadedVersion;
      }

      final userSession = decoded['userSessionId'];
      if (userSession is String && userSession.trim().isNotEmpty) {
        _userSessionId ??= userSession.trim();
      }
      final rawProfile = decoded['accountProfile'];
      if (rawProfile is Map<String, dynamic>) {
        _accountProfile ??= TmdbAccountProfile.tryParse(rawProfile);
      }
      final rawLastAccountId = decoded['lastSyncedAccountId'];
      if (rawLastAccountId is num && rawLastAccountId.toInt() > 0) {
        _lastSyncedAccountId ??= rawLastAccountId.toInt();
      }
      if (decoded['needsLocalPush'] == true) {
        _needsLocalPush = true;
      }
      if (decoded['sessionExpired'] == true &&
          _userSessionId != null &&
          _userSessionId!.isNotEmpty) {
        _sessionExpired = true;
        _lastSyncSucceeded = false;
        _lastSyncError ??=
            'TMDB session expired. Tap Reconnect below to back up your My List & Likes.';
      }
      final idPairs = decoded['idPairs'];
      if (idPairs is Map) {
        for (final entry in idPairs.entries) {
          final k = entry.key.toString();
          final v = entry.value;
          final parts = k.split(':');
          if (parts.length == 2 && v is String && v.isNotEmpty) {
            final tmdbId = int.tryParse(parts[1]);
            if (tmdbId != null && tmdbId > 0) {
              _registerIdPair(tmdbId, v, parts[0]);
            }
          }
        }
      }
      final animeKeysRaw = decoded['animeKeys'];
      if (animeKeysRaw is List) {
        for (final item in animeKeysRaw) {
          if (item is String && item.isNotEmpty) {
            _animeKeys.add(item);
          }
        }
      }
      final keyToAnilistRaw = decoded['keyToAnilist'];
      if (keyToAnilistRaw is Map) {
        for (final entry in keyToAnilistRaw.entries) {
          final k = entry.key.toString();
          final v = entry.value;
          if (v is num && v > 0) {
            final anilistId = v.toInt();
            _keyToAnilistCache.putIfAbsent(k, () => anilistId);
            _animeKeys.add(k);
            final parsedKey = _parseInteractionKey(k);
            if (parsedKey != null && parsedKey.kind == 'tmdb') {
              final tmdbId = int.tryParse(parsedKey.id);
              if (tmdbId != null && tmdbId > 0) {
                _anilistToTmdbCache.putIfAbsent(
                  anilistId,
                  () => (tmdbId: tmdbId, mediaType: parsedKey.type),
                );
              }
            }
          }
        }
      }
      final anilistToTmdbRaw = decoded['anilistToTmdb'];
      if (anilistToTmdbRaw is Map) {
        for (final entry in anilistToTmdbRaw.entries) {
          final anilistId = int.tryParse(entry.key.toString());
          final parts = entry.value.toString().split(':');
          if (anilistId != null && anilistId > 0 && parts.length == 2) {
            final tmdbId = int.tryParse(parts[1]);
            final normType = _normalizeType(parts[0]);
            if (tmdbId != null && tmdbId > 0) {
              _registerAnilistPair(anilistId, tmdbId, normType);
            }
          }
        }
      }
      final dailyPicksRaw = decoded['dailyPicks'];
      if (dailyPicksRaw is Map) {
        for (final entry in dailyPicksRaw.entries) {
          final k = entry.key.toString();
          final v = entry.value;
          if (v is String && v.isNotEmpty) {
            _dailyPicksCache.putIfAbsent(k, () => v);
          }
        }
      }
      final dailyRowsRaw = decoded['dailyRows'];
      if (dailyRowsRaw is Map) {
        for (final entry in dailyRowsRaw.entries) {
          final k = entry.key.toString();
          final v = entry.value;
          if (k.isEmpty || v is! Map) continue;
          final dateKey = v['dateKey']?.toString() ?? '';
          final sourceRaw = v['sourceMeta'];
          final itemsRaw = v['items'];
          if (dateKey.isEmpty || sourceRaw is! Map || itemsRaw is! List) continue;
          try {
            final sourceMeta = MetaModel.tryParse(
              Map<String, dynamic>.from(sourceRaw),
            );
            if (sourceMeta == null || sourceMeta.id.isEmpty) continue;
            final items = <MetaModel>[
              for (final rawItem in itemsRaw)
                if (rawItem is Map)
                  if (MetaModel.tryParse(Map<String, dynamic>.from(rawItem))
                      case final parsed?)
                    parsed,
            ];
            if (items.isNotEmpty) {
              _dailyRowsCache.putIfAbsent(
                k,
                () => (
                  dateKey: dateKey,
                  sourceMeta: sourceMeta,
                  items: List<MetaModel>.unmodifiable(items),
                ),
              );
            }
          } catch (_) {}
        }
      }
      final pendingWatchRaw = decoded['pendingWatchlist'];
      if (pendingWatchRaw is Map) {
        for (final entry in pendingWatchRaw.entries) {
          final k = entry.key.toString();
          final v = entry.value;
          if (k.isNotEmpty && v is bool) {
            _pendingWatchlistOps.putIfAbsent(k, () => v);
          }
        }
      }
      final pendingRatingsRaw = decoded['pendingRatings'];
      if (pendingRatingsRaw is Map) {
        for (final entry in pendingRatingsRaw.entries) {
          final k = entry.key.toString();
          final v = entry.value;
          if (k.isNotEmpty && v is num) {
            _pendingRatingOps.putIfAbsent(k, () => v.toDouble());
          }
        }
      }
      final recentWatchRaw = decoded['recentWatchlist'];
      if (recentWatchRaw is Map) {
        for (final entry in recentWatchRaw.entries) {
          final k = entry.key.toString();
          final raw = entry.value;
          if (k.isNotEmpty && raw is Map) {
            final v = raw['v'];
            final ts = raw['ts'];
            if (v is bool && ts is num && _isWithinConfirmationWindow(ts.toInt())) {
              _recentWatchlistMutations.putIfAbsent(
                k,
                () => (value: v, updatedAtMs: ts.toInt()),
              );
            }
          }
        }
      }
      final recentRatingsRaw = decoded['recentRatings'];
      if (recentRatingsRaw is Map) {
        for (final entry in recentRatingsRaw.entries) {
          final k = entry.key.toString();
          final raw = entry.value;
          if (k.isNotEmpty && raw is Map) {
            final v = raw['v'];
            final ts = raw['ts'];
            if (v is num && ts is num && _isWithinConfirmationWindow(ts.toInt())) {
              _recentRatingMutations.putIfAbsent(
                k,
                () => (value: v.toDouble(), updatedAtMs: ts.toInt()),
              );
            }
          }
        }
      }
      final ratings = decoded['ratings'];
      if (ratings is Map) {
        for (final entry in ratings.entries) {
          final k = entry.key.toString();
          final v = entry.value;
          if (v is num && v > 0) {
            _ratingsCache.putIfAbsent(k, () => v.toDouble());
          }
        }
      }
      final myList = decoded['myList'];
      if (myList is List) {
        for (final item in myList) {
          if (item is String && item.isNotEmpty) {
            _myListCache.add(item);
          }
        }
      }
      final rawMetas = decoded['myListMetas'];
      if (rawMetas is List) {
        for (final item in rawMetas) {
          if (item is Map<String, dynamic>) {
            final parsed = MetaModel.tryParse(item);
            if (parsed != null) {
              final normalized = _normalizeMyListMeta(parsed);
              // Self-heal: ensure all keys for every persisted My List meta are
              // registered in _myListCache so unbridged IDs are never dropped.
              _myListCache.addAll(_keysForMeta(normalized));
              if (!_myListMetas.any((m) => _metasMatch(m, normalized))) {
                _myListMetas.add(normalized);
              }
            }
          }
        }
      }
      final rawLikedMetas = decoded['likedMetas'];
      if (rawLikedMetas is List) {
        for (final item in rawLikedMetas) {
          if (item is Map<String, dynamic>) {
            final parsed = MetaModel.tryParse(item);
            if (parsed != null) {
              final normalized = _normalizeMyListMeta(parsed);
              if (!isMetaDisliked(normalized)) {
                for (final k in _keysForMeta(normalized)) {
                  _ratingsCache.putIfAbsent(k, () => 8.5);
                }
                if (!_likedMetas.any((m) => _metasMatch(m, normalized))) {
                  _likedMetas.add(normalized);
                }
              }
            }
          }
        }
      }
      _notifyMyListListeners();
    } catch (_) {
      // Safe fallback in unit test environments.
    } finally {
      _interactionsLoaded = true;
    }
  }

  /// Awaits completion of all queued interaction disk writes.
  Future<void> flushInteractions() => _writeQueue;

  Future<void> _persistInteractionsToDisk() {
    final targetSeq = ++_persistSeq;
    _writeQueue = _writeQueue.then((_) async {
      try {
        // Coalesce rapid back-to-back writes so superseded snapshots skip redundant I/O.
        if (targetSeq != _persistSeq) return;
        // CRITICAL: Never serialize and overwrite the disk file before existing
        // interactions have finished loading from disk!
        if (!_interactionsLoaded) {
          await ensureInteractionsLoaded();
        }
        final file = _resolveInteractionsFile();
        if (file == null) return;
        _pruneExpiredRecentMutations();
        final version = ++_persistVersion;
        final payload = <String, dynamic>{
          'persistVersion': version,
          'lastSyncedAccountId': _lastSyncedAccountId,
          'needsLocalPush': _needsLocalPush,
          'sessionExpired': _sessionExpired,
          'userSessionId': _userSessionId,
          'accountProfile': _accountProfile?.toJson(),
          'ratings': Map<String, double>.from(_ratingsCache),
          'myList': _myListCache.toList(),
          'myListMetas': [for (final m in _myListMetas) m.toJson()],
          'likedMetas': [for (final m in _likedMetas) m.toJson()],
          'animeKeys': _animeKeys.toList(),
          'keyToAnilist': Map<String, int>.from(_keyToAnilistCache),
          'anilistToTmdb': {
            for (final e in _anilistToTmdbCache.entries)
              '${e.key}': '${e.value.mediaType}:${e.value.tmdbId}',
          },
          'dailyPicks': Map<String, String>.from(_dailyPicksCache),
          'dailyRows': {
            for (final e in _dailyRowsCache.entries)
              e.key: {
                'dateKey': e.value.dateKey,
                'sourceMeta': e.value.sourceMeta.toJson(),
                'items': [for (final m in e.value.items) m.toJson()],
              },
          },
          'idPairs': Map<String, String>.from(_tmdbToImdbCache),
          'pendingWatchlist': Map<String, bool>.from(_pendingWatchlistOps),
          'pendingRatings': Map<String, double>.from(_pendingRatingOps),
          'recentWatchlist': {
            for (final e in _recentWatchlistMutations.entries)
              e.key: {'v': e.value.value, 'ts': e.value.updatedAtMs},
          },
          'recentRatings': {
            for (final e in _recentRatingMutations.entries)
              e.key: {'v': e.value.value, 'ts': e.value.updatedAtMs},
          },
        };
        final encoded = jsonEncode(payload);

        // Atomic write via .tmp + rename, then mirror into .bak unconditionally so
        // intentional unlikes, removals, and disconnects stay authoritative.
        final tmpFile = File('${file.path}.tmp');
        await tmpFile.writeAsString(encoded, flush: true);

        try {
          await tmpFile.rename(file.path);
        } catch (_) {
          await file.writeAsString(encoded, flush: true);
        }

        final bakFile = File('${file.path}.bak');
        try {
          await bakFile.writeAsString(encoded);
        } catch (_) {}
      } catch (_) {
        // Ignore disk errors in test environments.
      }
    });
    return _writeQueue;
  }

  List<String> _keysForMeta(MetaModel m) {
    final trimmed = m.id.trim();
    final parsedTmdb = int.tryParse(trimmed);
    return _interactionKeys(
      tmdbId: parsedTmdb,
      imdbId: parsedTmdb == null ? trimmed : null,
      mediaType: m.type,
    );
  }

  bool _metasMatch(MetaModel a, MetaModel b) {
    final aId = a.id.trim();
    final bId = b.id.trim();
    if (aId.isNotEmpty && aId == bId) {
      if (aId.startsWith('tt') ||
          aId.startsWith('anilist:') ||
          (a.name.trim().isNotEmpty && a.name.trim() == b.name.trim())) {
        return true;
      }
    }
    final aKeys = _keysForMeta(a);
    final bKeys = _keysForMeta(b);
    for (final k in aKeys) {
      if (bKeys.contains(k)) return true;
    }
    return false;
  }

  MetaModel _normalizeMyListMeta(MetaModel meta) {
    final normType = _normalizeType(meta.type);
    final trimmedId = meta.id.trim();
    final isAnilist = trimmedId.startsWith('anilist:');
    int? resolvedTmdb = isAnilist ? null : int.tryParse(trimmedId);
    var resolvedType = normType;
    String? rawImdb;
    if (isAnilist) {
      final anilistId = int.tryParse(trimmedId.substring('anilist:'.length));
      if (anilistId != null && anilistId > 0) {
        final cached = _anilistToTmdbCache[anilistId];
        if (cached != null) {
          resolvedTmdb = cached.tmdbId;
          resolvedType = cached.mediaType;
          rawImdb = _cachedImdbFor(resolvedTmdb, resolvedType);
        } else {
          final mapped = _animeIdMap?.lookupByAnilistId(anilistId);
          if (mapped != null) {
            if (mapped.tmdbId != null && mapped.tmdbId! > 0) {
              resolvedTmdb = mapped.tmdbId;
              resolvedType = mapped.isMovie ? 'movie' : 'series';
              rawImdb = mapped.imdbId ?? _cachedImdbFor(resolvedTmdb!, resolvedType);
            } else if (mapped.imdbId != null && mapped.imdbId!.isNotEmpty) {
              rawImdb = mapped.imdbId;
              resolvedType = mapped.isMovie ? 'movie' : 'series';
            }
          }
        }
      }
      if (rawImdb != null && !rawImdb.startsWith('tt')) {
        rawImdb = 'tt$rawImdb';
      }
    } else {
      rawImdb = resolvedTmdb == null && trimmedId.isNotEmpty
          ? (trimmedId.startsWith('tt') ? trimmedId : 'tt$trimmedId')
          : (resolvedTmdb != null ? _cachedImdbFor(resolvedTmdb, resolvedType) : null);
    }
    final canonicalId = rawImdb ??
        (resolvedTmdb != null && resolvedTmdb > 0 ? '$resolvedTmdb' : null) ??
        trimmedId;
    final nonBetterPoster =
        (meta.poster != null && meta.poster!.isNotEmpty && !meta.poster!.contains('btttr.cc'))
            ? meta.poster
            : null;
    final fallbackPoster = meta.posterFallback ?? nonBetterPoster;
    final primaryPoster = rawImdb != null ? betterPosterUrl(rawImdb) : (meta.poster ?? fallbackPoster);
    return meta.copyWith(
      id: canonicalId,
      type: resolvedType,
      poster: primaryPoster,
      posterFallback: fallbackPoster,
    );
  }

  /// Builds a normalized [MetaModel] for "My List" with Better Poster (`btttr.cc`)
  /// primary artwork and TMDB/addon fallback poster.
  MetaModel? buildMyListMeta({
    MetaModel? baseMeta,
    TmdbMovieDetails? details,
    int? tmdbId,
    String? imdbId,
    required String mediaType,
  }) {
    final normType = _normalizeType(
      details?.mediaType ??
          (mediaType.trim().isNotEmpty ? mediaType : (baseMeta?.type ?? 'movie')),
    );
    final effectiveTmdbId = details?.tmdbId ?? tmdbId ?? int.tryParse(baseMeta?.id.trim() ?? '');
    final rawImdb = (details?.imdbId != null &&
            details!.imdbId!.trim().isNotEmpty &&
            !details.imdbId!.trim().startsWith('anilist:'))
        ? details.imdbId!.trim()
        : (imdbId != null && imdbId.trim().isNotEmpty && !imdbId.trim().startsWith('anilist:'))
            ? imdbId.trim()
            : (baseMeta != null && baseMeta.id.trim().startsWith('tt'))
                ? baseMeta.id.trim()
                : (effectiveTmdbId != null ? _cachedImdbFor(effectiveTmdbId, normType) : null);
    final cleanImdb = rawImdb != null
        ? (rawImdb.startsWith('tt') ? rawImdb : 'tt$rawImdb')
        : null;
    if (effectiveTmdbId != null && effectiveTmdbId > 0 && cleanImdb != null) {
      _registerIdPair(effectiveTmdbId, cleanImdb, normType);
    }

    final resolvedId = cleanImdb ??
        (effectiveTmdbId != null && effectiveTmdbId > 0 ? '$effectiveTmdbId' : null) ??
        baseMeta?.id.trim() ??
        '';
    final resolvedName = (details != null && details.title.trim().isNotEmpty)
        ? details.title.trim()
        : (baseMeta?.name.trim() ?? '');

    if (resolvedId.isEmpty || resolvedName.isEmpty) return null;

    final nonBetterBasePoster = (baseMeta?.poster != null &&
            baseMeta!.poster!.isNotEmpty &&
            !baseMeta.poster!.contains('btttr.cc'))
        ? baseMeta.poster
        : null;

    final fallbackPoster = details?.posterUrl ??
        baseMeta?.posterFallback ??
        nonBetterBasePoster ??
        details?.textlessPosterUrl;

    final primaryPoster = cleanImdb != null
        ? betterPosterUrl(cleanImdb)
        : (baseMeta?.poster ?? fallbackPoster);

    return MetaModel(
      id: resolvedId,
      type: normType,
      name: resolvedName,
      poster: primaryPoster,
      posterFallback: fallbackPoster,
      background: details?.backdropUrl ?? baseMeta?.background,
      landscapePoster: baseMeta?.landscapePoster,
      logo: details?.logoUrl ?? baseMeta?.logo,
      description: (details != null && details.overview.isNotEmpty)
          ? details.overview
          : baseMeta?.description,
      genres: (details != null && details.genres.isNotEmpty)
          ? details.genres
          : (baseMeta?.genres ?? const []),
      releaseInfo: details?.releaseYear ?? baseMeta?.releaseInfo,
      runtime: details?.runtimeLabel ?? baseMeta?.runtime,
      imdbRating: details?.ratingLabel ?? baseMeta?.imdbRating,
    );
  }

  void _upsertMyListMeta(MetaModel candidate, {required bool moveToFront}) =>
      _upsertMetaInList(_myListMetas, candidate, moveToFront: moveToFront);

  void _upsertLikedMeta(MetaModel candidate, {required bool moveToFront}) =>
      _upsertMetaInList(_likedMetas, candidate, moveToFront: moveToFront);

  static String _pickCanonicalMetaId(String nextId, String prevId) {
    if (nextId.startsWith('tt')) return nextId;
    if (prevId.startsWith('tt')) return prevId;
    if (!nextId.startsWith('anilist:') && int.tryParse(nextId) != null) {
      return nextId;
    }
    return prevId.isNotEmpty ? prevId : nextId;
  }

  void _upsertMetaInList(
    List<MetaModel> list,
    MetaModel candidate, {
    required bool moveToFront,
  }) {
    final normalized = _normalizeMyListMeta(candidate);
    final existingIdx = list.indexWhere((m) => _metasMatch(m, normalized));
    if (existingIdx >= 0) {
      final prev = list[existingIdx];
      final merged = MetaModel(
        id: _pickCanonicalMetaId(normalized.id, prev.id),
        type: normalized.type,
        name: normalized.name.isNotEmpty ? normalized.name : prev.name,
        poster: normalized.poster ?? prev.poster,
        posterFallback: normalized.posterFallback ?? prev.posterFallback,
        tallPoster: normalized.tallPoster ?? prev.tallPoster,
        background: normalized.background ?? prev.background,
        landscapePoster: normalized.landscapePoster ?? prev.landscapePoster,
        logo: normalized.logo ?? prev.logo,
        logoAspectRatio: normalized.logoAspectRatio ?? prev.logoAspectRatio,
        description: normalized.description ?? prev.description,
        genres: normalized.genres.isNotEmpty ? normalized.genres : prev.genres,
        releaseInfo: normalized.releaseInfo ?? prev.releaseInfo,
        runtime: normalized.runtime ?? prev.runtime,
        imdbRating: normalized.imdbRating ?? prev.imdbRating,
      );
      if (moveToFront && existingIdx != 0) {
        list.removeAt(existingIdx);
        list.insert(0, merged);
      } else {
        list[existingIdx] = merged;
      }
    } else {
      if (moveToFront) {
        list.insert(0, normalized);
      } else {
        list.add(normalized);
      }
    }
  }

  List<String> _interactionKeys({
    int? tmdbId,
    String? imdbId,
    required String mediaType,
  }) {
    final normType = _normalizeType(mediaType);
    final keys = <String>[];
    if (tmdbId != null && tmdbId > 0) {
      final tmdbKey = _cacheKey('$tmdbId', normType);
      keys.add(tmdbKey);
      final mappedImdb = _cachedImdbFor(tmdbId, normType);
      String? imdbKey;
      if (mappedImdb != null) {
        imdbKey = _cacheKey(mappedImdb, normType);
        keys.add(imdbKey);
      }
      final linkedAnilist = _keyToAnilistCache[tmdbKey] ??
          (imdbKey != null ? _keyToAnilistCache[imdbKey] : null) ??
          _animeIdMap?.lookupAnilistIdByTmdb(tmdbId: tmdbId, type: normType) ??
          (mappedImdb != null ? _animeIdMap?.lookupAnilistIdByImdb(mappedImdb) : null);
      if (linkedAnilist != null && linkedAnilist > 0) {
        keys.add(_cacheKey('anilist:$linkedAnilist', normType));
      }
    }
    if (imdbId != null && imdbId.trim().isNotEmpty) {
      final trimmed = imdbId.trim();
      final primaryKey = _cacheKey(trimmed, normType);
      keys.add(primaryKey);
      if (trimmed.startsWith('anilist:')) {
        final anilistId = int.tryParse(trimmed.substring('anilist:'.length));
        if (anilistId != null && anilistId > 0) {
          final cachedTmdb = _anilistToTmdbCache[anilistId];
          if (cachedTmdb != null) {
            keys.add(_cacheKey('${cachedTmdb.tmdbId}', cachedTmdb.mediaType));
            keys.add(_cacheKey(trimmed, cachedTmdb.mediaType));
            final mappedImdb = _cachedImdbFor(cachedTmdb.tmdbId, cachedTmdb.mediaType);
            if (mappedImdb != null) {
              keys.add(_cacheKey(mappedImdb, cachedTmdb.mediaType));
            }
          }
          final mapped = _animeIdMap?.lookupByAnilistId(anilistId);
          if (mapped != null) {
            final mappedType = mapped.isMovie ? 'movie' : 'series';
            if (mapped.tmdbId != null && mapped.tmdbId! > 0) {
              keys.add(_cacheKey('${mapped.tmdbId}', mappedType));
              final mappedImdb = _cachedImdbFor(mapped.tmdbId!, mappedType);
              if (mappedImdb != null) {
                keys.add(_cacheKey(mappedImdb, mappedType));
              }
            }
            if (mapped.imdbId != null && mapped.imdbId!.isNotEmpty) {
              final clean = mapped.imdbId!.startsWith('tt')
                  ? mapped.imdbId!
                  : 'tt${mapped.imdbId!}';
              keys.add(_cacheKey(clean, mappedType));
              final resolvedTmdb = _imdbToTmdbCache[clean];
              if (resolvedTmdb != null) {
                keys.add(_cacheKey('${resolvedTmdb.tmdbId}', resolvedTmdb.mediaType));
                keys.add(_cacheKey(clean, resolvedTmdb.mediaType));
              }
            }
          }
        }
      } else {
        final cleanImdb = trimmed.startsWith('tt') ? trimmed : 'tt$trimmed';
        final mappedTmdb = _imdbToTmdbCache[cleanImdb];
        if (mappedTmdb != null) {
          final resTmdbKey = _cacheKey('${mappedTmdb.tmdbId}', mappedTmdb.mediaType);
          final resImdbKey = _cacheKey(cleanImdb, mappedTmdb.mediaType);
          keys.add(resTmdbKey);
          keys.add(resImdbKey);
          final linkedAnilist = _keyToAnilistCache[resTmdbKey] ??
              _keyToAnilistCache[resImdbKey] ??
              _animeIdMap?.lookupAnilistIdByTmdb(
                tmdbId: mappedTmdb.tmdbId,
                type: mappedTmdb.mediaType,
              );
          if (linkedAnilist != null && linkedAnilist > 0) {
            keys.add(_cacheKey('anilist:$linkedAnilist', mappedTmdb.mediaType));
          }
        } else {
          final linkedAnilist =
              _keyToAnilistCache[primaryKey] ?? _animeIdMap?.lookupAnilistIdByImdb(cleanImdb);
          if (linkedAnilist != null && linkedAnilist > 0) {
            keys.add(_cacheKey('anilist:$linkedAnilist', normType));
          }
        }
      }
    }
    return keys.toSet().toList();
  }

  double? _pendingRatingFor(Iterable<String> keys) {
    for (final k in keys) {
      if (_pendingRatingOps.containsKey(k)) return _pendingRatingOps[k];
    }
    return null;
  }

  bool? _pendingWatchlistFor(Iterable<String> keys) {
    for (final k in keys) {
      if (_pendingWatchlistOps.containsKey(k)) return _pendingWatchlistOps[k];
    }
    return null;
  }

  bool _isWithinConfirmationWindow(int updatedAtMs) {
    final ageMs = _nowMs() - updatedAtMs;
    return ageMs >= 0 && ageMs < kTmdbWriteConfirmationWindow.inMilliseconds;
  }

  void _pruneExpiredRecentMutations() {
    _recentWatchlistMutations.removeWhere(
      (_, entry) => !_isWithinConfirmationWindow(entry.updatedAtMs),
    );
    _recentRatingMutations.removeWhere(
      (_, entry) => !_isWithinConfirmationWindow(entry.updatedAtMs),
    );
  }

  T? _recentValueFor<T>(
    Map<String, ({T value, int updatedAtMs})> recentMap,
    Iterable<String> keys,
  ) {
    ({T value, int updatedAtMs})? latest;
    for (final k in keys) {
      final entry = recentMap[k];
      if (entry == null) continue;
      if (!_isWithinConfirmationWindow(entry.updatedAtMs)) {
        recentMap.remove(k);
        continue;
      }
      if (latest == null || entry.updatedAtMs > latest.updatedAtMs) {
        latest = entry;
      }
    }
    return latest?.value;
  }

  double? _recentRatingFor(Iterable<String> keys) =>
      _recentValueFor<double>(_recentRatingMutations, keys);

  bool? _recentWatchlistFor(Iterable<String> keys) =>
      _recentValueFor<bool>(_recentWatchlistMutations, keys);

  void _recordRecentMutation<T>(
    Map<String, ({T value, int updatedAtMs})> recentMap, {
    required Iterable<String> keys,
    required String canonicalKey,
    required T value,
  }) {
    for (final k in keys) {
      recentMap.remove(k);
    }
    if (canonicalKey.isNotEmpty) {
      recentMap[canonicalKey] = (value: value, updatedAtMs: _nowMs());
    }
  }

  List<String> _expandInteractionKey(String key) {
    final k = _parseInteractionKey(key);
    if (k == null) return [key];
    return _interactionKeys(
      tmdbId: k.kind == 'tmdb' ? int.tryParse(k.id) : null,
      imdbId: k.kind == 'imdb'
          ? k.id
          : (k.kind == 'anilist' ? 'anilist:${k.id}' : null),
      mediaType: k.type,
    );
  }

  String _canonicalPendingKey({
    int? tmdbId,
    String? imdbId,
    required String mediaType,
    required List<String> keys,
  }) {
    final normType = _normalizeType(mediaType);
    if (tmdbId != null && tmdbId > 0) return _cacheKey('$tmdbId', normType);
    if (imdbId != null && imdbId.trim().isNotEmpty) return _cacheKey(imdbId.trim(), normType);
    return keys.isNotEmpty ? keys.first : '';
  }

  ({String? imdbId, int? tmdbId, String mediaType}) _resolveLocalIds({
    int? tmdbId,
    String? imdbId,
    required String mediaType,
    MetaModel? meta,
  }) {
    final rawId = meta?.id.trim();
    final isAnilistId = rawId != null && rawId.startsWith('anilist:');
    final rawImdb = imdbId ??
        ((rawId != null && (rawId.startsWith('tt') || isAnilistId)) ? rawId : null);
    final resolvedImdb = (rawImdb != null && rawImdb.trim().isNotEmpty)
        ? (rawImdb.trim().startsWith('tt') || rawImdb.trim().startsWith('anilist:')
            ? rawImdb.trim()
            : 'tt${rawImdb.trim()}')
        : null;
    final cachedTmdb = (resolvedImdb != null && !resolvedImdb.startsWith('anilist:'))
        ? _imdbToTmdbCache[resolvedImdb]
        : null;
    final parsedMetaTmdb = isAnilistId ? null : int.tryParse(rawId ?? '');
    final resolvedTmdb = tmdbId ?? parsedMetaTmdb ?? cachedTmdb?.tmdbId;
    final baseType = _normalizeType(
      mediaType.trim().isNotEmpty ? mediaType : (meta?.type ?? 'movie'),
    );
    final resolvedType = (cachedTmdb != null &&
            (resolvedTmdb == null || resolvedTmdb == cachedTmdb.tmdbId))
        ? cachedTmdb.mediaType
        : baseType;
    if (resolvedTmdb != null &&
        resolvedTmdb > 0 &&
        resolvedImdb != null &&
        !resolvedImdb.startsWith('anilist:')) {
      _registerIdPair(resolvedTmdb, resolvedImdb, resolvedType);
    }
    return (imdbId: resolvedImdb, tmdbId: resolvedTmdb, mediaType: resolvedType);
  }

  /// Looks up any known user rating (`0.5 .. 10.0`) for this title.
  double? getCachedUserRating({
    int? tmdbId,
    String? imdbId,
    required String mediaType,
  }) {
    for (final k in _interactionKeys(tmdbId: tmdbId, imdbId: imdbId, mediaType: mediaType)) {
      final r = _ratingsCache[k];
      if (r != null && r > 0) return r;
    }
    return null;
  }

  /// Looks up whether this title is saved in the user's "My List".
  bool getCachedIsInMyList({
    int? tmdbId,
    String? imdbId,
    required String mediaType,
  }) {
    for (final k in _interactionKeys(tmdbId: tmdbId, imdbId: imdbId, mediaType: mediaType)) {
      if (_myListCache.contains(k)) return true;
    }
    return false;
  }

  void _patchMemoInteraction({
    int? tmdbId,
    String? imdbId,
    required String mediaType,
    double? userRating,
    bool clearUserRating = false,
    bool? isInMyList,
  }) {
    for (final k in _interactionKeys(tmdbId: tmdbId, imdbId: imdbId, mediaType: mediaType)) {
      final core = _coreMemo[k];
      if (core != null) {
        _coreMemo[k] = core.copyWith(
          userRating: userRating,
          clearUserRating: clearUserRating,
          isInMyList: isInMyList,
        );
      }
      final full = _memo[k];
      if (full != null) {
        _memo[k] = full.copyWith(
          userRating: userRating,
          clearUserRating: clearUserRating,
          isInMyList: isInMyList,
        );
      }
    }
  }

  /// Projects live cache, pending-op, and recent-confirmation state onto [details]
  /// so session memo hits never resurrect cleared or pre-edit interaction flags.
  TmdbMovieDetails _withLiveInteractionState(
    TmdbMovieDetails details, {
    String? lookupId,
  }) {
    final released = details.filterReleasedRelated(now: currentNow);
    final projectedSimilar = _projectCachedImdbIds(released.similar);
    final projectedRecs = _projectCachedImdbIds(released.recommendations);
    final allResolved = projectedRecs.take(20).every((r) => r.imdbId != null) &&
        projectedSimilar.take(20).every((s) => s.imdbId != null);
    final effectiveResolved = released.isExternalIdsResolved && allResolved;

    final trimmedLookup = lookupId?.trim();
    final effectiveImdb = released.imdbId ??
        (trimmedLookup != null && trimmedLookup.isNotEmpty ? trimmedLookup : null);
    final keys = <String>{
      ..._interactionKeys(
        tmdbId: released.tmdbId,
        imdbId: effectiveImdb,
        mediaType: released.mediaType,
      ),
      if (trimmedLookup != null && trimmedLookup.isNotEmpty)
        _cacheKey(trimmedLookup, released.mediaType),
    };
    final pendingRating = _pendingRatingFor(keys);
    final recentRating = _recentRatingFor(keys);
    final liveRating = pendingRating != null
        ? (pendingRating > 0 ? pendingRating : null)
        : (recentRating != null
            ? (recentRating > 0 ? recentRating : null)
            : getCachedUserRating(
                tmdbId: released.tmdbId,
                imdbId: effectiveImdb,
                mediaType: released.mediaType,
              ));
    final pendingWatchlist = _pendingWatchlistFor(keys);
    final recentWatchlist = _recentWatchlistFor(keys);
    final liveMyList = pendingWatchlist ??
        recentWatchlist ??
        getCachedIsInMyList(
          tmdbId: released.tmdbId,
          imdbId: effectiveImdb,
          mediaType: released.mediaType,
        );
    final relatedChanged =
        !identical(released, details) || effectiveResolved != released.isExternalIdsResolved;
    if (!relatedChanged &&
        liveRating == released.userRating &&
        liveMyList == released.isInMyList) {
      return released;
    }
    return released.copyWith(
      similar: projectedSimilar,
      recommendations: projectedRecs,
      isExternalIdsResolved: effectiveResolved,
      userRating: liveRating,
      clearUserRating: liveRating == null,
      isInMyList: liveMyList,
    );
  }

  void _patchAllMemosFromCaches() {
    for (final entry in _coreMemo.entries.toList()) {
      _coreMemo[entry.key] = _withLiveInteractionState(entry.value);
    }
    for (final entry in _memo.entries.toList()) {
      _memo[entry.key] = _withLiveInteractionState(entry.value);
    }
  }

  TmdbMovieDetails? _cachedDetailsMatchingType(
    List<String> keys,
    String mediaType,
  ) {
    final normType = _normalizeType(mediaType);
    for (final k in keys) {
      final candidate = _memo[k] ?? _coreMemo[k];
      if (candidate != null && candidate.mediaType == normType) {
        return candidate;
      }
    }
    return null;
  }

  void _applyRatingToCaches({
    required List<String> keys,
    required int? tmdbId,
    required String? imdbId,
    required String mediaType,
    required double? rating,
    MetaModel? meta,
    bool isAnime = false,
  }) {
    if (isAnime) {
      final anilistId = _lookupAnilistFromMap(
        tmdbId: tmdbId,
        imdbId: imdbId,
        mediaType: mediaType,
      );
      markAsAnime(
        tmdbId: tmdbId,
        imdbId: imdbId,
        mediaType: mediaType,
        anilistId: anilistId,
        notify: false,
      );
    }
    if (rating == null || rating <= 0) {
      for (final k in keys) {
        _ratingsCache.remove(k);
      }
      _patchMemoInteraction(
        tmdbId: tmdbId,
        imdbId: imdbId,
        mediaType: mediaType,
        clearUserRating: true,
      );
      _likedMetas.removeWhere((m) => _keysForMeta(m).any(keys.contains));
      return;
    }
    for (final k in keys) {
      _ratingsCache[k] = rating;
    }
    _patchMemoInteraction(
      tmdbId: tmdbId,
      imdbId: imdbId,
      mediaType: mediaType,
      userRating: rating,
    );
    if (rating >= 5.0) {
      final cachedDetails = _cachedDetailsMatchingType(keys, mediaType);
      final candidate = buildMyListMeta(
        baseMeta: meta,
        details: cachedDetails,
        tmdbId: tmdbId,
        imdbId: imdbId,
        mediaType: mediaType,
      );
      if (candidate != null) {
        _upsertLikedMeta(candidate, moveToFront: true);
      }
      if (cachedDetails == null && (candidate == null || !candidate.id.startsWith('tt'))) {
        final lookupId = imdbId ?? (tmdbId != null ? '$tmdbId' : meta?.id);
        if (lookupId != null &&
            lookupId.trim().isNotEmpty &&
            !lookupId.trim().startsWith('anilist:')) {
          unawaited(_enrichSingleLikedItem(lookupId.trim(), mediaType, baseMeta: candidate ?? meta));
        }
      }
    } else {
      _likedMetas.removeWhere((m) => _keysForMeta(m).any(keys.contains));
    }
  }

  /// Sets or clears the user's rating (`0.5 .. 10.0`) locally and submits it to
  /// TMDB (`POST` or `DELETE` `/{movie|tv}/{id}/rating`).
  Future<void> setUserRating({
    int? tmdbId,
    String? imdbId,
    required String mediaType,
    required double? rating,
    MetaModel? meta,
    bool isAnime = false,
  }) async {
    await ensureInteractionsLoaded();
    final ids = _resolveLocalIds(
      tmdbId: tmdbId,
      imdbId: imdbId,
      mediaType: mediaType,
      meta: meta,
    );
    final normType = ids.mediaType;
    final resolvedImdbId = ids.imdbId;
    final resolvedTmdbId = ids.tmdbId;
    final keys = _interactionKeys(
      tmdbId: resolvedTmdbId,
      imdbId: resolvedImdbId,
      mediaType: normType,
    );
    final effectiveAnime = isAnime ||
        _hasAnimeSignal(
          tmdbId: resolvedTmdbId,
          imdbId: resolvedImdbId,
          mediaType: normType,
          keys: keys,
          meta: meta,
        );

    _applyRatingToCaches(
      keys: keys,
      tmdbId: resolvedTmdbId,
      imdbId: resolvedImdbId,
      mediaType: normType,
      rating: rating,
      meta: meta,
      isAnime: effectiveAnime,
    );
    for (final k in keys) {
      _pendingRatingOps.remove(k);
      _recentRatingMutations.remove(k);
    }
    final effectiveRating = (rating != null && rating > 0) ? rating : 0.0;
    final pendingKey = _canonicalPendingKey(
      tmdbId: resolvedTmdbId,
      imdbId: resolvedImdbId,
      mediaType: normType,
      keys: keys,
    );
    if (pendingKey.isNotEmpty) {
      _pendingRatingOps[pendingKey] = effectiveRating;
    }
    if (!isAuthenticated) {
      _needsLocalPush = true;
    }
    _notifyMyListListeners();
    unawaited(_persistInteractionsToDisk());

    final submitRes = await _submitTmdbRating(
      tmdbId: resolvedTmdbId,
      imdbId: resolvedImdbId,
      mediaType: normType,
      rating: rating,
      meta: meta,
      animeIdMap: _animeIdMap,
    );
    _reconcilePendingAfterSubmit<double>(
      pendingMap: _pendingRatingOps,
      recentMap: _recentRatingMutations,
      initialKeys: keys,
      submitRes: submitRes,
      resolvedTmdbId: resolvedTmdbId,
      resolvedImdbId: resolvedImdbId,
      normType: normType,
      pendingValue: effectiveRating,
      onRemoveStaleKeys: (stale) {
        for (final k in stale) {
          _ratingsCache.remove(k);
        }
      },
      onCanonicalResolved: (allKeys, resTmdb, resType) => _applyRatingToCaches(
        keys: allKeys,
        tmdbId: resTmdb,
        imdbId: resolvedImdbId,
        mediaType: resType,
        rating: rating,
        meta: meta,
        isAnime: effectiveAnime,
      ),
    );
  }

  void _reconcilePendingAfterSubmit<T>({
    required Map<String, T> pendingMap,
    required Map<String, ({T value, int updatedAtMs})> recentMap,
    required List<String> initialKeys,
    required ({bool ok, int? tmdbId, String? mediaType}) submitRes,
    required int? resolvedTmdbId,
    required String? resolvedImdbId,
    required String normType,
    required T pendingValue,
    required void Function(List<String> staleKeys) onRemoveStaleKeys,
    required void Function(List<String> allKeys, int tmdbId, String mediaType) onCanonicalResolved,
  }) {
    final resTmdb = submitRes.tmdbId;
    final resType = submitRes.mediaType;
    final canonicalChanged = resTmdb != null &&
        resType != null &&
        (resTmdb != resolvedTmdbId || resType != normType);
    final resolvedKeys = (resTmdb != null && resType != null)
        ? _interactionKeys(
            tmdbId: resTmdb,
            imdbId: resolvedImdbId,
            mediaType: resType,
          )
        : const <String>[];
    final allKeys = <String>{
      ...initialKeys,
      ...resolvedKeys,
    }.toList();

    // Do not let an older in-flight POST overwrite or clear a newer user toggle.
    T? latestPending;
    for (final k in allKeys) {
      if (pendingMap.containsKey(k)) {
        latestPending = pendingMap[k];
        break;
      }
    }
    if (latestPending != null && latestPending != pendingValue) {
      return;
    }

    if (canonicalChanged) {
      final crossTypeChanged = resType != normType;
      final staleKeys = crossTypeChanged
          ? [
              for (final k in initialKeys)
                if (k.startsWith('$normType:') && !resolvedKeys.contains(k)) k,
            ]
          : const <String>[];
      if (staleKeys.isNotEmpty) {
        onRemoveStaleKeys(staleKeys);
        for (final k in staleKeys) {
          pendingMap.remove(k);
          recentMap.remove(k);
        }
      }
      onCanonicalResolved(crossTypeChanged ? resolvedKeys : allKeys, resTmdb, resType);
      _notifyMyListListeners();
    }

    final effectiveKeys = (resType != null && resType != normType && resolvedKeys.isNotEmpty)
        ? resolvedKeys
        : allKeys;
    final canonicalKey = _canonicalPendingKey(
      tmdbId: resTmdb ?? resolvedTmdbId,
      imdbId: resolvedImdbId,
      mediaType: resType ?? normType,
      keys: effectiveKeys,
    );

    if (submitRes.ok) {
      for (final k in allKeys) {
        pendingMap.remove(k);
      }
      _recordRecentMutation<T>(
        recentMap,
        keys: effectiveKeys,
        canonicalKey: canonicalKey,
        value: pendingValue,
      );
      if (!hasPendingSyncOps) {
        _pendingFlushAttempts = 0;
      } else {
        _schedulePendingFlushRetry();
      }
      unawaited(_persistInteractionsToDisk());
    } else {
      _needsLocalPush = true;
      if (canonicalChanged) {
        for (final k in allKeys) {
          pendingMap.remove(k);
        }
        pendingMap[_cacheKey('$resTmdb', resType)] = pendingValue;
      }
      unawaited(_persistInteractionsToDisk());
      _notifyMyListListeners();
      _schedulePendingFlushRetry();
    }
  }

  void _schedulePendingFlushRetry() {
    if (!_enableRetryTimer ||
        _disposed ||
        _sessionExpired ||
        !isAuthenticated ||
        (!hasPendingSyncOps && !_needsLocalPush)) {
      return;
    }
    if (_pendingFlushTimer?.isActive ?? false) return;
    const delays = [
      Duration(seconds: 4),
      Duration(seconds: 12),
      Duration(seconds: 30),
    ];
    final idx = _pendingFlushAttempts < delays.length
        ? _pendingFlushAttempts
        : delays.length - 1;
    final delay = delays[idx];
    _pendingFlushAttempts++;
    _pendingFlushTimer = Timer(delay, () {
      _pendingFlushTimer = null;
      if (_disposed ||
          !isAuthenticated ||
          (!hasPendingSyncOps && !_needsLocalPush)) {
        return;
      }
      unawaited(syncTmdbAccountData(pushLocalOnly: _needsLocalPush));
    });
  }

  void _applyWatchlistToCaches({
    required List<String> keys,
    required int? tmdbId,
    required String? imdbId,
    required String mediaType,
    required bool inMyList,
    MetaModel? meta,
    bool isAnime = false,
  }) {
    if (isAnime) {
      final anilistId = _lookupAnilistFromMap(
        tmdbId: tmdbId,
        imdbId: imdbId,
        mediaType: mediaType,
      );
      markAsAnime(
        tmdbId: tmdbId,
        imdbId: imdbId,
        mediaType: mediaType,
        anilistId: anilistId,
        notify: false,
      );
    }
    for (final k in keys) {
      if (inMyList) {
        _myListCache.add(k);
      } else {
        _myListCache.remove(k);
      }
    }
    _patchMemoInteraction(
      tmdbId: tmdbId,
      imdbId: imdbId,
      mediaType: mediaType,
      isInMyList: inMyList,
    );

    if (inMyList) {
      final cachedDetails = _cachedDetailsMatchingType(keys, mediaType);
      final candidate = buildMyListMeta(
        baseMeta: meta,
        details: cachedDetails,
        tmdbId: tmdbId,
        imdbId: imdbId,
        mediaType: mediaType,
      );
      if (candidate != null) {
        _upsertMyListMeta(candidate, moveToFront: true);
      }
      if (cachedDetails == null && (candidate == null || !candidate.id.startsWith('tt'))) {
        final lookupId = imdbId ?? (tmdbId != null ? '$tmdbId' : meta?.id);
        if (lookupId != null &&
            lookupId.trim().isNotEmpty &&
            !lookupId.trim().startsWith('anilist:')) {
          unawaited(_enrichSingleMyListItem(lookupId.trim(), mediaType, baseMeta: candidate ?? meta));
        }
      }
    } else {
      _myListMetas.removeWhere((m) {
        final mKeys = _keysForMeta(m);
        return mKeys.any(keys.contains);
      });
    }
  }

  /// Toggles or sets whether this title is in the user's "My List" and syncs
  /// with the user's TMDB Watchlist (`POST /account/{account_id}/watchlist`).
  Future<void> setMyList({
    int? tmdbId,
    String? imdbId,
    required String mediaType,
    required bool inMyList,
    MetaModel? meta,
    bool isAnime = false,
  }) async {
    await ensureInteractionsLoaded();
    final ids = _resolveLocalIds(
      tmdbId: tmdbId,
      imdbId: imdbId,
      mediaType: mediaType,
      meta: meta,
    );
    final normType = ids.mediaType;
    final resolvedImdbId = ids.imdbId;
    final resolvedTmdbId = ids.tmdbId;
    final keys = _interactionKeys(
      tmdbId: resolvedTmdbId,
      imdbId: resolvedImdbId,
      mediaType: normType,
    );
    final effectiveAnime = isAnime ||
        _hasAnimeSignal(
          tmdbId: resolvedTmdbId,
          imdbId: resolvedImdbId,
          mediaType: normType,
          keys: keys,
          meta: meta,
        );

    _applyWatchlistToCaches(
      keys: keys,
      tmdbId: resolvedTmdbId,
      imdbId: resolvedImdbId,
      mediaType: normType,
      inMyList: inMyList,
      meta: meta,
      isAnime: effectiveAnime,
    );
    for (final k in keys) {
      _pendingWatchlistOps.remove(k);
      _recentWatchlistMutations.remove(k);
    }
    final pendingKey = _canonicalPendingKey(
      tmdbId: resolvedTmdbId,
      imdbId: resolvedImdbId,
      mediaType: normType,
      keys: keys,
    );
    if (pendingKey.isNotEmpty) {
      _pendingWatchlistOps[pendingKey] = inMyList;
    }
    if (!isAuthenticated) {
      _needsLocalPush = true;
    }

    _notifyMyListListeners();
    unawaited(_persistInteractionsToDisk());

    final submitRes = await _submitTmdbWatchlist(
      tmdbId: resolvedTmdbId,
      imdbId: resolvedImdbId,
      mediaType: normType,
      watchlist: inMyList,
      meta: meta,
      animeIdMap: _animeIdMap,
    );
    _reconcilePendingAfterSubmit<bool>(
      pendingMap: _pendingWatchlistOps,
      recentMap: _recentWatchlistMutations,
      initialKeys: keys,
      submitRes: submitRes,
      resolvedTmdbId: resolvedTmdbId,
      resolvedImdbId: resolvedImdbId,
      normType: normType,
      pendingValue: inMyList,
      onRemoveStaleKeys: (stale) {
        for (final k in stale) {
          _myListCache.remove(k);
        }
      },
      onCanonicalResolved: (allKeys, resTmdb, resType) => _applyWatchlistToCaches(
        keys: allKeys,
        tmdbId: resTmdb,
        imdbId: resolvedImdbId,
        mediaType: resType,
        inMyList: inMyList,
        meta: meta,
        isAnime: effectiveAnime,
      ),
    );
  }

  void _syncAnimeForDetails(TmdbMovieDetails details, {String? lookupId, MetaModel? baseMeta}) {
    final effectiveImdb = details.imdbId ?? lookupId;
    final keys = _interactionKeys(
      tmdbId: details.tmdbId,
      imdbId: effectiveImdb,
      mediaType: details.mediaType,
    );
    final anilistId = _lookupAnilistFromMap(
      tmdbId: details.tmdbId,
      imdbId: effectiveImdb,
      mediaType: details.mediaType,
    );
    if (details.isJapaneseAnimation ||
        anilistId != null ||
        _hasAnimeSignal(
          tmdbId: details.tmdbId,
          imdbId: effectiveImdb,
          mediaType: details.mediaType,
          keys: keys,
          meta: baseMeta,
        )) {
      markAsAnime(
        tmdbId: details.tmdbId,
        imdbId: effectiveImdb,
        mediaType: details.mediaType,
        anilistId: anilistId,
        notify: false,
      );
    }
  }

  Future<void> _enrichSingleLikedItem(
    String lookupId,
    String mediaType, {
    MetaModel? baseMeta,
  }) async {
    try {
      final details = await fetchCoreDetails(lookupId, type: mediaType);
      if (details.title.trim().isEmpty) return;
      final rating = getCachedUserRating(
        tmdbId: details.tmdbId,
        imdbId: details.imdbId ?? lookupId,
        mediaType: details.mediaType,
      );
      if (rating == null || rating < 5.0) return;
      _syncAnimeForDetails(details, lookupId: lookupId, baseMeta: baseMeta);
      for (final k in _interactionKeys(
        tmdbId: details.tmdbId,
        imdbId: details.imdbId ?? lookupId,
        mediaType: details.mediaType,
      )) {
        _ratingsCache[k] = rating;
      }
      final enriched = buildMyListMeta(
        baseMeta: baseMeta,
        details: details,
        tmdbId: details.tmdbId,
        imdbId: details.imdbId,
        mediaType: details.mediaType,
      );
      if (enriched != null) {
        _upsertLikedMeta(enriched, moveToFront: false);
        _notifyMyListListeners();
        unawaited(_persistInteractionsToDisk());
      }
    } catch (_) {}
  }

  Future<void> _enrichSingleMyListItem(
    String lookupId,
    String mediaType, {
    MetaModel? baseMeta,
  }) async {
    try {
      final details = await fetchCoreDetails(lookupId, type: mediaType);
      if (details.title.trim().isEmpty) return;
      if (!getCachedIsInMyList(
        tmdbId: details.tmdbId,
        imdbId: details.imdbId ?? lookupId,
        mediaType: details.mediaType,
      )) {
        return;
      }
      _syncAnimeForDetails(details, lookupId: lookupId, baseMeta: baseMeta);
      for (final k in _interactionKeys(
        tmdbId: details.tmdbId,
        imdbId: details.imdbId ?? lookupId,
        mediaType: details.mediaType,
      )) {
        _myListCache.add(k);
      }
      final enriched = buildMyListMeta(
        baseMeta: baseMeta,
        details: details,
        tmdbId: details.tmdbId,
        imdbId: details.imdbId,
        mediaType: details.mediaType,
      );
      if (enriched != null) {
        _upsertMyListMeta(enriched, moveToFront: false);
        _notifyMyListListeners();
        unawaited(_persistInteractionsToDisk());
      }
    } catch (_) {
      // Non-fatal if offline; item will enrich on next sync.
    }
  }

  /// Synchronizes [_myListCache] with [_myListMetas], resolving any saved ID
  /// keys that do not yet have a cached [MetaModel] or `btttr.cc` Better Poster.
  Future<List<MetaModel>> syncAndResolveMyList({CancelToken? cancelToken}) async {
    await ensureInteractionsLoaded();

    // Normalize existing metas with any newly learned IMDb IDs and ensure their
    // interaction keys are registered in _myListCache (never drop metas with unbridged IDs).
    var changed = false;
    for (var i = 0; i < _myListMetas.length; i++) {
      final current = _myListMetas[i];
      final normalized = _normalizeMyListMeta(current);
      if (normalized != current) {
        _myListMetas[i] = normalized;
        changed = true;
      }
      for (final k in _keysForMeta(_myListMetas[i])) {
        if (_myListCache.add(k)) changed = true;
      }
    }

    // Collect any keys in _myListCache not yet represented in _myListMetas.
    final coveredKeys = <String>{
      for (final m in _myListMetas) ..._keysForMeta(m),
    };
    final unresolvedKeys = _myListCache.where((k) => !coveredKeys.contains(k)).toList()
      // Prefer ':imdb:' keys first so resolving one also registers its ':tmdb:' pair.
      ..sort((a, b) {
        final aImdb = a.contains(':imdb:') ? 0 : 1;
        final bImdb = b.contains(':imdb:') ? 0 : 1;
        return aImdb.compareTo(bImdb);
      });

    for (final key in unresolvedKeys) {
      if (cancelToken?.isCancelled ?? false) break;
      final latestCovered = <String>{
        for (final m in _myListMetas) ..._keysForMeta(m),
      };
      if (latestCovered.contains(key)) continue;

      final parts = key.split(':');
      if (parts.length < 3) continue;
      final mediaType = parts[0];
      final rawId = parts.sublist(2).join(':');
      try {
        final details = await fetchCoreDetails(
          rawId,
          type: mediaType,
          cancelToken: cancelToken,
        );
        if (!_myListCache.contains(key)) continue;
        for (final k in _interactionKeys(
          tmdbId: details.tmdbId,
          imdbId: details.imdbId ?? rawId,
          mediaType: details.mediaType,
        )) {
          _myListCache.add(k);
        }
        final built = buildMyListMeta(
          details: details,
          tmdbId: details.tmdbId,
          imdbId: details.imdbId,
          mediaType: details.mediaType,
        );
        if (built != null) {
          _upsertMyListMeta(built, moveToFront: false);
          changed = true;
          _notifyMyListListeners();
        }
      } catch (_) {
        // Keep going if an individual item fails to resolve.
      }
    }

    // Also upgrade any existing item in _myListMetas that still has a numeric TMDB ID
    // so it receives its IMDb ID and `btttr.cc` Better Poster URL.
    final numericItems = _myListMetas.where((m) => !m.id.startsWith('tt')).toList();
    for (final item in numericItems) {
      if (cancelToken?.isCancelled ?? false) break;
      try {
        final details = await fetchCoreDetails(
          item.id,
          type: item.type,
          cancelToken: cancelToken,
        );
        final built = buildMyListMeta(
          baseMeta: item,
          details: details,
          tmdbId: details.tmdbId,
          imdbId: details.imdbId,
          mediaType: details.mediaType,
        );
        if (built != null && built != item) {
          _upsertMyListMeta(built, moveToFront: false);
          changed = true;
          _notifyMyListListeners();
        }
      } catch (_) {}
    }

    if (changed) {
      unawaited(_persistInteractionsToDisk());
    }
    return getCachedMyListMetas();
  }

  /// Synchronizes liked keys in [_ratingsCache] (`rating >= 5.0`) with [_likedMetas].
  Future<List<MetaModel>> syncAndResolveLikes({CancelToken? cancelToken}) async {
    await ensureInteractionsLoaded();

    _likedMetas.removeWhere(isMetaDisliked);

    var changed = false;
    for (var i = 0; i < _likedMetas.length; i++) {
      final current = _likedMetas[i];
      final normalized = _normalizeMyListMeta(current);
      if (normalized != current) {
        _likedMetas[i] = normalized;
        changed = true;
      }
      for (final k in _keysForMeta(_likedMetas[i])) {
        if (!_ratingsCache.containsKey(k)) {
          _ratingsCache[k] = 8.5;
          changed = true;
        }
      }
    }

    final coveredKeys = <String>{
      for (final m in _likedMetas) ..._keysForMeta(m),
    };
    final likedKeys = _ratingsCache.entries
        .where((e) => e.value >= 5.0 && !coveredKeys.contains(e.key))
        .map((e) => e.key)
        .toList()
      ..sort((a, b) {
        final aImdb = a.contains(':imdb:') ? 0 : 1;
        final bImdb = b.contains(':imdb:') ? 0 : 1;
        return aImdb.compareTo(bImdb);
      });

    for (final key in likedKeys) {
      if (cancelToken?.isCancelled ?? false) break;
      final latestCovered = <String>{
        for (final m in _likedMetas) ..._keysForMeta(m),
      };
      if (latestCovered.contains(key)) continue;

      final parts = key.split(':');
      if (parts.length < 3) continue;
      final mediaType = parts[0];
      final rawId = parts.sublist(2).join(':');
      final savedRating = _ratingsCache[key];
      if (savedRating == null || savedRating < 5.0) continue;

      try {
        final details = await fetchCoreDetails(
          rawId,
          type: mediaType,
          cancelToken: cancelToken,
        );
        for (final k in _interactionKeys(
          tmdbId: details.tmdbId,
          imdbId: details.imdbId ?? rawId,
          mediaType: details.mediaType,
        )) {
          _ratingsCache[k] = savedRating;
        }
        final built = buildMyListMeta(
          details: details,
          tmdbId: details.tmdbId,
          imdbId: details.imdbId,
          mediaType: details.mediaType,
        );
        if (built != null) {
          _upsertLikedMeta(built, moveToFront: false);
          changed = true;
          _notifyMyListListeners();
        }
      } catch (_) {}
    }

    if (changed) {
      unawaited(_persistInteractionsToDisk());
    }
    return getCachedLikedMetas();
  }

  /// Fetches an additional page from TMDB's `/{movie|tv}/{id}/recommendations`
  /// endpoint.
  Future<List<TmdbRecommendation>> fetchRecommendationsPage(
    int tmdbId,
    String mediaType, {
    int page = 2,
    CancelToken? cancelToken,
  }) async {
    final normType = _normalizeType(mediaType);
    final resource = _resourceFor(normType);
    try {
      final json = await _getJson(
        '/$resource/$tmdbId/recommendations',
        {'page': page},
        cancelToken: cancelToken,
      );
      return _parseRecommendations(
        json['results'],
        defaultMediaType: normType,
        now: currentNow,
      );
    } catch (_) {
      return const [];
    }
  }

  /// Queries TMDB's `/discover/{movie|tv}` endpoint using thematic keywords,
  /// genres, and quality/recency gates for content-based recommendation mixing.
  Future<List<TmdbRecommendation>> fetchDiscoverRecommendations({
    required String mediaType,
    List<int> genreIds = const [],
    List<int> keywordIds = const [],
    int? minReleaseYear,
    int minVoteCount = 200,
    double minVoteAverage = 6.4,
    String? originalLanguage,
    bool excludeAnimation = false,
    CancelToken? cancelToken,
  }) async {
    if (genreIds.isEmpty && keywordIds.isEmpty) return const [];
    final normType = _normalizeType(mediaType);
    final resource = _resourceFor(normType);
    final todayKey = _formatCategoryDayKey(_clock?.call() ?? DateTime.now());
    final query = <String, dynamic>{
      'sort_by': 'popularity.desc',
      'vote_count.gte': minVoteCount,
      'vote_average.gte': minVoteAverage,
      'include_adult': false,
      normType == 'series' ? 'first_air_date.lte' : 'primary_release_date.lte':
          todayKey,
      'page': 1,
    };
    if (genreIds.isNotEmpty) {
      query['with_genres'] = genreIds.take(2).join(',');
    }
    if (keywordIds.isNotEmpty) {
      query['with_keywords'] = keywordIds.take(5).join('|');
    }
    if (minReleaseYear != null) {
      query[normType == 'series' ? 'first_air_date.gte' : 'primary_release_date.gte'] =
          '$minReleaseYear-01-01';
    }
    if (excludeAnimation) {
      query['without_genres'] = '16';
    }
    if (originalLanguage != null &&
        originalLanguage.trim().isNotEmpty &&
        originalLanguage.trim().toLowerCase() != 'en') {
      query['with_original_language'] = originalLanguage.trim().toLowerCase();
    }
    try {
      final json = await _getJson(
        '/discover/$resource',
        query,
        cancelToken: cancelToken,
      );
      return _parseRecommendations(
        json['results'],
        defaultMediaType: normType,
        now: currentNow,
      );
    } catch (_) {
      return const [];
    }
  }

  /// Returns a frequency map of genres associated with titles the user has
  /// marked "Not for me" (`rating < 5.0`) among loaded core/full details.
  Map<String, int> getDislikedGenresSnapshot({bool isAnime = false}) {
    final counts = <String, int>{};
    final visited = <String>{};
    for (final d in [..._memo.values, ..._coreMemo.values]) {
      final idKey = '${d.mediaType}:${d.tmdbId}';
      if (!visited.add(idKey)) continue;
      final itemIsAnime = d.isJapaneseAnimation ||
          _hasAnimeSignal(tmdbId: d.tmdbId, imdbId: d.imdbId, mediaType: d.mediaType);
      if (itemIsAnime != isAnime) continue;
      final rating = getCachedUserRating(
        tmdbId: d.tmdbId,
        imdbId: d.imdbId,
        mediaType: d.mediaType,
      );
      if (rating != null && rating > 0 && rating < kTmdbHalfRatingThreshold) {
        for (final g in d.genres) {
          counts[g] = (counts[g] ?? 0) + 1;
        }
      }
    }
    return counts;
  }

  /// Resolves personalized card artwork (`/{movie|tv}/{id}/images?include_image_language=en,null`):
  /// - `tallPosterUrl`: **strict** textless poster (`iso_639_1 == null` only; returns `null` if none exists so baked-in text is never cropped).
  /// - `landscapeBackdropUrl`: language-neutral 16:9 backdrop (`iso_639_1 == null` preferred).
  /// - `logoUrl` & `logoAspectRatio`: official English/neutral transparent PNG logo + its exact `width / height` aspect ratio.
  Future<PersonalizedArtwork> fetchPersonalizedCardArtwork(
    int tmdbId,
    String mediaType, {
    CancelToken? cancelToken,
  }) {
    final normType = _normalizeType(mediaType);
    final key = '$normType:$tmdbId';
    final cached = _personalizedArtworkCache[key];
    if (cached != null) return Future.value(cached);

    return _inflightPersonalizedArtwork.putIfAbsent(key, () async {
      try {
        final resource = _resourceFor(normType);
        Map<String, dynamic> detailsJson = const {};
        Map<String, dynamic> imagesJson = const {};

        try {
          final appended = await _getJson(
            '/$resource/$tmdbId',
            {
              'append_to_response': normType == 'series'
                  ? 'images,content_ratings,credits'
                  : 'images,release_dates,credits',
              'include_image_language': 'en,null',
            },
            cancelToken: cancelToken,
          );
          detailsJson = appended;
          if (appended['images'] is Map<String, dynamic>) {
            imagesJson = appended['images'] as Map<String, dynamic>;
          } else if (appended['posters'] is List || appended['backdrops'] is List) {
            imagesJson = appended;
          }
        } catch (_) {}

        if (imagesJson.isEmpty) {
          imagesJson = await _getJson(
            '/$resource/$tmdbId/images',
            const {'include_image_language': 'en,null'},
            cancelToken: cancelToken,
          );
        }

        final posters = _maps(imagesJson['posters']);
        final backdrops = _maps(imagesJson['backdrops']);
        final logos = _maps(imagesJson['logos']);

        // Strict textless poster: only iso_639_1 == null or empty, ranked by
        // PostersPlus clean_notch competitive selection (tmdb.py:323-346).
        final bestTallPoster = _selectTextlessPoster(posters);

        // Best standard poster (English preferred) as fallback when no textless poster exists.
        final bestStandardPoster = _bestImage(posters, preferEnglish: true);

        // Clean textless backdrop preferred for landscape card.
        final bestBackdrop = _bestImage(backdrops, textless: true);

        // Prefer English PNG logo, falling back to language-neutral logo.
        final enLogos = logos
            .where((i) => i['iso_639_1'] == 'en' && !_str(i['file_path']).endsWith('.svg'))
            .toList();
        final neutralLogos = logos
            .where((i) => i['iso_639_1'] == null && !_str(i['file_path']).endsWith('.svg'))
            .toList();
        final bestLogo = enLogos.isNotEmpty
            ? _bestImage(enLogos, preferEnglish: true)
            : (neutralLogos.isNotEmpty ? _bestImage(neutralLogos, textless: true) : null);

        double? logoAspect = (bestLogo?['aspect_ratio'] as num?)?.toDouble();
        if (logoAspect == null &&
            bestLogo?['width'] is num &&
            bestLogo?['height'] is num &&
            (bestLogo!['height'] as num) > 0) {
          logoAspect = (bestLogo['width'] as num).toDouble() /
              (bestLogo['height'] as num).toDouble();
        }

        final ageRating = _extractAgeRating(detailsJson, normType);
        final notchText = _resolveCleanNotchBadge(tmdbId, normType, detailsJson);

        final result = (
          tallPosterUrl: _img(bestTallPoster?['file_path'], 'w500'),
          standardPosterUrl: _img(bestStandardPoster?['file_path'], 'w500'),
          landscapeBackdropUrl: _img(bestBackdrop?['file_path'], 'w780'),
          logoUrl: _img(bestLogo?['file_path'], 'w500'),
          logoAspectRatio: logoAspect,
          ageRating: ageRating,
          notchText: notchText,
        );
        _personalizedArtworkCache[key] = result;
        return result;
      } catch (_) {
        const empty = (
          tallPosterUrl: null,
          standardPosterUrl: null,
          landscapeBackdropUrl: null,
          logoUrl: null,
          logoAspectRatio: null,
          ageRating: null,
          notchText: null,
        );
        return empty;
      } finally {
        _inflightPersonalizedArtwork.remove(key);
      }
    });
  }

  /// Clears cached TMDB standard, category, and collection catalogs on pull-to-refresh.
  void clearCategoryCache() {
    _categoryCatalogsCache = null;
    _categoryCatalogItemsCache.clear();
    _standardCatalogItemsCache.clear();
    _collectionCatalogItemsCache.clear();
  }

  /// The 10 official TMDB standard catalog rows (5 Movies + 5 TV Series),
  /// strictly interleaved (`1 Movie -> 1 Series`) so Home shows all 10 rows
  /// while Movies and TV Shows filter cleanly to their respective 5 rows.
  static const List<({String id, String type, String name, String endpoint})>
      _standardCatalogConfigs = [
    (
      id: 'tmdb.standard.trending_movie',
      type: 'movie',
      name: 'Trending Movies Today',
      endpoint: '/trending/movie/day',
    ),
    (
      id: 'tmdb.standard.trending_tv',
      type: 'series',
      name: 'Trending Series Today',
      endpoint: '/trending/tv/day',
    ),
    (
      id: 'tmdb.standard.popular_movie',
      type: 'movie',
      name: 'Popular Movies',
      endpoint: '/movie/popular',
    ),
    (
      id: 'tmdb.standard.popular_tv',
      type: 'series',
      name: 'Popular Series',
      endpoint: '/tv/popular',
    ),
    (
      id: 'tmdb.standard.top_rated_movie',
      type: 'movie',
      name: 'Top Rated Movies',
      endpoint: '/movie/top_rated',
    ),
    (
      id: 'tmdb.standard.top_rated_tv',
      type: 'series',
      name: 'Top Rated Series',
      endpoint: '/tv/top_rated',
    ),
    (
      id: 'tmdb.standard.now_playing_movie',
      type: 'movie',
      name: 'Now Playing in Theaters',
      endpoint: '/movie/now_playing',
    ),
    (
      id: 'tmdb.standard.airing_today_tv',
      type: 'series',
      name: 'Airing Today',
      endpoint: '/tv/airing_today',
    ),
    (
      id: 'tmdb.standard.upcoming_movie',
      type: 'movie',
      name: 'Upcoming Movies',
      endpoint: '/movie/upcoming',
    ),
    (
      id: 'tmdb.standard.on_the_air_tv',
      type: 'series',
      name: 'On The Air',
      endpoint: '/tv/on_the_air',
    ),
  ];

  /// Returns the 10 interleaved TMDB standard catalog descriptors for Home,
  /// Movies, and TV Shows.
  List<CatalogItemModel> getStandardCatalogs() => [
        for (final cfg in _standardCatalogConfigs)
          CatalogItemModel(
            id: cfg.id,
            type: cfg.type,
            name: cfg.name,
          ),
      ];

  /// Fetches a single TMDB standard catalog row (`/trending/*`, `/movie/*`, `/tv/*`)
  /// using the exact same Daily Fresh High-Quality Cohort Engine and 2-wave
  /// `btttr.cc` Better Poster resolution as [fetchCategoryCatalog].
  Future<List<MetaModel>> fetchStandardCatalog(
    CatalogItemModel catalog, {
    CancelToken? cancelToken,
    DateTime? now,
    void Function(List<MetaModel>)? onWave2Enriched,
  }) {
    final refNow = now ?? currentNow;
    final todayKey = _formatCategoryDayKey(refNow);
    final yesterdayKey = _formatCategoryDayKey(
      refNow.subtract(const Duration(days: 1)),
    );
    final cacheKey = '$todayKey|${catalog.key}';
    final cached = _standardCatalogItemsCache[cacheKey];
    if (cached != null && cached.isNotEmpty) return Future.value(cached);

    return _inflightStandardCatalogs.putIfAbsent(cacheKey, () async {
      try {
        await ensureInteractionsLoaded();
        final isSeries = catalog.type == 'series';
        final normType = isSeries ? 'series' : 'movie';
        final cfg = _standardCatalogConfigs.firstWhere(
          (c) => c.id == catalog.id,
          orElse: () => (
            id: catalog.id,
            type: normType,
            name: catalog.name,
            endpoint: isSeries ? '/tv/popular' : '/movie/popular',
          ),
        );

        final rotatingPage = 3 + (_categoryDailyHash('$todayKey|${catalog.key}|page') % 3);

        Map<String, dynamic> buildQuery(int page) => {
              'language': 'en-US',
              'page': '$page',
            };

        final pages = await Future.wait([
          _getJson(cfg.endpoint, buildQuery(1), cancelToken: cancelToken),
          _getJson(cfg.endpoint, buildQuery(2), cancelToken: cancelToken)
              .catchError((_) => const <String, dynamic>{}),
          _getJson(cfg.endpoint, buildQuery(rotatingPage), cancelToken: cancelToken)
              .catchError((_) => const <String, dynamic>{}),
        ]);

        final combinedRaw = <Map<String, dynamic>>[
          ..._maps(pages[0]['results']),
          ..._maps(pages[1]['results']),
          ..._maps(pages[2]['results']),
        ];

        final validPool = <Map<String, dynamic>>[];
        final seenTmdbIds = <int>{};
        for (final r in combinedRaw) {
          final tmdbId = (r['id'] as num?)?.toInt();
          final posterPath = _str(r['poster_path']);
          final title = isSeries
              ? (_str(r['name']).isNotEmpty ? _str(r['name']) : _str(r['original_name']))
              : (_str(r['title']).isNotEmpty ? _str(r['title']) : _str(r['original_title']));
          if (tmdbId == null || posterPath.isEmpty || title.isEmpty) continue;
          if (!_isTmdbItemReleased(r, isSeries: isSeries, now: refNow)) continue;
          if (!seenTmdbIds.add(tmdbId)) continue;
          final probeMeta = MetaModel(id: '$tmdbId', type: normType, name: title);
          if (isMetaDisliked(probeMeta)) continue;
          validPool.add(r);
        }

        // For non-trending standard endpoints, sort pool by popularity descending;
        // for daily trending, preserve TMDB's velocity rank order across pages.
        if (!cfg.endpoint.startsWith('/trending/')) {
          validPool.sort((a, b) {
            final popA = (a['popularity'] as num?)?.toDouble() ?? 0.0;
            final popB = (b['popularity'] as num?)?.toDouble() ?? 0.0;
            return popB.compareTo(popA);
          });
        }

        final validItems = _selectDailyCategoryCohort(
          pool: validPool,
          catalogKey: catalog.key,
          todayKey: todayKey,
          yesterdayKey: yesterdayKey,
          targetCount: 20,
        );

        final wave1Count = validItems.length < kViewportPriorityCount
            ? validItems.length
            : kViewportPriorityCount;
        await Future.wait([
          for (var i = 0; i < wave1Count; i++)
            _resolveImdbId(
              (validItems[i]['id'] as num).toInt(),
              mediaType: normType,
              cancelToken: cancelToken,
            ),
        ]);

        List<MetaModel> buildShelfMetas() {
          final list = <MetaModel>[];
          for (final r in validItems) {
            final tmdbId = (r['id'] as num).toInt();
            final imdbId = _cachedImdbFor(tmdbId, normType);
            final id = (imdbId != null && imdbId.isNotEmpty) ? imdbId : '$tmdbId';
            final title = isSeries
                ? (_str(r['name']).isNotEmpty ? _str(r['name']) : _str(r['original_name']))
                : (_str(r['title']).isNotEmpty ? _str(r['title']) : _str(r['original_title']));
            final tmdbPoster = _img(_str(r['poster_path']), 'w342');
            final tmdbBackdrop = _img(_str(r['backdrop_path']), 'w780');
            final poster = (imdbId != null && imdbId.isNotEmpty)
                ? betterPosterUrl(imdbId)
                : tmdbPoster;
            final rawDate = isSeries ? _str(r['first_air_date']) : _str(r['release_date']);
            final year = rawDate.length >= 4 ? rawDate.substring(0, 4) : null;
            final voteAvg = (r['vote_average'] as num?)?.toDouble();
            final rating = (voteAvg != null && voteAvg > 0)
                ? (voteAvg >= 10.0 ? '10' : voteAvg.toStringAsFixed(1))
                : null;
            final genres = _resolveGenresFromIds(r['genre_ids']);
            final overview = _str(r['overview']).trim();

            final meta = MetaModel(
              id: id,
              type: normType,
              name: title,
              poster: poster,
              posterFallback: tmdbPoster,
              background: tmdbBackdrop ?? tmdbPoster,
              landscapePoster: tmdbBackdrop,
              description: overview.isNotEmpty ? overview : null,
              genres: genres.isNotEmpty ? genres : [catalog.name],
              releaseInfo: year,
              imdbRating: rating,
            );

            if (!isMetaDisliked(meta)) {
              list.add(meta);
            }
          }
          return list;
        }

        final metas = buildShelfMetas();
        _standardCatalogItemsCache[cacheKey] = metas;

        // Wave 2: Resolve remaining off-screen IMDb IDs in bounded batches of 8
        // and patch the shelf with upgraded `btttr.cc` Better Posters.
        if (validItems.length > wave1Count) {
          unawaited(() async {
            for (var i = wave1Count; i < validItems.length; i += kMaxBackgroundConcurrency) {
              if (cancelToken?.isCancelled ?? false) return;
              final end = (i + kMaxBackgroundConcurrency < validItems.length)
                  ? i + kMaxBackgroundConcurrency
                  : validItems.length;
              await Future.wait([
                for (var j = i; j < end; j++)
                  _resolveImdbId(
                    (validItems[j]['id'] as num).toInt(),
                    mediaType: normType,
                    cancelToken: cancelToken,
                  ),
              ]);
            }
            if (cancelToken?.isCancelled ?? false) return;
            final upgraded = buildShelfMetas();
            _standardCatalogItemsCache[cacheKey] = upgraded;
            onWave2Enriched?.call(upgraded);
          }());
        }

        return metas;
      } finally {
        _inflightStandardCatalogs.remove(cacheKey);
      }
    });
  }

  /// Curated priority ordering of official TMDB Movie genres so the most popular
  /// categories appear first on the Categories and Collection Details screens.
  static const List<({int id, String name})> defaultMovieGenres = [
    (id: 28, name: 'Action'),
    (id: 35, name: 'Comedy'),
    (id: 18, name: 'Drama'),
    (id: 878, name: 'Sci-Fi'),
    (id: 53, name: 'Thriller'),
    (id: 80, name: 'Crime'),
    (id: 27, name: 'Horror'),
    (id: 12, name: 'Adventure'),
    (id: 10749, name: 'Romance'),
    (id: 14, name: 'Fantasy'),
    (id: 9648, name: 'Mystery'),
    (id: 16, name: 'Animation'),
    (id: 10751, name: 'Family'),
    (id: 99, name: 'Documentary'),
    (id: 36, name: 'History'),
    (id: 10752, name: 'War'),
    (id: 10402, name: 'Music'),
    (id: 37, name: 'Western'),
  ];

  /// Curated priority ordering of official TMDB TV Series genres.
  static const List<({int id, String name})> defaultSeriesGenres = [
    (id: 10759, name: 'Action & Adventure'),
    (id: 35, name: 'Comedy'),
    (id: 18, name: 'Drama'),
    (id: 10765, name: 'Sci-Fi & Fantasy'),
    (id: 80, name: 'Crime'),
    (id: 9648, name: 'Mystery'),
    (id: 16, name: 'Animation'),
    (id: 10751, name: 'Family'),
    (id: 99, name: 'Documentary'),
    (id: 10764, name: 'Reality'),
    (id: 10768, name: 'War & Politics'),
    (id: 37, name: 'Western'),
    (id: 10762, name: 'Kids'),
    (id: 10766, name: 'Soap'),
    (id: 10767, name: 'Talk'),
    (id: 10763, name: 'News'),
  ];

  /// Fetches actual TMDB Movie and TV Series categories (`/genre/movie/list` &
  /// `/genre/tv/list`, with curated fallback) and interleaves them strictly:
  /// 1 Movie row -> 1 Series row -> 1 Movie row -> 1 Series row.
  Future<List<CatalogItemModel>> fetchCategoryCatalogs({
    CancelToken? cancelToken,
  }) async {
    final cached = _categoryCatalogsCache;
    if (cached != null && cached.isNotEmpty) return cached;

    var movieGenres = List<({int id, String name})>.from(defaultMovieGenres);
    var seriesGenres = List<({int id, String name})>.from(defaultSeriesGenres);

    try {
      final responses = await Future.wait([
        _getJson('/genre/movie/list', const {'language': 'en-US'}, cancelToken: cancelToken)
            .catchError((_) => const <String, dynamic>{}),
        _getJson('/genre/tv/list', const {'language': 'en-US'}, cancelToken: cancelToken)
            .catchError((_) => const <String, dynamic>{}),
      ]);

      final fetchedMovies = _maps(responses[0]['genres']);
      if (fetchedMovies.isNotEmpty) {
        final byId = <int, String>{
          for (final g in fetchedMovies)
            if (g['id'] is num && _str(g['name']).trim().isNotEmpty)
              (g['id'] as num).toInt(): _str(g['name']).trim() == 'Science Fiction'
                  ? 'Sci-Fi'
                  : _str(g['name']).trim(),
        };
        final ordered = <({int id, String name})>[];
        for (final def in defaultMovieGenres) {
          final liveName = byId.remove(def.id);
          if (liveName != null) {
            ordered.add((id: def.id, name: liveName));
          }
        }
        for (final entry in byId.entries) {
          if (entry.key == 10770) continue; // skip TV Movie meta-tag
          ordered.add((id: entry.key, name: entry.value));
        }
        if (ordered.isNotEmpty) movieGenres = ordered;
      }

      final fetchedSeries = _maps(responses[1]['genres']);
      if (fetchedSeries.isNotEmpty) {
        final byId = <int, String>{
          for (final g in fetchedSeries)
            if (g['id'] is num && _str(g['name']).trim().isNotEmpty)
              (g['id'] as num).toInt(): _str(g['name']).trim(),
        };
        final ordered = <({int id, String name})>[];
        for (final def in defaultSeriesGenres) {
          final liveName = byId.remove(def.id);
          if (liveName != null) {
            ordered.add((id: def.id, name: liveName));
          }
        }
        for (final entry in byId.entries) {
          ordered.add((id: entry.key, name: entry.value));
        }
        if (ordered.isNotEmpty) seriesGenres = ordered;
      }
    } catch (_) {}

    final movieCatalogs = [
      for (final g in movieGenres)
        CatalogItemModel(
          id: 'tmdb.category.${g.id}',
          type: 'movie',
          name: g.name,
        ),
    ];
    final seriesCatalogs = [
      for (final g in seriesGenres)
        CatalogItemModel(
          id: 'tmdb.category.${g.id}',
          type: 'series',
          name: g.name,
        ),
    ];

    // Interleave strictly: 1 Movie row, then 1 Series row, then 1 Movie row, then 1 Series row.
    final interleaved = <CatalogItemModel>[];
    final maxLen = movieCatalogs.length > seriesCatalogs.length
        ? movieCatalogs.length
        : seriesCatalogs.length;
    for (var i = 0; i < maxLen; i++) {
      if (i < movieCatalogs.length) interleaved.add(movieCatalogs[i]);
      if (i < seriesCatalogs.length) interleaved.add(seriesCatalogs[i]);
    }

    _categoryCatalogsCache = interleaved;
    return interleaved;
  }

  /// Fetches a single TMDB category shelf (`/discover/movie` or `/discover/tv`)
  /// using the Daily Fresh High-Quality Category Discovery Engine:
  /// 1. Enforces rating (`vote_average.gte`) and vote-count (`vote_count.gte`) quality floors.
  /// 2. Fetches a multi-page elite pool (Pages 1, 2, and a daily rotating page 3..5).
  /// 3. Divides the elite popularity-sorted pool into 20 rank-stratified buckets and uses a
  ///    deterministic daily hash (`YYYY-MM-DD`) with anti-yesterday collision avoidance to
  ///    select 1 title per bucket — guaranteeing a fresh 20-title lineup every day.
  /// 4. Sorts the selected 20 titles strictly by `popularity` descending so the most popular
  ///    titles always appear first from left to right.
  Future<List<MetaModel>> fetchCategoryCatalog(
    CatalogItemModel catalog, {
    CancelToken? cancelToken,
    DateTime? now,
    void Function(List<MetaModel>)? onWave2Enriched,
  }) {
    final refNow = now ?? currentNow;
    final todayKey = _formatCategoryDayKey(refNow);
    final yesterdayKey = _formatCategoryDayKey(
      refNow.subtract(const Duration(days: 1)),
    );
    final cacheKey = '$todayKey|${catalog.key}';
    final cached = _categoryCatalogItemsCache[cacheKey];
    if (cached != null && cached.isNotEmpty) return Future.value(cached);

    return _inflightCategoryCatalogs.putIfAbsent(cacheKey, () async {
      try {
        await ensureInteractionsLoaded();
        final genreIdStr = catalog.id.replaceFirst('tmdb.category.', '').trim();
        final genreId = int.tryParse(genreIdStr) ?? 0;
        final isSeries = catalog.type == 'series';
        final endpoint = isSeries ? '/discover/tv' : '/discover/movie';

        // Narrower/specialty genres use a gentler vote-count floor so their pool stays deep.
        const nicheGenreIds = <int>{
          99, 36, 10402, 10752, 37, 10762, 10763, 10764, 10766, 10767, 10768,
        };
        final isNiche = nicheGenreIds.contains(genreId);
        final minVoteAverage = isNiche ? '5.8' : '6.4';
        final minVoteCount = isNiche ? '25' : (isSeries ? '70' : '140');

        // Rotate the 3rd page daily across pages 3, 4, and 5 so deeper acclaimed hits cycle in.
        final rotatingPage = 3 + (_categoryDailyHash('$todayKey|${catalog.key}|page') % 3);

        Map<String, dynamic> buildQuery(int page, {bool strictQuality = true}) => {
              'with_genres': genreIdStr,
              'sort_by': 'popularity.desc',
              'include_adult': 'false',
              isSeries ? 'first_air_date.lte' : 'primary_release_date.lte':
                  todayKey,
              if (strictQuality) 'vote_average.gte': minVoteAverage,
              if (strictQuality) 'vote_count.gte': minVoteCount,
              'page': '$page',
            };

        final pages = await Future.wait([
          _getJson(endpoint, buildQuery(1), cancelToken: cancelToken),
          _getJson(endpoint, buildQuery(2), cancelToken: cancelToken)
              .catchError((_) => const <String, dynamic>{}),
          _getJson(endpoint, buildQuery(rotatingPage), cancelToken: cancelToken)
              .catchError((_) => const <String, dynamic>{}),
        ]);

        var combinedRaw = <Map<String, dynamic>>[
          ..._maps(pages[0]['results']),
          ..._maps(pages[1]['results']),
          ..._maps(pages[2]['results']),
        ];

        // Fallback if a specialty genre returned too few titles under strict quality gates.
        if (combinedRaw.length < 20) {
          final fallbackPage = await _getJson(
            endpoint,
            buildQuery(1, strictQuality: false),
            cancelToken: cancelToken,
          ).catchError((_) => const <String, dynamic>{});
          combinedRaw = [...combinedRaw, ..._maps(fallbackPage['results'])];
        }

        final normType = isSeries ? 'series' : 'movie';
        final validPool = <Map<String, dynamic>>[];
        final seenTmdbIds = <int>{};
        for (final r in combinedRaw) {
          final tmdbId = (r['id'] as num?)?.toInt();
          final posterPath = _str(r['poster_path']);
          final title = isSeries
              ? (_str(r['name']).isNotEmpty ? _str(r['name']) : _str(r['original_name']))
              : (_str(r['title']).isNotEmpty ? _str(r['title']) : _str(r['original_title']));
          if (tmdbId == null || posterPath.isEmpty || title.isEmpty) continue;
          if (!_isTmdbItemReleased(r, isSeries: isSeries, now: refNow)) continue;
          if (!seenTmdbIds.add(tmdbId)) continue;
          final probeMeta = MetaModel(id: '$tmdbId', type: normType, name: title);
          if (isMetaDisliked(probeMeta)) continue;
          validPool.add(r);
        }

        // Sort the entire elite candidate pool strictly by popularity descending.
        validPool.sort((a, b) {
          final popA = (a['popularity'] as num?)?.toDouble() ?? 0.0;
          final popB = (b['popularity'] as num?)?.toDouble() ?? 0.0;
          return popB.compareTo(popA);
        });

        // Select today's 20 titles via rank-stratified buckets with anti-yesterday rotation,
        // then sort the selected 20 titles strictly by popularity descending.
        final validItems = _selectDailyCategoryCohort(
          pool: validPool,
          catalogKey: catalog.key,
          todayKey: todayKey,
          yesterdayKey: yesterdayKey,
          targetCount: 20,
        );

        // Resolve IMDb IDs for the first viewport wave (top 6 cards) so Better Poster
        // (`btttr.cc`) and IMDb-keyed hero artwork work immediately, and warm the rest in background.
        final wave1Count = validItems.length < kViewportPriorityCount
            ? validItems.length
            : kViewportPriorityCount;
        await Future.wait([
          for (var i = 0; i < wave1Count; i++)
            _resolveImdbId(
              (validItems[i]['id'] as num).toInt(),
              mediaType: normType,
              cancelToken: cancelToken,
            ),
        ]);

        // Warm remaining IMDb IDs in the background without blocking row render.
        if (validItems.length > wave1Count) {
          unawaited(() async {
            for (var i = wave1Count; i < validItems.length; i += kMaxBackgroundConcurrency) {
              if (cancelToken?.isCancelled ?? false) break;
              final end = (i + kMaxBackgroundConcurrency < validItems.length)
                  ? i + kMaxBackgroundConcurrency
                  : validItems.length;
              await Future.wait([
                for (var j = i; j < end; j++)
                  _resolveImdbId(
                    (validItems[j]['id'] as num).toInt(),
                    mediaType: normType,
                    cancelToken: cancelToken,
                  ),
              ]);
            }
            if (cancelToken?.isCancelled ?? false) return;
            final enrichedMetas = _buildCatalogRowMetas(
              validItems: validItems,
              isSeries: isSeries,
              normType: normType,
              fallbackGenreName: catalog.name,
            );
            _categoryCatalogItemsCache[cacheKey] = enrichedMetas;
            onWave2Enriched?.call(enrichedMetas);
          }());
        }

        final metas = _buildCatalogRowMetas(
          validItems: validItems,
          isSeries: isSeries,
          normType: normType,
          fallbackGenreName: catalog.name,
        );

        _categoryCatalogItemsCache[cacheKey] = metas;
        return metas;
      } finally {
        _inflightCategoryCatalogs.remove(cacheKey);
      }
    });
  }

  List<MetaModel> _buildCatalogRowMetas({
    required List<Map<String, dynamic>> validItems,
    required bool isSeries,
    required String normType,
    required String fallbackGenreName,
  }) {
    final list = <MetaModel>[];
    for (final r in validItems) {
      final tmdbId = (r['id'] as num).toInt();
      final imdbId = _cachedImdbFor(tmdbId, normType);
      final id = (imdbId != null && imdbId.isNotEmpty) ? imdbId : '$tmdbId';
      final title = isSeries
          ? (_str(r['name']).isNotEmpty ? _str(r['name']) : _str(r['original_name']))
          : (_str(r['title']).isNotEmpty ? _str(r['title']) : _str(r['original_title']));
      final tmdbPoster = _img(_str(r['poster_path']), 'w342');
      final tmdbBackdrop = _img(_str(r['backdrop_path']), 'w780');
      final poster = (imdbId != null && imdbId.isNotEmpty)
          ? betterPosterUrl(imdbId)
          : tmdbPoster;
      final rawDate = isSeries ? _str(r['first_air_date']) : _str(r['release_date']);
      final year = rawDate.length >= 4 ? rawDate.substring(0, 4) : null;
      final voteAvg = (r['vote_average'] as num?)?.toDouble();
      final rating = (voteAvg != null && voteAvg > 0)
          ? (voteAvg >= 10.0 ? '10' : voteAvg.toStringAsFixed(1))
          : null;
      final genres = _resolveGenresFromIds(r['genre_ids']);
      final overview = _str(r['overview']).trim();

      final meta = MetaModel(
        id: id,
        type: normType,
        name: title,
        poster: poster,
        posterFallback: tmdbPoster,
        background: tmdbBackdrop ?? tmdbPoster,
        landscapePoster: tmdbBackdrop,
        description: overview.isNotEmpty ? overview : null,
        genres: genres.isNotEmpty ? genres : [fallbackGenreName],
        releaseInfo: year,
        imdbRating: rating,
      );

      if (!isMetaDisliked(meta)) {
        list.add(meta);
      }
    }
    return list;
  }

  static String _formatCategoryDayKey(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static int _categoryDailyHash(String input) {
    var hash = 0x811c9dc5;
    for (var i = 0; i < input.length; i++) {
      hash ^= input.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }

  /// Selects [targetCount] titles from the popularity-sorted [pool] by partitioning
  /// [pool] into [targetCount] popularity-rank buckets, picking 1 title per bucket
  /// using [todayKey] while avoiding [yesterdayKey]'s pick in each bucket, and finally
  /// sorting the selected cohort strictly by popularity descending.
  static List<Map<String, dynamic>> _selectDailyCategoryCohort({
    required List<Map<String, dynamic>> pool,
    required String catalogKey,
    required String todayKey,
    required String yesterdayKey,
    int targetCount = 20,
  }) {
    if (pool.length <= targetCount) return List<Map<String, dynamic>>.from(pool);

    final selected = <Map<String, dynamic>>[];
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
        final yIdx = _categoryDailyHash('$yesterdayKey|$catalogKey|b:$b') % bucketSize;
        var tIdx = _categoryDailyHash('$todayKey|$catalogKey|b:$b') % bucketSize;
        if (tIdx == yIdx) {
          tIdx = (tIdx + 1) % bucketSize;
        }
        selected.add(pool[start + tIdx]);
      }
    }

    // Ensure final 20-title row is strictly ordered by popularity descending (most popular first).
    selected.sort((a, b) {
      final popA = (a['popularity'] as num?)?.toDouble() ?? 0.0;
      final popB = (b['popularity'] as num?)?.toDouble() ?? 0.0;
      return popB.compareTo(popA);
    });
    return selected;
  }

  /// Fetches a premade collection or OTT genre row from TMDB, applying the Daily
  /// Fetches the signed-in user's custom TMDB v3 lists (`/account/{id}/lists`)
  /// and maps each non-empty list into a [CollectionFolderModel] for the
  /// Collections tab. Returns an empty list when unauthenticated or if the user
  /// has not created any custom lists yet.
  Future<List<CollectionFolderModel>> fetchUserCustomListFolders({
    CancelToken? cancelToken,
  }) async {
    try {
      await ensureInteractionsLoaded();
      final sessionId = _userSessionId;
      if (sessionId == null || sessionId.isEmpty) return const [];
      var accountId = _accountProfile?.id;
      if (accountId == null || accountId <= 0) {
        final ok = await _verifyOrExpireSessionOn401(
          sessionId,
          cancelToken: cancelToken,
        );
        if (ok) accountId = _accountProfile?.id;
      }
      if (accountId == null || accountId <= 0) return const [];

      final json = await _getJson(
        '/account/$accountId/lists',
        {'session_id': sessionId, 'page': '1'},
        cancelToken: cancelToken,
      );
      final rawLists = _maps(json['results']);
      if (rawLists.isEmpty) return const [];

      final folders = <CollectionFolderModel>[];
      for (final raw in rawLists) {
        final listId = (raw['id'] as num?)?.toInt();
        final name = _str(raw['name']);
        final itemCount = (raw['item_count'] as num?)?.toInt() ?? 0;
        if (listId == null || name.isEmpty || itemCount <= 0) continue;
        final backdropPath = _str(raw['backdrop_path']);
        final posterPath = _str(raw['poster_path']);
        final coverPath = backdropPath.isNotEmpty ? backdropPath : posterPath;
        final coverUrl = coverPath.isNotEmpty
            ? '${ApiConstants.tmdbImageUrl}/w780$coverPath'
            : null;
        folders.add(
          CollectionFolderModel(
            id: 'tmdb_user_list_$listId',
            title: name,
            hideTitle: false,
            coverImageUrl: coverUrl,
            heroBackdropUrl: coverUrl,
            sources: [
              CollectionCatalogSource(
                type: 'movie',
                addonId: 'org.themoviedb.v3',
                catalogId: 'tmdb_user_list_$listId',
                tmdbId: listId,
                provider: 'tmdb',
              ),
            ],
          ),
        );
      }
      return folders;
    } catch (_) {
      return const [];
    }
  }

  /// Fresh High-Quality Cohort Engine, popularity-descending ordering, `< 20`
  /// pruning (when [pruneIfUnder20] is true), and 2-wave `btttr.cc` Better Poster
  /// IMDb ID resolution.
  Future<List<MetaModel>> fetchCollectionCatalog({
    required String catalogKey,
    required String type,
    required String rowTitle,
    required String endpoint,
    required Map<String, dynamic> queryParameters,
    bool pruneIfUnder20 = false,
    int targetCount = 20,
    CancelToken? cancelToken,
    DateTime? now,
    void Function(List<MetaModel>)? onWave2Enriched,
  }) {
    final refNow = now ?? currentNow;
    final todayKey = _formatCategoryDayKey(refNow);
    final yesterdayKey = _formatCategoryDayKey(
      refNow.subtract(const Duration(days: 1)),
    );
    final cacheKey = '$todayKey|$catalogKey|$targetCount';
    final cached = _collectionCatalogItemsCache[cacheKey];
    if (cached != null) return Future.value(cached);

    return _inflightCollectionCatalogs.putIfAbsent(cacheKey, () async {
      try {
        await ensureInteractionsLoaded();
        final isSeries = type == 'series';
        final normType = isSeries ? 'series' : 'movie';

        var combinedRaw = <Map<String, dynamic>>[];
        if (endpoint.startsWith('/collection/')) {
          final colJson = await _getJson(
            endpoint,
            queryParameters,
            cancelToken: cancelToken,
          );
          combinedRaw = [
            ..._maps(colJson['parts']),
            ..._maps(colJson['results']),
          ];
        } else if (endpoint.startsWith('/list/')) {
          final listJson = await _getJson(
            endpoint,
            queryParameters,
            cancelToken: cancelToken,
          );
          combinedRaw = [
            ..._maps(listJson['items']),
            ..._maps(listJson['results']),
          ];
        } else {
          final dateLteKey =
              isSeries ? 'first_air_date.lte' : 'primary_release_date.lte';
          final effectiveQuery = Map<String, dynamic>.from(queryParameters);
          final existingLte = parseTmdbAirDate(effectiveQuery[dateLteKey]?.toString());
          final todayRef = DateTime(refNow.year, refNow.month, refNow.day);
          if (existingLte == null || existingLte.isAfter(todayRef)) {
            effectiveQuery[dateLteKey] = todayKey;
          }

          final rotatingPage =
              3 + (_categoryDailyHash('$todayKey|$catalogKey|page') % 3);
          Map<String, dynamic> buildPageQuery(int page) => {
                ...effectiveQuery,
                'page': '$page',
              };
          final pages = await Future.wait([
            _getJson(endpoint, buildPageQuery(1), cancelToken: cancelToken),
            _getJson(endpoint, buildPageQuery(2), cancelToken: cancelToken)
                .catchError((_) => const <String, dynamic>{}),
            _getJson(
              endpoint,
              buildPageQuery(rotatingPage),
              cancelToken: cancelToken,
            ).catchError((_) => const <String, dynamic>{}),
          ]);
          combinedRaw = [
            ..._maps(pages[0]['results']),
            ..._maps(pages[1]['results']),
            ..._maps(pages[2]['results']),
          ];

          final hasStrictGates = effectiveQuery.containsKey('vote_count.gte') ||
              effectiveQuery.containsKey('vote_average.gte') ||
              effectiveQuery.containsKey('primary_release_date.gte') ||
              effectiveQuery.containsKey('first_air_date.gte');
          if (!pruneIfUnder20 &&
              combinedRaw.length < targetCount &&
              hasStrictGates) {
            final relaxedQuery = Map<String, dynamic>.from(effectiveQuery)
              ..remove('vote_count.gte')
              ..remove('vote_average.gte')
              ..remove('primary_release_date.gte')
              ..remove('first_air_date.gte')
              ..['page'] = '1';
            final fallbackPage = await _getJson(
              endpoint,
              relaxedQuery,
              cancelToken: cancelToken,
            ).catchError((_) => const <String, dynamic>{});
            combinedRaw = [
              ...combinedRaw,
              ..._maps(fallbackPage['results']),
            ];
          }
        }

        final validPool = <Map<String, dynamic>>[];
        final seenTmdbIds = <int>{};
        for (final r in combinedRaw) {
          final tmdbId = (r['id'] as num?)?.toInt();
          final posterPath = _str(r['poster_path']);
          final title = isSeries
              ? (_str(r['name']).isNotEmpty
                  ? _str(r['name'])
                  : _str(r['original_name']))
              : (_str(r['title']).isNotEmpty
                  ? _str(r['title'])
                  : _str(r['original_title']));
          if (tmdbId == null || posterPath.isEmpty || title.isEmpty) continue;
          if (!_isTmdbItemReleased(r, isSeries: isSeries, now: refNow)) continue;
          if (!seenTmdbIds.add(tmdbId)) continue;
          final probeMeta = MetaModel(id: '$tmdbId', type: normType, name: title);
          if (isMetaDisliked(probeMeta)) continue;
          validPool.add(r);
        }

        if (pruneIfUnder20 && validPool.length < 20) {
          _collectionCatalogItemsCache[cacheKey] = const <MetaModel>[];
          return const <MetaModel>[];
        }

        validPool.sort((a, b) {
          final popA = (a['popularity'] as num?)?.toDouble() ?? 0.0;
          final popB = (b['popularity'] as num?)?.toDouble() ?? 0.0;
          return popB.compareTo(popA);
        });

        final validItems = _selectDailyCategoryCohort(
          pool: validPool,
          catalogKey: catalogKey,
          todayKey: todayKey,
          yesterdayKey: yesterdayKey,
          targetCount: targetCount,
        );

        final wave1Count = validItems.length < kViewportPriorityCount
            ? validItems.length
            : kViewportPriorityCount;
        await Future.wait([
          for (var i = 0; i < wave1Count; i++)
            _resolveImdbId(
              (validItems[i]['id'] as num).toInt(),
              mediaType: normType,
              cancelToken: cancelToken,
            ),
        ]);

        if (validItems.length > wave1Count) {
          unawaited(() async {
            for (var i = wave1Count;
                i < validItems.length;
                i += kMaxBackgroundConcurrency) {
              if (cancelToken?.isCancelled ?? false) break;
              final end = (i + kMaxBackgroundConcurrency < validItems.length)
                  ? i + kMaxBackgroundConcurrency
                  : validItems.length;
              await Future.wait([
                for (var j = i; j < end; j++)
                  _resolveImdbId(
                    (validItems[j]['id'] as num).toInt(),
                    mediaType: normType,
                    cancelToken: cancelToken,
                  ),
              ]);
            }
            if (cancelToken?.isCancelled ?? false) return;
            final enrichedMetas = _buildCatalogRowMetas(
              validItems: validItems,
              isSeries: isSeries,
              normType: normType,
              fallbackGenreName: rowTitle,
            );
            _collectionCatalogItemsCache[cacheKey] = enrichedMetas;
            onWave2Enriched?.call(enrichedMetas);
          }());
        }

        final metas = _buildCatalogRowMetas(
          validItems: validItems,
          isSeries: isSeries,
          normType: normType,
          fallbackGenreName: rowTitle,
        );
        _collectionCatalogItemsCache[cacheKey] = metas;
        return metas;
      } finally {
        _inflightCollectionCatalogs.remove(cacheKey);
      }
    });
  }

  static const Set<int> _oscarWinnerTmdbIds = {
    496243, 545611, 872585, 1064213, 376867, 399055, 490132, 581734, 776503,
    314365, 194662, 76203, 68734, 74643, 45269, 12162, 12405, 6977, 1422,
    1640, 70, 122, 1574, 453, 98, 14, 1934, 597, 409, 197, 13, 424, 33,
    274, 581, 403, 380, 746, 792, 606, 279,
  };

  static const Set<int> _emmyWinnerTmdbIds = {
    1396, 1399, 76331, 136315, 126308, 97400, 87739, 87108, 65494, 74204,
    93405, 100088, 194764, 154385, 60059, 63247, 67136, 71578, 1402, 1418,
    2316, 4607, 1398, 4598, 1104,
  };

  static const Set<int> _globeWinnerTmdbIds = {
    313369, 424694, 530915, 693134, 792307, 76600, 674324, 94997, 119051,
  };

  static const Map<String, String> _prestigeDirectorBadges = {
    'christopher nolan': 'C. NOLAN',
    'denis villeneuve': 'D. VILLENEUVE',
    'martin scorsese': 'M. SCORSESE',
    'quentin tarantino': 'Q. TARANTINO',
    'david fincher': 'D. FINCHER',
    'steven spielberg': 'S. SPIELBERG',
    'hayao miyazaki': 'H. MIYAZAKI',
    'bong joon-ho': 'BONG JOON-HO',
    'bong joon ho': 'BONG JOON-HO',
    'guillermo del toro': 'G. DEL TORO',
    'ridley scott': 'R. SCOTT',
    'james cameron': 'J. CAMERON',
    'wes anderson': 'W. ANDERSON',
    'yorgos lanthimos': 'Y. LANTHIMOS',
    'alex garland': 'A. GARLAND',
    'robert eggers': 'R. EGGERS',
    'ari aster': 'A. ASTER',
    'jordan peele': 'J. PEELE',
    'greta gerwig': 'G. GERWIG',
    'park chan-wook': 'PARK CHAN-WOOK',
    'makoto shinkai': 'M. SHINKAI',
    'vince gilligan': 'V. GILLIGAN',
  };

  String? _extractAgeRating(Map<String, dynamic> details, String normType) {
    if (details.isEmpty) return null;
    const priorityCountries = ['US', 'GB', 'CA', 'AU', 'DE'];

    if (normType == 'series') {
      final ratingsBlock = details['content_ratings'];
      final results = ratingsBlock is Map<String, dynamic>
          ? _maps(ratingsBlock['results'])
          : const <Map<String, dynamic>>[];
      for (final iso in priorityCountries) {
        for (final r in results) {
          if (_str(r['iso_3166_1']).toUpperCase() == iso) {
            final normalized = _normalizeAgeCertification(_str(r['rating']), isSeries: true);
            if (normalized != null) return normalized;
          }
        }
      }
      for (final r in results) {
        final normalized = _normalizeAgeCertification(_str(r['rating']), isSeries: true);
        if (normalized != null) return normalized;
      }
    } else {
      final releasesBlock = details['release_dates'];
      final results = releasesBlock is Map<String, dynamic>
          ? _maps(releasesBlock['results'])
          : const <Map<String, dynamic>>[];
      for (final iso in priorityCountries) {
        for (final r in results) {
          if (_str(r['iso_3166_1']).toUpperCase() == iso) {
            for (final rd in _maps(r['release_dates'])) {
              final normalized = _normalizeAgeCertification(
                _str(rd['certification']),
                isSeries: false,
              );
              if (normalized != null) return normalized;
            }
          }
        }
      }
      for (final r in results) {
        for (final rd in _maps(r['release_dates'])) {
          final normalized = _normalizeAgeCertification(
            _str(rd['certification']),
            isSeries: false,
          );
          if (normalized != null) return normalized;
        }
      }
    }

    if (details['adult'] == true) {
      return normType == 'series' ? 'TV-MA' : 'R';
    }
    return null;
  }

  static String? _normalizeAgeCertification(String raw, {required bool isSeries}) {
    final clean = raw.trim().toUpperCase();
    if (clean.isEmpty ||
        clean == 'NR' ||
        clean == 'NOT RATED' ||
        clean == 'UNRATED' ||
        clean == 'N/A' ||
        clean == 'NONE') {
      return null;
    }
    switch (clean) {
      case 'G':
      case 'PG':
      case 'PG-13':
      case 'R':
      case 'NC-17':
      case 'TV-Y':
      case 'TV-Y7':
      case 'TV-G':
      case 'TV-PG':
      case 'TV-14':
      case 'TV-MA':
        return clean;
      case 'U':
      case '0':
      case 'ALL':
        return isSeries ? 'TV-G' : 'G';
      case '6':
      case '7':
        return isSeries ? 'TV-PG' : 'PG';
      case '12':
      case '12A':
      case '13':
      case '13+':
      case '14':
      case '14+':
      case '14A':
      case 'M':
      case 'MA':
        return isSeries ? 'TV-14' : 'PG-13';
      case '15':
      case '15+':
      case '16':
      case '16+':
      case 'MA15+':
      case 'MA 15+':
        return isSeries ? 'TV-MA' : 'R';
      case '18':
      case '18+':
      case '18A':
      case 'R18+':
        return isSeries ? 'TV-MA' : 'R';
      default:
        if (clean.length <= 6) return clean;
        return null;
    }
  }

  String? _resolveCleanNotchBadge(
    int tmdbId,
    String normType,
    Map<String, dynamic> details,
  ) {
    // 1. Major Awards (PostersPlus awards.py tier 1)
    if (normType == 'movie' && _oscarWinnerTmdbIds.contains(tmdbId)) {
      return '★  OSCAR WINNER';
    }
    if (normType == 'series' && _emmyWinnerTmdbIds.contains(tmdbId)) {
      return '★  EMMY WINNER';
    }
    if (_globeWinnerTmdbIds.contains(tmdbId)) {
      return '★  GLOBE WINNER';
    }
    if (details.isEmpty) return null;

    // 2. Timely Lifecycle (PostersPlus discovery.py tier 1)
    final now = DateTime.now();
    if (normType == 'series') {
      final nextEp = details['next_episode_to_air'];
      final lastAirStr = _str(details['last_air_date']);
      final lastAir = DateTime.tryParse(lastAirStr);
      if (nextEp is Map<String, dynamic>) {
        final nextAir = DateTime.tryParse(_str(nextEp['air_date']));
        if (nextAir != null && nextAir.difference(now).inDays.abs() <= 21) {
          return 'NEW EPISODE';
        }
      }
      if (lastAir != null && now.difference(lastAir).inDays.abs() <= 45) {
        return 'NEW SEASON';
      }
    } else {
      final relStr = _str(details['release_date']);
      final rel = DateTime.tryParse(relStr);
      if (rel != null && now.difference(rel).inDays >= 0 && now.difference(rel).inDays <= 60) {
        return 'NEW RELEASE';
      }
    }

    // 3. Prestige Studios / Networks (PostersPlus discovery.py tier 2)
    final companies = _maps(details['production_companies']);
    final networks = _maps(details['networks']);
    for (final n in [...networks, ...companies]) {
      final name = _str(n['name']).toLowerCase();
      if (name == 'a24' || name.startsWith('a24 ')) return 'A24';
      if (name == 'hbo' || name.contains('home box office')) return 'HBO ORIGINAL';
      if (name.contains('apple tv')) return 'APPLE TV+';
      if (name == 'fx' || name == 'fx networks') return 'FX ORIGINAL';
      if (name.contains('pixar')) return 'PIXAR';
      if (name.contains('studio ghibli')) return 'STUDIO GHIBLI';
      if (name.contains('marvel studios')) return 'MARVEL STUDIOS';
      if (name == 'neon') return 'NEON';
      if (name.contains('mappa')) return 'MAPPA';
      if (name.contains('ufotable')) return 'UFOTABLE';
      if (name.contains('kyoto animation')) return 'KYOTO ANIMATION';
      if (name.contains('wit studio')) return 'WIT STUDIO';
      if (name.contains('Searchlight Pictures'.toLowerCase())) return 'SEARCHLIGHT';
    }

    // 4. Prestige Directors / Creators (PostersPlus discovery.py tier 2)
    final credits = details['credits'];
    if (credits is Map<String, dynamic>) {
      for (final c in _maps(credits['crew'])) {
        if (_str(c['job']).toLowerCase() == 'director') {
          final dName = _str(c['name']).toLowerCase();
          final badge = _prestigeDirectorBadges[dName];
          if (badge != null) return badge;
        }
      }
    }
    for (final c in _maps(details['created_by'])) {
      final cName = _str(c['name']).toLowerCase();
      final badge = _prestigeDirectorBadges[cName];
      if (badge != null) return badge;
    }

    // 5. Acclaim & Structural Format (PostersPlus discovery.py tier 3)
    final voteAvg = (details['vote_average'] as num?)?.toDouble() ?? 0.0;
    final voteCount = (details['vote_count'] as num?)?.toInt() ?? 0;
    if (voteAvg >= 8.2 && voteCount >= 400) {
      return '★  MUST-SEE';
    }
    if (normType == 'series') {
      final showType = _str(details['type']).toLowerCase();
      final seasons = (details['number_of_seasons'] as num?)?.toInt() ?? 0;
      final episodes = (details['number_of_episodes'] as num?)?.toInt() ?? 0;
      final status = _str(details['status']).toLowerCase();
      if (showType.contains('miniseries') ||
          (seasons == 1 && status == 'ended' && episodes > 0 && episodes <= 12)) {
        return 'MINI SERIES';
      }
      if (status == 'ended' && seasons >= 2 && voteAvg >= 7.6) {
        return 'BINGE READY';
      }
    }
    if (voteAvg >= 7.8 && voteCount >= 250) {
      return 'CRITICS PICK';
    }
    final origLang = _str(details['original_language']).toLowerCase();
    if (origLang.isNotEmpty && origLang != 'en' && voteAvg >= 7.4) {
      switch (origLang) {
        case 'ko':
          return 'KOREAN HIT';
        case 'ja':
          return 'ANIME HIT';
        case 'fr':
          return 'FRENCH CINEMA';
        case 'es':
          return 'SPANISH HIT';
        default:
          return 'INTERNATIONAL';
      }
    }
    return null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TMDB v3 User Authentication & Account Sync
  // ─────────────────────────────────────────────────────────────────────────

  /// Builds the TMDB web approval URL for a given [requestToken].
  static String buildApprovalUrl(String requestToken) =>
      'https://www.themoviedb.org/authenticate/${requestToken.trim()}';

  /// TMDB request tokens stay valid for 60 minutes; we treat them as stale after 55.
  static const Duration kPendingAuthMaxAge = Duration(minutes: 55);

  File? _pendingAuthFile() {
    final interactions = _resolveInteractionsFile();
    if (interactions == null) return null;
    return File('${interactions.parent.path}/tmdb_pending_auth.json');
  }

  /// Persists an in-flight login (unapproved `request_token`, or an already-issued
  /// `session_id` whose profile fetch has not finished) so that if Android kills the
  /// app while the user approves in the browser, the approval is still picked up on
  /// the next launch instead of being wasted.
  Future<void> savePendingAuth({
    required String requestToken,
    required DateTime createdAt,
    String? sessionId,
  }) async {
    try {
      final file = _pendingAuthFile();
      if (file == null) return;
      await file.writeAsString(jsonEncode({
        'requestToken': requestToken,
        'createdAtMs': createdAt.millisecondsSinceEpoch,
        if (sessionId != null) 'sessionId': sessionId,
      }), flush: true);
    } catch (_) {}
  }

  /// Returns the persisted in-flight login, or `null` if none exists or it is stale.
  Future<({String requestToken, DateTime createdAt, String? sessionId})?>
      loadPendingAuth() async {
    try {
      final file = _pendingAuthFile();
      if (file == null || !file.existsSync()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      final token = decoded['requestToken'];
      final ms = decoded['createdAtMs'];
      if (token is! String || token.isEmpty || ms is! num) return null;
      final createdAt = DateTime.fromMillisecondsSinceEpoch(ms.toInt());
      final sessionId = decoded['sessionId'];
      final session = (sessionId is String && sessionId.isNotEmpty) ? sessionId : null;
      // A session_id never expires on its own; only unapproved tokens go stale.
      if (session == null && DateTime.now().difference(createdAt) > kPendingAuthMaxAge) {
        await clearPendingAuth();
        return null;
      }
      return (requestToken: token, createdAt: createdAt, sessionId: session);
    } catch (_) {
      return null;
    }
  }

  Future<void> clearPendingAuth() async {
    try {
      final file = _pendingAuthFile();
      if (file != null && file.existsSync()) await file.delete();
    } catch (_) {}
  }

  /// Step 1 of TMDB v3 Auth: Creates a short-lived unapproved `request_token`.
  Future<String> createRequestToken({CancelToken? cancelToken}) async {
    final res = await _dio.get<dynamic>(
      '${ApiConstants.tmdbBaseUrl}/authentication/token/new',
      queryParameters: {'api_key': ApiConstants.tmdbApiKey},
      cancelToken: cancelToken,
    );
    final data = res.data;
    if (data is Map<String, dynamic> &&
        data['success'] == true &&
        data['request_token'] is String) {
      final token = (data['request_token'] as String).trim();
      if (token.isNotEmpty) return token;
    }
    throw const TmdbException('Failed to create TMDB request token');
  }

  /// Step 3 of TMDB v3 Auth: Polls `POST /authentication/session/new` to exchange
  /// an approved [requestToken] for a permanent `session_id`.
  ///
  /// Returns the `session_id` if the user has clicked "Allow" on TMDB, or `null`
  /// if the token has not yet been approved (`401` / `status_code: 17`).
  Future<String?> tryCreateSession(
    String requestToken, {
    CancelToken? cancelToken,
  }) async {
    try {
      final res = await _dio.post<dynamic>(
        '${ApiConstants.tmdbBaseUrl}/authentication/session/new',
        queryParameters: {'api_key': ApiConstants.tmdbApiKey},
        data: {'request_token': requestToken.trim()},
        cancelToken: cancelToken,
      );
      final data = res.data;
      if (data is Map<String, dynamic> &&
          data['success'] == true &&
          data['session_id'] is String) {
        final sessionId = (data['session_id'] as String).trim();
        if (sessionId.isNotEmpty) return sessionId;
      }
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 401 || status == 400 || status == 422) {
        return null;
      }
      rethrow;
    }
    return null;
  }

  /// Step 4 of TMDB v3 Auth: Fetches `/account` for [sessionId], persists both
  /// `userSessionId` and `accountProfile`, and returns the resolved profile.
  Future<TmdbAccountProfile> fetchAndStoreAccountProfile(
    String sessionId, {
    CancelToken? cancelToken,
  }) async {
    await ensureInteractionsLoaded();
    late final Response<dynamic> res;
    try {
      res = await _dio.get<dynamic>(
        '${ApiConstants.tmdbBaseUrl}/account',
        queryParameters: {
          'api_key': ApiConstants.tmdbApiKey,
          'session_id': sessionId.trim(),
        },
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw const TmdbException(
          'TMDB session expired. Tap Reconnect below to back up your My List & Likes.',
          statusCode: 401,
        );
      }
      throw TmdbException(
        e.message ?? 'TMDB account request failed',
        statusCode: e.response?.statusCode,
      );
    }
    final data = res.data;
    if (res.statusCode == 401 ||
        (data is Map && (data['status_code'] == 3 || data['status_code'] == 30))) {
      throw const TmdbException(
        'TMDB session expired. Tap Reconnect below to back up your My List & Likes.',
        statusCode: 401,
      );
    }
    final profile = TmdbAccountProfile.tryParse(data);
    if (profile == null) {
      throw const TmdbException('Invalid TMDB account profile response');
    }
    _userSessionId = sessionId.trim();
    _accountProfile = profile;
    _sessionExpired = false;
    _lastSyncError = null;
    await _persistInteractionsToDisk();
    return profile;
  }

  /// Directly sets an authenticated session and profile (useful for restoration/testing).
  Future<void> setAuthenticatedSession({
    required String sessionId,
    required TmdbAccountProfile profile,
  }) async {
    await ensureInteractionsLoaded();
    _userSessionId = sessionId.trim();
    _accountProfile = profile;
    _sessionExpired = false;
    _lastSyncError = null;
    await _persistInteractionsToDisk();
  }

  /// Prepares an in-place TMDB reconnect when a session expires (HTTP 401).
  /// Preserves every local My List item, Like, Dislike, and pending mutation,
  /// and marks `_needsLocalPush = true` so the next sign-in pushes everything.
  Future<void> prepareSessionReconnect() async {
    await ensureInteractionsLoaded();
    final oldAccountId = _accountProfile?.id;
    if (oldAccountId != null && oldAccountId > 0) {
      _lastSyncedAccountId ??= oldAccountId;
    }
    _pendingFlushTimer?.cancel();
    _pendingFlushTimer = null;
    _userSessionId = null;
    _accountProfile = null;
    _sessionExpired = false;
    _lastSyncError = null;
    _lastSyncSucceeded = true;
    if (_myListCache.isNotEmpty || _ratingsCache.isNotEmpty || pendingSyncCount > 0) {
      _needsLocalPush = true;
    }
    unawaited(clearPendingAuth());
    _memo.clear();
    _coreMemo.clear();
    _notifyMyListListeners();
    await _persistInteractionsToDisk();
  }

  Future<bool> _verifyOrExpireSessionOn401(
    String sessionId, {
    CancelToken? cancelToken,
  }) async {
    try {
      final res = await _dio.get<dynamic>(
        '${ApiConstants.tmdbBaseUrl}/account',
        queryParameters: {
          'api_key': ApiConstants.tmdbApiKey,
          'session_id': sessionId.trim(),
        },
        cancelToken: cancelToken,
      );
      final data = res.data;
      if (res.statusCode == 401 ||
          (data is Map && (data['status_code'] == 3 || data['status_code'] == 30))) {
        _sessionExpired = true;
        if (_myListCache.isNotEmpty || _ratingsCache.isNotEmpty || pendingSyncCount > 0) {
          _needsLocalPush = true;
        }
        return false;
      }
      final profile = TmdbAccountProfile.tryParse(data);
      if (profile != null) {
        _accountProfile = profile;
        _sessionExpired = false;
        return true;
      }
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        _sessionExpired = true;
        if (_myListCache.isNotEmpty || _ratingsCache.isNotEmpty || pendingSyncCount > 0) {
          _needsLocalPush = true;
        }
        return false;
      }
    } catch (_) {}
    return false;
  }

  /// Disconnects the current TMDB session and revokes the remote `session_id`
  /// while preserving local Likes, Dislikes, My List, and pending mutations on
  /// this device so disconnecting or reconnecting later never loses user data.
  Future<void> logout({CancelToken? cancelToken}) async {
    await ensureInteractionsLoaded();
    final oldSession = _userSessionId;
    final oldAccountId = _accountProfile?.id;
    if (oldAccountId != null && oldAccountId > 0) {
      _lastSyncedAccountId ??= oldAccountId;
    }
    _pendingFlushTimer?.cancel();
    _pendingFlushTimer = null;
    _userSessionId = null;
    _accountProfile = null;
    _sessionExpired = false;
    _lastSyncError = null;
    _lastSyncSucceeded = true;
    unawaited(clearPendingAuth());
    _memo.clear();
    _coreMemo.clear();
    _standardCatalogItemsCache.clear();
    _categoryCatalogItemsCache.clear();
    _notifyMyListListeners();
    await _persistInteractionsToDisk();

    if (oldSession != null && oldSession.isNotEmpty) {
      try {
        await _dio.delete<dynamic>(
          '${ApiConstants.tmdbBaseUrl}/authentication/session',
          queryParameters: {'api_key': ApiConstants.tmdbApiKey},
          data: {'session_id': oldSession},
          cancelToken: cancelToken,
        );
      } catch (_) {}
    }
  }

  /// Reads every page (or up to [maxPages] if capped) of a paginated TMDB account list.
  /// Throws if any request fails so callers never act on a partial snapshot.
  Future<({List<Map<String, dynamic>> items, bool isComplete})> _fetchAllAccountPages(
    String path, {
    CancelToken? cancelToken,
    int? maxPages,
  }) async {
    Map<String, dynamic> query(int page) =>
        {'sort_by': 'created_at.desc', 'page': '$page'};
    final freshOptions = Options(headers: const {'Cache-Control': 'no-cache'});

    final first = await _getJson(
      path,
      query(1),
      cancelToken: cancelToken,
      options: freshOptions,
    );
    final out = <Map<String, dynamic>>[..._maps(first['results'])];
    final totalPages = (first['total_pages'] as num?)?.toInt() ?? 1;
    final lastPage = maxPages != null && totalPages > maxPages ? maxPages : totalPages;
    final isComplete = maxPages == null || totalPages <= maxPages;
    for (var start = 2; start <= lastPage; start += 2) {
      final end = start + 1 < lastPage ? start + 1 : lastPage;
      final pages = await Future.wait([
        for (var p = start; p <= end; p++)
          _getJson(
            path,
            query(p),
            cancelToken: cancelToken,
            options: freshOptions,
          ),
      ]);
      for (final page in pages) {
        out.addAll(_maps(page['results']));
      }
    }
    return (items: out, isComplete: isComplete);
  }

  Future<_AccountSnapshot> _fetchAccountSnapshot(
    int accountId, {
    CancelToken? cancelToken,
  }) async {
    // Fetch Watchlist first, then Ratings (max 2 parallel streams) to stay well
    // under TMDB's per-IP rate limit and avoid Android socket spikes on resume.
    final watchLists = await Future.wait([
      _fetchAllAccountPages('/account/$accountId/watchlist/movies', cancelToken: cancelToken),
      _fetchAllAccountPages('/account/$accountId/watchlist/tv', cancelToken: cancelToken),
    ]);
    final ratedLists = await Future.wait([
      _fetchAllAccountPages('/account/$accountId/rated/movies', cancelToken: cancelToken),
      _fetchAllAccountPages('/account/$accountId/rated/tv', cancelToken: cancelToken),
    ]);
    return _AccountSnapshot(
      watchMovies: watchLists[0].items,
      watchTv: watchLists[1].items,
      ratedMovies: ratedLists[0].items,
      ratedTv: ratedLists[1].items,
      watchMoviesComplete: watchLists[0].isComplete,
      watchTvComplete: watchLists[1].isComplete,
      ratedMoviesComplete: ratedLists[0].isComplete,
      ratedTvComplete: ratedLists[1].isComplete,
    );
  }

  /// Splits a stored interaction key (`movie:tmdb:123` / `series:imdb:tt123` / `series:anilist:123`).
  static ({String type, String kind, String id})? _parseInteractionKey(String key) {
    final parts = key.split(':');
    if (parts.length != 3) return null;
    final type = parts[0];
    final kind = parts[1];
    if ((type != 'movie' && type != 'series') ||
        (kind != 'tmdb' && kind != 'imdb' && kind != 'anilist')) {
      return null;
    }
    return (type: type, kind: kind, id: parts[2]);
  }

  MetaModel? _findCachedMetaFor({
    int? tmdbId,
    String? imdbId,
    required String mediaType,
  }) {
    final normType = _normalizeType(mediaType);
    final targetKeys = _interactionKeys(
      tmdbId: tmdbId,
      imdbId: imdbId,
      mediaType: normType,
    ).toSet();
    for (final list in [_myListMetas, _likedMetas]) {
      for (final m in list) {
        if (_keysForMeta(m).any(targetKeys.contains)) return m;
      }
    }
    for (final k in targetKeys) {
      final d = _memo[k] ?? _coreMemo[k];
      if (d != null && d.title.trim().isNotEmpty) {
        return MetaModel(
          id: d.imdbId ?? '${d.tmdbId}',
          type: d.mediaType,
          name: d.title,
          releaseInfo: d.releaseYear,
        );
      }
    }
    return null;
  }

  Future<({int tmdbId, String mediaType})?> _resolveTargetForParsedKey(
    ({String type, String kind, String id}) k, {
    AnimeIdMap? animeIdMap,
  }) {
    final tmdbInt = k.kind == 'tmdb' ? int.tryParse(k.id) : null;
    final imdbVal = k.kind == 'imdb'
        ? k.id
        : (k.kind == 'anilist' ? 'anilist:${k.id}' : null);
    final cachedMeta = _findCachedMetaFor(
      tmdbId: tmdbInt,
      imdbId: imdbVal,
      mediaType: k.type,
    );
    return _resolveTmdbTarget(
      tmdbId: tmdbInt,
      imdbId: imdbVal,
      mediaType: k.type,
      meta: cachedMeta,
      animeIdMap: animeIdMap ?? _animeIdMap,
    );
  }

  /// Flushes any locally queued Watchlist / Rating mutations made while offline
  /// or after transient TMDB errors before rebuilding local caches from remote state.
  Future<
      ({
        Set<String> addedWatchlistKeys,
        Set<String> removedWatchlistKeys,
        Map<String, double> flushedRatings,
        bool hadFailure,
      })> _flushPendingOps({AnimeIdMap? animeIdMap}) async {
    final effectiveMap = animeIdMap ?? _animeIdMap;
    final addedWatchlistKeys = <String>{};
    final removedWatchlistKeys = <String>{};
    final flushedRatings = <String, double>{};
    var flushedAny = false;
    var hadFailure = false;

    for (final entry in _pendingWatchlistOps.entries.toList()) {
      if (_sessionExpired) {
        hadFailure = true;
        break;
      }
      final k = _parseInteractionKey(entry.key);
      if (k == null) {
        _pendingWatchlistOps.remove(entry.key);
        continue;
      }
      final entryTmdb = k.kind == 'tmdb' ? int.tryParse(k.id) : null;
      final entryImdb = k.kind == 'imdb'
          ? k.id
          : (k.kind == 'anilist' ? 'anilist:${k.id}' : null);
      final cachedMeta = _findCachedMetaFor(
        tmdbId: entryTmdb,
        imdbId: entryImdb,
        mediaType: k.type,
      );
      final res = await _submitTmdbWatchlist(
        tmdbId: entryTmdb,
        imdbId: entryImdb,
        mediaType: k.type,
        watchlist: entry.value,
        meta: cachedMeta,
        animeIdMap: effectiveMap,
      );
      if (res.ok) {
        _pendingWatchlistOps.remove(entry.key);
        final flushedKeys = <String>{
          entry.key,
          if (res.tmdbId != null && res.mediaType != null)
            ..._interactionKeys(
              tmdbId: res.tmdbId,
              imdbId: k.kind == 'imdb' ? k.id : null,
              mediaType: res.mediaType!,
            ),
        };
        for (final rk in flushedKeys) {
          _pendingWatchlistOps.remove(rk);
          if (entry.value) {
            addedWatchlistKeys.add(rk);
            _myListCache.add(rk);
          } else {
            removedWatchlistKeys.add(rk);
            _myListCache.remove(rk);
          }
        }
        final canonicalKey = (res.tmdbId != null && res.mediaType != null)
            ? _cacheKey('${res.tmdbId}', res.mediaType!)
            : entry.key;
        _recordRecentMutation<bool>(
          _recentWatchlistMutations,
          keys: flushedKeys,
          canonicalKey: canonicalKey,
          value: entry.value,
        );
        flushedAny = true;
      } else {
        hadFailure = true;
        if (_sessionExpired) break;
      }
    }

    for (final entry in _pendingRatingOps.entries.toList()) {
      if (_sessionExpired) {
        hadFailure = true;
        break;
      }
      final k = _parseInteractionKey(entry.key);
      if (k == null) {
        _pendingRatingOps.remove(entry.key);
        continue;
      }
      final entryTmdb = k.kind == 'tmdb' ? int.tryParse(k.id) : null;
      final entryImdb = k.kind == 'imdb'
          ? k.id
          : (k.kind == 'anilist' ? 'anilist:${k.id}' : null);
      final cachedMeta = _findCachedMetaFor(
        tmdbId: entryTmdb,
        imdbId: entryImdb,
        mediaType: k.type,
      );
      final res = await _submitTmdbRating(
        tmdbId: entryTmdb,
        imdbId: entryImdb,
        mediaType: k.type,
        rating: entry.value > 0 ? entry.value : null,
        meta: cachedMeta,
        animeIdMap: effectiveMap,
      );
      if (res.ok) {
        _pendingRatingOps.remove(entry.key);
        final flushedKeys = <String>{
          entry.key,
          if (res.tmdbId != null && res.mediaType != null)
            ..._interactionKeys(
              tmdbId: res.tmdbId,
              imdbId: k.kind == 'imdb' ? k.id : null,
              mediaType: res.mediaType!,
            ),
        };
        for (final rk in flushedKeys) {
          _pendingRatingOps.remove(rk);
          flushedRatings[rk] = entry.value;
          if (entry.value > 0) {
            _ratingsCache[rk] = entry.value;
          } else {
            _ratingsCache.remove(rk);
          }
        }
        final canonicalKey = (res.tmdbId != null && res.mediaType != null)
            ? _cacheKey('${res.tmdbId}', res.mediaType!)
            : entry.key;
        _recordRecentMutation<double>(
          _recentRatingMutations,
          keys: flushedKeys,
          canonicalKey: canonicalKey,
          value: entry.value,
        );
        flushedAny = true;
      } else {
        hadFailure = true;
        if (_sessionExpired) break;
      }
    }

    if (flushedAny) {
      unawaited(_persistInteractionsToDisk());
    }
    return (
      addedWatchlistKeys: addedWatchlistKeys,
      removedWatchlistKeys: removedWatchlistKeys,
      flushedRatings: flushedRatings,
      hadFailure: hadFailure,
    );
  }

  /// One-time migration at login: uploads Watchlist entries and ratings that exist only
  /// on this device (including anime, which are TMDB titles) so they live in the user's
  /// TMDB account. Any transient push failures are queued into `_pending*Ops` so they
  /// survive snapshot rebuilds and retry on later syncs. Returns upload status.
  Future<({bool pushedAny, bool hadFailure})> _pushLocalOnlyEntries(
    _AccountSnapshot remote, {
    AnimeIdMap? animeIdMap,
    Set<String> skipWatchlistKeys = const {},
    Set<String> skipRatingKeys = const {},
  }) async {
    String idKey(String type, int id) => '$type:$id';
    int? idOf(Map<String, dynamic> r) => (r['id'] as num?)?.toInt();
    final remoteWatch = <String>{
      for (final r in remote.watchMovies) if (idOf(r) != null) idKey('movie', idOf(r)!),
      for (final r in remote.watchTv) if (idOf(r) != null) idKey('series', idOf(r)!),
    };
    final remoteRated = <String>{
      for (final r in remote.ratedMovies) if (idOf(r) != null) idKey('movie', idOf(r)!),
      for (final r in remote.ratedTv) if (idOf(r) != null) idKey('series', idOf(r)!),
    };

    final seen = <String>{};
    final jobs = <Future<({bool pushed, bool failed})> Function()>[];
    var queueChanged = false;

    for (final key in _myListCache.toList()) {
      if (skipWatchlistKeys.contains(key)) continue;
      final k = _parseInteractionKey(key);
      if (k == null) continue;
      if (_pendingWatchlistFor([key]) == false) continue;
      if (k.kind == 'tmdb') {
        final tmdbInt = int.tryParse(k.id);
        if (tmdbInt != null && remoteWatch.contains(idKey(k.type, tmdbInt))) {
          _pendingWatchlistOps.remove(key);
          continue;
        }
      }
      jobs.add(() async {
        final target = await _resolveTargetForParsedKey(k, animeIdMap: animeIdMap);
        if (target == null) {
          if (_pendingWatchlistFor([key]) == null) {
            _pendingWatchlistOps[key] = true;
            queueChanged = true;
          }
          return (pushed: false, failed: true);
        }
        final dedupe = idKey(target.mediaType, target.tmdbId);
        if (remoteWatch.contains(dedupe)) {
          _pendingWatchlistOps.remove(key);
          return (pushed: false, failed: false);
        }
        if (!seen.add('w|$dedupe')) return (pushed: false, failed: false);
        final res = await _submitTmdbWatchlist(
          tmdbId: target.tmdbId,
          imdbId: k.kind == 'imdb'
              ? k.id
              : (k.kind == 'anilist' ? 'anilist:${k.id}' : null),
          mediaType: target.mediaType,
          watchlist: true,
          meta: _findCachedMetaFor(
            tmdbId: target.tmdbId,
            imdbId: k.kind == 'imdb'
                ? k.id
                : (k.kind == 'anilist' ? 'anilist:${k.id}' : null),
            mediaType: target.mediaType,
          ),
          animeIdMap: animeIdMap,
        );
        final resolvedTmdb = res.tmdbId ?? target.tmdbId;
        final resolvedType = res.mediaType ?? target.mediaType;
        final allKeys = <String>{
          key,
          ..._interactionKeys(
            tmdbId: resolvedTmdb,
            imdbId: k.kind == 'imdb'
                ? k.id
                : (k.kind == 'anilist' ? 'anilist:${k.id}' : null),
            mediaType: resolvedType,
          ),
        };
        final canonicalKey = _cacheKey('$resolvedTmdb', resolvedType);
        if (res.ok) {
          _myListCache.addAll(allKeys);
          for (final ak in allKeys) {
            _pendingWatchlistOps.remove(ak);
          }
          _recordRecentMutation<bool>(
            _recentWatchlistMutations,
            keys: allKeys,
            canonicalKey: canonicalKey,
            value: true,
          );
        } else if (_pendingWatchlistFor(allKeys) == null) {
          _pendingWatchlistOps[canonicalKey] = true;
          queueChanged = true;
        }
        return (pushed: res.ok, failed: !res.ok);
      });
    }
    for (final entry in _ratingsCache.entries.toList()) {
      if (skipRatingKeys.contains(entry.key)) continue;
      final k = _parseInteractionKey(entry.key);
      if (k == null || entry.value <= 0) continue;
      if (_pendingRatingFor([entry.key]) == 0.0) continue;
      if (k.kind == 'tmdb') {
        final tmdbInt = int.tryParse(k.id);
        if (tmdbInt != null && remoteRated.contains(idKey(k.type, tmdbInt))) {
          _pendingRatingOps.remove(entry.key);
          continue;
        }
      }
      jobs.add(() async {
        final target = await _resolveTargetForParsedKey(k, animeIdMap: animeIdMap);
        if (target == null) {
          if (_pendingRatingFor([entry.key]) == null) {
            _pendingRatingOps[entry.key] = entry.value;
            queueChanged = true;
          }
          return (pushed: false, failed: true);
        }
        final dedupe = idKey(target.mediaType, target.tmdbId);
        if (remoteRated.contains(dedupe)) {
          _pendingRatingOps.remove(entry.key);
          return (pushed: false, failed: false);
        }
        if (!seen.add('r|$dedupe')) return (pushed: false, failed: false);
        final res = await _submitTmdbRating(
          tmdbId: target.tmdbId,
          imdbId: k.kind == 'imdb'
              ? k.id
              : (k.kind == 'anilist' ? 'anilist:${k.id}' : null),
          mediaType: target.mediaType,
          rating: entry.value,
          meta: _findCachedMetaFor(
            tmdbId: target.tmdbId,
            imdbId: k.kind == 'imdb'
                ? k.id
                : (k.kind == 'anilist' ? 'anilist:${k.id}' : null),
            mediaType: target.mediaType,
          ),
          animeIdMap: animeIdMap,
        );
        final resolvedTmdb = res.tmdbId ?? target.tmdbId;
        final resolvedType = res.mediaType ?? target.mediaType;
        final allKeys = <String>{
          entry.key,
          ..._interactionKeys(
            tmdbId: resolvedTmdb,
            imdbId: k.kind == 'imdb'
                ? k.id
                : (k.kind == 'anilist' ? 'anilist:${k.id}' : null),
            mediaType: resolvedType,
          ),
        };
        final canonicalKey = _cacheKey('$resolvedTmdb', resolvedType);
        if (res.ok) {
          for (final ak in allKeys) {
            _ratingsCache[ak] = entry.value;
            _pendingRatingOps.remove(ak);
          }
          _recordRecentMutation<double>(
            _recentRatingMutations,
            keys: allKeys,
            canonicalKey: canonicalKey,
            value: entry.value,
          );
        } else if (_pendingRatingFor(allKeys) == null) {
          _pendingRatingOps[canonicalKey] = entry.value;
          queueChanged = true;
        }
        return (pushed: res.ok, failed: !res.ok);
      });
    }

    var pushedAny = false;
    var hadFailure = false;
    for (var i = 0; i < jobs.length; i += 2) {
      if (_sessionExpired) {
        hadFailure = true;
        break;
      }
      final end = i + 2 < jobs.length ? i + 2 : jobs.length;
      final results = await Future.wait([for (var j = i; j < end; j++) jobs[j]()]);
      if (results.any((r) => r.pushed)) pushedAny = true;
      if (results.any((r) => r.failed)) hadFailure = true;
    }
    if (pushedAny || queueChanged) {
      unawaited(_persistInteractionsToDisk());
    }
    return (pushedAny: pushedAny, hadFailure: hadFailure);
  }

  /// Resolves IMDb IDs for remaining animated items beyond Wave 1 so non-Japanese
  /// anime (e.g. donghua indexed by IMDb ID in [animeIdMap]) are also classified.
  Future<void> _reclassifyRemainingAnimationItems(
    List<({int tmdbId, String mediaType})> targets, {
    AnimeIdMap? animeIdMap,
    CancelToken? cancelToken,
  }) async {
    final effectiveMap = animeIdMap ?? _animeIdMap;
    if (effectiveMap == null || targets.isEmpty) return;
    var anyMarked = false;
    for (var i = 0; i < targets.length; i += kMaxBackgroundConcurrency) {
      if (cancelToken?.isCancelled ?? false) break;
      final chunk = targets.skip(i).take(kMaxBackgroundConcurrency).toList();
      final imdbs = await Future.wait([
        for (final t in chunk)
          _resolveImdbId(t.tmdbId, mediaType: t.mediaType, cancelToken: cancelToken),
      ]);
      for (var j = 0; j < chunk.length; j++) {
        final t = chunk[j];
        final imdb = imdbs[j];
        if (imdb == null || imdb.isEmpty) continue;
        final anilistId = effectiveMap.lookupAnilistIdByImdb(imdb);
        if (anilistId != null && anilistId > 0) {
          markAsAnime(
            tmdbId: t.tmdbId,
            imdbId: imdb,
            mediaType: t.mediaType,
            anilistId: anilistId,
            notify: false,
          );
          anyMarked = true;
        }
      }
    }
    if (anyMarked) {
      _notifyMyListListeners();
      unawaited(_persistInteractionsToDisk());
    }
  }

  Future<void> _enrichSyncMetasInBatches(
    List<MetaModel> myListTargets,
    List<MetaModel> likedTargets, {
    CancelToken? cancelToken,
  }) async {
    final jobs = <Future<void> Function()>[
      for (final meta in myListTargets)
        () => _enrichSingleMyListItem(meta.id, meta.type, baseMeta: meta),
      for (final meta in likedTargets)
        () => _enrichSingleLikedItem(meta.id, meta.type, baseMeta: meta),
    ];
    for (var i = 0; i < jobs.length; i += kMaxBackgroundConcurrency) {
      if (cancelToken?.isCancelled ?? false) break;
      final end = i + kMaxBackgroundConcurrency < jobs.length
          ? i + kMaxBackgroundConcurrency
          : jobs.length;
      await Future.wait([for (var j = i; j < end; j++) jobs[j]()]);
    }
  }

  /// Synchronizes the user's TMDB Watchlist ("My List") and Rated movies/TV shows
  /// ("Likes" >= 5.0, "Dislikes" < 5.0) with local caches and disk persistence.
  ///
  /// TMDB is the source of truth, so anime (which are plain TMDB titles) are restored
  /// from the account as well and re-classified as anime from TMDB data
  /// (Animation genre + Japanese original language, or the bundled [animeIdMap]).
  ///
  /// Pending offline/failed local mutations are always uploaded first, and with
  /// [pushLocalOnly] (used at initial login or same-account reconnect), any remaining
  /// device-only entries are uploaded to TMDB so nothing stored locally is lost.
  /// Concurrent calls share the active sync flight to prevent racing rebuilds.
  ///
  /// The sync aborts without touching local data if any TMDB request fails.
  Future<void> syncTmdbAccountData({
    CancelToken? cancelToken,
    AnimeIdMap? animeIdMap,
    bool pushLocalOnly = false,
    bool throwOnError = false,
  }) async {
    Future<void>? inflight = _inflightSync;
    if (inflight != null) {
      await inflight;
      if (pushLocalOnly && _needsLocalPush) {
        await syncTmdbAccountData(
          cancelToken: cancelToken,
          animeIdMap: animeIdMap,
          pushLocalOnly: true,
          throwOnError: throwOnError,
        );
        return;
      }
      if (throwOnError && !_lastSyncSucceeded) {
        throw TmdbException(_lastSyncError ?? 'TMDB sync failed');
      }
      return;
    }
    final future = _runSyncTmdbAccountData(
      cancelToken: cancelToken,
      animeIdMap: animeIdMap,
      pushLocalOnly: pushLocalOnly,
    );
    _inflightSync = future;
    try {
      await future;
    } finally {
      if (identical(_inflightSync, future)) {
        _inflightSync = null;
      }
    }
    if (throwOnError && !_lastSyncSucceeded) {
      throw TmdbException(_lastSyncError ?? 'TMDB sync failed');
    }
  }

  static bool _isUnauthorizedError(Object error) {
    if (error is TmdbException) {
      return error.statusCode == 401 ||
          error.message.contains('status code of 401');
    }
    if (error is DioException) {
      return error.response?.statusCode == 401;
    }
    return error.toString().contains('status code of 401');
  }

  static String _friendlySyncError(Object error) {
    if (_isUnauthorizedError(error)) {
      return 'TMDB session expired. Tap Reconnect below to back up your My List & Likes.';
    }
    if (error is TmdbException) {
      if (error.statusCode == 429) {
        return 'TMDB rate limit hit. Retrying automatically.';
      }
      return error.message;
    }
    if (error is DioException) {
      if (error.response?.statusCode == 429) {
        return 'TMDB rate limit hit. Retrying automatically.';
      }
      return error.message ?? 'Network error syncing with TMDB';
    }
    return error.toString();
  }

  Future<void> _runSyncTmdbAccountData({
    CancelToken? cancelToken,
    AnimeIdMap? animeIdMap,
    bool pushLocalOnly = false,
  }) async {
    await ensureInteractionsLoaded();
    final effectiveMap = animeIdMap ?? _animeIdMap;
    final sessionId = _userSessionId;
    var profile = _accountProfile;
    if (sessionId == null || sessionId.isEmpty) return;

    if (profile == null) {
      try {
        profile = await fetchAndStoreAccountProfile(
          sessionId,
          cancelToken: cancelToken,
        );
      } catch (e) {
        if (_isUnauthorizedError(e)) {
          _sessionExpired = true;
          _pendingFlushTimer?.cancel();
          _pendingFlushTimer = null;
        }
        _lastSyncSucceeded = false;
        _lastSyncError = _friendlySyncError(e);
        if ((pushLocalOnly || _sessionExpired) &&
            (_myListCache.isNotEmpty || _ratingsCache.isNotEmpty || pendingSyncCount > 0)) {
          _needsLocalPush = true;
        }
        unawaited(_persistInteractionsToDisk());
        _notifyMyListListeners();
        return;
      }
    }

    final accountId = profile.id;
    final switchedAccount =
        _lastSyncedAccountId != null && _lastSyncedAccountId != accountId;
    final effectivePushLocalOnly =
        !switchedAccount && (pushLocalOnly || _needsLocalPush);
    if (switchedAccount) {
      _needsLocalPush = false;
    } else if (pushLocalOnly) {
      _needsLocalPush = true;
    }
    try {
      final flushed = await _flushPendingOps(animeIdMap: effectiveMap);
      if (_sessionExpired) {
        throw const TmdbException(
          'TMDB session expired. Tap Reconnect below to back up your My List & Likes.',
          statusCode: 401,
        );
      }
      if (switchedAccount) {
        // Switching to a different TMDB account: drop any previous account's
        // recent-write confirmation memory while keeping newly flushed writes.
        _recentWatchlistMutations.clear();
        _recentRatingMutations.clear();
        for (final k in flushed.addedWatchlistKeys) {
          _recentWatchlistMutations[k] = (value: true, updatedAtMs: _nowMs());
        }
        for (final k in flushed.removedWatchlistKeys) {
          _recentWatchlistMutations[k] = (value: false, updatedAtMs: _nowMs());
        }
        for (final e in flushed.flushedRatings.entries) {
          _recentRatingMutations[e.key] = (value: e.value, updatedAtMs: _nowMs());
        }
      }

      var snapshot = await _fetchAccountSnapshot(accountId, cancelToken: cancelToken);
      _sessionExpired = false;
      var pushHadFailure = false;
      if (effectivePushLocalOnly) {
        final skipWatch = <String>{
          for (final k in flushed.addedWatchlistKeys) ..._expandInteractionKey(k),
        };
        final skipRatings = <String>{
          for (final k in flushed.flushedRatings.keys) ..._expandInteractionKey(k),
        };
        final pushRes = await _pushLocalOnlyEntries(
          snapshot,
          animeIdMap: effectiveMap,
          skipWatchlistKeys: skipWatch,
          skipRatingKeys: skipRatings,
        );
        if (_sessionExpired) {
          throw const TmdbException(
            'TMDB session expired. Tap Reconnect below to back up your My List & Likes.',
            statusCode: 401,
          );
        }
        pushHadFailure = pushRes.hadFailure;
        if (pushRes.pushedAny) {
          snapshot = await _fetchAccountSnapshot(accountId, cancelToken: cancelToken);
        }
      }

      final watchMovies = snapshot.watchMovies;
      final watchTv = snapshot.watchTv;
      final ratedMovies = snapshot.ratedMovies;
      final ratedTv = snapshot.ratedTv;

      // Resolve Wave 1 IMDb IDs for the top items so `btttr.cc` posters work immediately.
      final priorityPairs = <({int tmdbId, String mediaType})>[
        for (final r in watchMovies.take(kViewportPriorityCount))
          if (r['id'] is num) (tmdbId: (r['id'] as num).toInt(), mediaType: 'movie'),
        for (final r in watchTv.take(kViewportPriorityCount))
          if (r['id'] is num) (tmdbId: (r['id'] as num).toInt(), mediaType: 'series'),
        for (final r in ratedMovies.take(kViewportPriorityCount))
          if (r['id'] is num) (tmdbId: (r['id'] as num).toInt(), mediaType: 'movie'),
        for (final r in ratedTv.take(kViewportPriorityCount))
          if (r['id'] is num) (tmdbId: (r['id'] as num).toInt(), mediaType: 'series'),
      ];
      if (priorityPairs.isNotEmpty) {
        await Future.wait([
          for (final p in priorityPairs)
            _resolveImdbId(
              p.tmdbId,
              mediaType: p.mediaType,
              cancelToken: cancelToken,
            ),
        ]);
      }

      final remainingAnimationTargets = <String, ({int tmdbId, String mediaType})>{};

      /// Derives anime classification from TMDB data and [animeIdMap] so it survives reinstalls.
      void classifyAnime(Map<String, dynamic> r, {required bool isSeries}) {
        final tmdbId = (r['id'] as num?)?.toInt();
        if (tmdbId == null) return;
        final normType = isSeries ? 'series' : 'movie';
        final imdbId = _cachedImdbFor(tmdbId, normType);
        final keys = _interactionKeys(
          tmdbId: tmdbId,
          imdbId: imdbId,
          mediaType: normType,
        );
        final genres = r['genre_ids'];
        final isAnimation = genres is List && genres.contains(16);
        final animatedJapanese =
            isAnimation && _str(r['original_language']).toLowerCase() == 'ja';
        final anilistId = effectiveMap?.lookupAnilistIdByTmdb(
              tmdbId: tmdbId,
              type: normType,
            ) ??
            (imdbId != null ? effectiveMap?.lookupAnilistIdByImdb(imdbId) : null);
        final alreadyKnown = keys.any(_animeKeys.contains);
        if (!animatedJapanese && anilistId == null && !alreadyKnown) {
          if (isAnimation && imdbId == null && effectiveMap != null) {
            remainingAnimationTargets['$normType:$tmdbId'] =
                (tmdbId: tmdbId, mediaType: normType);
          }
          return;
        }
        for (final k in keys) {
          _animeKeys.add(k);
          if (anilistId != null && anilistId > 0) _keyToAnilistCache[k] = anilistId;
        }
      }

      MetaModel? parseSyncItem(Map<String, dynamic> r, {required bool isSeries}) {
        final tmdbId = (r['id'] as num?)?.toInt();
        if (tmdbId == null) return null;
        final normType = isSeries ? 'series' : 'movie';
        final title = isSeries
            ? (_str(r['name']).isNotEmpty ? _str(r['name']) : _str(r['original_name']))
            : (_str(r['title']).isNotEmpty ? _str(r['title']) : _str(r['original_title']));
        if (title.isEmpty) return null;

        final imdbId = _cachedImdbFor(tmdbId, normType);
        final id = (imdbId != null && imdbId.isNotEmpty) ? imdbId : '$tmdbId';
        final tmdbPoster = _img(_str(r['poster_path']), 'w342');
        final tmdbBackdrop = _img(_str(r['backdrop_path']), 'w780');
        final poster = (imdbId != null && imdbId.isNotEmpty)
            ? betterPosterUrl(imdbId)
            : tmdbPoster;
        final rawDate = isSeries ? _str(r['first_air_date']) : _str(r['release_date']);
        final year = rawDate.length >= 4 ? rawDate.substring(0, 4) : null;
        final voteAvg = (r['vote_average'] as num?)?.toDouble();
        final rating = (voteAvg != null && voteAvg > 0)
            ? (voteAvg >= 10.0 ? '10' : voteAvg.toStringAsFixed(1))
            : null;
        final genres = _resolveGenresFromIds(r['genre_ids']);
        final overview = _str(r['overview']).trim();

        return MetaModel(
          id: id,
          type: normType,
          name: title,
          poster: poster,
          posterFallback: tmdbPoster,
          background: tmdbBackdrop ?? tmdbPoster,
          landscapePoster: tmdbBackdrop,
          description: overview.isNotEmpty ? overview : null,
          genres: genres,
          releaseInfo: year,
          imdbRating: rating,
        );
      }

      // Prune expired or snapshot-confirmed entries in the recent-write ledger so
      // lagging TMDB GET responses never overwrite recent confirmed writes.
      _pruneExpiredRecentMutations();
      final snapshotWatchKeys = <String>{
        for (final r in watchMovies)
          if (r['id'] is num)
            ..._interactionKeys(
              tmdbId: (r['id'] as num).toInt(),
              imdbId: _cachedImdbFor((r['id'] as num).toInt(), 'movie'),
              mediaType: 'movie',
            ),
        for (final r in watchTv)
          if (r['id'] is num)
            ..._interactionKeys(
              tmdbId: (r['id'] as num).toInt(),
              imdbId: _cachedImdbFor((r['id'] as num).toInt(), 'series'),
              mediaType: 'series',
            ),
      };
      for (final e in _recentWatchlistMutations.entries.toList()) {
        final expanded = _expandInteractionKey(e.key);
        final inSnap = expanded.any(snapshotWatchKeys.contains);
        if ((e.value.value && inSnap) || (!e.value.value && !inSnap)) {
          _recentWatchlistMutations.remove(e.key);
        }
      }

      final snapshotRatingsByKey = <String, double>{};
      for (final list in [
        (items: ratedMovies, normType: 'movie'),
        (items: ratedTv, normType: 'series'),
      ]) {
        for (final r in list.items) {
          final tmdbId = (r['id'] as num?)?.toInt();
          final score = (r['rating'] as num?)?.toDouble();
          if (tmdbId == null || score == null || score <= 0) continue;
          final imdbId = _cachedImdbFor(tmdbId, list.normType);
          for (final k in _interactionKeys(
            tmdbId: tmdbId,
            imdbId: imdbId,
            mediaType: list.normType,
          )) {
            snapshotRatingsByKey[k] = score;
          }
        }
      }
      for (final e in _recentRatingMutations.entries.toList()) {
        final expanded = _expandInteractionKey(e.key);
        double? snapScore;
        for (final k in expanded) {
          snapScore ??= snapshotRatingsByKey[k];
        }
        if (e.value.value > 0) {
          if (snapScore != null && (snapScore - e.value.value).abs() < 0.01) {
            _recentRatingMutations.remove(e.key);
          }
        } else if (snapScore == null) {
          _recentRatingMutations.remove(e.key);
        }
      }

      // Preserve any still-pending or unconfirmed-recent local watchlist metas
      // across rebuild so TMDB eventual consistency never drops them.
      final activeWatchTrueKeys = <String>{
        for (final e in _recentWatchlistMutations.entries)
          if (e.value.value) ..._expandInteractionKey(e.key),
        for (final e in _pendingWatchlistOps.entries)
          if (e.value) ..._expandInteractionKey(e.key),
      };
      final activeWatchFalseKeys = <String>{
        for (final e in _recentWatchlistMutations.entries)
          if (!e.value.value) ..._expandInteractionKey(e.key),
        for (final e in _pendingWatchlistOps.entries)
          if (!e.value) ..._expandInteractionKey(e.key),
      };
      // If a pending op explicitly set true/false, let it override recent/opposite.
      for (final e in _pendingWatchlistOps.entries) {
        final expanded = _expandInteractionKey(e.key);
        if (e.value) {
          activeWatchFalseKeys.removeAll(expanded);
        } else {
          activeWatchTrueKeys.removeAll(expanded);
        }
      }
      final preservedProtectedMyList = activeWatchTrueKeys.isEmpty
          ? const <MetaModel>[]
          : _myListMetas
              .where((m) => _keysForMeta(m).any(activeWatchTrueKeys.contains))
              .toList();

      // 1. Rebuild Watchlist ("My List") while preserving pure-AniList items.
      final watchListComplete =
          snapshot.watchMoviesComplete && snapshot.watchTvComplete;
      if (watchListComplete) {
        final preservedAniListMyList = _myListMetas
            .where((m) => m.id.startsWith('anilist:'))
            .toList();
        _myListCache.clear();
        _myListMetas
          ..clear()
          ..addAll(preservedAniListMyList);
        for (final m in preservedAniListMyList) {
          _myListCache.addAll(_keysForMeta(m));
        }
      }

      void addWatchlistItems(List<Map<String, dynamic>> rawList, {required bool isSeries}) {
        final normType = isSeries ? 'series' : 'movie';
        for (final r in rawList) {
          final meta = parseSyncItem(r, isSeries: isSeries);
          if (meta == null) continue;
          final tmdbId = (r['id'] as num).toInt();
          final imdbId = _cachedImdbFor(tmdbId, normType);
          for (final k in _interactionKeys(tmdbId: tmdbId, imdbId: imdbId, mediaType: normType)) {
            _myListCache.add(k);
          }
          classifyAnime(r, isSeries: isSeries);
          _upsertMyListMeta(meta, moveToFront: false);
        }
      }

      addWatchlistItems(watchMovies, isSeries: false);
      addWatchlistItems(watchTv, isSeries: true);

      // Re-apply unconfirmed recent writes and pending local watchlist mutations.
      if (activeWatchFalseKeys.isNotEmpty) {
        _myListCache.removeAll(activeWatchFalseKeys);
        _myListMetas.removeWhere((m) => _keysForMeta(m).any(activeWatchFalseKeys.contains));
      }
      if (activeWatchTrueKeys.isNotEmpty) {
        _myListCache.addAll(activeWatchTrueKeys);
      }
      for (final m in preservedProtectedMyList) {
        _myListCache.addAll(_keysForMeta(m));
        _upsertMyListMeta(m, moveToFront: true);
      }

      // Preserve any unconfirmed-recent or still-pending local liked metas across rebuild.
      final ratingOverrides = <String, double>{
        for (final e in _recentRatingMutations.entries) e.key: e.value.value,
        for (final e in _pendingRatingOps.entries) e.key: e.value,
      };
      final activeLikedKeys = <String>{
        for (final e in ratingOverrides.entries)
          if (e.value >= kTmdbHalfRatingThreshold) ..._expandInteractionKey(e.key),
      };
      final preservedProtectedLiked = activeLikedKeys.isEmpty
          ? const <MetaModel>[]
          : _likedMetas
              .where((m) => _keysForMeta(m).any(activeLikedKeys.contains))
              .toList();

      // 2. Rebuild Ratings (Likes >= 5.0, Dislikes < 5.0) while preserving pure-AniList items.
      final ratingsComplete =
          snapshot.ratedMoviesComplete && snapshot.ratedTvComplete;
      if (ratingsComplete) {
        final preservedAniListLiked = _likedMetas
            .where((m) => m.id.startsWith('anilist:'))
            .toList();
        final preservedAniListRatings = <String, double>{
          for (final entry in _ratingsCache.entries)
            if (entry.key.contains('anilist:')) entry.key: entry.value,
        };
        _ratingsCache
          ..clear()
          ..addAll(preservedAniListRatings);
        _likedMetas
          ..clear()
          ..addAll(preservedAniListLiked);
      }

      void addRatedItems(List<Map<String, dynamic>> rawList, {required bool isSeries}) {
        final normType = isSeries ? 'series' : 'movie';
        for (final r in rawList) {
          final tmdbId = (r['id'] as num?)?.toInt();
          final userScore = (r['rating'] as num?)?.toDouble();
          if (tmdbId == null || userScore == null || userScore <= 0) continue;
          final imdbId = _cachedImdbFor(tmdbId, normType);
          for (final k in _interactionKeys(tmdbId: tmdbId, imdbId: imdbId, mediaType: normType)) {
            _ratingsCache[k] = userScore;
          }
          classifyAnime(r, isSeries: isSeries);
          final meta = parseSyncItem(r, isSeries: isSeries);
          if (meta != null && userScore >= kTmdbHalfRatingThreshold) {
            _upsertLikedMeta(meta, moveToFront: false);
          }
        }
      }

      addRatedItems(ratedMovies, isSeries: false);
      addRatedItems(ratedTv, isSeries: true);

      void applyRatingOverrides(Map<String, double> overrides) {
        for (final entry in overrides.entries) {
          final keys = _expandInteractionKey(entry.key);
          if (entry.value > 0) {
            for (final rk in keys) {
              _ratingsCache[rk] = entry.value;
            }
            if (entry.value < kTmdbHalfRatingThreshold) {
              _likedMetas.removeWhere((m) => _keysForMeta(m).any(keys.contains));
            }
          } else {
            for (final rk in keys) {
              _ratingsCache.remove(rk);
            }
            _likedMetas.removeWhere((m) => _keysForMeta(m).any(keys.contains));
          }
        }
      }

      applyRatingOverrides(ratingOverrides);
      for (final m in preservedProtectedLiked) {
        _upsertLikedMeta(m, moveToFront: true);
      }

      _lastSyncedAccountId = accountId;
      _sessionExpired = false;
      _needsLocalPush = flushed.hadFailure ||
          pushHadFailure ||
          _pendingWatchlistOps.isNotEmpty ||
          _pendingRatingOps.isNotEmpty;
      _lastSyncSucceeded = true;
      _lastSyncError = null;
      _lastSuccessfulSyncAt = (_clock ?? DateTime.now)();
      if (!hasPendingSyncOps) {
        _pendingFlushAttempts = 0;
      } else {
        _schedulePendingFlushRetry();
      }
      _patchAllMemosFromCaches();
      _notifyMyListListeners();
      await _persistInteractionsToDisk();

      // Background-enrich any synced My List / Liked items missing IMDb IDs (`tt...`).
      final myListNeedingImdb = [
        for (final meta in _myListMetas)
          if (!meta.id.startsWith('tt') && !meta.id.startsWith('anilist:')) meta,
      ];
      final likedNeedingImdb = [
        for (final meta in _likedMetas)
          if (!meta.id.startsWith('tt') && !meta.id.startsWith('anilist:')) meta,
      ];
      if (myListNeedingImdb.isNotEmpty || likedNeedingImdb.isNotEmpty) {
        unawaited(
          _enrichSyncMetasInBatches(
            myListNeedingImdb,
            likedNeedingImdb,
            cancelToken: cancelToken,
          ),
        );
      }
      if (remainingAnimationTargets.isNotEmpty) {
        unawaited(
          _reclassifyRemainingAnimationItems(
            remainingAnimationTargets.values.toList(),
            animeIdMap: effectiveMap,
            cancelToken: cancelToken,
          ),
        );
      }
    } catch (e) {
      // Non-fatal (offline / TMDB error): local data and `_needsLocalPush` stay intact.
      if (_isUnauthorizedError(e)) {
        final stillValid = await _verifyOrExpireSessionOn401(
          sessionId,
          cancelToken: cancelToken,
        );
        if (!stillValid) {
          _sessionExpired = true;
          _pendingFlushTimer?.cancel();
          _pendingFlushTimer = null;
          if (_myListCache.isNotEmpty ||
              _ratingsCache.isNotEmpty ||
              pendingSyncCount > 0) {
            _needsLocalPush = true;
          }
        }
      }
      _lastSyncSucceeded = false;
      _lastSyncError = _friendlySyncError(e);
      if (!_sessionExpired && hasPendingSyncOps) {
        _schedulePendingFlushRetry();
      }
      _notifyMyListListeners();
      unawaited(_persistInteractionsToDisk());
    }
  }

  /// Fetches the user's existing TMDB rating from `/account_states` when a
  /// TMDB user session exists, so any rating previously submitted on TMDB
  /// is reflected on the Details screen.
  Future<double?> syncAccountRatingFromTmdb({
    required int tmdbId,
    String? imdbId,
    required String mediaType,
    CancelToken? cancelToken,
  }) async {
    await ensureInteractionsLoaded();
    final normType = _normalizeType(mediaType);
    final keys = _interactionKeys(tmdbId: tmdbId, imdbId: imdbId, mediaType: normType);
    final pendingRating = _pendingRatingFor(keys);
    if (pendingRating != null) {
      return pendingRating > 0 ? pendingRating : null;
    }
    final recentRating = _recentRatingFor(keys);
    if (recentRating != null) {
      return recentRating > 0 ? recentRating : null;
    }

    final sessionId = _userSessionId;
    if (sessionId == null || sessionId.isEmpty) {
      return getCachedUserRating(tmdbId: tmdbId, imdbId: imdbId, mediaType: mediaType);
    }
    try {
      final resource = _resourceFor(normType);
      final res = await _dio.get<dynamic>(
        '${ApiConstants.tmdbBaseUrl}/$resource/$tmdbId/account_states',
        queryParameters: {
          'api_key': ApiConstants.tmdbApiKey,
          'session_id': sessionId,
        },
        cancelToken: cancelToken,
      );
      final data = res.data;
      if (data is Map<String, dynamic>) {
        final rated = data['rated'];
        if (rated is Map<String, dynamic> && rated['value'] is num) {
          final remoteRating = (rated['value'] as num).toDouble();
          if (remoteRating > 0) {
            final fullKeys = _interactionKeys(
              tmdbId: tmdbId,
              imdbId: imdbId,
              mediaType: normType,
            );
            for (final k in fullKeys) {
              _ratingsCache[k] = remoteRating;
            }
            _patchMemoInteraction(
              tmdbId: tmdbId,
              imdbId: imdbId,
              mediaType: normType,
              userRating: remoteRating,
            );
            if (remoteRating >= kTmdbHalfRatingThreshold) {
              TmdbMovieDetails? cachedDetails;
              for (final k in fullKeys) {
                cachedDetails ??= _memo[k] ?? _coreMemo[k];
              }
              final candidate = buildMyListMeta(
                details: cachedDetails,
                tmdbId: tmdbId,
                imdbId: imdbId,
                mediaType: normType,
              );
              if (candidate != null) {
                _upsertLikedMeta(candidate, moveToFront: false);
              }
            }
            _notifyMyListListeners();
            unawaited(_persistInteractionsToDisk());
            return remoteRating;
          }
        }
      }
    } catch (_) {
      // Non-fatal if offline.
    }
    return getCachedUserRating(tmdbId: tmdbId, imdbId: imdbId, mediaType: mediaType);
  }

  static final RegExp _animeSeasonSuffixRe = RegExp(
    r'(?::\s*|\s+)(?:Season\s+\d+|Part\s+\d+|Cour\s+\d+|\d+(?:st|nd|rd|th)\s+Season)\s*$',
    caseSensitive: false,
  );

  Future<({List<String> titles, int? year, String? mediaType})?> _fetchAnilistMediaMeta(
    int anilistId,
  ) async {
    try {
      final res = await _dio.post<dynamic>(
        ApiConstants.anilistGraphQLUrl,
        data: {
          'query':
              'query (\$id: Int) { Media(id: \$id, type: ANIME) { title { english romaji native } seasonYear format } }',
          'variables': {'id': anilistId},
        },
        options: Options(
          contentType: Headers.jsonContentType,
          sendTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
      final data = res.data;
      if (data is! Map<String, dynamic>) return null;
      final media = _map(_map(data['data'])['Media']);
      if (media.isEmpty) return null;
      final rawTitle = _map(media['title']);
      final titles = <String>{
        for (final key in ['english', 'romaji', 'native'])
          if (_str(rawTitle[key]).isNotEmpty) _str(rawTitle[key]),
      }.toList();
      if (titles.isEmpty) return null;
      final year = (media['seasonYear'] as num?)?.toInt();
      final format = _str(media['format']).toUpperCase();
      final mediaType = format == 'MOVIE' ? 'movie' : (format.isNotEmpty ? 'series' : null);
      return (titles: titles, year: year, mediaType: mediaType);
    } catch (_) {
      return null;
    }
  }

  Future<({int tmdbId, String mediaType})?> _searchTmdbTargetOnce(
    String query, {
    required String mediaType,
    int? year,
    required bool preferAnimation,
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return null;
    final normType = _normalizeType(mediaType);
    final endpoint = normType == 'series' ? '/search/tv' : '/search/movie';
    try {
      final json = await _getJson(endpoint, {
        'query': cleanQuery,
        'include_adult': 'false',
        if (year != null) (normType == 'movie' ? 'year' : 'first_air_date_year'): '$year',
      });
      final results = _maps(json['results']);
      if (results.isEmpty) return null;
      Map<String, dynamic>? chosen;
      if (preferAnimation) {
        for (final r in results) {
          if (r['id'] is! num) continue;
          final genres = r['genre_ids'];
          if (genres is List && genres.contains(16)) {
            chosen = r;
            break;
          }
          chosen ??= r;
        }
      } else {
        for (final r in results) {
          if (r['id'] is num) {
            chosen = r;
            break;
          }
        }
      }
      if (chosen == null || chosen['id'] is! num) return null;
      return (tmdbId: (chosen['id'] as num).toInt(), mediaType: normType);
    } catch (_) {
      return null;
    }
  }

  Future<({int tmdbId, String mediaType})?> _searchTmdbTargetByTitle({
    required List<String> titles,
    int? year,
    required String mediaType,
    bool preferAnimation = true,
  }) async {
    final uniqueTitles = <String>{
      for (final t in titles)
        if (t.trim().isNotEmpty) t.trim(),
    }.toList();
    if (uniqueTitles.isEmpty) return null;

    final normType = _normalizeType(mediaType);
    final altType = normType == 'series' ? 'movie' : 'series';

    for (final tryType in [normType, altType]) {
      for (final rawTitle in uniqueTitles) {
        if (year != null) {
          final withYear = await _searchTmdbTargetOnce(
            rawTitle,
            mediaType: tryType,
            year: year,
            preferAnimation: preferAnimation,
          );
          if (withYear != null) return withYear;
        }
        final stripped = rawTitle.replaceAll(_animeSeasonSuffixRe, '').trim();
        final candidate = stripped.isNotEmpty ? stripped : rawTitle;
        final withoutYear = await _searchTmdbTargetOnce(
          candidate,
          mediaType: tryType,
          preferAnimation: preferAnimation,
        );
        if (withoutYear != null) return withoutYear;
        if (stripped.isNotEmpty && stripped != rawTitle) {
          final rawNoYear = await _searchTmdbTargetOnce(
            rawTitle,
            mediaType: tryType,
            preferAnimation: preferAnimation,
          );
          if (rawNoYear != null) return rawNoYear;
        }
      }
    }
    return null;
  }

  Future<({int tmdbId, String mediaType})?> _resolveTmdbTarget({
    int? tmdbId,
    String? imdbId,
    required String mediaType,
    MetaModel? meta,
    AnimeIdMap? animeIdMap,
  }) async {
    final normType = _normalizeType(mediaType);
    final effectiveMap = animeIdMap ?? _animeIdMap;
    if (tmdbId != null && tmdbId > 0) {
      if (imdbId != null &&
          imdbId.trim().isNotEmpty &&
          !imdbId.trim().startsWith('anilist:')) {
        final trimmed = imdbId.trim();
        final clean = trimmed.startsWith('tt') ? trimmed : 'tt$trimmed';
        final cached = _imdbToTmdbCache[clean];
        if (cached != null && cached.tmdbId == tmdbId) return cached;
      }
      return (tmdbId: tmdbId, mediaType: normType);
    }
    if (imdbId == null || imdbId.trim().isEmpty) return null;
    final trimmed = imdbId.trim();
    if (trimmed.startsWith('anilist:')) {
      final anilistId = int.tryParse(trimmed.substring('anilist:'.length));
      if (anilistId == null || anilistId <= 0) return null;

      final cachedAnilist = _anilistToTmdbCache[anilistId];
      if (cachedAnilist != null) return cachedAnilist;

      await effectiveMap?.ensureLoaded();
      final mapped = effectiveMap?.lookupByAnilistId(anilistId);
      if (mapped != null) {
        final mappedType = mapped.isMovie ? 'movie' : 'series';
        if (mapped.tmdbId != null && mapped.tmdbId! > 0) {
          _registerAnilistPair(anilistId, mapped.tmdbId!, mappedType);
          return (tmdbId: mapped.tmdbId!, mediaType: mappedType);
        }
        if (mapped.imdbId != null && mapped.imdbId!.isNotEmpty) {
          final byImdb = await _resolveTmdbTarget(
            imdbId: mapped.imdbId,
            mediaType: mappedType,
            meta: meta,
            animeIdMap: effectiveMap,
          );
          if (byImdb != null) {
            _registerAnilistPair(anilistId, byImdb.tmdbId, byImdb.mediaType);
            return byImdb;
          }
        }
      }

      final candidateTitles = <String>[];
      int? candidateYear;
      var effectiveType = mapped != null ? (mapped.isMovie ? 'movie' : 'series') : normType;
      final cachedMeta = meta ?? _findCachedMetaFor(imdbId: trimmed, mediaType: normType);
      if (cachedMeta != null && cachedMeta.name.trim().isNotEmpty) {
        candidateTitles.add(cachedMeta.name.trim());
        candidateYear = int.tryParse(cachedMeta.releaseInfo?.trim() ?? '');
      }
      if (candidateTitles.isEmpty) {
        final aniMeta = await _fetchAnilistMediaMeta(anilistId);
        if (aniMeta != null) {
          candidateTitles.addAll(aniMeta.titles);
          candidateYear ??= aniMeta.year;
          if (mapped == null && aniMeta.mediaType != null) {
            effectiveType = aniMeta.mediaType!;
          }
        }
      }

      if (candidateTitles.isNotEmpty) {
        final searched = await _searchTmdbTargetByTitle(
          titles: candidateTitles,
          year: candidateYear,
          mediaType: effectiveType,
          preferAnimation: true,
        );
        if (searched != null) {
          _registerAnilistPair(anilistId, searched.tmdbId, searched.mediaType);
          return searched;
        }
      }

      if (mapped?.fallbackTvTmdbId != null && mapped!.fallbackTvTmdbId! > 0) {
        final tvId = mapped.fallbackTvTmdbId!;
        _registerAnilistPair(anilistId, tvId, 'series');
        return (tmdbId: tvId, mediaType: 'series');
      }
      return null;
    }

    final parsed = int.tryParse(trimmed);
    if (parsed != null && parsed > 0) {
      return (tmdbId: parsed, mediaType: normType);
    }

    final cleanImdb = trimmed.startsWith('tt') ? trimmed : 'tt$trimmed';
    final cached = _imdbToTmdbCache[cleanImdb];
    if (cached != null) return cached;

    try {
      final found = await _getJson(
        '/find/$cleanImdb',
        {'external_source': 'imdb_id'},
      );
      final primaryKey = normType == 'series' ? 'tv_results' : 'movie_results';
      final fallbackKey = normType == 'series' ? 'movie_results' : 'tv_results';
      final primaryHits = _maps(found[primaryKey]);
      final fallbackHits = _maps(found[fallbackKey]);
      if (primaryHits.isNotEmpty && primaryHits.first['id'] is num) {
        final resolved = (primaryHits.first['id'] as num).toInt();
        _registerIdPair(resolved, cleanImdb, normType);
        return (tmdbId: resolved, mediaType: normType);
      }
      if (fallbackHits.isNotEmpty && fallbackHits.first['id'] is num) {
        final resolved = (fallbackHits.first['id'] as num).toInt();
        final altType = normType == 'series' ? 'movie' : 'series';
        _registerIdPair(resolved, cleanImdb, altType);
        return (tmdbId: resolved, mediaType: altType);
      }
    } catch (_) {}

    await effectiveMap?.ensureLoaded();
    final mapEntry = effectiveMap?.lookupByImdbId(cleanImdb);
    if (mapEntry != null && mapEntry.tmdbId != null && mapEntry.tmdbId! > 0) {
      final mapType = mapEntry.isMovie ? 'movie' : 'series';
      _registerIdPair(mapEntry.tmdbId!, cleanImdb, mapType);
      return (tmdbId: mapEntry.tmdbId!, mediaType: mapType);
    }

    final cachedMeta = meta ?? _findCachedMetaFor(imdbId: cleanImdb, mediaType: normType);
    if (cachedMeta != null && cachedMeta.name.trim().isNotEmpty) {
      final preferAnimation = mapEntry != null ||
          _hasAnimeSignal(
            imdbId: cleanImdb,
            mediaType: normType,
            keys: _interactionKeys(imdbId: cleanImdb, mediaType: normType),
            meta: cachedMeta,
          );
      final searched = await _searchTmdbTargetByTitle(
        titles: [cachedMeta.name.trim()],
        year: int.tryParse(cachedMeta.releaseInfo?.trim() ?? ''),
        mediaType: mapEntry != null ? (mapEntry.isMovie ? 'movie' : 'series') : normType,
        preferAnimation: preferAnimation,
      );
      if (searched != null) {
        _registerIdPair(searched.tmdbId, cleanImdb, searched.mediaType);
        return searched;
      }
    }

    if (mapEntry?.fallbackTvTmdbId != null && mapEntry!.fallbackTvTmdbId! > 0) {
      final tvId = mapEntry.fallbackTvTmdbId!;
      _registerIdPair(tvId, cleanImdb, 'series');
      return (tmdbId: tvId, mediaType: 'series');
    }
    return null;
  }

  static bool _isTmdbNotFoundResponse(int? statusCode, dynamic data) {
    if (statusCode == 404) return true;
    return data is Map && data['status_code'] == 34;
  }

  static bool _isTmdbNotFoundException(Object error) {
    if (error is DioException) {
      return _isTmdbNotFoundResponse(
        error.response?.statusCode,
        error.response?.data,
      );
    }
    return false;
  }

  static bool _isUnauthorizedResponseOrError(
    Object? error,
    int? statusCode,
    dynamic data,
  ) {
    if (statusCode == 401) return true;
    if (data is Map && (data['status_code'] == 3 || data['status_code'] == 30)) {
      return true;
    }
    if (error is DioException) {
      final s = error.response?.statusCode;
      final d = error.response?.data;
      if (s == 401) return true;
      if (d is Map && (d['status_code'] == 3 || d['status_code'] == 30)) {
        return true;
      }
    }
    return false;
  }

  void _markSessionExpired([Object? error]) {
    if (_userSessionId == null || _userSessionId!.isEmpty) return;
    _sessionExpired = true;
    _lastSyncSucceeded = false;
    _lastSyncError = error != null
        ? _friendlySyncError(error)
        : 'TMDB session expired. Tap Reconnect below to back up your My List & Likes.';
    if (_myListCache.isNotEmpty ||
        _ratingsCache.isNotEmpty ||
        pendingSyncCount > 0) {
      _needsLocalPush = true;
    }
    _pendingFlushTimer?.cancel();
    _pendingFlushTimer = null;
    _notifyMyListListeners();
    unawaited(_persistInteractionsToDisk());
  }

  Future<({bool ok, int? tmdbId, String? mediaType, bool unauthorized})>
      _submitWithMediaTypeFallback({
    required int tmdbId,
    required String mediaType,
    required String? imdbId,
    required Future<Response<dynamic>> Function(String type) send,
  }) async {
    Future<
        ({
          bool retry,
          ({bool ok, int? tmdbId, String? mediaType, bool unauthorized}) result
        })> attempt(String attemptType) async {
      try {
        final res = await send(attemptType);
        final data = res.data;
        if (_isUnauthorizedResponseOrError(null, res.statusCode, data)) {
          return (
            retry: false,
            result: (
              ok: false,
              tmdbId: tmdbId,
              mediaType: attemptType,
              unauthorized: true,
            ),
          );
        }
        if (_isTmdbNotFoundResponse(res.statusCode, data)) {
          return (
            retry: true,
            result: (
              ok: false,
              tmdbId: tmdbId,
              mediaType: attemptType,
              unauthorized: false,
            ),
          );
        }
        if (data is Map && data['success'] == false) {
          return (
            retry: false,
            result: (
              ok: false,
              tmdbId: tmdbId,
              mediaType: attemptType,
              unauthorized: false,
            ),
          );
        }
        return (
          retry: false,
          result: (
            ok: true,
            tmdbId: tmdbId,
            mediaType: attemptType,
            unauthorized: false,
          ),
        );
      } catch (e) {
        final unauthorized = _isUnauthorizedResponseOrError(e, null, null);
        return (
          retry: !unauthorized && _isTmdbNotFoundException(e),
          result: (
            ok: false,
            tmdbId: tmdbId,
            mediaType: attemptType,
            unauthorized: unauthorized,
          ),
        );
      }
    }

    final first = await attempt(mediaType);
    if (!first.retry) return first.result;

    final altType = mediaType == 'series' ? 'movie' : 'series';
    final fallback = await attempt(altType);
    if (fallback.result.ok) {
      _registerIdPair(tmdbId, imdbId, altType);
      return fallback.result;
    }
    return fallback.result.unauthorized ? fallback.result : first.result;
  }

  Future<({bool ok, int? tmdbId, String? mediaType})> _submitTmdbRating({
    int? tmdbId,
    String? imdbId,
    required String mediaType,
    required double? rating,
    MetaModel? meta,
    AnimeIdMap? animeIdMap,
  }) async {
    final sessionId = _userSessionId;
    if (sessionId == null || sessionId.isEmpty) {
      return (ok: false, tmdbId: tmdbId, mediaType: mediaType);
    }

    final effectiveMeta = meta ??
        _findCachedMetaFor(tmdbId: tmdbId, imdbId: imdbId, mediaType: mediaType);
    final target = await _resolveTmdbTarget(
      tmdbId: tmdbId,
      imdbId: imdbId,
      mediaType: mediaType,
      meta: effectiveMeta,
      animeIdMap: animeIdMap,
    );
    if (target == null) return (ok: false, tmdbId: null, mediaType: null);

    final query = {
      'api_key': ApiConstants.tmdbApiKey,
      'session_id': sessionId,
    };
    final res = await _submitWithMediaTypeFallback(
      tmdbId: target.tmdbId,
      mediaType: target.mediaType,
      imdbId: imdbId,
      send: (type) {
        final resource = _resourceFor(type);
        final url = '${ApiConstants.tmdbBaseUrl}/$resource/${target.tmdbId}/rating';
        if (rating == null || rating <= 0) {
          return _dio.delete<dynamic>(url, queryParameters: query);
        }
        return _dio.post<dynamic>(
          url,
          queryParameters: query,
          data: {'value': rating},
          options: Options(contentType: Headers.jsonContentType),
        );
      },
    );
    if (res.unauthorized) {
      _markSessionExpired(const TmdbException('', statusCode: 401));
    } else if (res.ok && _sessionExpired) {
      _sessionExpired = false;
    }
    return (ok: res.ok, tmdbId: res.tmdbId, mediaType: res.mediaType);
  }

  Future<({bool ok, int? tmdbId, String? mediaType})> _submitTmdbWatchlist({
    int? tmdbId,
    String? imdbId,
    required String mediaType,
    required bool watchlist,
    MetaModel? meta,
    AnimeIdMap? animeIdMap,
  }) async {
    final sessionId = _userSessionId;
    if (sessionId == null || sessionId.isEmpty) {
      return (ok: false, tmdbId: tmdbId, mediaType: mediaType);
    }

    final effectiveMeta = meta ??
        _findCachedMetaFor(tmdbId: tmdbId, imdbId: imdbId, mediaType: mediaType);
    final target = await _resolveTmdbTarget(
      tmdbId: tmdbId,
      imdbId: imdbId,
      mediaType: mediaType,
      meta: effectiveMeta,
      animeIdMap: animeIdMap,
    );
    if (target == null) return (ok: false, tmdbId: null, mediaType: null);

    var accountId = _accountProfile?.id;
    if (accountId == null) {
      try {
        accountId = (await fetchAndStoreAccountProfile(sessionId)).id;
      } catch (e) {
        if (_isUnauthorizedError(e)) {
          _markSessionExpired(e);
        }
      }
    }
    if (accountId == null) {
      return (ok: false, tmdbId: target.tmdbId, mediaType: target.mediaType);
    }

    final url = '${ApiConstants.tmdbBaseUrl}/account/$accountId/watchlist';
    final query = {
      'api_key': ApiConstants.tmdbApiKey,
      'session_id': sessionId,
    };
    final res = await _submitWithMediaTypeFallback(
      tmdbId: target.tmdbId,
      mediaType: target.mediaType,
      imdbId: imdbId,
      send: (type) => _dio.post<dynamic>(
        url,
        queryParameters: query,
        data: {
          'media_type': _resourceFor(type),
          'media_id': target.tmdbId,
          'watchlist': watchlist,
        },
        options: Options(contentType: Headers.jsonContentType),
      ),
    );
    if (res.unauthorized) {
      _markSessionExpired(const TmdbException('', statusCode: 401));
    } else if (res.ok && _sessionExpired) {
      _sessionExpired = false;
    }
    return (ok: res.ok, tmdbId: res.tmdbId, mediaType: res.mediaType);
  }

  static String _normalizeType(String? type) =>
      (type == 'series' || type == 'tv') ? 'series' : 'movie';

  static String _resourceFor(String mediaType) =>
      mediaType == 'series' ? 'tv' : 'movie';

  static String _cacheKey(String idOrImdbId, String mediaType) {
    final trimmed = idOrImdbId.trim();
    if (trimmed.startsWith('anilist:')) return '$mediaType:$trimmed';
    if (int.tryParse(trimmed) != null) return '$mediaType:tmdb:$trimmed';
    final cleanImdb = trimmed.startsWith('tt') ? trimmed : 'tt$trimmed';
    return '$mediaType:imdb:$cleanImdb';
  }

  void _registerIdPair(int tmdbId, String? imdbId, String mediaType) {
    if (imdbId == null || imdbId.isEmpty) return;
    final trimmed = imdbId.trim();
    if (trimmed.startsWith('anilist:')) return;
    final cleanImdb = trimmed.startsWith('tt') ? trimmed : 'tt$trimmed';
    final normType = _normalizeType(mediaType);
    final altType = normType == 'series' ? 'movie' : 'series';
    _tmdbToImdbCache['$normType:$tmdbId'] = cleanImdb;
    _imdbToTmdbCache[cleanImdb] = (tmdbId: tmdbId, mediaType: normType);

    final newTmdbKey = _cacheKey('$tmdbId', normType);
    final newImdbKey = _cacheKey(cleanImdb, normType);
    final altImdbKey = _cacheKey(cleanImdb, altType);
    final relatedKeys = [newTmdbKey, newImdbKey, altImdbKey];

    if (relatedKeys.any(_animeKeys.contains)) {
      _animeKeys
        ..add(newTmdbKey)
        ..add(newImdbKey);
    }
    int? linkedAnilist;
    for (final k in relatedKeys) {
      final v = _keyToAnilistCache[k];
      if (v != null && v > 0) {
        linkedAnilist = v;
        break;
      }
    }
    if (linkedAnilist != null) {
      _animeKeys
        ..add(newTmdbKey)
        ..add(newImdbKey);
      _keyToAnilistCache[newTmdbKey] = linkedAnilist;
      _keyToAnilistCache[newImdbKey] = linkedAnilist;
      _anilistToTmdbCache[linkedAnilist] = (tmdbId: tmdbId, mediaType: normType);
    }
    if (_pendingWatchlistFor(relatedKeys) != false &&
        (_myListCache.contains(newTmdbKey) ||
            _myListCache.contains(newImdbKey) ||
            _myListCache.contains(altImdbKey))) {
      _myListCache
        ..add(newTmdbKey)
        ..add(newImdbKey);
    }
    if (_pendingRatingFor(relatedKeys) != 0.0) {
      double? linkedRating;
      for (final k in relatedKeys) {
        final r = _ratingsCache[k];
        if (r != null && r > 0) {
          linkedRating = r;
          break;
        }
      }
      if (linkedRating != null) {
        _ratingsCache.putIfAbsent(newTmdbKey, () => linkedRating!);
        _ratingsCache.putIfAbsent(newImdbKey, () => linkedRating!);
      }
    }
  }

  void _registerAnilistPair(int anilistId, int tmdbId, String mediaType) {
    if (anilistId <= 0 || tmdbId <= 0) return;
    final normType = _normalizeType(mediaType);
    _anilistToTmdbCache[anilistId] = (tmdbId: tmdbId, mediaType: normType);

    final tmdbKey = _cacheKey('$tmdbId', normType);
    final aniKey = _cacheKey('anilist:$anilistId', normType);
    final altType = normType == 'series' ? 'movie' : 'series';
    final altAniKey = _cacheKey('anilist:$anilistId', altType);

    _animeKeys
      ..add(tmdbKey)
      ..add(aniKey);
    _keyToAnilistCache[tmdbKey] = anilistId;
    _keyToAnilistCache[aniKey] = anilistId;

    final mappedImdb = _cachedImdbFor(tmdbId, normType);
    final imdbKey = mappedImdb != null ? _cacheKey(mappedImdb, normType) : null;
    if (imdbKey != null) {
      _animeKeys.add(imdbKey);
      _keyToAnilistCache[imdbKey] = anilistId;
    }

    _animeIdMap?.registerRuntimeMapping(
      anilistId: anilistId,
      tmdbId: tmdbId,
      imdbId: mappedImdb,
      isMovie: normType == 'movie',
    );

    final relatedKeys = <String>[
      aniKey,
      altAniKey,
      tmdbKey,
      if (imdbKey != null) imdbKey,
    ];
    if (_pendingWatchlistFor(relatedKeys) != false &&
        relatedKeys.any(_myListCache.contains)) {
      _myListCache.add(tmdbKey);
      if (imdbKey != null) _myListCache.add(imdbKey);
    }
    if (_pendingRatingFor(relatedKeys) != 0.0) {
      double? linkedRating;
      for (final k in relatedKeys) {
        final r = _ratingsCache[k];
        if (r != null && r > 0) {
          linkedRating = r;
          break;
        }
      }
      if (linkedRating != null) {
        _ratingsCache.putIfAbsent(tmdbKey, () => linkedRating!);
        if (imdbKey != null) _ratingsCache.putIfAbsent(imdbKey, () => linkedRating!);
      }
    }
  }

  String? _cachedImdbFor(int tmdbId, String mediaType) =>
      _tmdbToImdbCache['${_normalizeType(mediaType)}:$tmdbId'];

  /// Returns a synchronously cached season if already resolved (e.g., bundled
  /// via `append_to_response=season/1`), dynamically filtering out unreleased
  /// episodes and invalidating the cache if a newly released episode needs
  /// fresh post-release metadata from TMDB.
  TmdbSeasonDetails? getCachedSeason(int tvTmdbId, int seasonNumber) {
    final key = '$tvTmdbId:S$seasonNumber';
    final cached = _seasonMemo[key];
    if (cached == null) return null;
    if (cached.hasNewlyReleasedIncompleteEpisode()) {
      _seasonMemo.remove(key);
      return null;
    }
    final updated = cached.filterReleased();
    _seasonMemo[key] = updated;
    return updated;
  }

  /// Stores a resolved details payload under both its IMDb key and TMDB key so
  /// subsequent lookups by either identifier hit memory in O(1).
  void _storeCore(String requestKey, TmdbMovieDetails details) {
    _coreMemo[requestKey] = details;
    _coreMemo[_cacheKey('${details.tmdbId}', details.mediaType)] = details;
    if (details.imdbId != null && details.imdbId!.isNotEmpty) {
      _coreMemo[_cacheKey(details.imdbId!, details.mediaType)] = details;
    }
  }

  void _storeFull(String requestKey, TmdbMovieDetails details) {
    _storeCore(requestKey, details);
    _memo[requestKey] = details;
    _memo[_cacheKey('${details.tmdbId}', details.mediaType)] = details;
    if (details.imdbId != null && details.imdbId!.isNotEmpty) {
      _memo[_cacheKey(details.imdbId!, details.mediaType)] = details;
    }
  }

  /// Searches TMDB (`/search/movie` or `/search/tv`) using the user's TMDB API
  /// key and returns poster-bearing [MetaModel] results ready for [PosterRow]
  /// and [DetailScreen].
  ///
  /// When [onEnriched] is provided, the top [kViewportPriorityCount] items have
  /// their IMDb IDs resolved in the background so `btttr.cc` posters can upgrade
  /// seamlessly without delaying the initial search row render.
  Future<List<MetaModel>> searchMedia(
    String query, {
    required String type,
    CancelToken? cancelToken,
    void Function(List<MetaModel>)? onEnriched,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final normType = _normalizeType(type);
    final endpoint = normType == 'series' ? '/search/tv' : '/search/movie';
    final json = await _getJson(
      endpoint,
      {
        'query': trimmed,
        'include_adult': 'false',
      },
      cancelToken: cancelToken,
    );

    final rawList = _maps(json['results']);
    final seenIds = <int>{};
    final entries = <({int tmdbId, MetaModel meta})>[];
    final currentNow = _clock?.call();

    for (final r in rawList) {
      if (r['id'] is! num) continue;
      final tmdbId = (r['id'] as num).toInt();
      if (!seenIds.add(tmdbId)) continue;

      final posterPath = _str(r['poster_path']);
      if (posterPath.isEmpty) continue;

      final title = _str(r['title']).isNotEmpty ? _str(r['title']) : _str(r['name']);
      if (title.isEmpty) continue;

      if (!_isTmdbItemReleased(r, isSeries: normType == 'series', now: currentNow)) {
        continue;
      }

      final posterUrl = _img(posterPath, 'w342');
      final backdropUrl = _img(r['backdrop_path'], 'w780');
      final releaseDate = _str(r['release_date']).isNotEmpty
          ? _str(r['release_date'])
          : _str(r['first_air_date']);
      final releaseYear = releaseDate.length >= 4 ? releaseDate.substring(0, 4) : null;
      final vote = r['vote_average'];
      final rating = vote is num && vote > 0 ? vote.toDouble().toStringAsFixed(1) : null;
      final overview = _str(r['overview']);

      final cachedImdb = _cachedImdbFor(tmdbId, normType);
      entries.add((
        tmdbId: tmdbId,
        meta: MetaModel(
          id: cachedImdb ?? '$tmdbId',
          type: normType,
          name: title,
          poster: cachedImdb != null ? betterPosterUrl(cachedImdb) : posterUrl,
          posterFallback: posterUrl,
          background: backdropUrl,
          description: overview.isNotEmpty ? overview : null,
          releaseInfo: releaseYear,
          imdbRating: rating,
        ),
      ));
    }

    final initialMetas = [for (final e in entries) e.meta];

    if (onEnriched != null && entries.isNotEmpty && !(cancelToken?.isCancelled ?? false)) {
      final unenrichedTop = entries
          .take(kViewportPriorityCount)
          .where((e) => _cachedImdbFor(e.tmdbId, normType) == null)
          .toList();
      if (unenrichedTop.isNotEmpty) {
        unawaited(() async {
          await Future.wait(
            unenrichedTop.map(
              (e) => _resolveImdbId(e.tmdbId, mediaType: normType, cancelToken: cancelToken),
            ),
          ).catchError((_) => <String?>[]);
          if (cancelToken?.isCancelled ?? false) return;
          final enriched = [
            for (final e in entries)
              () {
                final imdb = _cachedImdbFor(e.tmdbId, normType);
                if (imdb == null) return e.meta;
                return e.meta.copyWith(
                  id: imdb,
                  poster: betterPosterUrl(imdb),
                );
              }(),
          ];
          onEnriched(enriched);
        }());
      }
    }

    return initialMetas;
  }

  /// Backwards-compatible full fetch for a movie (core metadata + enriched
  /// recommendation IMDb IDs).
  Future<TmdbMovieDetails> fetchMovie(String imdbId, {CancelToken? cancelToken}) =>
      fetchMediaDetails(imdbId, type: 'movie', cancelToken: cancelToken);

  /// Full fetch (core metadata + enriched external IDs) for a movie or series.
  Future<TmdbMovieDetails> fetchMediaDetails(
    String idOrImdbId, {
    String type = 'movie',
    CancelToken? cancelToken,
  }) {
    final normType = _normalizeType(type);
    final key = _cacheKey(idOrImdbId, normType);
    final cached = _memo[key];
    if (cached != null) {
      return Future.value(_withLiveInteractionState(cached, lookupId: idOrImdbId));
    }

    return _inflight.putIfAbsent(key, () {
      final request = () async {
        final core = await fetchCoreDetails(
          idOrImdbId,
          type: normType,
          cancelToken: cancelToken,
        );
        final enriched = await enrichExternalIds(core, cancelToken: cancelToken);
        final live = _withLiveInteractionState(enriched, lookupId: idOrImdbId);
        _storeFull(key, live);
        return live;
      }();
      request.then((_) {}, onError: (_) {}).whenComplete(() => _inflight.remove(key));
      return request;
    });
  }

  /// Phase 1: Fetches primary movie or series metadata in 1–2 RTTs without
  /// blocking on the 40 secondary `/external_ids` calls.
  Future<TmdbMovieDetails> fetchCoreDetails(
    String idOrImdbId, {
    String type = 'movie',
    CancelToken? cancelToken,
  }) {
    final normType = _normalizeType(type);
    final key = _cacheKey(idOrImdbId, normType);

    final fullCached = _memo[key];
    if (fullCached != null) {
      return Future.value(_withLiveInteractionState(fullCached, lookupId: idOrImdbId));
    }

    final coreCached = _coreMemo[key];
    if (coreCached != null) {
      return Future.value(_withLiveInteractionState(coreCached, lookupId: idOrImdbId));
    }

    return _inflightCore.putIfAbsent(key, () {
      final future = _fetchCoreInternal(
        idOrImdbId,
        preferredType: normType,
        cancelToken: cancelToken,
      );
      future
          .then((details) {
            if (details.title.trim().isNotEmpty) {
              _storeCore(key, details);
            }
          }, onError: (_) {})
          .whenComplete(() => _inflightCore.remove(key));
      return future;
    });
  }

  Future<TmdbMovieDetails> _fetchCoreInternal(
    String idOrImdbId, {
    required String preferredType,
    CancelToken? cancelToken,
  }) async {
    await ensureInteractionsLoaded();
    final trimmed = idOrImdbId.trim();
    int tmdbId;
    String resolvedType = preferredType;
    String? knownImdbId;

    final parsedNumeric = int.tryParse(trimmed);
    if (parsedNumeric != null) {
      tmdbId = parsedNumeric;
      knownImdbId = _cachedImdbFor(tmdbId, resolvedType);
    } else if (trimmed.startsWith('anilist:')) {
      await _animeIdMap?.ensureLoaded();
      final target = await _resolveTmdbTarget(
        imdbId: trimmed,
        mediaType: preferredType,
        animeIdMap: _animeIdMap,
      );
      if (target == null) {
        throw const TmdbException('Title not found on TMDB');
      }
      tmdbId = target.tmdbId;
      resolvedType = target.mediaType;
      knownImdbId = _cachedImdbFor(tmdbId, resolvedType);
    } else {
      final cleanImdb = trimmed.startsWith('tt') ? trimmed : 'tt$trimmed';
      knownImdbId = cleanImdb;

      final target = await _resolveTmdbTarget(
        imdbId: cleanImdb,
        mediaType: preferredType,
        animeIdMap: _animeIdMap,
      );
      if (target == null) {
        throw const TmdbException('Title not found on TMDB');
      }
      tmdbId = target.tmdbId;
      resolvedType = target.mediaType;
    }

    final resource = _resourceFor(resolvedType);
    // Bundle `season/1` directly in the `/tv/{id}` request so Season 1 episodes
    // resolve in the same single HTTP round-trip as the series metadata.
    // When a valid user session is active, also bundle `account_states` so user rating
    // and watchlist status resolve in Phase 1 with zero extra round-trips.
    final baseAppend = resolvedType == 'series'
        ? 'credits,recommendations,similar,images,external_ids,keywords,season/1'
        : 'credits,recommendations,similar,images,external_ids,keywords';
    final includeAccountStates = isAuthenticated && !_sessionExpired;
    final append = includeAccountStates ? '$baseAppend,account_states' : baseAppend;

    late final Map<String, dynamic> json;
    try {
      json = await _getJson(
        '/$resource/$tmdbId',
        {
          'append_to_response': append,
          'include_image_language': 'en,null',
        },
        cancelToken: cancelToken,
      );
    } on TmdbException catch (e) {
      if (e.statusCode == 401 && includeAccountStates) {
        _markSessionExpired(e);
        json = await _getJson(
          '/$resource/$tmdbId',
          {
            'append_to_response': baseAppend,
            'include_image_language': 'en,null',
          },
          cancelToken: cancelToken,
        );
      } else {
        rethrow;
      }
    }

    TmdbSeasonDetails? bundledSeason1;
    if (resolvedType == 'series' && json['season/1'] is Map<String, dynamic>) {
      bundledSeason1 = _parseSeasonJson(_map(json['season/1']), 1);
      _seasonMemo['$tmdbId:S1'] = bundledSeason1;
    }

    final externalIdsMap = _map(json['external_ids']);
    final responseImdb = _str(json['imdb_id']).isNotEmpty
        ? _str(json['imdb_id'])
        : _str(externalIdsMap['imdb_id']);
    final finalImdbId = responseImdb.isNotEmpty ? responseImdb : knownImdbId;
    _registerIdPair(tmdbId, finalImdbId, resolvedType);

    final images = _map(json['images']);
    final textlessPoster = _bestImage(_maps(images['posters']), textless: true);
    final logo = _bestImage(_maps(images['logos']), preferEnglish: true);

    final cast = <TmdbCast>[
      for (final c in _maps(_map(json['credits'])['cast']).take(20))
        TmdbCast(
          name: _str(c['name']),
          character: _str(c['character']),
          profileUrl: _img(c['profile_path'], 'w185'),
        ),
    ].where((c) => c.name.isNotEmpty).toList();

    final currentNow = _clock?.call();
    final rawRecs = _parseRecommendations(
      _map(json['recommendations'])['results'],
      defaultMediaType: resolvedType,
      onlyReleased: false,
      now: currentNow,
    );
    final rawSimilar = _parseRecommendations(
      _map(json['similar'])['results'],
      defaultMediaType: resolvedType,
      onlyReleased: false,
      now: currentNow,
    );

    // Attach any IMDb IDs already present in session cache immediately.
    final allRecommendations = _projectCachedImdbIds(rawRecs);
    final allSimilar = _projectCachedImdbIds(rawSimilar);
    final recommendations = [
      for (final r in allRecommendations)
        if (r.isReleased(now: currentNow)) r,
    ];
    final similar = [
      for (final s in allSimilar)
        if (s.isReleased(now: currentNow)) s,
    ];

    final allResolved = recommendations.take(20).every((r) => r.imdbId != null) &&
        similar.take(20).every((s) => s.imdbId != null);

    final releaseDate = _str(json['release_date']).isNotEmpty
        ? _str(json['release_date'])
        : _str(json['first_air_date']);
    final runtime = _extractRuntimeMinutes(json);
    final vote = json['vote_average'];

    final seasons = resolvedType == 'series'
        ? _parseSeasons(
            json['seasons'],
            lastEpisodeToAir: _map(json['last_episode_to_air']),
            nextEpisodeToAir: _map(json['next_episode_to_air']),
            bundledSeason1: bundledSeason1,
          )
        : const <TmdbSeasonSummary>[];
    final numSeasons = json['number_of_seasons'];
    final numEpisodes = json['number_of_episodes'];

    final title = _str(json['title']).isNotEmpty ? _str(json['title']) : _str(json['name']);
    final origLang = _str(json['original_language']).trim().toLowerCase();
    final interactionKeys = _interactionKeys(
      tmdbId: tmdbId,
      imdbId: finalImdbId,
      mediaType: resolvedType,
    );

    final pendingRating = _pendingRatingFor(interactionKeys);
    final recentRating = _recentRatingFor(interactionKeys);
    final inlineUserRating = _extractUserRating(json);
    var learnedRemoteInteraction = false;
    if (pendingRating == null &&
        recentRating == null &&
        inlineUserRating != null &&
        inlineUserRating > 0) {
      for (final k in interactionKeys) {
        if (_ratingsCache[k] != inlineUserRating) {
          _ratingsCache[k] = inlineUserRating;
          learnedRemoteInteraction = true;
        }
      }
    }
    final pendingWatchlist = _pendingWatchlistFor(interactionKeys);
    final recentWatchlist = _recentWatchlistFor(interactionKeys);
    final inlineWatchlist = _extractWatchlistState(json);
    // Additive-only merge from `account_states`: a single title's `watchlist: false`
    // must never delete un-synced local / pre-TMDB / >500th My List entries;
    // explicit removals happen only via `setMyList(inMyList: false)` or full account sync.
    if (pendingWatchlist == null &&
        recentWatchlist == null &&
        inlineWatchlist == true) {
      for (final k in interactionKeys) {
        if (_myListCache.add(k)) {
          learnedRemoteInteraction = true;
        }
      }
    }
    final cachedUserRating = getCachedUserRating(
      tmdbId: tmdbId,
      imdbId: finalImdbId,
      mediaType: resolvedType,
    );
    final resolvedUserRating = pendingRating != null
        ? (pendingRating > 0 ? pendingRating : null)
        : (recentRating != null
            ? (recentRating > 0 ? recentRating : null)
            : (inlineUserRating ?? cachedUserRating));
    final cachedMyList = getCachedIsInMyList(
      tmdbId: tmdbId,
      imdbId: finalImdbId,
      mediaType: resolvedType,
    );
    final resolvedMyList = pendingWatchlist ??
        recentWatchlist ??
        ((inlineWatchlist == true) || cachedMyList);

    final keywordsWrapper = _map(json['keywords']);
    final rawKeywords = _maps(
      keywordsWrapper['keywords'] ?? keywordsWrapper['results'],
    );
    final keywordIds = [
      for (final kw in rawKeywords.take(12))
        if (kw['id'] is num) (kw['id'] as num).toInt(),
    ];
    final genreIds = [
      for (final g in _maps(json['genres']))
        if (g['id'] is num) (g['id'] as num).toInt(),
    ];
    final collectionMap = _map(json['belongs_to_collection']);
    final collectionId = collectionMap['id'] is num
        ? (collectionMap['id'] as num).toInt()
        : null;

    final detailsResult = TmdbMovieDetails(
      tmdbId: tmdbId,
      mediaType: resolvedType,
      imdbId: finalImdbId,
      originalLanguage: origLang.isNotEmpty ? origLang : null,
      title: title,
      overview: _str(json['overview']),
      backdropUrl: _img(json['backdrop_path'], 'w780'),
      posterUrl: _img(json['poster_path'], 'w500'),
      textlessPosterUrl: _img(textlessPoster?['file_path'], 'w780'),
      logoUrl: _img(logo?['file_path'], 'original'),
      genres: [for (final g in _maps(json['genres'])) _str(g['name'])]
          .where((g) => g.isNotEmpty)
          .toList(),
      releaseYear: releaseDate.length >= 4 ? releaseDate.substring(0, 4) : null,
      runtimeMinutes: runtime,
      voteAverage: vote is num && vote > 0 ? vote.toDouble() : null,
      cast: cast,
      recommendations: recommendations,
      similar: similar,
      allRecommendations: allRecommendations,
      allSimilar: allSimilar,
      numberOfSeasons: numSeasons is num && numSeasons > 0 ? numSeasons.toInt() : null,
      numberOfEpisodes: numEpisodes is num && numEpisodes > 0 ? numEpisodes.toInt() : null,
      seasons: seasons,
      isExternalIdsResolved: allResolved,
      userRating: resolvedUserRating,
      isInMyList: resolvedMyList,
      keywordIds: keywordIds,
      genreIds: genreIds,
      collectionId: collectionId,
    );

    _syncAnimeForDetails(detailsResult, lookupId: idOrImdbId);

    var shouldNotifyAndPersist = learnedRemoteInteraction;
    if (resolvedMyList) {
      for (final k in _interactionKeys(tmdbId: tmdbId, imdbId: finalImdbId, mediaType: resolvedType)) {
        _myListCache.add(k);
      }
      final enrichedMeta = buildMyListMeta(
        details: detailsResult,
        tmdbId: tmdbId,
        imdbId: finalImdbId,
        mediaType: resolvedType,
      );
      if (enrichedMeta != null) {
        _upsertMyListMeta(enrichedMeta, moveToFront: false);
        shouldNotifyAndPersist = true;
      }
    }
    if (resolvedUserRating != null && resolvedUserRating >= kTmdbHalfRatingThreshold) {
      final likedMeta = buildMyListMeta(
        details: detailsResult,
        tmdbId: tmdbId,
        imdbId: finalImdbId,
        mediaType: resolvedType,
      );
      if (likedMeta != null) {
        _upsertLikedMeta(likedMeta, moveToFront: false);
        shouldNotifyAndPersist = true;
      }
    }
    if (shouldNotifyAndPersist) {
      _notifyMyListListeners();
      unawaited(_persistInteractionsToDisk());
    }
    if (hasPendingSyncOps) {
      _schedulePendingFlushRetry();
    }

    return detailsResult;
  }

  static double? _extractUserRating(Map<String, dynamic> json) {
    final accountStates = json['account_states'];
    if (accountStates is Map<String, dynamic>) {
      final rated = accountStates['rated'];
      if (rated is Map<String, dynamic> && rated['value'] is num) {
        return (rated['value'] as num).toDouble();
      }
      if (rated is num) return rated.toDouble();
    }
    final directRated = json['rated'];
    if (directRated is Map<String, dynamic> && directRated['value'] is num) {
      return (directRated['value'] as num).toDouble();
    }
    if (directRated is num) return directRated.toDouble();
    if (json['user_rating'] is num) {
      return (json['user_rating'] as num).toDouble();
    }
    return null;
  }

  static bool? _extractWatchlistState(Map<String, dynamic> json) {
    final accountStates = json['account_states'];
    if (accountStates is Map<String, dynamic> && accountStates['watchlist'] is bool) {
      return accountStates['watchlist'] as bool;
    }
    if (json['watchlist'] is bool) return json['watchlist'] as bool;
    return null;
  }

  List<TmdbRecommendation> _projectCachedImdbIds(
    List<TmdbRecommendation> items,
  ) =>
      [
        for (final item in items)
          item.copyWith(
            imdbId: item.imdbId ?? _cachedImdbFor(item.id, item.mediaType),
          ),
      ];

  List<TmdbRecommendation> _visibleCollectionMovies(
    List<TmdbRecommendation> items, {
    int? excludeTmdbId,
    DateTime? now,
  }) =>
      [
        for (final m in items)
          if (m.id != excludeTmdbId && m.isReleased(now: now)) m,
      ];

  /// Returns the earliest upcoming calendar release date among unreleased
  /// movies in cached [collectionId] (excluding [excludeTmdbId]), or `null`.
  DateTime? getNextCollectionReleaseDate(
    int collectionId, {
    int? excludeTmdbId,
    DateTime? now,
  }) {
    final cached = _movieCollectionMemo[collectionId];
    if (cached == null || cached.isEmpty) return null;
    final refNow = now ?? _clock?.call();
    return nextRecommendationReleaseDate(
      cached.where((m) => m.id != excludeTmdbId),
      now: refNow,
    );
  }

  /// Returns cached franchise collection movies sorted by popularity descending,
  /// excluding unreleased titles and [excludeTmdbId] (the movie open in Details).
  List<TmdbRecommendation>? getCachedCollectionMovies(
    int collectionId, {
    int? excludeTmdbId,
    DateTime? now,
  }) {
    final cached = _movieCollectionMemo[collectionId];
    if (cached == null) return null;
    final projected = _projectCachedImdbIds(cached);
    _movieCollectionMemo[collectionId] = projected;
    return _visibleCollectionMovies(
      projected,
      excludeTmdbId: excludeTmdbId,
      now: now ?? _clock?.call(),
    );
  }

  /// Fetches all movies belonging to TMDB [collectionId] (`/collection/{id}`),
  /// sorted strictly by popularity descending, excluding unreleased titles and
  /// [excludeTmdbId].
  Future<List<TmdbRecommendation>> fetchCollectionMovies(
    int collectionId, {
    int? excludeTmdbId,
    CancelToken? cancelToken,
    DateTime? now,
  }) async {
    final refNow = now ?? _clock?.call();
    final cached = getCachedCollectionMovies(
      collectionId,
      excludeTmdbId: excludeTmdbId,
      now: refNow,
    );
    if (cached != null) return cached;

    final allParts = await _inflightMovieCollections.putIfAbsent(collectionId, () {
      final future = _fetchCollectionMoviesInternal(
        collectionId,
        cancelToken: cancelToken,
      );
      future
          .then((parts) => _movieCollectionMemo[collectionId] = parts, onError: (_) {})
          .whenComplete(() => _inflightMovieCollections.remove(collectionId));
      return future;
    });

    final projected = _projectCachedImdbIds(allParts);
    _movieCollectionMemo[collectionId] = projected;
    return _visibleCollectionMovies(
      projected,
      excludeTmdbId: excludeTmdbId,
      now: refNow,
    );
  }

  Future<List<TmdbRecommendation>> _fetchCollectionMoviesInternal(
    int collectionId, {
    CancelToken? cancelToken,
  }) async {
    final json = await _getJson(
      '/collection/$collectionId',
      const {'language': 'en-US'},
      cancelToken: cancelToken,
    );
    final rawParts = [
      ..._maps(json['parts']),
      ..._maps(json['results']),
    ];
    final parsed = _parseRecommendations(
      rawParts,
      defaultMediaType: 'movie',
      sortByQualityTier: false,
      onlyReleased: false,
      collectionId: collectionId,
    );
    return _projectCachedImdbIds(parsed);
  }

  /// Resolves external IMDb IDs for visible released franchise collection items
  /// in two prioritized waves (viewport items first, remaining items in bounded
  /// batches) so Better Posters and direct navigation caching apply cleanly.
  Future<List<TmdbRecommendation>> enrichCollectionExternalIds(
    int collectionId, {
    int? excludeTmdbId,
    CancelToken? cancelToken,
    DateTime? now,
    void Function(List<TmdbRecommendation>)? onWave1Complete,
  }) async {
    final refNow = now ?? _clock?.call();
    final current = _movieCollectionMemo[collectionId];
    if (current == null || current.isEmpty) return const [];
    final projected = _projectCachedImdbIds(current);
    _movieCollectionMemo[collectionId] = projected;

    final visibleSlice = _visibleCollectionMovies(
      projected,
      excludeTmdbId: excludeTmdbId,
      now: refNow,
    );
    if (visibleSlice.isEmpty || visibleSlice.every((m) => m.imdbId != null)) {
      return visibleSlice;
    }

    await _resolveImdbWaves(
      groups: [visibleSlice],
      cancelToken: cancelToken,
      onWave1Complete: onWave1Complete == null
          ? null
          : () {
              final updatedAll = _projectCachedImdbIds(
                _movieCollectionMemo[collectionId] ?? projected,
              );
              _movieCollectionMemo[collectionId] = updatedAll;
              onWave1Complete(
                _visibleCollectionMovies(
                  updatedAll,
                  excludeTmdbId: excludeTmdbId,
                  now: refNow,
                ),
              );
            },
    );

    final finalAll = _projectCachedImdbIds(
      _movieCollectionMemo[collectionId] ?? projected,
    );
    _movieCollectionMemo[collectionId] = finalAll;
    return _visibleCollectionMovies(
      finalAll,
      excludeTmdbId: excludeTmdbId,
      now: refNow,
    );
  }

  Future<void> _resolveImdbWaves({
    required List<List<TmdbRecommendation>> groups,
    CancelToken? cancelToken,
    void Function()? onWave1Complete,
  }) async {
    final wave1Targets = <String, ({int id, String mediaType})>{};
    final wave2Targets = <String, ({int id, String mediaType})>{};

    void collectTarget(TmdbRecommendation item, {required bool isWave1}) {
      if (item.imdbId != null || _cachedImdbFor(item.id, item.mediaType) != null) {
        return;
      }
      final k = '${_normalizeType(item.mediaType)}:${item.id}';
      if (isWave1) {
        wave2Targets.remove(k);
        wave1Targets[k] = (id: item.id, mediaType: item.mediaType);
      } else if (!wave1Targets.containsKey(k)) {
        wave2Targets[k] = (id: item.id, mediaType: item.mediaType);
      }
    }

    for (final group in groups) {
      for (var i = 0; i < group.length; i++) {
        collectTarget(group[i], isWave1: i < kViewportPriorityCount);
      }
    }

    // Execute Wave 1 (mounted viewport items) concurrently.
    if (wave1Targets.isNotEmpty && !(cancelToken?.isCancelled ?? false)) {
      await Future.wait(
        wave1Targets.values.map(
          (t) => _resolveImdbId(t.id, mediaType: t.mediaType, cancelToken: cancelToken),
        ),
      ).catchError((_) => <String?>[]);

      if (cancelToken?.isCancelled ?? false) return;
      if (wave2Targets.isNotEmpty) {
        onWave1Complete?.call();
      }
    }

    // Execute Wave 2 (off-screen rail items) in bounded batches.
    final remaining = wave2Targets.values.toList();
    for (var i = 0; i < remaining.length; i += kMaxBackgroundConcurrency) {
      if (cancelToken?.isCancelled ?? false) break;
      final chunk = remaining.skip(i).take(kMaxBackgroundConcurrency);
      await Future.wait(
        chunk.map(
          (t) => _resolveImdbId(t.id, mediaType: t.mediaType, cancelToken: cancelToken),
        ),
      ).catchError((_) => <String?>[]);
    }
  }

  /// Phase 2: Resolves external IMDb IDs for `similar` and `recommendations`
  /// in two prioritized waves:
  /// - Wave 1: Visible viewport items (first [kViewportPriorityCount] of each row),
  ///   emitting immediately via [onWave1Complete].
  /// - Wave 2: Remaining off-screen items in bounded batches of [kMaxBackgroundConcurrency].
  Future<TmdbMovieDetails> enrichExternalIds(
    TmdbMovieDetails details, {
    CancelToken? cancelToken,
    void Function(TmdbMovieDetails)? onWave1Complete,
  }) async {
    if (details.isExternalIdsResolved ||
        (details.similar.isEmpty && details.recommendations.isEmpty)) {
      final marked = details.copyWith(isExternalIdsResolved: true);
      _storeFull(_cacheKey('${details.tmdbId}', details.mediaType), marked);
      return marked;
    }

    final simTop = details.similar.take(20).toList();
    final recTop = details.recommendations.take(20).toList();

    await _resolveImdbWaves(
      groups: [simTop, recTop],
      cancelToken: cancelToken,
      onWave1Complete: () {
        final afterWave1 = _applyCachedImdbIds(
          details,
          isFullyResolved: false,
        );
        _storeCore(_cacheKey('${details.tmdbId}', details.mediaType), afterWave1);
        onWave1Complete?.call(afterWave1);
      },
    );

    if (cancelToken?.isCancelled ?? false) {
      return _applyCachedImdbIds(details, isFullyResolved: false);
    }

    final finalDetails = _applyCachedImdbIds(details, isFullyResolved: true);
    _storeFull(_cacheKey('${details.tmdbId}', details.mediaType), finalDetails);
    return finalDetails;
  }

  TmdbMovieDetails _applyCachedImdbIds(
    TmdbMovieDetails source, {
    required bool isFullyResolved,
  }) =>
      source.copyWith(
        similar: _projectCachedImdbIds(source.similar),
        recommendations: _projectCachedImdbIds(source.recommendations),
        allSimilar: _projectCachedImdbIds(source.allSimilar),
        allRecommendations: _projectCachedImdbIds(source.allRecommendations),
        isExternalIdsResolved: isFullyResolved,
      );

  /// Public cached IMDb ID resolver for a TMDB movie/TV ID (used for Better Posters).
  Future<String?> resolveImdbId(
    int tmdbId, {
    String mediaType = 'movie',
    CancelToken? cancelToken,
  }) =>
      _resolveImdbId(
        tmdbId,
        mediaType: mediaType,
        cancelToken: cancelToken,
      );

  /// Deduplicated external ID lookup for a single movie or series.
  Future<String?> _resolveImdbId(
    int tmdbId, {
    String mediaType = 'movie',
    CancelToken? cancelToken,
  }) {
    final normType = _normalizeType(mediaType);
    final cacheKey = '$normType:$tmdbId';
    final cached = _tmdbToImdbCache[cacheKey];
    if (cached != null) return Future.value(cached);

    return _inflightExternalIds.putIfAbsent(cacheKey, () async {
      try {
        final resource = _resourceFor(normType);
        final res = await _dio.get<dynamic>(
          '${ApiConstants.tmdbBaseUrl}/$resource/$tmdbId/external_ids',
          queryParameters: {'api_key': ApiConstants.tmdbApiKey},
          cancelToken: cancelToken,
        );
        final data = res.data;
        if (data is Map<String, dynamic>) {
          final imdb = data['imdb_id'] as String?;
          if (imdb != null && imdb.isNotEmpty) {
            _registerIdPair(tmdbId, imdb, normType);
            return _tmdbToImdbCache[cacheKey];
          }
        }
      } catch (_) {
        // Resiliently swallow individual external_id failures so one missing ID
        // never breaks the rest of the rail.
      } finally {
        _inflightExternalIds.remove(cacheKey);
      }
      return null;
    });
  }

  /// Series Architectural Contract: Fetches and memoizes episode details for a
  /// specific season (`/tv/{id}/season/{season_number}`).
  ///
  /// Only already-released episodes (`isReleased == true`) are exposed in
  /// [TmdbSeasonDetails.episodes], while upcoming episodes are retained in
  /// [TmdbSeasonDetails.allEpisodes] so that as soon as an episode crosses its
  /// release date, it becomes visible immediately.
  Future<TmdbSeasonDetails> fetchSeasonDetails(
    int tvTmdbId,
    int seasonNumber, {
    CancelToken? cancelToken,
    bool forceRefresh = false,
  }) {
    final key = '$tvTmdbId:S$seasonNumber';
    if (!forceRefresh) {
      final cached = getCachedSeason(tvTmdbId, seasonNumber);
      if (cached != null) return Future.value(cached);
    } else {
      _seasonMemo.remove(key);
    }

    return _inflightSeasons.putIfAbsent(key, () {
      final future = _fetchSeasonInternal(
        tvTmdbId,
        seasonNumber,
        cancelToken: cancelToken,
      );
      future
          .then((season) => _seasonMemo[key] = season, onError: (_) {})
          .whenComplete(() => _inflightSeasons.remove(key));
      return future;
    });
  }

  Future<TmdbSeasonDetails> _fetchSeasonInternal(
    int tvTmdbId,
    int seasonNumber, {
    CancelToken? cancelToken,
  }) async {
    final json = await _getJson(
      '/tv/$tvTmdbId/season/$seasonNumber',
      const {},
      cancelToken: cancelToken,
    );
    return _parseSeasonJson(json, seasonNumber);
  }

  static TmdbSeasonDetails _parseSeasonJson(
    Map<String, dynamic> json,
    int fallbackSeasonNumber, {
    DateTime? now,
  }) {
    final seasonNumber = (json['season_number'] as num?)?.toInt() ?? fallbackSeasonNumber;
    final allEpisodes = <TmdbEpisode>[
      for (final ep in _maps(json['episodes']))
        if (ep['episode_number'] is num)
          TmdbEpisode(
            id: (ep['id'] as num?)?.toInt() ?? 0,
            episodeNumber: (ep['episode_number'] as num).toInt(),
            seasonNumber: (ep['season_number'] as num?)?.toInt() ?? seasonNumber,
            name: _str(ep['name']),
            overview: _str(ep['overview']),
            stillUrl: _img(ep['still_path'], 'w500'),
            airDate: _str(ep['air_date']).isNotEmpty ? _str(ep['air_date']) : null,
            runtimeMinutes: (ep['runtime'] as num?)?.toInt(),
            voteAverage: (ep['vote_average'] as num?)?.toDouble(),
          ),
    ];

    final releasedEpisodes = <TmdbEpisode>[
      for (final ep in allEpisodes)
        if (ep.isReleased(now: now)) ep,
    ];

    return TmdbSeasonDetails(
      id: (json['id'] as num?)?.toInt() ?? 0,
      seasonNumber: seasonNumber,
      name: _str(json['name']).isNotEmpty ? _str(json['name']) : 'Season $seasonNumber',
      overview: _str(json['overview']),
      posterUrl: _img(json['poster_path'], 'w342'),
      airDate: _str(json['air_date']).isNotEmpty ? _str(json['air_date']) : null,
      episodes: releasedEpisodes,
      allEpisodes: allEpisodes,
    );
  }

  Future<Map<String, dynamic>> _getJson(
    String path,
    Map<String, dynamic> query, {
    CancelToken? cancelToken,
    Options? options,
  }) async {
    final append = query['append_to_response']?.toString() ?? '';
    final needsSession = path.startsWith('/account') ||
        append.contains('account_states') ||
        path.endsWith('/account_states');
    try {
      final res = await _dio.get<dynamic>(
        '${ApiConstants.tmdbBaseUrl}$path',
        queryParameters: {
          ...query,
          'api_key': ApiConstants.tmdbApiKey,
          if (needsSession &&
              _userSessionId != null &&
              _userSessionId!.isNotEmpty)
            'session_id': _userSessionId,
        },
        options: options,
        cancelToken: cancelToken,
      );
      final data = res.data;
      if (data is Map<String, dynamic>) return data;
      throw const TmdbException('Unexpected TMDB response');
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      final status = e.response?.statusCode;
      if (status == 401) {
        throw TmdbException(
          needsSession
              ? 'TMDB session expired. Tap Reconnect below to back up your My List & Likes.'
              : 'TMDB API authentication failed.',
          statusCode: 401,
          dioType: e.type,
          cause: e,
        );
      }
      if (status == 429) {
        throw TmdbException(
          'TMDB rate limit hit. Retrying automatically.',
          statusCode: 429,
          dioType: e.type,
          cause: e,
        );
      }
      throw TmdbException(
        e.message ?? 'TMDB request failed',
        statusCode: status,
        dioType: e.type,
        cause: e,
      );
    }
  }

  static int? _extractRuntimeMinutes(Map<String, dynamic> json) {
    final direct = json['runtime'];
    if (direct is num && direct > 0) return direct.toInt();
    final epRuntimes = json['episode_run_time'];
    if (epRuntimes is List && epRuntimes.isNotEmpty && epRuntimes.first is num) {
      final first = (epRuntimes.first as num).toInt();
      if (first > 0) return first;
    }
    final lastEp = _map(json['last_episode_to_air']);
    final lastEpRuntime = lastEp['runtime'];
    if (lastEpRuntime is num && lastEpRuntime > 0) return lastEpRuntime.toInt();
    return null;
  }

  static List<TmdbSeasonSummary> _parseSeasons(
    dynamic rawList, {
    Map<String, dynamic> lastEpisodeToAir = const {},
    Map<String, dynamic> nextEpisodeToAir = const {},
    TmdbSeasonDetails? bundledSeason1,
    DateTime? now,
  }) {
    final lastEpSeason = (lastEpisodeToAir['season_number'] as num?)?.toInt();
    final lastEpNumber = (lastEpisodeToAir['episode_number'] as num?)?.toInt();
    final nextEpSeason = (nextEpisodeToAir['season_number'] as num?)?.toInt();
    final nextEpNumber = (nextEpisodeToAir['episode_number'] as num?)?.toInt();

    final out = <TmdbSeasonSummary>[];
    for (final s in _maps(rawList)) {
      if (s['season_number'] is! num) continue;
      final seasonNum = (s['season_number'] as num).toInt();
      final totalEpCount = (s['episode_count'] as num?)?.toInt() ?? 0;
      if (seasonNum < 0 || totalEpCount <= 0) continue;

      final rawAirDate = _str(s['air_date']).isNotEmpty ? _str(s['air_date']) : null;

      // Skip future seasons whose premiere air_date has not arrived yet.
      if (rawAirDate != null && !isAirDateReleased(rawAirDate, now: now)) {
        continue;
      }
      // Skip unscheduled future seasons beyond the last season that has aired.
      if (rawAirDate == null && lastEpSeason != null && seasonNum > lastEpSeason) {
        continue;
      }
      // If the next episode to air is Episode 1 of this season in the future,
      // this season has 0 released episodes so far.
      if (nextEpSeason == seasonNum &&
          nextEpNumber == 1 &&
          !isAirDateReleased(_str(nextEpisodeToAir['air_date']), now: now)) {
        continue;
      }

      var releasedCount = totalEpCount;
      if (seasonNum == 1 && bundledSeason1 != null && bundledSeason1.allEpisodes.isNotEmpty) {
        releasedCount = bundledSeason1.episodes.length;
      } else if (lastEpSeason == seasonNum &&
          lastEpNumber != null &&
          lastEpNumber > 0 &&
          lastEpNumber < totalEpCount) {
        if ((nextEpSeason == seasonNum && nextEpNumber != null && nextEpNumber > lastEpNumber) ||
            nextEpisodeToAir.isNotEmpty) {
          releasedCount = lastEpNumber;
        }
      }

      if (releasedCount <= 0) continue;

      out.add(TmdbSeasonSummary(
        id: (s['id'] as num?)?.toInt() ?? seasonNum,
        seasonNumber: seasonNum,
        name: _str(s['name']).isNotEmpty ? _str(s['name']) : 'Season $seasonNum',
        overview: _str(s['overview']),
        posterUrl: _img(s['poster_path'], 'w342'),
        airDate: rawAirDate,
        episodeCount: releasedCount,
        voteAverage: (s['vote_average'] as num?)?.toDouble(),
      ));
    }
    // Filter out Season 0 ("Specials") whenever regular numbered seasons (1..N) exist.
    final regularSeasons = out.where((s) => s.seasonNumber > 0).toList();
    final result = regularSeasons.isNotEmpty ? regularSeasons : out;
    result.sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));
    return result;
  }

  static Map<String, dynamic> _map(dynamic v) =>
      v is Map<String, dynamic> ? v : const <String, dynamic>{};

  static List<Map<String, dynamic>> _maps(dynamic v) => v is List
      ? [for (final e in v) if (e is Map<String, dynamic>) e]
      : const <Map<String, dynamic>>[];

  static String _str(dynamic v) => v is String ? v : '';

  static String? _img(dynamic path, String size) =>
      path is String && path.isNotEmpty ? '${ApiConstants.tmdbImageUrl}/$size$path' : null;

  /// TMDB Genre ID map verbatim from PostersPlus clean_notch (config.py:740-758).
  static const Map<int, String> _tmdbGenreIdNames = {
    28: 'Action',
    12: 'Adventure',
    16: 'Animation',
    35: 'Comedy',
    80: 'Crime',
    99: 'Documentary',
    18: 'Drama',
    10751: 'Family',
    14: 'Fantasy',
    36: 'History',
    27: 'Horror',
    10402: 'Music',
    9648: 'Mystery',
    10749: 'Romance',
    878: 'Sci-Fi',
    10770: 'TV Movie',
    53: 'Thriller',
    10752: 'War',
    37: 'Western',
    10759: 'Action',
    10762: 'Kids',
    10763: 'News',
    10764: 'Reality',
    10765: 'Sci-Fi',
    10766: 'Soap',
    10767: 'Talk',
    10768: 'War',
  };

  /// Western Genre Priority Ordering verbatim from PostersPlus clean_notch (config.py:754-758).
  static const List<int> _westernGenrePriorityOrder = [
    27, 53, 9648, 878, 10765, 80, 35, 10749, 14, 16, 10751, 28, 10759, 36,
    10402, 10752, 10768, 37, 99, 18, 12, 10764, 10762, 10763, 10766, 10767,
  ];

  static List<String> _resolveGenresFromIds(dynamic rawGenreIds) {
    if (rawGenreIds is! List) return const [];
    final ids = rawGenreIds
        .whereType<num>()
        .map((n) => n.toInt())
        .toSet();
    if (ids.isEmpty) return const [];
    final out = <String>[];
    for (final priorityId in _westernGenrePriorityOrder) {
      if (ids.contains(priorityId)) {
        final name = _tmdbGenreIdNames[priorityId];
        if (name != null && !out.contains(name)) {
          out.add(name);
        }
      }
    }
    for (final id in ids) {
      final name = _tmdbGenreIdNames[id];
      if (name != null && !out.contains(name)) {
        out.add(name);
      }
    }
    return out;
  }

  /// Competitive textless poster selection verbatim from PostersPlus clean_notch (tmdb.py:323-346).
  /// Strictly filters to `iso_639_1 == null` or `""`.
  static Map<String, dynamic>? _selectTextlessPoster(
    List<Map<String, dynamic>> posters,
  ) {
    final textless = posters.where((p) {
      final lang = p['iso_639_1'];
      return lang == null || (lang is String && lang.trim().isEmpty);
    }).toList();
    if (textless.isEmpty) return null;

    var bestRating = 0.0;
    for (final p in textless) {
      final r = (p['vote_average'] as num?)?.toDouble() ?? 0.0;
      if (r > bestRating) bestRating = r;
    }
    final competitive = textless.where((p) {
      final r = (p['vote_average'] as num?)?.toDouble() ?? 0.0;
      return r >= bestRating - 1.0; // TMDB_POSTER_MAX_SCORE_DROP = 1.0
    }).toList();
    final voted = competitive.where((p) {
      final v = (p['vote_count'] as num?)?.toInt() ?? 0;
      return v >= 3; // TMDB_POSTER_MIN_VOTES = 3
    }).toList();
    final pool = voted.isNotEmpty ? voted : competitive;
    pool.sort((a, b) {
      final aRating = (a['vote_average'] as num?)?.toDouble() ?? 0.0;
      final bRating = (b['vote_average'] as num?)?.toDouble() ?? 0.0;
      final cmp = bRating.compareTo(aRating);
      if (cmp != 0) return cmp;
      final aVotes = (a['vote_count'] as num?)?.toInt() ?? 0;
      final bVotes = (b['vote_count'] as num?)?.toInt() ?? 0;
      return bVotes.compareTo(aVotes);
    });
    return pool.first;
  }

  static String _rawReleaseDate(Map<String, dynamic> r, {bool? isSeries}) {
    if (isSeries == true) {
      final firstAir = _str(r['first_air_date']);
      return firstAir.isNotEmpty ? firstAir : _str(r['release_date']);
    }
    final rel = _str(r['release_date']);
    return rel.isNotEmpty ? rel : _str(r['first_air_date']);
  }

  static bool _isTmdbItemReleased(
    Map<String, dynamic> r, {
    bool? isSeries,
    DateTime? now,
  }) =>
      isAirDateReleased(_rawReleaseDate(r, isSeries: isSeries), now: now);

  static List<TmdbRecommendation> _parseRecommendations(
    dynamic rawList, {
    String defaultMediaType = 'movie',
    bool sortByQualityTier = true,
    bool onlyReleased = true,
    DateTime? now,
    int? collectionId,
  }) {
    final items = <TmdbRecommendation>[];
    final seenIds = <int>{};
    final indexById = <int, int>{};
    for (final r in _maps(rawList)) {
      if (r['id'] is num) {
        final id = (r['id'] as num).toInt();
        if (!seenIds.add(id)) continue;
        final posterPath = _str(r['poster_path']);
        if (posterPath.isEmpty) continue;
        final title = _str(r['title']).isNotEmpty
            ? _str(r['title'])
            : (_str(r['name']).isNotEmpty
                ? _str(r['name'])
                : _str(r['original_title']));
        if (title.isEmpty) continue;
        final itemMediaType = _str(r['media_type']).isNotEmpty
            ? _normalizeType(_str(r['media_type']))
            : defaultMediaType;
        final rawDate = _rawReleaseDate(r, isSeries: itemMediaType == 'series');
        if (onlyReleased && !isAirDateReleased(rawDate, now: now)) continue;
        final releaseYear =
            rawDate.length >= 4 ? int.tryParse(rawDate.substring(0, 4)) : null;
        final rawLang = _str(r['original_language']).trim().toLowerCase();
        final genreIdsRaw = r['genre_ids'];
        final genreIds = genreIdsRaw is List
            ? genreIdsRaw.whereType<num>().map((n) => n.toInt()).toList(growable: false)
            : const <int>[];
        indexById[id] = items.length;
        items.add(TmdbRecommendation(
          id: id,
          title: title,
          posterUrl: _img(posterPath, 'w342'),
          backdropUrl: _img(_str(r['backdrop_path']), 'w780'),
          popularity: (r['popularity'] as num?)?.toDouble() ?? 0.0,
          voteAverage: (r['vote_average'] as num?)?.toDouble(),
          voteCount: (r['vote_count'] as num?)?.toInt() ?? 0,
          mediaType: itemMediaType,
          genres: _resolveGenresFromIds(genreIdsRaw),
          releaseYear: releaseYear,
          releaseDate: rawDate.isNotEmpty ? rawDate : null,
          originalLanguage: rawLang.isNotEmpty ? rawLang : null,
          genreIds: genreIds,
          collectionId: collectionId,
        ));
      }
    }
    if (!sortByQualityTier) {
      items.sort((a, b) {
        final popCmp = b.popularity.compareTo(a.popularity);
        if (popCmp != 0) return popCmp;
        return (indexById[a.id] ?? 0).compareTo(indexById[b.id] ?? 0);
      });
      return items;
    }

    // Lightweight quality-and-recency-aware ordering for Detail Screen rails:
    // prioritize modern quality hits and iconic classics over pre-2012 low-vote slop,
    // while breaking ties (and handling un-dated test fixtures) by popularity descending.
    int qualityTier(TmdbRecommendation item) {
      final year = item.releaseYear;
      final votes = item.voteCount;
      final rating = item.voteAverage ?? 0.0;
      if (year == null && votes == 0 && rating == 0.0) return 1;
      final isClassic = year != null && year < 2012 && rating >= 7.8 && votes >= 1500;
      final isModernQuality = year != null && year >= 2012 && rating >= 6.2 && votes >= 100;
      if (isModernQuality || isClassic) return 2;
      if (year == null || year >= 2012 || (rating >= 7.0 && votes >= 300)) return 1;
      return 0;
    }

    items.sort((a, b) {
      final tierCmp = qualityTier(b).compareTo(qualityTier(a));
      if (tierCmp != 0) return tierCmp;
      return b.popularity.compareTo(a.popularity);
    });
    return items;
  }

  static Map<String, dynamic>? _bestImage(
    List<Map<String, dynamic>> images, {
    bool textless = false,
    bool preferEnglish = false,
  }) {
    if (images.isEmpty) return null;
    final filtered = textless
        ? images.where((i) => i['iso_639_1'] == null).toList()
        : images.where((i) => !preferEnglish || i['iso_639_1'] == 'en').toList();
    final pool = filtered.isEmpty ? images : filtered;
    pool.sort((a, b) {
      final aScore = ((a['vote_average'] as num?)?.toDouble() ?? 0) * 10 +
          ((a['vote_count'] as num?)?.toDouble() ?? 0);
      final bScore = ((b['vote_average'] as num?)?.toDouble() ?? 0) * 10 +
          ((b['vote_count'] as num?)?.toDouble() ?? 0);
      return bScore.compareTo(aScore);
    });
    return pool.first;
  }
}

final tmdbDioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    connectTimeout: ApiConstants.connectTimeout,
    receiveTimeout: ApiConstants.receiveTimeout,
    responseType: ResponseType.json,
    headers: const {'Accept': 'application/json'},
  ));
  // Credits + recommendations can run to ~100 KB; decode off the UI isolate.
  dio.transformer = BackgroundTransformer();
  dio.interceptors.add(RetryInterceptor(dio));
  ref.onDispose(() => dio.close(force: true));
  return dio;
});

final tmdbRepositoryProvider = Provider<TmdbRepository>((ref) {
  final repo = TmdbRepository(
    ref.watch(tmdbDioProvider),
    animeIdMap: ref.watch(animeIdMapProvider),
    enableRetryTimer: true,
  );
  ref.onDispose(repo.dispose);
  return repo;
});

/// Movie metadata for one Stremio `tt…` id (preserved for compatibility).
final movieDetailsProvider = FutureProvider.family<TmdbMovieDetails, String>(
  (ref, imdbId) => ref.watch(tmdbRepositoryProvider).fetchMovie(imdbId),
);

/// Raw TMDB account lists (Watchlist + Ratings) fetched across all pages.
class _AccountSnapshot {
  const _AccountSnapshot({
    required this.watchMovies,
    required this.watchTv,
    required this.ratedMovies,
    required this.ratedTv,
    this.watchMoviesComplete = true,
    this.watchTvComplete = true,
    this.ratedMoviesComplete = true,
    this.ratedTvComplete = true,
  });

  final List<Map<String, dynamic>> watchMovies;
  final List<Map<String, dynamic>> watchTv;
  final List<Map<String, dynamic>> ratedMovies;
  final List<Map<String, dynamic>> ratedTv;
  final bool watchMoviesComplete;
  final bool watchTvComplete;
  final bool ratedMoviesComplete;
  final bool ratedTvComplete;
}
