import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel/features/anime/data/anime_id_map.dart';
import 'package:pixel/features/details/data/tmdb_models.dart';
import 'package:pixel/features/details/data/tmdb_repository.dart';
import 'package:pixel/features/home/data/models/meta_model.dart';

// Dio only exposes factory constructors, so it cannot be subclassed. Implement
// the interface instead; unused methods deliberately throw via noSuchMethod.
class _FakeTmdbClient implements Dio {
  final List<String> requestedPaths = [];
  final List<Map<String, dynamic>> postedRatings = [];

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
    requestedPaths.add('POST $path');
    if (data is Map<String, dynamic>) {
      postedRatings.add({'path': path, ...data});
    }
    if (path.contains('/authentication/session/new')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {'success': true, 'session_id': 'test_user_session_999'} as T,
      );
    }
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 201,
      data: {'success': true} as T,
    );
  }

  @override
  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    requestedPaths.add('DELETE $path');
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: {'success': true} as T,
    );
  }

  @override
  Future<Response<T>> get<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    requestedPaths.add(path);

    if (path.contains('/authentication/token/new')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {'success': true, 'request_token': 'req_tok_abc123'} as T,
      );
    }
    if (path.endsWith('/account')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'id': 999,
          'username': 'openflix_user',
          'name': 'OpenFlix Tester',
          'avatar': {
            'tmdb': {'avatar_path': '/avatar_999.jpg'},
          },
        } as T,
      );
    }
    if (path.contains('/account/999/watchlist/movies')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'results': [
            {
              'id': 102,
              'title': 'High Pop Similar',
              'poster_path': '/high.jpg',
              'backdrop_path': '/high_bg.jpg',
              'release_date': '2024-03-01',
              'vote_average': 8.4,
            },
          ],
        } as T,
      );
    }
    if (path.contains('/account/999/watchlist/tv')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {'results': <Map<String, dynamic>>[]} as T,
      );
    }
    if (path.contains('/account/999/rated/movies')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'results': [
            {
              'id': 102,
              'title': 'High Pop Similar',
              'poster_path': '/high.jpg',
              'rating': 8.5,
            },
            {
              'id': 101,
              'title': 'Low Pop Similar',
              'poster_path': '/low.jpg',
              'rating': 1.5,
            },
          ],
        } as T,
      );
    }
    if (path.contains('/account/999/rated/tv')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {'results': <Map<String, dynamic>>[]} as T,
      );
    }
    if (path.contains('/trending/movie/day')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'results': [
            {
              'id': 102,
              'title': 'High Pop Similar',
              'poster_path': '/high.jpg',
              'backdrop_path': '/high_bg.jpg',
              'popularity': 95.0,
              'release_date': '2024-03-01',
              'vote_average': 8.4,
            },
          ],
        } as T,
      );
    }
    if (path.contains('/find/tt1234567')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'movie_results': [
            {'id': 12345}
          ],
        } as T,
      );
    }
    if (path.contains('/find/tt0903747')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'tv_results': [
            {'id': 1396}
          ],
        } as T,
      );
    }
    if (path.contains('/movie/102/external_ids')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {'id': 102, 'imdb_id': 'tt0000102'} as T,
      );
    }
    if (path.contains('/movie/102')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'id': 102,
          'imdb_id': 'tt0000102',
          'title': 'High Pop Similar',
          'overview': 'Direct lookup without /find/',
        } as T,
      );
    }
    if (path.contains('/movie/12345')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'id': 12345,
          'title': 'Test Movie',
          'overview': 'Overview text',
          'similar': {
            'results': [
              {
                'id': 101,
                'title': 'Low Pop Similar',
                'poster_path': '/low.jpg',
                'release_date': '2024-01-01',
                'popularity': 1.5,
              },
              {
                'id': 102,
                'title': 'High Pop Similar',
                'poster_path': '/high.jpg',
                'release_date': '2024-03-01',
                'popularity': 95.0,
              },
            ]
          },
          'recommendations': {
            'results': [
              {
                'id': 201,
                'title': 'Rec Title 1',
                'poster_path': '/rec1.jpg',
                'release_date': '2024-01-15',
                'popularity': 12.0,
              },
              {
                'id': 202,
                'title': 'Rec Title 2',
                'poster_path': '/rec2.jpg',
                'release_date': '2024-02-15',
                'popularity': 45.0,
              },
              // Overlapping ID 102 in both lists to test deduplication
              {
                'id': 102,
                'title': 'High Pop Similar',
                'poster_path': '/high.jpg',
                'release_date': '2024-03-01',
                'popularity': 95.0,
              },
            ]
          },
        } as T,
      );
    }
    if (path.contains('/tv/1396/season/1')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'id': 3572,
          'season_number': 1,
          'name': 'Season 1',
          'episodes': [
            {
              'id': 62085,
              'episode_number': 1,
              'season_number': 1,
              'name': 'Leavetaking',
              'overview': 'A strange noblewoman arrives in a remote mountain village.',
              'still_path': '/pilot.jpg',
              'air_date': '2021-11-18',
              'runtime': 55,
              'vote_average': 8.9,
            },
            {
              'id': 62086,
              'episode_number': 2,
              'season_number': 1,
              'name': 'Future Episode',
              'overview': 'Releases in the future.',
              'still_path': '/ep2.jpg',
              'air_date': '2099-12-31',
              'runtime': 52,
              'vote_average': 0.0,
            },
            {
              'id': 62087,
              'episode_number': 3,
              'season_number': 1,
              'name': 'TBA Episode',
              'overview': '',
              'still_path': null,
              'air_date': null,
              'runtime': null,
              'vote_average': 0.0,
            },
          ],
        } as T,
      );
    }
    if (path.contains('/tv/1396')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'id': 1396,
          'name': 'Breaking Bad',
          'overview': 'Chemistry teacher series',
          'first_air_date': '2008-01-20',
          'episode_run_time': [47],
          'number_of_seasons': 3,
          'number_of_episodes': 62,
          'seasons': [
            {
              'id': 3571,
              'season_number': 0,
              'name': 'Specials',
              'episode_count': 5,
              'air_date': '2009-02-17',
            },
            {
              'id': 3572,
              'season_number': 1,
              'name': 'Book One',
              'episode_count': 8,
              'air_date': '2021-11-18',
              'poster_path': '/s1.jpg',
            },
          ],
        } as T,
      );
    }
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 404,
    );
  }
}

