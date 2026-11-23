import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../addons/domain/models/stream_models.dart';
import '../../preferences/domain/models/playback_preferences.dart';
import '../domain/models/ranked_stream.dart';
import 'stream_metadata_parser.dart';

/// Physical display resolution cap derived from the device's shortest physical
/// screen dimension (`min(physicalWidth, physicalHeight)`).
class DeviceDisplayProfile {
  const DeviceDisplayProfile({required this.maxRecommendedHeight});

  final int maxRecommendedHeight;

  factory DeviceDisplayProfile.fromPhysicalShortEdge(double shortEdgePx) {
    if (shortEdgePx >= 2000) return const DeviceDisplayProfile(maxRecommendedHeight: 2160);
    if (shortEdgePx >= 1350) return const DeviceDisplayProfile(maxRecommendedHeight: 1440);
    if (shortEdgePx >= 1000) return const DeviceDisplayProfile(maxRecommendedHeight: 1080);
    if (shortEdgePx >= 680) return const DeviceDisplayProfile(maxRecommendedHeight: 720);
    return const DeviceDisplayProfile(maxRecommendedHeight: 480);
  }

  factory DeviceDisplayProfile.current() {
    try {
      final dispatcher = ui.PlatformDispatcher.instance;
      final view = dispatcher.implicitView ??
          (dispatcher.views.isNotEmpty ? dispatcher.views.first : null);
      if (view == null) {
        return const DeviceDisplayProfile(maxRecommendedHeight: 1080);
      }
      final size = view.physicalSize;
      if (size.isEmpty) {
        return const DeviceDisplayProfile(maxRecommendedHeight: 1080);
      }
      final shortEdge = math.min(size.width, size.height);
      return DeviceDisplayProfile.fromPhysicalShortEdge(shortEdge);
    } catch (_) {
      return const DeviceDisplayProfile(maxRecommendedHeight: 1080);
    }
  }
}

/// Session-scoped penalty tracker so hosts/streams that fail during actual
/// playback are automatically demoted on subsequent link picks for 10 minutes.
class HostReliabilityTracker {
  final Map<String, int> _failedHostsMs = {};
  final Set<String> _failedStreamKeys = {};
  final Set<String> _runtimeRejectedStreamKeys = {};

  static const _cooldownMs = 10 * 60 * 1000;

  String? _hostOf(ResolvedStream s) {
    final uri = Uri.tryParse(s.url ?? '');
    if (uri != null && uri.host.isNotEmpty) return uri.host.toLowerCase();
    return s.providerName.toLowerCase();
  }

  void recordFailure(ResolvedStream s, {DateTime? now}) {
    final ts = (now ?? DateTime.now()).millisecondsSinceEpoch;
    _failedStreamKeys.add(s.dedupKey);
    final host = _hostOf(s);
    if (host != null && host.isNotEmpty) {
      _failedHostsMs[host] = ts;
    }
  }

  void recordRuntimeMismatch(ResolvedStream s) {
    _runtimeRejectedStreamKeys.add(s.dedupKey);
    _failedStreamKeys.add(s.dedupKey);
  }

  bool isHostPenalized(ResolvedStream s, {DateTime? now}) {
    final host = _hostOf(s);
    if (host == null) return false;
    final at = _failedHostsMs[host];
    if (at == null) return false;
    final ts = (now ?? DateTime.now()).millisecondsSinceEpoch;
    if (ts - at > _cooldownMs) {
      _failedHostsMs.remove(host);
      return false;
    }
    return true;
  }

  bool isStreamFailed(ResolvedStream s) =>
      _failedStreamKeys.contains(s.dedupKey);

  bool isStreamRuntimeRejected(ResolvedStream s) =>
      _runtimeRejectedStreamKeys.contains(s.dedupKey);
}

final hostReliabilityTrackerProvider = Provider<HostReliabilityTracker>(
  (ref) => HostReliabilityTracker(),
);

abstract final class StreamRanker {
  static List<RankedStream> rank({
    required List<ResolvedStream> streams,
    required PlaybackPreferences prefs,
    required DeviceDisplayProfile displayProfile,
    Map<String, StreamProbeResult> probeCache = const {},
    HostReliabilityTracker? reliabilityTracker,
    String? mediaTitle,
  }) {
    final primary = normalizeLanguageCode(prefs.primaryLanguage) ?? 'en';
    final fallback = normalizeLanguageCode(prefs.fallbackLanguage) ?? 'en';

    final out = <RankedStream>[];
    for (final s in streams) {
      final probe = probeCache[s.dedupKey];
      final runtimeRejected = (probe?.runtimeMismatch == true) ||
          (reliabilityTracker?.isStreamRuntimeRejected(s) ?? false);
      // Never surface streams whose runtime clearly mismatches TMDB's runtime.
      if (runtimeRejected) continue;

      final meta = StreamMetadataParser.parse(s, mediaTitle: mediaTitle);
      final tier = _classifyLanguageTier(
        meta: meta,
        primary: primary,
        fallback: fallback,
      );
      final hostPenalized =
          reliabilityTracker?.isHostPenalized(s) ?? false;
      final streamFailed = reliabilityTracker?.isStreamFailed(s) ?? false;

      final isPlayableTransport = s.canPlayInternally;
      final isDead = probe != null && !probe.isAlive;
      final isAutoPlayEligible =
          isPlayableTransport && !isDead && !streamFailed;

      final score = _scoreStream(
        stream: s,
        meta: meta,
        tier: tier,
        displayCap: displayProfile.maxRecommendedHeight,
        probe: probe,
        hostPenalized: hostPenalized,
        streamFailed: streamFailed,
      );

      out.add(
        RankedStream(
          stream: s,
          meta: meta,
          languageMatchTier: tier,
          probe: probe,
          compositeScore: score,
          isAutoPlayEligible: isAutoPlayEligible,
        ),
      );
    }

    out.sort((a, b) {
      // 1. Auto-play eligible HTTP/HLS/DASH streams always rank ahead of torrents/dead
      final eligDiff =
          (b.isAutoPlayEligible ? 1 : 0) - (a.isAutoPlayEligible ? 1 : 0);
      if (eligDiff != 0) return eligDiff;

      // 2. Direct playable transport over torrent/external even when both dead/excluded
      final transDiff = (b.stream.canPlayInternally ? 1 : 0) -
          (a.stream.canPlayInternally ? 1 : 0);
      if (transDiff != 0) return transDiff;

      // 3. Deterministic composite score
      final scoreDiff = b.compositeScore.compareTo(a.compositeScore);
      if (scoreDiff != 0) return scoreDiff;

      // 4. Higher stated qualityRank tie-break, then provider name
      final qDiff = b.stream.qualityRank.compareTo(a.stream.qualityRank);
      if (qDiff != 0) return qDiff;
      return a.stream.providerName.compareTo(b.stream.providerName);
    });

    return out;
  }

