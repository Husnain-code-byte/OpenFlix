import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel/features/anime/data/anilist_addon_repository.dart';
import 'package:pixel/features/anime/data/anime_id_map.dart';
import 'package:pixel/features/anime/data/anime_resolver.dart';
import 'package:pixel/features/details/data/tmdb_models.dart';
import 'package:pixel/features/details/data/tmdb_repository.dart';
import 'package:pixel/features/home/data/models/meta_model.dart';
import 'package:pixel/features/personalization/data/personalization_repository.dart';
import 'package:pixel/features/personalization/data/personalized_slots.dart';
import 'package:pixel/features/personalization/data/recommendation_scoring_engine.dart';

class _FakeHybridEngineDio implements Dio {
  final List<String> requestedPaths = [];
  final Map<String, Map<String, dynamic>?> discoverQueries = {};

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
    requestedPaths.add(path);

    if (path.endsWith('/movie/500')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'id': 500,
          'imdb_id': 'tt0500500',
          'title': 'Inception',
          'release_date': '2010-07-16',
          'original_language': 'en',
          'genres': [
            {'id': 878, 'name': 'Sci-Fi'},
            {'id': 53, 'name': 'Thriller'},
          ],
          'keywords': {
            'keywords': [
              {'id': 4565, 'name': 'dystopia'},
              {'id': 9715, 'name': 'dream'},
            ],
          },
          'recommendations': {
            'results': [
              {
                'id': 601,
                'title': 'Pre-2012 Slop Movie',
                'poster_path': '/601.jpg',
                'backdrop_path': '/601_bg.jpg',
                'release_date': '1996-03-10',
                'original_language': 'en',
                'popularity': 180.0,
                'vote_average': 5.9,
                'vote_count': 95,
                'genre_ids': [53],
                'media_type': 'movie',
              },
              {
                'id': 602,
                'title': 'John Wick: Chapter 2',
                'poster_path': '/602.jpg',
                'backdrop_path': '/602_bg.jpg',
                'release_date': '2017-02-10',
                'original_language': 'en',
                'popularity': 110.0,
                'vote_average': 7.5,
                'vote_count': 12000,
                'genre_ids': [28, 53],
                'media_type': 'movie',
              },
              {
                'id': 603,
                'title': 'John Wick: Chapter 3 - Parabellum',
                'poster_path': '/603.jpg',
                'backdrop_path': '/603_bg.jpg',
                'release_date': '2019-05-17',
                'original_language': 'en',
                'popularity': 105.0,
                'vote_average': 7.4,
                'vote_count': 10000,
                'genre_ids': [28, 53],
                'media_type': 'movie',
              },
              {
                'id': 604,
                'title': 'Interstellar',
                'poster_path': '/604.jpg',
                'backdrop_path': '/604_bg.jpg',
                'release_date': '2014-11-07',
                'original_language': 'en',
                'popularity': 120.0,
                'vote_average': 8.4,
                'vote_count': 34000,
                'genre_ids': [878, 18],
                'media_type': 'movie',
              },
            ],
          },
          'similar': {'results': const []},
        } as T,
      );
    }

    if (path.endsWith('/movie/500/recommendations')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {'results': const []} as T,
      );
    }

    if (path.endsWith('/movie/602/recommendations') ||
        path.endsWith('/movie/604/recommendations')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'results': [
            {
              'id': 701,
              'title': 'Arrival',
              'poster_path': '/701.jpg',
              'backdrop_path': '/701_bg.jpg',
              'release_date': '2016-11-11',
              'original_language': 'en',
              'popularity': 85.0,
              'vote_average': 7.6,
              'vote_count': 17000,
              'genre_ids': [878, 18, 9648],
              'media_type': 'movie',
            },
          ],
        } as T,
      );
    }

    if (path.endsWith('/discover/movie')) {
      discoverQueries[path] = queryParameters;
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'results': [
            {
              'id': 701,
              'title': 'Arrival',
              'poster_path': '/701.jpg',
              'backdrop_path': '/701_bg.jpg',
              'release_date': '2016-11-11',
              'original_language': 'en',
              'popularity': 85.0,
              'vote_average': 7.6,
              'vote_count': 17000,
              'genre_ids': [878, 18, 9648],
            },
            {
              'id': 702,
              'title': 'Ex Machina',
              'poster_path': '/702.jpg',
              'backdrop_path': '/702_bg.jpg',
              'release_date': '2015-04-24',
              'original_language': 'en',
              'popularity': 70.0,
              'vote_average': 7.7,
              'vote_count': 13000,
              'genre_ids': [878, 53],
            },
          ],
        } as T,
      );
    }

    if (path.contains('/images')) {
      return Response<T>(
        requestOptions: RequestOptions(path: path),
        statusCode: 200,
        data: {
          'posters': [
            {
              'file_path': '/textless_poster.jpg',
              'iso_639_1': null,
              'vote_average': 8.0,
              'vote_count': 10,
            },
          ],
          'backdrops': [
            {
              'file_path': '/backdrop.jpg',
              'iso_639_1': null,
              'vote_average': 8.0,
              'vote_count': 10,
            },
          ],
          'logos': const [],
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
      data: {
        'data': {
          'Media': {
            'title': {'english': 'Attack on Titan', 'romaji': 'Shingeki no Kyojin'},
            'seasonYear': 2013,
            'genres': ['Action', 'Drama'],
            'tags': [
              {'name': 'Survival', 'rank': 90, 'isMediaSpoiler': false},
              {'name': 'Military', 'rank': 85, 'isMediaSpoiler': false},
            ],
            'recommendations': {
              'nodes': [
                {
                  'rating': 45,
                  'mediaRecommendation': {
                    'id': 2001,
                    'title': {'english': 'Vinland Saga', 'romaji': 'Vinland Saga'},
                    'format': 'TV',
                    'seasonYear': 2019,
                    'genres': ['Action', 'Adventure', 'Drama'],
                    'averageScore': 87,
                    'popularity': 250000,
                    'isAdult': false,
                    'bannerImage': 'https://img/vinland_banner.jpg',
                    'coverImage': {'extraLarge': 'https://img/vinland.jpg'},
                    'tags': [
                      {'name': 'Military', 'rank': 82, 'isMediaSpoiler': false},
                    ],
                    'recommendations': {
                      'nodes': [
                        {
                          'rating': 50,
                          'mediaRecommendation': {
                            'id': 2003,
                            'title': {'english': '86 EIGHTY-SIX', 'romaji': '86'},
                            'format': 'TV',
                            'seasonYear': 2021,
                            'genres': ['Action', 'Drama', 'Sci-Fi'],
                            'averageScore': 83,
                            'popularity': 210000,
                            'isAdult': false,
                            'bannerImage': 'https://img/86_banner.jpg',
                            'coverImage': {'extraLarge': 'https://img/86.jpg'},
                          },
                        },
                      ],
                    },
                  },
                },
                {
                  'rating': 30,
                  'mediaRecommendation': {
                    'id': 2002,
                    'title': {'english': 'Vinland Saga Season 2', 'romaji': 'Vinland Saga Season 2'},
                    'format': 'TV',
                    'seasonYear': 2023,
                    'genres': ['Action', 'Drama'],
                    'averageScore': 88,
                    'popularity': 180000,
                    'isAdult': false,
                    'bannerImage': 'https://img/vinland2_banner.jpg',
                    'coverImage': {'extraLarge': 'https://img/vinland2.jpg'},
                  },
                },
                {
                  'rating': 20,
                  'mediaRecommendation': {
                    'id': 2004,
                    'title': {'english': 'Old Slop OVA', 'romaji': 'Old Slop OVA'},
                    'format': 'TV',
                    'seasonYear': 1994,
                    'genres': ['Action'],
                    'averageScore': 59,
                    'popularity': 5000,
                    'isAdult': false,
                    'bannerImage': 'https://img/slop_banner.jpg',
                    'coverImage': {'extraLarge': 'https://img/slop.jpg'},
                  },
                },
              ],
            },
          },
        },
      } as T,
    );
  }
}

