import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pixel/core/perf/image_perf.dart';
import 'package:pixel/core/theme/app_theme.dart';
import 'package:pixel/features/anime/data/anilist_addon_repository.dart';
import 'package:pixel/features/anime/data/anime_id_map.dart';
import 'package:pixel/features/anime/data/anime_resolver.dart';
import 'package:pixel/features/details/data/tmdb_repository.dart';
import 'package:pixel/features/details/presentation/controllers/details_controller.dart';
import 'package:pixel/features/details/presentation/screens/detail_screen.dart';
import 'package:pixel/features/home/data/models/meta_model.dart';
import 'package:pixel/features/home/presentation/widgets/poster_card.dart';
import 'package:pixel/features/home/presentation/widgets/poster_row.dart';

class _FakeCollectionDetailsTmdbDio implements Dio {
  final List<String> requestedPaths = [];

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
    requestedPaths.add(uriPath);

    if (uriPath.endsWith('/find/tt1160419')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'movie_results': [
            {'id': 438631},
          ],
        } as T,
      );
    }

    if (uriPath.endsWith('/movie/438631')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'id': 438631,
          'imdb_id': 'tt1160419',
          'title': 'Dune',
          'overview': 'Paul Atreides arrives on Arrakis.',
          'release_date': '2021-09-15',
          'runtime': 155,
          'vote_average': 7.8,
          'poster_path': '/dune1.jpg',
          'belongs_to_collection': {
            'id': 726871,
            'name': 'Dune Collection',
          },
          'similar': {
            'results': [
              {
                'id': 335984,
                'title': 'Blade Runner 2049',
                'poster_path': '/br2049.jpg',
                'popularity': 90.0,
                'release_date': '2017-10-04',
                'vote_average': 7.6,
                'vote_count': 13000,
              },
            ],
          },
          'recommendations': {
            'results': [
              {
                'id': 329865,
                'title': 'Arrival',
                'poster_path': '/arrival.jpg',
                'popularity': 85.0,
                'release_date': '2016-11-10',
                'vote_average': 7.6,
                'vote_count': 17000,
              },
            ],
          },
        } as T,
      );
    }

    if (uriPath.endsWith('/movie/693134')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'id': 693134,
          'imdb_id': 'tt15239678',
          'title': 'Dune: Part Two',
          'overview': 'Paul Atreides unites with the Fremen.',
          'release_date': '2024-02-27',
          'runtime': 166,
          'vote_average': 8.2,
          'poster_path': '/dune2.jpg',
          'belongs_to_collection': {
            'id': 726871,
            'name': 'Dune Collection',
          },
          'similar': {
            'results': [
              {
                'id': 335984,
                'title': 'Blade Runner 2049',
                'poster_path': '/br2049.jpg',
                'release_date': '2017-10-04',
                'popularity': 90.0,
              },
            ],
          },
          'recommendations': {
            'results': [
              {
                'id': 329865,
                'title': 'Arrival',
                'poster_path': '/arrival.jpg',
                'release_date': '2016-11-10',
                'popularity': 85.0,
              },
            ],
          },
        } as T,
      );
    }

    if (uriPath.endsWith('/collection/726871')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'id': 726871,
          'name': 'Dune Collection',
          'parts': [
            {
              'id': 438631,
              'title': 'Dune',
              'poster_path': '/dune1.jpg',
              'popularity': 95.0,
              'release_date': '2021-09-15',
              'vote_average': 7.8,
              'vote_count': 12000,
            },
            {
              // Older / lower-rated entry with higher popularity than 777001:
              // verifies strict popularity-descending order (not qualityTier).
              'id': 693134,
              'title': 'Dune: Part Two',
              'poster_path': '/dune2.jpg',
              'popularity': 180.0,
              'release_date': '2005-01-01',
              'vote_average': 5.8,
              'vote_count': 200,
            },
            {
              'id': 777001,
              'title': 'Dune: Messiah',
              'poster_path': '/dune3.jpg',
              'popularity': 42.0,
              'release_date': '2025-12-18',
              'vote_average': 8.4,
              'vote_count': 3000,
            },
            {
              // Future release_date should be excluded until release day arrives.
              'id': 777003,
              'title': 'Dune: Future Sequel',
              'poster_path': '/dune4.jpg',
              'popularity': 250.0,
              'release_date': '2099-12-18',
            },
            {
              // Missing poster_path should be excluded cleanly.
              'id': 777002,
              'title': 'Dune: Unreleased Posterless',
              'poster_path': null,
              'popularity': 300.0,
            },
          ],
        } as T,
      );
    }

    if (uriPath.endsWith('/movie/888001')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'id': 888001,
          'imdb_id': 'tt8880001',
          'title': 'Solo Film',
          'overview': 'Not part of any franchise.',
          'poster_path': '/solo.jpg',
          'belongs_to_collection': null,
          'similar': {
            'results': [
              {
                'id': 335984,
                'title': 'Blade Runner 2049',
                'poster_path': '/br2049.jpg',
                'release_date': '2017-10-04',
                'popularity': 90.0,
              },
            ],
          },
          'recommendations': {'results': const []},
        } as T,
      );
    }

    if (uriPath.endsWith('/movie/888002')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'id': 888002,
          'imdb_id': 'tt8880002',
          'title': 'Single Entry Franchise',
          'overview': 'Only 1 released movie in its TMDB collection.',
          'poster_path': '/single.jpg',
          'belongs_to_collection': {
            'id': 990001,
            'name': 'Single Entry Collection',
          },
          'similar': {
            'results': [
              {
                'id': 335984,
                'title': 'Blade Runner 2049',
                'poster_path': '/br2049.jpg',
                'release_date': '2017-10-04',
                'popularity': 90.0,
              },
            ],
          },
          'recommendations': {'results': const []},
        } as T,
      );
    }

    if (uriPath.endsWith('/collection/990001')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'id': 990001,
          'name': 'Single Entry Collection',
          'parts': [
            {
              'id': 888002,
              'title': 'Single Entry Franchise',
              'poster_path': '/single.jpg',
              'release_date': '2024-01-01',
              'popularity': 55.0,
            },
          ],
        } as T,
      );
    }

    if (uriPath.endsWith('/collection/555111')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'id': 555111,
          'name': 'Large Wave Collection',
          'parts': [
            for (var i = 1; i <= 9; i++)
              {
                'id': 5000 + i,
                'title': 'Franchise Entry $i',
                'poster_path': '/entry_$i.jpg',
                'release_date': '2024-01-0$i',
                'popularity': (100 - i).toDouble(),
              },
          ],
        } as T,
      );
    }

    final extMatch = RegExp(r'/movie/(\d+)/external_ids$').firstMatch(uriPath);
    if (extMatch != null) {
      final id = int.parse(extMatch.group(1)!);
      final imdb = switch (id) {
        693134 => 'tt15239678',
        438631 => 'tt1160419',
        777001 => 'tt7770001',
        335984 => 'tt1856101',
        329865 => 'tt2543164',
        _ => 'tt000$id',
      };
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {'id': id, 'imdb_id': imdb} as T,
      );
    }

    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 404,
      data: <String, dynamic>{} as T,
    );
  }
}

