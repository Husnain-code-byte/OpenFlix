import 'dart:async';

import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/errors/user_error.dart';
import '../../../../core/perf/image_perf.dart';
import '../../../addons/data/stremio_addon_service.dart';
import '../../../addons/domain/models/addon_models.dart';
import '../../../addons/presentation/controllers/addons_controller.dart';
import '../../../anime/data/anilist_addon_repository.dart';
import '../../../anime/data/anime_id_map.dart';
import '../../../details/data/tmdb_repository.dart';
import '../../data/models/manifest_model.dart';
import '../../data/models/meta_model.dart';
import '../../data/repositories/hero_artwork_repository.dart';

enum ShelfStatus { idle, loading, loaded, error }

class ShelfState extends Equatable {
  const ShelfState({required this.catalog, this.status = ShelfStatus.idle, this.metas = const [], this.error});
  final CatalogItemModel catalog;
  final ShelfStatus status;
  final List<MetaModel> metas;
  final String? error;

  ShelfState copyWith({ShelfStatus? status, List<MetaModel>? metas, String? error}) =>
      ShelfState(catalog: catalog, status: status ?? this.status, metas: metas ?? this.metas, error: error);

  @override
  List<Object?> get props => [catalog.key, status, metas, error];
}

/// Per-shelf store — patching one row never rebuilds the others.
class ShelvesController extends Notifier<Map<String, ShelfState>> {
  @override
  Map<String, ShelfState> build() => const {};

  /// Rebuilds the shelf map for [catalogs].
  ///
  /// [keepContent] (pull-to-refresh) keeps the posters already on screen and only
  /// resets the status to `idle`, so rows revalidate without flashing a skeleton.
  void init(List<CatalogItemModel> catalogs, {bool keepContent = false}) => state = {
        for (final c in catalogs)
          c.key: keepContent
              ? (state[c.key]?.copyWith(status: ShelfStatus.idle) ?? ShelfState(catalog: c))
              : ShelfState(catalog: c),
      };

  void patch(String key, ShelfState Function(ShelfState) update) {
    final current = state[key];
    if (current != null) state = {...state, key: update(current)};
  }

  /// Syncs enabled custom Stremio addon catalogs into the shelf map without
  /// clearing or flashing built-in TMDB/AniList shelves.
  void syncCustomCatalogs(
    List<CatalogItemModel> customCatalogs, {
    bool resetStatus = false,
  }) {
    final desiredByKey = {for (final c in customCatalogs) c.key: c};
    final next = <String, ShelfState>{};

    for (final entry in state.entries) {
      if (entry.value.catalog.addonId == null) {
        next[entry.key] = entry.value;
      }
    }

    for (final c in desiredByKey.values) {
      final prev = state[c.key];
      if (prev != null) {
        next[c.key] = resetStatus
            ? ShelfState(
                catalog: c,
                status: ShelfStatus.idle,
                metas: prev.metas,
              )
            : ShelfState(
                catalog: c,
                status: prev.status,
                metas: prev.metas,
                error: prev.error,
              );
      } else {
        next[c.key] = ShelfState(catalog: c);
      }
    }

    state = next;
  }

  void ensureCatalog(CatalogItemModel catalog) {
    if (state.containsKey(catalog.key)) return;
    state = {...state, catalog.key: ShelfState(catalog: catalog)};
  }
}

final shelvesProvider = NotifierProvider<ShelvesController, Map<String, ShelfState>>(ShelvesController.new);

sealed class HomeState extends Equatable {
  const HomeState();
  @override
  List<Object?> get props => [];
}

class HomeInitial extends HomeState {
  const HomeInitial();
}

class HomeLoading extends HomeState {
  const HomeLoading();
}

class HomeReady extends HomeState {
  const HomeReady({
    required this.manifest,
    required this.catalogs,
    required this.hero,
    this.addonError,
    this.refreshError,
    this.refreshErrorTick = 0,
  });
  final ManifestModel manifest;
  final List<CatalogItemModel> catalogs;
  final List<MetaModel> hero;
  final String? addonError;
  final UserError? refreshError;
  final int refreshErrorTick;

