import 'package:equatable/equatable.dart';

const _monthNames = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Formats an ISO `"2021-11-18"` date string into Figma's `"November 18, 2021"`.
String? formatEpisodeAirDate(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final trimmed = raw.trim();
  final parts = trimmed.split('-');
  if (parts.length == 3) {
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final day = int.tryParse(parts[2]);
    if (year != null && month != null && month >= 1 && month <= 12 && day != null) {
      return '${_monthNames[month - 1]} $day, $year';
    }
  }
  return trimmed;
}

/// Parses a TMDB `"YYYY-MM-DD"` date string into a calendar [DateTime] (midnight local time).
DateTime? parseTmdbAirDate(String? rawAirDate) {
  if (rawAirDate == null) return null;
  final trimmed = rawAirDate.trim();
  if (trimmed.isEmpty) return null;
  final parts = trimmed.split('-');
  if (parts.length < 3) return null;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || month < 1 || month > 12 || day == null || day < 1 || day > 31) {
    return null;
  }
  return DateTime(year, month, day);
}

/// Returns `true` if [rawAirDate] (`"YYYY-MM-DD"`) is non-empty and its calendar
/// release date has arrived (`<= today` relative to [now] or `DateTime.now()`).
///
/// Unscheduled items (`null` or empty `air_date`) and future-dated items return `false`.
bool isAirDateReleased(String? rawAirDate, {DateTime? now}) {
  final airDate = parseTmdbAirDate(rawAirDate);
  if (airDate == null) return false;
  final ref = now ?? DateTime.now();
  final today = DateTime(ref.year, ref.month, ref.day);
  return !airDate.isAfter(today);
}

/// Rating value (> 8.0) submitted to TMDB when the user clicks "Like".
const double kTmdbLikeRatingValue = 8.5;

/// Rating value (< 2.0) submitted to TMDB when the user clicks "Not for me".
const double kTmdbDislikeRatingValue = 1.5;

/// Half of TMDB's 10.0 maximum rating scale. Any existing TMDB rating `< 5.0`
/// (such as `4.5`) is classified as "Not for me" ([TmdbUserReaction.disliked]);
/// any rating `>= 5.0` is classified as "Liked" ([TmdbUserReaction.liked]).
const double kTmdbHalfRatingThreshold = 5.0;

/// User reaction state derived from the user's TMDB rating for a movie or series.
enum TmdbUserReaction { none, liked, disliked }

/// Authenticated TMDB user account profile (`/3/account`).
class TmdbAccountProfile extends Equatable {
  const TmdbAccountProfile({
    required this.id,
    required this.username,
    this.name,
    this.avatarUrl,
  });

  final int id;
  final String username;
  final String? name;
  final String? avatarUrl;

  String get displayName =>
      (name != null && name!.trim().isNotEmpty) ? name!.trim() : username;

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        if (name != null) 'name': name,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
      };

  static TmdbAccountProfile? tryParse(Map<String, dynamic>? json) {
    if (json == null) return null;
    final rawId = json['id'];
    final id = rawId is num ? rawId.toInt() : int.tryParse(rawId?.toString() ?? '');
    if (id == null || id <= 0) return null;
    final username = (json['username'] ?? '').toString().trim();
    if (username.isEmpty) return null;
    final rawName = (json['name'] ?? '').toString().trim();
    String? avatarUrl = (json['avatarUrl'] ?? '').toString().trim();
    if (avatarUrl.isEmpty) {
      final avatar = json['avatar'];
      if (avatar is Map) {
        final tmdb = avatar['tmdb'];
        if (tmdb is Map && tmdb['avatar_path'] is String) {
          final path = (tmdb['avatar_path'] as String).trim();
          if (path.isNotEmpty) {
            avatarUrl = 'https://image.tmdb.org/t/p/w185$path';
          }
        }
        if (avatarUrl.isEmpty && avatar['gravatar'] is Map) {
          final hash = (avatar['gravatar']['hash'] ?? '').toString().trim();
          if (hash.isNotEmpty) {
            avatarUrl = 'https://www.gravatar.com/avatar/$hash?s=185&d=identicon';
          }
        }
      }
    }
    return TmdbAccountProfile(
      id: id,
      username: username,
      name: rawName.isNotEmpty ? rawName : null,
      avatarUrl: avatarUrl.isNotEmpty ? avatarUrl : null,
    );
  }

  @override
  List<Object?> get props => [id, username, name, avatarUrl];
}

