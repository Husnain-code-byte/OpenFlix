import 'dart:async';

import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/perf/image_perf.dart';
import '../../../addons/data/stremio_addon_service.dart';
import '../../../addons/domain/models/addon_models.dart';
import '../../../addons/presentation/controllers/addons_controller.dart';
import '../../../anime/data/anilist_addon_repository.dart';
import '../../../anime/data/anime_id_map.dart';
import '../../../home/data/models/meta_model.dart';
import '../../../player/domain/models/watch_progress_models.dart';
import '../../../player/presentation/controllers/watch_progress_controller.dart';
import '../../data/tmdb_models.dart';
import '../../data/tmdb_repository.dart';

/// Unique key identifying a Details route target (`id` can be an IMDb `tt…` ID
/// or a numeric TMDB ID; `type` is `'movie'` or `'series'`).
typedef DetailsQueryKey = ({String id, String type});

/// Phased loading lifecycle for the Details screen:
/// - [loadingCore]: Initial primary metadata fetch in progress.
/// - [enrichingRelated]: Core metadata (Hero, Logo, Synopsis, Telemetry, Cast,
///   Genres, Seasons, and initial Related lists) is rendered; background
///   `btttr.cc` external ID enrichment is running non-blockingly.
/// - [ready]: All primary and secondary metadata resolved.
/// - [error]: Core metadata request failed.
enum DetailsLoadPhase { loadingCore, enrichingRelated, ready, error }

class DetailsViewState extends Equatable {
  const DetailsViewState({
    this.phase = DetailsLoadPhase.loadingCore,
    this.details,
    this.similarMetas = const [],
    this.recommendedMetas = const [],
    this.collectionMetas = const [],
    this.animePicks = const [],
    this.isAnime = false,
    this.selectedSeasonNumber,
    this.seasonsCache = const {},
    this.isLoadingSeason = false,
    this.seasonError,
    this.errorMessage,
    this.userRating,
    this.isInMyList = false,
  });

  final DetailsLoadPhase phase;
  final TmdbMovieDetails? details;

  /// Pre-mapped and memoized [MetaModel] lists for "More Like This",
  /// "Viewers Also Watched", and "Collection" so `DetailScreen.build()` never
  /// re-allocates lists or re-formats URLs across UI rebuilds or tab switches.
  final List<MetaModel> similarMetas;
  final List<MetaModel> recommendedMetas;
  final List<MetaModel> collectionMetas;

  /// Third related row powered by AniList recommendations for anime titles.
  final List<MetaModel> animePicks;
  final bool isAnime;

  /// Series-specific state slice: active season selection and memoized episode lists.
  final int? selectedSeasonNumber;
  final Map<int, TmdbSeasonDetails> seasonsCache;
  final bool isLoadingSeason;
  final String? seasonError;

  final String? errorMessage;

  /// The user's personal TMDB rating (`0.5 .. 10.0`), or `null` if unrated.
  final double? userRating;

  /// Whether this title is saved in the user's "My List".
  final bool isInMyList;

  /// Classifies [userRating] into [TmdbUserReaction]:
  /// - `< 5.0` (less than half of 10.0, e.g. `4.5` or `< 2.0`) -> [TmdbUserReaction.disliked]
  /// - `>= 5.0` (half or above, including `> 8.0`) -> [TmdbUserReaction.liked]
  /// - `null` -> [TmdbUserReaction.none]
  TmdbUserReaction get userReaction => reactionFromRating(userRating ?? details?.userRating);

  bool get isInitialLoading => phase == DetailsLoadPhase.loadingCore && details == null;
  bool get hasFailed => phase == DetailsLoadPhase.error && details == null;
  bool get isSeries => details?.mediaType == 'series';

  TmdbSeasonDetails? get activeSeasonDetails =>
      selectedSeasonNumber != null ? seasonsCache[selectedSeasonNumber!] : null;

  /// Episode count for the currently selected season (from loaded season details
  /// or the season summary list), counting only released episodes.
  int? get activeSeasonEpisodeCount {
    final activeSeason = activeSeasonDetails;
    if (activeSeason != null && activeSeason.episodes.isNotEmpty) {
      return activeSeason.episodes.length;
    }
    final d = details;
    final sel = selectedSeasonNumber ?? 1;
    if (d != null && d.seasons.isNotEmpty) {
      for (final s in d.seasons) {
        if (s.seasonNumber == sel && s.episodeCount > 0) return s.episodeCount;
      }
      if (d.seasons.first.episodeCount > 0) return d.seasons.first.episodeCount;
    }
    return null;
  }

  /// Season summaries with episode counts synchronized to the exact count of
  /// released episodes for any season loaded in [seasonsCache].
  List<TmdbSeasonSummary> get resolvedSeasons {
    final d = details;
    if (d == null || d.seasons.isEmpty) return const [];
    return [
      for (final s in d.seasons)
        if (seasonsCache[s.seasonNumber] != null &&
            seasonsCache[s.seasonNumber]!.episodes.isNotEmpty)
          s.copyWith(episodeCount: seasonsCache[s.seasonNumber]!.episodes.length)
        else
          s,
    ];
  }

