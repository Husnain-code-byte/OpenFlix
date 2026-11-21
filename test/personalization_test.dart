import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel/core/perf/snap_physics.dart';
import 'package:pixel/core/theme/app_theme.dart';
import 'package:pixel/features/anime/data/anilist_addon_repository.dart';
import 'package:pixel/features/anime/data/anime_id_map.dart';
import 'package:pixel/features/anime/data/anime_resolver.dart';
import 'package:pixel/features/details/data/tmdb_repository.dart';
import 'package:pixel/features/home/data/models/manifest_model.dart';
import 'package:pixel/features/home/data/models/meta_model.dart';
import 'package:pixel/features/home/presentation/controllers/home_controller.dart';
import 'package:pixel/features/home/presentation/widgets/hero_banner.dart';
import 'package:pixel/features/home/presentation/widgets/pixel_bottom_nav.dart';
import 'package:pixel/features/home/presentation/widgets/poster_card.dart';
import 'package:pixel/features/home/presentation/widgets/poster_row.dart';
import 'package:pixel/features/personalization/data/personalization_repository.dart';
import 'package:pixel/features/personalization/data/personalized_slots.dart';
import 'package:pixel/features/personalization/presentation/widgets/clean_notch_engine.dart';
import 'package:pixel/features/personalization/presentation/widgets/personalized_shelf.dart';