/// Classifies a TMDB rating (`0.5 .. 10.0`) into [TmdbUserReaction]:
/// - `null` or `<= 0` -> [TmdbUserReaction.none]
/// - `< 5.0` (less than half of 10.0, e.g. `4.5` or `< 2.0`) -> [TmdbUserReaction.disliked]
/// - `>= 5.0` (half or above, including `> 8.0`) -> [TmdbUserReaction.liked]
TmdbUserReaction reactionFromRating(double? rating) {
  if (rating == null || rating <= 0) return TmdbUserReaction.none;
  return rating < kTmdbHalfRatingThreshold
      ? TmdbUserReaction.disliked
      : TmdbUserReaction.liked;
}

/// One cast member from TMDB `credits.cast`.
class TmdbCast extends Equatable {
  const TmdbCast({required this.name, required this.character, this.profileUrl});

  final String name;
  final String character;
  final String? profileUrl;

  @override
  List<Object?> get props => [name, character, profileUrl];
}

/// A recommended or similar title from TMDB.
class TmdbRecommendation extends Equatable {
  const TmdbRecommendation({
    required this.id,
    required this.title,
    this.posterUrl,
    this.backdropUrl,
    this.popularity = 0.0,
    this.voteAverage,
    this.voteCount = 0,
    this.imdbId,
    this.mediaType = 'movie',
    this.genres = const [],
    this.releaseYear,
    this.releaseDate,
    this.originalLanguage,
    this.genreIds = const [],
    this.collectionId,
  });

  final int id;
  final String title;
  final String? posterUrl;
  final String? backdropUrl;
  final double popularity;
  final double? voteAverage;
  final int voteCount;
  final String? imdbId;
  final String mediaType;
  final List<String> genres;
  final int? releaseYear;
  final String? releaseDate;
  final String? originalLanguage;
  final List<int> genreIds;
  final int? collectionId;

  bool isReleased({DateTime? now}) => isAirDateReleased(releaseDate, now: now);

  TmdbRecommendation copyWith({
    String? posterUrl,
    String? backdropUrl,
    String? imdbId,
    String? mediaType,
    List<String>? genres,
    int? releaseYear,
    String? releaseDate,
    String? originalLanguage,
    List<int>? genreIds,
    int? collectionId,
  }) =>
      TmdbRecommendation(
        id: id,
        title: title,
        posterUrl: posterUrl ?? this.posterUrl,
        backdropUrl: backdropUrl ?? this.backdropUrl,
        popularity: popularity,
        voteAverage: voteAverage,
        voteCount: voteCount,
        imdbId: imdbId ?? this.imdbId,
        mediaType: mediaType ?? this.mediaType,
        genres: genres ?? this.genres,
        releaseYear: releaseYear ?? this.releaseYear,
        releaseDate: releaseDate ?? this.releaseDate,
        originalLanguage: originalLanguage ?? this.originalLanguage,
        genreIds: genreIds ?? this.genreIds,
        collectionId: collectionId ?? this.collectionId,
      );

  @override
  List<Object?> get props => [
        id,
        title,
        posterUrl,
        backdropUrl,
        popularity,
        voteAverage,
        voteCount,
        imdbId,
        mediaType,
        genres,
        releaseYear,
        releaseDate,
        originalLanguage,
        genreIds,
        collectionId,
      ];
}

