class ApiConstants {
  ApiConstants._();

  // TMDB v3. Used to resolve IMDb ids into clean artwork and
  // authoritative movie/series metadata. Inject at build time via
  // --dart-define-from-file=.env.prod.json (or --dart-define=TMDB_API_KEY=...).
  static const String tmdbApiKey = String.fromEnvironment(
    'TMDB_API_KEY',
    defaultValue: '',
  );
  static const String tmdbBaseUrl = 'https://api.themoviedb.org/3';
  static const String tmdbImageUrl = 'https://image.tmdb.org/t/p';

  static const Duration connectTimeout = Duration(seconds: 12);
  static const Duration receiveTimeout = Duration(seconds: 15);
  static const int maxRetries = 2;

  /// Catalogs fetched concurrently on first paint; a second background wave
  /// immediately follows while the opening splash screen rests.
  static const int initialCatalogBatch = 4;
  static const int backgroundCatalogBatch = 4;
  static const int heroItems = 6;

  /// Strip `/manifest.json` to derive the addon base URL.
  static String deriveBaseUrl(String manifestUrl) =>
      manifestUrl.replaceFirst(RegExp(r'/manifest\.json(\?.*)?$'), '');

  // AniList & Fribb integration constants
  static const String anilistGraphQLUrl = 'https://graphql.anilist.co';
  static const String fribbAnimeListMiniUrl =
      'https://raw.githubusercontent.com/Fribb/anime-lists/master/anime-list-mini.json';
  static const Duration anilistBatchWindow = Duration(milliseconds: 40);
  static const int anilistMaxAliases = 6;
  static const Duration anilistCacheTtl = Duration(minutes: 30);
}
