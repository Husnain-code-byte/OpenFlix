import 'dart:convert';

import 'package:equatable/equatable.dart';

String? _str(dynamic v) => v is String && v.trim().isNotEmpty ? v.trim() : null;

int? _int(dynamic v) => v is int ? v : (v is num ? v.toInt() : null);

List<CollectionCatalogSource> _parseSources(dynamic raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is Map<String, dynamic>)
        CollectionCatalogSource.fromJson(item)
      else if (item is Map)
        CollectionCatalogSource.fromJson(Map<String, dynamic>.from(item)),
  ];
}

/// Catalog source entry inside a premade collection folder.
class CollectionCatalogSource extends Equatable {
  const CollectionCatalogSource({
    required this.type,
    required this.addonId,
    required this.catalogId,
    this.genre,
    this.provider,
    this.title,
    this.sortBy,
    this.sortHow,
    this.tmdbId,
    this.mediaType,
    this.traktListId,
    this.tmdbSourceType,
  });

  final String type;
  final String? genre;
  final String addonId;
  final String catalogId;
  final String? provider;
  final String? title;
  final String? sortBy;
  final String? sortHow;
  final int? tmdbId;
  final String? mediaType;
  final String? traktListId;
  final String? tmdbSourceType;

  factory CollectionCatalogSource.fromJson(Map<String, dynamic> json) =>
      CollectionCatalogSource(
        type: _str(json['type']) ?? 'movie',
        genre: _str(json['genre']),
        addonId: _str(json['addonId']) ?? '',
        catalogId: _str(json['catalogId']) ?? '',
        provider: _str(json['provider']),
        title: _str(json['title']),
        sortBy: _str(json['sortBy']),
        sortHow: _str(json['sortHow']),
        tmdbId: _int(json['tmdbId']),
        mediaType: _str(json['mediaType']),
        traktListId: _str(json['traktListId']),
        tmdbSourceType: _str(json['tmdbSourceType']),
      );

  @override
  List<Object?> get props => [
        type,
        genre,
        addonId,
        catalogId,
        provider,
        title,
        sortBy,
        sortHow,
        tmdbId,
        mediaType,
        traktListId,
        tmdbSourceType,
      ];
}

/// One folder tile within a premade collection row.
class CollectionFolderModel extends Equatable {
  const CollectionFolderModel({
    required this.id,
    required this.title,
    this.hideTitle = true,
    this.tileShape = 'LANDSCAPE',
    this.coverEmoji,
    this.focusGifUrl,
    this.focusGifEnabled = false,
    this.coverImageUrl,
    this.titleLogoUrl,
    this.heroBackdropUrl,
    this.heroVideoUrl,
    this.focusVideoUrl,
    this.focusVideoWebmUrl,
    this.sources = const [],
    this.catalogSources = const [],
  });

  final String id;
  final String title;
  final bool hideTitle;
  final String tileShape;
  final String? coverEmoji;
  final String? focusGifUrl;
  final bool focusGifEnabled;
  final String? coverImageUrl;
  final String? titleLogoUrl;
  final String? heroBackdropUrl;
  final String? heroVideoUrl;
  final String? focusVideoUrl;
  final String? focusVideoWebmUrl;
  final List<CollectionCatalogSource> sources;
  final List<CollectionCatalogSource> catalogSources;

  /// Prioritizes animated [focusGifUrl] when enabled, falling back to [coverImageUrl].
  List<String?> get artworkUrls => [
        if (focusGifEnabled && focusGifUrl != null && focusGifUrl!.isNotEmpty)
          focusGifUrl,
        if (coverImageUrl != null && coverImageUrl!.isNotEmpty) coverImageUrl,
      ];

