import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/perf/image_perf.dart';
import '../../../addons/data/stremio_addon_service.dart';
import '../../../addons/presentation/controllers/addons_controller.dart';
import '../../../details/data/tmdb_repository.dart';
import '../../../home/data/models/manifest_model.dart';
import '../../../home/data/models/meta_model.dart';
import '../../../home/data/repositories/addon_repository_impl.dart';
import '../../../home/domain/repositories/addon_repository.dart';

/// Represents a single horizontal search result row from either a search-capable
/// Stremio addon catalog or the user's TMDB API key.
class SearchResultRow extends Equatable {
  const SearchResultRow({
    required this.key,
    required this.title,
    required this.sourceName,
    required this.type,
    required this.order,
    required this.metas,
  });

  final String key;
  final String title;
  final String sourceName;
  final String type;
  final int order;
  final List<MetaModel> metas;

  SearchResultRow copyWith({
    String? title,
    List<MetaModel>? metas,
  }) =>
      SearchResultRow(
        key: key,
        title: title ?? this.title,
        sourceName: sourceName,
        type: type,
        order: order,
        metas: metas ?? this.metas,
      );

  @override
  List<Object?> get props => [key, title, sourceName, type, order, metas];
}

class SearchState extends Equatable {
  const SearchState({
    this.query = '',
    this.isSearching = false,
    this.rows = const [],
    this.errorMessage,
  });

  final String query;
  final bool isSearching;
  final List<SearchResultRow> rows;
  final String? errorMessage;

  bool get hasActiveQuery => query.trim().isNotEmpty;

  SearchState copyWith({
    String? query,
    bool? isSearching,
    List<SearchResultRow>? rows,
    String? errorMessage,
    bool clearError = false,
  }) =>
      SearchState(
        query: query ?? this.query,
        isSearching: isSearching ?? this.isSearching,
        rows: rows ?? this.rows,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      );

  @override
  List<Object?> get props => [query, isSearching, rows, errorMessage];
}

class SearchController extends Notifier<SearchState> {
  Timer? _debounceTimer;
  CancelToken? _cancelToken;
  int _generation = 0;

  // Session cache of resolved manifests per addon and completed search rows per query.
  final Map<AddonRepository, ManifestModel> _manifestCache = {};
  final Map<String, List<SearchResultRow>> _queryCache = {};
  final Set<String> _warmedUrls = {};
  String _cachedDayKey = _currentDayKey();

  static String _currentDayKey() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  void _invalidateIfDayChanged() {
    final today = _currentDayKey();
    if (today != _cachedDayKey) {
      _cachedDayKey = today;
      _queryCache.clear();
    }
  }

  @override
  SearchState build() {
    ref.onDispose(() {
      _debounceTimer?.cancel();
      _cancelToken?.cancel('SearchController disposed');
    });
    return const SearchState();
  }

  /// Updates the search query and triggers a debounced multi-addon + TMDB search.
  void setQuery(String value, {bool immediate = false}) {
    final prevTrimmed = state.query.trim();
    final nextTrimmed = value.trim();

    if (nextTrimmed.isEmpty) {
      _debounceTimer?.cancel();
      _cancelToken?.cancel('Query cleared');
      _generation++;
      state = const SearchState(query: '');
      return;
    }

    if (nextTrimmed == prevTrimmed && !immediate && (state.isSearching || state.rows.isNotEmpty)) {
      state = state.copyWith(query: value);
      return;
    }

    _invalidateIfDayChanged();
    final normalizedKey = nextTrimmed.toLowerCase();
    final cachedRows = _queryCache[normalizedKey];
    if (cachedRows != null && !immediate) {
      _debounceTimer?.cancel();
      _cancelToken?.cancel('Query served from cache');
      _generation++;
      state = SearchState(
        query: value,
        isSearching: false,
        rows: cachedRows,
      );
      return;
    }

    state = state.copyWith(
      query: value,
      isSearching: true,
      clearError: true,
    );

    _debounceTimer?.cancel();
    if (immediate) {
      _executeSearch(nextTrimmed);
    } else {
      _debounceTimer = Timer(const Duration(milliseconds: 260), () {
        _executeSearch(nextTrimmed);
      });
    }
  }