class _FakePersonalizationTmdbDio implements Dio {
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
    // Strict textless poster + English logo with aspect_ratio
    if (path.contains('/movie/101/images')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'posters': [
            {
              'file_path': '/textless_101.jpg',
              'iso_639_1': null,
              'vote_average': 8.5,
              'vote_count': 20,
            },
            {
              'file_path': '/en_poster_101.jpg',
              'iso_639_1': 'en',
              'vote_average': 9.0,
              'vote_count': 40,
            },
          ],
          'backdrops': [
            {
              'file_path': '/clean_backdrop_101.jpg',
              'iso_639_1': null,
              'vote_average': 8.0,
              'vote_count': 15,
            },
          ],
          'logos': [
            {
              'file_path': '/logo_101.png',
              'iso_639_1': 'en',
              'aspect_ratio': 3.6,
              'vote_average': 8.0,
              'vote_count': 10,
            },
          ],
        } as T,
      );
    }

    // Only English text-bearing posters (no iso_639_1 == null textless poster)
    if (path.contains('/movie/102/images')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'posters': [
            {
              'file_path': '/en_with_text_102.jpg',
              'iso_639_1': 'en',
              'vote_average': 9.0,
              'vote_count': 50,
            },
          ],
          'backdrops': const [],
          'logos': const [],
        } as T,
      );
    }

    // Textless poster on page 2
    if (path.contains('/movie/103/images')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'posters': [
            {
              'file_path': '/textless_103.jpg',
              'iso_639_1': null,
              'vote_average': 8.4,
              'vote_count': 18,
            },
          ],
          'backdrops': const [],
          'logos': const [],
        } as T,
      );
    }

    if (path.endsWith('/movie/500')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'id': 500,
          'title': 'Source Movie',
          'poster_path': '/source.jpg',
          'backdrop_path': '/source_bg.jpg',
          'recommendations': {
            'results': [
              {
                'id': 101,
                'title': 'Genuine Recommendation 1',
                'poster_path': '/rec1.jpg',
                'backdrop_path': '/rec1_bg.jpg',
                'release_date': '2024-02-01',
                'popularity': 80.0,
                'vote_average': 8.2,
                'vote_count': 500,
                'genre_ids': [878, 18],
                'media_type': 'movie',
              },
            ],
          },
          'similar': {
            'results': [
              {
                'id': 999,
                'title': 'Unrelated Similar Slop',
                'poster_path': '/slop.jpg',
                'backdrop_path': '/slop_bg.jpg',
                'release_date': '2024-02-01',
                'popularity': 9999.0,
                'vote_average': 9.5,
                'vote_count': 9000,
                'media_type': 'movie',
              },
            ],
          },
        } as T,
      );
    }

    if (path.endsWith('/movie/500/recommendations')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'results': [
            {
              'id': 102,
              'title': 'English Text Poster Movie',
              'poster_path': '/rec2.jpg',
              'backdrop_path': '/rec2_bg.jpg',
              'release_date': '2024-03-01',
              'popularity': 70.0,
              'vote_average': 7.9,
              'vote_count': 300,
              'genre_ids': [18],
              'media_type': 'movie',
            },
            {
              'id': 103,
              'title': 'Genuine Recommendation Page 2',
              'poster_path': '/rec3.jpg',
              'backdrop_path': '/rec3_bg.jpg',
              'release_date': '2024-04-01',
              'popularity': 68.0,
              'vote_average': 8.4,
              'vote_count': 280,
              'genre_ids': [53, 80],
              'media_type': 'movie',
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
  test('mergeFeedEntries places 4 personalized rows at 1-indexed slots 2, 5, 8, 11 with 2 catalogs between each', () {
    final catalogs = [
      for (var i = 1; i <= 10; i++)
        CatalogItemModel(id: 'cat_$i', type: 'movie', name: 'Catalog $i'),
    ];

    const item = MetaModel(id: 'tt1111111', type: 'movie', name: 'Sample');
    final pRows = [
      const PersonalizedRowData(
        bucket: PersonalizationBucket.likedMovie,
        sourceMeta: MetaModel(id: 'tt0001', type: 'movie', name: 'Inception'),
        items: [item],
      ),
      const PersonalizedRowData(
        bucket: PersonalizationBucket.myListMovie,
        sourceMeta: MetaModel(id: 'tt0002', type: 'movie', name: 'The Terminal List'),
        items: [item],
      ),
      const PersonalizedRowData(
        bucket: PersonalizationBucket.likedSeries,
        sourceMeta: MetaModel(id: 'tt0003', type: 'series', name: 'Severance'),
        items: [item],
      ),
      const PersonalizedRowData(
        bucket: PersonalizationBucket.myListSeries,
        sourceMeta: MetaModel(id: 'tt0004', type: 'series', name: 'Dark'),
        items: [item],
      ),
    ];

    final merged = mergeFeedEntries(
      catalogs: catalogs,
      personalizedRows: pRows,
      slotPositions: PersonalizedSlots.homePositions,
    );

    // 10 catalogs + 4 personalized rows = 14 feed entries
    expect(merged.length, 14);

    // 1-indexed positions 2, 5, 8, 11 -> 0-indexed 1, 4, 7, 10
    expect(merged[0], isA<CatalogFeedEntry>());
    expect(merged[1], isA<PersonalizedFeedEntry>());
    expect(
      (merged[1] as PersonalizedFeedEntry).row.bucket,
      PersonalizationBucket.likedMovie,
    );

    expect(merged[2], isA<CatalogFeedEntry>());
    expect(merged[3], isA<CatalogFeedEntry>());
    expect(merged[4], isA<PersonalizedFeedEntry>());
    expect(
      (merged[4] as PersonalizedFeedEntry).row.bucket,
      PersonalizationBucket.myListMovie,
    );

    expect(merged[5], isA<CatalogFeedEntry>());
    expect(merged[6], isA<CatalogFeedEntry>());
    expect(merged[7], isA<PersonalizedFeedEntry>());
    expect(
      (merged[7] as PersonalizedFeedEntry).row.bucket,
      PersonalizationBucket.likedSeries,
    );

    expect(merged[8], isA<CatalogFeedEntry>());
    expect(merged[9], isA<CatalogFeedEntry>());
    expect(merged[10], isA<PersonalizedFeedEntry>());
    expect(
      (merged[10] as PersonalizedFeedEntry).row.bucket,
      PersonalizationBucket.myListSeries,
    );
  });

  test('Daily pick stays stable on the same day, avoids repeating yesterday when >1 candidate exists, and separates Anime', () async {
    final tmdbRepo = TmdbRepository(_FakePersonalizationTmdbDio());
    final animeIdMap = AnimeIdMap()..populate(const {}, const {});
    final aniListRepo = AniListAddonRepository(
      dio: _FakePersonalizationTmdbDio(),
      resolver: AnimeResolver(
        animeIdMap: animeIdMap,
        tmdbDio: _FakePersonalizationTmdbDio(),
      ),
    );
    final personalizationRepo = PersonalizationRepository(
      tmdbRepo: tmdbRepo,
      aniListRepo: aniListRepo,
      animeIdMap: animeIdMap,
    );

    await tmdbRepo.setUserRating(
      imdbId: 'tt0816692',
      mediaType: 'movie',
      rating: 8.5,
      meta: const MetaModel(id: 'tt0816692', type: 'movie', name: 'Interstellar'),
    );
    await tmdbRepo.setUserRating(
      imdbId: 'tt1375666',
      mediaType: 'movie',
      rating: 8.5,
      meta: const MetaModel(id: 'tt1375666', type: 'movie', name: 'Inception'),
    );
    // Anime movie should NOT appear in likedMovie candidates
    await tmdbRepo.setUserRating(
      imdbId: 'tt5311514',
      mediaType: 'movie',
      rating: 8.5,
      isAnime: true,
      meta: const MetaModel(id: 'tt5311514', type: 'movie', name: 'Your Name'),
    );

    final movieCandidates =
        personalizationRepo.candidatesForBucket(PersonalizationBucket.likedMovie);
    expect(movieCandidates.map((m) => m.name), containsAll(['Interstellar', 'Inception']));
    expect(movieCandidates.any((m) => m.name == 'Your Name'), isFalse);

    final animeCandidates =
        personalizationRepo.candidatesForBucket(PersonalizationBucket.likedAnime);
    expect(animeCandidates.map((m) => m.name), ['Your Name']);

    final day1 = DateTime(2026, 10, 31, 10);
    final pick1 = await personalizationRepo.pickDailySource(
      PersonalizationBucket.likedMovie,
      now: day1,
    );
    final pick1Again = await personalizationRepo.pickDailySource(
      PersonalizationBucket.likedMovie,
      now: day1,
    );
    expect(pick1, isNotNull);
    expect(pick1Again?.id, pick1?.id);

    // Next day with 2 candidates should rotate away from yesterday's pick
    final day2 = DateTime(2026, 11, 1, 10);
    final pick2 = await personalizationRepo.pickDailySource(
      PersonalizationBucket.likedMovie,
      now: day2,
    );
    expect(pick2, isNotNull);
    expect(pick2?.id, isNot(equals(pick1?.id)));
  });

  test('fetchPersonalizedCardArtwork strictly requires iso_639_1 == null for tallPosterUrl and extracts logo aspect_ratio', () async {
    final tmdbRepo = TmdbRepository(_FakePersonalizationTmdbDio());

    final art101 = await tmdbRepo.fetchPersonalizedCardArtwork(101, 'movie');
    expect(art101.tallPosterUrl, 'https://image.tmdb.org/t/p/w500/textless_101.jpg');
    expect(art101.landscapeBackdropUrl, 'https://image.tmdb.org/t/p/w780/clean_backdrop_101.jpg');
    expect(art101.logoUrl, 'https://image.tmdb.org/t/p/w500/logo_101.png');
    expect(art101.logoAspectRatio, 3.6);

    // Movie 102 only has an English poster with baked-in text -> tallPosterUrl must be null, standardPosterUrl populated
    final art102 = await tmdbRepo.fetchPersonalizedCardArtwork(102, 'movie');
    expect(art102.tallPosterUrl, isNull);
    expect(art102.standardPosterUrl, 'https://image.tmdb.org/t/p/w500/en_with_text_102.jpg');
  });

  testWidgets('PersonalizedShelf renders standard 113x170 normal PosterCards for both Liked and My List rows with 8px poster gap', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const likedRow = PersonalizedRowData(
      bucket: PersonalizationBucket.likedMovie,
      sourceMeta: MetaModel(id: 'tt1375666', type: 'movie', name: 'Inception'),
      items: [
        MetaModel(
          id: 'tt001',
          type: 'movie',
          name: 'Do Not Disturb: Lady Boss in Disguise',
          genres: ['Drama', 'Sci-Fi'],
          imdbRating: '8.2',
        ),
        MetaModel(
          id: 'tt002',
          type: 'movie',
          name: 'Shutter Island',
          genres: ['Drama', 'Thriller', 'Mystery'],
          imdbRating: '8.4',
        ),
      ],
    );

    const myListRow = PersonalizedRowData(
      bucket: PersonalizationBucket.myListMovie,
      sourceMeta: MetaModel(id: 'tt0816692', type: 'movie', name: 'Interstellar'),
      items: [
        MetaModel(
          id: 'tt003',
          type: 'movie',
          name: 'The Terminal List',
          genres: ['Action', 'Drama'],
          imdbRating: '7.9',
        ),
        MetaModel(
          id: 'tt004',
          type: 'movie',
          name: 'Ali G: Who Iz I?',
          genres: ['Comedy'],
          imdbRating: '7.4',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: ListView(
            children: [
              PersonalizedShelf(row: likedRow, onTapMeta: (_) {}),
              PersonalizedShelf(row: myListRow, onTapMeta: (_) {}),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Because you liked Inception'), findsOneWidget);
    expect(find.text('Because you added Interstellar to your list'), findsOneWidget);

    expect(find.byType(PersonalizedTallCard), findsNothing);
    expect(find.byType(PersonalizedLandscapeCard), findsNothing);

    final cards = find.byType(PosterCard);
    expect(cards, findsNWidgets(4));
    final c0 = tester.getRect(cards.at(0));
    final c1 = tester.getRect(cards.at(1));
    final c2 = tester.getRect(cards.at(2));
    final c3 = tester.getRect(cards.at(3));
    expect(c0.size, Size(AppDimens.posterWidth, AppDimens.posterHeight));
    expect(c2.size, Size(AppDimens.posterWidth, AppDimens.posterHeight));
    expect(c1.left - c0.right, closeTo(AppDimens.posterGap, 0.01));
    expect(c3.left - c2.right, closeTo(AppDimens.posterGap, 0.01));
  });

  test('fetchBucketRecommendations strictly uses /recommendations (including page 2) with standard posters and never includes /similar titles', () async {
    final tmdbRepo = TmdbRepository(_FakePersonalizationTmdbDio());
    final animeIdMap = AnimeIdMap()..populate(const {}, const {});
    final aniListRepo = AniListAddonRepository(
      dio: _FakePersonalizationTmdbDio(),
      resolver: AnimeResolver(
        animeIdMap: animeIdMap,
        tmdbDio: _FakePersonalizationTmdbDio(),
      ),
    );
    final personalizationRepo = PersonalizationRepository(
      tmdbRepo: tmdbRepo,
      aniListRepo: aniListRepo,
      animeIdMap: animeIdMap,
    );

    final results = await personalizationRepo.fetchRecommendationsForSource(
      bucket: PersonalizationBucket.likedMovie,
      sourceMeta: const MetaModel(id: '500', type: 'movie', name: 'Source Movie'),
      seenIds: <String>{},
    );

    final names = results.map((m) => m.name).toList();
    expect(names, [
      'Genuine Recommendation 1',
      'English Text Poster Movie',
      'Genuine Recommendation Page 2',
    ]);
    expect(names, isNot(contains('Unrelated Similar Slop')));
    for (final item in results) {
      expect(item.poster, isNotNull);
    }
    expect(results.first.genres, contains('Sci-Fi'));
  });

  test('Daily personalized row snapshot persists across app restarts and stays locked until next calendar day', () async {
    final tempDir = await Directory.systemTemp.createTemp('openflix_daily_row_');
    addTearDown(() => tempDir.delete(recursive: true));
    final file = File('${tempDir.path}/openflix_user_interactions_v1.json');

    final day1 = DateTime(2026, 11, 21, 9, 0);
    final day2 = DateTime(2026, 11, 22, 9, 0);

    // Session 1: Save Liked movies + lock today's daily row snapshot to disk
    final tmdb1 = TmdbRepository(_FakePersonalizationTmdbDio(), interactionsFileOverride: file);
    final animeMap = AnimeIdMap()..populate(const {}, const {});
    final aniList = AniListAddonRepository(
      dio: _FakePersonalizationTmdbDio(),
      resolver: AnimeResolver(
        animeIdMap: animeMap,
        tmdbDio: _FakePersonalizationTmdbDio(),
      ),
    );
    final repo1 = PersonalizationRepository(
      tmdbRepo: tmdb1,
      aniListRepo: aniList,
      animeIdMap: animeMap,
    );

    const seed = MetaModel(
      id: 'tt0500',
      type: 'movie',
      name: 'Source Movie',
      genres: ['Sci-Fi'],
    );
    await tmdb1.setUserRating(
      tmdbId: 500,
      imdbId: 'tt0500',
      mediaType: 'movie',
      rating: 9.0,
      meta: seed,
    );
    await tmdb1.setUserRating(
      tmdbId: 501,
      imdbId: 'tt0501',
      mediaType: 'movie',
      rating: 9.0,
      meta: const MetaModel(
        id: 'tt0501',
        type: 'movie',
        name: 'Other Liked Movie',
        genres: ['Drama'],
      ),
    );
    final pickedDay1 = await repo1.pickDailySource(
      PersonalizationBucket.likedMovie,
      now: day1,
    );
    expect(pickedDay1, isNotNull);

    const lockedItems = [
      MetaModel(id: '101', type: 'movie', name: 'Locked Rec 1', poster: 'https://img/101.jpg'),
      MetaModel(id: '102', type: 'movie', name: 'Locked Rec 2', poster: 'https://img/102.jpg'),
    ];
    await repo1.saveDailyRow(
      PersonalizationBucket.likedMovie,
      sourceMeta: pickedDay1!,
      items: lockedItems,
      now: day1,
    );
    await tmdb1.flushDiskWritesForTesting();

    // Session 2 (cold restart on the SAME day): Must restore the exact source + exact ordered items
    final tmdb2 = TmdbRepository(_FakePersonalizationTmdbDio(), interactionsFileOverride: file);
    await tmdb2.ensureInteractionsLoaded();
    final repo2 = PersonalizationRepository(
      tmdbRepo: tmdb2,
      aniListRepo: aniList,
      animeIdMap: animeMap,
    );

    final restoredSameDay = repo2.getPersistedDailyRow(
      PersonalizationBucket.likedMovie,
      now: day1,
    );
    expect(restoredSameDay, isNotNull);
    expect(restoredSameDay!.sourceMeta.id, pickedDay1.id);
    expect(restoredSameDay.items.map((m) => m.id).toList(), ['101', '102']);

    final repickedSameDay = await repo2.pickDailySource(
      PersonalizationBucket.likedMovie,
      now: day1,
    );
    expect(repickedSameDay?.id, pickedDay1.id);

    // Next calendar day: Persisted snapshot expires and daily source rotates away from yesterday
    final expiredNextDay = repo2.getPersistedDailyRow(
      PersonalizationBucket.likedMovie,
      now: day2,
    );
    expect(expiredNextDay, isNull);

    final pickedNextDay = await repo2.pickDailySource(
      PersonalizationBucket.likedMovie,
      now: day2,
    );
    expect(pickedNextDay?.id, isNot(equals(pickedDay1.id)));
  });

  testWidgets('PersonalizedShelf and PosterRow reset horizontal scroll offset to 0 when switching HomeFilter or PixelTab', (tester) async {
    await tester.binding.setSurfaceSize(const Size(393, 852));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final items = [
      for (var i = 1; i <= 12; i++)
        MetaModel(id: 'tt000$i', type: 'series', name: 'Anime Title $i'),
    ];
    final row = PersonalizedRowData(
      bucket: PersonalizationBucket.likedAnime,
      sourceMeta: const MetaModel(id: 'tt9999', type: 'series', name: 'Attack on Titan'),
      items: items,
    );

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: ListView(
              children: [
                PersonalizedShelf(row: row, onTapMeta: (_) {}),
                PosterRow(title: 'Catalog Row', metas: items, onTapMeta: (_) {}),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final listViews = find.byWidgetPredicate(
      (w) => w is ListView && w.scrollDirection == Axis.horizontal,
    );
    expect(listViews, findsNWidgets(2));

    // Scroll the PersonalizedShelf horizontally
    await tester.drag(listViews.at(0), const Offset(-400, 0));
    await tester.pumpAndSettle();
    final personalizedScrollable = tester.state<ScrollableState>(
      find.descendant(of: listViews.at(0), matching: find.byType(Scrollable)),
    );
    expect(personalizedScrollable.position.pixels, greaterThan(100));

    // Switch HomeFilter (e.g., Anime -> Movies) -> row scroll must reset to 0.0
    container.read(homeFilterProvider.notifier).state = HomeFilter.movies;
    await tester.pump();
    expect(personalizedScrollable.position.pixels, 0.0);

    // Scroll again, then switch bottom tab (Home -> My List) -> row scroll must reset to 0.0
    await tester.drag(listViews.at(0), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(personalizedScrollable.position.pixels, greaterThan(100));

    container.read(activeTabProvider.notifier).state = PixelTab.myList;
    await tester.pump();
    expect(personalizedScrollable.position.pixels, 0.0);
  });

  test('CleanNotchEngine 3-pass poster pipeline and logo alpha-trim + contrast rescue execute accurately', () async {
    // Create a synthetic bright white bottom poster to test Pass 1 (frost), Pass 2 (bleed levelling), and Pass 3 (tint)
    final posterRecorder = ui.PictureRecorder();
    final posterCanvas = Canvas(posterRecorder);
    posterCanvas.drawRect(
      const Rect.fromLTWH(0, 0, 200, 300),
      Paint()..color = const Color(0xFF1E5AA8),
    );
    posterCanvas.drawRect(
      const Rect.fromLTWH(0, 150, 200, 150),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    final rawPoster = await posterRecorder.endRecording().toImage(200, 300);

    final processedPoster = await CleanNotchEngine.processPoster(
      cacheKey: 'test_poster_1',
      rawImage: rawPoster,
    );
    expect(processedPoster, isNotNull);
    expect(processedPoster!.image.width, CleanNotchEngine.canvasWidth);
    expect(processedPoster.image.height, CleanNotchEngine.canvasHeight);
    // Bright white bottom half is successfully levelled and tinted down from 1.0
    expect(processedPoster.bgLum, lessThan(0.50));

    final processedLandscape = await CleanNotchEngine.processPoster(
      cacheKey: 'test_landscape_1',
      rawImage: rawPoster,
      isLandscape: true,
    );
    expect(processedLandscape, isNotNull);
    expect(processedLandscape!.image.width, CleanNotchEngine.canvasLandscapeWidth);
    expect(processedLandscape.image.height, CleanNotchEngine.canvasLandscapeHeight);
    expect(processedLandscape.bgLum, lessThan(0.50));
    expect(processedLandscape.notchColor.a, greaterThan(0.8));
    expect(CleanNotchEngine.metadataFontWeight, FontWeight.w500);

    final landscapeLogoSize = CleanNotchEngine.computeLogoTargetSize(
      cardWidth: PersonalizedSlots.landscapeWidth,
      cardHeight: PersonalizedSlots.landscapeHeight,
      aspectRatio: 3.6,
      isLandscape: true,
    );
    expect(landscapeLogoSize.width, lessThanOrEqualTo(PersonalizedSlots.landscapeWidth * 0.62 + 0.01));
    expect(landscapeLogoSize.height, lessThanOrEqualTo(PersonalizedSlots.landscapeHeight * 0.26 + 0.01));

    // Create a 100x60 logo with 20px transparent margins around a 60x20 dark-on-dark core
    final logoRecorder = ui.PictureRecorder();
    final logoCanvas = Canvas(logoRecorder);
    logoCanvas.drawRect(
      const Rect.fromLTWH(20, 20, 60, 20),
      Paint()..color = const Color(0xFF08080A),
    );
    final rawLogo = await logoRecorder.endRecording().toImage(100, 60);

    final processedLogo = await CleanNotchEngine.processLogo(
      cacheKey: 'test_logo_1',
      rawLogo: rawLogo,
      bgR: 16.0,
      bgG: 20.0,
      bgB: 30.0,
      bgLum: 0.08,
    );
    expect(processedLogo, isNotNull);
    expect(processedLogo!.image.width, 60);
    expect(processedLogo.image.height, 20);
    expect(processedLogo.aspectRatio, closeTo(3.0, 0.01));

    // Verify dark-on-dark logo was contrast-rescued to pure white (255, 255, 255)
    final logoBytes = await processedLogo.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(logoBytes!.getUint8(0), 255);
    expect(logoBytes.getUint8(1), 255);
    expect(logoBytes.getUint8(2), 255);
  });

  test('TmdbRepository interaction persistence never wipes My List, Likes, or Dislikes on pre-load writes or corrupted primary file', () async {
    final tempDir = await Directory.systemTemp.createTemp('openflix_persist_test_');
    addTearDown(() => tempDir.delete(recursive: true));
    final file = File('${tempDir.path}/openflix_user_interactions_v1.json');

    // 1. Session 1: Save My List item, Liked item, and Disliked item
    final repo1 = TmdbRepository(_FakePersonalizationTmdbDio(), interactionsFileOverride: file);
    await repo1.setMyList(
      tmdbId: 101,
      imdbId: 'tt0101',
      mediaType: 'movie',
      inMyList: true,
      meta: const MetaModel(id: 'tt0101', type: 'movie', name: 'My List Movie'),
    );
    await repo1.setUserRating(
      tmdbId: 202,
      imdbId: 'tt0202',
      mediaType: 'movie',
      rating: 8.5,
      meta: const MetaModel(id: 'tt0202', type: 'movie', name: 'Liked Movie'),
    );
    await repo1.setUserRating(
      tmdbId: 303,
      imdbId: 'tt0303',
      mediaType: 'movie',
      rating: 1.0,
      meta: const MetaModel(id: 'tt0303', type: 'movie', name: 'Disliked Movie'),
    );
    // Wait for queued atomic write to complete
    await repo1.flushInteractions();
    expect(await file.exists(), isTrue);
    expect(await File('${file.path}.bak').exists(), isTrue);

    // 2. Session 2: Call markAsAnime BEFORE ensureInteractionsLoaded() completes
    // (previously this overwrote the disk file with empty state!).
    final repo2 = TmdbRepository(_FakePersonalizationTmdbDio(), interactionsFileOverride: file);
    repo2.markAsAnime(tmdbId: 999, mediaType: 'series', anilistId: 12345);
    await repo2.flushInteractions();
    await repo2.ensureInteractionsLoaded();

    expect(repo2.getCachedMyListMetas().map((m) => m.name), contains('My List Movie'));
    expect(repo2.getCachedLikedMetas().map((m) => m.name), contains('Liked Movie'));
    expect(
      repo2.isMetaDisliked(const MetaModel(id: 'tt0303', type: 'movie', name: 'Disliked Movie')),
      isTrue,
    );

    // 3. Session 3: Simulate truncated/corrupted primary JSON file -> must auto-recover from .bak
    await file.writeAsString('{corrupted_partial_json', flush: true);
    final repo3 = TmdbRepository(_FakePersonalizationTmdbDio(), interactionsFileOverride: file);
    await repo3.ensureInteractionsLoaded();

    expect(repo3.getCachedMyListMetas().map((m) => m.name), contains('My List Movie'));
    expect(repo3.getCachedLikedMetas().map((m) => m.name), contains('Liked Movie'));
    expect(
      repo3.isMetaDisliked(const MetaModel(id: 'tt0303', type: 'movie', name: 'Disliked Movie')),
      isTrue,
    );
  });

  test('PosterSnapPhysics advances forward on light/medium swipes on wider 184px tall poster stride without snapping back', () {
    final physics = PosterSnapPhysics(itemExtent: PersonalizedSlots.tallStride); // 184.0
    final metrics = FixedScrollMetrics(
      minScrollExtent: 0.0,
      maxScrollExtent: 1840.0,
      pixels: 20.0,
      viewportDimension: 393.0,
      axisDirection: AxisDirection.right,
      devicePixelRatio: 3.0,
    );

    // A light/medium forward flick (260 px/s) that previously rounded back to 0.0
    // must advance to at least the next tall card boundary (184.0).
    final simForward = physics.createBallisticSimulation(metrics, 260.0);
    expect(simForward, isNotNull);
    expect(simForward!.x(2.0), closeTo(PersonalizedSlots.tallStride, 1.0));

    // A light/medium backward flick (-260 px/s) from 200.0 must step back to 184.0 / 0.0
    final metricsBack = FixedScrollMetrics(
      minScrollExtent: 0.0,
      maxScrollExtent: 1840.0,
      pixels: 170.0,
      viewportDimension: 393.0,
      axisDirection: AxisDirection.right,
      devicePixelRatio: 3.0,
    );
    final simBackward = physics.createBallisticSimulation(metricsBack, -260.0);
    expect(simBackward, isNotNull);
    expect(simBackward!.x(2.0), closeTo(0.0, 1.0));
  });

  test('TMDB Categories interleaves Movie and Series rows strictly (1 movie, 1 series) and populates Hero pool with both', () async {
    final repo = TmdbRepository(_FakePersonalizationTmdbDio());
    final catalogs = await repo.fetchCategoryCatalogs();
    expect(catalogs.length, greaterThanOrEqualTo(32));

    // Verify strict alternating pattern: movie, series, movie, series...
    for (var i = 0; i < 32; i++) {
      final expectedType = i.isEven ? 'movie' : 'series';
      expect(catalogs[i].type, expectedType, reason: 'Index $i should be $expectedType');
      expect(catalogMatchesFilter(catalogs[i], HomeFilter.categories), isTrue);
      expect(catalogMatchesFilter(catalogs[i], HomeFilter.home), isFalse);
      expect(catalogMatchesFilter(catalogs[i], HomeFilter.movies), isFalse);
      expect(catalogMatchesFilter(catalogs[i], HomeFilter.tvShows), isFalse);
    }

    // Verify Hero pool built from interleaved category shelves contains both movies and series
    final heroPool = buildHeroPool([
      const [
        MetaModel(id: 'tt_m1', type: 'movie', name: 'Action Movie 1', poster: 'https://img/m1.jpg'),
      ],
      const [
        MetaModel(id: 'tt_s1', type: 'series', name: 'Action Series 1', poster: 'https://img/s1.jpg'),
      ],
      const [
        MetaModel(id: 'tt_m2', type: 'movie', name: 'Comedy Movie 1', poster: 'https://img/m2.jpg'),
      ],
      const [
        MetaModel(id: 'tt_s2', type: 'series', name: 'Comedy Series 1', poster: 'https://img/s2.jpg'),
      ],
    ], 4);
    expect(heroPool.map((m) => m.type).toList(), ['movie', 'series', 'movie', 'series']);
  });

  test('CleanNotchEngine.processHeroPoster applies the identical 3-pass Tall/Landscape pipeline on Hero images', () async {
    const posterW = 300;
    const posterH = 450;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    // Vivid blue artwork upper region + bright white lower band
    canvas.drawRect(
      Rect.fromLTWH(0, 0, posterW.toDouble(), posterH * 0.72),
      Paint()..color = const Color(0xFF1E5AA8),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, posterH * 0.72, posterW.toDouble(), posterH * 0.28),
      Paint()..color = const Color(0xFFF5F5F5),
    );
    final rawPoster = await recorder.endRecording().toImage(posterW, posterH);
    addTearDown(rawPoster.dispose);

    final processed = await CleanNotchEngine.processHeroPoster(
      cacheKey: 'test_hero_blue_1',
      rawImage: rawPoster,
      aspectRatio: posterW / posterH,
    );
    expect(processed, isNotNull);
    expect(CleanNotchEngine.getCachedPoster('test_hero_blue_1'), same(processed));
    expect(processed!.bgB, greaterThan(processed.bgR));
    expect(processed.bgLum, lessThan(0.50));

    final img = processed.image;
    expect(img.width, posterW);
    expect(img.height, posterH);
    final rgba = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(rgba, isNotNull);

    // Top row must keep original crisp artwork pixels untouched (0x1E, 0x5A, 0xA8, 255)
    final topMidOff = ((img.width ~/ 2) * 4);
    expect(rgba!.getUint8(topMidOff), 0x1E);
    expect(rgba.getUint8(topMidOff + 1), 0x5A);
    expect(rgba.getUint8(topMidOff + 2), 0xA8);
    expect(rgba.getUint8(topMidOff + 3), 255);

    // Bottom row must carry dominant blue chromatic tint and levelled contrast
    final bottomMidOff = ((img.height - 1) * img.width + (img.width ~/ 2)) * 4;
    final botR = rgba.getUint8(bottomMidOff);
    final botG = rgba.getUint8(bottomMidOff + 1);
    final botB = rgba.getUint8(bottomMidOff + 2);
    final botA = rgba.getUint8(bottomMidOff + 3);
    final botLum = (0.2126 * botR + 0.7152 * botG + 0.0722 * botB) / 255.0;
    expect(botA, 255);
    expect(botB, greaterThan(botR));
    expect(botLum, lessThan(0.35));
  });

  testWidgets('HeroBanner renders cleanly with fallback bottom vignette before image processing', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SizedBox(
              height: 620,
              child: HeroBanner(
                items: const [
                  MetaModel(
                    id: 'local_hero_test',
                    type: 'movie',
                    name: 'Hero Color Test',
                    genres: ['Sci-Fi', 'Thriller'],
                    releaseInfo: '2025',
                    runtime: '2h 5m',
                  ),
                ],
                onPlay: (_) {},
                onMyList: (_) {},
                onOpen: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('HERO COLOR'), findsOneWidget);
    expect(find.text('TEST'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('My List'), findsOneWidget);
  });
}
