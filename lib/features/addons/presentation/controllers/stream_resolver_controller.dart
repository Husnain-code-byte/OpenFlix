import 'dart:async';

import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../anime/data/anime_id_map.dart';
import '../../data/cloudstream_bridge_client.dart';
import '../../data/stremio_addon_service.dart';
import '../../domain/models/addon_models.dart';
import '../../domain/models/stream_models.dart';
import 'addons_controller.dart';

class StreamResolverState extends Equatable {
  const StreamResolverState({
    this.isResolving = false,
    this.query,
    this.streams = const [],
    this.subtitles = const [],
    this.providerStatuses = const [],
    this.error,
  });

  final bool isResolving;
  final StreamQuery? query;
  final List<ResolvedStream> streams;
  final List<ResolvedSubtitle> subtitles;
  final List<ProviderResolutionStatus> providerStatuses;
  final String? error;

  StreamResolverState copyWith({
    bool? isResolving,
    StreamQuery? query,
    List<ResolvedStream>? streams,
    List<ResolvedSubtitle>? subtitles,
    List<ProviderResolutionStatus>? providerStatuses,
    String? error,
    bool clearError = false,
  }) =>
      StreamResolverState(
        isResolving: isResolving ?? this.isResolving,
        query: query ?? this.query,
        streams: streams ?? this.streams,
        subtitles: subtitles ?? this.subtitles,
        providerStatuses: providerStatuses ?? this.providerStatuses,
        error: clearError ? null : (error ?? this.error),
      );

  @override
  List<Object?> get props => [
        isResolving,
        query,
        streams,
        subtitles,
        providerStatuses,
        error,
      ];
}

class StreamResolverController extends Notifier<StreamResolverState> {
  int _generation = 0;
  String? _activeRequestId;
  CancelToken? _cancelToken;
  StreamSubscription<Cs3StreamEvent>? _cs3Sub;
  bool _disposed = false;

  @override
  StreamResolverState build() {
    _disposed = false;
    ref.onDispose(() {
      _disposed = true;
      cancel(notify: false);
    });
    return const StreamResolverState();
  }

  void cancel({bool notify = true}) {
    _generation++;
    _cancelToken?.cancel('Stream resolution cancelled');
    _cancelToken = null;
    _cs3Sub?.cancel();
    _cs3Sub = null;
    final reqId = _activeRequestId;
    _activeRequestId = null;
    if (reqId != null && !_disposed) {
      try {
        ref.read(cloudStreamEngineProvider).cancelStreamResolution(reqId);
      } catch (_) {}
    }
    if (notify && !_disposed && state.isResolving) {
      state = state.copyWith(isResolving: false);
    }
  }

