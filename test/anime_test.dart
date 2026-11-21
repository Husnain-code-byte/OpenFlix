import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel/features/anime/data/anilist_addon_repository.dart';
import 'package:pixel/features/anime/data/anilist_models.dart';
import 'package:pixel/features/anime/data/anime_id_map.dart';
import 'package:pixel/features/anime/data/anime_resolver.dart';

class _FakeTmdbDio implements Dio {
  _FakeTmdbDio({this.searchResults = const []});

  final List<Map<String, dynamic>> searchResults;
  final List<String> requestedPaths = [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<Response<T>> get<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    Options? options,
    ProgressCallback? onReceiveProgress,
  }) async {
    requestedPaths.add('$path?query=${queryParameters?['query']}');
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: {'results': searchResults} as T,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AnimeIdMap', () {
    test('populates and lookups forward and reverse IDs', () {
      final map = AnimeIdMap();
      map.populate(
        {
          16498: const AnimeIds(
            imdbId: 'tt2560140',
            tmdbId: 1429,
            isMovie: false,
            season: 1,
          ),
          372058: const AnimeIds(
            imdbId: 'tt5311514',
            tmdbId: 372058,
            isMovie: true,
          ),
        },
        {
          'imdb:tt2560140': 16498,
          'series:1429': 16498,
          'tv:1429': 16498,
          'imdb:tt5311514': 372058,
          'movie:372058': 372058,
        },
      );

      final tv = map.lookupByAnilistId(16498);
      expect(tv?.imdbId, 'tt2560140');
      expect(tv?.tmdbId, 1429);
      expect(tv?.isMovie, false);

      expect(map.lookupAnilistIdByImdb('tt2560140'), 16498);
      expect(map.lookupAnilistIdByTmdb(tmdbId: 1429, type: 'series'), 16498);
      expect(map.lookupAnilistIdByTmdb(tmdbId: 372058, type: 'movie'), 372058);
    });

    test('loads bundled assets/anime_id_map.json and resolves real anime IDs', () async {
      final map = AnimeIdMap();
      await map.ensureLoaded();
      expect(map.isLoaded, true);

      // Cowboy Bebop (AniList 1 -> IMDb tt0213338 / TMDB 30991)
      final bebop = map.lookupByAnilistId(1);
      expect(bebop?.imdbId, 'tt0213338');
      expect(bebop?.tmdbId, 30991);
      expect(map.lookupAnilistIdByImdb('tt0213338'), 1);
    });
  });

  group('AnimeResolver', () {
    test('resolves mapped items and skips unmapped ones', () async {
      final idMap = AnimeIdMap();
      idMap.populate(
        {
          100: const AnimeIds(imdbId: 'tt100', tmdbId: 100),
          101: const AnimeIds(imdbId: 'tt100', tmdbId: 100), // Sequel with same IMDB
        },
        {'imdb:tt100': 100},
      );

      final fakeDio = _FakeTmdbDio();
      final resolver = AnimeResolver(animeIdMap: idMap, tmdbDio: fakeDio);

      final mediaList = [
        const AniListMedia(
          id: 100,
          title: AniListTitle(romaji: 'Season 1', english: 'Title S1'),
          format: 'TV',
          seasonYear: 2020,
        ),
        const AniListMedia(
          id: 101,
          title: AniListTitle(romaji: 'Season 2', english: 'Title S2'),
          format: 'TV',
          seasonYear: 2022,
        ),
        const AniListMedia(
          id: 999,
          title: AniListTitle(romaji: 'Unknown Show'),
          format: 'TV',
        ),
      ];

      final resolved = await resolver.resolveMediaList(mediaList);
      // Item 100 resolved. Item 101 has duplicate key 'tt100' so deduped. Item 999 unmapped so dropped.
      expect(resolved.length, 1);
      expect(resolved.first.id, 'tt100');
      expect(resolved.first.name, 'Title S1');
      expect(resolved.first.poster, contains('btttr.cc/poster-a/imdb/poster-default/tt100.jpg'));
    });

    test('falls back to TMDB title search when not in Fribb map', () async {
      final idMap = AnimeIdMap();
      idMap.populate({}, {});

      final fakeDio = _FakeTmdbDio(
        searchResults: [
          {'id': 7890, 'name': 'Found Anime'}
        ],
      );
      final resolver = AnimeResolver(animeIdMap: idMap, tmdbDio: fakeDio);

      final mediaList = [
        const AniListMedia(
          id: 500,
          title: AniListTitle(romaji: 'Searchable Anime'),
          format: 'TV',
          seasonYear: 2021,
        ),
      ];

      final resolved = await resolver.resolveMediaList(mediaList);
      expect(resolved.length, 1);
      expect(resolved.first.id, '7890');
      expect(fakeDio.requestedPaths.first, contains('Searchable Anime'));
      expect(idMap.lookupAnilistIdByTmdb(tmdbId: 7890, type: 'series'), 500);

      // Re-resolving hits the fallback cache without issuing another network search
      final countBefore = fakeDio.requestedPaths.length;
      final cachedResolved = await resolver.resolveMediaList(mediaList);
      expect(cachedResolved.length, 1);
      expect(cachedResolved.first.id, '7890');
      expect(fakeDio.requestedPaths.length, countBefore);
    });
  });

  group('AniListAddonRepository', () {
    test('static manifest contains expected catalogs', () async {
      final manifest = AniListAddonRepository.staticManifest;
      expect(manifest.id, 'anilist');
      expect(manifest.catalogs.any((c) => c.id == 'anilist.popular'), true);
      expect(manifest.catalogs.any((c) => c.id == 'anilist.airing'), true);
      expect(manifest.catalogs.any((c) => c.id == 'anilist.upcoming'), true);
      expect(manifest.catalogs.any((c) => c.id == 'anilist.genre.Action'), true);
      expect(manifest.catalogs.any((c) => c.id == 'anilist.tag.Isekai'), true);
      expect(manifest.catalogs.any((c) => c.id == 'anilist.search.series'), true);
      expect(manifest.catalogs.any((c) => c.id == 'anilist.search.movie'), true);
    });
  });
}
