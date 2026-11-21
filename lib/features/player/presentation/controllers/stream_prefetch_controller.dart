import 'dart:async';

import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../addons/data/cloudstream_bridge_client.dart';
import '../../../addons/data/stremio_addon_service.dart';
import '../../../addons/domain/models/addon_models.dart';
import '../../../addons/domain/models/stream_models.dart';
import '../../../addons/presentation/controllers/addons_controller.dart';
import '../../../anime/data/anime_id_map.dart';
import '../../../preferences/domain/models/playback_preferences.dart';
import '../../../preferences/presentation/controllers/playback_preferences_controller.dart';
import '../../data/stream_ranker.dart';
import '../../data/stream_speed_prober.dart';
import '../../domain/models/ranked_stream.dart';

String prefetchKeyForQuery(StreamQuery q) {
  final baseId = (q.imdbId?.trim().isNotEmpty == true)
      ? 'imdb:${q.imdbId!.trim()}'
      : (q.tmdbId != null && q.tmdbId! > 0)
          ? 'tmdb:${q.tmdbId}'
          : (q.anilistId != null && q.anilistId! > 0)
              ? 'anilist:${q.anilistId}'
              : 'raw:${q.rawMetaId ?? q.title.trim().toLowerCase()}';
  final se = q.mediaType == 'series'
      ? '|s${q.season ?? 1}e${q.episode ?? 1}'
      : '';
  return '${q.mediaType}|$baseId$se';
}

class PrefetchSnapshot extends Equatable {
  const PrefetchSnapshot({
    required this.key,
    required this.query,
    this.isResolving = false,
    this.isProbing = false,
    this.isPaused = false,
    this.hasMoreProviders = false,
    this.hasAnyStreamAddon = true,
    this.rankedStreams = const [],
    this.bestAutoPlayKey,
    this.subtitles = const [],
    this.providerStatuses = const [],
    this.error,
    this.startedAtMs = 0,
  });

  final String key;
  final StreamQuery query;
  final bool isResolving;
  final bool isProbing;
  final bool isPaused;
  final bool hasMoreProviders;
  final bool hasAnyStreamAddon;
  /// Display-ordered streams (stable sequential append so links never jump
  /// around while the user is browsing or returning to the Links modal).
  final List<RankedStream> rankedStreams;
  /// Dedup key of the highest-scored auto-play candidate from [StreamRanker].
  final String? bestAutoPlayKey;
  final List<ResolvedSubtitle> subtitles;
  final List<ProviderResolutionStatus> providerStatuses;
  final String? error;
  final int startedAtMs;

  RankedStream? get bestPlayableStream {
    if (bestAutoPlayKey != null) {
      for (final r in rankedStreams) {
        if (r.dedupKey == bestAutoPlayKey && r.isAutoPlayEligible) {
          return r;
        }
      }
    }
    RankedStream? best;
    for (final r in rankedStreams) {
      if (!r.isAutoPlayEligible) continue;
      if (best == null || r.compositeScore > best.compositeScore) {
        best = r;
      }
    }
    return best;
  }

  /// True when a primary-language stream at >=720p (or adaptive HLS) has
  /// already been probed alive, allowing instant playback without waiting
  /// for slow or failing providers to time out.
  bool get hasHighConfidencePick {
    final best = bestPlayableStream;
    if (best == null) return false;
    final isPrimary =
        best.languageMatchTier == LanguageMatchTier.primaryDirect ||
            best.languageMatchTier == LanguageMatchTier.primaryMultiAudio;
    final goodRes =
        best.meta.resolutionHeight >= 720 || best.meta.isAdaptiveMaster;
    return isPrimary && goodRes && best.probe?.isAlive == true;
  }

