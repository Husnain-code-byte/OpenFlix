import 'dart:async';

import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../details/data/tmdb_repository.dart';
import '../../../home/presentation/controllers/home_controller.dart';
import '../../data/personalization_repository.dart';
import '../../data/personalized_slots.dart';

class PersonalizedRowsState extends Equatable {
  const PersonalizedRowsState({
    this.rowsByBucket = const {},
  });

  final Map<PersonalizationBucket, PersonalizedRowData> rowsByBucket;

  /// Returns the ordered personalized rows for [filter] (only buckets that have
  /// a valid daily source and are either loading or have resolved items).
  List<PersonalizedRowData> rowsForFilter(HomeFilter filter) {
    final buckets = PersonalizedSlots.bucketsForFilter(filter);
    final out = <PersonalizedRowData>[];
    for (final b in buckets) {
      final row = rowsByBucket[b];
      if (row != null && (row.isLoading || row.items.isNotEmpty)) {
        out.add(row);
      }
    }
    return out;
  }

  PersonalizedRowsState copyWith({
    Map<PersonalizationBucket, PersonalizedRowData>? rowsByBucket,
  }) =>
      PersonalizedRowsState(
        rowsByBucket: rowsByBucket ?? this.rowsByBucket,
      );

  @override
  List<Object?> get props => [rowsByBucket];
}

class PersonalizedRowsController extends Notifier<PersonalizedRowsState> {
  late PersonalizationRepository _repo;
  late TmdbRepository _tmdbRepo;
  CancelToken? _cancelToken;
  Timer? _midnightTimer;
  int _generation = 0;
  String _loadedDayKey = PersonalizationRepository.todayKey();

  void _scheduleMidnightRefresh() {
    _midnightTimer?.cancel();
    final now = DateTime.now();
    final nextMidnight = DateTime(now.year, now.month, now.day + 1, 0, 0, 1);
    final wait = nextMidnight.difference(now);
    final clampedWait = wait.isNegative
        ? const Duration(milliseconds: 250)
        : (wait > const Duration(hours: 6) ? const Duration(hours: 6) : wait);
    final gen = _generation;
    _midnightTimer = Timer(clampedWait, () {
      if (gen != _generation) return;
      if (PersonalizationRepository.todayKey() != _loadedDayKey) {
        refreshIfDayChanged();
      } else {
        _scheduleMidnightRefresh();
      }
    });
  }

  Future<void> refreshIfDayChanged() async {
    final today = PersonalizationRepository.todayKey();
    if (today == _loadedDayKey) {
      _scheduleMidnightRefresh();
      return;
    }
    await loadAll();
  }

  @override
  PersonalizedRowsState build() {
    _repo = ref.watch(personalizationRepositoryProvider);
    _tmdbRepo = ref.watch(tmdbRepositoryProvider);

    void onInteractionsChanged() {
      unawaited(_reconcileInteractions());
    }

    _tmdbRepo.addMyListListener(onInteractionsChanged);
    ref.onDispose(() {
      _tmdbRepo.removeMyListListener(onInteractionsChanged);
      _generation++;
      _midnightTimer?.cancel();
      _cancelToken?.cancel('PersonalizedRowsController disposed');
    });

    Future.microtask(loadAll);
    return const PersonalizedRowsState();
  }

  /// Resolves all 6 daily personalization buckets (`likedMovie`, `myListMovie`,
  /// `likedSeries`, `myListSeries`, `likedAnime`, `myListAnime`).
  Future<void> loadAll() async {
    _cancelToken?.cancel('Superseded by new personalization load');
    final token = CancelToken();
    _cancelToken = token;
    final gen = ++_generation;
    _loadedDayKey = PersonalizationRepository.todayKey();
    _scheduleMidnightRefresh();

    try {
      await _repo.ensureReady(cancelToken: token);
      if (gen != _generation || token.isCancelled) return;

      await _resolveBuckets(
        PersonalizationBucket.values,
        token: token,
        gen: gen,
      );
    } catch (_) {}
  }