/// Returns the earliest upcoming calendar release [DateTime] among unreleased
/// entries in [items], or `null` if none have a future release date.
DateTime? nextRecommendationReleaseDate(
  Iterable<TmdbRecommendation> items, {
  DateTime? now,
}) {
  final ref = now ?? DateTime.now();
  final today = DateTime(ref.year, ref.month, ref.day);
  DateTime? earliest;
  for (final item in items) {
    final airDate = parseTmdbAirDate(item.releaseDate);
    if (airDate == null || !airDate.isAfter(today)) continue;
    if (earliest == null || airDate.isBefore(earliest)) {
      earliest = airDate;
    }
  }
  return earliest;
}

/// Summary metadata for a single TV season on the Series Details screen.
class TmdbSeasonSummary extends Equatable {
  const TmdbSeasonSummary({
    required this.id,
    required this.seasonNumber,
    required this.name,
    this.overview = '',
    this.posterUrl,
    this.airDate,
    this.episodeCount = 0,
    this.voteAverage,
  });

  final int id;
  final int seasonNumber;
  final String name;
  final String overview;
  final String? posterUrl;
  final String? airDate;
  final int episodeCount;
  final double? voteAverage;

  /// Figma season row title: `"Season 1"` (`"Season"` + space + season number).
  String get displayTitle => 'Season $seasonNumber';

  /// 4-digit release year extracted from [airDate] (`"YYYY-MM-DD"` -> `"YYYY"`).
  String? get releaseYear {
    final raw = airDate?.trim();
    if (raw == null || raw.length < 4) return null;
    final year = raw.substring(0, 4);
    return int.tryParse(year) != null ? year : null;
  }

  /// Figma season row subtitle: `"8 episodes   2021"` (episode count + extra spacing + year).
  String get episodesAndYearLabel {
    final epPart = '$episodeCount ${episodeCount == 1 ? 'episode' : 'episodes'}';
    final year = releaseYear;
    if (year == null || year.isEmpty) return epPart;
    return '$epPart \u00A0 $year';
  }

  TmdbSeasonSummary copyWith({
    int? episodeCount,
    String? airDate,
  }) =>
      TmdbSeasonSummary(
        id: id,
        seasonNumber: seasonNumber,
        name: name,
        overview: overview,
        posterUrl: posterUrl,
        airDate: airDate ?? this.airDate,
        episodeCount: episodeCount ?? this.episodeCount,
        voteAverage: voteAverage,
      );

  @override
  List<Object?> get props => [id, seasonNumber, name, episodeCount, posterUrl, airDate];
}

/// Metadata for a single episode inside a TV season.
class TmdbEpisode extends Equatable {
  const TmdbEpisode({
    required this.id,
    required this.episodeNumber,
    required this.seasonNumber,
    required this.name,
    this.overview = '',
    this.stillUrl,
    this.airDate,
    this.runtimeMinutes,
    this.voteAverage,
  });

  final int id;
  final int episodeNumber;
  final int seasonNumber;
  final String name;
  final String overview;
  final String? stillUrl;
  final String? airDate;
  final int? runtimeMinutes;
  final double? voteAverage;

  String? get runtimeLabel => runtimeMinutes == null ? null : '$runtimeMinutes min';

  /// Figma Episode Card runtime format: `"55min"` (no space).
  String? get compactRuntimeLabel =>
      (runtimeMinutes == null || runtimeMinutes! <= 0) ? null : '${runtimeMinutes}min';

  /// Figma Episode Card release date format: `"November 18, 2021"`.
  String? get formattedAirDate => formatEpisodeAirDate(airDate);

  /// Parsed calendar air date (`YYYY-MM-DD`).
  DateTime? get parsedAirDate => parseTmdbAirDate(airDate);

  /// Whether this episode has already been released as of [now] (or `DateTime.now()`).
  bool isReleased({DateTime? now}) => isAirDateReleased(airDate, now: now);

