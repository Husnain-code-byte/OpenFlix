import 'package:media_kit/media_kit.dart';

import '../../addons/domain/models/stream_models.dart';
import '../../preferences/domain/models/playback_preferences.dart';
import '../domain/models/player_models.dart';

/// Builds user-facing audio & subtitle option lists and selects optimal initial
/// tracks using Primary/Fallback preferences and Netflix-style smart subtitles.
abstract final class TrackOrchestrator {
  static List<PlayerAudioOption> buildAudioOptions(List<AudioTrack> rawTracks) {
    final options = <PlayerAudioOption>[];
    var trackIndex = 1;
    for (final t in rawTracks) {
      if (t.id == 'auto' || t.id == 'no') continue;
      final normLang = normalizeLanguageCode(t.language) ??
          normalizeLanguageCode(t.title);
      final baseName = normLang != null
          ? languageDisplayName(normLang)
          : ((t.title?.trim().isNotEmpty == true)
              ? t.title!.trim()
              : (t.language?.trim().isNotEmpty == true &&
                      t.language!.trim().toLowerCase() != 'und'
                  ? t.language!.trim()
                  : 'Track $trackIndex'));

      // Append distinct track title qualifier (e.g. "Hindi (Commentary)") if helpful
      var display = baseName;
      final rawTitle = t.title?.trim();
      if (rawTitle != null &&
          rawTitle.isNotEmpty &&
          rawTitle.toLowerCase() != baseName.toLowerCase() &&
          normLang != null &&
          !rawTitle.toLowerCase().contains(baseName.toLowerCase())) {
        display = '$baseName · $rawTitle';
      }

      final detailParts = <String>[];
      if (t.codec != null && t.codec!.trim().isNotEmpty) {
        detailParts.add(_formatAudioCodecName(t.codec!));
      }
      final ch = t.channels?.trim();
      if (ch != null && ch.isNotEmpty) {
        detailParts.add(ch);
      } else if (t.channelscount != null && t.channelscount! > 0) {
        detailParts.add(t.channelscount! >= 6 ? '5.1' : '${t.channelscount}ch');
      }

      options.add(
        PlayerAudioOption(
          track: t,
          displayLabel: display,
          codecDetail: detailParts.isEmpty ? null : detailParts.join(' '),
          normalizedLang: normLang,
        ),
      );
      trackIndex++;
    }
    return options;
  }

  static List<PlayerSubtitleOption> buildSubtitleOptions(
    List<SubtitleTrack> embeddedTracks,
    List<ResolvedSubtitle> externalSubtitles,
  ) {
    final options = <PlayerSubtitleOption>[
      const PlayerSubtitleOption(
        id: 'off',
        displayLabel: 'Off',
        isOff: true,
      ),
    ];

    var idx = 1;
    for (final t in embeddedTracks) {
      if (t.id == 'auto' || t.id == 'no' || t.uri || t.data) continue;
      final normLang = normalizeLanguageCode(t.language) ??
          normalizeLanguageCode(t.title);
      final baseName = normLang != null
          ? languageDisplayName(normLang)
          : ((t.title?.trim().isNotEmpty == true)
              ? t.title!.trim()
              : (t.language?.trim().isNotEmpty == true &&
                      t.language!.trim().toLowerCase() != 'und'
                  ? t.language!.trim()
                  : 'Subtitle $idx'));
      final rawTitle = t.title?.trim();
      var display = baseName;
      if (rawTitle != null &&
          rawTitle.isNotEmpty &&
          rawTitle.toLowerCase() != baseName.toLowerCase() &&
          !rawTitle.toLowerCase().contains(baseName.toLowerCase())) {
        display = '$baseName · $rawTitle';
      }
      final detail = <String>[
        'Embedded',
        if (t.codec != null && t.codec!.trim().isNotEmpty)
          _formatSubtitleCodecName(t.codec!),
      ].join(' · ');

      options.add(
        PlayerSubtitleOption(
          id: 'emb:${t.id}',
          displayLabel: display,
          detail: detail,
          normalizedLang: normLang,
          embeddedTrack: t,
        ),
      );
      idx++;
    }

    for (var i = 0; i < externalSubtitles.length; i++) {
      final sub = externalSubtitles[i];
      final normLang = normalizeLanguageCode(sub.language) ??
          normalizeLanguageCode(sub.label);
      final baseName = normLang != null
          ? languageDisplayName(normLang)
          : (sub.label?.trim().isNotEmpty == true
              ? sub.label!.trim()
              : sub.language);
      options.add(
        PlayerSubtitleOption(
          id: 'ext:$i:${sub.url}',
          displayLabel: baseName,
          detail: 'Addon · ${sub.sourceName}',
          normalizedLang: normLang,
          isExternal: true,
          externalSubtitle: sub,
        ),
      );
    }

    return options;
  }