  factory CollectionFolderModel.fromJson(Map<String, dynamic> json) =>
      CollectionFolderModel(
        id: _str(json['id']) ?? '',
        title: _str(json['title']) ?? '',
        hideTitle: json['hideTitle'] is bool ? json['hideTitle'] as bool : true,
        tileShape: _str(json['tileShape']) ?? 'LANDSCAPE',
        coverEmoji: _str(json['coverEmoji']),
        focusGifUrl: _str(json['focusGifUrl']),
        focusGifEnabled: json['focusGifEnabled'] is bool
            ? json['focusGifEnabled'] as bool
            : false,
        coverImageUrl: _str(json['coverImageUrl']),
        titleLogoUrl: _str(json['titleLogoUrl']),
        heroBackdropUrl: _str(json['heroBackdropUrl']),
        heroVideoUrl: _str(json['heroVideoUrl']),
        focusVideoUrl: _str(json['focusVideoUrl']),
        focusVideoWebmUrl: _str(json['focusVideoWebmUrl']),
        sources: _parseSources(json['sources']),
        catalogSources: _parseSources(json['catalogSources']),
      );

  @override
  List<Object?> get props => [
        id,
        title,
        hideTitle,
        tileShape,
        coverEmoji,
        focusGifUrl,
        focusGifEnabled,
        coverImageUrl,
        titleLogoUrl,
        heroBackdropUrl,
        heroVideoUrl,
        focusVideoUrl,
        focusVideoWebmUrl,
        sources,
        catalogSources,
      ];
}

/// Top-level premade collection containing a list of themed folders.
class PremadeCollectionModel extends Equatable {
  const PremadeCollectionModel({
    required this.id,
    required this.title,
    this.folders = const [],
  });

  final String id;
  final String title;
  final List<CollectionFolderModel> folders;