  /// Clears the search input and returns to the default discovery shelves.
  void clearQuery() => setQuery('');

  /// Immediately executes the search for the current query (e.g. on keyboard submit).
  void submitSearch([String? value]) {
    final target = value ?? state.query;
    if (target.trim().isEmpty) return;
    setQuery(target, immediate: true);
  }

  Future<void> _executeSearch(String trimmedQuery) async {
    _cancelToken?.cancel('Superseded by newer search query');
    final token = CancelToken();
    _cancelToken = token;
    final gen = ++_generation;
    final normalizedKey = trimmedQuery.toLowerCase();

    final addons = ref.read(installedAddonsProvider);
    final tmdbRepo = ref.read(tmdbRepositoryProvider);
    final customSearchAddons = ref.read(enabledSearchStremioAddonsProvider);
    final stremioService = ref.read(stremioAddonServiceProvider);

    final activeRowsByKey = <String, SearchResultRow>{};

    void upsertRow(SearchResultRow row) {
      if (gen != _generation || token.isCancelled) return;
      if (row.metas.isEmpty) return;
      activeRowsByKey[row.key] = row;
      final sorted = activeRowsByKey.values.toList()
        ..sort((a, b) => a.order.compareTo(b.order));
      state = state.copyWith(
        rows: sorted,
        clearError: true,
      );
      _warmRowPosters(row.metas);
    }

    try {
      // Resolve manifests for all installed addons in parallel.
      final addonEntries = await Future.wait(
        addons.map((addon) async {
          final cached = _manifestCache[addon];
          if (cached != null) return (addon: addon, manifest: cached);
          try {
            final manifest = await addon.fetchManifest(cancelToken: token);
            _manifestCache[addon] = manifest;
            return (addon: addon, manifest: manifest);
          } catch (_) {
            return null;
          }
        }),
      );

      if (gen != _generation || token.isCancelled) return;

      final searchTasks = <Future<void>>[];
      var orderCounter = 0;

      // 1. Launch a search request for every search-capable catalog across all installed addons.
      for (final entry in addonEntries.whereType<({AddonRepository addon, ManifestModel manifest})>()) {
        final addon = entry.addon;
        final manifest = entry.manifest;
        final searchCatalogs = manifest.catalogs.where((c) => c.supportsSearch).toList();

        for (final catalog in searchCatalogs) {
          final isAniList = manifest.id == 'anilist';
          final rowOrder = isAniList
              ? 1000 + (catalog.type == 'movie' ? 1 : 0)
              : orderCounter++;
          final rowKey = 'addon:${manifest.id}:${catalog.type}:${catalog.id}';
          final rowTitle = formatAddonSearchTitle(manifest.name, catalog);

          searchTasks.add(() async {
            try {
              final metas = await addon.searchCatalog(
                catalog,
                trimmedQuery,
                cancelToken: token,
              );
              final withPosters = metas
                  .where((m) =>
                      (m.poster != null && m.poster!.isNotEmpty) ||
                      (m.posterFallback != null && m.posterFallback!.isNotEmpty))
                  .toList();
              if (withPosters.isNotEmpty) {
                upsertRow(
                  SearchResultRow(
                    key: rowKey,
                    title: rowTitle,
                    sourceName: manifest.name,
                    type: catalog.type,
                    order: rowOrder,
                    metas: withPosters,
                  ),
                );
              }
            } catch (_) {
              // Individual addon catalog search failures do not block other rows.
            }
          }());
        }
      }

      // 2. Query search-capable catalogs on user-installed custom Stremio addons.
      var customOrderOffset = 500;
      for (final customAddon in customSearchAddons) {
        final customSearchCatalogs =
            customAddon.manifest.catalogs.where((c) => c.supportsSearch);
        for (final catalog in customSearchCatalogs) {
          final rowOrder = customOrderOffset++;
          final rowKey =
              'custom:${customAddon.id}:${catalog.type}:${catalog.id}';
          final rowTitle =
              formatAddonSearchTitle(customAddon.manifest.name, catalog);

          searchTasks.add(() async {
            try {
              final metas = await stremioService.fetchCatalog(
                customAddon.baseUrl,
                catalog,
                search: trimmedQuery,
                sourceAddonId: customAddon.id,
                cancelToken: token,
              );
              final withPosters = metas
                  .where((m) =>
                      (m.poster != null && m.poster!.isNotEmpty) ||
                      (m.posterFallback != null && m.posterFallback!.isNotEmpty))
                  .toList();
              final results = withPosters.isNotEmpty ? withPosters : metas;
              if (results.isNotEmpty) {
                upsertRow(
                  SearchResultRow(
                    key: rowKey,
                    title: rowTitle,
                    sourceName: customAddon.manifest.name,
                    type: catalog.type,
                    order: rowOrder,
                    metas: results,
                  ),
                );
              }
            } catch (_) {}
          }());
        }
      }

      // 3. Launch TMDB Movie and Series searches using the user's TMDB API key.
      for (final mediaType in const ['movie', 'series']) {
        final rowOrder = orderCounter++;
        final kindLabel = mediaType == 'series' ? 'Series' : 'Movies';
        final rowKey = 'tmdb:$mediaType';
        final rowTitle = 'TMDB · $kindLabel';

        searchTasks.add(() async {
          try {
            final metas = await tmdbRepo.searchMedia(
              trimmedQuery,
              type: mediaType,
              cancelToken: token,
              onEnriched: (enrichedMetas) {
                if (enrichedMetas.isNotEmpty) {
                  upsertRow(
                    SearchResultRow(
                      key: rowKey,
                      title: rowTitle,
                      sourceName: 'TMDB',
                      type: mediaType,
                      order: rowOrder,
                      metas: enrichedMetas,
                    ),
                  );
                }
              },
            );
            if (metas.isNotEmpty) {
              upsertRow(
                SearchResultRow(
                  key: rowKey,
                  title: rowTitle,
                  sourceName: 'TMDB',
                  type: mediaType,
                  order: rowOrder,
                  metas: metas,
                ),
              );
            }
          } catch (_) {
            // Individual TMDB search failures do not block addon rows.
          }
        }());
      }

      await Future.wait(searchTasks);

      if (gen != _generation || token.isCancelled) return;

      final finalRows = activeRowsByKey.values.toList()
        ..sort((a, b) => a.order.compareTo(b.order));
      if (finalRows.isNotEmpty) {
        _queryCache[normalizedKey] = finalRows;
      }

      state = state.copyWith(
        isSearching: false,
        rows: finalRows,
      );
    } catch (e) {
      if (gen != _generation || token.isCancelled) return;
      state = state.copyWith(
        isSearching: false,
        errorMessage: e.toString(),
      );
    }
  }

