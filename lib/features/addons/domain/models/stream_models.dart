import 'package:equatable/equatable.dart';

import 'addon_models.dart';

enum StreamTransport {
  directHttp('DIRECT'),
  hls('HLS'),
  dash('DASH'),
  torrent('TORRENT'),
  youtube('YOUTUBE'),
  externalUrl('EXTERNAL');

  const StreamTransport(this.badgeLabel);
  final String badgeLabel;

  bool get isPlayableDirect =>
      this == directHttp || this == hls || this == dash;
}

class StreamQuery extends Equatable {
  const StreamQuery({
    required this.mediaType,
    required this.title,
    this.originalTitle,
    this.year,
    this.imdbId,
    this.tmdbId,
    this.anilistId,
    this.kitsuId,
    this.malId,
    this.rawMetaId,
    this.sourceAddonId,
    this.season,
    this.episode,
    this.episodeTitle,
    this.expectedRuntimeMinutes,
    this.isAnime = false,
    this.preferredLanguages = const [],
    this.skipProviders = const [],
  });

  final String mediaType; // 'movie' | 'series'
  final String title;
  final String? originalTitle;
  final int? year;
  final String? imdbId;
  final int? tmdbId;
  final int? anilistId;
  final int? kitsuId;
  final int? malId;
  final String? rawMetaId;
  final String? sourceAddonId;
  final int? season;
  final int? episode;
  final String? episodeTitle;
  final int? expectedRuntimeMinutes;
  final bool isAnime;
  final List<String> preferredLanguages;
  final List<String> skipProviders;

  String get displaySubtitle {
    final parts = <String>[];
    if (year != null) parts.add('$year');
    if (mediaType == 'series' && season != null && episode != null) {
      parts.add('S${season}E$episode');
    }
    if (episodeTitle != null && episodeTitle!.trim().isNotEmpty) {
      parts.add(episodeTitle!.trim());
    }
    return parts.join(' · ');
  }

  StreamQuery copyWith({
    String? imdbId,
    int? tmdbId,
    int? anilistId,
    int? kitsuId,
    int? malId,
    String? episodeTitle,
    int? expectedRuntimeMinutes,
    bool? isAnime,
    List<String>? preferredLanguages,
    List<String>? skipProviders,
  }) =>
      StreamQuery(
        mediaType: mediaType,
        title: title,
        originalTitle: originalTitle,
        year: year,
        imdbId: imdbId ?? this.imdbId,
        tmdbId: tmdbId ?? this.tmdbId,
        anilistId: anilistId ?? this.anilistId,
        kitsuId: kitsuId ?? this.kitsuId,
        malId: malId ?? this.malId,
        rawMetaId: rawMetaId,
        sourceAddonId: sourceAddonId,
        season: season,
        episode: episode,
        episodeTitle: episodeTitle ?? this.episodeTitle,
        expectedRuntimeMinutes:
            expectedRuntimeMinutes ?? this.expectedRuntimeMinutes,
        isAnime: isAnime ?? this.isAnime,
        preferredLanguages: preferredLanguages ?? this.preferredLanguages,
        skipProviders: skipProviders ?? this.skipProviders,
      );

  @override
  List<Object?> get props => [
        mediaType,
        title,
        originalTitle,
        year,
        imdbId,
        tmdbId,
        anilistId,
        kitsuId,
        malId,
        rawMetaId,
        sourceAddonId,
        season,
        episode,
        episodeTitle,
        expectedRuntimeMinutes,
        isAnime,
        preferredLanguages,
        skipProviders,
      ];
}

class ResolvedSubtitle extends Equatable {
  const ResolvedSubtitle({
    required this.url,
    required this.language,
    required this.sourceName,
    this.label,
    this.headers = const {},
  });

  final String url;
  final String language;
  final String sourceName;
  final String? label;
  final Map<String, String> headers;

  @override
  List<Object?> get props => [url, language, sourceName, label];
}

class ResolvedStream extends Equatable {
  const ResolvedStream({
    required this.id,
    required this.architecture,
    required this.addonId,
    required this.addonName,
    required this.providerName,
    required this.title,
    required this.transport,
    this.description,
    this.url,
    this.infoHash,
    this.fileIdx,
    this.trackerSources = const [],
    this.youtubeId,
    this.externalUrl,
    this.headers = const {},
    this.referer,
    this.qualityLabel,
    this.qualityRank = 0,
    this.sizeBytes,
    this.filename,
    this.bingeGroup,
    this.subtitles = const [],
    this.notWebReady = false,
    this.providerLang,
  });

  final String id;
  final AddonArchitecture architecture;
  final String addonId;
  final String addonName;
  final String providerName;
  final String title;
  final String? description;
  final StreamTransport transport;
  final String? url;
  final String? infoHash;
  final int? fileIdx;
  final List<String> trackerSources;
  final String? youtubeId;
  final String? externalUrl;
  final Map<String, String> headers;
  final String? referer;
  final String? qualityLabel;
  final int qualityRank;
  final int? sizeBytes;
  final String? filename;
  final String? bingeGroup;
  final List<ResolvedSubtitle> subtitles;
  final bool notWebReady;
  final String? providerLang;

