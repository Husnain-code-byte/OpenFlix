import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel/features/details/data/tmdb_repository.dart';
import 'package:pixel/features/home/data/models/manifest_model.dart';
import 'package:pixel/features/home/data/models/meta_model.dart';
import 'package:pixel/features/home/data/repositories/addon_repository_impl.dart';
import 'package:pixel/features/home/domain/repositories/addon_repository.dart';
import 'package:pixel/features/search/presentation/controllers/search_controller.dart';

class _FakeAddonRepo implements AddonRepository {
  _FakeAddonRepo({
    required this.manifest,
    required this.resultsByCatalogKey,
  });

  final ManifestModel manifest;
  final Map<String, List<MetaModel>> resultsByCatalogKey;
  final List<String> searchedQueries = [];

  @override
  Future<ManifestModel> fetchManifest({CancelToken? cancelToken}) async => manifest;

  @override
  Future<List<MetaModel>> fetchCatalog(
    CatalogItemModel catalog, {
    int? skip,
    CancelToken? cancelToken,
  }) async =>
      resultsByCatalogKey[catalog.key] ?? const [];

  @override
  Future<List<MetaModel>> searchCatalog(
    CatalogItemModel catalog,
    String query, {
    CancelToken? cancelToken,
  }) async {
    searchedQueries.add('${catalog.key}:$query');
    return resultsByCatalogKey[catalog.key] ?? const [];
  }
}

class _FakeTmdbSearchDio implements Dio {
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
    if (path.endsWith('/search/movie')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'results': [
            {
              'id': 268,
              'title': 'Batman',
              'poster_path': '/batman_movie.jpg',
              'backdrop_path': '/batman_bg.jpg',
              'release_date': '1989-06-23',
              'vote_average': 7.5,
              'overview': 'Gotham dark knight.',
            }
          ],
        } as T,
      );
    }
    if (path.endsWith('/search/tv')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'results': [
            {
              'id': 2098,
              'name': 'Batman: The Animated Series',
              'poster_path': '/batman_tas.jpg',
              'first_air_date': '1992-09-05',
              'vote_average': 8.5,
            }
          ],
        } as T,
      );
    }
    if (path.contains('/external_ids')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {'imdb_id': 'tt0096895'} as T,
      );
    }
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: <String, dynamic>{} as T,
    );
  }
}

void main() {
  test('CatalogItemModel.supportsSearch detects search capability across manifest formats', () {
    final addonSearch = CatalogItemModel.fromJson({
      'id': 'addon.search',
      'type': 'movie',
      'name': 'Results',
      'showInHome': false,
      'extra': [
        {'name': 'search', 'isRequired': true},
      ],
      'extraSupported': ['search', 'skip'],
      'extraRequired': ['search'],
    });
    expect(addonSearch.supportsSearch, isTrue);
    expect(addonSearch.hasRequiredExtra, isTrue);

    final regularCatalog = CatalogItemModel.fromJson({
      'id': 'addon.popular',
      'type': 'movie',
      'name': 'Popular',
      'extra': [
        {'name': 'genre', 'isRequired': false},
      ],
    });
    expect(regularCatalog.supportsSearch, isFalse);
    expect(regularCatalog.hasRequiredExtra, isFalse);
  });

  test('SearchController aggregates search rows from multiple addons and TMDB API key', () async {
    final addon1 = _FakeAddonRepo(
      manifest: ManifestModel.fromJson({
        'id': 'com.addon',
        'name': 'CatalogAddon',
        'version': '1.0.0',
        'description': 'Primary addon',
        'catalogs': [
          {
            'id': 'addon.search',
            'type': 'movie',
            'name': 'Results',
            'extraRequired': ['search'],
          },
          {
            'id': 'addon.search',
            'type': 'series',
            'name': 'Results',
            'extraRequired': ['search'],
          },
        ],
      }),
      resultsByCatalogKey: {
        'movie/addon.search': const [
          MetaModel(
            id: 'tt1877830',
            type: 'movie',
            name: 'The Batman',
            poster: 'https://example.com/the_batman.jpg',
          ),
        ],
        'series/addon.search': const [
          MetaModel(
            id: 'tt0103359',
            type: 'series',
            name: 'Batman: The Animated Series',
            poster: 'https://example.com/btas.jpg',
          ),
        ],
      },
    );

    final addon2 = _FakeAddonRepo(
      manifest: ManifestModel.fromJson({
        'id': 'com.cinemeta',
        'name': 'Cinemeta',
        'version': '1.0.0',
        'description': 'Secondary addon',
        'catalogs': [
          {
            'id': 'top',
            'type': 'movie',
            'name': 'Top',
            'extraSupported': ['search'],
          },
        ],
      }),
      resultsByCatalogKey: {
        'movie/top': const [
          MetaModel(
            id: 'tt0372784',
            type: 'movie',
            name: 'Batman Begins',
            poster: 'https://example.com/begins.jpg',
          ),
        ],
      },
    );

    final container = ProviderContainer(
      overrides: [
        installedAddonsProvider.overrideWithValue([addon1, addon2]),
        tmdbRepositoryProvider.overrideWithValue(TmdbRepository(_FakeTmdbSearchDio())),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(searchControllerProvider.notifier);
    notifier.submitSearch('Batman');

    // Wait for async search futures to complete.
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final state = container.read(searchControllerProvider);
    expect(state.isSearching, isFalse);
    expect(
      state.rows.map((r) => r.title).toList(),
      equals([
        'CatalogAddon · Movies',
        'CatalogAddon · Series',
        'Cinemeta (Top) · Movies',
        'TMDB · Movies',
        'TMDB · Series',
      ]),
    );

    notifier.clearQuery();
    expect(container.read(searchControllerProvider).query, isEmpty);
    expect(container.read(searchControllerProvider).rows, isEmpty);
  });

  test('places AniList search rows after TMDB rows', () async {
    final anilistAddon = _FakeAddonRepo(
      manifest: const ManifestModel(
        id: 'anilist',
        version: '1.0.0',
        name: 'AniList',
        catalogs: [
          CatalogItemModel(
            id: 'anilist.search.series',
            type: 'series',
            name: 'AniList',
            extraRequired: ['search'],
          ),
          CatalogItemModel(
            id: 'anilist.search.movie',
            type: 'movie',
            name: 'AniList',
            extraRequired: ['search'],
          ),
        ],
      ),
      resultsByCatalogKey: const {
        'series/anilist.search.series': [
          MetaModel(id: 'tt1', type: 'series', name: 'Anime Series', poster: 'p1'),
        ],
        'movie/anilist.search.movie': [
          MetaModel(id: 'tt2', type: 'movie', name: 'Anime Movie', poster: 'p2'),
        ],
      },
    );

    final container = ProviderContainer(
      overrides: [
        installedAddonsProvider.overrideWithValue([anilistAddon]),
        tmdbRepositoryProvider.overrideWithValue(TmdbRepository(_FakeTmdbSearchDio())),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(searchControllerProvider.notifier);
    notifier.submitSearch('Titan');

    await Future<void>.delayed(const Duration(milliseconds: 50));

    final state = container.read(searchControllerProvider);
    expect(
      state.rows.map((r) => r.title).toList(),
      equals([
        'TMDB · Movies',
        'TMDB · Series',
        'AniList · Series',
        'AniList · Movies',
      ]),
    );
  });
}