void main() {
  test('TmdbRepository parses both similar and recommendations sorted by popularity descending', () async {
    final dio = _FakeTmdbClient();
    final repo = TmdbRepository(dio);

    final details = await repo.fetchMovie('tt1234567');

    expect(details.title, 'Test Movie');
    expect(details.similar.length, 2);
    // Highest popularity should appear first
    expect(details.similar.first.id, 102);
    expect(details.similar.first.title, 'High Pop Similar');
    expect(details.similar.first.imdbId, 'tt0000102');
    expect(details.similar.last.id, 101);

    expect(details.recommendations.length, 3);
    expect(details.recommendations.first.id, 102);
    expect(details.recommendations[1].id, 202);
    expect(details.recommendations[1].title, 'Rec Title 2');
    expect(details.recommendations.last.id, 201);

    // Overlapping movie 102 in both similar and recommendations should only
    // trigger a single /movie/102/external_ids request.
    final ext102Calls = dio.requestedPaths
        .where((p) => p.contains('/movie/102/external_ids'))
        .length;
    expect(ext102Calls, 1);
  });

  test('fetchCoreDetails returns immediately without blocking on /external_ids, and bidirectional cache skips /find/', () async {
    final dio = _FakeTmdbClient();
    final repo = TmdbRepository(dio);

    // Phase 1: Core fetch should ONLY call /find/ and /movie/12345
    final core = await repo.fetchCoreDetails('tt1234567');
    expect(core.title, 'Test Movie');
    expect(core.isExternalIdsResolved, isFalse);
    expect(
      dio.requestedPaths.where((p) => p.contains('/external_ids')),
      isEmpty,
    );

    // Phase 2: Background enrichment resolves external IDs and populates bidirectional cache
    final enriched = await repo.enrichExternalIds(core);
    expect(enriched.isExternalIdsResolved, isTrue);
    expect(enriched.similar.first.imdbId, 'tt0000102');

    // Navigating to related item 'tt0000102' should skip /find/tt0000102 entirely!
    dio.requestedPaths.clear();
    final relatedDetails = await repo.fetchCoreDetails('tt0000102');
    expect(relatedDetails.tmdbId, 102);
    expect(relatedDetails.title, 'High Pop Similar');
    expect(dio.requestedPaths.where((p) => p.contains('/find/')), isEmpty);
  });

  test('Series contract: resolves /tv/ metadata, seasons count, and formatted season episodes', () async {
    final dio = _FakeTmdbClient();
    final repo = TmdbRepository(dio);

    final series = await repo.fetchCoreDetails('tt0903747', type: 'series');
    expect(series.mediaType, 'series');
    expect(series.title, 'Breaking Bad');
    expect(series.releaseYear, '2008');
    expect(series.runtimeMinutes, 47);
    expect(series.numberOfSeasons, 3);
    expect(series.seasonsCountLabel, '3');
    expect(series.seasons.length, 1);
    expect(series.seasons.first.seasonNumber, 1);
    expect(series.seasons.first.episodeCount, 8);
    expect(series.seasons.first.displayTitle, 'Season 1');
    expect(series.seasons.first.releaseYear, '2021');
    expect(series.seasons.first.episodesAndYearLabel, '8 episodes \u00A0 2021');

    final season1 = await repo.fetchSeasonDetails(series.tmdbId, 1);
    expect(season1.seasonNumber, 1);
    expect(season1.episodes.length, 1);
    expect(season1.allEpisodes.length, 3);
    expect(season1.episodes.first.name, 'Leavetaking');
    expect(season1.episodes.first.compactRuntimeLabel, '55min');
    expect(season1.episodes.first.formattedAirDate, 'November 18, 2021');
    expect(formatEpisodeAirDate('2021-11-18'), 'November 18, 2021');
    expect(season1.nextEpisodeReleaseDate(), DateTime(2099, 12, 31));

    // As soon as the future episode's release date arrives, it immediately appears in episodes:
    final afterRelease = season1.filterReleased(now: DateTime(2099, 12, 31));
    expect(afterRelease.episodes.length, 2);
    expect(afterRelease.episodes.last.name, 'Future Episode');
  });

  test('User rating classification & My List persistence: >8.0 is Liked, <2.0 is Not for me, <5.0 (e.g. 4.5) is Not for me, >=5.0 is Liked', () async {
    expect(kTmdbLikeRatingValue, greaterThan(8.0));
    expect(kTmdbDislikeRatingValue, lessThan(2.0));
    expect(reactionFromRating(null), TmdbUserReaction.none);
    expect(reactionFromRating(kTmdbLikeRatingValue), TmdbUserReaction.liked);
    expect(reactionFromRating(kTmdbDislikeRatingValue), TmdbUserReaction.disliked);
    // Out-of-range TMDB ratings: < 5.0 (less than half of 10.0, e.g. 4.5) -> disliked ("Not for me")
    expect(reactionFromRating(4.5), TmdbUserReaction.disliked);
    expect(reactionFromRating(3.0), TmdbUserReaction.disliked);
    // Out-of-range TMDB ratings: >= 5.0 -> liked ("Liked")
    expect(reactionFromRating(5.0), TmdbUserReaction.liked);
    expect(reactionFromRating(6.5), TmdbUserReaction.liked);
    expect(reactionFromRating(7.5), TmdbUserReaction.liked);

    final dio = _FakeTmdbClient();
    final repo = TmdbRepository(dio);
    final movie = await repo.fetchCoreDetails('tt1234567');
    expect(movie.userReaction, TmdbUserReaction.none);
    expect(movie.isInMyList, isFalse);

    await repo.setUserRating(
      tmdbId: movie.tmdbId,
      imdbId: movie.imdbId,
      mediaType: movie.mediaType,
      rating: kTmdbLikeRatingValue,
    );
    await repo.setMyList(
      tmdbId: movie.tmdbId,
      imdbId: movie.imdbId,
      mediaType: movie.mediaType,
      inMyList: true,
    );

    final updated = await repo.fetchCoreDetails('tt1234567');
    expect(updated.userRating, kTmdbLikeRatingValue);
    expect(updated.userReaction, TmdbUserReaction.liked);
    expect(updated.isInMyList, isTrue);
  });

  test('TMDB v3 Auth, Watchlist & Ratings Sync, and 10 Standard Catalogs', () async {
    final dio = _FakeTmdbClient();
    final repo = TmdbRepository(dio);

    // 1. Verify 10 interleaved standard catalogs (5 Movie + 5 Series)
    final standardCatalogs = repo.getStandardCatalogs();
    expect(standardCatalogs.length, 10);
    expect(
      standardCatalogs.where((c) => c.type == 'movie').length,
      5,
    );
    expect(
      standardCatalogs.where((c) => c.type == 'series').length,
      5,
    );
    expect(standardCatalogs.first.id, 'tmdb.standard.trending_movie');
    expect(standardCatalogs[1].id, 'tmdb.standard.trending_tv');

    // 2. Verify TMDB v3 authentication flow
    final token = await repo.createRequestToken();
    expect(token, 'req_tok_abc123');
    expect(
      TmdbRepository.buildApprovalUrl(token),
      'https://www.themoviedb.org/authenticate/req_tok_abc123',
    );

    final sessionId = await repo.tryCreateSession(token);
    expect(sessionId, 'test_user_session_999');

    final profile = await repo.fetchAndStoreAccountProfile(sessionId!);
    expect(repo.isAuthenticated, isTrue);
    expect(profile.id, 999);
    expect(profile.username, 'openflix_user');
    expect(profile.displayName, 'OpenFlix Tester');
    expect(profile.avatarUrl, 'https://image.tmdb.org/t/p/w185/avatar_999.jpg');

    // 3. Verify authoritative Watchlist & Ratings sync
    await repo.syncTmdbAccountData();
    final myList = repo.getCachedMyListMetas();
    expect(myList.length, 1);
    expect(myList.first.id, 'tt0000102');
    expect(
      myList.first.poster,
      contains('btttr.cc/poster-a/imdb/poster-default/tt0000102.jpg'),
    );

    final liked = repo.getCachedLikedMetas();
    expect(liked.length, 1);
    expect(liked.first.id, 'tt0000102');

    // Disliked movie (101 with rating 1.5 < 5.0) is filtered out of standard catalogs
    final trendingMovies = await repo.fetchStandardCatalog(standardCatalogs.first);
    expect(trendingMovies.length, 1);
    expect(trendingMovies.first.id, 'tt0000102');
    expect(
      trendingMovies.first.poster,
      contains('btttr.cc/poster-a/imdb/poster-default/tt0000102.jpg'),
    );

    // 4. Verify bidirectional watchlist & rating POST calls include session_id
    dio.postedRatings.clear();
    await repo.setMyList(
      tmdbId: 12345,
      imdbId: 'tt1234567',
      mediaType: 'movie',
      inMyList: true,
    );
    await repo.setUserRating(
      tmdbId: 12345,
      imdbId: 'tt1234567',
      mediaType: 'movie',
      rating: kTmdbLikeRatingValue,
    );
    expect(
      dio.postedRatings.any(
        (p) =>
            (p['path'] as String).contains('/account/999/watchlist') &&
            p['media_id'] == 12345 &&
            p['watchlist'] == true,
      ),
      isTrue,
    );
    expect(
      dio.postedRatings.any(
        (p) =>
            (p['path'] as String).contains('/movie/12345/rating') &&
            p['value'] == kTmdbLikeRatingValue,
      ),
      isTrue,
    );
  });

  group('Anime TMDB sync and reinstall restore', () {
    test('cross-type anime writes resolve authoritative TMDB media_type and keep anime classification', () async {
      final tmpDir = Directory.systemTemp.createTempSync('openflix_anime_cross_');
      addTearDown(() => tmpDir.deleteSync(recursive: true));
      final interactionsFile = File('${tmpDir.path}/interactions.json');

      final dio = _AnimeSyncTmdbClient(
        findResults: {
          // Your Name arrives typed as 'series' (AniList TV/movie overlap), but TMDB /find returns movie_results
          'tt5311514': {
            'movie_results': [
              {'id': 372058}
            ],
            'tv_results': <Map<String, dynamic>>[],
          },
        },
      );
      final idMap = AnimeIdMap()
        ..populate(
          {
            21519: const AnimeIds(imdbId: 'tt5311514', tmdbId: 372058, isMovie: true),
          },
          {
            'imdb:tt5311514': 21519,
            'movie:372058': 21519,
          },
        );
      final repo = TmdbRepository(
        dio,
        interactionsFileOverride: interactionsFile,
        animeIdMap: idMap,
      );
      final session = await repo.tryCreateSession('req_tok');
      await repo.fetchAndStoreAccountProfile(session!);

      const yourNameSeriesMeta = MetaModel(
        id: 'tt5311514',
        type: 'series',
        name: 'Your Name.',
      );
      await repo.setMyList(
        imdbId: 'tt5311514',
        mediaType: 'series',
        inMyList: true,
        isAnime: true,
        meta: yourNameSeriesMeta,
      );
      await repo.setUserRating(
        imdbId: 'tt5311514',
        mediaType: 'series',
        rating: kTmdbLikeRatingValue,
        isAnime: true,
        meta: yourNameSeriesMeta,
      );
      await repo.setUserRating(
        imdbId: 'tt5311514',
        mediaType: 'series',
        rating: kTmdbDislikeRatingValue,
        isAnime: true,
        meta: yourNameSeriesMeta,
      );

      expect(
        dio.postedRequests.any(
          (p) =>
              (p['path'] as String).endsWith('/account/999/watchlist') &&
              p['media_type'] == 'movie' &&
              p['media_id'] == 372058 &&
              p['watchlist'] == true,
        ),
        isTrue,
      );
      expect(
        dio.postedRequests.any(
          (p) =>
              (p['path'] as String).endsWith('/movie/372058/rating') &&
              p['value'] == kTmdbLikeRatingValue,
        ),
        isTrue,
      );
      expect(
        dio.postedRequests.any(
          (p) =>
              (p['path'] as String).endsWith('/movie/372058/rating') &&
              p['value'] == kTmdbDislikeRatingValue,
        ),
        isTrue,
      );
      expect(repo.isMetaAnime(yourNameSeriesMeta), isTrue);
      expect(
        repo.getCachedIsInMyList(tmdbId: 372058, imdbId: 'tt5311514', mediaType: 'movie'),
        isTrue,
      );
      expect(repo.isMetaDisliked(yourNameSeriesMeta), isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 30));
    });

    test('offline or failed anime interactions persist across reload and flush on sync instead of being wiped', () async {
      final tmpDir = Directory.systemTemp.createTempSync('openflix_anime_queue_');
      addTearDown(() => tmpDir.deleteSync(recursive: true));
      final interactionsFile = File('${tmpDir.path}/interactions.json');

      final offlineDio = _AnimeSyncTmdbClient(failWrites: true);
      final idMap = AnimeIdMap()
        ..populate(
          {
            16498: const AnimeIds(imdbId: 'tt2560140', tmdbId: 1429, isMovie: false),
            20: const AnimeIds(imdbId: 'tt0409591', tmdbId: 46260, isMovie: false),
          },
          {
            'imdb:tt2560140': 16498,
            'series:1429': 16498,
            'tv:1429': 16498,
            'imdb:tt0409591': 20,
            'series:46260': 20,
            'tv:46260': 20,
          },
        );

      final repo1 = TmdbRepository(
        offlineDio,
        interactionsFileOverride: interactionsFile,
        animeIdMap: idMap,
      );
      const aotMeta = MetaModel(id: 'tt2560140', type: 'series', name: 'Attack on Titan');
      const narutoMeta = MetaModel(id: 'tt0409591', type: 'series', name: 'Naruto');

      await repo1.setMyList(
        tmdbId: 1429,
        imdbId: 'tt2560140',
        mediaType: 'series',
        inMyList: true,
        isAnime: true,
        meta: aotMeta,
      );
      await repo1.setUserRating(
        tmdbId: 1429,
        imdbId: 'tt2560140',
        mediaType: 'series',
        rating: kTmdbLikeRatingValue,
        isAnime: true,
        meta: aotMeta,
      );
      await repo1.setUserRating(
        tmdbId: 46260,
        imdbId: 'tt0409591',
        mediaType: 'series',
        rating: kTmdbDislikeRatingValue,
        isAnime: true,
        meta: narutoMeta,
      );
      await repo1.flushInteractions();

      // Simulate app restart & reconnect to empty remote TMDB account
      final onlineDio = _AnimeSyncTmdbClient();
      final repo2 = TmdbRepository(
        onlineDio,
        interactionsFileOverride: interactionsFile,
        animeIdMap: idMap,
      );
      await repo2.ensureInteractionsLoaded();
      final session = await repo2.tryCreateSession('req_tok');
      await repo2.fetchAndStoreAccountProfile(session!);
      await repo2.syncTmdbAccountData(animeIdMap: idMap);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(
        onlineDio.postedRequests.any(
          (p) =>
              (p['path'] as String).endsWith('/account/999/watchlist') &&
              p['media_type'] == 'tv' &&
              p['media_id'] == 1429 &&
              p['watchlist'] == true,
        ),
        isTrue,
      );
      expect(
        onlineDio.postedRequests.any(
          (p) =>
              (p['path'] as String).endsWith('/tv/1429/rating') &&
              p['value'] == kTmdbLikeRatingValue,
        ),
        isTrue,
      );
      expect(
        onlineDio.postedRequests.any(
          (p) =>
              (p['path'] as String).endsWith('/tv/46260/rating') &&
              p['value'] == kTmdbDislikeRatingValue,
        ),
        isTrue,
      );
      expect(
        repo2.getCachedIsInMyList(tmdbId: 1429, imdbId: 'tt2560140', mediaType: 'series'),
        isTrue,
      );
      expect(
        repo2.getCachedUserRating(tmdbId: 1429, imdbId: 'tt2560140', mediaType: 'series'),
        kTmdbLikeRatingValue,
      );
      expect(repo2.isMetaDisliked(narutoMeta), isTrue);
      expect(repo2.isMetaAnime(aotMeta), isTrue);
      expect(repo2.isMetaAnime(narutoMeta), isTrue);
    });

    test('reinstall restore via syncTmdbAccountData recovers anime (>6 items), liked, and disliked into Anime row', () async {
      final tmpDir = Directory.systemTemp.createTempSync('openflix_anime_restore_');
      addTearDown(() => tmpDir.deleteSync(recursive: true));
      final freshInteractionsFile = File('${tmpDir.path}/interactions_fresh.json');

      // 8 watchlist TV items where items #1..#7 have no 'Animation' genre_ids from TMDB
      // (testing background >6 classification via AnimeIdMap) and item #8 is Japanese animation,
      // plus 1 non-anime US drama movie, and liked/disliked anime in /rated/*.
      final watchlistTv = <Map<String, dynamic>>[
        for (int i = 1; i <= 7; i++)
          {
            'id': 9000 + i,
            'name': 'Mapped Anime #$i',
            'poster_path': '/a$i.jpg',
            'genre_ids': [10759],
            'original_language': 'ja',
          },
        {
          'id': 9108,
          'name': 'Frieren',
          'poster_path': '/frieren.jpg',
          'genre_ids': [16, 18],
          'original_language': 'ja',
        },
      ];
      final watchlistMovies = <Map<String, dynamic>>[
        {
          'id': 8001,
          'title': 'Western Thriller',
          'poster_path': '/west.jpg',
          'genre_ids': [53],
          'original_language': 'en',
        },
        {
          'id': 372058,
          'title': 'Your Name.',
          'poster_path': '/yn.jpg',
          'genre_ids': [16, 10749],
          'original_language': 'ja',
        },
      ];
      final ratedTv = <Map<String, dynamic>>[
        {
          'id': 9007,
          'name': 'Mapped Anime #7',
          'poster_path': '/a7.jpg',
          'genre_ids': [10759],
          'original_language': 'ja',
          'rating': kTmdbLikeRatingValue,
        },
        {
          'id': 9200,
          'name': 'Disliked Anime',
          'poster_path': '/disliked.jpg',
          'genre_ids': [16],
          'original_language': 'ja',
          'rating': kTmdbDislikeRatingValue,
        },
      ];
      final ratedMovies = <Map<String, dynamic>>[
        {
          'id': 372058,
          'title': 'Your Name.',
          'poster_path': '/yn.jpg',
          'genre_ids': [16, 10749],
          'original_language': 'ja',
          'rating': kTmdbLikeRatingValue,
        },
      ];

      final idMap = AnimeIdMap()
        ..populate(
          {
            70007: const AnimeIds(imdbId: 'tt7000007', tmdbId: 9007, isMovie: false),
          },
          {
            'imdb:tt7000007': 70007,
            'series:9007': 70007,
            'tv:9007': 70007,
          },
        );
      final dio = _AnimeSyncTmdbClient(
        watchlistTv: watchlistTv,
        watchlistMovies: watchlistMovies,
        ratedMovies: ratedMovies,
        ratedTv: ratedTv,
        externalIdsByKey: {
          'tv:9007': 'tt7000007',
          'tv:9108': 'tt22248376',
          'movie:8001': 'tt8000001',
          'movie:372058': 'tt5311514',
          'tv:9200': 'tt9200000',
        },
      );

      final freshRepo = TmdbRepository(
        dio,
        interactionsFileOverride: freshInteractionsFile,
        animeIdMap: idMap,
      );
      final session = await freshRepo.tryCreateSession('req_tok');
      await freshRepo.fetchAndStoreAccountProfile(session!);
      await freshRepo.syncTmdbAccountData(animeIdMap: idMap);
      // Allow background enrichment beyond Wave 1 (>6 items) to finish
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final restoredList = freshRepo.getCachedMyListMetas();
      final frieren = restoredList.firstWhere((m) => m.name == 'Frieren');
      final mappedSeventh = restoredList.firstWhere((m) => m.name == 'Mapped Anime #7');
      final yourName = restoredList.firstWhere((m) => m.name == 'Your Name.');
      final western = restoredList.firstWhere((m) => m.name == 'Western Thriller');

      expect(freshRepo.isMetaAnime(frieren), isTrue);
      expect(freshRepo.isMetaAnime(mappedSeventh), isTrue);
      expect(freshRepo.isMetaAnime(yourName), isTrue);
      expect(freshRepo.isMetaAnime(western), isFalse);

      expect(
        freshRepo.getCachedLikedMetas().any((m) => m.name == 'Mapped Anime #7'),
        isTrue,
      );
      expect(
        freshRepo.getCachedLikedMetas().any((m) => m.name == 'Your Name.'),
        isTrue,
      );
      const dislikedAnime = MetaModel(id: 'tt9200000', type: 'series', name: 'Disliked Anime');
      expect(freshRepo.isMetaDisliked(dislikedAnime), isTrue);
      expect(freshRepo.isMetaAnime(dislikedAnime), isTrue);
    });
  });

  group('User interaction reliability and consistency', () {
    test(
      'fetchCoreDetails preserves local My List entry when account_states returns watchlist: false and updates memo hits live',
      () async {
        final dio = _ReliabilityTmdbDio(
          accountId: 700,
          coreResponses: {
            '/movie/501': {
              'id': 501,
              'imdb_id': 'tt0000501',
              'title': 'Pre-TMDB Saved Film',
              'poster_path': '/p501.jpg',
              'account_states': {'watchlist': false, 'rated': false},
            },
          },
          findResults: {
            'tt0000501': {
              'movie_results': [
                {'id': 501}
              ],
            },
          },
        );
        final repo = TmdbRepository(dio);
        // Save locally before signing in / before TMDB knows about it.
        await repo.setMyList(
          tmdbId: 501,
          imdbId: 'tt0000501',
          mediaType: 'movie',
          inMyList: true,
          meta: const MetaModel(
            id: 'tt0000501',
            type: 'movie',
            name: 'Pre-TMDB Saved Film',
          ),
        );
        await repo.setAuthenticatedSession(
          sessionId: 'sess_700',
          profile: const TmdbAccountProfile(id: 700, username: 'alice'),
        );

        // First open: TMDB says watchlist: false, yet local entry must NOT be deleted.
        final first = await repo.fetchCoreDetails('tt0000501', type: 'movie');
        expect(first.isInMyList, isTrue);
        expect(
          repo.getCachedIsInMyList(
            tmdbId: 501,
            imdbId: 'tt0000501',
            mediaType: 'movie',
          ),
          isTrue,
        );

        // Second open hits _coreMemo and must still report true.
        final second = await repo.fetchCoreDetails('tt0000501', type: 'movie');
        expect(second.isInMyList, isTrue);

        // Explicit removal must immediately reflect in cache AND subsequent memo hits.
        await repo.setMyList(
          tmdbId: 501,
          imdbId: 'tt0000501',
          mediaType: 'movie',
          inMyList: false,
        );
        final third = await repo.fetchCoreDetails('tt0000501', type: 'movie');
        expect(third.isInMyList, isFalse);
      },
    );

    test(
      'confirmed TMDB writes survive lagging account snapshots and lagging account_states inside the confirmation window',
      () async {
        var now = DateTime(2026, 11, 13, 12, 0, 0);
        final dio = _ReliabilityTmdbDio(
          accountId: 701,
          coreResponses: {
            '/movie/601': {
              'id': 601,
              'imdb_id': 'tt0000601',
              'title': 'Eventual Consistency Movie',
              'poster_path': '/p601.jpg',
              // Lagging GET endpoint still reports empty / false after POST 200.
              'account_states': {'watchlist': false, 'rated': false},
            },
          },
          accountStatesResponses: {
            '/movie/601/account_states': {'rated': false, 'watchlist': false},
          },
        );

        final tempDir = await Directory.systemTemp.createTemp('openflix_recent_');
        addTearDown(() => tempDir.delete(recursive: true));
        final file = File('${tempDir.path}/interactions.json');

        final repo = TmdbRepository(
          dio,
          interactionsFileOverride: file,
          clock: () => now,
        );
        await repo.setAuthenticatedSession(
          sessionId: 'sess_701',
          profile: const TmdbAccountProfile(id: 701, username: 'bob'),
        );

        await repo.setMyList(
          tmdbId: 601,
          imdbId: 'tt0000601',
          mediaType: 'movie',
          inMyList: true,
          meta: const MetaModel(
            id: 'tt0000601',
            type: 'movie',
            name: 'Eventual Consistency Movie',
          ),
        );
        await repo.setUserRating(
          tmdbId: 601,
          imdbId: 'tt0000601',
          mediaType: 'movie',
          rating: kTmdbLikeRatingValue,
          meta: const MetaModel(
            id: 'tt0000601',
            type: 'movie',
            name: 'Eventual Consistency Movie',
          ),
        );

        // Immediately sync while TMDB GET snapshot still lags behind the POST 200.
        await repo.syncTmdbAccountData();
        expect(
          repo.getCachedIsInMyList(tmdbId: 601, imdbId: 'tt0000601', mediaType: 'movie'),
          isTrue,
        );
        expect(
          repo.getCachedUserRating(tmdbId: 601, imdbId: 'tt0000601', mediaType: 'movie'),
          kTmdbLikeRatingValue,
        );
        expect(repo.getCachedMyListMetas().map((m) => m.name), contains('Eventual Consistency Movie'));
        expect(repo.getCachedLikedMetas().map((m) => m.name), contains('Eventual Consistency Movie'));

        // DetailScreen fetch & account_states must also respect the confirmation window.
        final core = await repo.fetchCoreDetails('601', type: 'movie');
        expect(core.isInMyList, isTrue);
        expect(core.userRating, kTmdbLikeRatingValue);
        final syncedRating = await repo.syncAccountRatingFromTmdb(
          tmdbId: 601,
          imdbId: 'tt0000601',
          mediaType: 'movie',
        );
        expect(syncedRating, kTmdbLikeRatingValue);

        // Now reverse via explicit remove & unlike while TMDB GET snapshot lags true/8.5.
        dio.watchlistMovies = [
          {'id': 601, 'title': 'Eventual Consistency Movie', 'poster_path': '/p601.jpg'},
        ];
        dio.ratedMovies = [
          {
            'id': 601,
            'title': 'Eventual Consistency Movie',
            'poster_path': '/p601.jpg',
            'rating': kTmdbLikeRatingValue,
          },
        ];
        dio.accountStatesResponses['/movie/601/account_states'] = {
          'watchlist': true,
          'rated': {'value': kTmdbLikeRatingValue},
        };
        await repo.setMyList(
          tmdbId: 601,
          imdbId: 'tt0000601',
          mediaType: 'movie',
          inMyList: false,
        );
        await repo.setUserRating(
          tmdbId: 601,
          imdbId: 'tt0000601',
          mediaType: 'movie',
          rating: null,
        );
        await repo.syncTmdbAccountData();
        expect(
          repo.getCachedIsInMyList(tmdbId: 601, imdbId: 'tt0000601', mediaType: 'movie'),
          isFalse,
        );
        expect(
          repo.getCachedUserRating(tmdbId: 601, imdbId: 'tt0000601', mediaType: 'movie'),
          isNull,
        );

        // Once the confirmation window expires and server catches up cleanly, sync honors server.
        dio.watchlistMovies = const [];
        dio.ratedMovies = [
          {
            'id': 601,
            'title': 'Eventual Consistency Movie',
            'poster_path': '/p601.jpg',
            'rating': 7.5,
          },
        ];
        now = now.add(kTmdbWriteConfirmationWindow + const Duration(seconds: 10));
        await repo.syncTmdbAccountData();
        expect(
          repo.getCachedUserRating(tmdbId: 601, imdbId: 'tt0000601', mediaType: 'movie'),
          7.5,
        );
      },
    );

    test(
      'syncTmdbAccountData fetches beyond 25 pages (>500 items) and queues failed local pushes instead of dropping them',
      () async {
        final dio = _ReliabilityTmdbDio(accountId: 702);
        // Build 27 pages x 20 items = 540 watchlist movies.
        dio.paginatedWatchlistMovies = {
          for (var page = 1; page <= 27; page++)
            page: [
              for (var i = 0; i < 20; i++)
                {
                  'id': (page - 1) * 20 + i + 1,
                  'title': 'Movie ${(page - 1) * 20 + i + 1}',
                  'poster_path': '/p${(page - 1) * 20 + i + 1}.jpg',
                },
            ],
        };

        final repo = TmdbRepository(dio);
        // Save a local offline item (#9001) and fail its initial push while signing in.
        dio.failWrites = true;
        await repo.setMyList(
          tmdbId: 9001,
          mediaType: 'movie',
          inMyList: true,
          meta: const MetaModel(id: '9001', type: 'movie', name: 'Local Unpushed'),
        );
        await repo.setAuthenticatedSession(
          sessionId: 'sess_702',
          profile: const TmdbAccountProfile(id: 702, username: 'carol'),
        );

        await repo.syncTmdbAccountData(pushLocalOnly: true);

        // Item #535 (page 27) AND the failed-to-push local item (#9001) are both present!
        expect(repo.getCachedMyListMetas().length, greaterThanOrEqualTo(541));
        expect(repo.getCachedIsInMyList(tmdbId: 535, mediaType: 'movie'), isTrue);
        expect(repo.getCachedIsInMyList(tmdbId: 9001, mediaType: 'movie'), isTrue);

        // Next sync after network recovers must upload #9001 via pending queue.
        dio.failWrites = false;
        dio.postedRequests.clear();
        await repo.syncTmdbAccountData();
        expect(
          dio.postedRequests.any(
            (p) =>
                (p['path'] as String).endsWith('/account/702/watchlist') &&
                p['media_id'] == 9001 &&
                p['watchlist'] == true,
          ),
          isTrue,
        );
      },
    );

    test(
      'logout preserves Likes, Dislikes, My List across restarts without .bak resurrection and isolates account switching',
      () async {
        final tempDir = await Directory.systemTemp.createTemp('openflix_logout_');
        final file = File('${tempDir.path}/interactions.json');
        final dio = _ReliabilityTmdbDio(accountId: 111);

        final repo1 = TmdbRepository(dio, interactionsFileOverride: file);
        addTearDown(() async {
          await repo1.flushDiskWritesForTesting();
          try {
            await tempDir.delete(recursive: true);
          } catch (_) {}
        });
        await repo1.setAuthenticatedSession(
          sessionId: 'sess_111',
          profile: const TmdbAccountProfile(id: 111, username: 'accountA'),
        );
        await repo1.setMyList(
          tmdbId: 801,
          imdbId: 'tt0000801',
          mediaType: 'movie',
          inMyList: true,
          meta: const MetaModel(id: 'tt0000801', type: 'movie', name: 'Account A Film'),
        );
        await repo1.setUserRating(
          tmdbId: 802,
          imdbId: 'tt0000802',
          mediaType: 'movie',
          rating: kTmdbLikeRatingValue,
          meta: const MetaModel(id: 'tt0000802', type: 'movie', name: 'Account A Liked'),
        );
        await repo1.setUserRating(
          tmdbId: 803,
          imdbId: 'tt0000803',
          mediaType: 'movie',
          rating: kTmdbDislikeRatingValue,
        );
        await repo1.syncTmdbAccountData();

        // Simulate a stale .bak holding an older authenticated session.
        await repo1.logout();
        expect(repo1.isAuthenticated, isFalse);
        expect(repo1.getCachedIsInMyList(tmdbId: 801, imdbId: 'tt0000801', mediaType: 'movie'), isTrue);
        expect(repo1.getCachedUserRating(tmdbId: 802, imdbId: 'tt0000802', mediaType: 'movie'), kTmdbLikeRatingValue);
        expect(repo1.getCachedUserRating(tmdbId: 803, imdbId: 'tt0000803', mediaType: 'movie'), kTmdbDislikeRatingValue);

        // Corrupt primary's sibling check: write a stale session into .bak with higher score
        // and verify valid primary still stays logged out while keeping data.
        final bakFile = File('${file.path}.bak');
        final staleBak = jsonDecode(await bakFile.readAsString()) as Map<String, dynamic>;
        staleBak['userSessionId'] = 'stale_resurrected_session';
        staleBak['persistVersion'] = 0;
        await bakFile.writeAsString(jsonEncode(staleBak), flush: true);

        final repo2 = TmdbRepository(dio, interactionsFileOverride: file);
        await repo2.ensureInteractionsLoaded();
        expect(repo2.isAuthenticated, isFalse);
        expect(repo2.getCachedMyListMetas().map((m) => m.name), contains('Account A Film'));
        expect(repo2.getCachedLikedMetas().map((m) => m.name), contains('Account A Liked'));
        expect(
          repo2.getCachedUserRating(tmdbId: 803, imdbId: 'tt0000803', mediaType: 'movie'),
          kTmdbDislikeRatingValue,
        );

        // Queue one new offline item while disconnected, then sign into a DIFFERENT Account B (#222).
        await repo2.setMyList(
          tmdbId: 804,
          mediaType: 'movie',
          inMyList: true,
          meta: const MetaModel(id: '804', type: 'movie', name: 'Offline Queue Item'),
        );
        dio.accountId = 222;
        dio.watchlistMovies = [
          {'id': 950, 'title': 'Account B Remote', 'poster_path': '/p950.jpg'},
        ];
        dio.ratedMovies = const [];
        dio.postedRequests.clear();
        await repo2.setAuthenticatedSession(
          sessionId: 'sess_222',
          profile: const TmdbAccountProfile(id: 222, username: 'accountB'),
        );
        await repo2.syncTmdbAccountData(pushLocalOnly: true);

        // Offline item (#804) flushes to Account B, Account A's #801/#802/#803 must NOT leak into B!
        expect(
          dio.postedRequests.any((p) => p['media_id'] == 804 && (p['path'] as String).contains('/account/222/watchlist')),
          isTrue,
        );
        expect(
          dio.postedRequests.any((p) => p['media_id'] == 801 || (p['path'] as String).contains('/802/')),
          isFalse,
        );
        expect(repo2.getCachedIsInMyList(tmdbId: 950, mediaType: 'movie'), isTrue);
        await repo2.flushDiskWritesForTesting();
      },
    );

    test(
      'failed initial pushLocalOnly preserves needsLocalPush across restart and syncTmdbAccountData(throwOnError: true) reports failure',
      () async {
        final dir = await Directory.systemTemp.createTemp('tmdb_push_retry_');
        final file = File('${dir.path}/interactions.json');
        final dio = _ReliabilityTmdbDio(accountId: 333);

        // User adds items offline before signing in.
        final repo1 = TmdbRepository(dio, interactionsFileOverride: file);
        TmdbRepository? repo2;
        addTearDown(() async {
          await repo1.flushDiskWritesForTesting();
          await repo2?.flushDiskWritesForTesting();
          try {
            await dir.delete(recursive: true);
          } catch (_) {}
        });
        await repo1.setMyList(
          tmdbId: 901,
          mediaType: 'movie',
          inMyList: true,
          meta: const MetaModel(id: '901', type: 'movie', name: 'Offline Film'),
        );
        await repo1.setUserRating(
          tmdbId: 902,
          mediaType: 'movie',
          rating: kTmdbLikeRatingValue,
          meta: const MetaModel(id: '902', type: 'movie', name: 'Offline Like'),
        );
        expect(repo1.hasPendingSyncOps, isTrue);
        expect(repo1.pendingSyncCount, 2);

        // First post-login sync fails on TMDB account endpoints.
        dio.failAccountReads = true;
        await repo1.setAuthenticatedSession(
          sessionId: 'sess_333',
          profile: const TmdbAccountProfile(id: 333, username: 'account333'),
        );
        await expectLater(
          repo1.syncTmdbAccountData(pushLocalOnly: true, throwOnError: true),
          throwsA(isA<TmdbException>()),
        );
        expect(repo1.lastSyncSucceeded, isFalse);
        expect(repo1.lastSyncError, isNotNull);
        await repo1.flushDiskWritesForTesting();

        // Recreate repository (app restart) and call standard boot sync WITHOUT pushLocalOnly: true.
        dio.failAccountReads = false;
        dio.watchlistMovies = [
          {'id': 909, 'title': 'Remote Item', 'poster_path': '/p909.jpg'},
        ];
        final nextRepo = TmdbRepository(dio, interactionsFileOverride: file);
        repo2 = nextRepo;
        await nextRepo.ensureInteractionsLoaded();
        await nextRepo.syncTmdbAccountData(); // pushLocalOnly defaults to false

        expect(nextRepo.lastSyncSucceeded, isTrue);
        expect(nextRepo.lastSyncError, isNull);
        expect(nextRepo.hasPendingSyncOps, isFalse);
        expect(nextRepo.getCachedIsInMyList(tmdbId: 901, mediaType: 'movie'), isTrue);
        expect(
          nextRepo.getCachedUserRating(tmdbId: 902, mediaType: 'movie'),
          kTmdbLikeRatingValue,
        );
        expect(nextRepo.getCachedIsInMyList(tmdbId: 909, mediaType: 'movie'), isTrue);
        expect(
          dio.postedRequests.any((p) => p['media_id'] == 901),
          isTrue,
        );
        expect(
          dio.postedRequests.any((p) => (p['path'] as String).contains('/movie/902/rating')),
          isTrue,
        );
        await nextRepo.flushDiskWritesForTesting();
      },
    );

    test(
      'AniList-keyed setMyList ensures AnimeIdMap loaded before syncing to TMDB',
      () async {
        final dir = await Directory.systemTemp.createTemp('tmdb_anilist_target_');
        addTearDown(() => dir.delete(recursive: true));
        final file = File('${dir.path}/interactions.json');
        final dio = _ReliabilityTmdbDio(accountId: 444);
        final animeMap = AnimeIdMap()
          ..populate(
            const {
              555: AnimeIds(
                tmdbId: 77555,
                imdbId: 'tt77555',
                isMovie: false,
              ),
            },
            const {},
          );
        final repo = TmdbRepository(
          dio,
          interactionsFileOverride: file,
          animeIdMap: animeMap,
        );
        await repo.setAuthenticatedSession(
          sessionId: 'sess_444',
          profile: const TmdbAccountProfile(id: 444, username: 'animeUser'),
        );
        await repo.setMyList(
          imdbId: 'anilist:555',
          mediaType: 'series',
          inMyList: true,
          meta: const MetaModel(
            id: 'anilist:555',
            type: 'series',
            name: 'Mapped Anime',
          ),
        );
        expect(
          dio.postedRequests.any(
            (p) =>
                p['media_id'] == 77555 &&
                p['media_type'] == 'tv' &&
                p['watchlist'] == true,
          ),
          isTrue,
        );
      },
    );

    test(
      'setUserRating retries with alternate mediaType on 404 / status_code 34 and reconciles caches',
      () async {
        final dir = await Directory.systemTemp.createTemp('tmdb_alt_type_');
        final file = File('${dir.path}/interactions.json');
        final dio = _ReliabilityTmdbDio(
          accountId: 555,
          notFoundPostPaths: {'/tv/888/rating'},
        );
        final repo = TmdbRepository(dio, interactionsFileOverride: file);
        addTearDown(() async {
          await repo.flushDiskWritesForTesting();
          try {
            await dir.delete(recursive: true);
          } catch (_) {}
        });

        await repo.setAuthenticatedSession(
          sessionId: 'sess_555',
          profile: const TmdbAccountProfile(id: 555, username: 'altTypeUser'),
        );

        await repo.setUserRating(
          tmdbId: 888,
          mediaType: 'series',
          rating: kTmdbLikeRatingValue,
          meta: const MetaModel(
            id: '888',
            type: 'series',
            name: 'Misclassified Film',
          ),
        );

        expect(
          dio.postedRequests.any((p) => (p['path'] as String).endsWith('/tv/888/rating')),
          isTrue,
        );
        expect(
          dio.postedRequests.any((p) => (p['path'] as String).endsWith('/movie/888/rating')),
          isTrue,
        );
        expect(repo.hasPendingSyncOps, isFalse);
        expect(
          repo.getCachedUserRating(tmdbId: 888, mediaType: 'movie'),
          kTmdbLikeRatingValue,
        );
        expect(
          repo.getCachedLikedMetas().any(
            (m) => m.name == 'Misclassified Film' && m.type == 'movie',
          ),
          isTrue,
        );
      },
    );

    test(
      'HTTP 401 session expiry sets friendly error, preserves My List & Likes, and backs up cleanly on reconnect + reinstall',
      () async {
        final dir = await Directory.systemTemp.createTemp('tmdb_401_recover_');
        final file = File('${dir.path}/interactions.json');
        final reinstallFile = File('${dir.path}/reinstall_interactions.json');
        final dio = _ReliabilityTmdbDio(
          accountId: 901,
          simulate401: true,
          trackRemoteWrites: true,
        );
        final repo = TmdbRepository(dio, interactionsFileOverride: file);
        addTearDown(() async {
          await repo.flushDiskWritesForTesting();
          try {
            await dir.delete(recursive: true);
          } catch (_) {}
        });

        await repo.setAuthenticatedSession(
          sessionId: 'expired_sess_901',
          profile: const TmdbAccountProfile(id: 901, username: 'expiredUser'),
        );

        await repo.setMyList(
          tmdbId: 101,
          mediaType: 'movie',
          inMyList: true,
          meta: const MetaModel(id: '101', type: 'movie', name: 'Local Saved Film'),
        );
        await repo.setUserRating(
          tmdbId: 202,
          mediaType: 'movie',
          rating: kTmdbLikeRatingValue,
          meta: const MetaModel(id: '202', type: 'movie', name: 'Local Liked Film'),
        );
        await repo.syncTmdbAccountData();

        expect(repo.isSessionExpired, isTrue);
        expect(repo.lastSyncSucceeded, isFalse);
        expect(repo.lastSyncError, isNotNull);
        expect(repo.lastSyncError, isNot(contains('RequestOptions.validateStatus')));
        expect(repo.lastSyncError, isNot(contains('status code of 401')));
        expect(repo.lastSyncError!.toLowerCase(), contains('expired'));
        expect(repo.getCachedIsInMyList(tmdbId: 101, mediaType: 'movie'), isTrue);
        expect(
          repo.getCachedUserRating(tmdbId: 202, mediaType: 'movie'),
          kTmdbLikeRatingValue,
        );

        await repo.prepareSessionReconnect();
        expect(repo.isAuthenticated, isFalse);
        expect(repo.isSessionExpired, isFalse);
        expect(repo.hasPendingSyncOps, isTrue);
        expect(repo.getCachedIsInMyList(tmdbId: 101, mediaType: 'movie'), isTrue);
        expect(
          repo.getCachedUserRating(tmdbId: 202, mediaType: 'movie'),
          kTmdbLikeRatingValue,
        );

        // User approves fresh session on reconnect and pushes preserved data.
        dio.simulate401 = false;
        await repo.setAuthenticatedSession(
          sessionId: 'fresh_sess_901',
          profile: const TmdbAccountProfile(id: 901, username: 'expiredUser'),
        );
        await repo.syncTmdbAccountData(pushLocalOnly: true);

        expect(repo.lastSyncSucceeded, isTrue);
        expect(repo.isSessionExpired, isFalse);
        expect(repo.hasPendingSyncOps, isFalse);
        expect(
          dio.postedRequests.any(
            (p) =>
                (p['path'] as String).endsWith('/account/901/watchlist') &&
                p['media_id'] == 101,
          ),
          isTrue,
        );
        expect(
          dio.postedRequests.any(
            (p) => (p['path'] as String).endsWith('/movie/202/rating'),
          ),
          isTrue,
        );

        // Uninstall + reinstall: brand new repository & empty local storage file.
        final reinstalled = TmdbRepository(dio, interactionsFileOverride: reinstallFile);
        await reinstalled.setAuthenticatedSession(
          sessionId: 'fresh_sess_901',
          profile: const TmdbAccountProfile(id: 901, username: 'expiredUser'),
        );
        await reinstalled.syncTmdbAccountData();

        expect(
          reinstalled.getCachedIsInMyList(tmdbId: 101, mediaType: 'movie'),
          isTrue,
        );
        expect(
          reinstalled.getCachedUserRating(tmdbId: 202, mediaType: 'movie'),
          kTmdbLikeRatingValue,
        );
        await reinstalled.flushDiskWritesForTesting();
      },
    );

    test(
      'Unmapped anilist:<id>, /find miss via AnimeIdMap IMDb lookup, and MOVIE-as-TV-S0 resolve and back up reliably',
      () async {
        final dir = await Directory.systemTemp.createTemp('tmdb_anime_resolve_');
        final file = File('${dir.path}/interactions.json');
        final idMap = AnimeIdMap()
          ..populate(
            const {
              50001: AnimeIds(
                imdbId: 'tt5000100',
                tmdbId: null,
                fallbackTvTmdbId: 9001,
                isMovie: true,
                season: 0,
              ),
              60003: AnimeIds(
                imdbId: 'tt9990001',
                tmdbId: 6603,
                isMovie: false,
              ),
            },
            const {
              'imdb:tt5000100': 50001,
              'imdb:tt9990001': 60003,
              'series:6603': 60003,
            },
          );
        final dio = _ReliabilityTmdbDio(
          accountId: 902,
          trackRemoteWrites: true,
          searchResponses: {
            '/search/movie:Anime Standalone Film': [
              {
                'id': 7701,
                'title': 'Anime Standalone Film',
                'genre_ids': [16, 18],
              },
            ],
            '/search/tv:Brand New Seasonal Anime': [
              {
                'id': 8802,
                'name': 'Brand New Seasonal Anime',
                'genre_ids': [16, 10759],
              },
            ],
          },
        );
        final repo = TmdbRepository(
          dio,
          animeIdMap: idMap,
          interactionsFileOverride: file,
        );
        addTearDown(() async {
          await repo.flushDiskWritesForTesting();
          try {
            await dir.delete(recursive: true);
          } catch (_) {}
        });

        await repo.setAuthenticatedSession(
          sessionId: 'sess_902',
          profile: const TmdbAccountProfile(id: 902, username: 'animeSyncUser'),
        );

        // 1. Anime MOVIE mapped to TV Season 0 with empty /find: finds standalone movie 7701.
        await repo.setMyList(
          imdbId: 'anilist:50001',
          mediaType: 'movie',
          inMyList: true,
          meta: const MetaModel(
            id: 'anilist:50001',
            type: 'movie',
            name: 'Anime Standalone Film',
          ),
        );
        // 2. Brand new anilist:<id> absent from AnimeIdMap: resolves via title search 8802.
        await repo.setUserRating(
          imdbId: 'anilist:50002',
          mediaType: 'series',
          rating: kTmdbLikeRatingValue,
          meta: const MetaModel(
            id: 'anilist:50002',
            type: 'series',
            name: 'Brand New Seasonal Anime',
            releaseInfo: '2026',
          ),
        );
        // 3. tt... where /find returns empty: resolves via AnimeIdMap.lookupByImdbId 6603.
        await repo.setMyList(
          imdbId: 'tt9990001',
          mediaType: 'series',
          inMyList: true,
          meta: const MetaModel(
            id: 'tt9990001',
            type: 'series',
            name: 'IMDb Fallback Show',
          ),
        );

        expect(repo.hasPendingSyncOps, isFalse);
        expect(
          dio.postedRequests.any(
            (p) =>
                (p['path'] as String).endsWith('/account/902/watchlist') &&
                p['media_type'] == 'movie' &&
                p['media_id'] == 7701,
          ),
          isTrue,
        );
        expect(
          dio.postedRequests.any(
            (p) =>
                (p['path'] as String).endsWith('/account/902/watchlist') &&
                p['media_type'] == 'tv' &&
                p['media_id'] == 6603,
          ),
          isTrue,
        );
        expect(
          dio.postedRequests.any(
            (p) => (p['path'] as String).endsWith('/tv/8802/rating'),
          ),
          isTrue,
        );
        // Must NOT have mistakenly added parent TV series 9001 for the movie.
        expect(
          dio.postedRequests.any((p) => p['media_id'] == 9001),
          isFalse,
        );

        await repo.flushDiskWritesForTesting();

        // Reload persisted state from disk: anilist:50002 -> 8802 bridge must persist!
        final repoReloaded = TmdbRepository(
          dio,
          animeIdMap: idMap,
          interactionsFileOverride: file,
        );
        await repoReloaded.ensureInteractionsLoaded();
        expect(
          repoReloaded.getCachedIsInMyList(imdbId: 'anilist:50001', mediaType: 'movie'),
          isTrue,
        );
        expect(
          repoReloaded.getCachedIsInMyList(tmdbId: 7701, mediaType: 'movie'),
          isTrue,
        );
        expect(
          repoReloaded.getCachedUserRating(imdbId: 'anilist:50002', mediaType: 'series'),
          kTmdbLikeRatingValue,
        );
        expect(
          repoReloaded.getCachedUserRating(tmdbId: 8802, mediaType: 'series'),
          kTmdbLikeRatingValue,
        );
      },
    );
  });
}

