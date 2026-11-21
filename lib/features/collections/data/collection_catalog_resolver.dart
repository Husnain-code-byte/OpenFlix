import 'package:equatable/equatable.dart';

import '../../anime/data/anilist_addon_repository.dart';
import '../../details/data/tmdb_repository.dart';
import 'collection_models.dart';

/// Media type filter tabs on the Collection Details screen.
enum CollectionMediaTab { movies, tvShows }

/// Configuration for a single content shelf or single-row grid inside a
/// selected collection folder.
class CollectionRowConfig extends Equatable {
  const CollectionRowConfig({
    required this.key,
    required this.catalogId,
    required this.type,
    required this.title,
    required this.endpoint,
    this.queryParameters = const {},
    this.isAniList = false,
    this.pruneIfUnder20 = false,
  });

  final String key;
  final String catalogId;
  final String type; // 'movie' or 'series'
  final String title;
  final String endpoint;
  final Map<String, dynamic> queryParameters;
  final bool isAniList;
  final bool pruneIfUnder20;

  bool get isSeries => type == 'series';

  @override
  List<Object?> get props => [
        key,
        catalogId,
        type,
        title,
        endpoint,
        queryParameters,
        isAniList,
        pruneIfUnder20,
      ];
}

typedef _OttSpec = ({
  String key,
  String watchProviders,
  String? networkIds,
});

typedef _GenreSpec = ({
  String movieGenre,
  String tvGenre,
  String? keywordIds,
  String? originLanguage,
  bool isAnime,
});

typedef _StudioSpec = ({
  String companyIds,
  String? tvNetworkIds,
  String? defaultGenres,
});

/// Maps any [CollectionFolderModel] (Streaming OTT, Crunchyroll Anime, Genres,
/// Studios, and all other premade collections) into daily-shuffled Movie and
/// TV Series row descriptors backed by TMDB and AniList.
class CollectionCatalogResolver {
  CollectionCatalogResolver._();

  static const Map<String, _OttSpec> _ottSpecs = {
    'netflix': (key: 'netflix', watchProviders: '8', networkIds: '213'),
    'prime': (key: 'prime', watchProviders: '9|119', networkIds: '1024'),
    'amazon': (key: 'prime', watchProviders: '9|119', networkIds: '1024'),
    'disney': (key: 'disney', watchProviders: '337', networkIds: '2739'),
    'hbo': (key: 'hbo', watchProviders: '1899|384', networkIds: '49|3186'),
    'max': (key: 'hbo', watchProviders: '1899|384', networkIds: '49|3186'),
    'apple': (key: 'apple', watchProviders: '350', networkIds: '2552'),
    'paramount': (key: 'paramount', watchProviders: '531', networkIds: '4330'),
    'hulu': (key: 'hulu', watchProviders: '15', networkIds: '453'),
    'peacock': (key: 'peacock', watchProviders: '386|387', networkIds: '3353'),
    'shudder': (key: 'shudder', watchProviders: '99', networkIds: null),
    'mgm': (key: 'mgm', watchProviders: '34|636', networkIds: '67|6219'),
    'discovery': (
      key: 'discovery',
      watchProviders: '520|510',
      networkIds: '4353|64',
    ),
    'hidive': (key: 'hidive', watchProviders: '430', networkIds: null),
  };