  PrefetchSnapshot copyWith({
    StreamQuery? query,
    bool? isResolving,
    bool? isProbing,
    bool? isPaused,
    bool? hasMoreProviders,
    bool? hasAnyStreamAddon,
    List<RankedStream>? rankedStreams,
    String? bestAutoPlayKey,
    bool clearBestAutoPlayKey = false,
    List<ResolvedSubtitle>? subtitles,
    List<ProviderResolutionStatus>? providerStatuses,
    String? error,
    bool clearError = false,
  }) =>
      PrefetchSnapshot(
        key: key,
        query: query ?? this.query,
        isResolving: isResolving ?? this.isResolving,
        isProbing: isProbing ?? this.isProbing,
        isPaused: isPaused ?? this.isPaused,
        hasMoreProviders: hasMoreProviders ?? this.hasMoreProviders,
        hasAnyStreamAddon: hasAnyStreamAddon ?? this.hasAnyStreamAddon,
        rankedStreams: rankedStreams ?? this.rankedStreams,
        bestAutoPlayKey: clearBestAutoPlayKey
            ? null
            : (bestAutoPlayKey ?? this.bestAutoPlayKey),
        subtitles: subtitles ?? this.subtitles,
        providerStatuses: providerStatuses ?? this.providerStatuses,
        error: clearError ? null : (error ?? this.error),
        startedAtMs: startedAtMs,
      );

  @override
  List<Object?> get props => [
        key,
        query,
        isResolving,
        isProbing,
        isPaused,
        hasMoreProviders,
        hasAnyStreamAddon,
        rankedStreams,
        bestAutoPlayKey,
        subtitles,
        providerStatuses,
        error,
        startedAtMs,
      ];
}

class _PrefetchSession {
  _PrefetchSession({
    required this.key,
    required this.enrichedQuery,
    required this.startedAtMs,
  });

  final String key;
  StreamQuery enrichedQuery;
  final int startedAtMs;

  CancelToken? activeCancelToken;
  String? activeRequestId;
  StreamSubscription<Cs3StreamEvent>? cs3Sub;
  Timer? probeDebounce;
  Timer? uiFlushThrottle;

  final Set<String> seenKeys = <String>{};
  final List<String> displayOrderKeys = <String>[];
  final List<ResolvedStream> rawStreams = <ResolvedStream>[];
  final List<ResolvedSubtitle> rawSubtitles = <ResolvedSubtitle>[];
  final Map<String, ProviderResolutionStatus> statusById = {};
  final Set<String> completedStremioIds = <String>{};
  final Set<String> completedCs3Names = <String>{};

  int runGeneration = 0;
  bool paused = false;
  bool disposed = false;

  void stopActiveRun(CloudStreamEngine csEngine) {
    runGeneration++;
    probeDebounce?.cancel();
    probeDebounce = null;
    uiFlushThrottle?.cancel();
    uiFlushThrottle = null;
    activeCancelToken?.cancel('Prefetch paused or superseded');
    activeCancelToken = null;
    cs3Sub?.cancel();
    cs3Sub = null;
    final reqId = activeRequestId;
    activeRequestId = null;
    if (reqId != null) {
      csEngine.cancelStreamResolution(reqId);
    }
  }

  void dispose(CloudStreamEngine csEngine) {
    if (disposed) return;
    disposed = true;
    paused = true;
    stopActiveRun(csEngine);
  }
}

class StreamPrefetchController extends Notifier<Map<String, PrefetchSnapshot>> {
  static const int _maxEntries = 2;
  static const int _ttlMs = 10 * 60 * 1000;
  static const int _maxRawStreams = 60;
  static const int _maxRankedStreams = 35;

  final Map<String, _PrefetchSession> _sessions = {};
  final List<String> _lruOrder = [];
  int _counter = 0;
  bool _disposed = false;
  late CloudStreamEngine _csEngine;

  @override
  Map<String, PrefetchSnapshot> build() {
    _disposed = false;
    _csEngine = ref.read(cloudStreamEngineProvider);
    ref.onDispose(() {
      _disposed = true;
      for (final s in _sessions.values) {
        s.dispose(_csEngine);
      }
      _sessions.clear();
      _lruOrder.clear();
    });
    return const {};
  }

  PrefetchSnapshot? snapshotForKey(String key) {
    final hit = state[key];
    if (hit == null) return null;
    final age = DateTime.now().millisecondsSinceEpoch - hit.startedAtMs;
    if (age > _ttlMs && !hit.isResolving) return null;
    return hit;
  }

  void reRankAll() {
    if (_disposed || state.isEmpty) return;
    final nextMap = <String, PrefetchSnapshot>{};
    state.forEach((key, snap) {
      final session = _sessions[key];
      if (session == null) {
        nextMap[key] = snap;
      } else {
        final ordered = _buildStableDisplayList(session, snap.query.title);
        nextMap[key] = snap.copyWith(
          rankedStreams: ordered.displayList,
          bestAutoPlayKey: ordered.bestAutoPlayKey,
          clearBestAutoPlayKey: ordered.bestAutoPlayKey == null,
        );
      }
    });
    state = nextMap;
  }