class _ReliabilityTmdbDio implements Dio {
  _ReliabilityTmdbDio({
    this.accountId = 700,
    this.coreResponses = const {},
    this.findResults = const {},
    this.notFoundPostPaths = const {},
    this.searchResponses = const {},
    this.simulate401 = false,
    this.trackRemoteWrites = false,
    Map<String, Map<String, dynamic>>? accountStatesResponses,
  }) : accountStatesResponses = accountStatesResponses ?? {};

  int accountId;
  bool failWrites = false;
  bool failAccountReads = false;
  bool simulate401 = false;
  final bool trackRemoteWrites;
  final Map<String, Map<String, dynamic>> coreResponses;
  final Map<String, Map<String, dynamic>> findResults;
  final Set<String> notFoundPostPaths;
  final Map<String, List<Map<String, dynamic>>> searchResponses;
  List<Map<String, dynamic>> watchlistMovies = const [];
  List<Map<String, dynamic>> watchlistTv = const [];
  List<Map<String, dynamic>> ratedMovies = const [];
  List<Map<String, dynamic>> ratedTv = const [];
  Map<int, List<Map<String, dynamic>>> paginatedWatchlistMovies = const {};
  final Map<String, Map<String, dynamic>> accountStatesResponses;
  final List<Map<String, dynamic>> postedRequests = [];

