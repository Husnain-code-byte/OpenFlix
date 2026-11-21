import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/api_constants.dart';

class HeroArtwork extends Equatable {
  const HeroArtwork({this.posterUrl, this.backdropUrl, this.logoUrl});

  final String? posterUrl;
  final String? backdropUrl;
  final String? logoUrl;

  @override
  List<Object?> get props => [posterUrl, backdropUrl, logoUrl];
}

typedef HeroArtworkKey = ({String imdbId, String type});

/// Resolves an IMDb id and selects TMDB's best language-neutral poster,
/// backdrop and English logo. Results are memoized for the session.
class HeroArtworkRepository {
  HeroArtworkRepository(this._dio);

  final Dio _dio;
  final Map<HeroArtworkKey, HeroArtwork?> _cache = {};
  final Map<HeroArtworkKey, Future<HeroArtwork?>> _inflight = {};

  Future<HeroArtwork?> fetch(HeroArtworkKey key) {
    if (_cache.containsKey(key)) return Future.value(_cache[key]);
    return _inflight.putIfAbsent(key, () {
      final future = _fetch(key);
      future.then((value) => _cache[key] = value, onError: (_) {}).whenComplete(() => _inflight.remove(key));
      return future;
    });
  }

  Future<HeroArtwork?> _fetch(HeroArtworkKey key) async {
    var resource = key.type == 'series' ? 'tv' : 'movie';
    int? id = int.tryParse(key.imdbId);
    if (id == null) {
      if (!key.imdbId.startsWith('tt')) return null;
      final find = await _get('/find/${key.imdbId}', {'external_source': 'imdb_id'});
      final resultKey = key.type == 'series' ? 'tv_results' : 'movie_results';
      final fallbackKey = key.type == 'series' ? 'movie_results' : 'tv_results';
      final primaryHits = _maps(find[resultKey]);
      final fallbackHits = _maps(find[fallbackKey]);
      if (primaryHits.isNotEmpty && primaryHits.first['id'] is num) {
        id = (primaryHits.first['id'] as num).toInt();
      } else if (fallbackHits.isNotEmpty && fallbackHits.first['id'] is num) {
        id = (fallbackHits.first['id'] as num).toInt();
        resource = key.type == 'series' ? 'movie' : 'tv';
      } else {
        return null;
      }
    }

    final images = await _get('/$resource/$id/images', {'include_image_language': 'en,null'});
    final poster = _best(_maps(images['posters']), language: null);
    final backdrop = _best(_maps(images['backdrops']), language: null);
    final logo = _best(_maps(images['logos']), language: 'en');

    return HeroArtwork(
      posterUrl: _url(poster?['file_path'], 'w780'),
      backdropUrl: _url(backdrop?['file_path'], 'w780'),
      logoUrl: _url(logo?['file_path'], 'original'),
    );
  }

  Future<Map<String, dynamic>> _get(String path, Map<String, dynamic> query) async {
    final res = await _dio.get<dynamic>(
      '${ApiConstants.tmdbBaseUrl}$path',
      queryParameters: {...query, 'api_key': ApiConstants.tmdbApiKey},
    );
    return res.data is Map<String, dynamic> ? res.data as Map<String, dynamic> : const {};
  }

  static List<Map<String, dynamic>> _maps(dynamic value) => value is List
      ? [for (final item in value) if (item is Map<String, dynamic>) item]
      : const [];

  static Map<String, dynamic>? _best(List<Map<String, dynamic>> images, {String? language}) {
    if (images.isEmpty) return null;
    final preferred = images.where((i) => i['iso_639_1'] == language).toList();
    final pool = preferred.isEmpty ? images : preferred;
    pool.sort((a, b) {
      double score(Map<String, dynamic> i) =>
          ((i['vote_average'] as num?)?.toDouble() ?? 0) * 10 +
          ((i['vote_count'] as num?)?.toDouble() ?? 0);
      return score(b).compareTo(score(a));
    });
    return pool.first;
  }

  static String? _url(dynamic path, String size) => path is String && path.isNotEmpty
      ? '${ApiConstants.tmdbImageUrl}/$size$path'
      : null;
}

final heroArtworkDioProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    connectTimeout: ApiConstants.connectTimeout,
    receiveTimeout: ApiConstants.receiveTimeout,
    responseType: ResponseType.json,
  ));
  dio.transformer = BackgroundTransformer();
  ref.onDispose(() => dio.close(force: true));
  return dio;
});

final heroArtworkRepositoryProvider = Provider<HeroArtworkRepository>(
  (ref) => HeroArtworkRepository(ref.watch(heroArtworkDioProvider)),
);

final heroArtworkProvider = FutureProvider.family<HeroArtwork?, HeroArtworkKey>(
  (ref, key) => ref.watch(heroArtworkRepositoryProvider).fetch(key),
);