  void _warmRowPosters(List<MetaModel> metas) {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    for (final m in metas.take(6)) {
      final raw = m.poster ?? m.posterFallback;
      if (raw == null || raw.isEmpty) continue;
      final url = tmdbSized(raw, forWidthPx: 300);
      if (url.isEmpty || !_warmedUrls.add(url)) continue;
      try {
        unawaited(
          PixelImageCache.instance.getSingleFile(url).then<void>((_) {}, onError: (_) {}),
        );
      } catch (_) {}
    }
  }

  /// Formats an addon search catalog's row heading in the Figma `Source · Kind` style.
  static String formatAddonSearchTitle(String addonName, CatalogItemModel catalog) {
    final kind = catalog.type == 'series'
        ? 'Series'
        : catalog.type == 'movie'
            ? 'Movies'
            : catalog.type;
    final cleanAddon = addonName.trim().isNotEmpty ? addonName.trim() : 'Addon';
    final trimmedName = catalog.name.trim();
    final isGeneric = trimmedName.isEmpty ||
        trimmedName.toLowerCase() == 'results' ||
        trimmedName.toLowerCase() == 'search' ||
        trimmedName.toLowerCase() == cleanAddon.toLowerCase();
    if (isGeneric) {
      return '$cleanAddon · $kind';
    }
    return '$cleanAddon ($trimmedName) · $kind';
  }
}

final searchControllerProvider =
    NotifierProvider<SearchController, SearchState>(SearchController.new);
