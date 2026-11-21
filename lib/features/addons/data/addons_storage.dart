import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/addon_models.dart';

class AddonsStorage {
  AddonsStorage({File? fileOverride}) : _fileOverride = fileOverride;

  static const _channel = MethodChannel('openflix/launcher');
  static const _fileName = 'addons_state_v1.json';

  final File? _fileOverride;
  String? _cachedFilesDir;
  Future<void> _writeChain = Future<void>.value();
  AddonsStoreState? _queuedState;
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
    final addonsDir = Directory('$dirPath/addons');
    if (!addonsDir.existsSync()) {
      addonsDir.createSync(recursive: true);
    }
    return File('${addonsDir.path}/$_fileName');
  }

  Future<AddonsStoreState> load() async {
    try {
      final file = await _resolveFile();
      if (file == null || !await file.exists()) {
        return const AddonsStoreState();
      }
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return const AddonsStoreState();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const AddonsStoreState();
      return AddonsStoreState.fromJson(decoded);
    } catch (_) {
      return const AddonsStoreState();
    }
  }

  /// Serialized, coalescing atomic save so concurrent batch installs never
  /// race on the same temp file or clobber newer snapshots with older ones.
  Future<void> save(AddonsStoreState state) {
    _queuedState = state;
    _writeChain = _writeChain.then((_) async {
      final toWrite = _queuedState;
      if (toWrite == null) return;
      _queuedState = null;
      await _writeAtomic(toWrite);
    }).catchError((_) {
      // Keep the write chain healthy even if a transient I/O error occurs.
    });
    return _writeChain;
  }

  Future<void> _writeAtomic(AddonsStoreState state) async {
    final file = await _resolveFile();
    if (file == null) return;
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    final tmp = File('${file.path}.${++_tmpCounter}.tmp');
    final encoded = jsonEncode(state.toJson());
    await tmp.writeAsString(encoded, flush: true);
    await tmp.rename(file.path);
  }
}

final addonsStorageProvider = Provider<AddonsStorage>((ref) => AddonsStorage());
