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

  static const int introLeadInMs = 3500;

  int get durationMs => endMs - startMs;

  /// True while playback is actively inside this segment with at least 1s left.
  /// Used for auto-skip triggers so auto-skip never cuts off pre-intro scenes.
  bool isActiveAt(int positionMs) =>
      positionMs >= startMs && positionMs < (endMs - 1000);

  /// True while the manual Skip CTA button should be visible on screen.
  /// - Intro: appears 3.5 seconds before [startMs] (clamped >= 0) and stays
  ///   visible until [endMs].
  /// - Outro: stays visible across the full `[startMs, endMs)` span.
  /// - Recap / Post-Credits: active across `[startMs, endMs - 1s)`.
  bool isPromptActiveAt(int positionMs) {
    if (type == SkipSegmentType.intro) {
      final leadStart = startMs > introLeadInMs ? startMs - introLeadInMs : 0;
      return positionMs >= leadStart && positionMs < endMs;
    }
    if (type == SkipSegmentType.outro) {
      return positionMs >= startMs && positionMs < endMs;
    }
    return isActiveAt(positionMs);
  }

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
    this.advancesToNextEpisode = false,
  });

  final SkipSegment segment;
  final SkipActionKind actionKind;

  /// Target seek position in milliseconds (for seek-based skip actions).
  final int? targetSeekMs;

  /// Optional next episode code (e.g. `S1E2`) when advancing to next episode.
  final String? nextEpisodeBadge;

  /// Remaining seconds before auto-advancing (only set when Auto-Skip Outro is active).
  final int? autoSkipCountdownSec;

  /// When true on a [SkipActionKind.skipCredits] prompt (outro ends within ~5s
  /// of episode end), tapping Skip Outro advances directly to the next episode.
  final bool advancesToNextEpisode;

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
        advancesToNextEpisode: advancesToNextEpisode,
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
        advancesToNextEpisode,
      ];
}