  HomeReady copyWith({
    List<MetaModel>? hero,
    String? addonError,
    bool clearAddonError = false,
    UserError? refreshError,
    bool clearRefreshError = false,
    int? refreshErrorTick,
  }) =>
      HomeReady(
        manifest: manifest,
        catalogs: catalogs,
        hero: hero ?? this.hero,
        addonError: clearAddonError ? null : (addonError ?? this.addonError),
        refreshError:
            clearRefreshError ? null : (refreshError ?? this.refreshError),
        refreshErrorTick: refreshErrorTick ?? this.refreshErrorTick,
      );

  @override
  List<Object?> get props => [
        manifest,
        catalogs,
        hero,
        addonError,
        refreshError,
        refreshErrorTick,
      ];
}

class HomeError extends HomeState {
  const HomeError(this.error);
  final UserError error;
  String get message => error.message;
  @override
  List<Object?> get props => [error];
}

class HomeController extends Notifier<HomeState> {
  late AniListAddonRepository _aniListRepo;
  late TmdbRepository _tmdbRepo;
  CancelToken? _cancel;
  Timer? _midnightTimer;
  final Set<String> _inflight = {};

  // Hero data accumulates as catalogs resolve (kept out of widget rebuilds)
  final List<List<MetaModel>> _heroLists = [];
  final Set<String> _warmedUrls = {};
  final Map<String, String> _shelfLoadedDayKey = {};
  String _loadedDayKey = _currentDayKey();

