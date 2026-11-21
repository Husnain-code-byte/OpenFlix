import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/api_constants.dart';
import '../../../core/network/dio_client.dart';
import '../../home/data/models/manifest_model.dart';
import '../../home/data/models/meta_model.dart';
import '../domain/models/addon_models.dart';
import '../domain/models/stream_models.dart';

class StremioVideoEntry {
  const StremioVideoEntry({
    required this.id,
    required this.title,
    this.season = 1,
    this.episode = 1,
    this.released,
    this.overview,
    this.thumbnail,
  });

  final String id;
  final String title;
  final int season;
  final int episode;
  final String? released;
  final String? overview;
  final String? thumbnail;
}

class StremioMetaPayload {
  const StremioMetaPayload({
    required this.meta,
    this.cast = const [],
    this.director = const [],
    this.country,
    this.imdbId,
    this.videos = const [],
  });

  final MetaModel meta;
  final List<String> cast;
  final List<String> director;
  final String? country;
  final String? imdbId;
  final List<StremioVideoEntry> videos;
}

class StremioAddonService {
  StremioAddonService(this._dio);

  final Dio _dio;

  static final RegExp _qualityRegex = RegExp(
    r'\b(2160p|4k|uhd|1440p|2k|1080p|fhd|720p|hd|480p|360p)\b',
    caseSensitive: false,
  );

  /// Normalizes a user-pasted manifest URL (`stremio://`, bare host, or
  /// configured path) to `https://.../manifest.json`.
  static String normalizeManifestUrl(String raw) {
    var trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Manifest URL cannot be empty.');
    }

    if (trimmed.toLowerCase().startsWith('stremio://')) {
      trimmed = 'https://${trimmed.substring('stremio://'.length)}';
    } else if (!trimmed.contains('://') &&
        !trimmed.contains(' ') &&
        trimmed.contains('.')) {
      trimmed = 'https://$trimmed';
    }

    final uri = Uri.tryParse(trimmed);
    if (uri == null || !uri.hasScheme || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      throw const FormatException(
        'Enter an http://, https://, or stremio:// addon manifest URL.',
      );
    }

    final pathLower = uri.path.toLowerCase();
    if (pathLower.endsWith('/manifest.json') || pathLower == 'manifest.json') {
      return uri.toString();
    }
    if (pathLower.endsWith('/configure') || pathLower.endsWith('/configure/')) {
      final replaced = uri.path.replaceFirst(
        RegExp(r'/configure/?$', caseSensitive: false),
        '/manifest.json',
      );
      return uri.replace(path: replaced).toString();
    }

