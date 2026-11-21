import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/perf/image_perf.dart';
import '../../../details/data/tmdb_repository.dart';
import '../../data/collection_models.dart';

sealed class CollectionsState extends Equatable {
  const CollectionsState();

  @override
  List<Object?> get props => [];
}

class CollectionsLoading extends CollectionsState {
  const CollectionsLoading();
}

class CollectionsReady extends CollectionsState {
  const CollectionsReady({
    required this.heroItems,
    required this.collections,
    this.allCollections = const [],
  });

  final List<CollectionHeroItem> heroItems;
  final List<PremadeCollectionModel> collections;
  final List<PremadeCollectionModel> allCollections;

  @override
  List<Object?> get props => [heroItems, collections, allCollections];
}

class CollectionsError extends CollectionsState {
  const CollectionsError(this.message);

  final String message;

  @override
  List<Object?> get props => [message];
}

class CollectionsController extends Notifier<CollectionsState> {
  static const String _assetPath = 'assets/premade_collections.json';
  final Set<String> _warmedUrls = {};

  @override
  CollectionsState build() {
    Future.microtask(load);
    return const CollectionsLoading();
  }

  void _warmUrl(String? url) {
    if (url == null || url.isEmpty || !_warmedUrls.add(url)) return;
    try {
      unawaited(
        PixelImageCache.instance
            .getSingleFile(url)
            .then<void>((_) {}, onError: (_) {}),
      );
    } catch (_) {
      // Ignore cache warm errors in environments without platform channels.
    }
  }

  void _warmInitialAssets(
    List<CollectionHeroItem> heroItems,
    List<PremadeCollectionModel> collections,
  ) {
    for (final hero in heroItems) {
      _warmUrl(hero.fallbackCoverUrl);
      _warmUrl(hero.gifUrl);
    }
    for (final collection in collections) {
      for (final folder in collection.folders.take(6)) {
        _warmUrl(folder.coverImageUrl);
      }
    }
  }

  Future<void> load({bool isRefresh = false}) async {
    if (!(isRefresh && state is CollectionsReady)) {
      state = const CollectionsLoading();
    }
    try {
      final rawJson = await rootBundle.loadString(_assetPath);
      final allCollections = await compute(
        PremadeCollectionModel.listFromJsonString,
        rawJson,
      );
      final defaultCollections =
          PremadeCollectionModel.defaultCollectionsFromAll(allCollections);
      List<CollectionFolderModel> userCustomFolders = const [];
      try {
        userCustomFolders = await ref
            .read(tmdbRepositoryProvider)
            .fetchUserCustomListFolders();
      } catch (_) {
        userCustomFolders = const [];
      }
      final combinedCollections = <PremadeCollectionModel>[
        if (userCustomFolders.isNotEmpty)
          PremadeCollectionModel(
            id: 'tmdb_user_custom_lists',
            title: 'My TMDB Lists',
            folders: userCustomFolders,
          ),
        ...defaultCollections,
      ];
      _warmInitialAssets(kDefaultCollectionHeroItems, combinedCollections);
      state = CollectionsReady(
        heroItems: kDefaultCollectionHeroItems,
        collections: combinedCollections,
        allCollections: allCollections,
      );
    } catch (e) {
      if (isRefresh && state is CollectionsReady) return;
      state = CollectionsError(e.toString());
    }
  }
}

final collectionsControllerProvider =
    NotifierProvider<CollectionsController, CollectionsState>(
  CollectionsController.new,
);
