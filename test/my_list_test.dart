import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel/core/theme/app_theme.dart';
import 'package:pixel/features/anime/data/anilist_addon_repository.dart';
import 'package:pixel/features/anime/data/anime_id_map.dart';
import 'package:pixel/features/anime/data/anime_resolver.dart';
import 'package:pixel/features/details/data/tmdb_models.dart';
import 'package:pixel/features/details/data/tmdb_repository.dart';
import 'package:pixel/features/details/presentation/controllers/details_controller.dart';
import 'package:pixel/features/home/data/models/meta_model.dart';
import 'package:pixel/features/home/presentation/widgets/poster_card.dart';
import 'package:pixel/features/home/presentation/widgets/poster_row.dart';
import 'package:pixel/features/my_list/presentation/controllers/my_list_controller.dart';
import 'package:pixel/features/my_list/presentation/screens/my_list_screen.dart';

class _FakeMyListTmdbDio implements Dio {
  final List<Map<String, dynamic>> posted = [];

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
        data: {'success': true, 'session_id': 'sess_mylist_999'} as T,
      );
    }
    if (data is Map<String, dynamic>) {
      posted.add({'path': uriPath, ...data});
    }
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 201,
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
    if (path.contains('/movie/12345')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'id': 12345,
          'imdb_id': 'tt1234567',
          'title': 'Dune: Part Two',
          'poster_path': '/dune2.jpg',
          'overview': 'Paul Atreides unites with Chani and the Fremen.',
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
    if (path.contains('/tv/1396')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'id': 1396,
          'name': 'Breaking Bad',
          'poster_path': '/bb.jpg',
          'external_ids': {'imdb_id': 'tt0903747'},
          'overview': 'Chemistry teacher turns to cooking meth.',
        } as T,
      );
    }
    if (path.endsWith('/account')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {'id': 999, 'username': 'mylist_user'} as T,
      );
    }
    if (path.contains('/find/tt9510000')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'tv_results': [
            {'id': 9510}
          ],
        } as T,
      );
    }
    if (path.contains('/tv/9510')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'id': 9510,
          'name': 'Dandadan',
          'poster_path': '/dandadan.jpg',
          'original_language': 'ja',
          'genres': [
            {'id': 16, 'name': 'Animation'},
          ],
          'external_ids': {'imdb_id': 'tt9510000'},
          'overview': 'Japanese animation series.',
          'account_states': {'watchlist': false, 'rated': false},
        } as T,
      );
    }
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 404,
    );
  }
}

