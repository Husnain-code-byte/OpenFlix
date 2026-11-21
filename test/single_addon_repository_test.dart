import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel/core/constants/api_constants.dart';
import 'package:pixel/core/network/dio_client.dart';
import 'package:pixel/features/home/data/models/manifest_model.dart';
import 'package:pixel/features/home/data/repositories/addon_repository_impl.dart';

class _RecordingClient extends StremioAddonClient {
  _RecordingClient(Dio dio) : super(dio);

  final urls = <String>[];
  final tokens = <CancelToken?>[];

  @override
  Future<Map<String, dynamic>> getJson(
    String url, {
    CancelToken? cancelToken,
  }) async {
    urls.add(url);
    tokens.add(cancelToken);
    if (Uri.parse(url).path.endsWith('/manifest.json')) {
      return {
        'id': 'test.addon',
        'version': '1.0.0',
        'name': 'Test Addon',
        'catalogs': [
          {'id': 'for_you', 'type': 'movie', 'name': 'For You'},
          {'id': 'for_you', 'type': 'series', 'name': 'For You'},
          {'id': 'popular', 'type': 'movie', 'name': 'Popular'},
        ],
      };
    }
    return {
      'metas': [
        {
          'id': 'tt2380307',
          'type': 'movie',
          'name': 'Coco',
          'poster': 'https://example.test/poster.jpg',
          'logo': 'https://example.test/logo.png',
        },
      ],
    };
  }
}

void main() {
  const defaultManifestUrl = 'https://v3-cinemeta.strem.io/manifest.json';
  late Dio dio;
  late _RecordingClient client;
  late AddonRepositoryImpl repository;

  setUp(() {
    dio = Dio();
    client = _RecordingClient(dio);
    repository = AddonRepositoryImpl(client);
  });

  tearDown(() => dio.close(force: true));

  test('only the original manifest is requested, in its original order', () async {
    final manifest = await repository.fetchManifest();

    expect(client.urls, [defaultManifestUrl]);
    expect(
      manifest.catalogs.map((catalog) => catalog.key).toList(),
      ['movie/for_you', 'series/for_you', 'movie/popular'],
    );
    expect(manifest.catalogs[0], isNot(manifest.catalogs[1]));
  });

  test('catalogs and pagination use the original manifest base', () async {
    const catalog = CatalogItemModel(id: 'popular', type: 'movie', name: 'Popular');
    final token = CancelToken();
    final base = ApiConstants.deriveBaseUrl(defaultManifestUrl);

    final metas = await repository.fetchCatalog(catalog, cancelToken: token);
    await repository.fetchCatalog(catalog, skip: 40, cancelToken: token);

    expect(client.urls, [
      '$base/catalog/movie/popular.json',
      '$base/catalog/movie/popular/skip=40.json',
    ]);
    expect(client.tokens, everyElement(same(token)));
    expect(metas.single.name, 'Coco');
    expect(metas.single.poster, 'https://example.test/poster.jpg');
    expect(metas.single.logo, 'https://example.test/logo.png');
  });

  test('the single manifest override remains usable for testing', () async {
    final custom = AddonRepositoryImpl(
      client,
      manifestUrl: 'https://example.test/addon/manifest.json',
    );
    final manifest = await custom.fetchManifest();
    await custom.fetchCatalog(manifest.catalogs.first);

    expect(client.urls, [
      'https://example.test/addon/manifest.json',
      'https://example.test/addon/catalog/movie/for_you.json',
    ]);
  });
}