  @override
  List<Object?> get props => [
        id,
        seasonNumber,
        episodeNumber,
        name,
        overview,
        stillUrl,
        airDate,
        runtimeMinutes,
        voteAverage,
      ];
}

/// Detailed episode list for one TV season (`/tv/{id}/season/{season_number}`).
class TmdbSeasonDetails extends Equatable {
  const TmdbSeasonDetails({
    required this.id,
    required this.seasonNumber,
    required this.name,
    this.overview = '',
    this.posterUrl,
    this.airDate,
    this.episodes = const [],
    List<TmdbEpisode>? allEpisodes,
  }) : allEpisodes = allEpisodes ?? episodes;

  final int id;
  final int seasonNumber;
  final String name;
  final String overview;
  final String? posterUrl;
  final String? airDate;

  /// Only the episodes that have already been released (`isReleased == true`).
  final List<TmdbEpisode> episodes;

  /// Full list of episodes from TMDB (including upcoming scheduled episodes),
  /// preserved so that as soon as an upcoming episode reaches its release date,
  /// [filterReleased] and [nextEpisodeReleaseDate] can expose it immediately.
  final List<TmdbEpisode> allEpisodes;

  /// Re-evaluates [allEpisodes] against [now] (or `DateTime.now()`) and returns
  /// a [TmdbSeasonDetails] whose [episodes] list contains only released episodes.
  TmdbSeasonDetails filterReleased({DateTime? now}) {
    final released = <TmdbEpisode>[
      for (final ep in allEpisodes)
        if (ep.isReleased(now: now)) ep,
    ];
    if (released.length == episodes.length) return this;
    return TmdbSeasonDetails(
      id: id,
      seasonNumber: seasonNumber,
      name: name,
      overview: overview,
      posterUrl: posterUrl,
      airDate: airDate,
      episodes: released,
      allEpisodes: allEpisodes,
    );
  }

  /// Returns `true` if an episode in [allEpisodes] was previously unreleased
  /// when cached, has now reached its release date, and is missing full
  /// post-release metadata (such as `overview` or `runtimeMinutes`), signaling
  /// that a fresh TMDB season fetch should be triggered.
  bool hasNewlyReleasedIncompleteEpisode({DateTime? now}) {
    final releasedIds = {for (final ep in episodes) ep.episodeNumber};
    for (final ep in allEpisodes) {
      if (ep.isReleased(now: now) && !releasedIds.contains(ep.episodeNumber)) {
        if (ep.overview.isEmpty || ep.runtimeMinutes == null || ep.stillUrl == null) {
          return true;
        }
      }
    }
    return false;
  }

  /// Returns the earliest future calendar release [DateTime] among unreleased
  /// episodes in [allEpisodes], or `null` if all scheduled episodes have aired.
  DateTime? nextEpisodeReleaseDate({DateTime? now}) {
    DateTime? earliest;
    for (final ep in allEpisodes) {
      if (!ep.isReleased(now: now)) {
        final dt = ep.parsedAirDate;
        if (dt != null && (earliest == null || dt.isBefore(earliest))) {
          earliest = dt;
        }
      }
    }
    return earliest;
  }

  @override
  List<Object?> get props => [id, seasonNumber, name, episodes, allEpisodes];
}

/// Everything the Movie and Series details screens read from TMDB.
class TmdbMovieDetails extends Equatable {
  const TmdbMovieDetails({
    required this.tmdbId,
    required this.title,
    this.overview = '',
    this.backdropUrl,
    this.posterUrl,
    this.textlessPosterUrl,
    this.logoUrl,
    this.genres = const [],
    this.releaseYear,
    this.runtimeMinutes,
    this.voteAverage,
    this.cast = const [],
    this.recommendations = const [],
    this.similar = const [],
    List<TmdbRecommendation>? allRecommendations,
    List<TmdbRecommendation>? allSimilar,
    this.mediaType = 'movie',
    this.imdbId,
    this.originalLanguage,
    this.numberOfSeasons,
    this.numberOfEpisodes,
    this.seasons = const [],
    this.isExternalIdsResolved = false,
    this.userRating,
    this.isInMyList = false,
    this.keywordIds = const [],
    this.genreIds = const [],
    this.collectionId,
  })  : allRecommendations = allRecommendations ?? recommendations,
        allSimilar = allSimilar ?? similar;