  static const Map<String, _GenreSpec> _genreSpecs = {
    'action': (
      movieGenre: '28',
      tvGenre: '10759',
      keywordIds: null,
      originLanguage: null,
      isAnime: false,
    ),
    'comedy': (
      movieGenre: '35',
      tvGenre: '35',
      keywordIds: null,
      originLanguage: null,
      isAnime: false,
    ),
    'drama': (
      movieGenre: '18',
      tvGenre: '18',
      keywordIds: null,
      originLanguage: null,
      isAnime: false,
    ),
    'scifi': (
      movieGenre: '878',
      tvGenre: '10765',
      keywordIds: null,
      originLanguage: null,
      isAnime: false,
    ),
    'horror': (
      movieGenre: '27',
      tvGenre: '9648|10765',
      keywordIds: null,
      originLanguage: null,
      isAnime: false,
    ),
    'crime': (
      movieGenre: '80',
      tvGenre: '80',
      keywordIds: null,
      originLanguage: null,
      isAnime: false,
    ),
    'fantasy': (
      movieGenre: '14',
      tvGenre: '10765',
      keywordIds: null,
      originLanguage: null,
      isAnime: false,
    ),
    'mystery': (
      movieGenre: '9648',
      tvGenre: '9648',
      keywordIds: null,
      originLanguage: null,
      isAnime: false,
    ),
    'romance': (
      movieGenre: '10749',
      tvGenre: '18',
      keywordIds: '9840',
      originLanguage: null,
      isAnime: false,
    ),
    'thriller': (
      movieGenre: '53',
      tvGenre: '80|9648',
      keywordIds: null,
      originLanguage: null,
      isAnime: false,
    ),
    'documentary': (
      movieGenre: '99',
      tvGenre: '99',
      keywordIds: null,
      originLanguage: null,
      isAnime: false,
    ),
    'animation': (
      movieGenre: '16',
      tvGenre: '16',
      keywordIds: null,
      originLanguage: null,
      isAnime: false,
    ),
    'bollywood': (
      movieGenre: '18|28|35|10749',
      tvGenre: '18|80|35',
      keywordIds: null,
      originLanguage: 'hi',
      isAnime: false,
    ),
    'westerns': (
      movieGenre: '37',
      tvGenre: '37',
      keywordIds: null,
      originLanguage: null,
      isAnime: false,
    ),
    'sports': (
      movieGenre: '18',
      tvGenre: '99|18',
      keywordIds: '6075',
      originLanguage: null,
      isAnime: false,
    ),
    'musicals': (
      movieGenre: '10402',
      tvGenre: '10402|35',
      keywordIds: null,
      originLanguage: null,
      isAnime: false,
    ),
    'kdrama': (
      movieGenre: '18',
      tvGenre: '18',
      keywordIds: null,
      originLanguage: 'ko',
      isAnime: false,
    ),
    'anime': (
      movieGenre: '16',
      tvGenre: '16',
      keywordIds: null,
      originLanguage: 'ja',
      isAnime: true,
    ),
    'spy': (
      movieGenre: '28|53',
      tvGenre: '10759|80',
      keywordIds: '470',
      originLanguage: null,
      isAnime: false,
    ),
    'war': (
      movieGenre: '10752',
      tvGenre: '10768',
      keywordIds: null,
      originLanguage: null,
      isAnime: false,
    ),
    'adventure': (
      movieGenre: '12',
      tvGenre: '10759',
      keywordIds: null,
      originLanguage: null,
      isAnime: false,
    ),
    'family': (
      movieGenre: '10751',
      tvGenre: '10751',
      keywordIds: null,
      originLanguage: null,
      isAnime: false,
    ),
    'history': (
      movieGenre: '36',
      tvGenre: '18|10768',
      keywordIds: null,
      originLanguage: null,
      isAnime: false,
    ),
    'limited_series': (
      movieGenre: '18',
      tvGenre: '18|9648',
      keywordIds: null,
      originLanguage: null,
      isAnime: false,
    ),
    'romantic_comedy': (
      movieGenre: '10749,35',
      tvGenre: '35,18',
      keywordIds: null,
      originLanguage: null,
      isAnime: false,
    ),
  };

  static const Map<String, _StudioSpec> _studioSpecs = {
    'marvel': (companyIds: '420|13252|11106|7505', tvNetworkIds: null, defaultGenres: null),
    'dc': (companyIds: '9993|184898|128064|429', tvNetworkIds: null, defaultGenres: null),
    'a24': (companyIds: '41077|293354', tvNetworkIds: null, defaultGenres: null),
    'pixar': (companyIds: '3', tvNetworkIds: null, defaultGenres: '16'),
    'disney_animated': (companyIds: '6125|158526|2', tvNetworkIds: null, defaultGenres: '16'),
    'ghibli': (companyIds: '10342', tvNetworkIds: null, defaultGenres: '16'),
    'lucasfilm': (companyIds: '1', tvNetworkIds: null, defaultGenres: null),
    'warner': (companyIds: '174|1957', tvNetworkIds: null, defaultGenres: null),
    'blumhouse': (companyIds: '3172', tvNetworkIds: null, defaultGenres: null),
    'universal': (companyIds: '33|26727', tvNetworkIds: null, defaultGenres: null),
    'sony': (companyIds: '34|5|11073', tvNetworkIds: null, defaultGenres: null),
    'paramount': (companyIds: '4|9223|228633', tvNetworkIds: null, defaultGenres: null),
    'dreamworks': (companyIds: '521', tvNetworkIds: null, defaultGenres: '16'),
  };

  static const Map<String, String> _networkIds = {
    'nbc': '6',
    'cbs': '16',
    'abc': '2',
    'fox': '19',
    'cw': '71',
    'showtime': '67',
    'tnt': '41',
    'usa': '30',
    'comedy_central': '47',
    'cartoon_network': '56',
    'disney_channel': '54',
    'bbc_one': '4',
    'nickelodeon': '13',
    'nick_jr': '35',
  };

  static const Map<String, int> _directorPersonIds = {
    'tarantino': 138,
    'nolan': 525,
    'spielberg': 488,
    'scorsese': 1032,
    'fincher': 7467,
    'villeneuve': 137427,
    'kubrick': 240,
    'hitchcock': 2636,
    'anderson': 5655,
    'burton': 510,
    'coen': 1223,
    'del_toro': 10828,
  };

  static const Map<String, int> _actorPersonIds = {
    'hanks': 31,
    'dicaprio': 6193,
    'denzel': 5292,
    'pitt': 287,
    'cruise': 500,
    'deniro': 380,
    'sandler': 19292,
    'jolie': 11701,
    'bale': 3894,
    'eastwood': 190,
    'carrey': 206,
    'depp': 85,
    'robbie': 234352,
    'damon': 1892,
    'freeman': 192,
    'rdj': 3223,
    'gosling': 30614,
    'reynolds': 10859,
    'rogen': 19274,
    'ferrell': 23659,
    'smith': 2888,
  };