class _FakeAniListDio implements Dio {
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
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: <String, dynamic>{} as T,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('MyListController separates movies and tvShows with Better Poster URLs', () async {
    final repo = TmdbRepository(_FakeMyListTmdbDio());
    final container = ProviderContainer(
      overrides: [
        tmdbRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);

    final notifier = container.read(myListControllerProvider.notifier);

    const movie1 = MetaModel(
      id: 'tt1234567',
      type: 'movie',
      name: 'Dune: Part Two',
      poster: 'https://image.tmdb.org/t/p/w500/dune2.jpg',
    );
    const series1 = MetaModel(
      id: 'tt0903747',
      type: 'series',
      name: 'Breaking Bad',
      poster: 'https://image.tmdb.org/t/p/w500/bb.jpg',
    );
    const anime1 = MetaModel(
      id: 'tt0388629',
      type: 'series',
      name: 'One Piece',
      poster: 'https://image.tmdb.org/t/p/w500/op.jpg',
    );

    await notifier.toggleMeta(movie1);
    await notifier.toggleMeta(series1);
    await notifier.toggleMeta(anime1, isAnime: true);

    final state = container.read(myListControllerProvider);
    expect(state.movies.length, 1);
    expect(state.tvShows.length, 1);
    expect(state.anime.length, 1);

    expect(state.movies.first.name, 'Dune: Part Two');
    expect(
      state.movies.first.poster,
      'https://btttr.cc/poster-a/imdb/poster-default/tt1234567.jpg',
    );
    expect(
      state.movies.first.posterFallback,
      'https://image.tmdb.org/t/p/w500/dune2.jpg',
    );

    expect(state.tvShows.first.name, 'Breaking Bad');
    expect(
      state.tvShows.first.poster,
      'https://btttr.cc/poster-a/imdb/poster-default/tt0903747.jpg',
    );
    expect(
      state.tvShows.first.posterFallback,
      'https://image.tmdb.org/t/p/w500/bb.jpg',
    );

    // Anime item is strictly separated into the Anime row (not in tvShows)
    expect(state.anime.first.name, 'One Piece');
    expect(state.tvShows.any((m) => m.id == 'tt0388629'), isFalse);

    // Removing the movie leaves TV show and Anime
    await notifier.toggleMeta(movie1);
    final afterRemove = container.read(myListControllerProvider);
    expect(afterRemove.movies, isEmpty);
    expect(afterRemove.tvShows.length, 1);
    expect(afterRemove.anime.length, 1);
  });

  testWidgets('MyListScreen renders My List header, Movies first row, TV Shows second row, and Anime third row with shared PosterRow geometry', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repo = TmdbRepository(_FakeMyListTmdbDio());
    await repo.setMyList(
      imdbId: 'tt1234567',
      mediaType: 'movie',
      inMyList: true,
      meta: const MetaModel(id: 'tt1234567', type: 'movie', name: 'Movie A'),
    );
    await repo.setMyList(
      imdbId: 'tt7654321',
      mediaType: 'movie',
      inMyList: true,
      meta: const MetaModel(id: 'tt7654321', type: 'movie', name: 'Movie B'),
    );
    await repo.setMyList(
      imdbId: 'tt0903747',
      mediaType: 'series',
      inMyList: true,
      meta: const MetaModel(id: 'tt0903747', type: 'series', name: 'Series A'),
    );
    await repo.setMyList(
      imdbId: 'tt0388629',
      mediaType: 'series',
      inMyList: true,
      isAnime: true,
      meta: const MetaModel(id: 'tt0388629', type: 'series', name: 'Anime A'),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tmdbRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            body: MyListScreen(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('My List'), findsOneWidget);
    expect(find.text('Search'), findsNothing);
    expect(find.text('Movies'), findsOneWidget);
    expect(find.text('TV Shows'), findsOneWidget);
    expect(find.text('Anime'), findsOneWidget);

    final rows = find.byType(PosterRow);
    expect(rows, findsNWidgets(3));

    // Verify Movies is row 1, TV Shows is row 2, and Anime is row 3
    final firstRowRect = tester.getRect(rows.at(0));
    final secondRowRect = tester.getRect(rows.at(1));
    final thirdRowRect = tester.getRect(rows.at(2));
    expect(firstRowRect.top, lessThan(secondRowRect.top));
    expect(secondRowRect.top, lessThan(thirdRowRect.top));
    expect(secondRowRect.top - firstRowRect.bottom, closeTo(AppDimens.rowSpacing, 0.01));
    expect(thirdRowRect.top - secondRowRect.bottom, closeTo(AppDimens.rowSpacing, 0.01));

    // Verify PosterCard dimensions (113x170) and 8px spacing between posters
    final cards = find.byType(PosterCard);
    expect(cards, findsNWidgets(4));
    final card0 = tester.getRect(cards.at(0));
    final card1 = tester.getRect(cards.at(1));
    expect(card0.size, Size(AppDimens.posterWidth, AppDimens.posterHeight));
    expect(card1.size, Size(AppDimens.posterWidth, AppDimens.posterHeight));
    expect(card1.left - card0.right, closeTo(AppDimens.posterGap, 0.01));
  });

  test('DetailsController detects Japanese Animation and syncs My List, Like, and Dislike to TMDB and Anime row', () async {
    final dio = _FakeMyListTmdbDio();
    final idMap = AnimeIdMap()..populate({}, {});
    final repo = TmdbRepository(dio, animeIdMap: idMap);
    final session = await repo.tryCreateSession('tok');
    await repo.fetchAndStoreAccountProfile(session!);
    final aniListRepo = AniListAddonRepository(
      dio: _FakeAniListDio(),
      resolver: AnimeResolver(animeIdMap: idMap, tmdbDio: dio),
    );

    final container = ProviderContainer(
      overrides: [
        tmdbRepositoryProvider.overrideWithValue(repo),
        animeIdMapProvider.overrideWithValue(idMap),
        aniListAddonRepositoryProvider.overrideWithValue(aniListRepo),
      ],
    );
    addTearDown(container.dispose);

    const key = (id: 'tt9510000', type: 'series');
    const meta = MetaModel(
      id: 'tt9510000',
      type: 'series',
      name: 'Dandadan',
      poster: 'https://image.tmdb.org/t/p/w500/dandadan.jpg',
    );

    // Keep controllers alive while loading & toggling
    final subDetails = container.listen(detailsControllerProvider(key), (_, __) {});
    final subMyList = container.listen(myListControllerProvider, (_, __) {});
    addTearDown(subDetails.close);
    addTearDown(subMyList.close);

    // Wait for initial DetailsController _load to finish
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final loadedDetails = container.read(detailsControllerProvider(key));
    expect(loadedDetails.details?.tmdbId, 9510);
    expect(loadedDetails.isAnime, isTrue);

    final notifier = container.read(detailsControllerProvider(key).notifier);
    await notifier.toggleMyList(meta: meta);
    await notifier.toggleLike(meta: meta);
    await notifier.toggleDislike(meta: meta);

    final myListState = container.read(myListControllerProvider);
    expect(myListState.anime.any((m) => m.name == 'Dandadan'), isTrue);
    expect(myListState.tvShows.any((m) => m.name == 'Dandadan'), isFalse);

    expect(
      dio.posted.any(
        (p) =>
            (p['path'] as String).endsWith('/account/999/watchlist') &&
            p['media_type'] == 'tv' &&
            p['media_id'] == 9510 &&
            p['watchlist'] == true,
      ),
      isTrue,
    );
    expect(
      dio.posted.any(
        (p) =>
            (p['path'] as String).endsWith('/tv/9510/rating') &&
            p['value'] == kTmdbLikeRatingValue,
      ),
      isTrue,
    );
    expect(
      dio.posted.any(
        (p) =>
            (p['path'] as String).endsWith('/tv/9510/rating') &&
            p['value'] == kTmdbDislikeRatingValue,
      ),
      isTrue,
    );
    expect(repo.isMetaAnime(meta), isTrue);
    expect(repo.isMetaDisliked(meta), isTrue);
  });

  test('DetailsController preserves mid-load user My List and Like toggles across Core load and Phase 2 enrichment', () async {
    final dio = _GatedDetailsTmdbDio();
    final idMap = AnimeIdMap()..populate({}, {});
    final repo = TmdbRepository(dio, animeIdMap: idMap);
    final aniListRepo = AniListAddonRepository(
      dio: _FakeAniListDio(),
      resolver: AnimeResolver(animeIdMap: idMap, tmdbDio: dio),
    );

    final container = ProviderContainer(
      overrides: [
        tmdbRepositoryProvider.overrideWithValue(repo),
        animeIdMapProvider.overrideWithValue(idMap),
        aniListAddonRepositoryProvider.overrideWithValue(aniListRepo),
      ],
    );
    addTearDown(container.dispose);

    const key = (id: '12345', type: 'movie');
    const meta = MetaModel(
      id: '12345',
      type: 'movie',
      name: 'Dune: Part Two',
    );
    final sub = container.listen(detailsControllerProvider(key), (_, __) {});
    addTearDown(sub.close);

    // Wait for Phase 1 network request to stall at the gate before completing.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final notifier = container.read(detailsControllerProvider(key).notifier);

    // User toggles My List and Like BEFORE Phase 1 returns stale false values.
    await notifier.toggleMyList(meta: meta);
    await notifier.toggleLike(meta: meta);
    expect(container.read(detailsControllerProvider(key)).isInMyList, isTrue);
    expect(
      container.read(detailsControllerProvider(key)).userReaction,
      TmdbUserReaction.liked,
    );

    // Release Phase 1 (which reports watchlist: false, rated: false) and Phase 2.
    dio.coreGate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 30));

    final afterPhase1 = container.read(detailsControllerProvider(key));
    expect(afterPhase1.isInMyList, isTrue);
    expect(afterPhase1.userReaction, TmdbUserReaction.liked);

    // Now test the opposite: open a second title where Phase 2 enrichment is gated,
    // unlike & remove after Phase 1 loads, then release Phase 2 -> must stay cleared.
    const key2 = (id: '12346', type: 'movie');
    const meta2 = MetaModel(
      id: '12346',
      type: 'movie',
      name: 'Gated Enrichment Film',
    );
    final sub2 = container.listen(detailsControllerProvider(key2), (_, __) {});
    addTearDown(sub2.close);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(container.read(detailsControllerProvider(key2)).isInMyList, isTrue);
    expect(
      container.read(detailsControllerProvider(key2)).userReaction,
      TmdbUserReaction.liked,
    );

    final notifier2 = container.read(detailsControllerProvider(key2).notifier);
    await notifier2.toggleMyList(meta: meta2);
    await notifier2.toggleLike(meta: meta2);
    dio.enrichmentGate.complete();
    await Future<void>.delayed(const Duration(milliseconds: 30));

    final afterPhase2 = container.read(detailsControllerProvider(key2));
    expect(afterPhase2.isInMyList, isFalse);
    expect(afterPhase2.userReaction, TmdbUserReaction.none);
    expect(afterPhase2.userRating, isNull);
  });
}

