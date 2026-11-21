import 'dart:async';
import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../anime/data/anilist_addon_repository.dart';
import '../../../details/data/tmdb_repository.dart';
import '../../../home/data/models/manifest_model.dart';
import '../../../home/data/models/meta_model.dart';
import '../../../home/presentation/controllers/home_controller.dart';
import '../../data/collection_catalog_resolver.dart';
import '../../data/collection_models.dart';

/// Navigation and provider family arguments identifying a selected collection
/// folder inside a premade collection.
typedef CollectionDetailsArgs = ({
  PremadeCollectionModel collection,
  CollectionFolderModel folder,
});

/// Load and presentation state for a single row (or single-row grid) inside
/// [CollectionDetailsScreen].
class CollectionRowState extends Equatable {
  const CollectionRowState({
    required this.config,
    this.status = ShelfStatus.idle,
    this.items = const [],
    this.error,
  });

  final CollectionRowConfig config;
  final ShelfStatus status;
  final List<MetaModel> items;
  final String? error;

  /// Genre rows that resolve to fewer than 20 titles are pruned completely.
  bool get isPruned =>
      config.pruneIfUnder20 &&
      status == ShelfStatus.loaded &&
      items.length < 20;

  CollectionRowState copyWith({
    CollectionRowConfig? config,
    ShelfStatus? status,
    List<MetaModel>? items,
    String? error,
    bool clearError = false,
  }) {
    return CollectionRowState(
      config: config ?? this.config,
      status: status ?? this.status,
      items: items ?? this.items,
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  List<Object?> get props => [config, status, items, error];
}

/// Complete state for [CollectionDetailsController].
class CollectionDetailsState extends Equatable {
  const CollectionDetailsState({
    required this.selectedTab,
    required this.movieRowConfigs,
    required this.seriesRowConfigs,
    required this.rows,
  });

  final CollectionMediaTab selectedTab;
  final List<CollectionRowConfig> movieRowConfigs;
  final List<CollectionRowConfig> seriesRowConfigs;
  final Map<String, CollectionRowState> rows;

  List<CollectionRowState> _visibleFor(List<CollectionRowConfig> configs) {
    final result = <CollectionRowState>[];
    for (final c in configs) {
      final row = rows[c.key] ?? CollectionRowState(config: c);
      if (!row.isPruned) {
        result.add(row);
      }
    }
    return result;
  }

  /// Movie rows that are idle, loading, errored, or have at least 20 items
  /// (when prunable) / any items (when non-prunable).
  List<CollectionRowState> get visibleMovieRows => _visibleFor(movieRowConfigs);

  /// TV Series rows filtered with the same pruning rules.
  List<CollectionRowState> get visibleSeriesRows =>
      _visibleFor(seriesRowConfigs);

  /// Rows belonging to the currently active media tab.
  List<CollectionRowState> get activeRows =>
      selectedTab == CollectionMediaTab.tvShows
          ? visibleSeriesRows
          : visibleMovieRows;

  /// Selector appears ONLY when multiple rows exist AND both Movies and TV
  /// Shows rows are available.
  bool get showMediaTypeSelector =>
      visibleMovieRows.isNotEmpty &&
      visibleSeriesRows.isNotEmpty &&
      (visibleMovieRows.length + visibleSeriesRows.length > 1);

  /// When the active view resolves to a single row, render it as a 3-column
  /// poster grid underneath its section heading instead of a horizontal shelf.
  bool get isSingleRowGridMode => activeRows.length == 1;

  CollectionDetailsState copyWith({
    CollectionMediaTab? selectedTab,
    List<CollectionRowConfig>? movieRowConfigs,
    List<CollectionRowConfig>? seriesRowConfigs,
    Map<String, CollectionRowState>? rows,
  }) {
    return CollectionDetailsState(
      selectedTab: selectedTab ?? this.selectedTab,
      movieRowConfigs: movieRowConfigs ?? this.movieRowConfigs,
      seriesRowConfigs: seriesRowConfigs ?? this.seriesRowConfigs,
      rows: rows ?? this.rows,
    );
  }

  @override
  List<Object?> get props => [
        selectedTab,
        movieRowConfigs,
        seriesRowConfigs,
        rows,
      ];
}

/// Manages Movie / TV Show tab switching, bounded concurrent fetching, `< 20`
/// genre row pruning, Wave-2 IMDb poster upgrades, and refresh for a selected
/// collection folder.
class CollectionDetailsController
    extends AutoDisposeFamilyNotifier<CollectionDetailsState, CollectionDetailsArgs> {
  static const int _initialActivePrefetchCount = 6;
  static const int _inactiveProbeLimit = 3;
  static const int _maxConcurrentLoads = 4;

  CancelToken _cancelToken = CancelToken();
  Timer? _midnightTimer;
  final ListQueue<String> _pendingQueue = ListQueue<String>();
  final Set<String> _queuedKeys = <String>{};
  int _inFlightCount = 0;
  bool _disposed = false;
  String _loadedDayKey = _currentDayKey();

  static String _currentDayKey() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  void _scheduleMidnightRefresh() {
    _midnightTimer?.cancel();
    if (_disposed) return;
    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1, 0, 0, 1);
    final wait = nextMidnight.difference(now);
    final clampedWait = wait.isNegative
        ? const Duration(milliseconds: 250)
        : (wait > const Duration(hours: 6) ? const Duration(hours: 6) : wait);
    _midnightTimer = Timer(clampedWait, () {
      if (_disposed) return;
      if (_currentDayKey() != _loadedDayKey) {
        refreshIfDayChanged().ignore();
      } else {
        _scheduleMidnightRefresh();
      }
    });
  }

  Future<void> refreshIfDayChanged() async {
    if (_disposed) return;
    final today = _currentDayKey();
    if (today == _loadedDayKey) {
      _scheduleMidnightRefresh();
      return;
    }
    await refresh();
  }

  @override
  CollectionDetailsState build(CollectionDetailsArgs arg) {
    _disposed = false;
    _cancelToken = CancelToken();
    _pendingQueue.clear();
    _queuedKeys.clear();
    _inFlightCount = 0;
    _loadedDayKey = _currentDayKey();

    ref.onDispose(() {
      _disposed = true;
      _midnightTimer?.cancel();
      _pendingQueue.clear();
      _queuedKeys.clear();
      if (!_cancelToken.isCancelled) {
        _cancelToken.cancel('CollectionDetailsController disposed');
      }
    });

    final resolved = CollectionCatalogResolver.buildRowsForFolder(
      collection: arg.collection,
      folder: arg.folder,
    );

    final initialRows = <String, CollectionRowState>{
      for (final c in resolved.movieRows) c.key: CollectionRowState(config: c),
      for (final c in resolved.seriesRows) c.key: CollectionRowState(config: c),
    };

    // Movies is selected by default whenever movie rows are available.
    final initialTab = resolved.movieRows.isNotEmpty
        ? CollectionMediaTab.movies
        : CollectionMediaTab.tvShows;

    Future<void>.microtask(() {
      if (_disposed) return;
      _scheduleMidnightRefresh();
      _enqueueInitialLoads(
        movieRows: resolved.movieRows,
        seriesRows: resolved.seriesRows,
        activeTab: initialTab,
      );
    });

    return CollectionDetailsState(
      selectedTab: initialTab,
      movieRowConfigs: resolved.movieRows,
      seriesRowConfigs: resolved.seriesRows,
      rows: initialRows,
    );
  }

  void _enqueueInitialLoads({
    required List<CollectionRowConfig> movieRows,
    required List<CollectionRowConfig> seriesRows,
    required CollectionMediaTab activeTab,
  }) {
    final activeConfigs =
        activeTab == CollectionMediaTab.tvShows ? seriesRows : movieRows;
    final inactiveConfigs =
        activeTab == CollectionMediaTab.tvShows ? movieRows : seriesRows;

    final initialActive = activeConfigs.take(_initialActivePrefetchCount);
    for (final c in initialActive) {
      _enqueueRow(c.key);
    }

    // If the inactive tab has only prunable rows, probe a small batch in the
    // background so the Movies/TV Shows selector hides if every row prunes.
    if (inactiveConfigs.isNotEmpty &&
        inactiveConfigs.every((c) => c.pruneIfUnder20)) {
      for (final c in inactiveConfigs.take(_inactiveProbeLimit)) {
        _enqueueRow(c.key);
      }
    }
  }

  /// Switches between Movies and TV Shows when the target tab has available rows.
  void selectTab(CollectionMediaTab tab) {
    if (state.selectedTab == tab) return;
    if (tab == CollectionMediaTab.movies && state.visibleMovieRows.isEmpty) {
      return;
    }
    if (tab == CollectionMediaTab.tvShows && state.visibleSeriesRows.isEmpty) {
      return;
    }

    state = state.copyWith(selectedTab: tab);

    final activeConfigs = tab == CollectionMediaTab.tvShows
        ? state.seriesRowConfigs
        : state.movieRowConfigs;
    var enqueued = 0;
    for (final c in activeConfigs) {
      final row = state.rows[c.key];
      if (row == null || row.isPruned) continue;
      if (row.status == ShelfStatus.idle) {
        _enqueueRow(c.key, prioritize: true);
      }
      enqueued++;
      if (enqueued >= _initialActivePrefetchCount) break;
    }
  }

  /// Requests loading for an idle row (e.g. as the user scrolls rows into view),
  /// or refreshes all shelves if the calendar day has rolled over.
  void ensureRowLoaded(String rowKey) {
    if (_disposed) return;
    if (_currentDayKey() != _loadedDayKey) {
      refreshIfDayChanged().ignore();
      return;
    }
    final row = state.rows[rowKey];
    if (row == null || row.status != ShelfStatus.idle) return;
    _enqueueRow(rowKey, prioritize: _isInActiveTab(row.config));
  }

  /// Retries a single failed row.
  void retryRow(String rowKey) {
    if (_disposed) return;
    final row = state.rows[rowKey];
    if (row == null) return;
    _updateRow(
      rowKey,
      row.copyWith(status: ShelfStatus.idle, clearError: true),
    );
    _enqueueRow(rowKey, prioritize: true);
  }

  /// Clears cached collection shelves and re-fetches visible rows cleanly.
  Future<void> refresh() async {
    if (_disposed) return;
    if (!_cancelToken.isCancelled) {
      _cancelToken.cancel('Collection details refresh');
    }
    _cancelToken = CancelToken();
    _pendingQueue.clear();
    _queuedKeys.clear();
    _inFlightCount = 0;
    _loadedDayKey = _currentDayKey();
    _scheduleMidnightRefresh();

    ref.read(aniListAddonRepositoryProvider).clearCache();
    ref.read(tmdbRepositoryProvider).clearCategoryCache();

    final resetRows = <String, CollectionRowState>{
      for (final c in state.movieRowConfigs)
        c.key: CollectionRowState(config: c),
      for (final c in state.seriesRowConfigs)
        c.key: CollectionRowState(config: c),
    };

    final validTab = state.selectedTab == CollectionMediaTab.tvShows &&
            state.seriesRowConfigs.isNotEmpty
        ? CollectionMediaTab.tvShows
        : (state.movieRowConfigs.isNotEmpty
            ? CollectionMediaTab.movies
            : CollectionMediaTab.tvShows);

    state = state.copyWith(selectedTab: validTab, rows: resetRows);

    _enqueueInitialLoads(
      movieRows: state.movieRowConfigs,
      seriesRows: state.seriesRowConfigs,
      activeTab: validTab,
    );
  }

  bool _isInActiveTab(CollectionRowConfig config) {
    return state.selectedTab == CollectionMediaTab.tvShows
        ? config.isSeries
        : !config.isSeries;
  }

  bool _isSingleRowForTab(CollectionRowConfig config) {
    return config.isSeries
        ? state.seriesRowConfigs.length == 1
        : state.movieRowConfigs.length == 1;
  }

  void _enqueueRow(String rowKey, {bool prioritize = false}) {
    if (_disposed || _queuedKeys.contains(rowKey)) return;
    final row = state.rows[rowKey];
    if (row == null || row.status != ShelfStatus.idle) return;
    _queuedKeys.add(rowKey);
    if (prioritize) {
      _pendingQueue.addFirst(rowKey);
    } else {
      _pendingQueue.addLast(rowKey);
    }
    _pumpQueue();
  }

  void _pumpQueue() {
    while (!_disposed &&
        _inFlightCount < _maxConcurrentLoads &&
        _pendingQueue.isNotEmpty) {
      final key = _pendingQueue.removeFirst();
      _queuedKeys.remove(key);
      final row = state.rows[key];
      if (row == null || row.status != ShelfStatus.idle) continue;
      _inFlightCount++;
      _loadRow(key).whenComplete(() {
        if (_inFlightCount > 0) _inFlightCount--;
        if (!_disposed) {
          _pumpQueue();
        }
      });
    }
  }

  Future<void> _loadRow(String key) async {
    final row = state.rows[key];
    if (row == null || _disposed) return;

    final token = _cancelToken;
    _updateRow(
      key,
      row.copyWith(status: ShelfStatus.loading, clearError: true),
    );

    final targetCount = _isSingleRowForTab(row.config) ? 24 : 20;

    try {
      final List<MetaModel> fetched;
      if (row.config.isAniList) {
        final aniRepo = ref.read(aniListAddonRepositoryProvider);
        final catalog = CatalogItemModel(
          id: row.config.catalogId,
          type: row.config.type,
          name: row.config.title,
        );
        final raw = await aniRepo.fetchCatalog(catalog, cancelToken: token);
        fetched = (row.config.pruneIfUnder20 && raw.length < 20)
            ? const <MetaModel>[]
            : raw;
      } else {
        final tmdbRepo = ref.read(tmdbRepositoryProvider);
        fetched = await tmdbRepo.fetchCollectionCatalog(
          catalogKey: row.config.key,
          type: row.config.type,
          rowTitle: row.config.title,
          endpoint: row.config.endpoint,
          queryParameters: row.config.queryParameters,
          pruneIfUnder20: row.config.pruneIfUnder20,
          targetCount: targetCount,
          cancelToken: token,
          onWave2Enriched: (enriched) {
            if (_disposed || token.isCancelled) return;
            final current = state.rows[key];
            if (current == null || current.status != ShelfStatus.loaded) return;
            _updateRow(key, current.copyWith(items: enriched));
          },
        );
      }

      if (_disposed || token.isCancelled) return;
      final current = state.rows[key];
      if (current == null) return;
      _updateRow(
        key,
        current.copyWith(
          status: ShelfStatus.loaded,
          items: fetched,
          clearError: true,
        ),
      );
      _reconcileSelectedTabIfEmpty();
    } on DioException catch (e) {
      if (CancelToken.isCancel(e) || _disposed || token.isCancelled) return;
      final current = state.rows[key];
      if (current == null) return;
      _updateRow(
        key,
        current.copyWith(
          status: ShelfStatus.error,
          error: e.message ?? e.toString(),
        ),
      );
    } catch (e) {
      if (_disposed || token.isCancelled) return;
      final current = state.rows[key];
      if (current == null) return;
      _updateRow(
        key,
        current.copyWith(
          status: ShelfStatus.error,
          error: e.toString(),
        ),
      );
    }
  }

  void _updateRow(String key, CollectionRowState updated) {
    if (_disposed) return;
    final nextRows = Map<String, CollectionRowState>.from(state.rows);
    nextRows[key] = updated;
    state = state.copyWith(rows: nextRows);
  }

  void _reconcileSelectedTabIfEmpty() {
    if (_disposed) return;
    if (state.selectedTab == CollectionMediaTab.movies &&
        state.visibleMovieRows.isEmpty &&
        state.visibleSeriesRows.isNotEmpty) {
      selectTab(CollectionMediaTab.tvShows);
    } else if (state.selectedTab == CollectionMediaTab.tvShows &&
        state.visibleSeriesRows.isEmpty &&
        state.visibleMovieRows.isNotEmpty) {
      selectTab(CollectionMediaTab.movies);
    }
  }
}

/// Family provider scoping collection details shelves per selected folder.
final collectionDetailsControllerProvider = AutoDisposeNotifierProviderFamily<
    CollectionDetailsController,
    CollectionDetailsState,
    CollectionDetailsArgs>(CollectionDetailsController.new);