void main() {
  test('Modern-First + Iconic Classics Gate rejects old low-vote slop and preserves classics & modern hits', () {
    const oldSlop = TmdbRecommendation(
      id: 1,
      title: '1996 Obscure Sequel',
      releaseYear: 1996,
      voteAverage: 6.1,
      voteCount: 90,
      popularity: 120.0,
    );
    const iconicClassic = TmdbRecommendation(
      id: 2,
      title: 'The Matrix',
      releaseYear: 1999,
      voteAverage: 8.7,
      voteCount: 24000,
      popularity: 75.0,
    );
    const modernHit = TmdbRecommendation(
      id: 3,
      title: 'Dune: Part Two',
      releaseYear: 2024,
      voteAverage: 8.2,
      voteCount: 4500,
      popularity: 95.0,
    );
    const eraMatchedPick = TmdbRecommendation(
      id: 4,
      title: 'Minority Report',
      releaseYear: 2002,
      voteAverage: 7.4,
      voteCount: 8500,
      popularity: 40.0,
    );

    expect(
      RecommendationScoringEngine.passesModernOrClassicGate(oldSlop, currentYear: 2026),
      isFalse,
    );
    expect(
      RecommendationScoringEngine.passesModernOrClassicGate(iconicClassic, currentYear: 2026),
      isTrue,
    );
    expect(
      RecommendationScoringEngine.passesModernOrClassicGate(modernHit, currentYear: 2026),
      isTrue,
    );
    // Era-matched pick only passes when seed itself is pre-2012.
    expect(
      RecommendationScoringEngine.passesModernOrClassicGate(
        eraMatchedPick,
        seedReleaseYear: 2020,
        currentYear: 2026,
      ),
      isFalse,
    );
    expect(
      RecommendationScoringEngine.passesModernOrClassicGate(
        eraMatchedPick,
        seedReleaseYear: 1999,
        currentYear: 2026,
      ),
      isTrue,
    );
  });

  test('2-Hop Graph Bridge co-occurrence + Discover boost elevates genuine matches over 1-hop noise', () {
    final candidates = [
      CandidateSignalData(
        item: const TmdbRecommendation(
          id: 10,
          title: 'Single Hop Mild Match',
          releaseYear: 2021,
          voteAverage: 7.1,
          voteCount: 1200,
          popularity: 72.0,
          genres: ['Sci-Fi'],
          originalLanguage: 'en',
        ),
        hop1Rank: 3,
      ),
      CandidateSignalData(
        item: const TmdbRecommendation(
          id: 11,
          title: 'Multi-Bridge Consensus Hit',
          releaseYear: 2021,
          voteAverage: 7.8,
          voteCount: 4000,
          popularity: 68.0,
          genres: ['Sci-Fi', 'Thriller'],
          originalLanguage: 'en',
        ),
        hop1Rank: 4,
        hop2BridgeCount: 2,
        hop2BestRankScore: 0.9,
        fromDiscover: true,
      ),
    ];

    final ranked = RecommendationScoringEngine.rankCandidates(
      candidates: candidates,
      seedTitle: 'Inception',
      seedGenres: const ['Sci-Fi', 'Thriller'],
      seedReleaseYear: 2010,
      seedOriginalLanguage: 'en',
      tasteProfile: const UserTasteProfile(),
      currentYear: 2026,
    );

    expect(ranked.first.title, 'Multi-Bridge Consensus Hit');
  });

  test('65% Seed / 35% User Taste Profile boosts matching taste genres and penalizes Disliked genres', () {
    final taste = UserTasteProfile.fromInteractions(
      likedMetas: const [
        MetaModel(
          id: 'tt1',
          type: 'movie',
          name: 'Blade Runner 2049',
          genres: ['Sci-Fi', 'Mystery'],
          releaseInfo: '2017',
        ),
      ],
      myListMetas: const [
        MetaModel(
          id: 'tt2',
          type: 'movie',
          name: 'Ex Machina',
          genres: ['Sci-Fi', 'Thriller'],
          releaseInfo: '2015',
        ),
      ],
      dislikedGenreCounts: const {'Horror': 2},
      isAnime: false,
    );

    final candidates = [
      CandidateSignalData(
        item: const TmdbRecommendation(
          id: 20,
          title: 'Horror Thriller',
          releaseYear: 2022,
          voteAverage: 7.6,
          voteCount: 3000,
          popularity: 85.0,
          genres: ['Horror', 'Thriller'],
          originalLanguage: 'en',
        ),
        hop1Rank: 0,
      ),
      CandidateSignalData(
        item: const TmdbRecommendation(
          id: 21,
          title: 'Sci-Fi Mystery Fit',
          releaseYear: 2022,
          voteAverage: 7.6,
          voteCount: 3000,
          popularity: 82.0,
          genres: ['Sci-Fi', 'Mystery'],
          originalLanguage: 'en',
        ),
        hop1Rank: 1,
      ),
    ];

    final ranked = RecommendationScoringEngine.rankCandidates(
      candidates: candidates,
      seedTitle: 'Arrival',
      seedGenres: const ['Thriller', 'Mystery'],
      seedReleaseYear: 2016,
      seedOriginalLanguage: 'en',
      tasteProfile: taste,
      currentYear: 2026,
    );

    expect(ranked.first.title, 'Sci-Fi Mystery Fit');
  });

  test('Franchise Stem Cap limits sequels to max 1 per franchise and excludes seed franchise duplicates', () {
    final candidates = [
      for (final entry in const [
        (id: 1, title: 'Dune: Part Two', pop: 90.0), // shares seed stem
        (id: 2, title: 'John Wick: Chapter 2', pop: 88.0),
        (id: 3, title: 'John Wick: Chapter 3 - Parabellum', pop: 86.0),
        (id: 4, title: 'John Wick: Chapter 4', pop: 84.0),
        (id: 5, title: 'Mad Max: Fury Road', pop: 82.0),
        (id: 6, title: 'Edge of Tomorrow', pop: 80.0),
        (id: 7, title: 'The Batman', pop: 78.0),
      ])
        CandidateSignalData(
          item: TmdbRecommendation(
            id: entry.id,
            title: entry.title,
            releaseYear: 2022,
            voteAverage: 7.9,
            voteCount: 5000,
            popularity: entry.pop,
            genres: const ['Action', 'Sci-Fi'],
          ),
          hop1Rank: entry.id - 1,
        ),
    ];

    final ranked = RecommendationScoringEngine.rankCandidates(
      candidates: candidates,
      seedTitle: 'Dune',
      seedGenres: const ['Action', 'Sci-Fi'],
      seedReleaseYear: 2021,
      tasteProfile: const UserTasteProfile(),
      currentYear: 2026,
    );

    final titles = ranked.map((r) => r.title).toList();
    expect(titles, isNot(contains('Dune: Part Two')));
    final johnWickCount = titles.where((t) => t.startsWith('John Wick')).length;
    expect(johnWickCount, 1);
    expect(titles, containsAll(['Mad Max: Fury Road', 'Edge of Tomorrow', 'The Batman']));
  });

  test('Smart Daily Seed Rotation favors recent high-affinity titles without repeating yesterday or paired bucket', () {
    final taste = UserTasteProfile.fromInteractions(
      likedMetas: const [
        MetaModel(id: 'tt1', type: 'movie', name: 'New Favorite', genres: ['Sci-Fi'], imdbRating: '8.8'),
        MetaModel(id: 'tt2', type: 'movie', name: 'Strong Match', genres: ['Sci-Fi'], imdbRating: '8.5'),
        MetaModel(id: 'tt3', type: 'movie', name: 'Decent Pick', genres: ['Sci-Fi'], imdbRating: '8.1'),
        MetaModel(id: 'tt4', type: 'movie', name: 'Older Unrelated', genres: ['Comedy'], imdbRating: '6.0'),
      ],
      myListMetas: const [],
      isAnime: false,
    );

    const candidates = [
      MetaModel(id: 'tt1', type: 'movie', name: 'New Favorite', genres: ['Sci-Fi'], imdbRating: '8.8'),
      MetaModel(id: 'tt2', type: 'movie', name: 'Strong Match', genres: ['Sci-Fi'], imdbRating: '8.5'),
      MetaModel(id: 'tt3', type: 'movie', name: 'Decent Pick', genres: ['Sci-Fi'], imdbRating: '8.1'),
      MetaModel(id: 'tt4', type: 'movie', name: 'Older Unrelated', genres: ['Comedy'], imdbRating: '6.0'),
      MetaModel(id: 'tt5', type: 'movie', name: 'Lowest Tier', genres: ['Drama'], imdbRating: '5.5'),
    ];

    final chosen = RecommendationScoringEngine.selectSmartDailySeed(
      candidates: candidates,
      tasteProfile: taste,
      dateKey: '2026-11-14',
      bucketKey: 'liked_movie',
      yesterdayId: 'tt1',
      avoidSourceId: 'tt2',
    );

    expect(chosen.id, isNot('tt1'));
    expect(chosen.id, isNot('tt2'));
    expect(chosen.id, 'tt3');
  });

  test('PersonalizationRepository executes 2-Hop + /discover + Franchise Cap end-to-end', () async {
    final dio = _FakeHybridEngineDio();
    final tmdbRepo = TmdbRepository(dio);
    final animeIdMap = AnimeIdMap()..populate(const {}, const {});
    final aniListRepo = AniListAddonRepository(
      dio: dio,
      resolver: AnimeResolver(animeIdMap: animeIdMap, tmdbDio: dio),
    );
    final repo = PersonalizationRepository(
      tmdbRepo: tmdbRepo,
      aniListRepo: aniListRepo,
      animeIdMap: animeIdMap,
    );

    final items = await repo.fetchRecommendationsForSource(
      bucket: PersonalizationBucket.likedMovie,
      sourceMeta: const MetaModel(id: '500', type: 'movie', name: 'Inception'),
      seenIds: <String>{},
    );

    final names = items.map((m) => m.name).toList();
    // Slop excluded by Modern-First Gate; Arrival discovered via Hop-2 + /discover;
    // Ex Machina from /discover; only 1 John Wick sequel kept.
    expect(names, isNot(contains('Pre-2012 Slop Movie')));
    expect(names, containsAll(['Interstellar', 'Arrival', 'Ex Machina']));
    expect(names.where((n) => n.startsWith('John Wick')).length, 1);
    expect(
      dio.requestedPaths.any((p) => p.endsWith('/discover/movie')),
      isTrue,
    );
    expect(
      dio.requestedPaths.any((p) => p.endsWith('/movie/604/recommendations')),
      isTrue,
    );
  });

  test('AniList 2-Hop GraphQL upgrade scores Hop-2 consensus and deduplicates anime franchises', () async {
    final dio = _FakeHybridEngineDio();
    final animeIdMap = AnimeIdMap()
      ..populate(const {
        2001: AnimeIds(tmdbId: 88801, isMovie: false),
        2002: AnimeIds(tmdbId: 88802, isMovie: false),
        2003: AnimeIds(tmdbId: 88803, isMovie: false),
        2004: AnimeIds(tmdbId: 88804, isMovie: false),
      }, const {});

    final aniListRepo = AniListAddonRepository(
      dio: dio,
      resolver: AnimeResolver(animeIdMap: animeIdMap, tmdbDio: dio),
    );

    final recs = await aniListRepo.fetchRecommendations(16498);
    final names = recs.map((m) => m.name).toList();

    expect(names, contains('Vinland Saga'));
    expect(names, contains('86 EIGHTY-SIX'));
    expect(names, isNot(contains('Vinland Saga Season 2')));
    expect(names, isNot(contains('Old Slop OVA')));
  });
}
