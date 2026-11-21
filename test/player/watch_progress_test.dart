import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel/core/theme/app_theme.dart';
import 'package:pixel/features/details/data/tmdb_models.dart';
import 'package:pixel/features/home/data/models/manifest_model.dart';
import 'package:pixel/features/home/presentation/controllers/home_controller.dart';
import 'package:pixel/features/home/presentation/widgets/continue_watching_shelf.dart';
import 'package:pixel/features/personalization/data/personalized_slots.dart';
import 'package:pixel/features/player/data/watch_progress_storage.dart';
import 'package:pixel/features/player/domain/models/watch_progress_models.dart';
import 'package:pixel/features/player/presentation/controllers/watch_progress_controller.dart';

void main() {
  group('WatchProgress & Series Auto-Season', () {
    test('movie resume window checks <30s, 30s..89%, and >=90% completion', () {
      // Too brief -> not resumable
      expect(isPositionResumable(15000, 7200000), isFalse);
      // Mid movie -> resumable
      expect(isPositionResumable(1800000, 7200000), isTrue);
      // Past 90% -> completed, not resumable
      expect(isPositionCompleted(6600000, 7200000), isTrue);
      expect(isPositionResumable(6600000, 7200000), isFalse);
    });

    test('resolveSeriesPlaybackTarget opens active watched season & auto-advances across episodes and season finale', () {
      const seasons = [
        TmdbSeasonSummary(id: 1, seasonNumber: 1, name: 'Season 1', episodeCount: 8),
        TmdbSeasonSummary(id: 2, seasonNumber: 2, name: 'Season 2', episodeCount: 8),
        TmdbSeasonSummary(id: 3, seasonNumber: 3, name: 'Season 3', episodeCount: 8),
      ];

      // 1. Mid-watch S3 E2 -> Resume S3 · E2 and Season 3 active
      const midEntry = WatchProgressEntry(
        canonicalId: 'imdb:tt7462410',
        mediaType: 'series',
        title: 'The Wheel of Time',
        lastWatchedSeason: 3,
        lastWatchedEpisode: 2,
        episodes: {
          'S3E2': EpisodeProgress(
            season: 3,
            episode: 2,
            positionMs: 1200000,
            durationMs: 3600000,
            updatedAtMs: 1000,
          ),
        },
      );
      final targetMid =
          resolveSeriesPlaybackTarget(entry: midEntry, seasons: seasons);
      expect(targetMid.season, 3);
      expect(targetMid.episode, 2);
      expect(targetMid.isResume, isTrue);
      expect(targetMid.buttonLabel, 'Resume S3 · E2');

      // 2. Completed S2 E8 -> auto-advance to S3 E1!
      const finaleDone = WatchProgressEntry(
        canonicalId: 'imdb:tt7462410',
        mediaType: 'series',
        title: 'The Wheel of Time',
        lastWatchedSeason: 2,
        lastWatchedEpisode: 8,
        episodes: {
          'S2E8': EpisodeProgress(
            season: 2,
            episode: 8,
            positionMs: 3500000,
            durationMs: 3600000,
            updatedAtMs: 2000,
            completed: true,
          ),
        },
      );
      final targetNextSeason =
          resolveSeriesPlaybackTarget(entry: finaleDone, seasons: seasons);
      expect(targetNextSeason.season, 3);
      expect(targetNextSeason.episode, 1);
      expect(targetNextSeason.isResume, isFalse);
      expect(targetNextSeason.buttonLabel, 'Play S3 · E1');
    });

    test('WatchProgressController merges cross-ID records and persists atomically', () async {
      final tmpDir = await Directory.systemTemp.createTemp('openflix_wp_');
      addTearDown(() => tmpDir.delete(recursive: true));
      final file = File('${tmpDir.path}/watch_progress.json');

      final container = ProviderContainer(
        overrides: [
          watchProgressStorageProvider.overrideWithValue(
            WatchProgressStorage(fileOverride: file),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(watchProgressControllerProvider.future);
      final ctrl = container.read(watchProgressControllerProvider.notifier);

      await ctrl.recordProgress(
        mediaType: 'series',
        title: 'The Wheel of Time',
        tmdbId: 71914,
        imdbId: 'tt7462410',
        season: 3,
        episode: 4,
        positionMs: 900000,
        durationMs: 3300000,
      );

      // Lookup succeeds using TMDB ID alone OR IMDb ID alone.
      final byTmdb = ctrl.lookup(tmdbId: 71914, mediaType: 'series');
      final byImdb = ctrl.lookup(imdbId: 'tt7462410', mediaType: 'series');
      expect(byTmdb, isNotNull);
      expect(byImdb, equals(byTmdb));
      expect(byTmdb!.lastWatchedSeason, 3);
      expect(byTmdb.episodeFor(3, 4)!.positionMs, 900000);

      // Reload from disk in fresh storage
      final reloaded = await WatchProgressStorage(fileOverride: file).load();
      expect(reloaded.lookup(tmdbId: 71914, mediaType: 'series'), isNotNull);
    });

    test('continueWatchingForFilter separates Home/Movies/TV/Anime and mergeFeedEntries puts it at Row #3', () {
      const movieEntry = WatchProgressEntry(
        canonicalId: 'imdb:tt1001',
        mediaType: 'movie',
        title: 'Dune',
        positionMs: 1200000,
        durationMs: 7200000,
        updatedAtMs: 300,
      );
      const tvEntry = WatchProgressEntry(
        canonicalId: 'imdb:tt2002',
        mediaType: 'series',
        title: 'Reacher',
        updatedAtMs: 500,
        lastWatchedSeason: 2,
        lastWatchedEpisode: 3,
        episodes: {
          'S2E3': EpisodeProgress(
            season: 2,
            episode: 3,
            positionMs: 900000,
            durationMs: 2880000,
            updatedAtMs: 500,
          ),
        },
      );
      const animeEntry = WatchProgressEntry(
        canonicalId: 'anilist:16498',
        mediaType: 'series',
        title: 'Attack on Titan',
        isAnime: true,
        updatedAtMs: 400,
        lastWatchedSeason: 1,
        lastWatchedEpisode: 5,
        episodes: {
          'S1E5': EpisodeProgress(
            season: 1,
            episode: 5,
            positionMs: 600000,
            durationMs: 1440000,
            updatedAtMs: 400,
          ),
        },
      );

      final store = WatchProgressStoreState(
        entriesById: {
          movieEntry.canonicalId: movieEntry,
          tvEntry.canonicalId: tvEntry,
          animeEntry.canonicalId: animeEntry,
        },
      );

      expect(
        store.continueWatchingForFilter(HomeFilter.home).map((e) => e.title),
        ['Reacher', 'Attack on Titan', 'Dune'],
      );
      expect(
        store.continueWatchingForFilter(HomeFilter.movies).map((e) => e.title),
        ['Dune'],
      );
      expect(
        store.continueWatchingForFilter(HomeFilter.tvShows).map((e) => e.title),
        ['Reacher'],
      );
      expect(
        store.continueWatchingForFilter(HomeFilter.anime).map((e) => e.title),
        ['Attack on Titan'],
      );

      final catalogs = [
        for (var i = 1; i <= 5; i++)
          CatalogItemModel(id: 'cat_$i', type: 'movie', name: 'Catalog $i'),
      ];
      final merged = mergeFeedEntries(
        catalogs: catalogs,
        personalizedRows: const [],
        slotPositions: PersonalizedSlots.homePositions,
        continueWatchingEntries: [tvEntry, movieEntry],
      );
      // 1-indexed Row #3 -> index 2
      expect(merged[2], isA<ContinueWatchingFeedEntry>());
    });

    testWidgets('ContinueWatchingShelf renders 170x98 card, S1E1 + time left, and 3-dots sheet with View Details & Remove', (tester) async {
      await tester.binding.setSurfaceSize(const Size(393, 852));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      var removedId = '';
      var viewedId = '';
      const entry = WatchProgressEntry(
        canonicalId: 'imdb:tt11247158',
        mediaType: 'series',
        title: 'The Legend of Vox Machina',
        updatedAtMs: 1000,
        lastWatchedSeason: 1,
        lastWatchedEpisode: 1,
        episodes: {
          'S1E1': EpisodeProgress(
            season: 1,
            episode: 1,
            positionMs: 600000,
            durationMs: 1500000,
            updatedAtMs: 1000,
          ),
        },
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.dark(),
            home: Scaffold(
              body: ContinueWatchingShelf(
                entries: const [entry],
                onResume: (_) {},
                onViewDetails: (e) => viewedId = e.canonicalId,
                onRemove: (e) => removedId = e.canonicalId,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Continue Watching'), findsOneWidget);
      expect(find.textContaining('S1E1'), findsOneWidget);
      expect(find.textContaining('15m left'), findsOneWidget);

      // Tap 3-dots button -> opens modal with title name, View Details, and Remove
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();

      expect(find.text('The Legend of Vox Machina'), findsOneWidget);
      expect(find.text('View Details'), findsOneWidget);
      expect(find.text('Remove from Continue Watching'), findsOneWidget);

      await tester.tap(find.text('Remove from Continue Watching'));
      await tester.pumpAndSettle();
      expect(removedId, entry.canonicalId);
      expect(viewedId, isEmpty);
    });
  });
}
