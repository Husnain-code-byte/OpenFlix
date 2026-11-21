import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/addon_models.dart';
import '../domain/models/stream_models.dart';

class Cs3InstallOutcome {
  const Cs3InstallOutcome({
    required this.status,
    this.localFilePath,
    this.providers = const [],
    this.extractors = const [],
    this.error,
  });

  final Cs3LoadStatus status;
  final String? localFilePath;
  final List<String> providers;
  final List<String> extractors;
  final String? error;
}

sealed class Cs3StreamEvent {
  const Cs3StreamEvent(this.requestId);
  final String requestId;
}

class Cs3StreamLinkEvent extends Cs3StreamEvent {
  const Cs3StreamLinkEvent(super.requestId, this.stream);
  final ResolvedStream stream;
}

class Cs3SubtitleEvent extends Cs3StreamEvent {
  const Cs3SubtitleEvent(super.requestId, this.providerName, this.subtitle);
  final String providerName;
  final ResolvedSubtitle subtitle;
}

class Cs3ProviderDoneEvent extends Cs3StreamEvent {
  const Cs3ProviderDoneEvent(
    super.requestId, {
    required this.providerName,
    required this.streamCount,
    required this.elapsedMs,
  });

  final String providerName;
  final int streamCount;
  final int elapsedMs;
}

class Cs3ProviderErrorEvent extends Cs3StreamEvent {
  const Cs3ProviderErrorEvent(
    super.requestId, {
    required this.providerName,
    required this.error,
    required this.elapsedMs,
  });

  final String providerName;
  final String error;
  final int elapsedMs;
}

class Cs3ResolutionCompleteEvent extends Cs3StreamEvent {
  const Cs3ResolutionCompleteEvent(super.requestId);
}

abstract interface class CloudStreamEngine {
  Future<Map<String, Cs3InstallOutcome>> loadSavedPlugins(
    List<InstalledCs3Plugin> plugins,
  );

  Future<Cs3InstallOutcome> installPlugin({
    required String uid,
    required String repoId,
    required String internalName,
    required String downloadUrl,
    String? expectedSha256,
    bool enabled = true,
  });

  Future<bool> setPluginEnabled(String uid, bool enabled);

  Future<bool> uninstallPlugin(String uid, {String? localFilePath});

  Stream<Cs3StreamEvent> resolveStreams({
    required String requestId,
    required StreamQuery query,
  });

  Future<void> cancelStreamResolution(String requestId);
}

class AndroidCloudStreamEngine implements CloudStreamEngine {
  static const _methodChannel = MethodChannel('openflix/cloudstream');
  static const _eventChannel = EventChannel('openflix/cloudstream_events');

  Stream<Map<String, dynamic>>? _sharedEvents;

  Stream<Map<String, dynamic>> get _rawEvents => _sharedEvents ??=
      _eventChannel.receiveBroadcastStream().map((event) {
        if (event is Map) {
          return Map<String, dynamic>.from(event);
        }
        return const <String, dynamic>{};
      });

  @override
  Future<Map<String, Cs3InstallOutcome>> loadSavedPlugins(
    List<InstalledCs3Plugin> plugins,
  ) async {
    if (!Platform.isAndroid || plugins.isEmpty) return const {};
    try {
      final raw = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>(
        'loadSavedPlugins',
        {
          'plugins': [
            for (final p in plugins)
              if (p.localFilePath != null && p.localFilePath!.isNotEmpty)
                {
                  'uid': p.uid,
                  'localFilePath': p.localFilePath,
                  'enabled': p.enabled,
                },
          ],
        },
      );
      if (raw == null) return const {};
      final out = <String, Cs3InstallOutcome>{};
      raw.forEach((key, value) {
        if (value is Map) {
          out[key.toString()] = _parseOutcome(Map<String, dynamic>.from(value));
        }
      });
      return out;
    } catch (e) {
      debugPrint('loadSavedPlugins error: $e');
      return const {};
    }
  }

