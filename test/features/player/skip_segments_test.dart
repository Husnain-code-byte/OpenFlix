import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixel/features/player/data/skip_segments_service.dart';
import 'package:pixel/features/player/domain/models/skip_segment.dart';
import 'package:pixel/features/player/domain/models/watch_progress_models.dart';
import 'package:pixel/features/preferences/domain/models/playback_preferences.dart';

void main() {
  group('IntroDbClient.parseResponse', () {
    test('parses valid intro, recap, outro, and post_credits segments', () {
      final json = {
        'imdb_id': 'tt0903747',
        'season': 1,
        'episode': 2,
        'recap': {'start_ms': 0, 'end_ms': 35000, 'confidence': 0.9},
        'intro': {'start_ms': 120000, 'end_ms': 142000, 'confidence': 1.0},
        'outro': {'start_sec': 2700, 'end_sec': 2765, 'confidence': 0.95},
        'post_credits': {
          'start_ms': 2765000,
          'end_ms': 2810000,
          'confidence': 0.85,
        },
      };

      final segments = IntroDbClient.parseResponse(json);
      expect(segments.length, 4);
      expect(segments[0].type, SkipSegmentType.recap);
      expect(segments[1].type, SkipSegmentType.intro);
      expect(segments[1].startMs, 120000);
      expect(segments[2].type, SkipSegmentType.outro);
      expect(segments[2].startMs, 2700000);
      expect(segments[3].type, SkipSegmentType.postCredits);
    });

    test('filters out low-confidence and too-short segments', () {
      final json = {
        'intro': {'start_ms': 10000, 'end_ms': 13000, 'confidence': 1.0},
        'outro': {'start_ms': 2000000, 'end_ms': 2060000, 'confidence': 0.2},
      };
      expect(IntroDbClient.parseResponse(json), isEmpty);
    });
  });

  group('AniSkipClient.parseResponse', () {
    test('maps op, ed, recap and prefers pure op over mixed-op', () {
      final json = {
        'found': true,
        'results': [
          {
            'skipType': 'mixed-op',
            'interval': {'startTime': 40.0, 'endTime': 130.0},
          },
          {
            'skipType': 'op',
            'interval': {'startTime': 47.365, 'endTime': 137.365},
          },
          {
            'skipType': 'ed',
            'interval': {'startTime': 1342.795, 'endTime': 1430.616},
          },
          {
            'skipType': 'recap',
            'interval': {'startTime': 0.0, 'endTime': 45.0},
          },
        ],
      };

      final segments = AniSkipClient.parseResponse(json);
      expect(segments.length, 3);
      expect(segments[0].type, SkipSegmentType.recap);
      expect(segments[1].type, SkipSegmentType.intro);
      expect(segments[1].startMs, 47365);
      expect(segments[2].type, SkipSegmentType.outro);
      expect(segments[2].startMs, 1342795);
    });

    test('rejects AniSkip items whose episodeLength mismatches actual video duration', () {
      final json = {
        'found': true,
        'results': [
          {
            'skipType': 'op',
            'episodeLength': 1420.0,
            'interval': {'startTime': 60.0, 'endTime': 150.0},
          },
          {
            'skipType': 'ed',
            'episodeLength': 1350.0,
            'interval': {'startTime': 1250.0, 'endTime': 1340.0},
          },
        ],
      };

      final matched = AniSkipClient.parseResponse(json, actualDurationSec: 1425);
      expect(matched.length, 1);
      expect(matched.first.type, SkipSegmentType.intro);
    });
  });

  group('SkipSegment prompt lead-in window', () {
    test('intro prompt appears 3.5s before intro.start through intro.end', () {
      const intro = SkipSegment(
        type: SkipSegmentType.intro,
        startMs: 60000,
        endMs: 150000,
        source: SkipSegmentSource.aniSkip,
      );

      expect(intro.isPromptActiveAt(56499), isFalse);
      expect(intro.isPromptActiveAt(56500), isTrue);
      expect(intro.isPromptActiveAt(60000), isTrue);
      expect(intro.isPromptActiveAt(149999), isTrue);
      expect(intro.isPromptActiveAt(150000), isFalse);
      // Auto-skip check does not trigger early during the 3.5s lead-in.
      expect(intro.isActiveAt(58000), isFalse);
      expect(intro.isActiveAt(60000), isTrue);
    });

    test('clamps intro lead-in at 0 when intro starts within 3.5s', () {
      const intro = SkipSegment(
        type: SkipSegmentType.intro,
        startMs: 2000,
        endMs: 92000,
        source: SkipSegmentSource.embeddedChapters,
      );

      expect(intro.isPromptActiveAt(0), isTrue);
      expect(intro.isPromptActiveAt(91999), isTrue);
      expect(intro.isPromptActiveAt(92000), isFalse);
    });
  });

  group('MpvChapterParser.parse', () {
    test('extracts Opening, Recap, Ending, Preview chapters accurately', () {
      final chapters = jsonEncode([
        {'title': 'Previously On', 'time': 0.0},
        {'title': 'Opening', 'time': 42.0},
        {'title': 'Part A', 'time': 132.0},
        {'title': 'Part B', 'time': 720.0},
        {'title': 'Ending Credits', 'time': 1320.0},
        {'title': 'Next Episode Preview', 'time': 1410.0},
      ]);

      final segments = MpvChapterParser.parse(chapters, durationMs: 1440000);
      expect(segments.length, 4);
      expect(segments[0].type, SkipSegmentType.recap);
      expect(segments[0].endMs, 42000);
      expect(segments[1].type, SkipSegmentType.intro);
      expect(segments[1].startMs, 42000);
      expect(segments[1].endMs, 132000);
      expect(segments[2].type, SkipSegmentType.outro);
      expect(segments[2].startMs, 1320000);
      expect(segments[2].endMs, 1410000);
      expect(segments[3].type, SkipSegmentType.postCredits);
      expect(segments[3].startMs, 1410000);
      expect(segments[3].endMs, 1440000);
    });

    test('rejects mislabeled full-act chapter covering >60% of duration', () {
      final chapters = jsonEncode([
        {'title': 'Intro', 'time': 0.0},
        {'title': 'Credits', 'time': 1300.0},
      ]);
      final segments = MpvChapterParser.parse(chapters, durationMs: 1400000);
      expect(segments.length, 1);
      expect(segments.first.type, SkipSegmentType.outro);
    });
  });

  group('SkipSegmentsRepository.mergeAndSanitize', () {
    test('prioritizes MKV chapters per type and fills gaps from online APIs', () {
      const embeddedIntro = SkipSegment(
        type: SkipSegmentType.intro,
        startMs: 50000,
        endMs: 140000,
        source: SkipSegmentSource.embeddedChapters,
      );
      const onlineIntro = SkipSegment(
        type: SkipSegmentType.intro,
        startMs: 45000,
        endMs: 135000,
        source: SkipSegmentSource.introDb,
      );
      const onlineOutro = SkipSegment(
        type: SkipSegmentType.outro,
        startMs: 2600000,
        endMs: 2690000,
        source: SkipSegmentSource.introDb,
      );
      const mismatchedOutro = SkipSegment(
        type: SkipSegmentType.postCredits,
        startMs: 2900000,
        endMs: 2950000,
        source: SkipSegmentSource.introDb,
      );

      final merged = SkipSegmentsRepository.mergeAndSanitize(
        embedded: const [embeddedIntro],
        online: const [onlineIntro, onlineOutro, mismatchedOutro],
        durationMs: 2700000,
      );

      expect(merged.length, 2);
      expect(merged[0].source, SkipSegmentSource.embeddedChapters);
      expect(merged[0].startMs, 50000);
      expect(merged[1].type, SkipSegmentType.outro);
      expect(merged[1].source, SkipSegmentSource.introDb);
    });

    test('rejects bogus/out-of-bounds anime intro & outro ranges', () {
      const tooLongAnimeIntro = SkipSegment(
        type: SkipSegmentType.intro,
        startMs: 0,
        endMs: 400000, // 6m40s — bogus for anime OP
        source: SkipSegmentSource.aniSkip,
      );
      const tooEarlyOutro = SkipSegment(
        type: SkipSegmentType.outro,
        startMs: 300000, // 20% into episode — bogus outro
        endMs: 390000,
        source: SkipSegmentSource.aniSkip,
      );
      const validOutro = SkipSegment(
        type: SkipSegmentType.outro,
        startMs: 1320000,
        endMs: 1410000,
        source: SkipSegmentSource.embeddedChapters,
      );

      final merged = SkipSegmentsRepository.mergeAndSanitize(
        embedded: const [validOutro],
        online: const [tooLongAnimeIntro, tooEarlyOutro],
        durationMs: 1440000,
        isAnime: true,
      );

      expect(merged.length, 1);
      expect(merged.first.type, SkipSegmentType.outro);
    });
  });

  group('ActiveSkipPrompt alignment & labels', () {
    test('places intro/recap left and outro/post-credits/next-episode right', () {
      expect(SkipActionKind.skipIntro.isLeftAligned, isTrue);
      expect(SkipActionKind.skipRecap.isLeftAligned, isTrue);
      expect(SkipActionKind.skipCredits.isLeftAligned, isFalse);
      expect(SkipActionKind.skipToPostCredits.isLeftAligned, isFalse);
      expect(SkipActionKind.nextEpisode.isLeftAligned, isFalse);
      expect(SkipActionKind.skipIntro.buttonLabel, 'Skip intro');
      expect(SkipActionKind.skipCredits.buttonLabel, 'Skip outro');
    });
  });

  group('Continue Watching next-episode promotion', () {
    test('promotes S1E2 when S1E1 reaches next-episode point', () {
      const entry = WatchProgressEntry(
        canonicalId: 'imdb:tt0903747',
        mediaType: 'series',
        title: 'Breaking Bad',
        imdbId: 'tt0903747',
        lastWatchedSeason: 1,
        lastWatchedEpisode: 1,
        nextSeason: 1,
        nextEpisode: 2,
        nextEpisodeRuntimeMinutes: 48,
        episodes: {
          'S1E1': EpisodeProgress(
            season: 1,
            episode: 1,
            positionMs: 3480000,
            durationMs: 3480000,
            updatedAtMs: 1000,
            completed: true,
          ),
        },
      );

      expect(entry.isInContinueWatching, isTrue);
      expect(entry.continueWatchingEpisodeBadge, 'S1E2');
      expect(entry.continueWatchingRemainingLabel, 'Up Next');
      expect(entry.continueWatchingProgressFraction, 0.0);
    });

    test('promotes across season boundary (S1E8 -> S2E1) on Home without seasonsCache', () {
      const entry = WatchProgressEntry(
        canonicalId: 'imdb:tt1234567',
        mediaType: 'series',
        title: 'Test Show',
        lastWatchedSeason: 1,
        lastWatchedEpisode: 8,
        nextSeason: 2,
        nextEpisode: 1,
        nextEpisodeRuntimeMinutes: 52,
        episodes: {
          'S1E8': EpisodeProgress(
            season: 1,
            episode: 8,
            positionMs: 3000000,
            durationMs: 3000000,
            updatedAtMs: 2000,
            completed: true,
          ),
        },
      );

      final target = resolveSeriesPlaybackTarget(entry: entry);
      expect(target.season, 2);
      expect(target.episode, 1);
      expect(target.resumePositionMs, 0);
      expect(entry.continueWatchingEpisodeBadge, 'S2E1');
    });

    test('hides confirmed series finale from Continue Watching', () {
      const entry = WatchProgressEntry(
        canonicalId: 'imdb:tt9999999',
        mediaType: 'series',
        title: 'Finished Show',
        lastWatchedSeason: 5,
        lastWatchedEpisode: 16,
        seriesCompleted: true,
        episodes: {
          'S5E16': EpisodeProgress(
            season: 5,
            episode: 16,
            positionMs: 3300000,
            durationMs: 3300000,
            updatedAtMs: 3000,
            completed: true,
          ),
        },
      );

      expect(entry.isInContinueWatching, isFalse);
    });
  });

  group('PlaybackPreferences auto-skip persistence', () {
    test('round-trips autoSkipIntroRecap and autoSkipOutro with false defaults', () {
      const defaults = PlaybackPreferences();
      expect(defaults.autoSkipIntroRecap, isFalse);
      expect(defaults.autoSkipOutro, isFalse);

      final custom = defaults.copyWith(
        autoSkipIntroRecap: true,
        autoSkipOutro: true,
      );
      final restored = PlaybackPreferences.fromJson(custom.toJson());
      expect(restored.autoSkipIntroRecap, isTrue);
      expect(restored.autoSkipOutro, isTrue);
    });
  });
}