  DetailsViewState copyWith({
    DetailsLoadPhase? phase,
    TmdbMovieDetails? details,
    List<MetaModel>? similarMetas,
    List<MetaModel>? recommendedMetas,
    List<MetaModel>? collectionMetas,
    List<MetaModel>? animePicks,
    bool? isAnime,
    int? selectedSeasonNumber,
    Map<int, TmdbSeasonDetails>? seasonsCache,
    bool? isLoadingSeason,
    String? seasonError,
    String? errorMessage,
    double? userRating,
    bool clearUserRating = false,
    bool? isInMyList,
  }) =>
      DetailsViewState(
        phase: phase ?? this.phase,
        details: details ?? this.details,
        similarMetas: similarMetas ?? this.similarMetas,
        recommendedMetas: recommendedMetas ?? this.recommendedMetas,
        collectionMetas: collectionMetas ?? this.collectionMetas,
        animePicks: animePicks ?? this.animePicks,
        isAnime: isAnime ?? this.isAnime,
        selectedSeasonNumber: selectedSeasonNumber ?? this.selectedSeasonNumber,
        seasonsCache: seasonsCache ?? this.seasonsCache,
        isLoadingSeason: isLoadingSeason ?? this.isLoadingSeason,
        seasonError: seasonError,
        errorMessage: errorMessage,
        userRating: clearUserRating ? null : (userRating ?? this.userRating),
        isInMyList: isInMyList ?? this.isInMyList,
      );

  @override
  List<Object?> get props => [
        phase,
        details,
        similarMetas,
        recommendedMetas,
        collectionMetas,
        animePicks,
        isAnime,
        selectedSeasonNumber,
        seasonsCache,
        isLoadingSeason,
        seasonError,
        errorMessage,
        userRating,
        isInMyList,
      ];
}

/// Isolated controller for the Movie & Series Details screen.
///
/// Decouples primary metadata rendering from secondary enrichment and provides
/// a built-in hook for Series season/episode loading.
class DetailsController extends AutoDisposeFamilyNotifier<DetailsViewState, DetailsQueryKey> {
  late TmdbRepository _repo;
  late AnimeIdMap _animeIdMap;
  late AniListAddonRepository _aniListRepo;
  CancelToken? _cancelToken;
  Timer? _releaseTimer;
  int _generation = 0;
  bool _userEditedReaction = false;
  bool _userEditedMyList = false;

  @override
  DetailsViewState build(DetailsQueryKey arg) {
    _repo = ref.watch(tmdbRepositoryProvider);
    _animeIdMap = ref.watch(animeIdMapProvider);
    _aniListRepo = ref.watch(aniListAddonRepositoryProvider);
    _userEditedReaction = false;
    _userEditedMyList = false;
    void onMyListChanged() {
      final parsedTmdb = state.details?.tmdbId ?? int.tryParse(arg.id.trim());
      final effectiveImdb = state.details?.imdbId ?? (parsedTmdb == null ? arg.id : null);
      final effectiveType = state.details?.mediaType ?? arg.type;
      final latestInList = _repo.getCachedIsInMyList(
        tmdbId: parsedTmdb,
        imdbId: effectiveImdb,
        mediaType: effectiveType,
      );
      final latestRating = _repo.getCachedUserRating(
        tmdbId: parsedTmdb,
        imdbId: effectiveImdb,
        mediaType: effectiveType,
      );
      final latestIsAnime = state.isAnime ||
          _repo.isKeyOrAnime(
            tmdbId: parsedTmdb,
            imdbId: effectiveImdb,
            mediaType: effectiveType,
            animeIdMap: _animeIdMap,
          );
      if (latestInList != state.isInMyList ||
          latestRating != state.userRating ||
          latestIsAnime != state.isAnime) {
        state = state.copyWith(
          isInMyList: latestInList,
          userRating: latestRating,
          clearUserRating: latestRating == null,
          isAnime: latestIsAnime,
          details: state.details?.copyWith(
            isInMyList: latestInList,
            userRating: latestRating,
            clearUserRating: latestRating == null,
          ),
        );
      }
    }

    _repo.addMyListListener(onMyListChanged);
    ref.onDispose(() {
      _repo.removeMyListListener(onMyListChanged);
      _generation++;
      _releaseTimer?.cancel();
      _cancelToken?.cancel('DetailsScreen disposed');
    });
    final parsedTmdbId = int.tryParse(arg.id.trim());
    final initialImdb = parsedTmdbId == null ? arg.id : null;
    final initialRating = _repo.getCachedUserRating(
      tmdbId: parsedTmdbId,
      imdbId: initialImdb,
      mediaType: arg.type,
    );
    final initialMyList = _repo.getCachedIsInMyList(
      tmdbId: parsedTmdbId,
      imdbId: initialImdb,
      mediaType: arg.type,
    );
    final initialIsAnime = _repo.isKeyOrAnime(
      tmdbId: parsedTmdbId,
      imdbId: initialImdb,
      mediaType: arg.type,
      animeIdMap: _animeIdMap,
    );
    Future.microtask(_load);
    return DetailsViewState(
      userRating: initialRating,
      isInMyList: initialMyList,
      isAnime: initialIsAnime,
    );
  }

  static bool _isStandardBuiltInId(String rawId) {
    final trimmed = rawId.trim();
    return trimmed.startsWith('tt') ||
        int.tryParse(trimmed) != null ||
        trimmed.startsWith('anilist:');
  }

