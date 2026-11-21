import 'package:equatable/equatable.dart';

class WatchLanguageOption extends Equatable {
  const WatchLanguageOption({
    required this.code,
    required this.iso3,
    required this.name,
    required this.nativeName,
    required this.flagEmoji,
    required this.aliases,
  });

  /// Canonical ISO-639-1 code (`'en'`, `'hi'`, `'ja'`, etc.).
  final String code;

  /// Canonical ISO-639-2 code (`'eng'`, `'hin'`, `'jpn'`, etc.).
  final String iso3;

  final String name;
  final String nativeName;
  final String flagEmoji;
  final List<String> aliases;

  @override
  List<Object?> get props => [code, iso3, name];
}

const List<WatchLanguageOption> kSupportedWatchLanguages = [
  WatchLanguageOption(
    code: 'en',
    iso3: 'eng',
    name: 'English',
    nativeName: 'English',
    flagEmoji: '🇺🇸',
    aliases: ['english', 'eng', 'en', 'usa', 'uk', 'british'],
  ),
  WatchLanguageOption(
    code: 'hi',
    iso3: 'hin',
    name: 'Hindi',
    nativeName: 'हिन्दी',
    flagEmoji: '🇮🇳',
    aliases: ['hindi', 'hin', 'hi', 'ind', 'bollywood', 'हिन्दी', 'हिंदी'],
  ),
  WatchLanguageOption(
    code: 'ur',
    iso3: 'urd',
    name: 'Urdu',
    nativeName: 'اردو',
    flagEmoji: '🇵🇰',
    aliases: ['urdu', 'urd', 'ur', 'اردو'],
  ),
  WatchLanguageOption(
    code: 'pa',
    iso3: 'pan',
    name: 'Punjabi',
    nativeName: 'ਪੰਜਾਬੀ',
    flagEmoji: '🇮🇳',
    aliases: ['punjabi', 'pan', 'pa', 'pun'],
  ),
  WatchLanguageOption(
    code: 'ta',
    iso3: 'tam',
    name: 'Tamil',
    nativeName: 'தமிழ்',
    flagEmoji: '🇮🇳',
    aliases: ['tamil', 'tam', 'ta', 'தமிழ்'],
  ),
  WatchLanguageOption(
    code: 'te',
    iso3: 'tel',
    name: 'Telugu',
    nativeName: 'తెలుగు',
    flagEmoji: '🇮🇳',
    aliases: ['telugu', 'tel', 'te', 'తెలుగు'],
  ),
  WatchLanguageOption(
    code: 'ml',
    iso3: 'mal',
    name: 'Malayalam',
    nativeName: 'മലയാളம்',
    flagEmoji: '🇮🇳',
    aliases: ['malayalam', 'mal', 'ml', 'മലയാളம்'],
  ),
  WatchLanguageOption(
    code: 'kn',
    iso3: 'kan',
    name: 'Kannada',
    nativeName: 'ಕನ್ನಡ',
    flagEmoji: '🇮🇳',
    aliases: ['kannada', 'kan', 'kn', 'ಕನ್ನಡ'],
  ),
  WatchLanguageOption(
    code: 'bn',
    iso3: 'ben',
    name: 'Bengali',
    nativeName: 'বাংলা',
    flagEmoji: '🇧🇩',
    aliases: ['bengali', 'bangla', 'ben', 'bn', 'বাংলা'],
  ),
  WatchLanguageOption(
    code: 'mr',
    iso3: 'mar',
    name: 'Marathi',
    nativeName: 'मराठी',
    flagEmoji: '🇮🇳',
    aliases: ['marathi', 'mar', 'mr', 'मराठी'],
  ),
  WatchLanguageOption(
    code: 'ja',
    iso3: 'jpn',
    name: 'Japanese',
    nativeName: '日本語',
    flagEmoji: '🇯🇵',
    aliases: ['japanese', 'jpn', 'ja', 'jap', 'nihongo', '日本語'],
  ),
  WatchLanguageOption(
    code: 'ko',
    iso3: 'kor',
    name: 'Korean',
    nativeName: '한국어',
    flagEmoji: '🇰🇷',
    aliases: ['korean', 'kor', 'ko', '한국어'],
  ),
  WatchLanguageOption(
    code: 'es',
    iso3: 'spa',
    name: 'Spanish',
    nativeName: 'Español',
    flagEmoji: '🇪🇸',
    aliases: ['spanish', 'espanol', 'español', 'latino', 'castellano', 'spa', 'es', 'lat'],
  ),
  WatchLanguageOption(
    code: 'fr',
    iso3: 'fra',
    name: 'French',
    nativeName: 'Français',
    flagEmoji: '🇫🇷',
    aliases: ['french', 'francais', 'français', 'vostfr', 'truefrench', 'vf', 'fra', 'fre', 'fr'],
  ),
  WatchLanguageOption(
    code: 'de',
    iso3: 'deu',
    name: 'German',
    nativeName: 'Deutsch',
    flagEmoji: '🇩🇪',
    aliases: ['german', 'deutsch', 'deu', 'ger', 'de'],
  ),
  WatchLanguageOption(
    code: 'it',
    iso3: 'ita',
    name: 'Italian',
    nativeName: 'Italiano',
    flagEmoji: '🇮🇹',
    aliases: ['italian', 'italiano', 'ita', 'it'],
  ),
  WatchLanguageOption(
    code: 'pt',
    iso3: 'por',
    name: 'Portuguese',
    nativeName: 'Português',
    flagEmoji: '🇧🇷',
    aliases: ['portuguese', 'portugues', 'português', 'dublado', 'pt-br', 'ptbr', 'por', 'pt'],
  ),
  WatchLanguageOption(
    code: 'ru',
    iso3: 'rus',
    name: 'Russian',
    nativeName: 'Русский',
    flagEmoji: '🇷🇺',
    aliases: ['russian', 'русский', 'rus', 'ru'],
  ),
  WatchLanguageOption(
    code: 'ar',
    iso3: 'ara',
    name: 'Arabic',
    nativeName: 'العربية',
    flagEmoji: '🇸🇦',
    aliases: ['arabic', 'العربية', 'ara', 'ar'],
  ),
  WatchLanguageOption(
    code: 'tr',
    iso3: 'tur',
    name: 'Turkish',
    nativeName: 'Türkçe',
    flagEmoji: '🇹🇷',
    aliases: ['turkish', 'turkce', 'türkçe', 'tur', 'tr'],
  ),
  WatchLanguageOption(
    code: 'zh',
    iso3: 'zho',
    name: 'Chinese',
    nativeName: '中文',
    flagEmoji: '🇨🇳',
    aliases: ['chinese', 'mandarin', 'cantonese', 'chs', 'cht', 'zho', 'chi', 'zh'],
  ),
  WatchLanguageOption(
    code: 'id',
    iso3: 'ind',
    name: 'Indonesian',
    nativeName: 'Bahasa Indonesia',
    flagEmoji: '🇮🇩',
    aliases: ['indonesian', 'bahasa', 'indo', 'id'],
  ),
];