  /// Normalizes a candidate stream URL to a direct `http://` or `https://` URI
  /// suitable for internal libmpv playback.
  ///
  /// Handles protocol-relative URLs (`//host/path`) and Android `intent://`
  /// links that wrap an HTTP/HTTPS stream or `S.browser_fallback_url`.
  /// Returns `null` for genuinely non-HTTP schemes such as `magnet:` or
  /// `stremio://`.
  static String? normalizeHttpPlayableUrl(String? raw) {
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;

    var candidate = trimmed;
    if (candidate.startsWith('//')) {
      candidate = 'https:$candidate';
    } else if (candidate.toLowerCase().startsWith('intent://')) {
      final fallbackMatch = RegExp(
        r';S\.browser_fallback_url=([^;]+)',
        caseSensitive: false,
      ).firstMatch(candidate);
      if (fallbackMatch != null) {
        final decoded = Uri.decodeComponent(fallbackMatch.group(1)!).trim();
        return normalizeHttpPlayableUrl(decoded);
      }
      final schemeMatch = RegExp(
        r';scheme=(https?)',
        caseSensitive: false,
      ).firstMatch(candidate);
      final hashIdx = candidate.indexOf('#Intent');
      if (schemeMatch != null && hashIdx > 'intent://'.length) {
        final scheme = schemeMatch.group(1)!.toLowerCase();
        final authorityAndPath = candidate.substring('intent://'.length, hashIdx);
        candidate = '$scheme://$authorityAndPath';
      } else {
        return null;
      }
    }

    final uri = Uri.tryParse(candidate) ?? Uri.tryParse(Uri.encodeFull(candidate));
    if (uri == null || !uri.hasScheme) return null;
    final scheme = uri.scheme.toLowerCase();
    if ((scheme != 'http' && scheme != 'https') || uri.host.trim().isEmpty) {
      return null;
    }
    return uri.toString();
  }

  /// Canonical HTTP/HTTPS URL playable directly inside OpenFlix's built-in
  /// libmpv player. Prefers [url] and falls back to [externalUrl] whenever
  /// either is a valid HTTP/HTTPS link (including extensionless Debrid/proxy
  /// redirect URLs).
  String? get internalPlayableUrl =>
      normalizeHttpPlayableUrl(url) ?? normalizeHttpPlayableUrl(externalUrl);

  /// True whenever this stream can be opened directly inside OpenFlix's
  /// internal video player without invoking Android external intents.
  bool get canPlayInternally => internalPlayableUrl != null;

  /// Builds request headers for libmpv / HTTP probing, forwarding all
  /// `behaviorHints.proxyHeaders.request` entries (e.g. `User-Agent`,
  /// `Referer`, `Origin`, `Cookie`) without duplicating case-variant keys.
  Map<String, String> buildRequestHeaders({
    required String defaultUserAgent,
  }) {
    final out = <String, String>{};
    final seenLower = <String>{};

    headers.forEach((rawKey, rawVal) {
      final key = rawKey.trim();
      final val = rawVal.trim();
      if (key.isEmpty || val.isEmpty) return;
      final lower = key.toLowerCase();
      if (seenLower.add(lower)) {
        out[key] = val;
      }
    });

    final ref = referer?.trim();
    if (ref != null && ref.isNotEmpty && !seenLower.contains('referer')) {
      out['Referer'] = ref;
      seenLower.add('referer');
    }

    if (!seenLower.contains('user-agent') && defaultUserAgent.isNotEmpty) {
      out['User-Agent'] = defaultUserAgent;
    }
    return out;
  }

  String get dedupKey {
    final playable = internalPlayableUrl;
    if (playable != null) return 'url:$playable';
    if (url != null && url!.isNotEmpty) return 'url:${url!}';
    if (infoHash != null && infoHash!.isNotEmpty) {
      return 'ih:${infoHash!.toLowerCase()}:${fileIdx ?? -1}';
    }
    if (youtubeId != null && youtubeId!.isNotEmpty) return 'yt:$youtubeId';
    return 'ext:${externalUrl ?? id}';
  }

  String? get formattedSize {
    final bytes = sizeBytes;
    if (bytes == null || bytes <= 0) return null;
    final gb = bytes / (1024 * 1024 * 1024);
    if (gb >= 1.0) return '${gb.toStringAsFixed(2)} GB';
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(0)} MB';
  }

  String? get playableOrCopyableTarget =>
      internalPlayableUrl ??
      url ??
      externalUrl ??
      (infoHash != null ? 'magnet:?xt=urn:btih:$infoHash' : null) ??
      (youtubeId != null ? 'https://www.youtube.com/watch?v=$youtubeId' : null);

  @override
  List<Object?> get props => [
        id,
        architecture,
        addonId,
        providerName,
        title,
        transport,
        url,
        externalUrl,
        infoHash,
        fileIdx,
        qualityLabel,
        qualityRank,
        sizeBytes,
        subtitles,
        providerLang,
      ];
}

enum ProviderStatusKind { loading, done, empty, error }

class ProviderResolutionStatus extends Equatable {
  const ProviderResolutionStatus({
    required this.sourceId,
    required this.sourceName,
    required this.architecture,
    required this.state,
    this.streamCount = 0,
    this.errorMessage,
    this.elapsedMs,
  });

  final String sourceId;
  final String sourceName;
  final AddonArchitecture architecture;
  final ProviderStatusKind state;
  final int streamCount;
  final String? errorMessage;
  final int? elapsedMs;

  ProviderResolutionStatus copyWith({
    ProviderStatusKind? state,
    int? streamCount,
    String? errorMessage,
    int? elapsedMs,
  }) =>
      ProviderResolutionStatus(
        sourceId: sourceId,
        sourceName: sourceName,
        architecture: architecture,
        state: state ?? this.state,
        streamCount: streamCount ?? this.streamCount,
        errorMessage: errorMessage ?? this.errorMessage,
        elapsedMs: elapsedMs ?? this.elapsedMs,
      );

  @override
  List<Object?> get props => [
        sourceId,
        sourceName,
        architecture,
        state,
        streamCount,
        errorMessage,
        elapsedMs,
      ];
}
