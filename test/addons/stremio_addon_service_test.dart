import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel/features/addons/data/stremio_addon_service.dart';
import 'package:pixel/features/addons/domain/models/addon_models.dart';
import 'package:pixel/features/addons/domain/models/stream_models.dart';

class _FakeStremioDio implements Dio {
  _FakeStremioDio(this._routes);

  final Map<String, dynamic> _routes;
  final List<String> requestedUrls = [];

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
    requestedUrls.add(path);
    if (!_routes.containsKey(path)) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        response: Response(
          requestOptions: RequestOptions(path: path),
          statusCode: 404,
        ),
        type: DioExceptionType.badResponse,
      );
    }
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: _routes[path] as T,
    );
  }
}

void main() {
  group('StremioAddonService', () {
    test('normalizes stremio://, configure paths, trailing slashes, and baseUrl',
        () {
      expect(
        StremioAddonService.normalizeManifestUrl(
          'stremio://example.org/cfg123/manifest.json',
        ),
        'https://example.org/cfg123/manifest.json',
      );
      expect(
        StremioAddonService.normalizeManifestUrl('https://example.org/addon/'),
        'https://example.org/addon/manifest.json',
      );
      expect(
        StremioAddonService.normalizeManifestUrl(
          'https://example.org/cfg/configure',
        ),
        'https://example.org/cfg/manifest.json',
      );
      expect(
        StremioAddonService.deriveBaseUrl(
          'https://example.org/cfg/manifest.json',
        ),
        'https://example.org/cfg',
      );
      expect(
        StremioAddonService.deriveConfigureUrl(
          'https://example.org/cfg/manifest.json',
        ),
        'https://example.org/cfg/configure',
      );
      expect(
        () => StremioAddonService.normalizeManifestUrl(''),
        throwsFormatException,
      );
    });

    test('fetches text/plain manifest, catalog, meta videos, and streams',
        () async {
      final manifestJson = jsonEncode({
        'id': 'org.test.stremio',
        'version': '2.1.0',
        'name': 'Test Addon',
        'description': 'Catalogs + Streams',
        'types': ['movie', 'series'],
        'idPrefixes': ['tt', 'kitsu:'],
        'resources': [
          'catalog',
          {'name': 'meta', 'types': ['series'], 'idPrefixes': ['kitsu:']},
          'stream',
          'subtitles',
        ],
        'behaviorHints': {'configurable': true},
        'catalogs': [
          {'id': 'top_movies', 'type': 'movie', 'name': 'Top Movies'},
          {
            'id': 'anime_hot',
            'type': 'anime',
            'name': 'Hot Anime',
            'extraSupported': ['search'],
          },
          {
            'id': 'search_only',
            'type': 'movie',
            'name': 'Search',
            'extraRequired': ['search'],
          },
        ],
      });

      final catalogJson = jsonEncode({
        'metas': [
          {'id': 'kitsu:42', 'type': 'series', 'name': 'Sample Anime'},
        ],
      });

      final metaJson = jsonEncode({
        'meta': {
          'id': 'kitsu:42',
          'type': 'series',
          'name': 'Sample Anime',
          'description': 'Custom ID show',
          'releaseInfo': '2024',
          'cast': ['Actor One'],
          'videos': [
            {
              'id': 'kitsu:42:1',
              'title': 'Pilot Episode',
              'season': 1,
              'episode': 1,
              'released': '2024-04-01T00:00:00Z',
            },
          ],
        },
      });

      final streamJson = jsonEncode({
        'streams': [
          {
            'name': 'StreamA 4K',
            'description': 'Direct HLS 2160p REMUX',
            'url': 'https://cdn.example.com/master.m3u8',
            'behaviorHints': {
              'videoSize': 4294967296,
              'filename': 'Sample.2160p.mkv',
              'proxyHeaders': {
                'request': {'Referer': 'https://ref.example.com'},
              },
            },
          },
          {
            'name': 'StreamB P2P',
            'title': 'Sample.1080p.WEB-DL',
            'infoHash': 'abcdef1234567890abcdef1234567890abcdef12',
            'fileIdx': 0,
          },
        ],
      });

      final dio = _FakeStremioDio({
        'https://addon.example.com/cfg/manifest.json': manifestJson,
        'https://addon.example.com/cfg/catalog/anime/anime_hot/search=One%20Piece.json':
            catalogJson,
        'https://addon.example.com/cfg/meta/series/kitsu%3A42.json': metaJson,
        'https://addon.example.com/cfg/stream/movie/tt0133093.json': streamJson,
      });

      final service = StremioAddonService(dio);
      final manifest = await service.fetchManifest(
        'stremio://addon.example.com/cfg/manifest.json',
      );
      expect(manifest.id, 'org.test.stremio');
      expect(manifest.behaviorHints.configurable, isTrue);
      expect(manifest.supportsResource('stream', type: 'movie'), isTrue);
      expect(
        manifest.supportsResource('meta', type: 'series', id: 'kitsu:42'),
        isTrue,
      );
      expect(
        manifest.supportsResource('meta', type: 'series', id: 'tt0133093'),
        isFalse,
      );

      final placements =
          StremioAddonService.defaultPlacementsForManifest(manifest);
      expect(placements.length, 3);
      expect(
        placements[0].targetScreens,
        {AddonTargetScreen.home, AddonTargetScreen.movies},
      );
      expect(placements[1].targetScreens, {AddonTargetScreen.anime});
      expect(placements[2].enabled, isFalse);

      final catItems = await service.fetchCatalog(
        'https://addon.example.com/cfg',
        manifest.catalogs[1],
        sourceAddonId: manifest.id,
        search: 'One Piece',
      );
      expect(catItems, hasLength(1));
      expect(catItems.first.sourceAddonId, 'org.test.stremio');

      final metaPayload = await service.fetchMeta(
        'https://addon.example.com/cfg',
        'series',
        'kitsu:42',
        sourceAddonId: manifest.id,
      );
      expect(metaPayload, isNotNull);
      expect(metaPayload!.videos, hasLength(1));
      expect(metaPayload.videos.first.title, 'Pilot Episode');

      final installed = InstalledStremioAddon(
        id: manifest.id,
        manifestUrl: 'https://addon.example.com/cfg/manifest.json',
        baseUrl: 'https://addon.example.com/cfg',
        manifest: manifest,
      );
      final streams = await service.fetchStreams(
        installed,
        'movie',
        'tt0133093',
      );
      expect(streams, hasLength(2));
      expect(streams[0].transport, StreamTransport.hls);
      expect(streams[0].qualityLabel, '4K');
      expect(streams[0].qualityRank, 2160);
      expect(streams[0].referer, 'https://ref.example.com');
      expect(streams[1].transport, StreamTransport.torrent);
      expect(streams[1].qualityLabel, '1080p');
    });
  });
}