final Map<String, WatchLanguageOption> _byCode = {
  for (final l in kSupportedWatchLanguages) l.code: l,
};

final Map<String, String> _aliasToCode = () {
  final map = <String, String>{};
  for (final l in kSupportedWatchLanguages) {
    map[l.code.toLowerCase()] = l.code;
    map[l.iso3.toLowerCase()] = l.code;
    map[l.name.toLowerCase()] = l.code;
    map[l.nativeName.toLowerCase()] = l.code;
    for (final a in l.aliases) {
      map[a.toLowerCase()] = l.code;
    }
  }
  return map;
}();

/// Normalizes ISO-639-1 (`en`), ISO-639-2/B/T (`eng`, `hin`, `ger`, `fre`),
/// locale tags (`en-US`, `pt_BR`), or language display names into canonical
/// ISO-639-1 codes (`'en'`, `'hi'`, etc.). Returns `null` for `und`/unknown.
String? normalizeLanguageCode(String? raw) {
  if (raw == null) return null;
  final trimmed = raw.trim().toLowerCase();
  if (trimmed.isEmpty ||
      trimmed == 'und' ||
      trimmed == 'unknown' ||
      trimmed == 'auto' ||
      trimmed == 'no' ||
      trimmed == 'uni' ||
      trimmed == 'multi' ||
      trimmed == 'all') {
    return null;
  }

  final direct = _aliasToCode[trimmed];
  if (direct != null) return direct;

  // Strip locale/region suffixes like `en-us`, `hi_IN`, `es-419`.
  final parts = trimmed.split(RegExp(r'[-_\s\(\)\[\],:/]+'));
  for (final part in parts) {
    if (part.isEmpty) continue;
    final found = _aliasToCode[part];
    if (found != null) return found;
  }
  return null;
}