  static LanguageMatchTier _classifyLanguageTier({
    required ParsedStreamMetadata meta,
    required String primary,
    required String fallback,
  }) {
    final langs = meta.detectedAudioLanguages;
    if (langs.contains(primary)) {
      return (meta.isMultiAudio || langs.length > 1)
          ? LanguageMatchTier.primaryMultiAudio
          : LanguageMatchTier.primaryDirect;
    }
    if (fallback != primary && langs.contains(fallback)) {
      return (meta.isMultiAudio || langs.length > 1)
          ? LanguageMatchTier.fallbackMultiAudio
          : LanguageMatchTier.fallbackDirect;
    }
    if (langs.isEmpty) {
      return LanguageMatchTier.originalOrUnknown;
    }
    return LanguageMatchTier.otherLanguage;
  }

  static double _scoreStream({
    required ResolvedStream stream,
    required ParsedStreamMetadata meta,
    required LanguageMatchTier tier,
    required int displayCap,
    StreamProbeResult? probe,
    required bool hostPenalized,
    required bool streamFailed,
  }) {
    double score = 0;

    // Tier 1: Language match (+100..+1000)
    score += switch (tier) {
      LanguageMatchTier.primaryDirect => 1000,
      LanguageMatchTier.primaryMultiAudio => 960,
      LanguageMatchTier.fallbackDirect => 720,
      LanguageMatchTier.fallbackMultiAudio => 690,
      LanguageMatchTier.originalOrUnknown => 420,
      LanguageMatchTier.otherLanguage => 100,
    };

    // Tier 2: Device-capped quality (+60..+300)
    final res = meta.resolutionHeight;
    if (meta.isAdaptiveMaster) {
      score += 210;
    } else if (res == 0) {
      score += 150;
    } else if (res <= displayCap) {
      score += switch (res) {
        >= 2160 => 300,
        >= 1440 => 270,
        >= 1080 => 240,
        >= 720 => 180,
        >= 480 => 110,
        _ => 60,
      };
    } else {
      // Soft cap above physical display resolution: clean 1080p (+240) & 720p (+180)
      // win on a 1080p phone, while 4K (+165) still beats 480p (+110) and plays
      // automatically if no fitting resolution exists.
      score += 165;
    }

    // Tier 3: Live speed & liveness probe (-500..+180)
    if (probe != null) {
      if (!probe.isAlive) {
        score -= 500;
      } else if (!probe.isInconclusive) {
        if (probe.ttfbMs != null) {
          final ms = probe.ttfbMs!.clamp(100, 1800);
          final ttfbPoints =
              100.0 * (1.0 - ((ms - 250).clamp(0, 1550) / 1550.0));
          score += ttfbPoints.clamp(0.0, 100.0);
        } else {
          score += 50;
        }
        if (probe.estimatedMbps != null) {
          final mbpsPoints = (probe.estimatedMbps! / 15.0).clamp(0.0, 1.0) * 80.0;
          score += mbpsPoints;
        } else if (stream.transport == StreamTransport.hls ||
            stream.transport == StreamTransport.dash) {
          // Adaptive HLS/DASH manifests verified alive get a balanced throughput baseline.
          score += 45;
        }
      }
    }

    // Tier 4: Quality hygiene, codecs & reliability (-300..+50)
    if (meta.releaseSource == ReleaseSourceHint.camTs) {
      score -= 250;
    } else if (meta.releaseSource == ReleaseSourceHint.webDl ||
        meta.releaseSource == ReleaseSourceHint.bluRay) {
      score += 25;
    } else if (meta.releaseSource == ReleaseSourceHint.remux) {
      score += 10;
    }

    if (meta.isDolbyVisionProfile5Only) {
      // Deprioritize Dolby Vision Profile 5 (DV without HDR10/SDR fallback)
      // slightly below standard HDR10/SDR links of the same resolution while
      // keeping it auto-play eligible and manually selectable in Links.
      score -= 35;
    }

    if (meta.videoCodec == VideoCodecHint.hevc ||
        meta.videoCodec == VideoCodecHint.av1) {
      score += 15;
    }
    if (meta.audioCodec.isSurroundOrPremium) {
      score += 10;
    }
    if (streamFailed) {
      score -= 600;
    } else if (hostPenalized) {
      score -= 300;
    }
    if (stream.notWebReady) {
      // Slightly prefer standard web-ready containers unless codec is needed,
      // though libmpv plays MKV/AC3/DTS natively.
      score -= 5;
    }

    return score;
  }
}
