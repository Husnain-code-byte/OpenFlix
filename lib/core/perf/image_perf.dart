import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Disk cache tuned for low-RAM devices: images survive 30 days so returning
/// to the app never re-downloads posters, but the store is capped.
class PixelImageCache extends CacheManager {
  static const cacheKey = 'pixel_img_cache_v2';

  PixelImageCache._()
      : super(Config(
          cacheKey,
          stalePeriod: const Duration(days: 30),
          maxNrOfCacheObjects: 350,
          fileService: HttpFileService(),
        ));

  static final PixelImageCache instance = PixelImageCache._();
}

/// TMDB serves fixed width buckets. The addon hands out `original`/`w500`
/// URLs even for 113px cards — decoding a 2000px JPEG into a 339px slot is the
/// single biggest source of jank and slow poster loads on 3GB devices.
/// Bucket the URL down to what is actually displayed.
String tmdbSized(String? url, {required int forWidthPx}) {
  if (url == null || !url.contains('image.tmdb.org/t/p/')) return url ?? '';
  final bucket = forWidthPx <= 300
      ? 'w342'
      : forWidthPx <= 600
          ? 'w500'
          : forWidthPx <= 900
              ? 'w780'
              : forWidthPx <= 1280
                  ? 'w1280'
                  : 'original';
  return url.replaceFirst(RegExp(r'/t/p/(original|w\d+)/'), '/t/p/$bucket/');
}

/// Resizes every TMDB URL in a fallback chain; proxied URLs pass through.
List<String> sizedChain(List<String?> urls, {required int forWidthPx}) => [
      for (final u in urls)
        if (u != null && u.isNotEmpty) tmdbSized(u, forWidthPx: forWidthPx),
    ];

/// Styled poster from the Better Posters service (btttr.cc):
///   https://btttr.cc/poster-a/imdb/poster-default/{imdb_id}.jpg
String betterPosterUrl(String imdbId) {
  final cleanId = imdbId.startsWith('tt') ? imdbId : 'tt$imdbId';
  return 'https://btttr.cc/poster-a/imdb/poster-default/$cleanId.jpg';
}

/// Fallback poster service for items where Better Posters is not applicable.
String postersPlusUrl({
  required String type, // 'movie' | 'series'
  required String id, // 'tt…' or a TMDB id
  String shape = 'portrait',
}) =>
    'https://postersplus.elfhosted.com/p/clean_notch/$type/$id.jpg?shape=$shape';
