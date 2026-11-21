import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel/features/addons/data/cloudstream_repo_service.dart';
import 'package:pixel/features/addons/data/official_addons_registry.dart';

class _FakeCsRepoDio implements Dio {
  _FakeCsRepoDio(this._responses);

  final Map<String, ({dynamic data, String? finalUri})> _responses;

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
    final hit = _responses[path];
    if (hit == null) {
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
      requestOptions: RequestOptions(path: hit.finalUri ?? path),
      statusCode: 200,
      data: hit.data as T,
    );
  }
}

void main() {
  group('CloudStreamRepoService', () {
    test('resolves official shortcodes and probes GitHub branches', () async {
      final dio = _FakeCsRepoDio({
        'https://raw.githubusercontent.com/user/demo-cs/refs/heads/builds/repo.json':
            (
          data: jsonEncode({'name': 'Demo', 'pluginLists': ['https://example.com/plugins.json']}),
          finalUri: null,
        ),
        'https://cutt.ly/customshort': (
          data: jsonEncode({'name': 'Short Repo', 'pluginLists': ['https://example.com/p2.json']}),
          finalUri: 'https://raw.githubusercontent.com/short/repo/builds/repo.json',
        ),
      });

      final service = CloudStreamRepoService(dio);

      final megixUrl = await service.resolveRepoUrl('megix');
      expect(
        megixUrl,
        kOfficialCloudStreamRepos.first.repoUrl,
      );

      final ghUrl =
          await service.resolveRepoUrl('https://github.com/user/demo-cs');
      expect(
        ghUrl,
        'https://raw.githubusercontent.com/user/demo-cs/refs/heads/builds/repo.json',
      );

      final shortUrl = await service.resolveRepoUrl('customshort');
      expect(
        shortUrl,
        'https://raw.githubusercontent.com/short/repo/builds/repo.json',
      );
    });

    test('parses manifestVersion >= 1, dedups versions, and flags NSFW',
        () async {
      const repoUrl = 'https://raw.githubusercontent.com/test/cs/builds/CS.json';
      const listUrl =
          'https://raw.githubusercontent.com/test/cs/builds/plugins.json';

      final dio = _FakeCsRepoDio({
        repoUrl: (
          data: jsonEncode({
            'manifestVersion': 2,
            'name': 'Megix Custom',
            'description': 'Multi-language bundle',
            'pluginLists': [listUrl],
          }),
          finalUri: null,
        ),
        listUrl: (
          data: jsonEncode([
            {
              'name': 'CineStream',
              'internalName': 'CineStream',
              'url': 'https://example.com/CineStream.cs3',
              'version': 12,
              'status': 1,
              'tvTypes': ['Movie', 'TvSeries'],
              'language': 'en',
              'fileSize': 20480,
              'fileHash': 'sha256-deadbeef',
            },
            {
              'name': 'CineStream',
              'internalName': 'CineStream',
              'url': 'https://example.com/CineStream_old.cs3',
              'version': 8,
              'status': 1,
            },
            {
              'name': 'AdultSource',
              'internalName': 'AdultSource',
              'url': 'https://example.com/Adult.cs3',
              'version': 2,
              'status': 1,
              'tvTypes': ['NSFW'],
            },
          ]),
          finalUri: null,
        ),
      });

      final service = CloudStreamRepoService(dio);
      final indexed = await service.fetchRepoIndex(repoUrl);

      expect(indexed.name, 'Megix Custom');
      expect(indexed.plugins, hasLength(2));
      final cine = indexed.plugins.firstWhere((p) => p.internalName == 'CineStream');
      expect(cine.version, 12);
      expect(cine.fileHash, 'sha256-deadbeef');
      expect(cine.isNsfw, isFalse);

      final adult =
          indexed.plugins.firstWhere((p) => p.internalName == 'AdultSource');
      expect(adult.isNsfw, isTrue);
    });
  });
}