  static PlayerAudioOption? selectInitialAudio({
    required List<PlayerAudioOption> options,
    required PlaybackPreferences prefs,
    String? preferredOverrideLang,
  }) {
    if (options.isEmpty) return null;
    final primary = normalizeLanguageCode(prefs.primaryLanguage) ?? 'en';
    final fallback = normalizeLanguageCode(prefs.fallbackLanguage) ?? 'en';

    if (preferredOverrideLang != null) {
      final exactOverride = _firstMatchingAudio(options, preferredOverrideLang);
      if (exactOverride != null) return exactOverride;
    }

    final primaryHit = _firstMatchingAudio(options, primary);
    if (primaryHit != null) return primaryHit;

    if (fallback != primary) {
      final fallbackHit = _firstMatchingAudio(options, fallback);
      if (fallbackHit != null) return fallbackHit;
    }

    // Prefer track flagged isDefault, else first available.
    for (final opt in options) {
      if (opt.track.isDefault == true) return opt;
    }
    return options.first;
  }

  static PlayerAudioOption? _firstMatchingAudio(
    List<PlayerAudioOption> options,
    String targetCode,
  ) {
    final matching = options.where((o) => o.normalizedLang == targetCode).toList();
    if (matching.isEmpty) return null;
    // Avoid picking commentary/descriptive tracks over main dialogue when multiple exist.
    final nonCommentary = matching.where((o) {
      final lower = (o.track.title ?? '').toLowerCase();
      return !lower.contains('commentary') && !lower.contains('descriptive');
    }).toList();
    return nonCommentary.isNotEmpty ? nonCommentary.first : matching.first;
  }

  /// Netflix-style smart subtitle selection:
  /// - If [userManualOverride] is true, try preserving [previousSubLang] / [previousSubId].
  /// - Otherwise, if active audio language matches `primaryLanguage`, return `Off`.
  /// - If active audio differs from `primaryLanguage` (or is unknown when content
  ///   is foreign/anime), automatically enable best `primaryLanguage` subtitle
  ///   (preferring embedded for tightest sync), else `fallbackLanguage`, else `Off`.
  static PlayerSubtitleOption selectInitialSubtitle({
    required List<PlayerSubtitleOption> options,
    required PlaybackPreferences prefs,
    String? activeAudioLang,
    bool userManualOverride = false,
    bool userChoseOff = false,
    String? previousSubLang,
  }) {
    final offOpt = options.firstWhere(
      (o) => o.isOff,
      orElse: () => const PlayerSubtitleOption(
        id: 'off',
        displayLabel: 'Off',
        isOff: true,
      ),
    );

    if (userManualOverride) {
      if (userChoseOff) return offOpt;
      if (previousSubLang != null) {
        final match = _bestSubForLang(options, previousSubLang);
        if (match != null) return match;
      }
      return offOpt;
    }

    final primary = normalizeLanguageCode(prefs.primaryLanguage) ?? 'en';
    final fallback = normalizeLanguageCode(prefs.fallbackLanguage) ?? 'en';

    // Active audio is already in the user's Primary watch language -> Subs OFF.
    if (activeAudioLang != null && activeAudioLang == primary) {
      return offOpt;
    }

    // Audio is in another language (e.g. Japanese/English when Primary is Hindi):
    // auto-enable Primary subtitles, else Fallback subtitles.
    final primarySub = _bestSubForLang(options, primary);
    if (primarySub != null) return primarySub;

    if (fallback != primary) {
      final fallbackSub = _bestSubForLang(options, fallback);
      if (fallbackSub != null) return fallbackSub;
    }

    return offOpt;
  }

  static PlayerSubtitleOption? _bestSubForLang(
    List<PlayerSubtitleOption> options,
    String langCode,
  ) {
    final matches = options
        .where((o) => !o.isOff && o.normalizedLang == langCode)
        .toList();
    if (matches.isEmpty) return null;
    // Prefer full dialogue tracks (not Signs/Songs/Forced) and embedded before external.
    matches.sort((a, b) {
      final aForced = _isSignsOrForced(a.displayLabel);
      final bForced = _isSignsOrForced(b.displayLabel);
      if (aForced != bForced) return aForced ? 1 : -1;
      if (a.isExternal != b.isExternal) return a.isExternal ? 1 : -1;
      return 0;
    });
    return matches.first;
  }

  static bool _isSignsOrForced(String label) {
    final l = label.toLowerCase();
    return l.contains('sign') || l.contains('song') || l.contains('forced');
  }

  static String _formatAudioCodecName(String raw) {
    final l = raw.trim().toLowerCase();
    if (l.contains('eac3')) return 'E-AC3';
    if (l.contains('ac3')) return 'AC3';
    if (l.contains('truehd')) return 'TrueHD';
    if (l.contains('dts')) return 'DTS';
    if (l.contains('opus')) return 'Opus';
    if (l.contains('aac')) return 'AAC';
    if (l.contains('flac')) return 'FLAC';
    return raw.toUpperCase();
  }

  static String _formatSubtitleCodecName(String raw) {
    final l = raw.trim().toLowerCase();
    if (l.contains('ass') || l.contains('ssa')) return 'ASS';
    if (l.contains('pgs')) return 'PGS';
    if (l.contains('dvd_subtitle') || l.contains('vobsub')) return 'VobSub';
    if (l.contains('subrip') || l.contains('srt')) return 'SRT';
    if (l.contains('webvtt') || l.contains('vtt')) return 'VTT';
    if (l.contains('mov_text') || l.contains('tx3g')) return 'TX3G';
    return raw.toUpperCase();
  }
}
