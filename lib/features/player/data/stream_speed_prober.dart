import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../addons/domain/models/stream_models.dart';
import '../domain/models/ranked_stream.dart';

class StreamSpeedProber {
  StreamSpeedProber({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(milliseconds: 1800),
                receiveTimeout: const Duration(milliseconds: 1800),
                followRedirects: true,
                maxRedirects: 6,
                validateStatus: (code) => code != null && code < 500,
              ),
            );

  static const int _maxProbeBytes = 65536;
  static const int _cacheTtlMs = 5 * 60 * 1000;
  static const String _defaultUserAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

  final Dio _dio;
  final Map<String, StreamProbeResult> _cache = {};

  Map<String, StreamProbeResult> get snapshotCache => Map.unmodifiable(_cache);

  StreamProbeResult? cachedFor(String dedupKey, {DateTime? now}) {
    final hit = _cache[dedupKey];
    if (hit == null) return null;
    final ts = (now ?? DateTime.now()).millisecondsSinceEpoch;
    if (ts - hit.probedAtMs > _cacheTtlMs) {
      _cache.remove(dedupKey);
      return null;
    }
    return hit;
  }

  /// Probes up to [maxProbes] top unprobed playable candidates concurrently.
  Future<Map<String, StreamProbeResult>> probeTopCandidates(
    List<RankedStream> ranked, {
    int maxProbes = 3,
    int? expectedRuntimeMinutes,
    CancelToken? cancelToken,
  }) async {
    if (_cache.length > 100) {
      _cache.clear();
    }
    final targets = <RankedStream>[];
    for (final item in ranked) {
      if (targets.length >= maxProbes) break;
      final s = item.stream;
      if (!s.canPlayInternally) {
        continue;
      }
      if (cachedFor(s.dedupKey) != null) continue;
      targets.add(item);
    }

    if (targets.isEmpty) return snapshotCache;

    await Future.wait([
      for (final target in targets)
        _probeSingle(
          target.stream,
          expectedRuntimeMinutes: expectedRuntimeMinutes,
          cancelToken: cancelToken,
        ).then((res) {
          _cache[target.stream.dedupKey] = res;
        }),
    ]);

    return snapshotCache;
  }

