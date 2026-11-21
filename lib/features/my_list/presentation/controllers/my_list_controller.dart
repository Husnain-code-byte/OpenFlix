import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/perf/image_perf.dart';
import '../../../anime/data/anime_id_map.dart';
import '../../../details/data/tmdb_repository.dart';
import '../../../home/data/models/meta_model.dart';
import '../../../home/presentation/controllers/home_controller.dart';

class MyListState extends Equatable {
  const MyListState({
    this.isLoading = false,
    this.items = const [],
    this.animeIds = const {},
    this.errorMessage,
  });

  final bool isLoading;
  final List<MetaModel> items;
  final Set<String> animeIds;
  final String? errorMessage;

  /// Saved non-anime Movies for the first row on the My List screen.
  List<MetaModel> get movies => items
      .where((m) => m.type != 'series' && m.type != 'tv' && !animeIds.contains(m.id))
      .toList(growable: false);

  /// Saved non-anime TV Shows / Series for the second row on the My List screen.
  List<MetaModel> get tvShows => items
      .where((m) => (m.type == 'series' || m.type == 'tv') && !animeIds.contains(m.id))
      .toList(growable: false);

  /// Saved Anime titles for the third row on the My List screen (strictly separated).
  List<MetaModel> get anime =>
      items.where((m) => animeIds.contains(m.id)).toList(growable: false);

  bool get isEmpty => items.isEmpty;

  MyListState copyWith({
    bool? isLoading,
    List<MetaModel>? items,
    Set<String>? animeIds,
    String? errorMessage,
    bool clearError = false,
  }) =>
      MyListState(
        isLoading: isLoading ?? this.isLoading,
        items: items ?? this.items,
        animeIds: animeIds ?? this.animeIds,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      );

  @override
  List<Object?> get props => [isLoading, items, animeIds, errorMessage];
}

/// Shared controller logic for 3-row saved collections ("My List" and "Liked")
/// split into Movies, TV Shows, and Anime.
abstract class SavedCollectionController extends Notifier<MyListState> {
  late TmdbRepository _repo;
  late AnimeIdMap _animeIdMap;
  CancelToken? _cancelToken;
  final Set<String> _warmedUrls = {};

  TmdbRepository get repo => _repo;
  AnimeIdMap get animeIdMap => _animeIdMap;

  String get collectionLabel;
  List<MetaModel> readCachedMetas();
  bool get hasUnresolvedEntries;
  Future<List<MetaModel>> syncAndResolve({CancelToken? cancelToken});

  Set<String> _computeAnimeIds(List<MetaModel> list) => {
        for (final m in list)
          if (_repo.isMetaAnime(m, _animeIdMap)) m.id,
      };

  @override
  MyListState build() {
    _repo = ref.watch(tmdbRepositoryProvider);
    _animeIdMap = ref.watch(animeIdMapProvider);

    void onRepoChanged() {
      final latest = readCachedMetas();
      final latestAnimeIds = _computeAnimeIds(latest);
      if (latest != state.items || latestAnimeIds != state.animeIds) {
        state = state.copyWith(
          items: latest,
          animeIds: latestAnimeIds,
          isLoading: false,
          clearError: true,
        );
        _warmPosters(latest);
      }
    }

    _repo.addMyListListener(onRepoChanged);
    ref.onDispose(() {
      _repo.removeMyListListener(onRepoChanged);
      _cancelToken?.cancel('$collectionLabel controller disposed');
    });

    final initialItems = readCachedMetas();
    Future.microtask(load);
    return MyListState(
      isLoading: initialItems.isEmpty && hasUnresolvedEntries,
      items: initialItems,
      animeIds: _computeAnimeIds(initialItems),
    );
  }

