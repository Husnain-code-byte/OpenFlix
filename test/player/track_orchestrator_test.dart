import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:pixel/features/addons/domain/models/stream_models.dart';
import 'package:pixel/features/player/data/track_orchestrator.dart';
import 'package:pixel/features/preferences/domain/models/playback_preferences.dart';

void main() {
  const prefs = PlaybackPreferences(
    primaryLanguage: 'hi',
    fallbackLanguage: 'en',
  );

  group('TrackOrchestrator', () {
    test('selectInitialAudio prioritizes Primary -> Fallback -> Default', () {
      final rawAudio = [
        AudioTrack.auto(),
        AudioTrack.no(),
        const AudioTrack('1', 'Japanese', 'jpn', codec: 'aac'),
        const AudioTrack('2', 'English', 'eng', codec: 'eac3', channels: '5.1'),
        const AudioTrack('3', 'Hindi', 'hin', codec: 'ac3', channels: '5.1'),
      ];

      final options = TrackOrchestrator.buildAudioOptions(rawAudio);
      expect(options.length, 3);

      final picked = TrackOrchestrator.selectInitialAudio(
        options: options,
        prefs: prefs,
      );
      expect(picked?.normalizedLang, 'hi');
      expect(picked?.codecDetail, 'AC3 5.1');

      final pickedFallback = TrackOrchestrator.selectInitialAudio(
        options: options.where((o) => o.normalizedLang != 'hi').toList(),
        prefs: prefs,
      );
      expect(pickedFallback?.normalizedLang, 'en');
    });

    test('Netflix smart subtitles stay OFF when active audio matches Primary language', () {
      final subs = TrackOrchestrator.buildSubtitleOptions(
        [
          SubtitleTrack.auto(),
          SubtitleTrack.no(),
          const SubtitleTrack('1', 'Hindi', 'hin', codec: 'ass'),
          const SubtitleTrack('2', 'English', 'eng', codec: 'subrip'),
        ],
        const [],
      );

      final subWhenPrimaryAudio = TrackOrchestrator.selectInitialSubtitle(
        options: subs,
        prefs: prefs,
        activeAudioLang: 'hi',
      );
      expect(subWhenPrimaryAudio.isOff, isTrue);
    });

    test('Netflix smart subtitles auto-enable Primary (or Fallback) embedded before external when audio differs', () {
      final subs = TrackOrchestrator.buildSubtitleOptions(
        [
          const SubtitleTrack('1', 'English', 'eng', codec: 'subrip'),
        ],
        const [
          ResolvedSubtitle(
            url: 'https://subs.example.com/hi.srt',
            language: 'hi',
            sourceName: 'OpenSubtitles',
          ),
        ],
      );

      // Primary audio is Hindi, stream audio is Japanese -> picks Hindi addon sub
      final pickHi = TrackOrchestrator.selectInitialSubtitle(
        options: subs,
        prefs: prefs,
        activeAudioLang: 'ja',
      );
      expect(pickHi.isOff, isFalse);
      expect(pickHi.normalizedLang, 'hi');

      // When only Fallback (English) exists while audio is Japanese -> picks English
      final enOnly = TrackOrchestrator.buildSubtitleOptions(
        [
          const SubtitleTrack('1', 'English', 'eng', codec: 'ass'),
        ],
        const [
          ResolvedSubtitle(
            url: 'https://subs.example.com/en.srt',
            language: 'en',
            sourceName: 'OpenSubtitles',
          ),
        ],
      );
      final pickEn = TrackOrchestrator.selectInitialSubtitle(
        options: enOnly,
        prefs: prefs,
        activeAudioLang: 'ja',
      );
      expect(pickEn.isOff, isFalse);
      expect(pickEn.isExternal, isFalse); // embedded preferred over external
    });
  });
}
