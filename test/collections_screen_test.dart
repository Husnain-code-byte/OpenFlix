import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pixel/core/theme/app_theme.dart';
import 'package:pixel/core/utils/responsive.dart';
import 'package:pixel/features/anime/data/anilist_addon_repository.dart';
import 'package:pixel/features/anime/data/anime_id_map.dart';
import 'package:pixel/features/anime/data/anime_resolver.dart';
import 'package:pixel/features/collections/data/collection_catalog_resolver.dart';
import 'package:pixel/features/collections/data/collection_models.dart';
import 'package:pixel/features/collections/presentation/controllers/collections_controller.dart';
import 'package:pixel/features/collections/presentation/screens/collection_details_screen.dart';
import 'package:pixel/features/collections/presentation/screens/collections_screen.dart';
import 'package:pixel/features/collections/presentation/widgets/collection_row.dart';
import 'package:pixel/features/collections/presentation/widgets/collections_hero_banner.dart';
import 'package:pixel/features/details/data/tmdb_repository.dart';
import 'package:pixel/features/details/presentation/screens/detail_screen.dart';
import 'package:pixel/features/home/data/models/manifest_model.dart';
import 'package:pixel/features/home/data/models/meta_model.dart';
import 'package:pixel/features/home/presentation/widgets/poster_card.dart';
import 'package:pixel/features/home/presentation/widgets/poster_row.dart';

class _StubCollectionsController extends CollectionsController {
  _StubCollectionsController(this._initialState);

  final CollectionsState _initialState;

  @override
  CollectionsState build() => _initialState;