  static const Map<String, int> _tmdbCollectionIds = {
    'collection_harry_potter': 1241,
    'collection_lord_of_the_rings': 119,
    'collection_star_wars': 10,
    'collection_hobbit': 121938,
    'collection_bond': 645,
    'collection_mission_impossible': 87359,
    'collection_indiana_jones': 84,
    'collection_jurassic_park': 328,
    'collection_fast_furious': 9485,
    'collection_john_wick': 404609,
    'collection_matrix': 2344,
    'collection_spider_man': 556,
    'collection_superman': 8537,
    'collection_batman': 120794,
    'collection_star_trek': 115575,
    'collection_alien': 8091,
    'collection_terminator': 528,
    'collection_dune': 726871,
    'collection_avatar': 87096,
  };

  static const Map<String, String> _themeKeywords = {
    'mindfuck': '275311|10854',
    'plot_twists': '275311',
    'heist': '10051',
    'time_travel': '4379',
    'superhero': '9715',
    'zombies': '12377',
    'apocalypse': '359337',
    'serial_killer': '10714',
    'whodunnit': '12570|381354',
    'time_loop': '10854',
    'outer_space': '252634',
    'true_crime': '33722',
  };

  static String _fmtDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  static List<CollectionCatalogSource> _deduplicateSources(
    CollectionFolderModel folder,
  ) {
    final raw = [...folder.sources, ...folder.catalogSources];
    final seen = <String>{};
    final out = <CollectionCatalogSource>[];
    for (final s in raw) {
      final normType = s.type == 'series' ? 'series' : 'movie';
      final key = '$normType|${s.catalogId}';
      if (s.catalogId.isNotEmpty && seen.add(key)) {
        out.add(s);
      }
    }
    return out;
  }

  static _OttSpec? _matchOttSpec(CollectionFolderModel folder) {
    final hay = '${folder.id} ${folder.title}'.toLowerCase();
    for (final entry in _ottSpecs.entries) {
      if (hay.contains(entry.key)) return entry.value;
    }
    return null;
  }

  /// Resolves a [CollectionFolderModel] into its Movie rows and TV Series rows.
  static ({
    List<CollectionRowConfig> movieRows,
    List<CollectionRowConfig> seriesRows,
  }) buildRowsForFolder({
    required PremadeCollectionModel collection,
    required CollectionFolderModel folder,
    DateTime? now,
  }) {
    final currentNow = now ?? DateTime.now();
    final lowerTitle = folder.title.toLowerCase();

    // Special case: Crunchyroll uses AniList directly for Anime Movies & Series.
    if (lowerTitle.contains('crunchyroll') ||
        folder.sources.any((s) => s.catalogId.contains('crunchyroll'))) {
      return _buildCrunchyrollRows(folder);
    }

    final isStreamingCollection =
        collection.id == '76d1a5f9-04ae-49cd-9a6f-4d8edfa50765' ||
            collection.title.toLowerCase() == 'streaming';
    final ottSpec = isStreamingCollection ? _matchOttSpec(folder) : null;

    if (ottSpec != null) {
      return _buildOttRows(folder, ottSpec, currentNow);
    }

    final sources = _deduplicateSources(folder);
    final movieRows = <CollectionRowConfig>[];
    final seriesRows = <CollectionRowConfig>[];

    for (final s in sources) {
      final isSeries = s.type == 'series';
      final normType = isSeries ? 'series' : 'movie';
      final row = _resolveGenericSource(
        folder: folder,
        source: s,
        normType: normType,
        now: currentNow,
      );
      if (isSeries) {
        seriesRows.add(row);
      } else {
        movieRows.add(row);
      }
    }

    return (movieRows: movieRows, seriesRows: seriesRows);
  }

  static ({
    List<CollectionRowConfig> movieRows,
    List<CollectionRowConfig> seriesRows,
  }) _buildCrunchyrollRows(CollectionFolderModel folder) {
    final movieRows = <CollectionRowConfig>[
      CollectionRowConfig(
        key: '${folder.id}|movie|anilist.movie.popular',
        catalogId: 'anilist.movie.popular',
        type: 'movie',
        title: 'Popular Anime Movies',
        endpoint: 'anilist',
        isAniList: true,
      ),
      CollectionRowConfig(
        key: '${folder.id}|movie|anilist.movie.top_rated',
        catalogId: 'anilist.movie.top_rated',
        type: 'movie',
        title: 'Top Rated Anime Movies',
        endpoint: 'anilist',
        isAniList: true,
      ),
      CollectionRowConfig(
        key: '${folder.id}|movie|anilist.movie.latest',
        catalogId: 'anilist.movie.latest',
        type: 'movie',
        title: 'Latest Anime Movies',
        endpoint: 'anilist',
        isAniList: true,
      ),
      for (final genre in AniListAddonRepository.genres)
        CollectionRowConfig(
          key: '${folder.id}|movie|anilist.movie.genre.$genre',
          catalogId: 'anilist.movie.genre.$genre',
          type: 'movie',
          title: genre,
          endpoint: 'anilist',
          isAniList: true,
          pruneIfUnder20: true,
        ),
    ];

    final animeSeriesCatalogs = AniListAddonRepository.staticManifest.catalogs
        .where((c) => !c.hasRequiredExtra);
    final seriesRows = <CollectionRowConfig>[
      for (final c in animeSeriesCatalogs)
        CollectionRowConfig(
          key: '${folder.id}|series|${c.id}',
          catalogId: c.id,
          type: 'series',
          title: c.name,
          endpoint: 'anilist',
          isAniList: true,
          pruneIfUnder20: c.id.startsWith('anilist.genre.') ||
              c.id.startsWith('anilist.tag.'),
        ),
    ];

    return (movieRows: movieRows, seriesRows: seriesRows);
  }