  final int tmdbId;
  final String title;
  final String overview;
  final String? backdropUrl;
  final String? posterUrl;
  final String? textlessPosterUrl;
  final String? logoUrl;
  final List<String> genres;
  final String? releaseYear;
  final int? runtimeMinutes;
  final double? voteAverage;
  final List<TmdbCast> cast;
  final List<TmdbRecommendation> recommendations;
  final List<TmdbRecommendation> similar;
  final List<TmdbRecommendation> allRecommendations;
  final List<TmdbRecommendation> allSimilar;

  /// `'movie'` or `'series'`.
  final String mediaType;
  final String? imdbId;

  /// ISO 639-1 language code from TMDB (`original_language`), e.g. `'ja'`.
  final String? originalLanguage;

  /// Numeric TMDB keyword IDs bundled from `append_to_response=...,keywords`.
  final List<int> keywordIds;

  /// Numeric TMDB genre IDs for targeted `/discover` queries.
  final List<int> genreIds;

  /// TMDB franchise collection ID (`belongs_to_collection.id`), when part of a series.
  final int? collectionId;

  /// Whether TMDB metadata classifies this title as Japanese animation.
  bool get isJapaneseAnimation =>
      originalLanguage?.toLowerCase() == 'ja' &&
      genres.any((g) => g.toLowerCase() == 'animation');

  /// Series-specific metadata contract.
  final int? numberOfSeasons;
  final int? numberOfEpisodes;
  final List<TmdbSeasonSummary> seasons;

  /// Whether background external ID resolution for related items has completed.
  final bool isExternalIdsResolved;

  /// The user's personal TMDB rating (`0.5 .. 10.0`) if rated, or `null` if unrated.
  final double? userRating;

  /// Whether this movie or series is saved in the user's "My List".
  final bool isInMyList;

  /// Derived [TmdbUserReaction] based on [userRating] (`< 5.0` -> disliked, `>= 5.0` -> liked).
  TmdbUserReaction get userReaction => reactionFromRating(userRating);

  /// "105 min": the Figma "Duration" value for movies.
  String? get runtimeLabel => runtimeMinutes == null ? null : '$runtimeMinutes min';

  /// "3": the Figma "Seasons" telemetry value for TV shows / series.
  String? get seasonsCountLabel {
    if (numberOfSeasons != null && numberOfSeasons! > 0) {
      return '$numberOfSeasons';
    }
    final regularCount = seasons.where((s) => s.seasonNumber > 0).length;
    if (regularCount > 0) return '$regularCount';
    if (seasons.isNotEmpty) return '${seasons.length}';
    return null;
  }

  /// "7.1": the Figma "Rating" value.
  String? get ratingLabel => voteAverage == null ? null : voteAverage!.toStringAsFixed(1);

  /// Re-evaluates [allRecommendations] and [allSimilar] against [now] (or
  /// `DateTime.now()`) so newly released titles appear immediately.
  TmdbMovieDetails filterReleasedRelated({DateTime? now}) {
    final releasedRecs = [
      for (final r in allRecommendations)
        if (r.isReleased(now: now)) r,
    ];
    final releasedSim = [
      for (final s in allSimilar)
        if (s.isReleased(now: now)) s,
    ];
    if (releasedRecs.length == recommendations.length &&
        releasedSim.length == similar.length) {
      return this;
    }
    return copyWith(
      recommendations: releasedRecs,
      similar: releasedSim,
    );
  }