class _FakeEmptyAniListDio implements Dio {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onSendProgress,
    ProgressCallback? onReceiveProgress,
  }) async =>
      Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: const {'data': {'Media': null}} as T,
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  ({
    TmdbRepository repo,
    _FakeCollectionDetailsTmdbDio dio,
    AniListAddonRepository aniRepo,
    AnimeIdMap idMap,
  }) createHarness() {
    final dio = _FakeCollectionDetailsTmdbDio();
    final idMap = AnimeIdMap()..populate({}, {});
    final repo = TmdbRepository(
      dio,
      animeIdMap: idMap,
    );
    final aniRepo = AniListAddonRepository(
      dio: _FakeEmptyAniListDio(),
      resolver: AnimeResolver(animeIdMap: idMap, tmdbDio: dio),
    );
    return (repo: repo, dio: dio, aniRepo: aniRepo, idMap: idMap);
  }

  group('TmdbRepository franchise collection support', () {
    test('fetches collection movies excluding current movie, sorted strictly by popularity, and reuses memoized payload', () async {
      final h = createHarness();
      final core = await h.repo.fetchCoreDetails('tt1160419');
      expect(core.tmdbId, 438631);
      expect(core.collectionId, 726871);

      final collection = await h.repo.fetchCollectionMovies(
        core.collectionId!,
        excludeTmdbId: core.tmdbId,
      );

      // Excludes 438631 (Dune) and posterless 777002; orders remaining by popularity descending.
      expect(collection.map((m) => m.id).toList(), [693134, 777001]);
      expect(collection.map((m) => m.title).toList(), [
        'Dune: Part Two',
        'Dune: Messiah',
      ]);

      final wave1Callbacks = <List<int>>[];
      final enriched = await h.repo.enrichCollectionExternalIds(
        core.collectionId!,
        excludeTmdbId: core.tmdbId,
        onWave1Complete: (items) =>
            wave1Callbacks.add(items.map((m) => m.id).toList()),
      );
      expect(enriched.map((m) => m.imdbId).toList(), ['tt15239678', 'tt7770001']);
      expect(wave1Callbacks, isEmpty);

      // Navigating to Dune: Part Two reuses the cached /collection/726871 payload
      // without firing another /collection/ request and excludes 693134 instead.
      final callsBefore = h.dio.requestedPaths
          .where((p) => p.endsWith('/collection/726871'))
          .length;
      expect(callsBefore, 1);

      final partTwoCollection = await h.repo.fetchCollectionMovies(
        726871,
        excludeTmdbId: 693134,
      );
      expect(partTwoCollection.map((m) => m.id).toList(), [438631, 777001]);
      expect(partTwoCollection.map((m) => m.imdbId).toList(), [
        'tt1160419',
        'tt7770001',
      ]);

      final callsAfter = h.dio.requestedPaths
          .where((p) => p.endsWith('/collection/726871'))
          .length;
      expect(callsAfter, 1);
    });

    test('enrichCollectionExternalIds invokes Wave 1 callback when off-screen Wave 2 items exist', () async {
      final h = createHarness();
      final items = await h.repo.fetchCollectionMovies(
        555111,
        excludeTmdbId: 5001,
      );
      expect(items.length, 8); // 5002..5009

      List<String?>? wave1ImdbIds;
      final enriched = await h.repo.enrichCollectionExternalIds(
        555111,
        excludeTmdbId: 5001,
        onWave1Complete: (wave1Items) {
          wave1ImdbIds = wave1Items.map((m) => m.imdbId).toList();
        },
      );

      expect(wave1ImdbIds, isNotNull);
      // First 6 (Wave 1) resolved during wave1 callback; remaining 2 not yet resolved.
      expect(wave1ImdbIds!.take(6).every((id) => id != null), isTrue);
      expect(wave1ImdbIds!.skip(6).every((id) => id == null), isTrue);
      // After Wave 2, all 8 items have IMDb IDs.
      expect(enriched.every((m) => m.imdbId != null), isTrue);
    });

    test('returns empty when collection only contains the currently open movie', () async {
      final h = createHarness();
      final items = await h.repo.fetchCollectionMovies(
        990001,
        excludeTmdbId: 888002,
      );
      expect(items, isEmpty);
    });
  });

  group('DetailsController franchise collection integration', () {
    test('populates collectionMetas sorted by popularity excluding open movie and skips standalone movies', () async {
      final h = createHarness();
      final container = ProviderContainer(
        overrides: [
          tmdbRepositoryProvider.overrideWithValue(h.repo),
          animeIdMapProvider.overrideWithValue(h.idMap),
          aniListAddonRepositoryProvider.overrideWithValue(h.aniRepo),
        ],
      );
      addTearDown(container.dispose);

      const key = (id: 'tt1160419', type: 'movie');
      final sub = container.listen(detailsControllerProvider(key), (_, __) {});
      addTearDown(sub.close);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      final state = container.read(detailsControllerProvider(key));
      expect(state.details?.tmdbId, 438631);
      expect(state.collectionMetas.map((m) => m.name).toList(), [
        'Dune: Part Two',
        'Dune: Messiah',
      ]);
      expect(state.collectionMetas.first.id, 'tt15239678');
      expect(
        state.collectionMetas.first.poster,
        betterPosterUrl('tt15239678'),
      );

      // Standalone movie produces empty collectionMetas and zero /collection/ calls.
      const soloKey = (id: '888001', type: 'movie');
      final soloSub = container.listen(detailsControllerProvider(soloKey), (_, __) {});
      addTearDown(soloSub.close);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final soloState = container.read(detailsControllerProvider(soloKey));
      expect(soloState.collectionMetas, isEmpty);
      expect(
        h.dio.requestedPaths.where((p) => p.contains('/collection/')),
        hasLength(1), // Only 726871 from the first test assertion
      );
    });
  });

  group('DetailScreen Collection row UI', () {
    testWidgets('shows Collection row below More Like This and Viewers Also Watched, ordered by popularity without current movie', (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final h = createHarness();
      const meta = MetaModel(
        id: 'tt1160419',
        type: 'movie',
        name: 'Dune',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tmdbRepositoryProvider.overrideWithValue(h.repo),
            animeIdMapProvider.overrideWithValue(h.idMap),
            aniListAddonRepositoryProvider.overrideWithValue(h.aniRepo),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const DetailScreen(meta: meta),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('More Like This'), findsOneWidget);
      expect(find.text('Viewers Also Watched'), findsOneWidget);
      expect(find.text('Collection'), findsOneWidget);

      final similarRect = tester.getRect(find.text('More Like This'));
      final recommendedRect = tester.getRect(find.text('Viewers Also Watched'));
      final collectionRect = tester.getRect(find.text('Collection'));
      expect(similarRect.top, lessThan(recommendedRect.top));
      expect(recommendedRect.top, lessThan(collectionRect.top));

      final collectionRowFinder = find.byWidgetPredicate(
        (w) => w is PosterRow && w.title == 'Collection',
      );
      final collectionRow = tester.widget<PosterRow>(collectionRowFinder);
      expect(collectionRow.metas.map((m) => m.name).toList(), [
        'Dune: Part Two',
        'Dune: Messiah',
      ]);
      expect(collectionRow.metas.any((m) => m.name == 'Dune'), isFalse);

      // Scroll Collection row into view and tap Dune: Part Two to open its DetailsScreen.
      final firstCollectionCard = find.descendant(
        of: collectionRowFinder,
        matching: find.byType(PosterCard),
      ).first;
      await tester.ensureVisible(firstCollectionCard);
      await tester.pump();
      await tester.tap(firstCollectionCard);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(seconds: 2));

      expect(find.byType(DetailScreen), findsOneWidget);
      final partTwoCollectionRow = tester.widget<PosterRow>(
        find.byWidgetPredicate((w) => w is PosterRow && w.title == 'Collection'),
      );
      expect(partTwoCollectionRow.metas.map((m) => m.name).toList(), [
        'Dune',
        'Dune: Messiah',
      ]);
      expect(
        partTwoCollectionRow.metas.any((m) => m.name == 'Dune: Part Two'),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('hides Collection row for standalone movies and single-film collections', (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final h = createHarness();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tmdbRepositoryProvider.overrideWithValue(h.repo),
            animeIdMapProvider.overrideWithValue(h.idMap),
            aniListAddonRepositoryProvider.overrideWithValue(h.aniRepo),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const DetailScreen(
              meta: MetaModel(id: '888001', type: 'movie', name: 'Solo Film'),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('More Like This'), findsOneWidget);
      expect(find.text('Collection'), findsNothing);

      // Single-film collection also omits the Collection row.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tmdbRepositoryProvider.overrideWithValue(h.repo),
            animeIdMapProvider.overrideWithValue(h.idMap),
            aniListAddonRepositoryProvider.overrideWithValue(h.aniRepo),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: const DetailScreen(
              meta: MetaModel(
                id: '888002',
                type: 'movie',
                name: 'Single Entry Franchise',
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('More Like This'), findsOneWidget);
      expect(find.text('Collection'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