  static ({
    List<CollectionRowConfig> movieRows,
    List<CollectionRowConfig> seriesRows,
  }) _buildOttRows(
    CollectionFolderModel folder,
    _OttSpec spec,
    DateTime now,
  ) {
    final sources = _deduplicateSources(folder);
    final movieRows = <CollectionRowConfig>[];
    final seriesRows = <CollectionRowConfig>[];

    final today = _fmtDate(now);
    final oneYearAgo = _fmtDate(now.subtract(const Duration(days: 365)));
    final twoYearsAgo = _fmtDate(now.subtract(const Duration(days: 730)));

    for (final s in sources) {
      final isSeries = s.type == 'series';
      final normType = isSeries ? 'series' : 'movie';
      final cid = s.catalogId.toLowerCase();
      final endpoint = isSeries ? '/discover/tv' : '/discover/movie';
      final dateKey = isSeries ? 'first_air_date' : 'primary_release_date';

      late final String rowTitle;
      final query = <String, dynamic>{
        'with_watch_providers': spec.watchProviders,
        'watch_region': 'US',
        'sort_by': 'popularity.desc',
        'include_adult': 'false',
      };

      if (cid.contains('kids')) {
        rowTitle = 'Kids & Family Top 10';
        query['with_genres'] = isSeries ? '10762|10751' : '10751|16';
      } else if (cid.contains('top10') || cid.contains('top50')) {
        rowTitle = 'Trending on ${folder.title}';
        query['$dateKey.gte'] = twoYearsAgo;
        query['$dateKey.lte'] = today;
      } else if (cid.contains('latest')) {
        rowTitle = 'Latest Releases';
        query['$dateKey.gte'] = oneYearAgo;
        query['$dateKey.lte'] = today;
      } else if (cid.contains('toprated')) {
        rowTitle = 'Top Rated';
        query['sort_by'] = 'vote_average.desc';
        query['vote_count.gte'] = isSeries ? '80' : '150';
      } else if (cid.contains('originals')) {
        rowTitle = '${folder.title} Originals';
        if (spec.networkIds != null && isSeries) {
          query.remove('with_watch_providers');
          query.remove('watch_region');
          query['with_networks'] = spec.networkIds;
        }
      } else {
        rowTitle = 'Popular on ${folder.title}';
      }

      final row = CollectionRowConfig(
        key: '${folder.id}|$normType|${s.catalogId}',
        catalogId: s.catalogId,
        type: normType,
        title: rowTitle,
        endpoint: endpoint,
        queryParameters: query,
      );

      if (isSeries) {
        seriesRows.add(row);
      } else {
        movieRows.add(row);
      }
    }

    // Ensure OTTs like MGM+ without predefined series sources still get a lead series row.
    if (seriesRows.isEmpty) {
      seriesRows.add(
        CollectionRowConfig(
          key: '${folder.id}|series|streaming_${spec.key}_series',
          catalogId: 'streaming_${spec.key}_series',
          type: 'series',
          title: 'Popular on ${folder.title}',
          endpoint: '/discover/tv',
          queryParameters: {
            'with_watch_providers': spec.watchProviders,
            'watch_region': 'US',
            'sort_by': 'popularity.desc',
            'include_adult': 'false',
          },
          pruneIfUnder20: true,
        ),
      );
    }

    // Check if premade JSON already provides genre category rows for this OTT;
    // since it does not, append TMDB category rows for both Movies and TV Shows
    // and mark them for `< 20` title pruning.
    final hasExplicitMovieGenres = movieRows.any(
      (r) => r.catalogId.contains('genre_'),
    );
    if (!hasExplicitMovieGenres) {
      for (final g in TmdbRepository.defaultMovieGenres) {
        movieRows.add(
          CollectionRowConfig(
            key: '${folder.id}|movie|ott_genre_${spec.key}_${g.id}',
            catalogId: 'ott_genre_${spec.key}_movie_${g.id}',
            type: 'movie',
            title: g.name,
            endpoint: '/discover/movie',
            queryParameters: {
              'with_watch_providers': spec.watchProviders,
              'watch_region': 'US',
              'with_genres': '${g.id}',
              'sort_by': 'popularity.desc',
              'include_adult': 'false',
            },
            pruneIfUnder20: true,
          ),
        );
      }
    }

    final hasExplicitSeriesGenres = seriesRows.any(
      (r) => r.catalogId.contains('genre_'),
    );
    if (!hasExplicitSeriesGenres) {
      for (final g in TmdbRepository.defaultSeriesGenres) {
        seriesRows.add(
          CollectionRowConfig(
            key: '${folder.id}|series|ott_genre_${spec.key}_${g.id}',
            catalogId: 'ott_genre_${spec.key}_series_${g.id}',
            type: 'series',
            title: g.name,
            endpoint: '/discover/tv',
            queryParameters: {
              'with_watch_providers': spec.watchProviders,
              'watch_region': 'US',
              'with_genres': '${g.id}',
              'sort_by': 'popularity.desc',
              'include_adult': 'false',
            },
            pruneIfUnder20: true,
          ),
        );
      }
    }

    return (movieRows: movieRows, seriesRows: seriesRows);
  }