  static DioException _unauthorizedException(String path) => DioException(
        requestOptions: RequestOptions(path: path),
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: path),
          statusCode: 401,
          data: const {
            'success': false,
            'status_code': 3,
            'status_message': 'Authentication failed.',
          },
        ),
        type: DioExceptionType.badResponse,
        message:
            'This exception was thrown because the response has a status code of 401 and RequestOptions.validateStatus was configured to throw for this status code.',
      );

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
    if (simulate401) {
      throw _unauthorizedException(path);
    }
    if (failWrites) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        type: DioExceptionType.connectionError,
      );
    }
    final uriPath = Uri.parse(path).path;
    if (data is Map<String, dynamic>) {
      postedRequests.add({'path': uriPath, ...data});
    }
    if (notFoundPostPaths.any(uriPath.endsWith)) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: path),
          statusCode: 404,
          data: {'success': false, 'status_code': 34},
        ),
        type: DioExceptionType.badResponse,
      );
    }
    if (trackRemoteWrites && data is Map<String, dynamic>) {
      if (uriPath.endsWith('/account/$accountId/watchlist')) {
        final mediaId = data['media_id'] as int?;
        final mediaType = data['media_type'] as String?;
        final watch = data['watchlist'] == true;
        if (mediaId != null) {
          final target = mediaType == 'tv'
              ? (watchlistTv = [...watchlistTv])
              : (watchlistMovies = [...watchlistMovies]);
          target.removeWhere((e) => e['id'] == mediaId);
          if (watch) {
            target.add({
              'id': mediaId,
              if (mediaType == 'tv') 'name': 'Item $mediaId' else 'title': 'Item $mediaId',
            });
          }
        }
      } else {
        final ratingMatch = RegExp(r'/(movie|tv)/(\d+)/rating$').firstMatch(uriPath);
        if (ratingMatch != null) {
          final mediaType = ratingMatch.group(1)!;
          final mediaId = int.parse(ratingMatch.group(2)!);
          final score = (data['value'] as num?)?.toDouble();
          if (score != null) {
            final target = mediaType == 'tv'
                ? (ratedTv = [...ratedTv])
                : (ratedMovies = [...ratedMovies]);
            target.removeWhere((e) => e['id'] == mediaId);
            target.add({
              'id': mediaId,
              'rating': score,
              if (mediaType == 'tv') 'name': 'Item $mediaId' else 'title': 'Item $mediaId',
            });
          }
        }
      }
    }
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 201,
      data: {'success': true} as T,
    );
  }

  @override
  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    if (simulate401) {
      throw _unauthorizedException(path);
    }
    if (failWrites) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        type: DioExceptionType.connectionError,
      );
    }
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: {'success': true} as T,
    );
  }

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
    final hasAccountTarget = uriPath.endsWith('/account') || uriPath.contains('/account/');
    if (simulate401 && hasAccountTarget) {
      throw _unauthorizedException(path);
    }
    if (failAccountReads && hasAccountTarget) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        type: DioExceptionType.connectionError,
        message: 'Simulated offline account sync failure',
      );
    }
    if (uriPath.endsWith('/account')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {'id': accountId, 'username': 'user_$accountId'} as T,
      );
    }
    if (uriPath.contains('/account/$accountId/watchlist/movies')) {
      final page = int.tryParse('${queryParameters?['page'] ?? 1}') ?? 1;
      if (paginatedWatchlistMovies.isNotEmpty) {
        return Response<T>(
          requestOptions: RequestOptions(path: path),
          statusCode: 200,
          data: {
            'page': page,
            'total_pages': paginatedWatchlistMovies.length,
            'results': paginatedWatchlistMovies[page] ?? const [],
          } as T,
        );
      }
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {'page': 1, 'total_pages': 1, 'results': watchlistMovies} as T,
      );
    }
    if (uriPath.contains('/account/$accountId/watchlist/tv')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {'page': 1, 'total_pages': 1, 'results': watchlistTv} as T,
      );
    }
    if (uriPath.contains('/account/$accountId/rated/tv')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {'page': 1, 'total_pages': 1, 'results': ratedTv} as T,
      );
    }
    if (uriPath.contains('/account/$accountId/rated/movies')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {'page': 1, 'total_pages': 1, 'results': ratedMovies} as T,
      );
    }
    if (uriPath.contains('/search/')) {
      final query = queryParameters?['query']?.toString() ?? '';
      for (final entry in searchResponses.entries) {
        if (entry.key == '/search/movie:$query' && uriPath.endsWith('/search/movie')) {
          return Response<T>(
            requestOptions: RequestOptions(path: path),
            statusCode: 200,
            data: {'results': entry.value} as T,
          );
        }
        if (entry.key == '/search/tv:$query' && uriPath.endsWith('/search/tv')) {
          return Response<T>(
            requestOptions: RequestOptions(path: path),
            statusCode: 200,
            data: {'results': entry.value} as T,
          );
        }
      }
    }
    if (uriPath.contains('/find/')) {
      final imdb = uriPath.split('/find/').last;
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: (findResults[imdb] ??
            {
              'movie_results': <Map<String, dynamic>>[],
              'tv_results': <Map<String, dynamic>>[],
            }) as T,
      );
    }
    for (final entry in accountStatesResponses.entries) {
      if (uriPath.endsWith(entry.key)) {
        return Response<T>(
          requestOptions: RequestOptions(path: path),
          statusCode: 200,
          data: entry.value as T,
        );
      }
    }
    for (final entry in coreResponses.entries) {
      if (uriPath.endsWith(entry.key)) {
        return Response<T>(
          requestOptions: RequestOptions(path: path),
          statusCode: 200,
          data: entry.value as T,
        );
      }
    }
    final extMatch = RegExp(r'/(movie|tv)/(\d+)/external_ids$').firstMatch(uriPath);
    if (extMatch != null) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {'id': int.parse(extMatch.group(2)!)} as T,
      );
    }
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 404,
      data: <String, dynamic>{} as T,
    );
  }
}

