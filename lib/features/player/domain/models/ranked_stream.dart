import 'package:equatable/equatable.dart';

import '../../../addons/domain/models/stream_models.dart';
import '../../../preferences/domain/models/playback_preferences.dart';

enum HdrFormat {
  none,
  hlg,
  hdr10,
  hdr10Plus,
  dolbyVision;

  String? get badgeLabel => switch (this) {
        HdrFormat.none => null,
        HdrFormat.hlg => 'HLG',
        HdrFormat.hdr10 => 'HDR10',
        HdrFormat.hdr10Plus => 'HDR10+',
        HdrFormat.dolbyVision => 'DV',
      };
}

enum VideoCodecHint {
  unknown,
  h264,
  vp9,
  hevc,
  av1;

  String? get badgeLabel => switch (this) {
        VideoCodecHint.unknown => null,
        VideoCodecHint.h264 => 'H.264',
        VideoCodecHint.vp9 => 'VP9',
        VideoCodecHint.hevc => 'HEVC',
        VideoCodecHint.av1 => 'AV1',
      };
}

enum AudioCodecHint {
  unknown,
  aac,
  opus,
  flac,
  ac3,
  eac3,
  dts,
  dtsHd,
  trueHd,
  atmos;

  String? get badgeLabel => switch (this) {
        AudioCodecHint.unknown => null,
        AudioCodecHint.aac => 'AAC',
        AudioCodecHint.opus => 'Opus',
        AudioCodecHint.flac => 'FLAC',
        AudioCodecHint.ac3 => 'AC3',
        AudioCodecHint.eac3 => 'DD+',
        AudioCodecHint.dts => 'DTS',
        AudioCodecHint.dtsHd => 'DTS-HD',
        AudioCodecHint.trueHd => 'TrueHD',
        AudioCodecHint.atmos => 'Atmos',
      };

  bool get isSurroundOrPremium =>
      this == ac3 ||
      this == eac3 ||
      this == dts ||
      this == dtsHd ||
      this == trueHd ||
      this == atmos;
}

enum ReleaseSourceHint {
  unknown,
  camTs,
  hdRip,
  webRip,
  webDl,
  bluRay,
  remux;

  String? get badgeLabel => switch (this) {
        ReleaseSourceHint.unknown => null,
        ReleaseSourceHint.camTs => 'CAM',
        ReleaseSourceHint.hdRip => 'HDRip',
        ReleaseSourceHint.webRip => 'WEBRip',
        ReleaseSourceHint.webDl => 'WEB-DL',
        ReleaseSourceHint.bluRay => 'BluRay',
        ReleaseSourceHint.remux => 'REMUX',
      };
}

enum LanguageMatchTier {
  primaryDirect,
  primaryMultiAudio,
  fallbackDirect,
  fallbackMultiAudio,
  originalOrUnknown,
  otherLanguage,
}

/// Validates a stream's actual duration against TMDB's expected runtime.
/// Returns `false` when the stream is clearly a trailer/clip or wrong title/episode.
bool isDurationCompatibleWithRuntime(
  int actualDurationSeconds,
  int? expectedRuntimeMinutes,
) {
  if (expectedRuntimeMinutes == null ||
      expectedRuntimeMinutes <= 0 ||
      actualDurationSeconds <= 0) {
    return true;
  }
  final expectedSec = expectedRuntimeMinutes * 60;
  // Always reject trailers/promos (<5m) for full episodes/movies (>=20m).
  if (expectedRuntimeMinutes >= 20 && actualDurationSeconds < 300) {
    return false;
  }
  // Allow +/-28% (minimum +/-6 min) to accommodate regional cuts/PAL speedup/credits.
  final proportionalTolerance = (expectedSec * 0.28).round();
  final maxDiffSec = proportionalTolerance > 360 ? proportionalTolerance : 360;
  return (actualDurationSeconds - expectedSec).abs() <= maxDiffSec;
}

class StreamProbeResult extends Equatable {
  const StreamProbeResult({
    required this.isAlive,
    this.statusCode,
    this.ttfbMs,
    this.estimatedMbps,
    this.contentType,
    this.probedDurationSeconds,
    this.runtimeMismatch = false,
    required this.probedAtMs,
    this.error,
  });

  final bool isAlive;
  final int? statusCode;
  final int? ttfbMs;
  final double? estimatedMbps;
  final String? contentType;
  final int? probedDurationSeconds;
  final bool runtimeMismatch;
  final int probedAtMs;
  final String? error;

  @override
  List<Object?> get props => [
        isAlive,
        statusCode,
        ttfbMs,
        estimatedMbps,
        contentType,
        probedDurationSeconds,
        runtimeMismatch,
        probedAtMs,
        error,
      ];
}