  static CollectionRowConfig _resolveGenericSource({
    required CollectionFolderModel folder,
    required CollectionCatalogSource source,
    required String normType,
    required DateTime now,
  }) {
    final isSeries = normType == 'series';
    final cid = source.catalogId.toLowerCase();
    final endpoint = isSeries ? '/discover/tv' : '/discover/movie';
    final dateKey = isSeries ? 'first_air_date' : 'primary_release_date';
    final today = _fmtDate(now);
    final oneYearAgo = _fmtDate(now.subtract(const Duration(days: 365)));

    String baseLabel(String kind) {
      if (kind == 'latest') return 'Latest ${folder.title}';
      if (kind == 'toprated') return 'Top Rated ${folder.title}';
      return '${folder.title} ${isSeries ? 'Series' : 'Movies'}';
    }

    final kind = cid.contains('latest')
        ? 'latest'
        : (cid.contains('toprated') || cid.contains('best') || cid.contains('top250'))
            ? 'toprated'
            : 'popular';

    // 1. Anime / MAL catalogs.
    if (cid.startsWith('anime_') || cid.startsWith('mal_')) {
      if (isSeries) {
        final aniId = cid.contains('airing')
            ? 'anilist.airing'
            : cid.contains('upcoming')
                ? 'anilist.upcoming'
                : 'anilist.popular';
        return CollectionRowConfig(
          key: '${folder.id}|$normType|${source.catalogId}',
          catalogId: aniId,
          type: 'series',
          title: _humanizeCatalogId(source.catalogId, folder.title, isSeries),
          endpoint: 'anilist',
          isAniList: true,
        );
      }
      final aniMovieId = cid.contains('toprated')
          ? 'anilist.movie.top_rated'
          : cid.contains('latest')
              ? 'anilist.movie.latest'
              : 'anilist.movie.popular';
      return CollectionRowConfig(
        key: '${folder.id}|$normType|${source.catalogId}',
        catalogId: aniMovieId,
        type: 'movie',
        title: _humanizeCatalogId(source.catalogId, folder.title, isSeries),
        endpoint: 'anilist',
        isAniList: true,
      );
    }

    // 2. Genres collection (`genre_*`).
    if (cid.startsWith('genre_')) {
      for (final entry in _genreSpecs.entries) {
        if (cid.contains(entry.key)) {
          final spec = entry.value;
          if (spec.isAnime) {
            return CollectionRowConfig(
              key: '${folder.id}|$normType|${source.catalogId}',
              catalogId: isSeries ? 'anilist.popular' : 'anilist.movie.popular',
              type: normType,
              title: isSeries ? 'Anime Series' : 'Anime Movies',
              endpoint: 'anilist',
              isAniList: true,
            );
          }
          final q = <String, dynamic>{
            'with_genres': isSeries ? spec.tvGenre : spec.movieGenre,
            'sort_by': kind == 'toprated' ? 'vote_average.desc' : 'popularity.desc',
            'include_adult': 'false',
            if (spec.keywordIds != null) 'with_keywords': spec.keywordIds,
            if (spec.originLanguage != null)
              'with_original_language': spec.originLanguage,
            if (kind == 'latest') '$dateKey.gte': oneYearAgo,
            if (kind == 'latest') '$dateKey.lte': today,
            if (kind == 'toprated') 'vote_count.gte': isSeries ? '80' : '180',
            if (kind == 'popular') 'vote_count.gte': isSeries ? '30' : '80',
          };
          return CollectionRowConfig(
            key: '${folder.id}|$normType|${source.catalogId}',
            catalogId: source.catalogId,
            type: normType,
            title: baseLabel(kind),
            endpoint: endpoint,
            queryParameters: q,
          );
        }
      }
    }

    // 3. Studios collection (`studio_*`, `collection_mcu`).
    if (cid.startsWith('studio_') || cid == 'collection_mcu') {
      final q = <String, dynamic>{
        'sort_by': kind == 'toprated' ? 'vote_average.desc' : 'popularity.desc',
        'include_adult': 'false',
      };
      String title = baseLabel(kind);

      if (cid == 'collection_mcu') {
        title = 'Marvel Cinematic Universe';
        q['with_companies'] = '420';
      } else if (cid.contains('spiderman')) {
        title = 'Spider-Man Universe';
        q['with_keywords'] = '9715|155030';
        q['with_companies'] = '5|7505';
      } else if (cid.contains('xmen')) {
        title = 'X-Men Universe';
        q['with_keywords'] = '155030';
        q['with_companies'] = '19551|7505|25';
      } else if (cid.contains('avengers')) {
        title = 'Avengers';
        q['with_companies'] = '420';
        q['with_keywords'] = '180547';
      } else if (cid.contains('dceu')) {
        title = 'DC Extended Universe';
        q['with_companies'] = '9993|128064';
        q['primary_release_date.gte'] = '2013-01-01';
        q['primary_release_date.lte'] = '2023-12-31';
      } else if (cid.startsWith('studio_dcu')) {
        title = isSeries ? 'DC Universe Series' : 'DC Universe';
        q['with_companies'] = '184898|9993';
        q['$dateKey.gte'] = '2024-01-01';
      } else if (cid.contains('batman')) {
        title = 'Batman';
        q['with_companies'] = '9993|429';
        q['with_keywords'] = '697|849';
      } else if (cid.contains('superman')) {
        title = 'Superman';
        q['with_companies'] = '9993|429';
        q['with_keywords'] = '849';
      } else if (cid.contains('animation')) {
        title = '${folder.title} Animation';
        q['with_genres'] = '16';
        q['with_companies'] = cid.contains('dc') ? '2785|9993|429' : '13252|7505';
      } else if (cid.contains('legacy')) {
        title = 'Marvel Legacy';
        q['with_companies'] = '7505|19551';
        q['primary_release_date.lte'] = '2016-12-31';
      } else {
        for (final entry in _studioSpecs.entries) {
          if (cid.contains(entry.key)) {
            q['with_companies'] = entry.value.companyIds;
            if (entry.value.defaultGenres != null) {
              q['with_genres'] = entry.value.defaultGenres;
            }
            break;
          }
        }
      }

      if (kind == 'latest') {
        q['$dateKey.gte'] = oneYearAgo;
        q['$dateKey.lte'] = today;
      } else if (kind == 'toprated') {
        q['vote_count.gte'] = isSeries ? '50' : '150';
      }

      return CollectionRowConfig(
        key: '${folder.id}|$normType|${source.catalogId}',
        catalogId: source.catalogId,
        type: normType,
        title: title,
        endpoint: endpoint,
        queryParameters: q,
      );
    }

    // 4. TMDB Film Collections (`collection_*`) and User Custom TMDB Lists (`tmdb_user_list_*`).
    if (cid.startsWith('tmdb_user_list_')) {
      final listId = source.tmdbId ??
          int.tryParse(cid.substring('tmdb_user_list_'.length));
      if (listId != null) {
        return CollectionRowConfig(
          key: '${folder.id}|movie|${source.catalogId}',
          catalogId: source.catalogId,
          type: 'movie',
          title: folder.title,
          endpoint: '/list/$listId',
          queryParameters: const {'language': 'en-US'},
        );
      }
    }
    final tmdbColId = _tmdbCollectionIds[cid];
    if (tmdbColId != null) {
      return CollectionRowConfig(
        key: '${folder.id}|movie|${source.catalogId}',
        catalogId: source.catalogId,
        type: 'movie',
        title: folder.title,
        endpoint: '/collection/$tmdbColId',
        queryParameters: const {'language': 'en-US'},
      );
    }

    // 5. Networks (`network_*`).
    if (cid.startsWith('network_')) {
      for (final entry in _networkIds.entries) {
        if (cid.contains(entry.key)) {
          return CollectionRowConfig(
            key: '${folder.id}|series|${source.catalogId}',
            catalogId: source.catalogId,
            type: 'series',
            title: baseLabel(kind),
            endpoint: '/discover/tv',
            queryParameters: {
              'with_networks': entry.value,
              'sort_by':
                  kind == 'toprated' ? 'vote_average.desc' : 'popularity.desc',
              'include_adult': 'false',
              if (kind == 'latest') 'first_air_date.gte': oneYearAgo,
              if (kind == 'latest') 'first_air_date.lte': today,
              if (kind == 'toprated') 'vote_count.gte': '40',
            },
          );
        }
      }
    }

    // 6. Directors & Actors.
    if (cid.startsWith('director_')) {
      for (final entry in _directorPersonIds.entries) {
        if (cid.contains(entry.key)) {
          return CollectionRowConfig(
            key: '${folder.id}|movie|${source.catalogId}',
            catalogId: source.catalogId,
            type: 'movie',
            title: '${folder.title} Filmography',
            endpoint: '/discover/movie',
            queryParameters: {
              'with_crew': '${entry.value}',
              'sort_by': 'popularity.desc',
              'include_adult': 'false',
            },
          );
        }
      }
    }
    if (cid.startsWith('actor_')) {
      for (final entry in _actorPersonIds.entries) {
        if (cid.contains(entry.key)) {
          return CollectionRowConfig(
            key: '${folder.id}|movie|${source.catalogId}',
            catalogId: source.catalogId,
            type: 'movie',
            title: 'Starring ${folder.title}',
            endpoint: '/discover/movie',
            queryParameters: {
              'with_cast': '${entry.value}',
              'sort_by': 'popularity.desc',
              'include_adult': 'false',
            },
          );
        }
      }
    }

    // 7. World Cinema (`world_<lang>_*`).
    if (cid.startsWith('world_')) {
      final parts = cid.split('_');
      final lang = parts.length >= 2 ? parts[1] : 'ko';
      return CollectionRowConfig(
        key: '${folder.id}|$normType|${source.catalogId}',
        catalogId: source.catalogId,
        type: normType,
        title: baseLabel(kind),
        endpoint: endpoint,
        queryParameters: {
          'with_original_language': lang,
          'sort_by':
              kind == 'toprated' ? 'vote_average.desc' : 'popularity.desc',
          'include_adult': 'false',
          if (kind == 'latest') '$dateKey.gte': oneYearAgo,
          if (kind == 'latest') '$dateKey.lte': today,
          if (kind == 'toprated') 'vote_count.gte': isSeries ? '30' : '80',
        },
      );
    }

    // 8. Decades (`decade_2020s_*`, `decade_1990s_*`, ...).
    if (cid.startsWith('decade_')) {
      final match = RegExp(r'(\d{4})s').firstMatch(cid);
      final startYear = int.tryParse(match?.group(1) ?? '2020') ?? 2020;
      final isBefore1950 = cid.contains('1950s_and_before');
      return CollectionRowConfig(
        key: '${folder.id}|$normType|${source.catalogId}',
        catalogId: source.catalogId,
        type: normType,
        title: baseLabel(kind),
        endpoint: endpoint,
        queryParameters: {
          if (!isBefore1950) '$dateKey.gte': '$startYear-01-01',
          '$dateKey.lte': '${startYear + 9}-12-31',
          'sort_by':
              kind == 'toprated' ? 'vote_average.desc' : 'popularity.desc',
          'vote_count.gte': kind == 'toprated' ? (isSeries ? '60' : '250') : '50',
          'include_adult': 'false',
        },
      );
    }

    // 9. Themes (`themed_*`).
    if (cid.startsWith('themed_')) {
      for (final entry in _themeKeywords.entries) {
        if (cid.contains(entry.key)) {
          return CollectionRowConfig(
            key: '${folder.id}|$normType|${source.catalogId}',
            catalogId: source.catalogId,
            type: normType,
            title: folder.title,
            endpoint: endpoint,
            queryParameters: {
              'with_keywords': entry.value,
              'sort_by': 'popularity.desc',
              'vote_count.gte': isSeries ? '30' : '80',
              'include_adult': 'false',
            },
          );
        }
      }
      if (cid.contains('modern_horror')) {
        return CollectionRowConfig(
          key: '${folder.id}|movie|${source.catalogId}',
          catalogId: source.catalogId,
          type: 'movie',
          title: folder.title,
          endpoint: '/discover/movie',
          queryParameters: const {
            'with_genres': '27',
            'primary_release_date.gte': '2016-01-01',
            'vote_average.gte': '6.0',
            'vote_count.gte': '100',
            'sort_by': 'popularity.desc',
          },
        );
      }
      if (cid.contains('horror_classics')) {
        return CollectionRowConfig(
          key: '${folder.id}|movie|${source.catalogId}',
          catalogId: source.catalogId,
          type: 'movie',
          title: folder.title,
          endpoint: '/discover/movie',
          queryParameters: const {
            'with_genres': '27',
            'primary_release_date.lte': '1999-12-31',
            'vote_average.gte': '6.8',
            'vote_count.gte': '300',
            'sort_by': 'popularity.desc',
          },
        );
      }
      if (cid.contains('reality_tv')) {
        return CollectionRowConfig(
          key: '${folder.id}|series|${source.catalogId}',
          catalogId: source.catalogId,
          type: 'series',
          title: folder.title,
          endpoint: '/discover/tv',
          queryParameters: const {
            'with_genres': '10764',
            'sort_by': 'popularity.desc',
          },
        );
      }
    }

    // 10. Runtime, Kids, Reality, Trending, New & Latest, Awards, TV Collections, Fallback.
    if (cid.startsWith('runtime_')) {
      final (int? gte, int? lte) = cid.contains('short')
          ? (null, 90)
          : cid.contains('standard')
              ? (90, 120)
              : cid.contains('long')
                  ? (120, 150)
                  : (150, null);
      return CollectionRowConfig(
        key: '${folder.id}|movie|${source.catalogId}',
        catalogId: source.catalogId,
        type: 'movie',
        title: folder.title,
        endpoint: '/discover/movie',
        queryParameters: {
          if (gte != null) 'with_runtime.gte': '$gte',
          if (lte != null) 'with_runtime.lte': '$lte',
          'vote_average.gte': '6.4',
          'vote_count.gte': '150',
          'sort_by': 'popularity.desc',
        },
      );
    }

    if (cid.startsWith('kids_')) {
      return CollectionRowConfig(
        key: '${folder.id}|$normType|${source.catalogId}',
        catalogId: source.catalogId,
        type: normType,
        title: folder.title,
        endpoint: endpoint,
        queryParameters: {
          'with_genres': isSeries ? '10762|10751|16' : '10751|16',
          if (cid.contains('disney')) 'with_companies': '2|6125|3',
          'sort_by': 'popularity.desc',
          'include_adult': 'false',
        },
      );
    }

    if (cid.startsWith('reality_')) {
      return CollectionRowConfig(
        key: '${folder.id}|series|${source.catalogId}',
        catalogId: source.catalogId,
        type: 'series',
        title: folder.title,
        endpoint: '/discover/tv',
        queryParameters: {
          'with_genres': '10764',
          'sort_by': 'popularity.desc',
          if (cid.contains('latest')) 'first_air_date.gte': oneYearAgo,
        },
      );
    }

    if (cid.contains('now_playing')) {
      return CollectionRowConfig(
        key: '${folder.id}|movie|${source.catalogId}',
        catalogId: source.catalogId,
        type: 'movie',
        title: folder.title,
        endpoint: '/movie/now_playing',
        queryParameters: const {'language': 'en-US'},
      );
    }
    if (cid.contains('upcoming')) {
      return CollectionRowConfig(
        key: '${folder.id}|movie|${source.catalogId}',
        catalogId: source.catalogId,
        type: 'movie',
        title: folder.title,
        endpoint: '/movie/upcoming',
        queryParameters: const {'language': 'en-US'},
      );
    }
    if (cid.contains('on_the_air')) {
      return CollectionRowConfig(
        key: '${folder.id}|series|${source.catalogId}',
        catalogId: source.catalogId,
        type: 'series',
        title: folder.title,
        endpoint: '/tv/on_the_air',
        queryParameters: const {'language': 'en-US'},
      );
    }
    if (cid.contains('airing_today')) {
      return CollectionRowConfig(
        key: '${folder.id}|series|${source.catalogId}',
        catalogId: source.catalogId,
        type: 'series',
        title: folder.title,
        endpoint: '/tv/airing_today',
        queryParameters: const {'language': 'en-US'},
      );
    }
    if (cid.contains('trending') || cid.contains('top100')) {
      return CollectionRowConfig(
        key: '${folder.id}|$normType|${source.catalogId}',
        catalogId: source.catalogId,
        type: normType,
        title: '${folder.title} ${isSeries ? 'Series' : 'Movies'}',
        endpoint: isSeries ? '/trending/tv/day' : '/trending/movie/day',
        queryParameters: const {'language': 'en-US'},
      );
    }
    if (cid.startsWith('awards_')) {
      final isAnimation = cid.contains('animated');
      return CollectionRowConfig(
        key: '${folder.id}|$normType|${source.catalogId}',
        catalogId: source.catalogId,
        type: normType,
        title: _humanizeCatalogId(source.catalogId, folder.title, isSeries),
        endpoint: endpoint,
        queryParameters: {
          if (isAnimation) 'with_genres': '16',
          if (cid.contains('2024')) '$dateKey.gte': '2024-01-01',
          if (cid.contains('2024')) '$dateKey.lte': '2024-12-31',
          if (cid.contains('2025')) '$dateKey.gte': '2025-01-01',
          if (cid.contains('2025')) '$dateKey.lte': '2025-12-31',
          'vote_average.gte': '7.2',
          'vote_count.gte': isSeries ? '100' : '400',
          'sort_by': 'popularity.desc',
        },
      );
    }

    // Default safe TMDB discover fallback for remaining folders.
    return CollectionRowConfig(
      key: '${folder.id}|$normType|${source.catalogId}',
      catalogId: source.catalogId,
      type: normType,
      title: _humanizeCatalogId(source.catalogId, folder.title, isSeries),
      endpoint: endpoint,
      queryParameters: {
        'sort_by': kind == 'toprated' ? 'vote_average.desc' : 'popularity.desc',
        'include_adult': 'false',
        'vote_count.gte': isSeries ? '40' : '100',
        if (kind == 'latest') '$dateKey.gte': oneYearAgo,
      },
    );
  }

  static String _humanizeCatalogId(
    String catalogId,
    String folderTitle,
    bool isSeries,
  ) {
    final cleaned = catalogId
        .replaceFirst(RegExp(r'^(awards_|anime_|mal_|new_latest_)'), '')
        .replaceAll('_', ' ')
        .trim();
    if (cleaned.isEmpty) return folderTitle;
    final words = cleaned
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
    return words.length > 3 ? words : '$folderTitle ${isSeries ? 'Series' : 'Movies'}';
  }
}
