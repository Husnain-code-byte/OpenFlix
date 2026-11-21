import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel/features/anime/data/anilist_addon_repository.dart';
import 'package:pixel/features/anime/data/anilist_models.dart';
import 'package:pixel/features/anime/data/anime_id_map.dart';
import 'package:pixel/features/anime/data/anime_resolver.dart';
import 'package:pixel/features/details/data/tmdb_repository.dart';
import 'package:pixel/features/details/presentation/controllers/details_controller.dart';
import 'package:pixel/features/home/data/models/manifest_model.dart';

class _FakeReleaseTmdbDio implements Dio {
  final List<({String path, Map<String, dynamic>? query})> requests = [];

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
    requests.add((path: uriPath, query: queryParameters));

    if (uriPath.endsWith('/movie/upcoming') ||
        uriPath.endsWith('/movie/popular') ||
        uriPath.endsWith('/trending/movie/day')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'results': [
            {
              'id': 1,
              'title': 'Released Movie',
              'poster_path': '/rel_m.jpg',
              'release_date': '2026-11-17',
              'popularity': 90.0,
            },
            {
              'id': 2,
              'title': 'Releases Tomorrow Movie',
              'poster_path': '/tom_m.jpg',
              'release_date': '2026-11-18',
              'popularity': 200.0,
            },
            {
              'id': 3,
              'title': 'TBA Movie',
              'poster_path': '/tba_m.jpg',
              'release_date': '',
              'popularity': 300.0,
            },
          ],
        } as T,
      );
    }

    if (uriPath.endsWith('/tv/on_the_air') || uriPath.endsWith('/tv/popular')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'results': [
            {
              'id': 10,
              'name': 'Released Series',
              'poster_path': '/rel_tv.jpg',
              'first_air_date': '2026-11-10',
              'popularity': 80.0,
            },
            {
              'id': 11,
              'name': 'Future Series',
              'poster_path': '/fut_tv.jpg',
              'first_air_date': '2026-11-18',
              'popularity': 180.0,
            },
            {
              'id': 12,
              'name': 'Unscheduled Series',
              'poster_path': '/tba_tv.jpg',
              'first_air_date': null,
              'popularity': 250.0,
            },
          ],
        } as T,
      );
    }

    if (uriPath.endsWith('/discover/movie')) {
      final page = int.tryParse('${queryParameters?['page'] ?? 1}') ?? 1;
      if (page > 1) {
        return Response<T>(
          requestOptions: RequestOptions(path: path),
          statusCode: 200,
          data: {'results': const <Map<String, dynamic>>[]} as T,
        );
      }
      final genre = queryParameters?['with_genres']?.toString() ?? '';
      if (genre == '99') {
        // 19 released + 2 unreleased = 21 total; must prune under <20 released gate.
        return Response<T>(
          requestOptions: RequestOptions(path: path),
          statusCode: 200,
          data: {
            'results': [
              for (var i = 1; i <= 19; i++)
                {
                  'id': 300 + i,
                  'title': 'Released Doc $i',
                  'poster_path': '/doc_$i.jpg',
                  'release_date': '2025-01-01',
                  'popularity': (100 - i).toDouble(),
                },
              {
                'id': 398,
                'title': 'Unreleased Doc 1',
                'poster_path': '/udoc_1.jpg',
                'release_date': '2026-11-18',
                'popularity': 500.0,
              },
              {
                'id': 399,
                'title': 'Unreleased Doc 2',
                'poster_path': '/udoc_2.jpg',
                'release_date': '',
                'popularity': 501.0,
              },
            ],
          } as T,
        );
      }
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'results': [
            {
              'id': 20,
              'title': 'Category Released',
              'poster_path': '/cat_rel.jpg',
              'release_date': '2026-05-01',
              'popularity': 50.0,
            },
            {
              'id': 21,
              'title': 'Category Releases Tomorrow',
              'poster_path': '/cat_tom.jpg',
              'release_date': '2026-11-18',
              'popularity': 150.0,
            },
          ],
        } as T,
      );
    }

    if (uriPath.endsWith('/collection/700')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'id': 700,
          'name': 'Test Franchise Collection',
          'parts': [
            {
              'id': 500,
              'title': 'Franchise 1 (Open)',
              'poster_path': '/f1.jpg',
              'release_date': '2024-01-01',
              'popularity': 100.0,
            },
            {
              'id': 501,
              'title': 'Franchise 2 (Released)',
              'poster_path': '/f2.jpg',
              'release_date': '2025-06-01',
              'popularity': 90.0,
            },
            {
              'id': 502,
              'title': 'Franchise 3 (Releases Tomorrow)',
              'poster_path': '/f3.jpg',
              'release_date': '2026-11-18',
              'popularity': 250.0,
            },
            {
              'id': 503,
              'title': 'Franchise 4 (TBA)',
              'poster_path': '/f4.jpg',
              'release_date': '',
              'popularity': 300.0,
            },
          ],
        } as T,
      );
    }

    if (uriPath.endsWith('/movie/500')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'id': 500,
          'imdb_id': 'tt0000500',
          'title': 'Franchise 1 (Open)',
          'release_date': '2024-01-01',
          'poster_path': '/f1.jpg',
          'belongs_to_collection': {'id': 700, 'name': 'Test Franchise Collection'},
          'similar': {
            'results': [
              {
                'id': 601,
                'title': 'Similar Released',
                'poster_path': '/s1.jpg',
                'release_date': '2025-01-01',
                'popularity': 60.0,
              },
              {
                'id': 602,
                'title': 'Similar Releases Tomorrow',
                'poster_path': '/s2.jpg',
                'release_date': '2026-11-18',
                'popularity': 120.0,
              },
            ],
          },
          'recommendations': {
            'results': [
              {
                'id': 603,
                'title': 'Rec Released',
                'poster_path': '/r1.jpg',
                'release_date': '2025-02-01',
                'popularity': 70.0,
              },
              {
                'id': 604,
                'title': 'Rec Future',
                'poster_path': '/r2.jpg',
                'release_date': '2027-01-01',
                'popularity': 140.0,
              },
            ],
          },
        } as T,
      );
    }

    if (uriPath.endsWith('/search/movie')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'results': [
            {
              'id': 701,
              'title': 'Search Released',
              'poster_path': '/sr1.jpg',
              'release_date': '2024-05-01',
            },
            {
              'id': 702,
              'title': 'Search Unreleased',
              'poster_path': '/sr2.jpg',
              'release_date': '2026-12-25',
            },
          ],
        } as T,
      );
    }

    final extMatch = RegExp(r'/(movie|tv)/(\d+)/external_ids$').firstMatch(uriPath);
    if (extMatch != null) {
      final id = int.parse(extMatch.group(2)!);
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {'id': id, 'imdb_id': 'tt0000$id'} as T,
      );
    }

    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 404,
      data: <String, dynamic>{} as T,
    );
  }
}