  /// Reconciles active rows when the user likes/unlikes or adds/removes from My List:
  /// - Existing valid daily sources stay locked for the rest of the day.
  /// - Buckets that transitioned `0 -> 1` fill in immediately.
  /// - Buckets whose active source was unliked or removed from My List re-pick immediately
  ///   (or disappear if 0 candidates remain).
  Future<void> _reconcileInteractions() async {
    final token = _cancelToken ??= CancelToken();
    final gen = _generation;

    final updatedMap = Map<PersonalizationBucket, PersonalizedRowData>.from(
      state.rowsByBucket,
    );
    final bucketsToResolve = <PersonalizationBucket>[];
    var mapChanged = false;

    for (final bucket in PersonalizationBucket.values) {
      final candidates = _repo.candidatesForBucket(bucket);
      final currentRow = updatedMap[bucket];

      if (candidates.isEmpty) {
        if (currentRow != null) {
          updatedMap.remove(bucket);
          unawaited(_repo.clearDailyRow(bucket));
          mapChanged = true;
        }
        continue;
      }

      if (currentRow == null) {
        // Bucket transitioned 0 -> 1 mid-day: resolve immediately.
        bucketsToResolve.add(bucket);
        continue;
      }

      final sourceStillValid = candidates.any(
        (m) => _repo.matchesCandidate(m, currentRow.sourceMeta),
      );
      if (!sourceStillValid) {
        // Active source was unliked or removed from My List: clear today's locked
        // snapshot and re-pick immediately.
        updatedMap.remove(bucket);
        unawaited(_repo.clearDailyRow(bucket));
        mapChanged = true;
        bucketsToResolve.add(bucket);
        continue;
      }

      // Filter out any newly disliked items from the existing row without shuffling.
      final filteredItems = currentRow.items
          .where((m) => !_tmdbRepo.isMetaDisliked(m))
          .toList(growable: false);
      if (filteredItems.length != currentRow.items.length) {
        if (filteredItems.isEmpty && !currentRow.isLoading) {
          updatedMap.remove(bucket);
          unawaited(_repo.clearDailyRow(bucket));
        } else {
          updatedMap[bucket] = currentRow.copyWith(items: filteredItems);
          unawaited(
            _repo.saveDailyRow(
              bucket,
              sourceMeta: currentRow.sourceMeta,
              items: filteredItems,
            ),
          );
        }
        mapChanged = true;
      }
    }

    if (mapChanged) {
      state = state.copyWith(rowsByBucket: Map.unmodifiable(updatedMap));
    }

    if (bucketsToResolve.isNotEmpty) {
      await _resolveBuckets(bucketsToResolve, token: token, gen: gen);
    }
  }

  Future<void> _resolveBuckets(
    List<PersonalizationBucket> buckets, {
    required CancelToken token,
    required int gen,
  }) async {
    // 1. Pick daily sources for the requested buckets, avoiding same-title
    // collision between paired Liked and My List buckets when >1 candidate exists.
    final pickedSources = <PersonalizationBucket, PersonalizedRowData>{};
    final snapshotsToStyleUpgrade = <PersonalizationBucket, PersonalizedRowData>{};
    final currentMap = Map<PersonalizationBucket, PersonalizedRowData>.from(
      state.rowsByBucket,
    );

    for (final bucket in buckets) {
      final candidates = _repo.candidatesForBucket(bucket);
      if (candidates.isEmpty) {
        currentMap.remove(bucket);
        continue;
      }

      // 0. Restore today's locked daily snapshot from disk immediately if the
      //    source is still in the user's Likes/My List. Never re-fetch or shuffle
      //    across app restarts until tomorrow's calendar date.
      final persisted = _repo.getPersistedDailyRow(bucket);
      if (persisted != null) {
        final sourceStillValid = candidates.any(
          (m) => _repo.matchesCandidate(m, persisted.sourceMeta),
        );
        if (sourceStillValid) {
          final filtered = persisted.items
              .where((m) => !_tmdbRepo.isMetaDisliked(m))
              .toList(growable: false);
          if (filtered.isNotEmpty) {
            final row = PersonalizedRowData(
              bucket: bucket,
              sourceMeta: persisted.sourceMeta,
              items: filtered,
              isLoading: false,
            );
            currentMap[bucket] = row;
            if (filtered.any((m) => !(m.poster?.contains('btttr.cc') ?? false))) {
              snapshotsToStyleUpgrade[bucket] = row;
            }
            continue;
          }
        } else {
          await _repo.clearDailyRow(bucket);
          if (gen != _generation || token.isCancelled) return;
        }
      }

      final pairedBucket = _pairedBucketFor(bucket);
      final avoidId = pickedSources[pairedBucket]?.sourceMeta.id ??
          currentMap[pairedBucket]?.sourceMeta.id;
      final source = await _repo.pickDailySource(
        bucket,
        avoidSourceId: avoidId,
      );
      if (gen != _generation || token.isCancelled) return;
      if (source != null) {
        final existing = currentMap[bucket];
        if (existing != null &&
            _repo.matchesCandidate(existing.sourceMeta, source) &&
            existing.items.isNotEmpty) {
          continue;
        }
        final placeholder = PersonalizedRowData(
          bucket: bucket,
          sourceMeta: source,
          items: const [],
          isLoading: true,
        );
        pickedSources[bucket] = placeholder;
        currentMap[bucket] = placeholder;
      } else {
        currentMap.remove(bucket);
      }
    }

    if (pickedSources.isEmpty) {
      state = state.copyWith(rowsByBucket: Map.unmodifiable(currentMap));
      if (snapshotsToStyleUpgrade.isNotEmpty) {
        unawaited(
          _upgradeSnapshotPosters(
            snapshotsToStyleUpgrade,
            token: token,
            gen: gen,
          ),
        );
      }
      return;
    }

    state = state.copyWith(rowsByBucket: Map.unmodifiable(currentMap));
    if (snapshotsToStyleUpgrade.isNotEmpty) {
      unawaited(
        _upgradeSnapshotPosters(
          snapshotsToStyleUpgrade,
          token: token,
          gen: gen,
        ),
      );
    }

    // Track seen IDs separately for Home/Movies/TV vs Anime so recommendations
    // never duplicate across the 4 Home rows or across the 2 Anime rows.
    final seenNonAnimeIds = <String>{
      for (final entry in currentMap.entries)
        if (!entry.key.isAnime && !pickedSources.containsKey(entry.key))
          for (final m in entry.value.items) m.id,
    };
    final seenAnimeIds = <String>{
      for (final entry in currentMap.entries)
        if (entry.key.isAnime && !pickedSources.containsKey(entry.key))
          for (final m in entry.value.items) m.id,
    };

    for (final entry in pickedSources.entries) {
      if (gen != _generation || token.isCancelled) return;
      final bucket = entry.key;
      final source = entry.value.sourceMeta;
      final seenSet = bucket.isAnime ? seenAnimeIds : seenNonAnimeIds;

      try {
        final items = await _repo.fetchRecommendationsForSource(
          bucket: bucket,
          sourceMeta: source,
          seenIds: seenSet,
          cancelToken: token,
          onWave1Ready: (wave1Items) {
            if (gen != _generation || token.isCancelled) return;
            final next = Map<PersonalizationBucket, PersonalizedRowData>.from(
              state.rowsByBucket,
            );
            next[bucket] = PersonalizedRowData(
              bucket: bucket,
              sourceMeta: source,
              items: wave1Items,
              isLoading: false,
            );
            state = state.copyWith(rowsByBucket: Map.unmodifiable(next));
          },
        );
        if (gen != _generation || token.isCancelled) return;

        final next = Map<PersonalizationBucket, PersonalizedRowData>.from(
          state.rowsByBucket,
        );
        if (items.isEmpty) {
          next.remove(bucket);
        } else {
          next[bucket] = PersonalizedRowData(
            bucket: bucket,
            sourceMeta: source,
            items: items,
            isLoading: false,
          );
          // Lock today's exact source + ordered items to disk so restarts never shuffle.
          await _repo.saveDailyRow(
            bucket,
            sourceMeta: source,
            items: items,
          );
        }
        state = state.copyWith(rowsByBucket: Map.unmodifiable(next));
      } catch (_) {
        if (gen != _generation || token.isCancelled) return;
        final next = Map<PersonalizationBucket, PersonalizedRowData>.from(
          state.rowsByBucket,
        )..remove(bucket);
        state = state.copyWith(rowsByBucket: Map.unmodifiable(next));
      }
    }
  }