  @override
  Future<Cs3InstallOutcome> installPlugin({
    required String uid,
    required String repoId,
    required String internalName,
    required String downloadUrl,
    String? expectedSha256,
    bool enabled = true,
  }) async {
    if (!Platform.isAndroid) {
      return const Cs3InstallOutcome(
        status: Cs3LoadStatus.failed,
        error: 'Native .cs3 execution requires Android runtime.',
      );
    }
    try {
      final raw = await _methodChannel.invokeMethod<Map<dynamic, dynamic>>(
        'installPlugin',
        {
          'uid': uid,
          'repoId': repoId,
          'internalName': internalName,
          'downloadUrl': downloadUrl,
          'expectedSha256': expectedSha256,
          'enabled': enabled,
        },
      );
      if (raw == null) {
        return const Cs3InstallOutcome(
          status: Cs3LoadStatus.failed,
          error: 'Native plugin loader returned null.',
        );
      }
      return _parseOutcome(Map<String, dynamic>.from(raw));
    } catch (e) {
      return Cs3InstallOutcome(
        status: Cs3LoadStatus.failed,
        error: e.toString(),
      );
    }
  }

  @override
  Future<bool> setPluginEnabled(String uid, bool enabled) async {
    if (!Platform.isAndroid) return false;
    try {
      return (await _methodChannel.invokeMethod<bool>('setPluginEnabled', {
            'uid': uid,
            'enabled': enabled,
          })) ??
          false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> uninstallPlugin(String uid, {String? localFilePath}) async {
    if (!Platform.isAndroid) return true;
    try {
      return (await _methodChannel.invokeMethod<bool>('uninstallPlugin', {
            'uid': uid,
            'localFilePath': localFilePath,
          })) ??
          false;
    } catch (_) {
      return false;
    }
  }

  @override
  Stream<Cs3StreamEvent> resolveStreams({
    required String requestId,
    required StreamQuery query,
  }) async* {
    if (!Platform.isAndroid) {
      yield Cs3ResolutionCompleteEvent(requestId);
      return;
    }

    final controller = StreamController<Cs3StreamEvent>();
    var linkCounter = 0;

    final sub = _rawEvents.where((m) => m['requestId'] == requestId).listen(
      (m) {
        final type = m['eventType']?.toString();
        switch (type) {
          case 'stream':
            final url = m['url']?.toString().trim() ?? '';
            if (url.isEmpty) break;
            final isM3u8 = m['isM3u8'] == true ||
                m['type'] == 'M3U8' ||
                url.toLowerCase().contains('.m3u8');
            final isDash = m['isDash'] == true ||
                m['type'] == 'DASH' ||
                url.toLowerCase().contains('.mpd');
            final isTorrent =
                m['type'] == 'TORRENT' || m['type'] == 'MAGNET' || url.startsWith('magnet:');
            final transport = isTorrent
                ? StreamTransport.torrent
                : (isM3u8
                    ? StreamTransport.hls
                    : (isDash ? StreamTransport.dash : StreamTransport.directHttp));
            final qualityVal = (m['quality'] as num?)?.toInt() ?? 0;
            final qualityLabel = _qualityFromInt(qualityVal, m['linkName']?.toString());
            final headers = <String, String>{};
            if (m['headers'] is Map) {
              (m['headers'] as Map).forEach((k, v) {
                if (v != null) headers[k.toString()] = v.toString();
              });
            }
            final providerName = m['providerName']?.toString() ?? 'CloudStream';
            final linkName = m['linkName']?.toString() ?? providerName;
            final linkSource = m['linkSource']?.toString();
            controller.add(
              Cs3StreamLinkEvent(
                requestId,
                ResolvedStream(
                  id: 'cs3_${requestId}_${linkCounter++}',
                  architecture: AddonArchitecture.cloudstream,
                  addonId: m['sourcePlugin']?.toString() ?? providerName,
                  addonName: providerName,
                  providerName: linkSource?.isNotEmpty == true ? linkSource! : providerName,
                  title: linkName,
                  description: linkSource != null && linkSource != linkName
                      ? linkSource
                      : providerName,
                  transport: transport,
                  url: url,
                  headers: headers,
                  referer: m['referer']?.toString(),
                  qualityLabel: qualityLabel,
                  qualityRank: qualityVal,
                  providerLang: m['providerLang']?.toString(),
                ),
              ),
            );
          case 'subtitle':
            final subUrl = m['url']?.toString().trim() ?? '';
            if (subUrl.isEmpty) break;
            final headers = <String, String>{};
            if (m['headers'] is Map) {
              (m['headers'] as Map).forEach((k, v) {
                if (v != null) headers[k.toString()] = v.toString();
              });
            }
            final providerName = m['providerName']?.toString() ?? 'CloudStream';
            controller.add(
              Cs3SubtitleEvent(
                requestId,
                providerName,
                ResolvedSubtitle(
                  url: subUrl,
                  language: m['lang']?.toString() ?? 'und',
                  sourceName: providerName,
                  headers: headers,
                ),
              ),
            );
          case 'providerDone':
            controller.add(
              Cs3ProviderDoneEvent(
                requestId,
                providerName: m['providerName']?.toString() ?? 'CloudStream',
                streamCount: (m['streamCount'] as num?)?.toInt() ?? 0,
                elapsedMs: (m['elapsedMs'] as num?)?.toInt() ?? 0,
              ),
            );
          case 'providerError':
            controller.add(
              Cs3ProviderErrorEvent(
                requestId,
                providerName: m['providerName']?.toString() ?? 'CloudStream',
                error: m['error']?.toString() ?? 'Error',
                elapsedMs: (m['elapsedMs'] as num?)?.toInt() ?? 0,
              ),
            );
          case 'complete':
            controller.add(Cs3ResolutionCompleteEvent(requestId));
            controller.close();
        }
      },
      onError: (Object err) {
        if (!controller.isClosed) {
          controller.add(Cs3ResolutionCompleteEvent(requestId));
          controller.close();
        }
      },
    );

    try {
      await _methodChannel.invokeMethod<bool>('startStreamResolution', {
        'requestId': requestId,
        'mediaType': query.mediaType,
        'title': query.title,
        'originalTitle': query.originalTitle,
        'year': query.year,
        'imdbId': query.imdbId,
        'tmdbId': query.tmdbId?.toString(),
        'anilistId': query.anilistId?.toString(),
        'malId': query.malId?.toString(),
        'season': query.season,
        'episode': query.episode,
        'episodeTitle': query.episodeTitle,
        'isAnime': query.isAnime,
        'preferredLanguages': query.preferredLanguages,
        'skipProviders': query.skipProviders,
      });
    } catch (e) {
      if (!controller.isClosed) {
        controller.add(Cs3ResolutionCompleteEvent(requestId));
        await controller.close();
      }
    }

    try {
      yield* controller.stream;
    } finally {
      await sub.cancel();
    }
  }

  @override
  Future<void> cancelStreamResolution(String requestId) async {
    if (!Platform.isAndroid) return;
    try {
      await _methodChannel.invokeMethod<bool>('cancelStreamResolution', {
        'requestId': requestId,
      });
    } catch (_) {}
  }

  static Cs3InstallOutcome _parseOutcome(Map<String, dynamic> m) {
    final statusStr = m['status']?.toString();
    return Cs3InstallOutcome(
      status: statusStr == 'loaded' ? Cs3LoadStatus.loaded : Cs3LoadStatus.failed,
      localFilePath: m['localFilePath'] as String?,
      providers: (m['providers'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      extractors:
          (m['extractors'] as List?)?.map((e) => e.toString()).toList() ??
              const [],
      error: m['error'] as String?,
    );
  }

  static String? _qualityFromInt(int q, String? linkName) {
    if (q >= 2160) return '4K';
    if (q >= 1440) return '1440p';
    if (q >= 1080) return '1080p';
    if (q >= 720) return '720p';
    if (q >= 480) return '480p';
    if (q >= 360) return '360p';
    if (linkName != null) {
      final m = RegExp(r'\b(4k|2160p|1080p|720p|480p)\b', caseSensitive: false)
          .firstMatch(linkName);
      if (m != null) return m.group(1)!.toUpperCase();
    }
    return null;
  }
}

final cloudStreamEngineProvider = Provider<CloudStreamEngine>(
  (ref) => AndroidCloudStreamEngine(),
);