  Future<bool> _tryLoadFromStremioMeta(CancelToken token, int gen) async {
    AddonsStoreState? store;
    try {
      store = ref.read(addonsControllerProvider).valueOrNull ??
          await ref.read(addonsControllerProvider.future);
    } catch (_) {
      store = ref.read(addonsControllerProvider).valueOrNull;
    }
    if (store == null || store.stremioAddons.isEmpty) return false;

    final candidates = store.stremioAddons
        .where((a) =>
            a.enabled &&
            a.manifest.supportsResource('meta', type: arg.type, id: arg.id))
        .toList()
      ..sort((a, b) {
        final aMatch = a.manifest.idPrefixes.any(arg.id.startsWith) ? 0 : 1;
        final bMatch = b.manifest.idPrefixes.any(arg.id.startsWith) ? 0 : 1;
        if (aMatch != bMatch) return aMatch.compareTo(bMatch);
        return a.orderIndex.compareTo(b.orderIndex);
      });

    final stremioService = ref.read(stremioAddonServiceProvider);
    for (final addon in candidates) {
      if (gen != _generation || token.isCancelled) return false;
      try {
        final payload = await stremioService.fetchMeta(
          addon.baseUrl,
          arg.type,
          arg.id,
          sourceAddonId: addon.id,
          cancelToken: token,
        );
        if (payload == null) continue;
        if (gen != _generation || token.isCancelled) return true;

        final grouped = <int, List<TmdbEpisode>>{};
        for (var i = 0; i < payload.videos.length; i++) {
          final v = payload.videos[i];
          final sNum = v.season;
          final rawAir = v.released?.trim();
          final airDate = rawAir != null && rawAir.length >= 10
              ? rawAir.substring(0, 10)
              : rawAir;
          final ep = TmdbEpisode(
            id: (sNum * 10000) + v.episode + i,
            episodeNumber: v.episode,
            seasonNumber: sNum,
            name: v.title,
            overview: v.overview ?? '',
            stillUrl: v.thumbnail,
            airDate: airDate,
          );
          grouped.putIfAbsent(sNum, () => []).add(ep);
        }

        final seasonNums = grouped.keys.toList()..sort();
        final seasons = <TmdbSeasonSummary>[];
        final seasonMap = <int, TmdbSeasonDetails>{};
        for (final sNum in seasonNums) {
          final eps = grouped[sNum]!
            ..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
          seasons.add(
            TmdbSeasonSummary(
              id: sNum,
              seasonNumber: sNum,
              name: sNum == 0 ? 'Specials' : 'Season $sNum',
              episodeCount: eps.length,
            ),
          );
          seasonMap[sNum] = TmdbSeasonDetails(
            id: sNum,
            seasonNumber: sNum,
            name: sNum == 0 ? 'Specials' : 'Season $sNum',
            episodes: eps,
          );
        }

        final yearMatch =
            RegExp(r'(19|20)\d{2}').firstMatch(payload.meta.releaseInfo ?? '');
        final mapped = TmdbMovieDetails(
          tmdbId: int.tryParse(arg.id.trim()) ?? 0,
          title: payload.meta.name,
          overview: payload.meta.description ?? '',
          backdropUrl: payload.meta.background ?? payload.meta.poster,
          posterUrl: payload.meta.poster ?? payload.meta.posterFallback,
          logoUrl: payload.meta.logo,
          genres: payload.meta.genres,
          releaseYear: yearMatch?.group(0),
          voteAverage: double.tryParse(payload.meta.imdbRating ?? ''),
          cast: [
            for (final name in payload.cast) TmdbCast(name: name, character: ''),
          ],
          mediaType: arg.type == 'series' ? 'series' : 'movie',
          imdbId: payload.imdbId,
          numberOfSeasons: seasons.isNotEmpty ? seasons.length : null,
          numberOfEpisodes:
              payload.videos.isNotEmpty ? payload.videos.length : null,
          seasons: seasons,
          isExternalIdsResolved: true,
        );

        final progressStore =
            ref.read(watchProgressControllerProvider).valueOrNull;
        final savedProgress = progressStore?.lookup(
          imdbId: mapped.imdbId,
          tmdbId: mapped.tmdbId > 0 ? mapped.tmdbId : null,
          rawId: arg.id,
          mediaType: mapped.mediaType,
        );
        final pickedSeason = mapped.mediaType == 'series'
            ? resolveSeriesPlaybackTarget(
                entry: savedProgress,
                seasons: seasons,
                seasonsCache: seasonMap,
              ).season
            : null;
        final validPickedSeason = (pickedSeason != null &&
                seasons.any((s) => s.seasonNumber == pickedSeason))
            ? pickedSeason
            : (seasons.isNotEmpty ? seasons.first.seasonNumber : null);

        state = state.copyWith(
          phase: DetailsLoadPhase.ready,
          details: mapped,
          seasonsCache: seasonMap,
          selectedSeasonNumber: validPickedSeason,
          isLoadingSeason: false,
        );
        return true;
      } catch (_) {}
    }
    return false;
  }

