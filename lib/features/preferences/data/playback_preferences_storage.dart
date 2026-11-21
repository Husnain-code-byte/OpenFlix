import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/playback_preferences.dart';

class PlaybackPreferencesStorage {
  PlaybackPreferencesStorage({File? fileOverride})
      : _fileOverride = fileOverride;

  static const _channel = MethodChannel('openflix/launcher');
  static const _fileName = 'playback_prefs_v1.json';

  final File? _fileOverride;
  String? _cachedFilesDir;
  Future<void> _writeChain = Future<void>.value();
  PlaybackPreferences? _queued;
  int _tmpCounter = 0;

  Future<File?> _resolveFile() async {
    if (_fileOverride != null) return _fileOverride;
    if (_cachedFilesDir == null && Platform.isAndroid) {
      try {
        _cachedFilesDir = await _channel.invokeMethod<String>('getFilesDir');
      } catch (_) {}
      if (_cachedFilesDir == null) {
        for (final base in const [
          '/data/user/0/app.openflix.client/files',
          '/data/data/app.openflix.client/files',
          '/data/user/0/com.example.pixel/files',
          '/data/data/com.example.pixel/files',
        ]) {
          if (Directory(base).existsSync()) {
            _cachedFilesDir = base;
            break;
          }
        }
      }
    }
    final dirPath = _cachedFilesDir;
    if (dirPath == null || dirPath.trim().isEmpty) return null;
    final prefsDir = Directory('$dirPath/preferences');
    if (!prefsDir.existsSync()) {
      prefsDir.createSync(recursive: true);
    }
    return File('${prefsDir.path}/$_fileName');
  }

  Future<PlaybackPreferences> load() async {
    try {
      final file = await _resolveFile();
      if (file == null || !await file.exists()) {
        return const PlaybackPreferences();
      }
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return const PlaybackPreferences();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return const PlaybackPreferences();
      }
      return PlaybackPreferences.fromJson(decoded);
    } catch (_) {
      return const PlaybackPreferences();
    }
  }

  Future<void> save(PlaybackPreferences prefs) {
    _queued = prefs;
    _writeChain = _writeChain.then((_) async {
      final toWrite = _queued;
      if (toWrite == null) return;
      _queued = null;
      await _writeAtomic(toWrite);
    }).catchError((_) {});
    return _writeChain;
  }

  Future<void> _writeAtomic(PlaybackPreferences prefs) async {
    final file = await _resolveFile();
    if (file == null) return;
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    final tmp = File('${file.path}.${++_tmpCounter}.tmp');
    await tmp.writeAsString(jsonEncode(prefs.toJson()), flush: true);
    await tmp.rename(file.path);
  }
}

final playbackPreferencesStorageProvider =
    Provider<PlaybackPreferencesStorage>((ref) => PlaybackPreferencesStorage());