  /// Loads saved items from disk and enriches any unresolved entries
  /// with their `btttr.cc` Better Poster and TMDB fallback artwork.
  Future<void> load() async {
    _cancelToken?.cancel('Superseded by new $collectionLabel load');
    final token = CancelToken();
    _cancelToken = token;

    try {
      await _repo.ensureInteractionsLoaded();
      unawaited(_animeIdMap.ensureLoaded().then((_) {
        if (!token.isCancelled) {
          final current = readCachedMetas();
          state = state.copyWith(animeIds: _computeAnimeIds(current));
        }
      }));
      if (token.isCancelled) return;

      final diskItems = readCachedMetas();
      final hasUnresolved = hasUnresolvedEntries;

      state = state.copyWith(
        items: diskItems,
        animeIds: _computeAnimeIds(diskItems),
        isLoading: diskItems.isEmpty && hasUnresolved,
        clearError: true,
      );
      _warmPosters(diskItems);

      if (_repo.isAuthenticated) {
        await _animeIdMap.ensureLoaded();
        if (token.isCancelled) return;
        await _repo.syncTmdbAccountData(
          cancelToken: token,
          animeIdMap: _animeIdMap,
          pushLocalOnly: _repo.hasPendingSyncOps,
        );
        if (token.isCancelled) return;
      }

      final resolved = await syncAndResolve(cancelToken: token);
      await _animeIdMap.ensureLoaded();
      if (token.isCancelled) return;

      state = state.copyWith(
        isLoading: false,
        items: resolved,
        animeIds: _computeAnimeIds(resolved),
        clearError: true,
      );
      _warmPosters(resolved);
    } catch (e) {
      if (token.isCancelled) return;
      state = state.copyWith(
        isLoading: false,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> refresh() => load();

  void _warmPosters(List<MetaModel> metas) {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    for (final m in metas.take(12)) {
      for (final raw in [m.poster, m.posterFallback]) {
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
  }
}

class MyListController extends SavedCollectionController {
  @override
  String get collectionLabel => 'My List';

  @override
  List<MetaModel> readCachedMetas() => repo.getCachedMyListMetas();

  @override
  bool get hasUnresolvedEntries => repo.hasUnresolvedMyListEntries;

  @override
  Future<List<MetaModel>> syncAndResolve({CancelToken? cancelToken}) =>
      repo.syncAndResolveMyList(cancelToken: cancelToken);

  /// Returns true if [meta] is currently in the user's "My List".
  bool isMetaInMyList(MetaModel meta) {
    final trimmed = meta.id.trim();
    final parsedTmdb = int.tryParse(trimmed);
    return repo.getCachedIsInMyList(
      tmdbId: parsedTmdb,
      imdbId: parsedTmdb == null ? trimmed : null,
      mediaType: meta.type,
    );
  }

  /// Toggles [meta] in "My List" and returns `true` if added, `false` if removed.
  Future<bool> toggleMeta(MetaModel meta, {bool? isAnime}) async {
    await repo.ensureInteractionsLoaded();
    await animeIdMap.ensureLoaded();
    final trimmed = meta.id.trim();
    final parsedTmdb = int.tryParse(trimmed);
    final nextInList = !isMetaInMyList(meta);
    final effectiveIsAnime = isAnime ??
        (repo.isMetaAnime(meta, animeIdMap) ||
            ref.read(homeFilterProvider) == HomeFilter.anime);
    await repo.setMyList(
      tmdbId: parsedTmdb,
      imdbId: parsedTmdb == null ? trimmed : null,
      mediaType: meta.type,
      inMyList: nextInList,
      meta: meta,
      isAnime: effectiveIsAnime,
    );
    return nextInList;
  }
}

class LikedController extends SavedCollectionController {
  @override
  String get collectionLabel => 'Liked';

  @override
  List<MetaModel> readCachedMetas() => repo.getCachedLikedMetas();

  @override
  bool get hasUnresolvedEntries => repo.hasUnresolvedLikedEntries;

  @override
  Future<List<MetaModel>> syncAndResolve({CancelToken? cancelToken}) =>
      repo.syncAndResolveLikes(cancelToken: cancelToken);
}

final myListControllerProvider =
    NotifierProvider<MyListController, MyListState>(MyListController.new);

final likedControllerProvider =
    NotifierProvider<LikedController, MyListState>(LikedController.new);