  void markStreamFailed(String key, ResolvedStream stream) {
    if (_disposed) return;
    ref.read(hostReliabilityTrackerProvider).recordFailure(stream);
    final snap = state[key];
    final session = _sessions[key];
    if (snap == null || session == null) return;
    final ordered = _buildStableDisplayList(session, snap.query.title);
    state = {
      ...state,
      key: snap.copyWith(
        rankedStreams: ordered.displayList,
        bestAutoPlayKey: ordered.bestAutoPlayKey,
        clearBestAutoPlayKey: ordered.bestAutoPlayKey == null,
      ),
    };
  }

  /// Permanently removes a stream whose actual container/manifest runtime does
  /// not match TMDB's runtime so it disappears from the Links list immediately.
  void markStreamRuntimeMismatch(String key, ResolvedStream stream) {
    if (_disposed) return;
    ref.read(hostReliabilityTrackerProvider).recordRuntimeMismatch(stream);
    final snap = state[key];
    final session = _sessions[key];
    if (snap == null || session == null) return;
    session.rawStreams.removeWhere((s) => s.dedupKey == stream.dedupKey);
    session.displayOrderKeys.remove(stream.dedupKey);
    final ordered = _buildStableDisplayList(session, snap.query.title);
    state = {
      ...state,
      key: snap.copyWith(
        rankedStreams: ordered.displayList,
        bestAutoPlayKey: ordered.bestAutoPlayKey,
        clearBestAutoPlayKey: ordered.bestAutoPlayKey == null,
      ),
    };
  }

  /// Pauses active background scraping & speed probing for [key] while keeping
  /// every already-discovered stream & subtitle ready in memory.
  /// Call this once video playback stabilizes so zero RAM/CPU/bandwidth is
  /// wasted while the user is watching.
  void pausePrefetch(String key) {
    if (_disposed) return;
    final session = _sessions[key];
    if (session == null) return;
    if (session.paused && session.activeCancelToken == null) return;
    session.paused = true;
    session.stopActiveRun(_csEngine);

    final snap = state[key];
    if (snap != null) {
      final hasRemaining = _hasRemainingProviders(session);
      _putSnap(
        snap.copyWith(
          isResolving: false,
          isProbing: false,
          isPaused: true,
          hasMoreProviders: hasRemaining,
        ),
      );
    }
  }

  /// Pauses all active sessions except [keepKey] to avoid multiple titles
  /// scraping concurrently on memory-constrained phones.
  void pauseOtherKeys(String keepKey) {
    if (_disposed) return;
    for (final k in _sessions.keys.toList()) {
      if (k != keepKey) {
        pausePrefetch(k);
      }
    }
  }

  /// Resumes scraping ONLY the remaining unfinished providers for [key].
  /// When [skipProbe] is true (e.g. while video is already playing smoothly),
  /// network speed probing is skipped so playback stays completely stutter-free.
  Future<void> resumePrefetch(String key, {bool skipProbe = false}) async {
    if (_disposed) return;
    final session = _sessions[key];
    final snap = state[key];
    if (session == null || snap == null) return;
    if (snap.isResolving) return;
    if (!snap.hasMoreProviders && snap.rankedStreams.isNotEmpty) return;

    session.paused = false;
    await _runProviders(session, skipCompleted: true, skipProbe: skipProbe);
  }

  void cancelKey(String key) {
    if (_disposed) return;
    final session = _sessions.remove(key);
    session?.dispose(_csEngine);
    _lruOrder.remove(key);
    if (state.containsKey(key)) {
      final next = {...state}..remove(key);
      state = next;
    }
  }