class _AnimeSyncTmdbClient implements Dio {
  _AnimeSyncTmdbClient({
    this.failWrites = false,
    this.findResults = const {},
    this.watchlistMovies = const [],
    this.watchlistTv = const [],
    this.ratedMovies = const [],
    this.ratedTv = const [],
    this.externalIdsByKey = const {},
  });

  final bool failWrites;
  final Map<String, Map<String, dynamic>> findResults;
  final List<Map<String, dynamic>> watchlistMovies;
  final List<Map<String, dynamic>> watchlistTv;
  final List<Map<String, dynamic>> ratedMovies;
  final List<Map<String, dynamic>> ratedTv;
  final Map<String, String> externalIdsByKey;

  final List<Map<String, dynamic>> postedRequests = [];

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
    final uriPath = Uri.parse(path).path;
    if (uriPath.endsWith('/authentication/session/new')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {'success': true, 'session_id': 'test_user_session_999'} as T,
      );
    }
    if (failWrites) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        type: DioExceptionType.connectionError,
      );
    }
    if (data is Map<String, dynamic>) {
      postedRequests.add({'path': uriPath, ...data});
    }
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 201,
      data: {'success': true} as T,
    );
  }

  @override
  Future<Response<T>> delete<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    if (failWrites) {
      throw DioException(
        requestOptions: RequestOptions(path: path),
        type: DioExceptionType.connectionError,
      );
    }
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: {'success': true} as T,
    );
  }

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
    if (uriPath.endsWith('/authentication/token/new')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {'success': true, 'request_token': 'req_tok'} as T,
      );
    }
    if (uriPath.endsWith('/account')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {'id': 999, 'username': 'openflix_user'} as T,
      );
    }
    if (uriPath.contains('/account/999/watchlist/movies')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {'results': watchlistMovies} as T,
      );
    }
    if (uriPath.contains('/account/999/watchlist/tv')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {'results': watchlistTv} as T,
      );
    }
    if (uriPath.contains('/account/999/rated/movies')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {'results': ratedMovies} as T,
      );
    }
    if (uriPath.contains('/account/999/rated/tv')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {'results': ratedTv} as T,
      );
    }
    if (uriPath.contains('/find/')) {
      final imdb = uriPath.split('/find/').last;
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: (findResults[imdb] ??
            {
              'movie_results': <Map<String, dynamic>>[],
              'tv_results': <Map<String, dynamic>>[],
            }) as T,
      );
    }
    final extMatch = RegExp(r'/(movie|tv)/(\d+)/external_ids$').firstMatch(uriPath);
    if (extMatch != null) {
      final res = extMatch.group(1)!;
      final id = extMatch.group(2)!;
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'id': int.parse(id),
          if (externalIdsByKey['$res:$id'] != null)
            'imdb_id': externalIdsByKey['$res:$id'],
        } as T,
      );
    }
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 404,
      data: <String, dynamic>{} as T,
    );
  }
}
