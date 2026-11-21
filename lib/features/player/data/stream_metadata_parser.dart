import '../domain/models/ranked_stream.dart';
import '../../addons/domain/models/stream_models.dart';
import '../../preferences/domain/models/playback_preferences.dart';

/// Parses Stremio multi-line metadata and CloudStream flat descriptor strings
/// into structured audio language, resolution, HDR, codec, and release quality.
abstract final class StreamMetadataParser {
  static final Map<String, RegExp> _wordLanguagePatterns = {
    'hi': RegExp(
      r'\b(hindi|hin|bollywood|dual[\s._-]?hindi)\b|हिन्दी|हिंदी',
      caseSensitive: false,
    ),
    'en': RegExp(
      r'\b(english|eng|eng[\s._-]?dub)\b',
      caseSensitive: false,
    ),
    'ur': RegExp(r'\b(urdu|urd)\b|اردو', caseSensitive: false),
    'pa': RegExp(r'\b(punjabi|panjabi|pun)\b|ਪੰਜਾਬੀ', caseSensitive: false),
    'ta': RegExp(r'\b(tamil|tam)\b|தமிழ்', caseSensitive: false),
    'te': RegExp(r'\b(telugu|tel)\b|తెలుగు', caseSensitive: false),
    'ml': RegExp(r'\b(malayalam|mal)\b|മലയാളம்', caseSensitive: false),
    'kn': RegExp(r'\b(kannada|kan)\b|ಕನ್ನಡ', caseSensitive: false),
    'bn': RegExp(r'\b(bengali|bangla|ben)\b|বাংলা', caseSensitive: false),
    'mr': RegExp(r'\b(marathi|mar)\b|मराठी', caseSensitive: false),
    'ja': RegExp(r'\b(japanese|jpn|nihongo|jap[\s._-]?dub)\b|日本語', caseSensitive: false),
    'ko': RegExp(r'\b(korean|kor)\b|한국어', caseSensitive: false),
    'es': RegExp(
      r'\b(spanish|espanol|español|latino|castellano|spa)\b',
      caseSensitive: false,
    ),
    'fr': RegExp(
      r'\b(french|francais|français|truefrench|vff|vfq|vostfr|fre|fra)\b',
      caseSensitive: false,
    ),
    'de': RegExp(r'\b(german|deutsch|ger|deu)\b', caseSensitive: false),
    'it': RegExp(r'\b(italian|italiano|ita)\b', caseSensitive: false),
    'pt': RegExp(
      r'\b(portuguese|portugues|português|dublado|pt-br|ptbr|por)\b',
      caseSensitive: false,
    ),
    'ru': RegExp(r'\b(russian|rus)\b|русский', caseSensitive: false),
    'ar': RegExp(r'\b(arabic|ara)\b|العربية', caseSensitive: false),
    'tr': RegExp(r'\b(turkish|turkce|türkçe|tur)\b', caseSensitive: false),
    'zh': RegExp(
      r'\b(chinese|mandarin|cantonese|zho|chi|chs|cht)\b',
      caseSensitive: false,
    ),
    'id': RegExp(r'\b(indonesian|bahasa|indo)\b', caseSensitive: false),
  };

  /// Bracketed or delimited short ISO-639-1 tokens such as `[HI]`, `(HI+EN)`,
  /// `HI-EN`, `[EN]`, `{JA}` — strictly delimited so English prose like "in 4K"
  /// or "it starts" never false-positives.
  static final RegExp _bracketShortCodePattern = RegExp(
    r'(?:^|[\[\(\{/\+|,&\s])(HI|EN|UR|TA|TE|ML|KN|PA|BN|MR|JA|JP|KO|ES|FR|DE|IT|PT|RU|AR|TR|ZH)(?=$|[\]\)\}/\+|,&\s])',
    caseSensitive: true,
  );

  static const Map<String, String> _flagToCode = {
    '🇮🇳': 'hi',
    '🇺🇸': 'en',
    '🇬🇧': 'en',
    '🇦🇺': 'en',
    '🇨🇦': 'en',
    '🇵🇰': 'ur',
    '🇧🇩': 'bn',
    '🇯🇵': 'ja',
    '🇰🇷': 'ko',
    '🇪🇸': 'es',
    '🇲🇽': 'es',
    '🇫🇷': 'fr',
    '🇩🇪': 'de',
    '🇮🇹': 'it',
    '🇵🇹': 'pt',
    '🇧🇷': 'pt',
    '🇷🇺': 'ru',
    '🇸🇦': 'ar',
    '🇹🇷': 'tr',
    '🇨🇳': 'zh',
    '🇹🇼': 'zh',
    '🇭🇰': 'zh',
    '🇮🇩': 'id',
  };

  /// Explicit subtitle-only clauses such as `ESub`, `Hindi Sub`, `Eng Sub`,
  /// `Multi Sub` must NOT leak into audio language detection.
  static final RegExp _subtitleClausePattern = RegExp(
    r'\b(e[\s._-]?subs?|hindi[\s._-]?subs?|eng(?:lish)?[\s._-]?subs?|'
    r'multi[\s._-]?subs?|soft[\s._-]?subs?|hard[\s._-]?subs?|hc[\s._-]?subs?|'
    r'subbed|vostfr|fansub)\b',
    caseSensitive: false,
  );