    final cleanPath = uri.path.replaceAll(RegExp(r'/+$'), '');
    final updated = uri.replace(path: '$cleanPath/manifest.json');
    return updated.toString();
  }

  static String deriveBaseUrl(String manifestUrl) =>
      ApiConstants.deriveBaseUrl(manifestUrl).replaceAll(RegExp(r'/+$'), '');

  static String deriveConfigureUrl(String manifestUrl) =>
      '${deriveBaseUrl(manifestUrl)}/configure';

  /// Redacts encoded configuration path segments in log/error strings so user
  /// Debrid API keys inside Stremio URLs are never exposed.
  static String sanitizeUrlForError(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return 'addon URL';
    return '${uri.scheme}://${uri.host}/.../manifest.json';
  }

  Future<Map<String, dynamic>> _getJsonObject(
    String url, {
    CancelToken? cancelToken,
  }) async {
    final res = await _dio.get<dynamic>(
      url,
      cancelToken: cancelToken,
      options: Options(responseType: ResponseType.plain),
    );
    final raw = res.data;
    final dynamic decoded = raw is String ? jsonDecode(raw) : raw;
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw const FormatException('Addon returned a non-object JSON payload');
  }

  Future<ManifestModel> fetchManifest(
    String rawUrl, {
    CancelToken? cancelToken,
  }) async {
    final normalized = normalizeManifestUrl(rawUrl);
    final json = await _getJsonObject(normalized, cancelToken: cancelToken);
    final manifest = ManifestModel.fromJson(json);
    if (manifest.id.trim().isEmpty || manifest.id == 'unknown') {
      throw const FormatException('Manifest is missing required "id" field.');
    }
    if (manifest.name.trim().isEmpty) {
      throw const FormatException('Manifest is missing required "name" field.');
    }
    return manifest;
  }

  Future<List<MetaModel>> fetchCatalog(
    String baseUrl,
    CatalogItemModel catalog, {
    String? sourceAddonId,
    int skip = 0,
    String? search,
    String? genre,
    CancelToken? cancelToken,
  }) async {
    final type = Uri.encodeComponent(catalog.type);
    final id = Uri.encodeComponent(catalog.id);

    final extraSegments = <String>[];
    if (search != null && search.trim().isNotEmpty) {
      extraSegments.add('search=${Uri.encodeComponent(search.trim())}');
    }
    if (genre != null && genre.trim().isNotEmpty) {
      extraSegments.add('genre=${Uri.encodeComponent(genre.trim())}');
    }
    if (skip > 0) {
      extraSegments.add('skip=$skip');
    }

    final cleanBase = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final url = extraSegments.isEmpty
        ? '$cleanBase/catalog/$type/$id.json'
        : '$cleanBase/catalog/$type/$id/${extraSegments.join('&')}.json';

    final json = await _getJsonObject(url, cancelToken: cancelToken);
    final list = MetaModel.listFromCatalogJson(json);
    if (sourceAddonId == null) return list;
    return [
      for (final m in list) m.copyWith(sourceAddonId: sourceAddonId),
    ];
  }

  Future<StremioMetaPayload?> fetchMeta(
    String baseUrl,
    String type,
    String id, {
    String? sourceAddonId,
    CancelToken? cancelToken,
  }) async {
    final cleanBase = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final url =
        '$cleanBase/meta/${Uri.encodeComponent(type)}/${Uri.encodeComponent(id)}.json';
    final json = await _getJsonObject(url, cancelToken: cancelToken);
    final rawMeta = json['meta'];
    if (rawMeta is! Map) return null;
    final metaMap = Map<String, dynamic>.from(rawMeta);
    final parsed = MetaModel.tryParse(metaMap);
    if (parsed == null) return null;

    final videosRaw = metaMap['videos'];
    final videos = <StremioVideoEntry>[];
    if (videosRaw is List) {
      for (final item in videosRaw.whereType<Map>()) {
        final m = Map<String, dynamic>.from(item);
        final vid = m['id']?.toString() ?? '';
        if (vid.isEmpty) continue;
        videos.add(
          StremioVideoEntry(
            id: vid,
            title: (m['title'] ?? m['name'] ?? 'Episode').toString(),
            season: (m['season'] as num?)?.toInt() ?? 1,
            episode: (m['episode'] as num?)?.toInt() ?? (videos.length + 1),
            released: m['released'] as String?,
            overview: m['overview'] as String?,
            thumbnail: m['thumbnail'] as String?,
          ),
        );
      }
    }

    final imdbRaw = metaMap['imdb_id']?.toString() ??
        (parsed.id.startsWith('tt') ? parsed.id : null);

    return StremioMetaPayload(
      meta: sourceAddonId != null
          ? parsed.copyWith(sourceAddonId: sourceAddonId)
          : parsed,
      cast: (metaMap['cast'] as List?)?.whereType<String>().toList() ?? const [],
      director:
          (metaMap['director'] as List?)?.whereType<String>().toList() ?? const [],
      country: metaMap['country'] as String?,
      imdbId: imdbRaw,
      videos: videos,
    );
  }

  Future<List<ResolvedStream>> fetchStreams(
    InstalledStremioAddon addon,
    String type,
    String videoId, {
    CancelToken? cancelToken,
  }) async {
    final cleanBase = addon.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final url =
        '$cleanBase/stream/${Uri.encodeComponent(type)}/${Uri.encodeComponent(videoId)}.json';
    final json = await _getJsonObject(url, cancelToken: cancelToken);
    final rawStreams = json['streams'];
    if (rawStreams is! List) return const [];

    final results = <ResolvedStream>[];
    for (var i = 0; i < rawStreams.length; i++) {
      final raw = rawStreams[i];
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final parsed = _parseStreamMap(addon, m, i);
      if (parsed != null) results.add(parsed);
    }
    return results;
  }

  Future<List<ResolvedSubtitle>> fetchSubtitles(
    InstalledStremioAddon addon,
    String type,
    String videoId, {
    CancelToken? cancelToken,
  }) async {
    final cleanBase = addon.baseUrl.replaceAll(RegExp(r'/+$'), '');
    final url =
        '$cleanBase/subtitles/${Uri.encodeComponent(type)}/${Uri.encodeComponent(videoId)}.json';
    final json = await _getJsonObject(url, cancelToken: cancelToken);
    final rawSubs = json['subtitles'];
    if (rawSubs is! List) return const [];

    final out = <ResolvedSubtitle>[];
    for (final raw in rawSubs.whereType<Map>()) {
      final m = Map<String, dynamic>.from(raw);
      final subUrl = m['url']?.toString().trim() ?? '';
      if (subUrl.isEmpty) continue;
      out.add(
        ResolvedSubtitle(
          url: subUrl,
          language: m['lang']?.toString() ?? 'und',
          label: m['id']?.toString(),
          sourceName: addon.manifest.name,
        ),
      );
    }
    return out;
  }

  ResolvedStream? _parseStreamMap(
    InstalledStremioAddon addon,
    Map<String, dynamic> m,
    int index,
  ) {
    final url = (m['url'] as String?)?.trim();
    final infoHash = (m['infoHash'] as String?)?.trim();
    final ytId = (m['ytId'] as String?)?.trim();
    final externalUrl = (m['externalUrl'] as String?)?.trim();

    if ((url == null || url.isEmpty) &&
        (infoHash == null || infoHash.isEmpty) &&
        (ytId == null || ytId.isEmpty) &&
        (externalUrl == null || externalUrl.isEmpty)) {
      return null;
    }

    final behaviorHints = m['behaviorHints'] is Map
        ? Map<String, dynamic>.from(m['behaviorHints'] as Map)
        : const <String, dynamic>{};

    final headers = <String, String>{};
    final proxyHeaders = behaviorHints['proxyHeaders'];
    if (proxyHeaders is Map && proxyHeaders['request'] is Map) {
      final req = Map<String, dynamic>.from(proxyHeaders['request'] as Map);
      req.forEach((k, v) {
        if (v != null) headers[k.toString()] = v.toString();
      });
    }

    final transport = _detectTransport(
      url: url,
      infoHash: infoHash,
      ytId: ytId,
      externalUrl: externalUrl,
    );

    final rawName = (m['name'] as String?)?.trim() ?? addon.manifest.name;
    final rawDesc =
        ((m['description'] ?? m['title']) as String?)?.trim();
    final combinedText = '$rawName ${rawDesc ?? ''} ${behaviorHints['filename'] ?? ''}';
    final (qualityLabel, qualityRank) = extractQuality(combinedText);

    final subs = <ResolvedSubtitle>[];
    if (m['subtitles'] is List) {
      for (final s in (m['subtitles'] as List).whereType<Map>()) {
        final sm = Map<String, dynamic>.from(s);
        final sUrl = sm['url']?.toString().trim() ?? '';
        if (sUrl.isEmpty) continue;
        subs.add(
          ResolvedSubtitle(
            url: sUrl,
            language: sm['lang']?.toString() ?? 'und',
            label: sm['id']?.toString(),
            sourceName: addon.manifest.name,
          ),
        );
      }
    }

    return ResolvedStream(
      id: '${addon.id}_$index',
      architecture: AddonArchitecture.stremio,
      addonId: addon.id,
      addonName: addon.manifest.name,
      providerName: rawName,
      title: rawName,
      description: rawDesc,
      transport: transport,
      url: url,
      infoHash: infoHash,
      fileIdx: (m['fileIdx'] as num?)?.toInt(),
      trackerSources:
          (m['sources'] as List?)?.whereType<String>().toList() ?? const [],
      youtubeId: ytId,
      externalUrl: externalUrl,
      headers: headers,
      referer: headers['Referer'] ?? headers['referer'],
      qualityLabel: qualityLabel,
      qualityRank: qualityRank,
      sizeBytes: (behaviorHints['videoSize'] as num?)?.toInt(),
      filename: behaviorHints['filename'] as String?,
      bingeGroup: behaviorHints['bingeGroup'] as String?,
      subtitles: subs,
      notWebReady: behaviorHints['notWebReady'] == true,
    );
  }

  static StreamTransport _detectTransport({
    String? url,
    String? infoHash,
    String? ytId,
    String? externalUrl,
  }) {
    if (url != null && url.isNotEmpty) {
      final lower = url.toLowerCase();
      if (lower.contains('.m3u8')) return StreamTransport.hls;
      if (lower.contains('.mpd')) return StreamTransport.dash;
      return StreamTransport.directHttp;
    }
    if (infoHash != null && infoHash.isNotEmpty) return StreamTransport.torrent;
    if (ytId != null && ytId.isNotEmpty) return StreamTransport.youtube;
    return StreamTransport.externalUrl;
  }

  static (String?, int) extractQuality(String text) {
    final m = _qualityRegex.firstMatch(text);
    if (m == null) return (null, 0);
    final raw = m.group(1)!.toUpperCase();
    return switch (raw) {
      '2160P' || '4K' || 'UHD' => ('4K', 2160),
      '1440P' || '2K' => ('1440p', 1440),
      '1080P' || 'FHD' => ('1080p', 1080),
      '720P' || 'HD' => ('720p', 720),
      '480P' => ('480p', 480),
      '360P' => ('360p', 360),
      _ => (raw, 0),
    };
  }

  /// Generates default per-catalog screen placements from a manifest.
  /// If [userOverride] is non-empty, applies those target screens to every
  /// non-required catalog row; if empty (stream-only override), leaves all rows
  /// unassigned (`enabled: false`).
  static List<CatalogPlacement> defaultPlacementsForManifest(
    ManifestModel manifest, {
    Set<AddonTargetScreen>? userOverride,
    CatalogShelfPosition position = CatalogShelfPosition.belowBuiltIn,
  }) {
    return [
      for (final c in manifest.catalogs)
        _buildDefaultPlacement(c, userOverride: userOverride, position: position),
    ];
  }

  static CatalogPlacement _buildDefaultPlacement(
    CatalogItemModel c, {
    Set<AddonTargetScreen>? userOverride,
    required CatalogShelfPosition position,
  }) {
    if (c.hasRequiredExtra) {
      return CatalogPlacement(
        catalogKey: c.baseKey,
        enabled: false,
        targetScreens: const {},
        position: position,
      );
    }

    if (userOverride != null) {
      return CatalogPlacement(
        catalogKey: c.baseKey,
        enabled: userOverride.isNotEmpty,
        targetScreens: userOverride,
        position: position,
      );
    }

    final isAnime = c.type.toLowerCase() == 'anime' ||
        RegExp(r'anime|crunchyroll', caseSensitive: false)
            .hasMatch('${c.name} ${c.id}');
    final Set<AddonTargetScreen> defaults;
    if (isAnime) {
      defaults = {AddonTargetScreen.anime};
    } else if (c.type == 'movie') {
      defaults = {AddonTargetScreen.home, AddonTargetScreen.movies};
    } else if (c.type == 'series') {
      defaults = {AddonTargetScreen.home, AddonTargetScreen.tvShows};
    } else {
      defaults = {AddonTargetScreen.home, AddonTargetScreen.categories};
    }

    return CatalogPlacement(
      catalogKey: c.baseKey,
      enabled: c.showInHome && defaults.isNotEmpty,
      targetScreens: defaults,
      position: position,
    );
  }
}

final stremioAddonServiceProvider = Provider<StremioAddonService>(
  (ref) => StremioAddonService(ref.watch(dioProvider)),
);
