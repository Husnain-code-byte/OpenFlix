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

  String get dedupKey {
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
