import 'package:equatable/equatable.dart';

/// Semantic type of a skippable timeline segment.
enum SkipSegmentType {
  recap,
  intro,
  outro,
  postCredits,
}

/// Origin of a skip segment, ordered by timing fidelity.
enum SkipSegmentSource {
  /// Embedded MKV/MP4 chapters read directly from `libmpv` (exact to file).
  embeddedChapters,

  /// IntroDB (`https://api.introdb.app`) community segments (TV & Movies).
  introDb,

  /// AniSkip v2 (`https://api.aniskip.com`) community segments (Anime).
  aniSkip,

  /// End-of-episode fallback threshold when no explicit outro timestamps exist.
  fallbackEnd,
}

class SkipSegment extends Equatable {
  const SkipSegment({
    required this.type,
    required this.startMs,
    required this.endMs,
    required this.source,
    this.confidence,
    this.label,
  });

  final SkipSegmentType type;
  final int startMs;
  final int endMs;
  final SkipSegmentSource source;
  final double? confidence;
  final String? label;

  int get durationMs => endMs - startMs;

  /// True while playback is actively inside this segment with at least 1s left.
  bool isActiveAt(int positionMs) =>
      positionMs >= startMs && positionMs < (endMs - 1000);

  SkipSegment copyWith({
    int? startMs,
    int? endMs,
    double? confidence,
    String? label,
  }) =>
      SkipSegment(
        type: type,
        startMs: startMs ?? this.startMs,
        endMs: endMs ?? this.endMs,
        source: source,
        confidence: confidence ?? this.confidence,
        label: label ?? this.label,
      );

  @override
  List<Object?> get props => [type, startMs, endMs, source, confidence, label];
}

/// User-facing action presented for an active skip segment.
enum SkipActionKind {
  skipRecap,
  skipIntro,
  skipCredits,
  skipToPostCredits,
  nextEpisode;

  /// Intro & Recap buttons align on the left above the seekbar start;
  /// Outro, Post-Credits & Next Episode align on the right above the seekbar end.
  bool get isLeftAligned =>
      this == SkipActionKind.skipIntro || this == SkipActionKind.skipRecap;

  String get buttonLabel => switch (this) {
        SkipActionKind.skipRecap => 'Skip recap',
        SkipActionKind.skipIntro => 'Skip intro',
        SkipActionKind.skipCredits => 'Skip outro',
        SkipActionKind.skipToPostCredits => 'Skip to post-credits',
        SkipActionKind.nextEpisode => 'Next episode',
      };
}

class ActiveSkipPrompt extends Equatable {
  const ActiveSkipPrompt({
    required this.segment,
    required this.actionKind,
    this.targetSeekMs,
    this.nextEpisodeBadge,
    this.autoSkipCountdownSec,
  });

  final SkipSegment segment;
  final SkipActionKind actionKind;

  /// Target seek position in milliseconds (for seek-based skip actions).
  final int? targetSeekMs;

  /// Optional next episode code (e.g. `S1E2`) when [actionKind] is [SkipActionKind.nextEpisode].
  final String? nextEpisodeBadge;

  /// Remaining seconds before auto-advancing (only set when Auto-Skip Outro is active).
  final int? autoSkipCountdownSec;

  bool get isLeftAligned => actionKind.isLeftAligned;

  String get displayLabel {
    final base = actionKind.buttonLabel;
    if (autoSkipCountdownSec != null && autoSkipCountdownSec! > 0) {
      return '$base (${autoSkipCountdownSec}s)';
    }
    return base;
  }

  ActiveSkipPrompt copyWith({
    int? autoSkipCountdownSec,
    bool clearCountdown = false,
  }) =>
      ActiveSkipPrompt(
        segment: segment,
        actionKind: actionKind,
        targetSeekMs: targetSeekMs,
        nextEpisodeBadge: nextEpisodeBadge,
        autoSkipCountdownSec: clearCountdown
            ? null
            : (autoSkipCountdownSec ?? this.autoSkipCountdownSec),
      );

  @override
  List<Object?> get props => [
        segment,
        actionKind,
        targetSeekMs,
        nextEpisodeBadge,
        autoSkipCountdownSec,
      ];
}