  Future<void> _load() async {
    _releaseTimer?.cancel();
    _cancelToken?.cancel('Superseded by new details load');
    final token = CancelToken();
    _cancelToken = token;
    final gen = ++_generation;

    if (state.details == null) {
      state = state.copyWith(phase: DetailsLoadPhase.loadingCore);
    }

    final isStandardId = _isStandardBuiltInId(arg.id);
    if (!isStandardId) {
      final loadedFromMeta = await _tryLoadFromStremioMeta(token, gen);
      if (loadedFromMeta) return;
      if (gen != _generation || token.isCancelled) return;
    }

    try {
      // Phase 1: Fetch core metadata (1–2 RTTs) and emit immediately.
      final core = await _repo.fetchCoreDetails(
        arg.id,
        type: arg.type,
        cancelToken: token,
      );
      if (gen != _generation || token.isCancelled) return;

      try {
        await ref.read(watchProgressControllerProvider.future);
      } catch (_) {}
      if (gen != _generation || token.isCancelled) return;
      final defaultSeason =
          state.selectedSeasonNumber ?? _pickActiveOrDefaultSeason(core);
      final initialPhase = core.isExternalIdsResolved
          ? DetailsLoadPhase.ready
          : DetailsLoadPhase.enrichingRelated;

      // Check if the active season was already bundled inline via `append_to_response=season/1`.
      final bundledSeason = (core.mediaType == 'series' && defaultSeason != null)
          ? _repo.getCachedSeason(core.tmdbId, defaultSeason)
          : null;
      final updatedSeasonsCache = bundledSeason != null
          ? {...state.seasonsCache, defaultSeason!: bundledSeason}
          : state.seasonsCache;

      final effectiveImdb = core.imdbId ?? (arg.id.startsWith('tt') ? arg.id : null);
      final eagerIsAnime = state.isAnime ||
          core.isJapaneseAnimation ||
          _repo.isKeyOrAnime(
            tmdbId: core.tmdbId,
            imdbId: effectiveImdb,
            mediaType: core.mediaType,
            animeIdMap: _animeIdMap,
          );
      if (eagerIsAnime) {
        _repo.markAsAnime(
          tmdbId: core.tmdbId,
          imdbId: effectiveImdb,
          mediaType: core.mediaType,
          notify: false,
        );
      }

      final cachedCollection =
          (core.mediaType == 'movie' && core.collectionId != null)
              ? _repo.getCachedCollectionMovies(
                  core.collectionId!,
                  excludeTmdbId: core.tmdbId,
                )
              : null;

      final liveCore = _resolveLiveInteraction(core);
      state = state.copyWith(
        phase: initialPhase,
        details: liveCore.details,
        similarMetas: _buildRelatedMetas(core.similar, fallbackType: core.mediaType),
        recommendedMetas: _buildRelatedMetas(core.recommendations, fallbackType: core.mediaType),
        collectionMetas: cachedCollection != null
            ? _buildRelatedMetas(cachedCollection, fallbackType: 'movie')
            : const [],
        isAnime: eagerIsAnime,
        selectedSeasonNumber: defaultSeason,
        seasonsCache: updatedSeasonsCache,
        isLoadingSeason: core.mediaType == 'series' &&
            defaultSeason != null &&
            !updatedSeasonsCache.containsKey(defaultSeason),
        userRating: liveCore.userRating,
        clearUserRating: liveCore.userRating == null,
        isInMyList: liveCore.isInMyList,
      );
      _scheduleNextReleaseWatch();

      // Sync any rating from TMDB account_states in the background.
      unawaited(_syncAccountRating(core, token, gen));

      // Resolve franchise collection movies if this movie belongs to a TMDB collection.
      if (core.mediaType == 'movie' && core.collectionId != null) {
        unawaited(_resolveCollectionMovies(core, token, gen));
      }

      // Resolve AniList anime picks if this title is an anime.
      unawaited(_resolveAnimePicks(core, token, gen));

      // For Series: if the active season wasn't bundled inline, fetch it in parallel.
      if (core.mediaType == 'series' &&
          defaultSeason != null &&
          !updatedSeasonsCache.containsKey(defaultSeason)) {
        _loadSeasonInternal(core.tmdbId, defaultSeason, token, gen).ignore();
      }

      // Phase 2: Resolve external IDs for Better Posters in prioritized background waves.
      if (!core.isExternalIdsResolved) {
        final enriched = await _repo.enrichExternalIds(
          core,
          cancelToken: token,
          onWave1Complete: (wave1Details) {
            if (gen != _generation || token.isCancelled) return;
            final liveWave1 = _resolveLiveInteraction(wave1Details);
            state = state.copyWith(
              phase: DetailsLoadPhase.enrichingRelated,
              details: liveWave1.details,
              userRating: liveWave1.userRating,
              clearUserRating: liveWave1.userRating == null,
              isInMyList: liveWave1.isInMyList,
              similarMetas: _buildRelatedMetas(wave1Details.similar, fallbackType: wave1Details.mediaType),
              recommendedMetas: _buildRelatedMetas(wave1Details.recommendations, fallbackType: wave1Details.mediaType),
            );
          },
        );
        if (gen != _generation || token.isCancelled) return;
        final liveEnriched = _resolveLiveInteraction(enriched);
        state = state.copyWith(
          phase: DetailsLoadPhase.ready,
          details: liveEnriched.details,
          userRating: liveEnriched.userRating,
          clearUserRating: liveEnriched.userRating == null,
          isInMyList: liveEnriched.isInMyList,
          similarMetas: _buildRelatedMetas(enriched.similar, fallbackType: enriched.mediaType),
          recommendedMetas: _buildRelatedMetas(enriched.recommendations, fallbackType: enriched.mediaType),
        );
      }
    } catch (e) {
      if (gen != _generation || token.isCancelled) return;
      if (e is DioException && CancelToken.isCancel(e)) return;
      if (isStandardId && await _tryLoadFromStremioMeta(token, gen)) {
        return;
      }
      if (gen != _generation || token.isCancelled) return;
      state = state.copyWith(
        phase: DetailsLoadPhase.error,
        errorMessage: e.toString(),
      );
    }
  }

