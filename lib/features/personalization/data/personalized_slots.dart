import 'package:equatable/equatable.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/responsive.dart';
import '../../home/data/models/manifest_model.dart';
import '../../home/data/models/meta_model.dart';
import '../../home/presentation/controllers/home_controller.dart';
import '../../player/domain/models/watch_progress_models.dart';

/// Visual card layout for personalized recommendation rows.
enum PersonalizedRowStyle {
  /// Ultra-tall vertical showcase card (`176×312`, radius `10`, Figma `124:543`)
  /// used for `"Because you liked <Title>"` rows.
  tall,

  /// Horizontal 16:9 showcase card (`305×172`, radius `12`, Figma `124:340` / `124:363`)
  /// used for `"Because you added <Title> to your list"` rows.
  landscape,
}

/// The 6 daily personalization buckets across Home, Movies, TV Shows, and Anime.
enum PersonalizationBucket {
  likedMovie(
    key: 'liked_movie',
    style: PersonalizedRowStyle.tall,
    isLikedSource: true,
    mediaType: 'movie',
    isAnime: false,
  ),
  myListMovie(
    key: 'mylist_movie',
    style: PersonalizedRowStyle.landscape,
    isLikedSource: false,
    mediaType: 'movie',
    isAnime: false,
  ),
  likedSeries(
    key: 'liked_series',
    style: PersonalizedRowStyle.tall,
    isLikedSource: true,
    mediaType: 'series',
    isAnime: false,
  ),
  myListSeries(
    key: 'mylist_series',
    style: PersonalizedRowStyle.landscape,
    isLikedSource: false,
    mediaType: 'series',
    isAnime: false,
  ),
  likedAnime(
    key: 'liked_anime',
    style: PersonalizedRowStyle.tall,
    isLikedSource: true,
    mediaType: 'series',
    isAnime: true,
  ),
  myListAnime(
    key: 'mylist_anime',
    style: PersonalizedRowStyle.landscape,
    isLikedSource: false,
    mediaType: 'series',
    isAnime: true,
  );

  const PersonalizationBucket({
    required this.key,
    required this.style,
    required this.isLikedSource,
    required this.mediaType,
    required this.isAnime,
  });

  final String key;
  final PersonalizedRowStyle style;
  final bool isLikedSource;
  final String mediaType;
  final bool isAnime;

  /// Formats the row heading using the picked source title.
  String formatHeading(String sourceTitle) => isLikedSource
      ? 'Because you liked $sourceTitle'
      : 'Because you added $sourceTitle to your list';
}

/// Hardcoded slot positions, card dimensions, and limits for personalized rows.
class PersonalizedSlots {
  PersonalizedSlots._();

  /// 1-indexed feed positions after the Hero Banner on Home (`2, 5, 8, 11`),
  /// placing P1 right after Catalog #1 with 2 regular catalog rows between each
  /// personalized row.
  static const List<int> homePositions = [2, 5, 8, 11];

  /// 1-indexed feed positions after the Hero Banner on Movies, TV Shows, and Anime (`2, 5`).
  static const List<int> filteredPositions = [2, 5];

  /// Maximum number of displayed cards per personalized row (matching the 20 posters
  /// displayed in the details screen related rows).
  static const int maxRowItems = 20;

  /// Number of candidate recommendations inspected per bucket to allow backfilling
  /// items missing strict textless artwork.
  static const int candidateFetchLimit = 36;

  // ── Ultra-Tall Card Specs (Figma 124:543 + 5% height: 176×328, radius 6) ──
  static double get tallWidth => 176.w;
  static double get tallHeight => 328.w;
  static double get tallRadius => 6.r;
  static double get tallStride => tallWidth + AppDimens.posterGap;

  // ── Landscape Card Specs (Figma 124:340 & 124:363: 305×172, radius 7) ────
  static double get landscapeWidth => 305.w;
  static double get landscapeHeight => 172.w;
  static double get landscapeRadius => 7.r;
  static double get landscapeStride => landscapeWidth + AppDimens.posterGap;

  /// Returns the ordered buckets that belong to [filter].
  static List<PersonalizationBucket> bucketsForFilter(HomeFilter filter) =>
      switch (filter) {
        HomeFilter.home => const [
            PersonalizationBucket.likedMovie,
            PersonalizationBucket.myListMovie,
            PersonalizationBucket.likedSeries,
            PersonalizationBucket.myListSeries,
          ],
        HomeFilter.movies => const [
            PersonalizationBucket.likedMovie,
            PersonalizationBucket.myListMovie,
          ],
        HomeFilter.tvShows => const [
            PersonalizationBucket.likedSeries,
            PersonalizationBucket.myListSeries,
          ],
        HomeFilter.anime => const [
            PersonalizationBucket.likedAnime,
            PersonalizationBucket.myListAnime,
          ],
        HomeFilter.categories => const [],
      };