  /// Earliest future calendar release date among unreleased items in
  /// [allRecommendations] or [allSimilar], or `null` if none exist.
  DateTime? nextRelatedReleaseDate({DateTime? now}) {
    final nextRec = nextRecommendationReleaseDate(allRecommendations, now: now);
    final nextSim = nextRecommendationReleaseDate(allSimilar, now: now);
    if (nextRec == null) return nextSim;
    if (nextSim == null) return nextRec;
    return nextRec.isBefore(nextSim) ? nextRec : nextSim;
  }

  TmdbMovieDetails copyWith({
    String? title,
    String? overview,
    String? backdropUrl,
    String? posterUrl,
    String? textlessPosterUrl,
    String? logoUrl,
    List<String>? genres,
    String? releaseYear,
    int? runtimeMinutes,
    double? voteAverage,
    List<TmdbCast>? cast,
    List<TmdbRecommendation>? recommendations,
    List<TmdbRecommendation>? similar,
    List<TmdbRecommendation>? allRecommendations,
    List<TmdbRecommendation>? allSimilar,
    String? mediaType,
    String? imdbId,
    String? originalLanguage,
    int? numberOfSeasons,
    int? numberOfEpisodes,
    List<TmdbSeasonSummary>? seasons,
    bool? isExternalIdsResolved,
    double? userRating,
    bool clearUserRating = false,
    bool? isInMyList,
    List<int>? keywordIds,
    List<int>? genreIds,
    int? collectionId,
  }) =>
      TmdbMovieDetails(
        tmdbId: tmdbId,
        title: title ?? this.title,
        overview: overview ?? this.overview,
        backdropUrl: backdropUrl ?? this.backdropUrl,
        posterUrl: posterUrl ?? this.posterUrl,
        textlessPosterUrl: textlessPosterUrl ?? this.textlessPosterUrl,
        logoUrl: logoUrl ?? this.logoUrl,
        genres: genres ?? this.genres,
        releaseYear: releaseYear ?? this.releaseYear,
        runtimeMinutes: runtimeMinutes ?? this.runtimeMinutes,
        voteAverage: voteAverage ?? this.voteAverage,
        cast: cast ?? this.cast,
        recommendations: recommendations ?? this.recommendations,
        similar: similar ?? this.similar,
        allRecommendations: allRecommendations ?? this.allRecommendations,
        allSimilar: allSimilar ?? this.allSimilar,
        mediaType: mediaType ?? this.mediaType,
        imdbId: imdbId ?? this.imdbId,
        originalLanguage: originalLanguage ?? this.originalLanguage,
        numberOfSeasons: numberOfSeasons ?? this.numberOfSeasons,
        numberOfEpisodes: numberOfEpisodes ?? this.numberOfEpisodes,
        seasons: seasons ?? this.seasons,
        isExternalIdsResolved: isExternalIdsResolved ?? this.isExternalIdsResolved,
        userRating: clearUserRating ? null : (userRating ?? this.userRating),
        isInMyList: isInMyList ?? this.isInMyList,
        keywordIds: keywordIds ?? this.keywordIds,
        genreIds: genreIds ?? this.genreIds,
        collectionId: collectionId ?? this.collectionId,
      );

  @override
  List<Object?> get props => [
        tmdbId,
        mediaType,
        imdbId,
        originalLanguage,
        title,
        overview,
        backdropUrl,
        posterUrl,
        textlessPosterUrl,
        logoUrl,
        genres,
        releaseYear,
        runtimeMinutes,
        voteAverage,
        cast,
        recommendations,
        similar,
        allRecommendations,
        allSimilar,
        numberOfSeasons,
        numberOfEpisodes,
        seasons,
        isExternalIdsResolved,
        userRating,
        isInMyList,
        keywordIds,
        genreIds,
        collectionId,
      ];
}