  Future<void> prefetch(StreamQuery rawQuery, {bool forceRefresh = false}) async {
    if (_disposed) return;
    final key = prefetchKeyForQuery(rawQuery);
    final existingSnap = state[key];
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (!forceRefresh && existingSnap != null) {
      final fresh = nowMs - existingSnap.startedAtMs < _ttlMs;
      if (existingSnap.isResolving ||
          (fresh && existingSnap.rankedStreams.isNotEmpty)) {
        _touchLru(key);
        return;
      }
    }

    // Pause any other running title before starting a new scrape.
    pauseOtherKeys(key);

    // Evict expired or excess LRU entries (max 2 cached keys).
    _sessions.remove(key)?.dispose(_csEngine);
    _touchLru(key);
    while (_lruOrder.length > _maxEntries) {
      final oldest = _lruOrder.removeAt(0);
      _sessions.remove(oldest)?.dispose(_csEngine);
      if (state.containsKey(oldest)) {
        final next = {...state}..remove(oldest);
        state = next;
      }
    }

    final prefs =
        ref.read(playbackPreferencesControllerProvider).valueOrNull ??
            const PlaybackPreferences();
    final queryWithPrefs = rawQuery.preferredLanguages.isNotEmpty
        ? rawQuery
        : rawQuery.copyWith(preferredLanguages: prefs.preferredLanguagePair);

    final session = _PrefetchSession(
      key: key,
      enrichedQuery: queryWithPrefs,
      startedAtMs: nowMs,
    );
    _sessions[key] = session;

    _putSnap(
      PrefetchSnapshot(
        key: key,
        query: queryWithPrefs,
        isResolving: true,
        startedAtMs: nowMs,
      ),
    );

    final enriched = await _enrichQueryIds(queryWithPrefs);
    if (_disposed || session.disposed || session.paused) return;
    session.enrichedQuery = enriched;

    await _runProviders(session, skipCompleted: false);
  }

  bool _hasRemainingProviders(_PrefetchSession session) {
    final store = ref.read(addonsControllerProvider).valueOrNull ??
        const AddonsStoreState();
    final candidateIds = _buildCandidateStremioIds(session.enrichedQuery);
    for (final addon in store.stremioAddons) {
      if (!addon.enabled) continue;
      if (session.completedStremioIds.contains(addon.id)) continue;
      for (final cid in candidateIds) {
        if (addon.manifest.supportsResource(
          'stream',
          type: session.enrichedQuery.mediaType,
          id: cid,
        )) {
          return true;
        }
      }
    }
    for (final plugin in store.installedCs3Plugins) {
      if (!plugin.enabled || plugin.loadStatus != Cs3LoadStatus.loaded) {
        continue;
      }
      final names = plugin.registeredProviderNames.isNotEmpty
          ? plugin.registeredProviderNames
          : [plugin.name];
      for (final n in names) {
        if (!session.completedCs3Names.contains(n.trim().toLowerCase())) {
          return true;
        }
      }
    }
    return false;
  }

