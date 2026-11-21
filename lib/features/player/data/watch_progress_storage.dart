import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../home/presentation/controllers/home_controller.dart';
import '../domain/models/watch_progress_models.dart';

class WatchProgressStoreState {
  const WatchProgressStoreState({this.entriesById = const {}});

  final Map<String, WatchProgressEntry> entriesById;

  WatchProgressEntry? lookup({
    String? imdbId,
    int? tmdbId,
    int? anilistId,
    String? rawId,
    required String mediaType,
  }) {
    final normType = mediaType == 'tv' ? 'series' : mediaType;
    final candidates = <String>[
      if (imdbId != null && imdbId.trim().isNotEmpty) 'imdb:${imdbId.trim()}',
      if (tmdbId != null && tmdbId > 0) 'tmdb:$normType:$tmdbId',
      if (anilistId != null && anilistId > 0) 'anilist:$anilistId',
      if (rawId != null && rawId.trim().isNotEmpty) ...[
        'raw:$normType:${rawId.trim()}',
        if (rawId.trim().startsWith('tt')) 'imdb:${rawId.trim()}',
        if (int.tryParse(rawId.trim()) != null) 'tmdb:$normType:${rawId.trim()}',
      ],
    ];

    for (final key in candidates) {
      final direct = entriesById[key];
      if (direct != null) return direct;
    }

    // Fallback scan across alias keys when an entry accumulated a new ID later.
    for (final entry in entriesById.values) {
      if (entry.mediaType != normType) continue;
      if (imdbId != null && imdbId.isNotEmpty && entry.imdbId == imdbId) {
        return entry;
      }
      if (tmdbId != null && tmdbId > 0 && entry.tmdbId == tmdbId) {
        return entry;
      }
      if (anilistId != null &&
          anilistId > 0 &&
          entry.anilistId == anilistId) {
        return entry;
      }
      if (rawId != null && rawId.isNotEmpty && entry.rawId == rawId) {
        return entry;
      }
    }
    return null;
  }

  /// Returns Continue Watching entries filtered by [filter], ordered most
  /// recently watched first:
  /// - `Home`: all movies, TV shows, and anime
  /// - `Movies`: non-anime movies only
  /// - `TV Shows`: non-anime series only
  /// - `Anime`: anime titles only
  List<WatchProgressEntry> continueWatchingForFilter(HomeFilter filter) {
    if (filter == HomeFilter.categories) return const [];
    final list = entriesById.values.where((e) {
      if (!e.isInContinueWatching) return false;
      return switch (filter) {
        HomeFilter.home => true,
        HomeFilter.movies => e.mediaType == 'movie' && !e.isAnime,
        HomeFilter.tvShows => e.mediaType == 'series' && !e.isAnime,
        HomeFilter.anime => e.isAnime,
        HomeFilter.categories => false,
      };
    }).toList()
      ..sort((a, b) => b.updatedAtMs.compareTo(a.updatedAtMs));
    return list;
  }

  Map<String, dynamic> toJson() => {
        'entries': [for (final e in entriesById.values) e.toJson()],
      };

  factory WatchProgressStoreState.fromJson(Map<String, dynamic> json) {
    final list = json['entries'];
    final map = <String, WatchProgressEntry>{};
    if (list is List) {
      for (final raw in list) {
        if (raw is Map) {
          final entry =
              WatchProgressEntry.fromJson(Map<String, dynamic>.from(raw));
          if (entry.canonicalId.isNotEmpty) {
            map[entry.canonicalId] = entry;
          }
        }
      }
    }
    return WatchProgressStoreState(entriesById: map);
  }
}

class WatchProgressStorage {
  WatchProgressStorage({File? fileOverride}) : _fileOverride = fileOverride;

  static const _channel = MethodChannel('openflix/launcher');
  static const _fileName = 'watch_progress_v1.json';

  final File? _fileOverride;
  String? _cachedFilesDir;
  Future<void> _writeChain = Future<void>.value();
  WatchProgressStoreState? _queued;
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
    final dir = Directory('$dirPath/playback');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return File('${dir.path}/$_fileName');
  }

  Future<WatchProgressStoreState> load() async {
    try {
      final file = await _resolveFile();
      if (file == null || !await file.exists()) {
        return const WatchProgressStoreState();
      }
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return const WatchProgressStoreState();
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return const WatchProgressStoreState();
      }
      return WatchProgressStoreState.fromJson(decoded);
    } catch (_) {
      return const WatchProgressStoreState();
    }
  }

  Future<void> save(WatchProgressStoreState state) {
    _queued = state;
    _writeChain = _writeChain.then((_) async {
      final toWrite = _queued;
      if (toWrite == null) return;
      _queued = null;
      await _writeAtomic(toWrite);
    }).catchError((_) {});
    return _writeChain;
  }

  Future<void> _writeAtomic(WatchProgressStoreState state) async {
    final file = await _resolveFile();
    if (file == null) return;
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    final tmp = File('${file.path}.${++_tmpCounter}.tmp');
    await tmp.writeAsString(jsonEncode(state.toJson()), flush: true);
    await tmp.rename(file.path);
  }
}

final watchProgressStorageProvider =
    Provider<WatchProgressStorage>((ref) => WatchProgressStorage());