  static final RegExp _multiAudioPattern = RegExp(
    r'\b(dual[\s._-]?(?:audio|lang)?|multi[\s._-]?(?:audio|lang)?|'
    r'dd\+?\s*dual|triple[\s._-]?audio|org[\s._-]?dual)\b',
    caseSensitive: false,
  );

  static ParsedStreamMetadata parse(
    ResolvedStream stream, {
    String? mediaTitle,
  }) {
    final combinedRaw = [
      stream.title,
      if (stream.description != null) stream.description!,
      if (stream.filename != null) stream.filename!,
      if (stream.qualityLabel != null) stream.qualityLabel!,
      stream.providerName,
    ].join(' ');

    // Remove the media title's own words so titles like "The English Patient"
    // or "Hindi Medium" do not spoof audio track metadata.
    final titleStripped = _stripMediaTitle(combinedRaw, mediaTitle);

    final subLangs = <String>{};
    final audioScanBuffer = StringBuffer();
    var lastEnd = 0;
    var isHardSub = false;
    for (final m in _subtitleClausePattern.allMatches(titleStripped)) {
      if (m.start > lastEnd) {
        audioScanBuffer.write(titleStripped.substring(lastEnd, m.start));
        audioScanBuffer.write(' ');
      }
      final clause = m.group(0)!.toLowerCase();
      if (clause.contains('esub') || clause.contains('eng')) subLangs.add('en');
      if (clause.contains('hindi')) subLangs.add('hi');
      if (clause.contains('vostfr')) subLangs.add('fr');
      if (clause.contains('hard') || clause.contains('hc')) {
        isHardSub = true;
      }
      lastEnd = m.end;
    }
    if (lastEnd < titleStripped.length) {
      audioScanBuffer.write(titleStripped.substring(lastEnd));
    }
    final audioText = audioScanBuffer.toString();

    final audioLangs = <String>{};
    for (final entry in _wordLanguagePatterns.entries) {
      if (entry.key == 'fr' &&
          audioText.toLowerCase().contains('vostfr')) {
        // VOSTFR is French subtitles over original audio.
        continue;
      }
      if (entry.value.hasMatch(audioText)) {
        audioLangs.add(entry.key);
      }
    }

    for (final m in _bracketShortCodePattern.allMatches(audioText)) {
      final token = m.group(1)!.toLowerCase();
      final mapped = token == 'jp' ? 'ja' : token;
      audioLangs.add(mapped);
    }

    for (final entry in _flagToCode.entries) {
      if (audioText.contains(entry.key)) {
        audioLangs.add(entry.value);
      }
    }

    // CloudStream provider-declared language acts as fallback hint when the
    // link descriptor didn't explicitly state audio languages.
    final normProviderLang = normalizeLanguageCode(stream.providerLang);
    if (audioLangs.isEmpty && normProviderLang != null) {
      audioLangs.add(normProviderLang);
    }

    final isMultiAudio =
        audioLangs.length >= 2 || _multiAudioPattern.hasMatch(audioText);

    // Quality resolution
    final resolutionHeight = _parseResolutionHeight(
      combinedRaw,
      fallbackRank: stream.qualityRank,
    );
    final isAdaptiveMaster =
        stream.transport == StreamTransport.hls && resolutionHeight == 0;

    return ParsedStreamMetadata(
      detectedAudioLanguages: Set.unmodifiable(audioLangs),
      detectedSubtitleLanguages: Set.unmodifiable(subLangs),
      isMultiAudio: isMultiAudio,
      isHardcodedSub: isHardSub,
      resolutionHeight: resolutionHeight,
      isAdaptiveMaster: isAdaptiveMaster,
      hdrFormat: _parseHdr(combinedRaw),
      videoCodec: _parseVideoCodec(combinedRaw),
      audioCodec: _parseAudioCodec(combinedRaw),
      audioChannels: _parseAudioChannels(combinedRaw),
      releaseSource: _parseReleaseSource(combinedRaw),
    );
  }

  static String _stripMediaTitle(String text, String? mediaTitle) {
    if (mediaTitle == null || mediaTitle.trim().isEmpty) return text;
    final cleanTitle = mediaTitle.trim();
    var out = text;
    if (cleanTitle.length >= 4) {
      out = out.replaceAll(
        RegExp(RegExp.escape(cleanTitle), caseSensitive: false),
        ' ',
      );
      final dotted = cleanTitle.replaceAll(RegExp(r'\s+'), '.');
      out = out.replaceAll(
        RegExp(RegExp.escape(dotted), caseSensitive: false),
        ' ',
      );
    }
    return out;
  }