  Future<void> _runProviders(
    _PrefetchSession session, {
    required bool skipCompleted,
    bool skipProbe = false,
  }) async {
    if (_disposed || session.disposed || session.paused) return;

    session.stopActiveRun(_csEngine);
    final runGen = session.runGeneration;
    final token = CancelToken();
    final requestId =
        'pf_${DateTime.now().millisecondsSinceEpoch}_${++_counter}';
    session.activeCancelToken = token;
    session.activeRequestId = requestId;

    final enriched = session.enrichedQuery;
    final key = session.key;
    final store = ref.read(addonsControllerProvider).valueOrNull ??
        const AddonsStoreState();
    final stremioService = ref.read(stremioAddonServiceProvider);
    final candidateIds = _buildCandidateStremioIds(enriched);

    final streamAddons = <({InstalledStremioAddon addon, String videoId})>[];
    final subtitleAddons = <({InstalledStremioAddon addon, String videoId})>[];

    for (final addon in store.stremioAddons) {
      if (!addon.enabled) continue;
      if (!skipCompleted || !session.completedStremioIds.contains(addon.id)) {
        for (final cid in candidateIds) {
          if (addon.manifest.supportsResource(
            'stream',
            type: enriched.mediaType,
            id: cid,
          )) {
            streamAddons.add((addon: addon, videoId: cid));
            break;
          }
        }
      }
      if (!skipCompleted) {
        for (final cid in candidateIds) {
          if (addon.manifest.supportsResource(
            'subtitles',
            type: enriched.mediaType,
            id: cid,
          )) {
            subtitleAddons.add((addon: addon, videoId: cid));
            break;
          }
        }
      }
    }

    final enabledCs3Plugins = store.installedCs3Plugins
        .where((p) => p.enabled && p.loadStatus == Cs3LoadStatus.loaded)
        .toList();

    final hasRemainingCs3 = enabledCs3Plugins.any((p) {
      if (!skipCompleted) return true;
      final names = p.registeredProviderNames.isNotEmpty
          ? p.registeredProviderNames
          : [p.name];
      return names.any(
        (n) => !session.completedCs3Names.contains(n.trim().toLowerCase()),
      );
    });

    for (final entry in streamAddons) {
      final sid = 'stremio:${entry.addon.id}';
      session.statusById[sid] = ProviderResolutionStatus(
        sourceId: sid,
        sourceName: entry.addon.manifest.name,
        architecture: AddonArchitecture.stremio,
        state: ProviderStatusKind.loading,
      );
    }
    if (!skipCompleted) {
      for (final plugin in enabledCs3Plugins) {
        final cid = 'cs3:${plugin.uid}';
        session.statusById[cid] = ProviderResolutionStatus(
          sourceId: cid,
          sourceName: plugin.name,
          architecture: AddonArchitecture.cloudstream,
          state: ProviderStatusKind.loading,
        );
      }
    }

    final hasAnyAddon =
        streamAddons.isNotEmpty || enabledCs3Plugins.isNotEmpty;
    if (!hasAnyAddon && subtitleAddons.isEmpty) {
      _putSnap(
        PrefetchSnapshot(
          key: key,
          query: enriched,
          isResolving: false,
          isPaused: false,
          hasMoreProviders: false,
          hasAnyStreamAddon: false,
          startedAtMs: session.startedAtMs,
        ),
      );
      return;
    }

    if (streamAddons.isEmpty && !hasRemainingCs3 && subtitleAddons.isEmpty) {
      final cur = state[key];
      if (cur != null) {
        _putSnap(
          cur.copyWith(
            isResolving: false,
            isProbing: false,
            isPaused: false,
            hasMoreProviders: false,
          ),
        );
      }
      return;
    }

    final baseSnap = state[key] ??
        PrefetchSnapshot(
          key: key,
          query: enriched,
          startedAtMs: session.startedAtMs,
        );
    _putSnap(
      baseSnap.copyWith(
        query: enriched,
        isResolving: true,
        isPaused: false,
        hasMoreProviders: true,
        hasAnyStreamAddon: true,
        providerStatuses: session.statusById.values.toList(growable: false),
      ),
    );

    bool isRunActive() =>
        !_disposed &&
        !session.disposed &&
        !session.paused &&
        session.runGeneration == runGen &&
        !token.isCancelled;

    void emitSnapshotNow({bool scheduleProbe = false}) {
      if (!isRunActive()) return;
      final ordered = _buildStableDisplayList(session, enriched.title);
      final current = state[key];
      if (current == null) return;
      _putSnap(
        current.copyWith(
          rankedStreams: ordered.displayList,
          bestAutoPlayKey: ordered.bestAutoPlayKey,
          clearBestAutoPlayKey: ordered.bestAutoPlayKey == null,
          subtitles: List<ResolvedSubtitle>.unmodifiable(session.rawSubtitles),
          providerStatuses: session.statusById.values.toList(growable: false),
        ),
      );
      if (!skipProbe && scheduleProbe && ordered.displayList.isNotEmpty) {
        session.probeDebounce?.cancel();
        session.probeDebounce = Timer(const Duration(milliseconds: 350), () {
          if (isRunActive()) {
            unawaited(_runProbe(session, enriched, runGen, token));
          }
        });
      }
    }

    void flush({bool scheduleProbe = false}) {
      if (!isRunActive()) return;
      // Emit immediately for the very first batch so playback starts fast;
      // throttle subsequent updates to 650ms so Links scrolling stays at 60fps.
      if (session.displayOrderKeys.isEmpty) {
        emitSnapshotNow(scheduleProbe: scheduleProbe);
        return;
      }
      session.uiFlushThrottle ??= Timer(const Duration(milliseconds: 650), () {
        session.uiFlushThrottle = null;
        emitSnapshotNow(scheduleProbe: scheduleProbe);
      });
    }

    void addStreams(List<ResolvedStream> incoming) {
      var changed = false;
      for (final s in incoming) {
        if (session.rawStreams.length >= _maxRawStreams) break;
        if (session.seenKeys.add(s.dedupKey)) {
          session.rawStreams.add(s);
          for (final sub in s.subtitles) {
            if (!session.rawSubtitles.any((x) => x.url == sub.url)) {
              session.rawSubtitles.add(sub);
            }
          }
          changed = true;
        }
      }
      if (changed) flush(scheduleProbe: true);
    }

    final tasks = <Future<void>>[];

    for (final entry in streamAddons) {
      final sid = 'stremio:${entry.addon.id}';
      tasks.add(() async {
        final sw = Stopwatch()..start();
        try {
          final streams = await stremioService.fetchStreams(
            entry.addon,
            enriched.mediaType,
            entry.videoId,
            cancelToken: token,
          );
          if (!isRunActive()) return;
          sw.stop();
          session.completedStremioIds.add(entry.addon.id);
          addStreams(streams);
          session.statusById[sid] = session.statusById[sid]!.copyWith(
            state: streams.isEmpty
                ? ProviderStatusKind.empty
                : ProviderStatusKind.done,
            streamCount: streams.length,
            elapsedMs: sw.elapsedMilliseconds,
          );
          flush();
        } catch (e) {
          if (!isRunActive() ||
              (e is DioException && CancelToken.isCancel(e))) {
            return;
          }
          sw.stop();
          session.completedStremioIds.add(entry.addon.id);
          session.statusById[sid] = session.statusById[sid]!.copyWith(
            state: ProviderStatusKind.error,
            errorMessage: e.toString().replaceFirst('Exception: ', ''),
            elapsedMs: sw.elapsedMilliseconds,
          );
          flush();
        }
      }());
    }

    for (final entry in subtitleAddons) {
      tasks.add(() async {
        try {
          final subs = await stremioService.fetchSubtitles(
            entry.addon,
            enriched.mediaType,
            entry.videoId,
            cancelToken: token,
          );
          if (!isRunActive() || subs.isEmpty) return;
          var changed = false;
          for (final sub in subs) {
            if (!session.rawSubtitles.any((x) => x.url == sub.url)) {
              session.rawSubtitles.add(sub);
              changed = true;
            }
          }
          if (changed) flush();
        } catch (_) {}
      }());
    }

    if (hasRemainingCs3) {
      final csCompleter = Completer<void>();
      final csQuery = skipCompleted && session.completedCs3Names.isNotEmpty
          ? enriched.copyWith(
              skipProviders: session.completedCs3Names.toList(growable: false),
            )
          : enriched;
      session.cs3Sub = _csEngine
          .resolveStreams(requestId: requestId, query: csQuery)
          .listen(
        (event) {
          if (!isRunActive()) return;
          switch (event) {
            case Cs3StreamLinkEvent(:final stream):
              addStreams([stream]);
            case Cs3SubtitleEvent(:final subtitle):
              if (!session.rawSubtitles.any((x) => x.url == subtitle.url)) {
                session.rawSubtitles.add(subtitle);
                flush();
              }
            case Cs3ProviderDoneEvent(
                :final providerName,
                :final streamCount,
                :final elapsedMs,
              ):
              session.completedCs3Names.add(providerName.trim().toLowerCase());
              final matchKey =
                  _findCs3StatusKey(session.statusById, providerName);
              session.statusById[matchKey] = ProviderResolutionStatus(
                sourceId: matchKey,
                sourceName: providerName,
                architecture: AddonArchitecture.cloudstream,
                state: streamCount == 0
                    ? ProviderStatusKind.empty
                    : ProviderStatusKind.done,
                streamCount: streamCount,
                elapsedMs: elapsedMs,
              );
              flush();
            case Cs3ProviderErrorEvent(
                :final providerName,
                :final error,
                :final elapsedMs,
              ):
              session.completedCs3Names.add(providerName.trim().toLowerCase());
              final matchKey =
                  _findCs3StatusKey(session.statusById, providerName);
              session.statusById[matchKey] = ProviderResolutionStatus(
                sourceId: matchKey,
                sourceName: providerName,
                architecture: AddonArchitecture.cloudstream,
                state: ProviderStatusKind.error,
                errorMessage: error,
                elapsedMs: elapsedMs,
              );
              flush();
            case Cs3ResolutionCompleteEvent():
              if (!csCompleter.isCompleted) csCompleter.complete();
          }
        },
        onError: (_) {
          if (!csCompleter.isCompleted) csCompleter.complete();
        },
        onDone: () {
          if (!csCompleter.isCompleted) csCompleter.complete();
        },
      );
      tasks.add(csCompleter.future);
    }

    await Future.wait(tasks);
    if (!isRunActive()) return;

    session.probeDebounce?.cancel();
    session.uiFlushThrottle?.cancel();
    session.uiFlushThrottle = null;
    for (final sid in session.statusById.keys.toList()) {
      if (session.statusById[sid]!.state == ProviderStatusKind.loading) {
        session.statusById[sid] = session.statusById[sid]!.copyWith(
          state: ProviderStatusKind.empty,
        );
      }
    }

    final finalOrdered = _buildStableDisplayList(session, enriched.title);
    final current = state[key];
    if (current != null) {
      _putSnap(
        current.copyWith(
          isResolving: false,
          isPaused: false,
          hasMoreProviders: false,
          rankedStreams: finalOrdered.displayList,
          bestAutoPlayKey: finalOrdered.bestAutoPlayKey,
          clearBestAutoPlayKey: finalOrdered.bestAutoPlayKey == null,
          subtitles: List<ResolvedSubtitle>.unmodifiable(session.rawSubtitles),
          providerStatuses: session.statusById.values.toList(growable: false),
        ),
      );
    }

    if (!skipProbe && finalOrdered.displayList.isNotEmpty) {
      await _runProbe(session, enriched, runGen, token);
    }
  }