  /// Merges live user interaction state onto newly loaded metadata while
  /// preserving any toggle made on this controller before load finished.
  ({TmdbMovieDetails details, double? userRating, bool isInMyList})
      _resolveLiveInteraction(TmdbMovieDetails incoming) {
    final effectiveImdb =
        incoming.imdbId ?? (arg.id.startsWith('tt') ? arg.id : null);
    final lookupImdb =
        effectiveImdb ?? (int.tryParse(arg.id.trim()) == null ? arg.id : null);
    final argAlias =
        (int.tryParse(arg.id.trim()) == null && arg.id != lookupImdb)
            ? arg.id
            : null;
    final cachedRating = _repo.getCachedUserRating(
          tmdbId: incoming.tmdbId,
          imdbId: lookupImdb,
          mediaType: incoming.mediaType,
        ) ??
        (argAlias != null
            ? _repo.getCachedUserRating(
                imdbId: argAlias,
                mediaType: incoming.mediaType,
              )
            : null);
    final cachedInList = _repo.getCachedIsInMyList(
          tmdbId: incoming.tmdbId,
          imdbId: lookupImdb,
          mediaType: incoming.mediaType,
        ) ||
        (argAlias != null &&
            _repo.getCachedIsInMyList(
              imdbId: argAlias,
              mediaType: incoming.mediaType,
            ));
    final resolvedRating = _userEditedReaction
        ? state.userRating
        : (cachedRating ?? incoming.userRating);
    final resolvedInList = _userEditedMyList
        ? state.isInMyList
        : (incoming.isInMyList || cachedInList);
    return (
      details: incoming.copyWith(
        userRating: resolvedRating,
        clearUserRating: resolvedRating == null,
        isInMyList: resolvedInList,
      ),
      userRating: resolvedRating,
      isInMyList: resolvedInList,
    );
  }

  /// Retries loading details after a network failure.
  Future<void> retry() => _load();

  Future<void> _syncAccountRating(
    TmdbMovieDetails core,
    CancelToken token,
    int gen,
  ) async {
    if (_userEditedReaction) return;
    final remoteRating = await _repo.syncAccountRatingFromTmdb(
      tmdbId: core.tmdbId,
      imdbId: core.imdbId ?? arg.id,
      mediaType: core.mediaType,
      cancelToken: token,
    );
    if (gen != _generation || token.isCancelled || _userEditedReaction) return;
    if (remoteRating != null && remoteRating != state.userRating) {
      state = state.copyWith(
        userRating: remoteRating,
        details: state.details?.copyWith(userRating: remoteRating),
      );
    }
  }

  Future<void> _resolveCollectionMovies(
    TmdbMovieDetails core,
    CancelToken token,
    int gen,
  ) async {
    final collectionId = core.collectionId;
    if (collectionId == null || core.mediaType != 'movie') return;
    try {
      final items = await _repo.fetchCollectionMovies(
        collectionId,
        excludeTmdbId: core.tmdbId,
        cancelToken: token,
      );
      if (gen != _generation || token.isCancelled) return;
      _scheduleNextReleaseWatch();
      if (items.isEmpty) {
        if (state.collectionMetas.isNotEmpty) {
          state = state.copyWith(collectionMetas: const []);
        }
        return;
      }

      state = state.copyWith(
        collectionMetas: _buildRelatedMetas(items, fallbackType: 'movie'),
      );

      if (items.any((m) => m.imdbId == null)) {
        final enriched = await _repo.enrichCollectionExternalIds(
          collectionId,
          excludeTmdbId: core.tmdbId,
          cancelToken: token,
          onWave1Complete: (wave1Items) {
            if (gen != _generation || token.isCancelled) return;
            state = state.copyWith(
              collectionMetas: _buildRelatedMetas(wave1Items, fallbackType: 'movie'),
            );
          },
        );
        if (gen != _generation || token.isCancelled) return;
        state = state.copyWith(
          collectionMetas: _buildRelatedMetas(enriched, fallbackType: 'movie'),
        );
      }
    } catch (_) {
      // Non-critical background enrichment failure
    }
  }