  factory PremadeCollectionModel.fromJson(Map<String, dynamic> json) {
    final rawFolders = json['folders'];
    final parsedFolders = <CollectionFolderModel>[];
    if (rawFolders is List) {
      for (final item in rawFolders) {
        if (item is Map<String, dynamic>) {
          parsedFolders.add(CollectionFolderModel.fromJson(item));
        } else if (item is Map) {
          parsedFolders.add(
            CollectionFolderModel.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    return PremadeCollectionModel(
      id: _str(json['id']) ?? '',
      title: _str(json['title']) ?? '',
      folders: parsedFolders,
    );
  }

  /// Parses the root JSON array of premade collections.
  static List<PremadeCollectionModel> listFromJsonString(String rawJson) {
    final decoded = jsonDecode(rawJson);
    if (decoded is! List) return const [];
    final out = <PremadeCollectionModel>[];
    for (final item in decoded) {
      if (item is Map<String, dynamic>) {
        final model = PremadeCollectionModel.fromJson(item);
        if (model.folders.isNotEmpty) out.add(model);
      } else if (item is Map) {
        final model = PremadeCollectionModel.fromJson(
          Map<String, dynamic>.from(item),
        );
        if (model.folders.isNotEmpty) out.add(model);
      }
    }
    return out;
  }

  /// Filters all collections down to the default enabled set (Streaming, Genres, Studios, Film Collections).
  static List<PremadeCollectionModel> defaultCollectionsFromAll(
    List<PremadeCollectionModel> all,
  ) {
    final byId = {for (final c in all) c.id: c};
    final ordered = <PremadeCollectionModel>[
      for (final id in kDefaultCollectionIds)
        if (byId[id] != null) byId[id]!,
    ];
    if (ordered.isNotEmpty) return ordered;
    // Fallback by title match if custom IDs are used in tests.
    const defaultTitles = [
      'streaming',
      'genres',
      'genre',
      'studios',
      'film collections',
    ];
    final matched = <PremadeCollectionModel>[
      for (final c in all)
        if (defaultTitles.contains(c.title.toLowerCase())) c,
    ];
    return matched.isNotEmpty ? matched : all;
  }

  @override
  List<Object?> get props => [id, title, folders];
}

/// Default collection IDs enabled out of the box on the Collections screen:
/// 1. Streaming, 2. Genres, 3. Studios, 4. Film Collections.
const List<String> kDefaultCollectionIds = [
  '76d1a5f9-04ae-49cd-9a6f-4d8edfa50765', // Streaming
  'a0957a26-d26d-40c6-bce9-c3b21e4e8e58', // Genres
  '26de10b2-0b10-4237-8a6f-531a9b923e67', // Studios
  'f1c2aa90-a744-464d-879d-60f6df59c0e8', // Film Collections (TMDB Iconic Franchises)
];

/// One OTT hero GIF item displayed sequentially at the top of the Collections screen.
class CollectionHeroItem extends Equatable {
  const CollectionHeroItem({
    required this.id,
    required this.title,
    required this.gifUrl,
    this.fallbackCoverUrl,
    required this.tmdbWatchProviderId,
    required this.duration,
  });

  final String id;
  final String title;
  final String gifUrl;
  final String? fallbackCoverUrl;
  final int tmdbWatchProviderId;
  final Duration duration;

  @override
  List<Object?> get props => [
        id,
        title,
        gifUrl,
        fallbackCoverUrl,
        tmdbWatchProviderId,
        duration,
      ];
}

/// The 5 OTT hero GIFs shown sequentially at the top of the Collections screen:
/// Netflix, Disney+, Prime Video, HBO Max, and Hulu.
const List<CollectionHeroItem> kDefaultCollectionHeroItems = [
  CollectionHeroItem(
    id: 'netflix',
    title: 'Netflix',
    gifUrl:
        'https://cdn.jsdelivr.net/gh/luckynumb3rs/stremio-perfect-setup/collections/streaming/focused/netflix.webp',
    fallbackCoverUrl:
        'https://image.tmdb.org/t/p/w780/56v2KjBlU4XaOv9rVYEQypROD7P.jpg',
    tmdbWatchProviderId: 8,
    duration: Duration(milliseconds: 3600),
  ),
  CollectionHeroItem(
    id: 'disney_plus',
    title: 'Disney+',
    gifUrl:
        'https://64.media.tumblr.com/ca6dc6d4e8a260c0c5f40c47c7334e57/eb71329b4dc482d5-50/s500x750/e9e82c5bca839be289f3d87863141ebf6d7fca28.gifv',
    fallbackCoverUrl:
        'https://image.tmdb.org/t/p/w780/9zcbqSxdsRMZWHYtyCd1nXPr2xq.jpg',
    tmdbWatchProviderId: 337,
    duration: Duration(milliseconds: 3340),
  ),
  CollectionHeroItem(
    id: 'prime_video',
    title: 'Prime Video',
    gifUrl:
        'https://cdn.jsdelivr.net/gh/luckynumb3rs/stremio-perfect-setup/collections/streaming/focused/prime-video.webp',
    fallbackCoverUrl:
        'https://image.tmdb.org/t/p/w780/7cqKGQMnNabzOpi7qaIgZvQ7NGV.jpg',
    tmdbWatchProviderId: 9,
    duration: Duration(milliseconds: 6240),
  ),
  CollectionHeroItem(
    id: 'hbo_max',
    title: 'HBO Max',
    gifUrl:
        'https://64.media.tumblr.com/cca7a86d443a0bc88536a2ad6ce72aec/b495f88d5c1df470-a2/s640x960/4cb9b614191d17d02c946b4ca59548cd333c06fd.gifv',
    fallbackCoverUrl:
        'https://image.tmdb.org/t/p/w780/uDgy6hyPd82kOHh6I95FLtLnj6p.jpg',
    tmdbWatchProviderId: 1899,
    duration: Duration(milliseconds: 2500),
  ),
  CollectionHeroItem(
    id: 'hulu',
    title: 'Hulu',
    gifUrl:
        'https://cdn.jsdelivr.net/gh/luckynumb3rs/stremio-perfect-setup/collections/streaming/focused/hulu.webp',
    fallbackCoverUrl:
        'https://image.tmdb.org/t/p/w780/zPIug5giU8oug6Xes5K1sTfQJxY.jpg',
    tmdbWatchProviderId: 15,
    duration: Duration(milliseconds: 2680),
  ),
];