  Future<void> _runProbe(
    _PrefetchSession session,
    StreamQuery enriched,
    int runGen,
    CancelToken token,
  ) async {
    if (_disposed ||
        session.disposed ||
        session.paused ||
        session.runGeneration != runGen ||
        token.isCancelled) {
      return;
    }
    final snap = state[session.key];
    if (snap == null) return;
    final preRanked = _rank(session.rawStreams, enriched.title);
    if (preRanked.isEmpty) return;

    final preOrdered = _buildStableDisplayList(session, enriched.title);
    _putSnap(
      snap.copyWith(
        isProbing: true,
        rankedStreams: preOrdered.displayList,
        bestAutoPlayKey: preOrdered.bestAutoPlayKey,
        clearBestAutoPlayKey: preOrdered.bestAutoPlayKey == null,
      ),
    );
    await ref.read(streamSpeedProberProvider).probeTopCandidates(
          preRanked,
          maxProbes: 3,
          expectedRuntimeMinutes: enriched.expectedRuntimeMinutes,
          cancelToken: token,
        );
    if (_disposed ||
        session.disposed ||
        session.paused ||
        session.runGeneration != runGen ||
        token.isCancelled) {
      return;
    }
    final postOrdered = _buildStableDisplayList(session, enriched.title);
    final latest = state[session.key];
    if (latest == null) return;
    _putSnap(
      latest.copyWith(
        isProbing: false,
        rankedStreams: postOrdered.displayList,
        bestAutoPlayKey: postOrdered.bestAutoPlayKey,
        clearBestAutoPlayKey: postOrdered.bestAutoPlayKey == null,
      ),
    );
  }