  Future<void> _resolveAnimePicks(
    TmdbMovieDetails core,
    CancelToken token,
    int gen,
  ) async {
    try {
      await _animeIdMap.ensureLoaded();
      if (gen != _generation || token.isCancelled) return;

      final imdb = core.imdbId ?? (arg.id.startsWith('tt') ? arg.id : null);
      int? anilistId;
      if (imdb != null) {
        anilistId = _animeIdMap.lookupAnilistIdByImdb(imdb);
      }
      anilistId ??= _animeIdMap.lookupAnilistIdByTmdb(
        tmdbId: core.tmdbId,
        type: core.mediaType,
      );

      final isAnime = state.isAnime ||
          anilistId != null ||
          core.isJapaneseAnimation ||
          _repo.isKeyOrAnime(
            tmdbId: core.tmdbId,
            imdbId: imdb,
            mediaType: core.mediaType,
            animeIdMap: _animeIdMap,
          );
      if (!isAnime) return;

      _repo.markAsAnime(
        tmdbId: core.tmdbId,
        imdbId: imdb,
        mediaType: core.mediaType,
        anilistId: anilistId,
      );
      if (!state.isAnime) {
        state = state.copyWith(isAnime: true);
      }

      if (anilistId == null) return;

      final recs = await _aniListRepo.fetchRecommendations(
        anilistId,
        cancelToken: token,
      );
      if (gen != _generation || token.isCancelled) return;
      if (recs.isNotEmpty) {
        state = state.copyWith(animePicks: recs);
      }
    } catch (_) {
      // Non-critical background enrichment failure
    }
  }

  Future<bool> _resolveIsAnimeForInteraction({MetaModel? meta}) async {
    await _animeIdMap.ensureLoaded();
    final parsedTmdbId = state.details?.tmdbId ?? int.tryParse(arg.id.trim());
    final effectiveImdb =
        state.details?.imdbId ?? (parsedTmdbId == null ? arg.id : null);
    final effectiveType = state.details?.mediaType ?? arg.type;
    final detected = state.isAnime ||
        (state.details?.isJapaneseAnimation ?? false) ||
        _repo.isKeyOrAnime(
          tmdbId: parsedTmdbId,
          imdbId: effectiveImdb,
          mediaType: effectiveType,
          meta: meta,
          animeIdMap: _animeIdMap,
        );
    if (detected && !state.isAnime) {
      state = state.copyWith(isAnime: true);
    }
    return detected;
  }

  /// Likes this movie or series (submits TMDB rating `> 8.0`, specifically `8.5`),
  /// or clears the rating if already liked.
  Future<void> toggleLike({MetaModel? meta}) async {
    _userEditedReaction = true;
    final isAlreadyLiked = state.userReaction == TmdbUserReaction.liked;
    final double? nextRating = isAlreadyLiked ? null : kTmdbLikeRatingValue;
    state = state.copyWith(
      userRating: nextRating,
      clearUserRating: nextRating == null,
      details: state.details?.copyWith(
        userRating: nextRating,
        clearUserRating: nextRating == null,
      ),
    );
    final isAnime = await _resolveIsAnimeForInteraction(meta: meta);
    final parsedTmdbId = state.details?.tmdbId ?? int.tryParse(arg.id.trim());
    await _repo.setUserRating(
      tmdbId: parsedTmdbId,
      imdbId: state.details?.imdbId ?? (parsedTmdbId == null ? arg.id : null),
      mediaType: state.details?.mediaType ?? arg.type,
      rating: nextRating,
      meta: meta,
      isAnime: isAnime,
    );
  }

  /// Marks this movie or series as "Not for me" (submits TMDB rating `< 2.0`,
  /// specifically `1.5`), or clears the rating if already marked "Not for me".
  Future<void> toggleDislike({MetaModel? meta}) async {
    _userEditedReaction = true;
    final isAlreadyDisliked = state.userReaction == TmdbUserReaction.disliked;
    final double? nextRating = isAlreadyDisliked ? null : kTmdbDislikeRatingValue;
    state = state.copyWith(
      userRating: nextRating,
      clearUserRating: nextRating == null,
      details: state.details?.copyWith(
        userRating: nextRating,
        clearUserRating: nextRating == null,
      ),
    );
    final isAnime = await _resolveIsAnimeForInteraction(meta: meta);
    final parsedTmdbId = state.details?.tmdbId ?? int.tryParse(arg.id.trim());
    await _repo.setUserRating(
      tmdbId: parsedTmdbId,
      imdbId: state.details?.imdbId ?? (parsedTmdbId == null ? arg.id : null),
      mediaType: state.details?.mediaType ?? arg.type,
      rating: nextRating,
      meta: meta,
      isAnime: isAnime,
    );
  }

  /// Toggles whether this movie or series is saved in "My List".
  Future<void> toggleMyList({MetaModel? meta}) async {
    _userEditedMyList = true;
    final nextInList = !state.isInMyList;
    state = state.copyWith(
      isInMyList: nextInList,
      details: state.details?.copyWith(isInMyList: nextInList),
    );
    final isAnime = await _resolveIsAnimeForInteraction(meta: meta);
    final parsedTmdbId = state.details?.tmdbId ?? int.tryParse(arg.id.trim());
    await _repo.setMyList(
      tmdbId: parsedTmdbId,
      imdbId: state.details?.imdbId ?? (parsedTmdbId == null ? arg.id : null),
      mediaType: state.details?.mediaType ?? arg.type,
      inMyList: nextInList,
      meta: meta,
      isAnime: isAnime,
    );
  }