  static int _parseResolutionHeight(String text, {required int fallbackRank}) {
    final lower = text.toLowerCase();
    if (RegExp(r'\b(2160p?|4k|uhd)\b').hasMatch(lower)) return 2160;
    if (RegExp(r'\b(1440p?|2k|qhd)\b').hasMatch(lower)) return 1440;
    if (RegExp(r'\b(1080p?|fhd|full[\s._-]?hd)\b').hasMatch(lower)) return 1080;
    if (RegExp(r'\b(720p?|hd)\b').hasMatch(lower) &&
        !lower.contains('hdrip') &&
        !lower.contains('hdcam') &&
        !lower.contains('hdts')) {
      return 720;
    }
    if (RegExp(r'\b(480p?|sd)\b').hasMatch(lower)) return 480;
    if (RegExp(r'\b360p?\b').hasMatch(lower)) return 360;
    if (fallbackRank >= 2160) return 2160;
    if (fallbackRank >= 1440) return 1440;
    if (fallbackRank >= 1080) return 1080;
    if (fallbackRank >= 720) return 720;
    if (fallbackRank >= 480) return 480;
    if (fallbackRank >= 360) return 360;
    return 0;
  }

  static HdrFormat _parseHdr(String text) {
    final lower = text.toLowerCase();
    if (RegExp(r'\b(dovi|dolby[\s._-]?vision|dv)\b').hasMatch(lower)) {
      return HdrFormat.dolbyVision;
    }
    if (RegExp(r'\bhdr10\+|hdr10plus\b').hasMatch(lower)) {
      return HdrFormat.hdr10Plus;
    }
    if (RegExp(r'\bhdr10\b|\bhdr\b').hasMatch(lower)) {
      return HdrFormat.hdr10;
    }
    if (RegExp(r'\bhlg\b').hasMatch(lower)) {
      return HdrFormat.hlg;
    }
    return HdrFormat.none;
  }

  static VideoCodecHint _parseVideoCodec(String text) {
    final lower = text.toLowerCase();
    if (RegExp(r'\bav1\b').hasMatch(lower)) return VideoCodecHint.av1;
    if (RegExp(r'\b(hevc|x265|h[\s._-]?265)\b').hasMatch(lower)) {
      return VideoCodecHint.hevc;
    }
    if (RegExp(r'\bvp9\b').hasMatch(lower)) return VideoCodecHint.vp9;
    if (RegExp(r'\b(avc|x264|h[\s._-]?264)\b').hasMatch(lower)) {
      return VideoCodecHint.h264;
    }
    return VideoCodecHint.unknown;
  }

  static AudioCodecHint _parseAudioCodec(String text) {
    final lower = text.toLowerCase();
    if (RegExp(r'\batmos\b').hasMatch(lower)) return AudioCodecHint.atmos;
    if (RegExp(r'\btrue[\s._-]?hd\b').hasMatch(lower)) {
      return AudioCodecHint.trueHd;
    }
    if (RegExp(r'\bdts[\s._-]?(?:hd|x|ma)\b').hasMatch(lower)) {
      return AudioCodecHint.dtsHd;
    }
    if (RegExp(r'\bdts\b').hasMatch(lower)) return AudioCodecHint.dts;
    if (RegExp(r'(?:dd\+|ddp|e[\s._-]?ac[\s._-]?3|dolby[\s._-]?digital[\s._-]?plus)')
        .hasMatch(lower)) {
      return AudioCodecHint.eac3;
    }
    if (RegExp(r'\b(ac3|dd5\.?1|dolby[\s._-]?digital)\b').hasMatch(lower)) {
      return AudioCodecHint.ac3;
    }
    if (RegExp(r'\bflac\b').hasMatch(lower)) return AudioCodecHint.flac;
    if (RegExp(r'\bopus\b').hasMatch(lower)) return AudioCodecHint.opus;
    if (RegExp(r'\baac\b').hasMatch(lower)) return AudioCodecHint.aac;
    return AudioCodecHint.unknown;
  }

  static String? _parseAudioChannels(String text) {
    if (RegExp(r'\b7\.1\b').hasMatch(text)) return '7.1';
    if (RegExp(r'\b5\.1\b').hasMatch(text)) return '5.1';
    if (RegExp(r'\b2\.0\b').hasMatch(text)) return '2.0';
    return null;
  }

  static ReleaseSourceHint _parseReleaseSource(String text) {
    final lower = text.toLowerCase();
    if (RegExp(r'\b(cam|camrip|hdcam|hdts|telesync|telecine|dvdscr|scr|ts)\b')
        .hasMatch(lower)) {
      return ReleaseSourceHint.camTs;
    }
    if (RegExp(r'\bremux\b').hasMatch(lower)) return ReleaseSourceHint.remux;
    if (RegExp(r'\b(blu[\s._-]?ray|bdrip|brrip)\b').hasMatch(lower)) {
      return ReleaseSourceHint.bluRay;
    }
    if (RegExp(r'\bweb[\s._-]?dl\b').hasMatch(lower)) {
      return ReleaseSourceHint.webDl;
    }
    if (RegExp(r'\bweb[\s._-]?rip\b').hasMatch(lower)) {
      return ReleaseSourceHint.webRip;
    }
    if (RegExp(r'\bhd[\s._-]?rip\b').hasMatch(lower)) {
      return ReleaseSourceHint.hdRip;
    }
    return ReleaseSourceHint.unknown;
  }
}