  /// Upgrades poster URLs of previously persisted daily snapshots in place to
  /// Better Posters (`btttr.cc`) without changing the locked source or item order.
  Future<void> _upgradeSnapshotPosters(
    Map<PersonalizationBucket, PersonalizedRowData> rows, {
    required CancelToken token,
    required int gen,
  }) async {
    for (final entry in rows.entries) {
      if (gen != _generation || token.isCancelled) return;
      final bucket = entry.key;
      final row = entry.value;
      try {
        final styled = await _repo.ensureStyledPosters(
          row.items,
          cancelToken: token,
        );
        if (gen != _generation || token.isCancelled) return;
        var changed = false;
        for (var i = 0; i < styled.length && i < row.items.length; i++) {
          if (styled[i].poster != row.items[i].poster) {
            changed = true;
            break;
          }
        }
        if (!changed) continue;
        final next = Map<PersonalizationBucket, PersonalizedRowData>.from(
          state.rowsByBucket,
        );
        final current = next[bucket];
        if (current == null || current.sourceMeta.id != row.sourceMeta.id) {
          continue;
        }
        next[bucket] = current.copyWith(items: styled);
        state = state.copyWith(rowsByBucket: Map.unmodifiable(next));
        await _repo.saveDailyRow(
          bucket,
          sourceMeta: current.sourceMeta,
          items: styled,
        );
      } catch (_) {}
    }
  }

  static PersonalizationBucket _pairedBucketFor(PersonalizationBucket bucket) =>
      switch (bucket) {
        PersonalizationBucket.likedMovie => PersonalizationBucket.myListMovie,
        PersonalizationBucket.myListMovie => PersonalizationBucket.likedMovie,
        PersonalizationBucket.likedSeries => PersonalizationBucket.myListSeries,
        PersonalizationBucket.myListSeries => PersonalizationBucket.likedSeries,
        PersonalizationBucket.likedAnime => PersonalizationBucket.myListAnime,
        PersonalizationBucket.myListAnime => PersonalizationBucket.likedAnime,
      };
}

final personalizedRowsControllerProvider =
    NotifierProvider<PersonalizedRowsController, PersonalizedRowsState>(
  PersonalizedRowsController.new,
);