  static String _currentDayKey() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  void _scheduleMidnightRefresh() {
    _midnightTimer?.cancel();
    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1, 0, 0, 1);
    final wait = nextMidnight.difference(now);
    final clampedWait = wait.isNegative
        ? const Duration(milliseconds: 250)
        : (wait > const Duration(hours: 6) ? const Duration(hours: 6) : wait);
    _midnightTimer = Timer(clampedWait, () {
      if (_currentDayKey() != _loadedDayKey) {
        refreshIfDayChanged();
      } else {
        _scheduleMidnightRefresh();
      }
    });
  }

  Future<void> refreshIfDayChanged() async {
    final today = _currentDayKey();
    if (today == _loadedDayKey) {
      _scheduleMidnightRefresh();
      return;
    }
    await load(isRefresh: true);
  }

  void _warmUrl(String? rawUrl, {required int forWidthPx}) {
    if (rawUrl == null || rawUrl.isEmpty) return;
    final url = tmdbSized(rawUrl, forWidthPx: forWidthPx);
    if (url.isEmpty || !_warmedUrls.add(url)) return;
    unawaited(
      PixelImageCache.instance.getSingleFile(url).then<void>((_) {}, onError: (_) {}),
    );
  }

  void _warmShelfPosters(List<MetaModel> metas, {int count = 8}) {
    for (final m in metas.take(count)) {
      final raw = m.poster ?? m.posterFallback;
      // Warm both standard buckets (w342 and w500) depending on device DPR;
      // non-TMDB URLs pass through unchanged so _warmedUrls deduplicates them.
      _warmUrl(raw, forWidthPx: 300);
      _warmUrl(raw, forWidthPx: 500);
    }
  }

  void _extendHero() {
    final st = state;
    if (st is! HomeReady) return;
    final hero = buildHeroPool(_heroLists, ApiConstants.heroItems);
    // buildHeroPool is a stable superset — only extend, never reorder
    if (hero.length > st.hero.length) {
      state = st.copyWith(hero: hero);
      for (final m in hero) {
        _warmUrl(m.background ?? m.landscapePoster ?? m.posterFallback ?? m.poster, forWidthPx: 1100);
        _warmUrl(m.logo, forWidthPx: 600);
        unawaited(
          ref
              .read(heroArtworkProvider((imdbId: m.id, type: m.type)).future)
              .then<void>((art) {
            if (art != null) {
              _warmUrl(art.posterUrl ?? art.backdropUrl, forWidthPx: 1100);
              _warmUrl(art.logoUrl, forWidthPx: 600);
            }
          }, onError: (_) {}),
        );
      }
    }
  }

  @override
  HomeState build() {
    _aniListRepo = ref.watch(aniListAddonRepositoryProvider);
    _tmdbRepo = ref.watch(tmdbRepositoryProvider);
    ref.listen<AsyncValue<AddonsStoreState>>(addonsControllerProvider, (_, next) {
      if (state is HomeReady) {
        _syncCustomCatalogs(next.valueOrNull);
      }
    });
    ref.onDispose(() {
      _midnightTimer?.cancel();
      _cancel?.cancel();
    });
    Future.microtask(load);
    return const HomeInitial();
  }

  void _syncCustomCatalogs(
    AddonsStoreState? store, {
    bool resetStatus = false,
  }) {
    final customCatalogs = _collectAllCustomCatalogs(store);
    _shelves.syncCustomCatalogs(customCatalogs, resetStatus: resetStatus);
  }

  static List<CatalogItemModel> _collectAllCustomCatalogs(
    AddonsStoreState? store,
  ) {
    if (store == null || store.stremioAddons.isEmpty) return const [];
    final sorted = [...store.stremioAddons]
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    final out = <CatalogItemModel>[];
    final seen = <String>{};
    for (final addon in sorted) {
      if (!addon.enabled) continue;
      for (final cat in addon.manifest.catalogs) {
        if (cat.hasRequiredExtra) continue;
        final placement = addon.placementFor(cat);
        if (placement == null ||
            !placement.enabled ||
            placement.targetScreens.isEmpty) {
          continue;
        }
        final namespaced = cat.copyWithAddon(
          addon.id,
          addon.manifest.name,
          customName: placement.customTitle,
        );
        if (seen.add(namespaced.key)) {
          out.add(namespaced);
        }
      }
    }
    return out;
  }

  ShelvesController get _shelves => ref.read(shelvesProvider.notifier);

  Future<void> load({bool isRefresh = false}) async {
    _cancel?.cancel();
    _cancel = CancelToken();
    _inflight.clear();
    _heroLists.clear();
    _loadedDayKey = _currentDayKey();
    _scheduleMidnightRefresh();
    if (isRefresh) {
      _aniListRepo.clearCache();
      _tmdbRepo.clearCategoryCache();
    }
    if (!(isRefresh && state is HomeReady)) state = const HomeLoading();

    // Warm bundled Anime ID map in background immediately.
    unawaited(ref.read(animeIdMapProvider).ensureLoaded());

    try {
      final standardCatalogs = _tmdbRepo.getStandardCatalogs();
      final aniListManifest = await _aniListRepo.fetchManifest(cancelToken: _cancel);
      final categoryCatalogs = await _tmdbRepo.fetchCategoryCatalogs(cancelToken: _cancel);
      final aniListCatalogs = aniListManifest.catalogs.where((c) => !c.hasRequiredExtra).toList();
      final catalogs = [...standardCatalogs, ...aniListCatalogs, ...categoryCatalogs];

      final resolvedManifest = ManifestModel(
        id: 'org.themoviedb.v3',
        version: '3.0.0',
        name: 'TMDB',
        catalogs: standardCatalogs,
      );

      if (isRefresh && state is HomeReady) {
        final cur = state as HomeReady;
        state = HomeReady(
          manifest: resolvedManifest,
          catalogs: catalogs,
          hero: cur.hero,
        );
      } else {
        state = HomeReady(
          manifest: resolvedManifest,
          catalogs: catalogs,
          hero: const [],
        );
      }
      _shelves.init(catalogs, keepContent: isRefresh);
      _syncCustomCatalogs(
        ref.read(addonsControllerProvider).valueOrNull,
        resetStatus: isRefresh,
      );

      // First batch concurrently; hero appears as soon as the first list resolves.
      final batch = standardCatalogs.take(ApiConstants.initialCatalogBatch).toList();

      final batchErrors = <Object>[];
      final results = await Future.wait(
        batch.map(
          (c) => _loadShelf(c).then<List<MetaModel>?>((v) => v).catchError((Object err) {
            batchErrors.add(err);
            return null;
          }),
        ),
      );
      final lists = results.whereType<List<MetaModel>>().toList();
      if (standardCatalogs.isNotEmpty && lists.isEmpty) {
        final cur = state;
        final mapped = UserError.from(
          batchErrors.firstOrNull ?? 'offline',
          fallbackType: UserErrorType.offline,
          logTag: 'HomeController.batch',
        );
        if (cur is HomeReady) {
          final hasCachedShelves = ref
              .read(shelvesProvider)
              .values
              .any((s) => s.metas.isNotEmpty);
          if (isRefresh && (cur.hero.isNotEmpty || hasCachedShelves)) {
            state = cur.copyWith(
              clearAddonError: true,
              refreshError: mapped,
              refreshErrorTick: cur.refreshErrorTick + 1,
            );
          } else {
            state = cur.copyWith(addonError: mapped.message);
          }
        }
      } else if (state is HomeReady) {
        state = (state as HomeReady).copyWith(
          clearAddonError: true,
          clearRefreshError: true,
        );
      }
      _extendHero();

      // Immediately start downloading the next wave of catalogs and their posters
      // in the background while the opening screen finishes resting, plus top 2
      // AniList shelves and top 4 TMDB Category shelves (2 Movie + 2 Series) so
      // the Anime and Categories tab heroes and top rows are warm immediately.
      final nextWave = [
        ...standardCatalogs
            .skip(ApiConstants.initialCatalogBatch)
            .take(ApiConstants.backgroundCatalogBatch),
        ...aniListCatalogs.take(2),
        ...categoryCatalogs.take(4),
      ];
      if (nextWave.isNotEmpty) {
        unawaited(
          Future.wait(
            nextWave.map((c) => _loadShelf(c, warmCount: 6).then<void>((_) {}, onError: (_) {})),
          ),
        );
      }
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) return;
      final mapped = UserError.from(e, logTag: 'HomeController.load');
      final cur = state;
      final hasCached = cur is HomeReady &&
          (cur.hero.isNotEmpty ||
              ref.read(shelvesProvider).values.any((s) => s.metas.isNotEmpty));
      if (isRefresh && hasCached) {
        state = cur.copyWith(
          refreshError: mapped,
          refreshErrorTick: cur.refreshErrorTick + 1,
        );
        return;
      }
      state = HomeError(mapped);
    } catch (e) {
      final mapped = UserError.from(e, logTag: 'HomeController.load');
      final cur = state;
      final hasCached = cur is HomeReady &&
          (cur.hero.isNotEmpty ||
              ref.read(shelvesProvider).values.any((s) => s.metas.isNotEmpty));
      if (isRefresh && hasCached) {
        state = cur.copyWith(
          refreshError: mapped,
          refreshErrorTick: cur.refreshErrorTick + 1,
        );
        return;
      }
      state = HomeError(mapped);
    }
  }

  Future<List<MetaModel>> _loadShelf(CatalogItemModel c, {int warmCount = 8}) async {
    if (!_inflight.add(c.key)) return const [];
    _shelves.patch(c.key, (s) => s.copyWith(status: ShelfStatus.loading));
    try {
      final List<MetaModel> metas;
      if (c.addonId != null) {
        final store = ref.read(addonsControllerProvider).valueOrNull;
        final addon = store?.stremioAddons
            .where((a) => a.id == c.addonId && a.enabled)
            .firstOrNull;
        if (addon == null) {
          metas = const [];
        } else {
          metas = await ref.read(stremioAddonServiceProvider).fetchCatalog(
                addon.baseUrl,
                c,
                sourceAddonId: addon.id,
                cancelToken: _cancel,
              );
        }
      } else if (c.id.startsWith('anilist.')) {
        metas = await _aniListRepo.fetchCatalog(c, cancelToken: _cancel);
      } else if (c.id.startsWith('tmdb.standard.')) {
        metas = await _tmdbRepo.fetchStandardCatalog(
          c,
          cancelToken: _cancel,
          onWave2Enriched: (enriched) {
            _shelves.patch(c.key, (s) => s.copyWith(metas: enriched));
          },
        );
      } else if (c.id.startsWith('tmdb.category.')) {
        metas = await _tmdbRepo.fetchCategoryCatalog(
          c,
          cancelToken: _cancel,
          onWave2Enriched: (enriched) {
            _shelves.patch(c.key, (s) => s.copyWith(metas: enriched));
          },
        );
      } else {
        metas = const [];
      }
      _shelves.patch(c.key, (s) => s.copyWith(status: ShelfStatus.loaded, metas: metas));
      _shelfLoadedDayKey[c.key] = _currentDayKey();
      _warmShelfPosters(metas, count: warmCount);
      if (c.id.startsWith('tmdb.category.')) {
        for (final m in metas.take(2)) {
          _warmUrl(m.background ?? m.landscapePoster ?? m.posterFallback ?? m.poster, forWidthPx: 1100);
          unawaited(
            ref
                .read(heroArtworkProvider((imdbId: m.id, type: m.type)).future)
                .then<void>((art) {
              if (art != null) {
                _warmUrl(art.posterUrl ?? art.backdropUrl, forWidthPx: 1100);
                _warmUrl(art.logoUrl, forWidthPx: 600);
              }
            }, onError: (_) {}),
          );
        }
      } else if (c.addonId == null &&
          _heroLists.length < ApiConstants.initialCatalogBatch &&
          !c.id.startsWith('anilist.')) {
        _heroLists.add(metas);
        _extendHero();
      }
      return metas;
    } catch (e) {
      _shelves.patch(c.key, (s) => s.copyWith(status: ShelfStatus.error, error: e.toString()));
      rethrow;
    } finally {
      _inflight.remove(c.key);
    }
  }

  Future<void> refresh() => load(isRefresh: true);

  /// Lazy-load a shelf when it becomes visible, or refresh a TMDB category / AniList
  /// shelf automatically if the calendar day (`YYYY-MM-DD`) has rolled over.
  void ensureShelf(String key, {CatalogItemModel? fallbackCatalog}) {
    var shelf = ref.read(shelvesProvider)[key];
    if (shelf == null && fallbackCatalog != null) {
      _shelves.ensureCatalog(fallbackCatalog);
      shelf = ref.read(shelvesProvider)[key];
    }
    if (shelf == null) return;
    final id = shelf.catalog.id;
    final isDailyRotatingShelf = id.startsWith('tmdb.standard.') ||
        id.startsWith('tmdb.category.') ||
        id.startsWith('anilist.');
    final isStaleDailyShelf = isDailyRotatingShelf &&
        shelf.status == ShelfStatus.loaded &&
        _shelfLoadedDayKey[key] != _currentDayKey();
    if (shelf.status == ShelfStatus.idle || isStaleDailyShelf) {
      _loadShelf(shelf.catalog).ignore();
    }
  }

  void retryShelf(String key) {
    final shelf = ref.read(shelvesProvider)[key];
    if (shelf != null) _loadShelf(shelf.catalog).ignore();
  }
}