class _FakeReleaseAniListDio implements Dio {
  bool transitionedToReleased = false;

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
  }) async {
    final query = (data is Map<String, dynamic>) ? (data['query'] as String? ?? '') : '';
    if (query.contains('Media(id:')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'data': {
            'Media': {
              'title': {'english': 'Seed Anime', 'romaji': 'Seed Anime'},
              'seasonYear': 2022,
              'genres': ['Action'],
              'tags': const [],
              'recommendations': {
                'nodes': [
                  {
                    'rating': 80,
                    'mediaRecommendation': {
                      'id': 1001,
                      'title': {'english': 'Released Anime Rec'},
                      'format': 'TV',
                      'status': 'FINISHED',
                      'seasonYear': 2023,
                      'startDate': {'year': 2023, 'month': 4, 'day': 1},
                      'genres': ['Action'],
                      'averageScore': 82,
                      'popularity': 50000,
                      'isAdult': false,
                    },
                  },
                  {
                    'rating': 95,
                    'mediaRecommendation': {
                      'id': 1002,
                      'title': {'english': 'Unreleased Anime Rec'},
                      'format': 'TV',
                      'status': 'NOT_YET_RELEASED',
                      'seasonYear': 2027,
                      'startDate': {'year': 2027, 'month': 1, 'day': 10},
                      'genres': ['Action'],
                      'averageScore': 85,
                      'popularity': 90000,
                      'isAdult': false,
                    },
                  },
                ],
              },
            },
          },
        } as T,
      );
    }

    if (query.contains('search:')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'data': {
            'Page': {
              'media': [
                {
                  'id': 1001,
                  'title': {'english': 'Released Anime Search'},
                  'format': 'TV',
                  'status': 'RELEASING',
                  'seasonYear': 2026,
                  'startDate': {'year': 2026, 'month': 10, 'day': 1},
                  'isAdult': false,
                },
                {
                  'id': 1002,
                  'title': {'english': 'Upcoming Anime Search'},
                  'format': 'TV',
                  'status': 'NOT_YET_RELEASED',
                  'seasonYear': 2026,
                  'startDate': {'year': 2026, 'month': 12, 'day': 1},
                  'isAdult': false,
                },
              ],
            },
          },
        } as T,
      );
    }

    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: {
        'data': {
          'c0': {
            'media': [
              {
                'id': 1001,
                'title': {'english': 'Released Anime'},
                'format': 'TV',
                'status': 'RELEASING',
                'seasonYear': 2026,
                'startDate': {'year': 2026, 'month': 10, 'day': 1},
                'averageScore': 80,
                'popularity': 40000,
                'isAdult': false,
              },
              {
                'id': 1002,
                'title': {'english': 'Soon To Release Anime'},
                'format': 'TV',
                'status': transitionedToReleased ? 'RELEASING' : 'NOT_YET_RELEASED',
                'seasonYear': 2026,
                'startDate': {'year': 2026, 'month': 11, 'day': 18},
                'averageScore': 85,
                'popularity': 60000,
                'isAdult': false,
              },
            ],
          },
        },
      } as T,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Unreleased title filtering & instant release reveal across screens', () {
    test('Standard, Category, Collection, and Search rows hide unreleased titles and reveal them once released', () async {
      var now = DateTime(2026, 11, 17, 23, 59, 50);
      final dio = _FakeReleaseTmdbDio();
      final repo = TmdbRepository(dio, clock: () => now);

      // 1. Home / Movies / TV Shows (Standard catalogs)
      final upcomingMovies = await repo.fetchStandardCatalog(
        const CatalogItemModel(
          id: 'tmdb.standard.upcoming_movie',
          type: 'movie',
          name: 'Upcoming Movies',
        ),
        now: now,
      );
      expect(upcomingMovies.map((m) => m.name).toList(), ['Released Movie']);

      final onTheAirTv = await repo.fetchStandardCatalog(
        const CatalogItemModel(
          id: 'tmdb.standard.on_the_air_tv',
          type: 'series',
          name: 'On The Air',
        ),
        now: now,
      );
      expect(onTheAirTv.map((m) => m.name).toList(), ['Released Series']);

      // 2. Categories (/discover with primary_release_date.lte)
      final catMovies = await repo.fetchCategoryCatalog(
        const CatalogItemModel(
          id: 'tmdb.category.28',
          type: 'movie',
          name: 'Action',
        ),
        now: now,
      );
      expect(catMovies.map((m) => m.name).toList(), ['Category Released']);
      final discoverReq = dio.requests.firstWhere((r) => r.path.endsWith('/discover/movie'));
      expect(discoverReq.query?['primary_release_date.lte'], '2026-11-17');

      // 3. Collection Details: prunes under 20 released items, filters /collection/ too
      final prunedCol = await repo.fetchCollectionCatalog(
        catalogKey: 'col|movie|genre_99',
        type: 'movie',
        rowTitle: 'Documentary',
        endpoint: '/discover/movie',
        queryParameters: const {'with_genres': '99'},
        pruneIfUnder20: true,
        now: now,
      );
      expect(prunedCol, isEmpty);

      final franchiseCol = await repo.fetchCollectionCatalog(
        catalogKey: 'col|movie|franchise_700',
        type: 'movie',
        rowTitle: 'Test Franchise',
        endpoint: '/collection/700',
        queryParameters: const {'language': 'en-US'},
        now: now,
      );
      expect(
        franchiseCol.map((m) => m.name).toList(),
        ['Franchise 1 (Open)', 'Franchise 2 (Released)'],
      );

      // 4. Search excludes unreleased movies
      final searchHits = await repo.searchMedia('Search', type: 'movie');
      expect(searchHits.map((m) => m.name).toList(), ['Search Released']);

      // Advance clock 15 seconds across midnight into 2026-11-18:
      // Titles releasing on 2026-11-18 immediately appear in Standard, Category, & Collection!
      now = DateTime(2026, 11, 18, 0, 0, 5);

      final upcomingAfter = await repo.fetchStandardCatalog(
        const CatalogItemModel(
          id: 'tmdb.standard.upcoming_movie',
          type: 'movie',
          name: 'Upcoming Movies',
        ),
        now: now,
      );
      expect(
        upcomingAfter.map((m) => m.name).toList(),
        containsAll(['Released Movie', 'Releases Tomorrow Movie']),
      );
      expect(upcomingAfter.map((m) => m.name), isNot(contains('TBA Movie')));

      final onTheAirAfter = await repo.fetchStandardCatalog(
        const CatalogItemModel(
          id: 'tmdb.standard.on_the_air_tv',
          type: 'series',
          name: 'On The Air',
        ),
        now: now,
      );
      expect(
        onTheAirAfter.map((m) => m.name).toList(),
        containsAll(['Released Series', 'Future Series']),
      );
      expect(onTheAirAfter.map((m) => m.name), isNot(contains('Unscheduled Series')));

      final catAfter = await repo.fetchCategoryCatalog(
        const CatalogItemModel(
          id: 'tmdb.category.28',
          type: 'movie',
          name: 'Action',
        ),
        now: now,
      );
      expect(
        catAfter.map((m) => m.name).toList(),
        containsAll(['Category Released', 'Category Releases Tomorrow']),
      );

      final franchiseAfter = await repo.fetchCollectionCatalog(
        catalogKey: 'col|movie|franchise_700',
        type: 'movie',
        rowTitle: 'Test Franchise',
        endpoint: '/collection/700',
        queryParameters: const {'language': 'en-US'},
        now: now,
      );
      expect(
        franchiseAfter.map((m) => m.name).toList(),
        containsAll([
          'Franchise 3 (Releases Tomorrow)',
          'Franchise 1 (Open)',
          'Franchise 2 (Released)',
        ]),
      );
      expect(franchiseAfter.map((m) => m.name), isNot(contains('Franchise 4 (TBA)')));
    });

    test('DetailsController filters unreleased titles in More Like This, Viewers Also Watched, and Collection, and reveals them on release day', () async {
      var now = DateTime(2026, 11, 17, 23, 59, 58);
      final dio = _FakeReleaseTmdbDio();
      final idMap = AnimeIdMap()..populate({}, {});
      final repo = TmdbRepository(dio, clock: () => now, animeIdMap: idMap);
      final aniRepo = AniListAddonRepository(
        dio: _FakeReleaseAniListDio(),
        resolver: AnimeResolver(animeIdMap: idMap, tmdbDio: dio),
      );

      final container = ProviderContainer(
        overrides: [
          tmdbRepositoryProvider.overrideWithValue(repo),
          animeIdMapProvider.overrideWithValue(idMap),
          aniListAddonRepositoryProvider.overrideWithValue(aniRepo),
        ],
      );
      addTearDown(container.dispose);

      const key = (id: '500', type: 'movie');
      final sub = container.listen(detailsControllerProvider(key), (_, __) {});
      addTearDown(sub.close);

      await Future<void>.delayed(const Duration(milliseconds: 50));
      final beforeRelease = container.read(detailsControllerProvider(key));
      expect(beforeRelease.similarMetas.map((m) => m.name).toList(), ['Similar Released']);
      expect(beforeRelease.recommendedMetas.map((m) => m.name).toList(), ['Rec Released']);
      expect(
        beforeRelease.collectionMetas.map((m) => m.name).toList(),
        ['Franchise 2 (Released)'],
      );

      // Advance clock across midnight into 2026-11-18 and notify release arrival:
      // Newly released titles appear immediately without refetching /movie/500 or /collection/700!
      now = DateTime(2026, 11, 18, 0, 0, 1);
      final coreBeforeCalls = dio.requests.where((r) => r.path.endsWith('/movie/500')).length;
      final colBeforeCalls = dio.requests.where((r) => r.path.endsWith('/collection/700')).length;

      container.read(detailsControllerProvider(key).notifier).refreshIfReleaseArrived();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final afterRelease = container.read(detailsControllerProvider(key));
      expect(
        afterRelease.similarMetas.map((m) => m.name).toList(),
        ['Similar Releases Tomorrow', 'Similar Released'],
      );
      expect(afterRelease.recommendedMetas.map((m) => m.name).toList(), ['Rec Released']);
      expect(
        afterRelease.collectionMetas.map((m) => m.name).toList(),
        ['Franchise 3 (Releases Tomorrow)', 'Franchise 2 (Released)'],
      );
      // Newly revealed collection item also gets its IMDb ID enriched.
      expect(afterRelease.collectionMetas.first.id, 'tt0000502');
      expect(dio.requests.where((r) => r.path.endsWith('/movie/500')).length, coreBeforeCalls);
      expect(dio.requests.where((r) => r.path.endsWith('/collection/700')).length, colBeforeCalls);
    });

    test('AniList catalog, recommendations, search, and AnimeResolver filter unreleased anime and reveal once released', () async {
      final idMap = AnimeIdMap()
        ..populate({
          1001: const AnimeIds(imdbId: 'tt1001', tmdbId: 1001),
          1002: const AnimeIds(imdbId: 'tt1002', tmdbId: 1002),
        }, {
          'imdb:tt1001': 1001,
          'imdb:tt1002': 1002,
        });
      var aniNow = DateTime(2026, 11, 17, 23, 59, 50);
      final aniDio = _FakeReleaseAniListDio();
      final repo = AniListAddonRepository(
        dio: aniDio,
        resolver: AnimeResolver(animeIdMap: idMap, tmdbDio: _FakeReleaseTmdbDio()),
        clock: () => aniNow,
      );

      // Catalog row omits NOT_YET_RELEASED anime
      final catalog = await repo.fetchCatalog(
        const CatalogItemModel(
          id: 'anilist.popular',
          type: 'series',
          name: 'Popular Anime',
        ),
      );
      expect(catalog.map((m) => m.name).toList(), ['Released Anime']);

      // Recommendations (Anime Picks) omits NOT_YET_RELEASED anime
      final recs = await repo.fetchRecommendations(999);
      expect(recs.map((m) => m.name).toList(), ['Released Anime Rec']);

      // Search omits NOT_YET_RELEASED anime
      final search = await repo.searchCatalog(
        const CatalogItemModel(
          id: 'anilist.search.series',
          type: 'series',
          name: 'AniList',
        ),
        'Anime',
      );
      expect(search.map((m) => m.name).toList(), ['Released Anime Search']);

      // Future startDate media is blocked even if status wasn't NOT_YET_RELEASED
      const futureStart = AniListMedia(
        id: 1002,
        title: AniListTitle(english: 'Future Date'),
        format: 'TV',
        status: 'RELEASING',
        startDateYear: 2099,
        startDateMonth: 1,
        startDateDay: 1,
      );
      expect(futureStart.isReleased(now: DateTime(2026, 11, 17)), isFalse);
      expect(futureStart.isReleased(now: DateTime(2099, 1, 1)), isTrue);

      // Once released and day advances to 2026-11-18, AniList catalog includes it immediately.
      aniNow = DateTime(2026, 11, 18, 0, 0, 1);
      aniDio.transitionedToReleased = true;
      repo.clearCache();
      final catalogAfter = await repo.fetchCatalog(
        const CatalogItemModel(
          id: 'anilist.popular',
          type: 'series',
          name: 'Popular Anime',
        ),
      );
      expect(
        catalogAfter.map((m) => m.name).toList(),
        containsAll(['Soon To Release Anime', 'Released Anime']),
      );
    });
  });
}