  Future<StreamProbeResult> _probeSingle(
    ResolvedStream stream, {
    int? expectedRuntimeMinutes,
    CancelToken? cancelToken,
  }) async {
    final url = stream.internalPlayableUrl;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (url == null || url.isEmpty) {
      return StreamProbeResult(
        isAlive: false,
        probedAtMs: nowMs,
        error: 'Missing URL',
      );
    }

    final headers = Map<String, dynamic>.from(
      stream.buildRequestHeaders(defaultUserAgent: _defaultUserAgent),
    );
    final isManifest = stream.transport == StreamTransport.hls ||
        stream.transport == StreamTransport.dash;
    final hasRangeHeader = headers.keys.any((k) => k.toLowerCase() == 'range');
    if (!isManifest && !hasRangeHeader) {
      headers['Range'] = 'bytes=0-${_maxProbeBytes - 1}';
    }

    final sw = Stopwatch()..start();
    try {
      final resp = await _dio.get<ResponseBody>(
        url,
        cancelToken: cancelToken,
        options: Options(
          headers: headers,
          responseType: ResponseType.stream,
        ),
      );
      final ttfbMs = sw.elapsedMilliseconds;
      final status = resp.statusCode ?? 0;
      final contentType =
          resp.headers.value(Headers.contentTypeHeader)?.toLowerCase() ?? '';

      if (status < 200 || status >= 400) {
        await resp.data?.stream.drain<void>().catchError((_) {});
        // Many debrid/proxy servers reject Dio's short Range/GET probe with
        // 403/405/406/416/429 while libmpv streams them cleanly. Only mark
        // definitive dead responses (e.g. 404/410) as dead.
        final isProbeBlocked = status == 403 ||
            status == 405 ||
            status == 406 ||
            status == 416 ||
            status == 429;
        return StreamProbeResult(
          isAlive: isProbeBlocked,
          isInconclusive: isProbeBlocked,
          statusCode: status,
          ttfbMs: isProbeBlocked ? null : ttfbMs,
          contentType: contentType,
          probedAtMs: nowMs,
          error: isProbeBlocked ? 'HTTP $status (unprobed)' : 'HTTP $status',
        );
      }

      // Reject HTML challenge / error pages disguised as 200 OK.
      // Generic or missing Content-Type (e.g. application/octet-stream,
      // binary/octet-stream, empty) is always allowed for libmpv.
      if (contentType.contains('text/html')) {
        await resp.data?.stream.drain<void>().catchError((_) {});
        return StreamProbeResult(
          isAlive: false,
          statusCode: status,
          ttfbMs: ttfbMs,
          contentType: contentType,
          probedAtMs: nowMs,
          error: 'HTML response',
        );
      }

      // Read up to 64 KB cleanly and cancel the underlying stream immediately
      // if the server ignored Range and returned an entire media file.
      final body = resp.data;
      var bytesRead = 0;
      final chunks = <int>[];
      if (body != null) {
        final done = Completer<void>();
        late StreamSubscription<List<int>> sub;
        sub = body.stream.listen(
          (chunk) {
            if (bytesRead < _maxProbeBytes) {
              final remaining = _maxProbeBytes - bytesRead;
              final take = chunk.length <= remaining ? chunk.length : remaining;
              if (take > 0) {
                chunks.addAll(chunk.sublist(0, take));
                bytesRead += take;
              }
            }
            if (bytesRead >= _maxProbeBytes && !done.isCompleted) {
              unawaited(sub.cancel().catchError((_) {}));
              done.complete();
            }
          },
          onError: (Object _) {
            if (!done.isCompleted) done.complete();
          },
          onDone: () {
            if (!done.isCompleted) done.complete();
          },
          cancelOnError: true,
        );
        await done.future.timeout(
          const Duration(milliseconds: 1200),
          onTimeout: () async {
            await sub.cancel().catchError((_) {});
          },
        );
      }

      final totalMs = sw.elapsedMilliseconds.clamp(1, 60000);
      final isBinaryMediaResponse = contentType.startsWith('video/') ||
          contentType.contains('octet-stream') ||
          contentType.contains('mp2t') ||
          contentType.contains('matroska');
      final bodyText = isManifest && !isBinaryMediaResponse
          ? utf8.decode(chunks, allowMalformed: true).trimLeft()
          : '';
      if (isManifest &&
          !isBinaryMediaResponse &&
          !bodyText.contains('#EXTM3U') &&
          !bodyText.contains('<MPD')) {
        return StreamProbeResult(
          isAlive: false,
          statusCode: status,
          ttfbMs: ttfbMs,
          contentType: contentType,
          probedAtMs: nowMs,
          error: 'Invalid manifest payload',
        );
      }

      // Parse exact duration from HLS media playlist (or follow first variant
      // of a master playlist) to filter out mismatched runtimes before showing.
      int? probedDurationSec;
      if (stream.transport == StreamTransport.hls &&
          expectedRuntimeMinutes != null &&
          expectedRuntimeMinutes > 0) {
        probedDurationSec = await _extractHlsDurationSeconds(
          manifestText: bodyText,
          baseUrl: url,
          headers: headers,
          cancelToken: cancelToken,
        );
      }
      final runtimeMismatch = probedDurationSec != null &&
          !isDurationCompatibleWithRuntime(
            probedDurationSec,
            expectedRuntimeMinutes,
          );
      if (runtimeMismatch) {
        return StreamProbeResult(
          isAlive: false,
          statusCode: status,
          ttfbMs: ttfbMs,
          contentType: contentType,
          probedDurationSeconds: probedDurationSec,
          runtimeMismatch: true,
          probedAtMs: nowMs,
          error:
              'Runtime mismatch (${(probedDurationSec / 60).round()}m vs ${expectedRuntimeMinutes}m)',
        );
      }

      final downloadMs = (totalMs - ttfbMs).clamp(1, 60000);
      final estimatedMbps = isManifest || bytesRead < 4096
          ? null
          : (bytesRead * 8.0) / (downloadMs * 1000.0);

      return StreamProbeResult(
        isAlive: true,
        statusCode: status,
        ttfbMs: ttfbMs,
        estimatedMbps: estimatedMbps,
        contentType: contentType,
        probedDurationSeconds: probedDurationSec,
        probedAtMs: nowMs,
      );
    } catch (e) {
      // Short 1.8s probe timeouts or TLS/proxy quirks should not hide a
      // potentially playable HTTP stream from libmpv; treat as inconclusive.
      return StreamProbeResult(
        isAlive: true,
        isInconclusive: true,
        probedAtMs: nowMs,
        error: e.toString().replaceFirst('DioException', 'Network'),
      );
    }
  }

  static final RegExp _extinfRegex = RegExp(r'#EXTINF:([0-9]+(?:\.[0-9]+)?)');

  static int? _sumExtinfSeconds(String playlist) {
    if (!playlist.contains('#EXTINF:')) return null;
    double total = 0;
    var count = 0;
    for (final m in _extinfRegex.allMatches(playlist)) {
      final v = double.tryParse(m.group(1) ?? '');
      if (v != null && v > 0) {
        total += v;
        count++;
      }
    }
    return count > 0 ? total.round() : null;
  }

  Future<int?> _extractHlsDurationSeconds({
    required String manifestText,
    required String baseUrl,
    required Map<String, dynamic> headers,
    CancelToken? cancelToken,
  }) async {
    final direct = _sumExtinfSeconds(manifestText);
    if (direct != null) return direct;

    // Master playlist: find first variant URI and inspect its #EXTINF segments.
    if (!manifestText.contains('#EXT-X-STREAM-INF')) return null;
    final lines = manifestText.split(RegExp(r'\r?\n'));
    String? variantLine;
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].startsWith('#EXT-X-STREAM-INF')) {
        for (var j = i + 1; j < lines.length; j++) {
          final l = lines[j].trim();
          if (l.isEmpty) continue;
          if (!l.startsWith('#')) {
            variantLine = l;
            break;
          }
        }
        if (variantLine != null) break;
      }
    }
    if (variantLine == null) return null;

    try {
      final resolvedUri = Uri.parse(baseUrl).resolve(variantLine).toString();
      final resp = await _dio.get<String>(
        resolvedUri,
        cancelToken: cancelToken,
        options: Options(
          headers: headers,
          responseType: ResponseType.plain,
        ),
      );
      final body = resp.data;
      if (body == null || body.isEmpty) return null;
      return _sumExtinfSeconds(body);
    } catch (_) {
      return null;
    }
  }
}

final streamSpeedProberProvider = Provider<StreamSpeedProber>(
  (ref) => StreamSpeedProber(),
);