  @override
  Future<void> load({bool isRefresh = false}) async {
    state = _initialState;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  group('Premade collections data', () {
    test(
        'assets/premade_collections.json parses all 20 collections and filters default 3',
        () async {
      final raw =
          await rootBundle.loadString('assets/premade_collections.json');
      final collections = PremadeCollectionModel.listFromJsonString(raw);

      expect(collections, hasLength(20));
      expect(collections.first.title, 'Streaming');
      expect(collections.first.folders, isNotEmpty);

      final defaultCols =
          PremadeCollectionModel.defaultCollectionsFromAll(collections);
      expect(
        defaultCols.map((c) => c.title).toList(),
        ['Streaming', 'Genres', 'Studios', 'Film Collections'],
      );

      final netflix = collections.first.folders.first;
      expect(netflix.title, 'Netflix');
      expect(netflix.focusGifEnabled, isTrue);
      expect(netflix.focusGifUrl, isNotNull);
      expect(netflix.coverImageUrl, isNotNull);
      expect(
        netflix.artworkUrls,
        [netflix.focusGifUrl, netflix.coverImageUrl],
      );

      final genres = collections.firstWhere((c) => c.title == 'Genres');
      final action = genres.folders.first;
      expect(action.focusGifEnabled, isFalse);
      expect(action.artworkUrls, [action.coverImageUrl]);
    });

    test(
        'kDefaultCollectionHeroItems contains the 5 required OTT GIFs in order',
        () {
      expect(kDefaultCollectionHeroItems, hasLength(5));
      expect(
        kDefaultCollectionHeroItems.map((e) => e.title).toList(),
        ['Netflix', 'Disney+', 'Prime Video', 'HBO Max', 'Hulu'],
      );
      expect(
        kDefaultCollectionHeroItems.map((e) => e.gifUrl).toList(),
        [
          'https://cdn.jsdelivr.net/gh/luckynumb3rs/stremio-perfect-setup/collections/streaming/focused/netflix.webp',
          'https://64.media.tumblr.com/ca6dc6d4e8a260c0c5f40c47c7334e57/eb71329b4dc482d5-50/s500x750/e9e82c5bca839be289f3d87863141ebf6d7fca28.gifv',
          'https://cdn.jsdelivr.net/gh/luckynumb3rs/stremio-perfect-setup/collections/streaming/focused/prime-video.webp',
          'https://64.media.tumblr.com/cca7a86d443a0bc88536a2ad6ce72aec/b495f88d5c1df470-a2/s640x960/4cb9b614191d17d02c946b4ca59548cd333c06fd.gifv',
          'https://cdn.jsdelivr.net/gh/luckynumb3rs/stremio-perfect-setup/collections/streaming/focused/hulu.webp',
        ],
      );
    });
  });

  group('CollectionsHeroBanner', () {
    testWidgets(
        'renders 371x189 card with 11px inset on reference viewport, crossfades without PageView, and ignores taps',
        (tester) async {
      const refSize =
          Size(Responsive.referenceWidth, Responsive.referenceHeight);
      await tester.binding.setSurfaceSize(refSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const items = [
        CollectionHeroItem(
          id: 'netflix',
          title: 'Netflix',
          gifUrl: '',
          tmdbWatchProviderId: 8,
          duration: Duration(milliseconds: 250),
        ),
        CollectionHeroItem(
          id: 'disney_plus',
          title: 'Disney+',
          gifUrl: '',
          tmdbWatchProviderId: 337,
          duration: Duration(seconds: 5),
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: CollectionsHeroBanner(items: items),
            ),
          ),
        ),
      );

      final cardFinder = find.byKey(const ValueKey('collections_hero_card'));
      final rect = tester.getRect(cardFinder);
      expect(rect.left, closeTo(11.0, 0.01));
      expect(rect.width, closeTo(refSize.width - 22.0, 0.01));
      expect(rect.height, closeTo(189.0, 0.01));
      expect(AppDimens.collectionsHeroRadius, closeTo(10.0, 0.01));
      expect(find.byType(AnimatedSwitcher), findsOneWidget);
      expect(find.byType(PageView), findsNothing);

      final container = tester.widget<Container>(cardFinder);
      final decoration = container.decoration as BoxDecoration;
      expect(
        decoration.borderRadius,
        BorderRadius.circular(AppDimens.collectionsHeroRadius),
      );

      expect(find.text('Netflix'), findsOneWidget);
      await tester.tap(cardFinder, warnIfMissed: false);
      await tester.pump();
      expect(find.byType(SnackBar), findsNothing);
      expect(find.text('Netflix'), findsOneWidget);

      // Wait for slide 0 duration + 520ms crossfade transition to slide 1.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 600));

      expect(find.text('Disney+'), findsOneWidget);
      expect(find.text('Netflix'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('CollectionRow', () {
    final collection = PremadeCollectionModel(
      id: 'col-1',
      title: 'Streaming',
      folders: List.generate(
        6,
        (i) => CollectionFolderModel(
          id: 'f-$i',
          title: 'Service $i',
        ),
      ),
    );

    for (final width in [360.0, 390.0, 412.0, Responsive.referenceWidth, 430.0]) {
      testWidgets(
          'landscape collection cards scale proportionally (192x112 at reference) at ${width.toStringAsFixed(1)} dp',
          (tester) async {
        await tester.binding.setSurfaceSize(Size(width, Responsive.referenceHeight));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        CollectionFolderModel? tappedFolder;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: CollectionRow(
                  collection: collection,
                  onTapFolder: (_, folder) => tappedFolder = folder,
                ),
              ),
            ),
          ),
        );

        final headingRect = tester.getRect(find.text('Streaming'));
        final cards = find.byType(CollectionFolderCard);
        final first = tester.getRect(cards.at(0));
        final second = tester.getRect(cards.at(1));

        expect(first.width, closeTo(AppDimens.collectionCardWidth, 0.01));
        expect(first.height, closeTo(AppDimens.collectionCardHeight, 0.01));
        expect(second.width, closeTo(AppDimens.collectionCardWidth, 0.01));
        expect(second.height, closeTo(AppDimens.collectionCardHeight, 0.01));
        expect(headingRect.left, closeTo(AppDimens.collectionsScreenPadding, 0.01));
        expect(first.left, closeTo(AppDimens.collectionsScreenPadding, 0.01));
        expect(first.top - headingRect.bottom, closeTo(AppDimens.rowGap, 0.01));
        expect(second.left - first.right, closeTo(AppDimens.posterGap, 0.01));

        await tester.tap(cards.at(0));
        expect(tappedFolder?.id, 'f-0');
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('CollectionsScreen', () {
    testWidgets(
        'matches Figma 151:21 layout (MainHeader -> 371x189 hero -> Streaming, Genres, Studios rows)',
        (tester) async {
      const refSize =
          Size(Responsive.referenceWidth, Responsive.referenceHeight);
      await tester.binding.setSurfaceSize(refSize);
      addTearDown(() => tester.binding.setSurfaceSize(null));

      const heroItems = [
        CollectionHeroItem(
          id: 'netflix',
          title: 'Netflix',
          gifUrl: '',
          tmdbWatchProviderId: 8,
          duration: Duration(seconds: 5),
        ),
      ];
      final collections = [
        const PremadeCollectionModel(
          id: '76d1a5f9-04ae-49cd-9a6f-4d8edfa50765',
          title: 'Streaming',
          folders: [
            CollectionFolderModel(id: 'f1', title: 'Netflix'),
            CollectionFolderModel(id: 'f2', title: 'Disney+'),
          ],
        ),
        const PremadeCollectionModel(
          id: 'a0957a26-d26d-40c6-bce9-c3b21e4e8e58',
          title: 'Genres',
          folders: [
            CollectionFolderModel(id: 'f3', title: 'Action'),
          ],
        ),
        const PremadeCollectionModel(
          id: '26de10b2-0b10-4237-8a6f-531a9b923e67',
          title: 'Studios',
          folders: [
            CollectionFolderModel(id: 'f4', title: 'Marvel'),
          ],
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            collectionsControllerProvider.overrideWith(
              () => _StubCollectionsController(
                CollectionsReady(
                  heroItems: heroItems,
                  collections: collections,
                ),
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const MediaQuery(
              data: MediaQueryData(
                size: refSize,
                padding: EdgeInsets.only(top: 28, bottom: 34),
              ),
              child: Scaffold(body: CollectionsScreen()),
            ),
          ),
        ),
      );

      final headerFinder = find.text('Collections');
      final heroCardRect =
          tester.getRect(find.byKey(const ValueKey('collections_hero_card')));
      final firstRowRect = tester.getRect(find.byType(CollectionRow).at(0));
      final firstHeadingRect = tester.getRect(find.text('Streaming'));
      final firstCardRect =
          tester.getRect(find.byType(CollectionFolderCard).first);
      final secondRowRect = tester.getRect(find.byType(CollectionRow).at(1));
      final thirdRowRect = tester.getRect(find.byType(CollectionRow).at(2));

      expect(headerFinder, findsOneWidget);
      expect(heroCardRect.left, closeTo(11.0, 0.01));
      expect(heroCardRect.top, closeTo(92.0, 0.01));
      expect(heroCardRect.width, closeTo(refSize.width - 22.0, 0.01));
      expect(heroCardRect.height, closeTo(189.0, 0.01));
      expect(firstHeadingRect.left, closeTo(11.0, 0.01));
      expect(firstCardRect.left, closeTo(11.0, 0.01));
      expect(firstRowRect.top, closeTo(298.0, 0.01));
      expect(
        secondRowRect.top - firstRowRect.bottom,
        closeTo(AppDimens.collectionsRowSpacing, 0.01),
      );
      expect(
        thirdRowRect.top - secondRowRect.bottom,
        closeTo(AppDimens.collectionsRowSpacing, 0.01),
      );
      expect(find.text('Streaming'), findsOneWidget);
      expect(find.text('Genres'), findsOneWidget);
      expect(find.text('Studios'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders skeleton loading state', (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            collectionsControllerProvider.overrideWith(
              () => _StubCollectionsController(const CollectionsLoading()),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(body: CollectionsScreen()),
          ),
        ),
      );
      expect(find.byType(CollectionsSkeleton), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders error state with Retry action', (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            collectionsControllerProvider.overrideWith(
              () => _StubCollectionsController(
                const CollectionsError('Asset read failed'),
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(body: CollectionsScreen()),
          ),
        ),
      );
      expect(find.text("Couldn't load collections"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders empty state with Reload action', (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            collectionsControllerProvider.overrideWith(
              () => _StubCollectionsController(
                const CollectionsReady(
                  heroItems: kDefaultCollectionHeroItems,
                  collections: [],
                ),
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(body: CollectionsScreen()),
          ),
        ),
      );
      expect(find.text('No collections available'), findsOneWidget);
      expect(find.text('Reload'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('CollectionCatalogResolver', () {
    test('appends TMDB movie & series genre rows (pruneIfUnder20: true) to Streaming OTTs', () {
      const streamingCollection = PremadeCollectionModel(
        id: '76d1a5f9-04ae-49cd-9a6f-4d8edfa50765',
        title: 'Streaming',
        folders: [],
      );
      const netflixFolder = CollectionFolderModel(
        id: 'f-netflix',
        title: 'Netflix',
        sources: [
          CollectionCatalogSource(
            type: 'movie',
            catalogId: 'streaming_netflix_movies',
            addonId: 'org.themoviedb.v3',
            provider: 'tmdb',
          ),
          CollectionCatalogSource(
            type: 'series',
            catalogId: 'streaming_netflix_shows',
            addonId: 'org.themoviedb.v3',
            provider: 'tmdb',
          ),
        ],
      );

      final resolved = CollectionCatalogResolver.buildRowsForFolder(
        collection: streamingCollection,
        folder: netflixFolder,
        now: DateTime(2026, 11, 14),
      );

      expect(resolved.movieRows.length, greaterThan(1));
      expect(resolved.seriesRows.length, greaterThan(1));

      for (final genre in TmdbRepository.defaultMovieGenres) {
        final matching = resolved.movieRows
            .where((r) => r.title == genre.name && r.pruneIfUnder20)
            .toList();
        expect(matching, hasLength(1), reason: 'Missing OTT movie genre ${genre.name}');
      }

      for (final genre in TmdbRepository.defaultSeriesGenres) {
        final matching = resolved.seriesRows
            .where((r) => r.title == genre.name && r.pruneIfUnder20)
            .toList();
        expect(matching, hasLength(1), reason: 'Missing OTT series genre ${genre.name}');
      }
    });

    test('resolves Crunchyroll to AniList Anime Movie catalogs and Anime Series catalogs', () {
      const streamingCollection = PremadeCollectionModel(
        id: '76d1a5f9-04ae-49cd-9a6f-4d8edfa50765',
        title: 'Streaming',
        folders: [],
      );
      const crunchyrollFolder = CollectionFolderModel(
        id: 'f-crunchyroll',
        title: 'Crunchyroll',
        sources: [
          CollectionCatalogSource(
            type: 'movie',
            catalogId: 'streaming_crunchyroll_movies',
            addonId: 'org.themoviedb.v3',
            provider: 'tmdb',
          ),
          CollectionCatalogSource(
            type: 'series',
            catalogId: 'streaming_crunchyroll_shows',
            addonId: 'org.themoviedb.v3',
            provider: 'tmdb',
          ),
        ],
      );

      final resolved = CollectionCatalogResolver.buildRowsForFolder(
        collection: streamingCollection,
        folder: crunchyrollFolder,
        now: DateTime(2026, 11, 14),
      );

      expect(resolved.movieRows.every((r) => r.isAniList), isTrue);
      expect(resolved.seriesRows.every((r) => r.isAniList), isTrue);
      expect(
        resolved.movieRows.map((r) => r.catalogId),
        containsAll([
          'anilist.movie.popular',
          'anilist.movie.top_rated',
          'anilist.movie.latest',
        ]),
      );
      expect(
        resolved.seriesRows.map((r) => r.catalogId),
        containsAll(['anilist.popular', 'anilist.airing', 'anilist.upcoming']),
      );
      expect(
        resolved.seriesRows.any((r) => r.catalogId.startsWith('anilist.genre.')),
        isTrue,
      );
    });

    test('resolves single-row collections such as Studio Ghibli to 1 movie row', () {
      const studiosCollection = PremadeCollectionModel(
        id: 'c-studios',
        title: 'Studios',
        folders: [],
      );
      const ghibliFolder = CollectionFolderModel(
        id: 'f-ghibli',
        title: 'Studio Ghibli',
        sources: [
          CollectionCatalogSource(
            type: 'movie',
            catalogId: 'studio_ghibli',
            addonId: 'org.themoviedb.v3',
            provider: 'tmdb',
          ),
        ],
      );

      final resolved = CollectionCatalogResolver.buildRowsForFolder(
        collection: studiosCollection,
        folder: ghibliFolder,
      );

      expect(resolved.movieRows, hasLength(1));
      expect(resolved.seriesRows, isEmpty);
    });

    test('resolves signed-in user TMDB custom list folders to /list/{id}', () {
      const userListCollection = PremadeCollectionModel(
        id: 'tmdb_user_custom_lists',
        title: 'My TMDB Lists',
        folders: [],
      );
      const userFolder = CollectionFolderModel(
        id: 'tmdb_user_list_82910',
        title: 'Sci-Fi Favorites',
        sources: [
          CollectionCatalogSource(
            type: 'movie',
            catalogId: 'tmdb_user_list_82910',
            addonId: 'org.themoviedb.v3',
            tmdbId: 82910,
            provider: 'tmdb',
          ),
        ],
      );

      final resolved = CollectionCatalogResolver.buildRowsForFolder(
        collection: userListCollection,
        folder: userFolder,
      );

      expect(resolved.movieRows, hasLength(1));
      expect(resolved.movieRows.single.endpoint, '/list/82910');
      expect(resolved.seriesRows, isEmpty);
    });
  });

  group('TmdbRepository.fetchCollectionCatalog', () {
    test('prunes rows with fewer than 20 items when pruneIfUnder20 is true', () async {
      final tempDir = await Directory.systemTemp.createTemp('openflix_col_prune_');
      addTearDown(() => tempDir.delete(recursive: true));
      final repo = TmdbRepository(
        _FakeCollectionTmdbDio(sparseGenres: const {'99'}),
        interactionsFileOverride: File('${tempDir.path}/interactions.json'),
      );

      final pruned = await repo.fetchCollectionCatalog(
        catalogKey: 'netflix|movie|genre_99',
        type: 'movie',
        rowTitle: 'Documentary',
        endpoint: '/discover/movie',
        queryParameters: const {'with_watch_providers': '8', 'with_genres': '99'},
        pruneIfUnder20: true,
        now: DateTime(2026, 11, 14),
      );
      expect(pruned, isEmpty);

      final kept = await repo.fetchCollectionCatalog(
        catalogKey: 'netflix|movie|genre_28',
        type: 'movie',
        rowTitle: 'Action',
        endpoint: '/discover/movie',
        queryParameters: const {'with_watch_providers': '8', 'with_genres': '28'},
        pruneIfUnder20: true,
        now: DateTime(2026, 11, 14),
      );
      expect(kept, hasLength(20));
    });

    test('sorts strictly by popularity descending and shuffles cohort daily', () async {
      final tempDir = await Directory.systemTemp.createTemp('openflix_col_shuffle_');
      addTearDown(() => tempDir.delete(recursive: true));
      final dio = _FakeCollectionTmdbDio();
      final repo = TmdbRepository(
        dio,
        interactionsFileOverride: File('${tempDir.path}/interactions.json'),
      );

      final day1 = await repo.fetchCollectionCatalog(
        catalogKey: 'netflix|movie|popular',
        type: 'movie',
        rowTitle: 'Popular on Netflix',
        endpoint: '/discover/movie',
        queryParameters: const {'with_watch_providers': '8'},
        now: DateTime(2026, 11, 14),
      );
      final day2 = await repo.fetchCollectionCatalog(
        catalogKey: 'netflix|movie|popular',
        type: 'movie',
        rowTitle: 'Popular on Netflix',
        endpoint: '/discover/movie',
        queryParameters: const {'with_watch_providers': '8'},
        now: DateTime(2026, 11, 15),
      );

      expect(day1, hasLength(20));
      expect(day2, hasLength(20));
      expect(day1.map((m) => m.id).toList(), isNot(equals(day2.map((m) => m.id).toList())));

      // Popularity weights encoded into vote_count/title order verify descending sort.
      final popsDay1 = day1.map((m) => dio.popularityById[m.id] ?? 0).toList();
      for (var i = 1; i < popsDay1.length; i++) {
        expect(popsDay1[i - 1], greaterThanOrEqualTo(popsDay1[i]));
      }
    });
  });

  group('CollectionDetailsScreen & Navigation', () {
    const streamingCollection = PremadeCollectionModel(
      id: '76d1a5f9-04ae-49cd-9a6f-4d8edfa50765',
      title: 'Streaming',
      folders: [],
    );
    const netflixFolder = CollectionFolderModel(
      id: 'f-netflix',
      title: 'Netflix',
      sources: [
        CollectionCatalogSource(
          type: 'movie',
          catalogId: 'streaming_netflix_movies',
          addonId: 'org.themoviedb.v3',
          provider: 'tmdb',
        ),
        CollectionCatalogSource(
          type: 'series',
          catalogId: 'streaming_netflix_shows',
          addonId: 'org.themoviedb.v3',
          provider: 'tmdb',
        ),
      ],
    );
    const studiosCollection = PremadeCollectionModel(
      id: 'c-studios',
      title: 'Studios',
      folders: [],
    );
    const ghibliFolder = CollectionFolderModel(
      id: 'f-ghibli',
      title: 'Studio Ghibli',
      sources: [
        CollectionCatalogSource(
          type: 'movie',
          catalogId: 'studio_ghibli',
          addonId: 'org.themoviedb.v3',
          provider: 'tmdb',
        ),
      ],
    );

    testWidgets('shows sliding Movies/TV Shows selector, prunes <20 rows, and switches tabs', (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final fakeDio = _FakeCollectionTmdbDio(
        sparseGenres: {
          '${TmdbRepository.defaultMovieGenres.firstWhere((g) => g.name == 'Action').id}',
        },
      );
      final tmdbRepo = TmdbRepository(fakeDio);
      final aniRepo = _FakeCollectionAniListRepository(dio: fakeDio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tmdbRepositoryProvider.overrideWithValue(tmdbRepo),
            aniListAddonRepositoryProvider.overrideWithValue(aniRepo),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const CollectionDetailsScreen(
              collection: streamingCollection,
              folder: netflixFolder,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Collections'), findsAtLeastNWidgets(1));
      expect(find.text('Movies'), findsOneWidget);
      expect(find.text('TV Shows'), findsOneWidget);

      // Action genre returned <20 items so its row was pruned; Popular on Netflix remains.
      expect(find.text('Popular on Netflix'), findsOneWidget);
      expect(find.text('Action'), findsNothing);
      expect(find.byType(PosterRow), findsWidgets);

      // Selected hero card preserves 371x189 geometry from Figma (`151:21`).
      final heroContainerFinder = find.ancestor(
        of: find.byType(CollectionFolderFallback),
        matching: find.byType(Container),
      );
      final heroSize = tester.getSize(heroContainerFinder.first);
      expect(
        heroSize.width,
        closeTo(393 - 2 * AppDimens.collectionsScreenPadding, 0.01),
      );
      expect(
        heroSize.height,
        closeTo(AppDimens.collectionsHeroHeight, 0.01),
      );

      // Tap TV Shows selector to switch tab and render TV shelves.
      await tester.tap(find.text('TV Shows'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Popular on Netflix'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('hides selector and renders 3-column grid when folder has only 1 row', (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final fakeDio = _FakeCollectionTmdbDio();
      final tmdbRepo = TmdbRepository(fakeDio);
      final aniRepo = _FakeCollectionAniListRepository(dio: fakeDio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tmdbRepositoryProvider.overrideWithValue(tmdbRepo),
            aniListAddonRepositoryProvider.overrideWithValue(aniRepo),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const CollectionDetailsScreen(
              collection: studiosCollection,
              folder: ghibliFolder,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      // Selector hidden because only 1 movie row and 0 series rows exist.
      expect(find.text('Movies'), findsNothing);
      expect(find.text('TV Shows'), findsNothing);

      // Row heading appears above a 3-column SliverGrid of PosterCards (not a PosterRow).
      expect(find.text('Studio Ghibli'), findsWidgets);
      expect(find.byType(PosterRow), findsNothing);
      expect(find.byType(SliverGrid), findsOneWidget);
      expect(find.byType(PosterCard), findsWidgets);

      // Tap a PosterCard -> opens DetailScreen.
      await tester.tap(find.byType(PosterCard).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));
      expect(find.byType(DetailScreen), findsOneWidget);
      // Drain DetailScreen's internal 1.5s font preload timer before FakeAsync teardown.
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping a folder card on CollectionsScreen pushes CollectionDetailsScreen', (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final fakeDio = _FakeCollectionTmdbDio();
      final tmdbRepo = TmdbRepository(fakeDio);
      final aniRepo = _FakeCollectionAniListRepository(dio: fakeDio);

      const sampleCollections = [
        PremadeCollectionModel(
          id: '76d1a5f9-04ae-49cd-9a6f-4d8edfa50765',
          title: 'Streaming',
          folders: [netflixFolder],
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            collectionsControllerProvider.overrideWith(
              () => _StubCollectionsController(
                const CollectionsReady(
                  collections: sampleCollections,
                  heroItems: kDefaultCollectionHeroItems,
                ),
              ),
            ),
            tmdbRepositoryProvider.overrideWithValue(tmdbRepo),
            aniListAddonRepositoryProvider.overrideWithValue(aniRepo),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const Scaffold(body: CollectionsScreen()),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(CollectionFolderCard).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(CollectionDetailsScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'CollectionsScreen header floats away on scroll down and returns on scroll up',
      (tester) async {
        tester.view.physicalSize = const Size(393, 852);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final tmdbDio = _FakeCollectionTmdbDio();
        final tmdbRepo = TmdbRepository(tmdbDio);
        final aniRepo = _FakeCollectionAniListRepository(dio: tmdbDio);
        const scrollableCollections = [
          PremadeCollectionModel(
            id: 'c-1',
            title: 'Streaming',
            folders: [netflixFolder],
          ),
          PremadeCollectionModel(
            id: 'c-2',
            title: 'Genres',
            folders: [netflixFolder],
          ),
          PremadeCollectionModel(
            id: 'c-3',
            title: 'Studios',
            folders: [ghibliFolder],
          ),
          PremadeCollectionModel(
            id: 'c-4',
            title: 'More',
            folders: [netflixFolder],
          ),
          PremadeCollectionModel(
            id: 'c-5',
            title: 'Featured',
            folders: [ghibliFolder],
          ),
        ];

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              collectionsControllerProvider.overrideWith(
                () => _StubCollectionsController(
                  const CollectionsReady(
                    collections: scrollableCollections,
                    heroItems: kDefaultCollectionHeroItems,
                  ),
                ),
              ),
              tmdbRepositoryProvider.overrideWithValue(tmdbRepo),
              aniListAddonRepositoryProvider.overrideWithValue(aniRepo),
            ],
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: const MediaQuery(
                data: MediaQueryData(
                  size: Size(393, 852),
                  padding: EdgeInsets.only(top: 28),
                ),
                child: Scaffold(body: CollectionsScreen()),
              ),
            ),
          ),
        );
        await tester.pump();

        final headerFinder = find.text('Collections');
        final initialTop = tester.getTopLeft(headerFinder).dy;
        expect(initialTop, greaterThanOrEqualTo(28));

        // Scroll down: floating header scrolls off top edge.
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -260));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        final hiddenAfterDown = headerFinder.evaluate().isEmpty ||
            tester.getBottomLeft(headerFinder).dy <= 0;
        expect(hiddenAfterDown, isTrue);

        // Scroll up: floating header snaps back into view.
        await tester.drag(find.byType(CustomScrollView), const Offset(0, 120));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(tester.getTopLeft(headerFinder).dy, equals(initialTop));
      },
    );

    testWidgets(
      'CollectionDetailsScreen uses Home scroll physics, row inset/spacing parity, and floating Movies/TV Shows top bar',
      (tester) async {
        tester.view.physicalSize = const Size(393, 852);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final tmdbDio = _FakeCollectionTmdbDio();
        final tmdbRepo = TmdbRepository(tmdbDio);
        final aniRepo = _FakeCollectionAniListRepository(dio: tmdbDio);

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              tmdbRepositoryProvider.overrideWithValue(tmdbRepo),
              aniListAddonRepositoryProvider.overrideWithValue(aniRepo),
            ],
            child: MaterialApp(
              theme: AppTheme.dark(),
              home: const MediaQuery(
                data: MediaQueryData(
                  size: Size(393, 852),
                  padding: EdgeInsets.only(top: 28),
                ),
                child: CollectionDetailsScreen(
                  collection: streamingCollection,
                  folder: netflixFolder,
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        await tester.pump(const Duration(milliseconds: 250));

        final scrollView = tester.widget<CustomScrollView>(
          find.byType(CustomScrollView),
        );
        expect(scrollView.physics, isA<AlwaysScrollableScrollPhysics>());
        expect(scrollView.physics?.parent, isNull);

        final topBarTitle = find.descendant(
          of: find.byType(SliverAppBar),
          matching: find.text('Collections'),
        );
        expect(topBarTitle, findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(SliverAppBar),
            matching: find.text('Movies'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(SliverAppBar),
            matching: find.text('TV Shows'),
          ),
          findsOneWidget,
        );

        final firstPosterRow = tester.widget<PosterRow>(
          find.byType(PosterRow).first,
        );
        expect(firstPosterRow.inset, AppDimens.screenPadding);

        final headerInitialTop = tester.getTopLeft(topBarTitle).dy;
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -320));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        final hiddenAfterDown = topBarTitle.evaluate().isEmpty ||
            tester.getBottomLeft(topBarTitle).dy <= 0;
        expect(hiddenAfterDown, isTrue);

        await tester.drag(find.byType(CustomScrollView), const Offset(0, 140));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        expect(tester.getTopLeft(topBarTitle).dy, equals(headerInitialTop));
      },
    );
  });
}

class _FakeCollectionTmdbDio implements Dio {
  _FakeCollectionTmdbDio({this.sparseGenres = const {}});

  final Set<String> sparseGenres;
  final Map<String, double> popularityById = {};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<Response<T>> get<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    final uriPath = Uri.parse(path).path;

    if (uriPath.endsWith('/external_ids')) {
      final parts = uriPath.split('/');
      final tmdbId = parts.length >= 2 ? parts[parts.length - 2] : '100';
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {'imdb_id': 'tt00$tmdbId'} as T,
      );
    }

    if (uriPath.endsWith('/discover/movie') || uriPath.endsWith('/discover/tv')) {
      final isTv = uriPath.endsWith('/discover/tv');
      final genre = queryParameters?['with_genres']?.toString() ?? '';
      final page = int.tryParse('${queryParameters?['page'] ?? 1}') ?? 1;

      if (sparseGenres.contains(genre)) {
        final sparseItems = page == 1
            ? List.generate(8, (i) {
                final id = 9000 + i;
                popularityById['tt00$id'] = 100.0 - i;
                popularityById['$id'] = 100.0 - i;
                return {
                  'id': id,
                  if (isTv) 'name': 'Sparse Show $i' else 'title': 'Sparse Movie $i',
                  'poster_path': '/sparse_$id.jpg',
                  'backdrop_path': '/sparse_bg_$id.jpg',
                  'popularity': 100.0 - i,
                  'vote_average': 7.5,
                  'genre_ids': [int.tryParse(genre) ?? 99],
                  if (isTv) 'first_air_date': '2025-01-01' else 'release_date': '2025-01-01',
                };
              })
            : const <Map<String, dynamic>>[];
        return Response<T>(
          requestOptions: RequestOptions(path: path),
          statusCode: 200,
          data: {'results': sparseItems} as T,
        );
      }

      // Return 14 unique items per page so combined pool reaches 42 (> 20)
      // for daily shuffle and popularity sorting assertions.
      final results = List.generate(14, (i) {
        final baseId = (isTv ? 5000 : 1000) + ((page - 1) * 20) + i;
        final pop = 1000.0 - (((page - 1) * 14 + i) * 11.5);
        popularityById['tt00$baseId'] = pop;
        popularityById['$baseId'] = pop;
        return {
          'id': baseId,
          if (isTv) 'name': 'Series $baseId' else 'title': 'Movie $baseId',
          'poster_path': '/p_$baseId.jpg',
          'backdrop_path': '/b_$baseId.jpg',
          'popularity': pop,
          'vote_average': 7.9,
          'genre_ids': [28],
          if (isTv) 'first_air_date': '2025-01-01' else 'release_date': '2025-01-01',
        };
      });

      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {'results': results} as T,
      );
    }

    if (uriPath.startsWith('/movie/') || uriPath.startsWith('/tv/')) {
      final isTv = uriPath.startsWith('/tv/');
      final rawId = uriPath.split('/').last;
      final numId = int.tryParse(rawId) ?? 1000;
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'id': numId,
          if (isTv) 'name': 'Sample Series $numId' else 'title': 'Sample Movie $numId',
          'overview': 'Sample overview',
          'poster_path': '/p_$numId.jpg',
          'backdrop_path': '/b_$numId.jpg',
          'vote_average': 8.0,
          'genres': [
            {'id': 28, 'name': 'Action'},
          ],
          'credits': {'cast': const [], 'crew': const []},
          'videos': {'results': const []},
          'similar': {'results': const []},
          'recommendations': {'results': const []},
        } as T,
      );
    }

    if (uriPath.startsWith('/find/')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'movie_results': [
            {
              'id': 1000,
              'title': 'Found Movie',
              'poster_path': '/p_1000.jpg',
            },
          ],
          'tv_results': const [],
        } as T,
      );
    }

    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: {'results': const []} as T,
    );
  }
}

class _FakeCollectionAniListRepository extends AniListAddonRepository {
  _FakeCollectionAniListRepository({required super.dio})
      : super(
          resolver: AnimeResolver(
            animeIdMap: AnimeIdMap()..populate(const {}, const {}),
            tmdbDio: dio,
          ),
        );

  @override
  Future<List<MetaModel>> fetchCatalog(
    CatalogItemModel catalog, {
    int skip = 0,
    CancelToken? cancelToken,
  }) async {
    return List.generate(
      20,
      (i) => MetaModel(
        id: 'anilist:${200 + i}',
        type: catalog.type,
        name: '${catalog.name} #$i',
      ),
    );
  }
}
