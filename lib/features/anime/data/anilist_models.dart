import 'package:equatable/equatable.dart';

class AniListTitle extends Equatable {
  const AniListTitle({this.romaji, this.english});

  final String? romaji;
  final String? english;

  String get displayTitle =>
      (english != null && english!.trim().isNotEmpty) ? english!.trim() : (romaji ?? '');

  factory AniListTitle.fromJson(Map<String, dynamic> json) => AniListTitle(
        romaji: json['romaji'] as String?,
        english: json['english'] as String?,
      );

  @override
  List<Object?> get props => [romaji, english];
}

class AniListMedia extends Equatable {
  const AniListMedia({
    required this.id,
    this.idMal,
    required this.title,
    this.format,
    this.status,
    this.seasonYear,
    this.startDateYear,
    this.startDateMonth,
    this.startDateDay,
    this.episodes,
    this.genres = const [],
    this.averageScore,
    this.popularity,
    this.isAdult = false,
    this.coverLarge,
    this.bannerImage,
  });

  final int id;
  final int? idMal;
  final AniListTitle title;
  final String? format;
  final String? status;
  final int? seasonYear;
  final int? startDateYear;
  final int? startDateMonth;
  final int? startDateDay;
  final int? episodes;
  final List<String> genres;
  final int? averageScore;
  final int? popularity;
  final bool isAdult;
  final String? coverLarge;
  final String? bannerImage;

  /// Returns `true` only once this anime has released (`status != NOT_YET_RELEASED`
  /// and its `startDate` / `seasonYear` is not in the future relative to [now]).
  bool isReleased({DateTime? now}) {
    final ref = now ?? DateTime.now();
    final today = DateTime(ref.year, ref.month, ref.day);
    final normStatus = status?.trim().toUpperCase();
    if (normStatus == 'NOT_YET_RELEASED') {
      return false;
    }
    if (normStatus == 'CANCELLED' &&
        startDateYear == null &&
        seasonYear == null) {
      return false;
    }
    if (startDateYear != null) {
      if (startDateYear! > today.year) return false;
      if (startDateYear! == today.year && startDateMonth != null) {
        if (startDateMonth! > today.month) return false;
        if (startDateMonth! == today.month && startDateDay != null) {
          if (startDateDay! > today.day) return false;
        }
      }
      return true;
    }
    if (seasonYear != null && seasonYear! > today.year) {
      return false;
    }
    if (normStatus == 'FINISHED' ||
        normStatus == 'RELEASING' ||
        normStatus == 'HIATUS') {
      return true;
    }
    return seasonYear != null ? seasonYear! <= today.year : normStatus != null;
  }

  static AniListMedia? tryParse(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! int) return null;

    final titleJson = json['title'];
    final title = titleJson is Map<String, dynamic>
        ? AniListTitle.fromJson(titleJson)
        : const AniListTitle();

    final coverJson = json['coverImage'];
    final coverLarge = coverJson is Map<String, dynamic>
        ? ((coverJson['extraLarge'] as String?) ?? (coverJson['large'] as String?))
        : null;

    final startJson = json['startDate'];
    final startYear =
        startJson is Map<String, dynamic> ? startJson['year'] as int? : null;
    final startMonth =
        startJson is Map<String, dynamic> ? startJson['month'] as int? : null;
    final startDay =
        startJson is Map<String, dynamic> ? startJson['day'] as int? : null;

    final genresRaw = json['genres'];
    final genres = genresRaw is List
        ? genresRaw.whereType<String>().toList()
        : const <String>[];

    return AniListMedia(
      id: id,
      idMal: json['idMal'] as int?,
      title: title,
      format: json['format'] as String?,
      status: json['status'] as String?,
      seasonYear: json['seasonYear'] as int?,
      startDateYear: startYear,
      startDateMonth: startMonth,
      startDateDay: startDay,
      episodes: json['episodes'] as int?,
      genres: genres,
      averageScore: json['averageScore'] as int?,
      popularity: json['popularity'] as int?,
      isAdult: json['isAdult'] == true,
      coverLarge: coverLarge,
      bannerImage: json['bannerImage'] as String?,
    );
  }

  @override
  List<Object?> get props => [
        id,
        idMal,
        format,
        status,
        seasonYear,
        startDateYear,
        startDateMonth,
        startDateDay,
        coverLarge,
      ];
}