  Future<void> resolve(StreamQuery rawQuery) async {
    cancel();
    final gen = ++_generation;
    final requestId = 'req_${DateTime.now().microsecondsSinceEpoch}_$gen';
    _activeRequestId = requestId;
    final token = CancelToken();
    _cancelToken = token;

    // 1. Enrich IDs via bundled AnimeIdMap (anilist <-> imdb <-> tmdb) when applicable
    final enrichedQuery = await _enrichQueryIds(rawQuery);
    if (gen != _generation || token.isCancelled) return;

    final store =
        ref.read(addonsControllerProvider).valueOrNull ?? const AddonsStoreState();
    final stremioService = ref.read(stremioAddonServiceProvider);
    final csEngine = ref.read(cloudStreamEngineProvider);

    final candidateIds = _buildCandidateStremioIds(enrichedQuery);

    // Filter Stremio addons that expose `stream` for any candidate ID
    final streamAddons = <({InstalledStremioAddon addon, String videoId})>[];
    final subtitleAddons = <({InstalledStremioAddon addon, String videoId})>[];

    for (final addon in store.stremioAddons) {
      if (!addon.enabled) continue;
      for (final cid in candidateIds) {
        if (addon.manifest.supportsResource(
          'stream',
          type: enrichedQuery.mediaType,
          id: cid,
        )) {
          streamAddons.add((addon: addon, videoId: cid));
          break;
        }
      }
      for (final cid in candidateIds) {
        if (addon.manifest.supportsResource(
          'subtitles',
          type: enrichedQuery.mediaType,
          id: cid,
        )) {
          subtitleAddons.add((addon: addon, videoId: cid));
          break;
        }
      }
    }

    final enabledCs3Plugins = store.installedCs3Plugins
        .where((p) => p.enabled && p.loadStatus == Cs3LoadStatus.loaded)
        .toList();

    final initialStatuses = <ProviderResolutionStatus>[
      for (final entry in streamAddons)
        ProviderResolutionStatus(
          sourceId: 'stremio:${entry.addon.id}',
          sourceName: entry.addon.manifest.name,
          architecture: AddonArchitecture.stremio,
          state: ProviderStatusKind.loading,
        ),
      for (final plugin in enabledCs3Plugins)
        ProviderResolutionStatus(
          sourceId: 'cs3:${plugin.uid}',
          sourceName: plugin.name,
          architecture: AddonArchitecture.cloudstream,
          state: ProviderStatusKind.loading,
        ),
    ];

    state = StreamResolverState(
      isResolving: initialStatuses.isNotEmpty,
      query: enrichedQuery,
      streams: const [],
      subtitles: const [],
      providerStatuses: initialStatuses,
    );

    if (initialStatuses.isEmpty && subtitleAddons.isEmpty) {
      return;
    }

    final seenKeys = <String>{};
    final collectedStreams = <ResolvedStream>[];
    final collectedSubs = <ResolvedSubtitle>[];
    final statusById = {
      for (final s in initialStatuses) s.sourceId: s,
    };

    void flush() {
      if (gen != _generation) return;
      final sortedStreams = [...collectedStreams]..sort(_compareStreams);
      state = state.copyWith(
        streams: sortedStreams,
        subtitles: List<ResolvedSubtitle>.unmodifiable(collectedSubs),
        providerStatuses: statusById.values.toList(),
      );
    }

    void addStreams(List<ResolvedStream> incoming) {
      var changed = false;
      for (final s in incoming) {
        if (seenKeys.add(s.dedupKey)) {
          collectedStreams.add(s);
          for (final sub in s.subtitles) {
            if (!collectedSubs.any((x) => x.url == sub.url)) {
              collectedSubs.add(sub);
            }
          }
          changed = true;
        }
      }
      if (changed) flush();
    }

    final tasks = <Future<void>>[];

    // 2. Stremio stream addons in parallel
    for (final entry in streamAddons) {
      final sid = 'stremio:${entry.addon.id}';
      tasks.add(() async {
        final sw = Stopwatch()..start();
        try {
          final streams = await stremioService.fetchStreams(
            entry.addon,
            enrichedQuery.mediaType,
            entry.videoId,
            cancelToken: token,
          );
          if (gen != _generation) return;
          sw.stop();
          addStreams(streams);
          statusById[sid] = statusById[sid]!.copyWith(
            state: streams.isEmpty
                ? ProviderStatusKind.empty
                : ProviderStatusKind.done,
            streamCount: streams.length,
            elapsedMs: sw.elapsedMilliseconds,
          );
          flush();
        } catch (e) {
          if (gen != _generation || (e is DioException && CancelToken.isCancel(e))) {
            return;
          }
          sw.stop();
          statusById[sid] = statusById[sid]!.copyWith(
            state: ProviderStatusKind.error,
            errorMessage: e.toString().replaceFirst('Exception: ', ''),
            elapsedMs: sw.elapsedMilliseconds,
          );
          flush();
        }
      }());
    }

    // 3. Stremio subtitle addons in parallel
    for (final entry in subtitleAddons) {
      tasks.add(() async {
        try {
          final subs = await stremioService.fetchSubtitles(
            entry.addon,
            enrichedQuery.mediaType,
            entry.videoId,
            cancelToken: token,
          );
          if (gen != _generation || subs.isEmpty) return;
          var changed = false;
          for (final sub in subs) {
            if (!collectedSubs.any((x) => x.url == sub.url)) {
              collectedSubs.add(sub);
              changed = true;
            }
          }
          if (changed) flush();
        } catch (_) {}
      }());
    }

    // 4. Native Android CloudStream .cs3 providers via EventChannel
    if (enabledCs3Plugins.isNotEmpty) {
      final csCompleter = Completer<void>();
      _cs3Sub = csEngine
          .resolveStreams(requestId: requestId, query: enrichedQuery)
          .listen(
        (event) {
          if (gen != _generation) return;
          switch (event) {
            case Cs3StreamLinkEvent(:final stream):
              addStreams([stream]);
            case Cs3SubtitleEvent(:final subtitle):
              if (!collectedSubs.any((x) => x.url == subtitle.url)) {
                collectedSubs.add(subtitle);
                flush();
              }
            case Cs3ProviderDoneEvent(
                :final providerName,
                :final streamCount,
                :final elapsedMs,
              ):
              final matchKey = _findCs3StatusKey(statusById, providerName);
              statusById[matchKey] = ProviderResolutionStatus(
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
              final matchKey = _findCs3StatusKey(statusById, providerName);
              statusById[matchKey] = ProviderResolutionStatus(
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
    if (gen != _generation) return;

    // Mark any leftover pending CS3 plugin statuses done if provider did not fire individually.
    for (final key in statusById.keys.toList()) {
      if (statusById[key]!.state == ProviderStatusKind.loading) {
        statusById[key] = statusById[key]!.copyWith(
          state: ProviderStatusKind.empty,
        );
      }
    }
    state = state.copyWith(
      isResolving: false,
      streams: [...collectedStreams]..sort(_compareStreams),
      subtitles: List<ResolvedSubtitle>.unmodifiable(collectedSubs),
      providerStatuses: statusById.values.toList(),
    );
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
      ids.add(
        q.mediaType == 'series' ? '${q.imdbId}:$s:$e' : q.imdbId!,
      );
    }
    if (q.kitsuId != null) {
      ids.add(
        q.mediaType == 'series'
            ? 'kitsu:${q.kitsuId}:$e'
            : 'kitsu:${q.kitsuId}',
      );
    }
    if (q.tmdbId != null) {
      ids.add(
        q.mediaType == 'series' ? 'tmdb:${q.tmdbId}:$s:$e' : 'tmdb:${q.tmdbId}',
      );
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

  static int _compareStreams(ResolvedStream a, ResolvedStream b) {
    final directDiff =
        (b.transport.isPlayableDirect ? 1 : 0) - (a.transport.isPlayableDirect ? 1 : 0);
    if (directDiff != 0) return directDiff;
    final qDiff = b.qualityRank.compareTo(a.qualityRank);
    if (qDiff != 0) return qDiff;
    return a.providerName.compareTo(b.providerName);
  }
}

final streamResolverProvider =
    NotifierProvider<StreamResolverController, StreamResolverState>(
  StreamResolverController.new,
);