  /// Series Hook: Selects a season and fetches its episodes if not already cached.
  Future<void> selectSeason(int seasonNumber) async {
    final currentDetails = state.details;
    if (currentDetails == null || currentDetails.mediaType != 'series') return;

    if (currentDetails.tmdbId <= 0) {
      if (state.seasonsCache.containsKey(seasonNumber)) {
        state = state.copyWith(
          selectedSeasonNumber: seasonNumber,
          isLoadingSeason: false,
        );
      }
      return;
    }

    final existing = state.seasonsCache[seasonNumber];
    if (existing != null && !existing.hasNewlyReleasedIncompleteEpisode()) {
      final refreshed = existing.filterReleased();
      state = state.copyWith(
        selectedSeasonNumber: seasonNumber,
        seasonsCache: {...state.seasonsCache, seasonNumber: refreshed},
        isLoadingSeason: false,
      );
      _scheduleNextReleaseWatch();
      return;
    }

    state = state.copyWith(
      selectedSeasonNumber: seasonNumber,
      isLoadingSeason: existing == null,
    );

    final token = _cancelToken ??= CancelToken();
    await _loadSeasonInternal(
      currentDetails.tmdbId,
      seasonNumber,
      token,
      _generation,
      forceRefresh: existing != null,
    );
  }

