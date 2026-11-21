import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel/features/preferences/data/playback_preferences_storage.dart';
import 'package:pixel/features/preferences/domain/models/playback_preferences.dart';
import 'package:pixel/features/preferences/presentation/controllers/playback_preferences_controller.dart';

void main() {
  group('PlaybackPreferences', () {
    test('normalizes ISO-639-1, ISO-639-2, and display names accurately', () {
      expect(normalizeLanguageCode('hin'), 'hi');
      expect(normalizeLanguageCode('Hindi'), 'hi');
      expect(normalizeLanguageCode('en-US'), 'en');
      expect(normalizeLanguageCode('jpn'), 'ja');
      expect(normalizeLanguageCode('und'), isNull);
      expect(normalizeLanguageCode('uni'), isNull);
    });

    test('persists Primary/Fallback languages & settings atomically', () async {
      final tmpDir = await Directory.systemTemp.createTemp('openflix_prefs_');
      addTearDown(() => tmpDir.delete(recursive: true));
      final file = File('${tmpDir.path}/prefs.json');

      final container = ProviderContainer(
        overrides: [
          playbackPreferencesStorageProvider.overrideWithValue(
            PlaybackPreferencesStorage(fileOverride: file),
          ),
        ],
      );
      addTearDown(container.dispose);

      final initial =
          await container.read(playbackPreferencesControllerProvider.future);
      expect(initial.hasCompletedLanguageSetup, isFalse);

      final ctrl =
          container.read(playbackPreferencesControllerProvider.notifier);
      await ctrl.setLanguages(primary: 'hi', fallback: 'en');
      await ctrl.setSubtitleScale(1.2);
      await ctrl.setAutoPlayNext(false);

      final reloaded =
          await PlaybackPreferencesStorage(fileOverride: file).load();
      expect(reloaded.primaryLanguage, 'hi');
      expect(reloaded.fallbackLanguage, 'en');
      expect(reloaded.hasCompletedLanguageSetup, isTrue);
      expect(reloaded.subtitleScale, closeTo(1.2, 0.01));
      expect(reloaded.autoPlayNextEpisode, isFalse);
    });
  });
}