class ParsedStreamMetadata extends Equatable {
  const ParsedStreamMetadata({
    this.detectedAudioLanguages = const {},
    this.detectedSubtitleLanguages = const {},
    this.isMultiAudio = false,
    this.isHardcodedSub = false,
    this.resolutionHeight = 0,
    this.isAdaptiveMaster = false,
    this.hdrFormat = HdrFormat.none,
    this.videoCodec = VideoCodecHint.unknown,
    this.audioCodec = AudioCodecHint.unknown,
    this.audioChannels,
    this.releaseSource = ReleaseSourceHint.unknown,
  });

  final Set<String> detectedAudioLanguages;
  final Set<String> detectedSubtitleLanguages;
  final bool isMultiAudio;
  final bool isHardcodedSub;
  final int resolutionHeight;
  final bool isAdaptiveMaster;
  final HdrFormat hdrFormat;
  final VideoCodecHint videoCodec;
  final AudioCodecHint audioCodec;
  final String? audioChannels;
  final ReleaseSourceHint releaseSource;

  String get resolutionLabel {
    if (resolutionHeight >= 2160) return '4K';
    if (resolutionHeight >= 1440) return '2K';
    if (resolutionHeight >= 1080) return '1080p';
    if (resolutionHeight >= 720) return '720p';
    if (resolutionHeight >= 480) return '480p';
    if (resolutionHeight > 0) return '${resolutionHeight}p';
    if (isAdaptiveMaster) return 'AUTO';
    return 'HD';
  }

  @override
  List<Object?> get props => [
        detectedAudioLanguages,
        detectedSubtitleLanguages,
        isMultiAudio,
        isHardcodedSub,
        resolutionHeight,
        isAdaptiveMaster,
        hdrFormat,
        videoCodec,
        audioCodec,
        audioChannels,
        releaseSource,
      ];
}

class RankedStream extends Equatable {
  const RankedStream({
    required this.stream,
    required this.meta,
    required this.languageMatchTier,
    this.probe,
    required this.compositeScore,
    required this.isAutoPlayEligible,
  });

  final ResolvedStream stream;
  final ParsedStreamMetadata meta;
  final LanguageMatchTier languageMatchTier;
  final StreamProbeResult? probe;
  final double compositeScore;
  final bool isAutoPlayEligible;

  String get dedupKey => stream.dedupKey;

  String get resolutionBadge => meta.resolutionLabel;

  String? get languageSummaryLabel {
    if (meta.detectedAudioLanguages.isEmpty) {
      return meta.isMultiAudio ? 'Multi Audio' : null;
    }
    final names = meta.detectedAudioLanguages
        .take(3)
        .map(languageDisplayName)
        .toList(growable: false);
    if (meta.isMultiAudio && names.length == 1) {
      return '${names.first} · Dual';
    }
    return names.join(' · ');
  }

  String? get speedLabel {
    final p = probe;
    if (p == null || !p.isAlive) return null;
    if (p.estimatedMbps != null && p.estimatedMbps! >= 0.5) {
      return '${p.estimatedMbps!.toStringAsFixed(1)} Mbps';
    }
    if (p.ttfbMs != null) {
      return '${p.ttfbMs} ms';
    }
    return 'Ready';
  }

  List<String> get codecSummaryBadges {
    final out = <String>[];
    if (meta.hdrFormat.badgeLabel != null) out.add(meta.hdrFormat.badgeLabel!);
    if (meta.videoCodec.badgeLabel != null) out.add(meta.videoCodec.badgeLabel!);
    if (meta.audioCodec.badgeLabel != null) {
      final ch = meta.audioChannels != null ? ' ${meta.audioChannels}' : '';
      out.add('${meta.audioCodec.badgeLabel!}$ch');
    }
    if (meta.releaseSource.badgeLabel != null) {
      out.add(meta.releaseSource.badgeLabel!);
    }
    if (stream.formattedSize != null) out.add(stream.formattedSize!);
    return out;
  }

  RankedStream copyWith({
    StreamProbeResult? probe,
    double? compositeScore,
    bool? isAutoPlayEligible,
  }) =>
      RankedStream(
        stream: stream,
        meta: meta,
        languageMatchTier: languageMatchTier,
        probe: probe ?? this.probe,
        compositeScore: compositeScore ?? this.compositeScore,
        isAutoPlayEligible: isAutoPlayEligible ?? this.isAutoPlayEligible,
      );

  @override
  List<Object?> get props => [
        stream,
        meta,
        languageMatchTier,
        probe,
        compositeScore,
        isAutoPlayEligible,
      ];
}