  /// Returns the 1-indexed feed positions for [filter].
  static List<int> positionsForFilter(HomeFilter filter) => switch (filter) {
        HomeFilter.home => homePositions,
        HomeFilter.movies ||
        HomeFilter.tvShows ||
        HomeFilter.anime =>
          filteredPositions,
        HomeFilter.categories => const [],
      };
}

/// Resolved data for a single personalized recommendation row.
class PersonalizedRowData extends Equatable {
  const PersonalizedRowData({
    required this.bucket,
    required this.sourceMeta,
    required this.items,
    this.isLoading = false,
  });

  final PersonalizationBucket bucket;
  final MetaModel sourceMeta;
  final List<MetaModel> items;
  final bool isLoading;

  String get title => bucket.formatHeading(sourceMeta.name);
  PersonalizedRowStyle get style => bucket.style;

  PersonalizedRowData copyWith({
    MetaModel? sourceMeta,
    List<MetaModel>? items,
    bool? isLoading,
  }) =>
      PersonalizedRowData(
        bucket: bucket,
        sourceMeta: sourceMeta ?? this.sourceMeta,
        items: items ?? this.items,
        isLoading: isLoading ?? this.isLoading,
      );

  @override
  List<Object?> get props => [bucket, sourceMeta, items, isLoading];
}

/// Discriminated union for a single row in the Home/Movies/TV/Anime feed.
sealed class HomeFeedEntry extends Equatable {
  const HomeFeedEntry();
}

class CatalogFeedEntry extends HomeFeedEntry {
  const CatalogFeedEntry(this.catalog);
  final CatalogItemModel catalog;

  @override
  List<Object?> get props => [catalog.key];
}

class PersonalizedFeedEntry extends HomeFeedEntry {
  const PersonalizedFeedEntry(this.row);
  final PersonalizedRowData row;

  @override
  List<Object?> get props => [row];
}

class ContinueWatchingFeedEntry extends HomeFeedEntry {
  const ContinueWatchingFeedEntry(this.entries);
  final List<WatchProgressEntry> entries;

  @override
  List<Object?> get props => [entries];
}

/// Merges [catalogs] and active [personalizedRows] so personalized rows land at
/// the 1-indexed [slotPositions] (e.g. `2, 5, 8, 11` on Home; `2, 5` on Movies/TV/Anime),
/// and inserts [continueWatchingEntries] (when non-empty) at 1-indexed Row #3.
///
/// Rules:
/// - Slots are filled in rank order by whichever rows are non-empty (or loading),
///   so missing buckets never leave gaps.
/// - If [catalogs] is shorter than a target slot position, remaining personalized
///   rows are interleaved with at least 1 catalog between them when available.
List<HomeFeedEntry> mergeFeedEntries({
  required List<CatalogItemModel> catalogs,
  required List<PersonalizedRowData> personalizedRows,
  required List<int> slotPositions,
  List<WatchProgressEntry> continueWatchingEntries = const [],
}) {
  final activeRows = personalizedRows
      .where((r) => r.isLoading || r.items.isNotEmpty)
      .toList(growable: false);

  List<HomeFeedEntry> withContinueWatching(List<HomeFeedEntry> base) {
    if (continueWatchingEntries.isEmpty) return base;
    final out = List<HomeFeedEntry>.from(base);
    // 1-indexed Row #3 -> 0-indexed position 2 (clamped if fewer than 2 rows exist)
    final insertIdx = out.length >= 2 ? 2 : out.length;
    out.insert(insertIdx, ContinueWatchingFeedEntry(continueWatchingEntries));
    return out;
  }

  if (activeRows.isEmpty || slotPositions.isEmpty) {
    return withContinueWatching([for (final c in catalogs) CatalogFeedEntry(c)]);
  }
  if (catalogs.isEmpty) {
    return withContinueWatching(
      [for (final r in activeRows) PersonalizedFeedEntry(r)],
    );
  }

  final out = <HomeFeedEntry>[];
  var catIdx = 0;
  var pIdx = 0;

  while (catIdx < catalogs.length || pIdx < activeRows.length) {
    final nextFeedPos = out.length + 1; // 1-indexed position in merged feed
    final targetSlot = pIdx < slotPositions.length
        ? slotPositions[pIdx]
        : (slotPositions.last + (pIdx - slotPositions.length + 1) * 3);

    if (pIdx < activeRows.length &&
        (nextFeedPos == targetSlot || catIdx >= catalogs.length)) {
      out.add(PersonalizedFeedEntry(activeRows[pIdx]));
      pIdx++;
      // If we ran out of catalogs early, still interleave remaining catalogs if any.
    } else if (catIdx < catalogs.length) {
      out.add(CatalogFeedEntry(catalogs[catIdx]));
      catIdx++;
    }
  }

  return withContinueWatching(out);
}