  /// Preserves sequential arrival order for every stream already displayed
  /// (so links NEVER shuffle or jump around while loading or when reopening the
  /// Links modal), while computing [bestAutoPlayKey] using full [StreamRanker]
  /// scoring for smart initial auto-play.
  ({List<RankedStream> displayList, String? bestAutoPlayKey})
      _buildStableDisplayList(_PrefetchSession session, String? mediaTitle) {
    final ranked = _rank(session.rawStreams, mediaTitle);
    String? bestKey;
    for (final r in ranked) {
      if (r.isAutoPlayEligible) {
        bestKey = r.dedupKey;
        break;
      }
    }

    final byKey = <String, RankedStream>{
      for (final r in ranked) r.dedupKey: r,
    };

    // Prune any keys removed by runtime mismatch filtering.
    session.displayOrderKeys.removeWhere((k) => !byKey.containsKey(k));
    final known = session.displayOrderKeys.toSet();

    // Append newly discovered links sequentially at the bottom (ranked within
    // their arrival batch so each new batch is tidy without disturbing rows above).
    for (final r in ranked) {
      if (known.add(r.dedupKey)) {
        session.displayOrderKeys.add(r.dedupKey);
      }
    }

    final displayList = <RankedStream>[
      for (final k in session.displayOrderKeys)
        if (byKey[k] case final item?) item,
    ];

    return (
      displayList: displayList.length <= _maxRankedStreams
          ? displayList
          : displayList.sublist(0, _maxRankedStreams),
      bestAutoPlayKey: bestKey,
    );
  }