class _GatedDetailsTmdbDio extends _FakeMyListTmdbDio {
  final Completer<void> coreGate = Completer<void>();
  final Completer<void> enrichmentGate = Completer<void>();

  @override
  Future<Response<T>> get<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    if (path.contains('/movie/12345')) {
      await coreGate.future;
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'id': 12345,
          'imdb_id': 'tt1234567',
          'title': 'Dune: Part Two',
          'poster_path': '/dune2.jpg',
          'account_states': {'watchlist': false, 'rated': false},
        } as T,
      );
    }
    if (path.contains('/movie/12346')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'id': 12346,
          'imdb_id': 'tt1234600',
          'title': 'Gated Enrichment Film',
          'poster_path': '/gated.jpg',
          'recommendations': {
            'results': [
              {
                'id': 777,
                'title': 'Related Film',
                'poster_path': '/rel.jpg',
                'release_date': '2024-01-01',
              },
            ],
          },
          'account_states': {
            'watchlist': true,
            'rated': {'value': kTmdbLikeRatingValue},
          },
        } as T,
      );
    }
    if (path.contains('/movie/777/external_ids')) {
      await enrichmentGate.future;
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {'id': 777, 'imdb_id': 'tt0000777'} as T,
      );
    }
    return super.get<T>(
      path,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
      onReceiveProgress: onReceiveProgress,
    );
  }
}
