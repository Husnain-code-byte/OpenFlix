import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/playback_preferences_storage.dart';
import '../../domain/models/playback_preferences.dart';

class PlaybackPreferencesController
    extends AsyncNotifier<PlaybackPreferences> {
  PlaybackPreferencesStorage get _storage =>
      ref.read(playbackPreferencesStorageProvider);

  @override
  Future<PlaybackPreferences> build() async => _storage.load();

  Future<void> setLanguages({
    required String primary,
    required String fallback,
    bool markSetupComplete = true,
  }) async {
    final normPrimary = normalizeLanguageCode(primary) ?? 'en';
    final normFallback = normalizeLanguageCode(fallback) ?? 'en';
    final current = state.valueOrNull ?? const PlaybackPreferences();
    final next = current.copyWith(
      primaryLanguage: normPrimary,
      fallbackLanguage: normFallback,
      hasCompletedLanguageSetup:
          markSetupComplete || current.hasCompletedLanguageSetup,
    );
    state = AsyncData(next);
    await _storage.save(next);
  }

  Future<void> markLanguageSetupComplete() async {
    final current = state.valueOrNull ?? const PlaybackPreferences();
    if (current.hasCompletedLanguageSetup) return;
    final next = current.copyWith(hasCompletedLanguageSetup: true);
    state = AsyncData(next);
    await _storage.save(next);
  }

  Future<void> setAutoPlayNext(bool enabled) async {
    final current = state.valueOrNull ?? const PlaybackPreferences();
    final next = current.copyWith(autoPlayNextEpisode: enabled);
    state = AsyncData(next);
    await _storage.save(next);
  }

  Future<void> setSubtitleScale(double scale) async {
    final current = state.valueOrNull ?? const PlaybackPreferences();
    final next = current.copyWith(subtitleScale: scale.clamp(0.7, 1.6));
    state = AsyncData(next);
    await _storage.save(next);
  }

  Future<void> setHardwareDecoding(bool enabled) async {
    final current = state.valueOrNull ?? const PlaybackPreferences();
    final next = current.copyWith(hardwareDecoding: enabled);
    state = AsyncData(next);
    await _storage.save(next);
  }

  Future<void> setAutoSkipIntroRecap(bool enabled) async {
    final current = state.valueOrNull ?? const PlaybackPreferences();
    final next = current.copyWith(autoSkipIntroRecap: enabled);
    state = AsyncData(next);
    await _storage.save(next);
  }

  Future<void> setAutoSkipOutro(bool enabled) async {
    final current = state.valueOrNull ?? const PlaybackPreferences();
    final next = current.copyWith(autoSkipOutro: enabled);
    state = AsyncData(next);
    await _storage.save(next);
  }
}

final playbackPreferencesControllerProvider =
    AsyncNotifierProvider<PlaybackPreferencesController, PlaybackPreferences>(
  PlaybackPreferencesController.new,
);
