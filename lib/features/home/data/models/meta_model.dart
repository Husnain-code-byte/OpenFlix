import 'package:equatable/equatable.dart';

String? _s(dynamic v) => v is String && v.trim().isNotEmpty ? v : null;

class MetaModel extends Equatable {
  const MetaModel({
    required this.id,
    required this.type,
    required this.name,
    this.poster,
    this.posterFallback,
    this.tallPoster,
    this.background,
    this.landscapePoster,
    this.logo,
    this.logoAspectRatio,
    this.description,
    this.genres = const [],
    this.releaseInfo,
    this.runtime,
    this.imdbRating,
    this.ageRating,
    this.notchText,
    this.sourceAddonId,
  });

  final String id;
  final String type;
  final String name;
  final String? poster;
  final String? posterFallback;
  final String? tallPoster;
  final String? background;
  final String? landscapePoster;
  final String? logo;
  final double? logoAspectRatio;
  final String? description;
  final List<String> genres;
  final String? releaseInfo;
  final String? runtime;
  final String? imdbRating;
  final String? ageRating;
  final String? notchText;
  final String? sourceAddonId;

  static MetaModel? tryParse(Map<String, dynamic> j) {
    final id = _s(j['id']);
    final name = _s(j['name']) ?? _s(j['title']);
    if (id == null || name == null) return null;

    var rating = _s(j['imdbRating']);
    if (rating == null && j['links'] is List) {
      final imdb = (j['links'] as List)
          .whereType<Map<String, dynamic>>()
          .where((l) => l['category'] == 'imdb');
      if (imdb.isNotEmpty) rating = _s(imdb.first['name']);
    }

    return MetaModel(
      id: id,
      type: _s(j['type']) ?? 'movie',
      name: name,
      poster: _s(j['poster']),
      posterFallback: _s(j['posterFallback']),
      tallPoster: _s(j['tallPoster']),
      background: _s(j['background']) ?? _s(j['banner']),
      landscapePoster: _s(j['landscapePoster']),
      logo: _s(j['logo']),
      logoAspectRatio: (j['logoAspectRatio'] as num?)?.toDouble(),
      description: _s(j['description']) ?? _s(j['overview']),
      genres: (j['genres'] as List?)?.whereType<String>().toList() ?? const [],
      releaseInfo: _s(j['releaseInfo']) ?? (j['year'] is int ? j['year'].toString() : null),
      runtime: _s(j['runtime']),
      imdbRating: rating,
      ageRating: _s(j['ageRating']),
      notchText: _s(j['notchText']),
      sourceAddonId: _s(j['sourceAddonId']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'name': name,
        if (poster != null) 'poster': poster,
        if (posterFallback != null) 'posterFallback': posterFallback,
        if (tallPoster != null) 'tallPoster': tallPoster,
        if (background != null) 'background': background,
        if (landscapePoster != null) 'landscapePoster': landscapePoster,
        if (logo != null) 'logo': logo,
        if (logoAspectRatio != null) 'logoAspectRatio': logoAspectRatio,
        if (description != null) 'description': description,
        if (genres.isNotEmpty) 'genres': genres,
        if (releaseInfo != null) 'releaseInfo': releaseInfo,
        if (runtime != null) 'runtime': runtime,
        if (imdbRating != null) 'imdbRating': imdbRating,
        if (ageRating != null) 'ageRating': ageRating,
        if (notchText != null) 'notchText': notchText,
        if (sourceAddonId != null) 'sourceAddonId': sourceAddonId,
      };

  /// Parses `{ "metas": [...] }`, dropping invalid and duplicate items.
  static List<MetaModel> listFromCatalogJson(Map<String, dynamic> json) {
    final raw = json['metas'];
    if (raw is! List) return const [];
    final seen = <String>{};
    final out = <MetaModel>[];
    for (final m in raw.whereType<Map<String, dynamic>>()) {
      final meta = tryParse(m);
      if (meta != null && seen.add(meta.id)) out.add(meta);
    }
    return out;
  }

  MetaModel copyWith({
    String? id,
    String? type,
    String? name,
    String? poster,
    String? posterFallback,
    String? tallPoster,
    String? background,
    String? landscapePoster,
    String? logo,
    double? logoAspectRatio,
    String? description,
    List<String>? genres,
    String? releaseInfo,
    String? runtime,
    String? imdbRating,
    String? ageRating,
    String? notchText,
    String? sourceAddonId,
  }) =>
      MetaModel(
        id: id ?? this.id,
        type: type ?? this.type,
        name: name ?? this.name,
        poster: poster ?? this.poster,
        posterFallback: posterFallback ?? this.posterFallback,
        tallPoster: tallPoster ?? this.tallPoster,
        background: background ?? this.background,
        landscapePoster: landscapePoster ?? this.landscapePoster,
        logo: logo ?? this.logo,
        logoAspectRatio: logoAspectRatio ?? this.logoAspectRatio,
        description: description ?? this.description,
        genres: genres ?? this.genres,
        releaseInfo: releaseInfo ?? this.releaseInfo,
        runtime: runtime ?? this.runtime,
        imdbRating: imdbRating ?? this.imdbRating,
        ageRating: ageRating ?? this.ageRating,
        notchText: notchText ?? this.notchText,
        sourceAddonId: sourceAddonId ?? this.sourceAddonId,
      );

  @override
  List<Object?> get props => [
        id,
        type,
        poster,
        posterFallback,
        tallPoster,
        background,
        landscapePoster,
        logo,
        logoAspectRatio,
        ageRating,
        notchText,
        sourceAddonId,
      ];
}