final homeControllerProvider = NotifierProvider<HomeController, HomeState>(HomeController.new);

/// Top-nav headings. The selected one becomes the page title, the rest stay chips.
enum HomeFilter { home, movies, tvShows, anime, categories }

final homeFilterProvider = StateProvider<HomeFilter>((ref) => HomeFilter.home);

/// Filters catalogs by active top-nav heading:
/// - `anime`: AniList catalogs + anime-tagged catalogs.
/// - `categories`: TMDB Movie & Series genre categories (interleaved 1 movie, 1 series).
/// - `movies` / `tvShows` / `home`: Stremio addon catalogs.
bool catalogMatchesFilter(CatalogItemModel c, HomeFilter f) {
  if (c.id.startsWith('anilist.')) {
    return f == HomeFilter.anime;
  }
  if (c.id.startsWith('tmdb.category.')) {
    return f == HomeFilter.categories;
  }
  if (f == HomeFilter.categories) {
    return false;
  }
  return switch (f) {
    HomeFilter.movies => c.type == 'movie',
    HomeFilter.tvShows => c.type == 'series',
    HomeFilter.anime =>
      RegExp(r'anime|crunchyroll', caseSensitive: false).hasMatch('${c.name} ${c.id}'),
    _ => true,
  };
}

/// Interleaves the top poster-bearing items of several catalogs (the hero is a poster card).
List<MetaModel> buildHeroPool(List<List<MetaModel>> lists, int limit) {
  final usable = [
    for (final l in lists) l.where((m) => m.poster != null || m.posterFallback != null).toList()
  ];
  final pool = <MetaModel>[];
  final seen = <String>{};
  for (var i = 0; i < 4 && pool.length < limit; i++) {
    for (final list in usable) {
      if (i < list.length && seen.add(list[i].id)) {
        pool.add(list[i]);
        if (pool.length >= limit) break;
      }
    }
  }
  return pool;
}