  Future<void> _loadSeasonInternal(
    int tvTmdbId,
    int seasonNumber,
    CancelToken token,
    int gen, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && state.seasonsCache.containsKey(seasonNumber)) return;
    if (state.seasonsCache[seasonNumber] == null) {
      state = state.copyWith(isLoadingSeason: true);
    }
    try {
      final seasonDetails = await _repo.fetchSeasonDetails(
        tvTmdbId,
        seasonNumber,
        cancelToken: token,
        forceRefresh: forceRefresh,
      );
      if (gen != _generation || token.isCancelled) return;
      state = state.copyWith(
        seasonsCache: {...state.seasonsCache, seasonNumber: seasonDetails},
        isLoadingSeason: false,
      );
      _scheduleNextReleaseWatch();
    } catch (e) {
      if (gen != _generation || token.isCancelled) return;
      state = state.copyWith(
        isLoadingSeason: false,
        seasonError: e.toString(),
      );
    }
  }

  /// Re-evaluates cached seasons, related rows, and collection movies when the
  /// calendar date advances (e.g. app resumed overnight) or a release timer fires.
  void refreshIfReleaseArrived() {
    _releaseTimer?.cancel();
    final currentDetails = state.details;
    if (currentDetails == null) return;
    final token = _cancelToken ??= CancelToken();
    final gen = _generation;

    final activeSeason = state.activeSeasonDetails;
    if (activeSeason != null) {
      if (activeSeason.hasNewlyReleasedIncompleteEpisode(now: _repo.currentNow)) {
        _loadSeasonInternal(
          currentDetails.tmdbId,
          activeSeason.seasonNumber,
          token,
          gen,
          forceRefresh: true,
        ).ignore();
      } else {
        final filteredSeason = activeSeason.filterReleased(now: _repo.currentNow);
        if (!identical(filteredSeason, activeSeason)) {
          state = state.copyWith(
            seasonsCache: {
              ...state.seasonsCache,
              activeSeason.seasonNumber: filteredSeason,
            },
          );
        }
      }
    }

    _refreshRelatedAndCollectionOnRelease(currentDetails, token, gen);
    _scheduleNextReleaseWatch();
  }

  void _refreshRelatedAndCollectionOnRelease(
    TmdbMovieDetails currentDetails,
    CancelToken token,
    int gen,
  ) {
    final now = _repo.currentNow;
    final filteredDetails = currentDetails.filterReleasedRelated(now: now);
    if (!identical(filteredDetails, currentDetails)) {
      final live = _resolveLiveInteraction(filteredDetails);
      state = state.copyWith(
        details: live.details,
        similarMetas: _buildRelatedMetas(
          filteredDetails.similar,
          fallbackType: filteredDetails.mediaType,
        ),
        recommendedMetas: _buildRelatedMetas(
          filteredDetails.recommendations,
          fallbackType: filteredDetails.mediaType,
        ),
      );
      final needsImdb = filteredDetails.similar.take(20).any((s) => s.imdbId == null) ||
          filteredDetails.recommendations.take(20).any((r) => r.imdbId == null);
      if (needsImdb) {
        unawaited(
          _repo
              .enrichExternalIds(
                filteredDetails,
                cancelToken: token,
                onWave1Complete: (wave1) {
                  if (gen != _generation || token.isCancelled) return;
                  final liveWave1 = _resolveLiveInteraction(wave1);
                  state = state.copyWith(
                    details: liveWave1.details,
                    similarMetas: _buildRelatedMetas(wave1.similar, fallbackType: wave1.mediaType),
                    recommendedMetas: _buildRelatedMetas(wave1.recommendations, fallbackType: wave1.mediaType),
                  );
                },
              )
              .then((enriched) {
            if (gen != _generation || token.isCancelled) return;
            final liveEnriched = _resolveLiveInteraction(enriched);
            state = state.copyWith(
              details: liveEnriched.details,
              similarMetas: _buildRelatedMetas(enriched.similar, fallbackType: enriched.mediaType),
              recommendedMetas: _buildRelatedMetas(enriched.recommendations, fallbackType: enriched.mediaType),
            );
          }, onError: (_) {}),
        );
      }
    }

    final collectionId = currentDetails.collectionId;
    if (currentDetails.mediaType == 'movie' && collectionId != null) {
      final releasedCollection = _repo.getCachedCollectionMovies(
        collectionId,
        excludeTmdbId: currentDetails.tmdbId,
      );
      if (releasedCollection != null) {
        final nextMetas = _buildRelatedMetas(releasedCollection, fallbackType: 'movie');
        if (nextMetas.length != state.collectionMetas.length) {
          state = state.copyWith(collectionMetas: nextMetas);
          if (releasedCollection.any((m) => m.imdbId == null)) {
            unawaited(
              _repo
                  .enrichCollectionExternalIds(
                    collectionId,
                    excludeTmdbId: currentDetails.tmdbId,
                    cancelToken: token,
                    onWave1Complete: (wave1) {
                      if (gen != _generation || token.isCancelled) return;
                      state = state.copyWith(
                        collectionMetas: _buildRelatedMetas(wave1, fallbackType: 'movie'),
                      );
                    },
                  )
                  .then((enriched) {
                if (gen != _generation || token.isCancelled) return;
                state = state.copyWith(
                  collectionMetas: _buildRelatedMetas(enriched, fallbackType: 'movie'),
                );
              }, onError: (_) {}),
            );
          }
        }
      }
    }
  }

  /// Watches the earliest upcoming release date across active episodes, related
  /// rows, and collection movies, revealing titles the moment their release date
  /// arrives.
  void _scheduleNextReleaseWatch() {
    _releaseTimer?.cancel();
    final currentDetails = state.details;
    if (currentDetails == null) return;

    final now = _repo.currentNow;
    final candidates = <DateTime>[
      if (state.activeSeasonDetails?.nextEpisodeReleaseDate(now: now) case final d?) d,
      if (currentDetails.nextRelatedReleaseDate(now: now) case final d?) d,
      if (currentDetails.collectionId != null && currentDetails.mediaType == 'movie')
        if (_repo.getNextCollectionReleaseDate(
          currentDetails.collectionId!,
          excludeTmdbId: currentDetails.tmdbId,
          now: now,
        )
            case final d?)
          d,
    ];
    if (candidates.isEmpty) return;
    candidates.sort();
    final nextRelease = candidates.first;

    final wait = nextRelease.difference(now);
    // Cap single timer chunk at 6 hours so long waits re-check periodically.
    final clampedWait = wait.isNegative
        ? const Duration(milliseconds: 250)
        : (wait > const Duration(hours: 6)
            ? const Duration(hours: 6)
            : wait + const Duration(seconds: 1));

    final gen = _generation;
    _releaseTimer = Timer(clampedWait, () {
      if (gen != _generation) return;
      refreshIfReleaseArrived();
    });
  }

  int? _pickActiveOrDefaultSeason(TmdbMovieDetails details) {
    if (details.mediaType != 'series') return null;
    final progressStore =
        ref.read(watchProgressControllerProvider).valueOrNull;
    final raw = arg.id.trim();
    final effectiveImdb =
        details.imdbId ?? (raw.startsWith('tt') ? raw : null);
    final parsedAnilist = raw.startsWith('anilist:')
        ? int.tryParse(raw.substring('anilist:'.length))
        : null;
    final entry = progressStore?.lookup(
      imdbId: effectiveImdb,
      tmdbId: details.tmdbId > 0 ? details.tmdbId : int.tryParse(raw),
      anilistId: parsedAnilist,
      rawId: raw,
      mediaType: details.mediaType,
    );
    if (entry != null) {
      final targetSeason = resolveSeriesPlaybackTarget(
        entry: entry,
        seasons: details.seasons,
      ).season;
      if (details.seasons.isEmpty ||
          details.seasons.any((s) => s.seasonNumber == targetSeason)) {
        return targetSeason;
      }
    }
    return _pickDefaultSeason(details);
  }

  static int? _pickDefaultSeason(TmdbMovieDetails details) {
    if (details.mediaType != 'series') return null;
    if (details.seasons.isEmpty) return 1;
    final regular = details.seasons.where((s) => s.seasonNumber > 0);
    return regular.isNotEmpty ? regular.first.seasonNumber : details.seasons.first.seasonNumber;
  }

  static List<MetaModel> _buildRelatedMetas(
    List<TmdbRecommendation> items, {
    required String fallbackType,
  }) =>
      [
        for (final r in items)
          MetaModel(
            id: r.imdbId ?? '${r.id}',
            type: r.mediaType.isNotEmpty ? r.mediaType : fallbackType,
            name: r.title,
            poster: r.imdbId != null
                ? betterPosterUrl(r.imdbId!)
                : (r.id.toString().startsWith('tt')
                    ? betterPosterUrl(r.id.toString())
                    : r.posterUrl),
            posterFallback: r.posterUrl,
          ),
      ];
}

final detailsControllerProvider =
    AutoDisposeNotifierProviderFamily<DetailsController, DetailsViewState, DetailsQueryKey>(
  DetailsController.new,
);