  List<RankedStream> _rank(List<ResolvedStream> raw, String? mediaTitle) {
    final prefs =
        ref.read(playbackPreferencesControllerProvider).valueOrNull ??
            const PlaybackPreferences();
    final prober = ref.read(streamSpeedProberProvider);
    final tracker = ref.read(hostReliabilityTrackerProvider);
    final ranked = StreamRanker.rank(
      streams: raw,
      prefs: prefs,
      displayProfile: DeviceDisplayProfile.current(),
      probeCache: prober.snapshotCache,
      reliabilityTracker: tracker,
      mediaTitle: mediaTitle,
    );
    if (ranked.length <= _maxRankedStreams) return ranked;
    return ranked.sublist(0, _maxRankedStreams);
  }

  void _touchLru(String key) {
    _lruOrder.remove(key);
    _lruOrder.add(key);
  }

  void _putSnap(PrefetchSnapshot snap) {
    if (_disposed) return;
    state = {...state, snap.key: snap};
  }

  Future<StreamQuery> _enrichQueryIds(StreamQuery q) async {
    final animeMap = ref.read(animeIdMapProvider);
    await animeMap.ensureLoaded();

    var imdbId = q.imdbId;
    var tmdbId = q.tmdbId;
    var anilistId = q.anilistId;
    if (anilistId == null &&
        q.rawMetaId != null &&
        q.rawMetaId!.startsWith('anilist:')) {
      anilistId = int.tryParse(q.rawMetaId!.substring('anilist:'.length));
    }
    var isAnime = q.isAnime;

    if (anilistId != null) {
      final ids = animeMap.lookupByAnilistId(anilistId);
      if (ids != null) {
        imdbId ??= ids.imdbId;
        tmdbId ??= ids.tmdbId;
        isAnime = true;
      }
    } else if (imdbId != null || tmdbId != null) {
      int? mappedAnilist;
      if (imdbId != null && imdbId.isNotEmpty) {
        mappedAnilist = animeMap.lookupAnilistIdByImdb(imdbId);
      }
      if (mappedAnilist == null && tmdbId != null && tmdbId > 0) {
        mappedAnilist = animeMap.lookupAnilistIdByTmdb(
          tmdbId: tmdbId,
          type: q.mediaType,
        );
      }
      if (mappedAnilist != null) {
        anilistId = mappedAnilist;
        isAnime = true;
      }
    }

    return q.copyWith(
      imdbId: imdbId,
      tmdbId: tmdbId,
      anilistId: anilistId,
      isAnime: isAnime,
    );
  }

  List<String> _buildCandidateStremioIds(StreamQuery q) {
    final ids = <String>[];
    final s = q.season ?? 1;
    final e = q.episode ?? 1;

    if (q.imdbId != null && q.imdbId!.isNotEmpty) {
      ids.add(q.mediaType == 'series' ? '${q.imdbId}:$s:$e' : q.imdbId!);
    }
    if (q.kitsuId != null) {
      ids.add(q.mediaType == 'series' ? 'kitsu:${q.kitsuId}:$e' : 'kitsu:${q.kitsuId}');
    }
    if (q.tmdbId != null) {
      ids.add(q.mediaType == 'series' ? 'tmdb:${q.tmdbId}:$s:$e' : 'tmdb:${q.tmdbId}');
    }
    if (q.rawMetaId != null &&
        q.rawMetaId!.isNotEmpty &&
        !ids.contains(q.rawMetaId)) {
      ids.add(
        q.mediaType == 'series' && !q.rawMetaId!.contains(':') && q.season != null
            ? '${q.rawMetaId}:$s:$e'
            : q.rawMetaId!,
      );
    }
    return ids;
  }

  String _findCs3StatusKey(
    Map<String, ProviderResolutionStatus> statusById,
    String providerName,
  ) {
    final exact = statusById.entries.where((e) =>
        e.key.startsWith('cs3:') &&
        e.value.sourceName.toLowerCase() == providerName.toLowerCase());
    if (exact.isNotEmpty) return exact.first.key;
    final partial = statusById.entries.where((e) =>
        e.key.startsWith('cs3:') &&
        (e.value.sourceName.toLowerCase().contains(providerName.toLowerCase()) ||
            providerName.toLowerCase().contains(e.value.sourceName.toLowerCase())));
    if (partial.isNotEmpty) return partial.first.key;
    return 'cs3:$providerName';
  }
}

final streamPrefetchControllerProvider =
    NotifierProvider<StreamPrefetchController, Map<String, PrefetchSnapshot>>(
  StreamPrefetchController.new,
);