WatchLanguageOption languageOptionForCode(String code) {
  final normalized = normalizeLanguageCode(code) ?? 'en';
  return _byCode[normalized] ?? kSupportedWatchLanguages.first;
}

String languageDisplayName(String? raw) {
  final norm = normalizeLanguageCode(raw);
  if (norm != null) {
    return _byCode[norm]?.name ?? norm.toUpperCase();
  }
  final clean = (raw ?? '').trim();
  if (clean.isEmpty || clean.toLowerCase() == 'und') return 'Unknown';
  return clean;
}

class PlaybackPreferences extends Equatable {
  const PlaybackPreferences({
    this.primaryLanguage = 'en',
    this.fallbackLanguage = 'en',
    this.hasCompletedLanguageSetup = false,
    this.autoPlayNextEpisode = true,
    this.subtitleScale = 1.0,
    this.hardwareDecoding = true,
    this.autoSkipIntroRecap = false,
    this.autoSkipOutro = false,
  });

  final String primaryLanguage;
  final String fallbackLanguage;
  final bool hasCompletedLanguageSetup;
  final bool autoPlayNextEpisode;
  final double subtitleScale;
  final bool hardwareDecoding;
  final bool autoSkipIntroRecap;
  final bool autoSkipOutro;

  List<String> get preferredLanguagePair {
    final p = normalizeLanguageCode(primaryLanguage) ?? 'en';
    final f = normalizeLanguageCode(fallbackLanguage) ?? 'en';
    if (p == f) return [p];
    return [p, f];
  }

  PlaybackPreferences copyWith({
    String? primaryLanguage,
    String? fallbackLanguage,
    bool? hasCompletedLanguageSetup,
    bool? autoPlayNextEpisode,
    double? subtitleScale,
    bool? hardwareDecoding,
    bool? autoSkipIntroRecap,
    bool? autoSkipOutro,
  }) =>
      PlaybackPreferences(
        primaryLanguage: primaryLanguage ?? this.primaryLanguage,
        fallbackLanguage: fallbackLanguage ?? this.fallbackLanguage,
        hasCompletedLanguageSetup:
            hasCompletedLanguageSetup ?? this.hasCompletedLanguageSetup,
        autoPlayNextEpisode: autoPlayNextEpisode ?? this.autoPlayNextEpisode,
        subtitleScale: subtitleScale ?? this.subtitleScale,
        hardwareDecoding: hardwareDecoding ?? this.hardwareDecoding,
        autoSkipIntroRecap: autoSkipIntroRecap ?? this.autoSkipIntroRecap,
        autoSkipOutro: autoSkipOutro ?? this.autoSkipOutro,
      );

  Map<String, dynamic> toJson() => {
        'primaryLanguage': primaryLanguage,
        'fallbackLanguage': fallbackLanguage,
        'hasCompletedLanguageSetup': hasCompletedLanguageSetup,
        'autoPlayNextEpisode': autoPlayNextEpisode,
        'subtitleScale': subtitleScale,
        'hardwareDecoding': hardwareDecoding,
        'autoSkipIntroRecap': autoSkipIntroRecap,
        'autoSkipOutro': autoSkipOutro,
      };

  factory PlaybackPreferences.fromJson(Map<String, dynamic> json) =>
      PlaybackPreferences(
        primaryLanguage:
            normalizeLanguageCode(json['primaryLanguage']?.toString()) ?? 'en',
        fallbackLanguage:
            normalizeLanguageCode(json['fallbackLanguage']?.toString()) ?? 'en',
        hasCompletedLanguageSetup: json['hasCompletedLanguageSetup'] == true,
        autoPlayNextEpisode: json['autoPlayNextEpisode'] != false,
        subtitleScale:
            ((json['subtitleScale'] as num?)?.toDouble() ?? 1.0).clamp(0.7, 1.6),
        hardwareDecoding: json['hardwareDecoding'] != false,
        autoSkipIntroRecap: json['autoSkipIntroRecap'] == true,
        autoSkipOutro: json['autoSkipOutro'] == true,
      );

  @override
  List<Object?> get props => [
        primaryLanguage,
        fallbackLanguage,
        hasCompletedLanguageSetup,
        autoPlayNextEpisode,
        subtitleScale,
        hardwareDecoding,
        autoSkipIntroRecap,
        autoSkipOutro,
      ];
}
