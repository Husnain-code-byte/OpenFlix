import 'package:flutter_test/flutter_test.dart';
import 'package:pixel/features/addons/domain/models/addon_models.dart';
import 'package:pixel/features/addons/domain/models/stream_models.dart';
import 'package:pixel/features/player/data/stream_ranker.dart';
import 'package:pixel/features/player/domain/models/ranked_stream.dart';
import 'package:pixel/features/preferences/domain/models/playback_preferences.dart';

void main() {
  const prefs = PlaybackPreferences(
    primaryLanguage: 'hi',
    fallbackLanguage: 'en',
  );
  final phone1080p = DeviceDisplayProfile.fromPhysicalShortEdge(1080);

  ResolvedStream makeStream({
    required String id,
    required String title,
    StreamTransport transport = StreamTransport.directHttp,
    String? url = 'https://host.example.com/video.mp4',
    String? infoHash,
    String? providerLang,
    int qualityRank = 0,
  }) =>
      ResolvedStream(
        id: id,
        architecture: AddonArchitecture.stremio,
        addonId: 'addon',
        addonName: 'TestAddon',
        providerName: 'Provider',
        providerLang: providerLang,
        title: title,
        transport: transport,
        url: url,
        infoHash: infoHash,
        qualityRank: qualityRank,
      );

  group('StreamRanker', () {
    test('ranks Primary > Fallback > Unknown > Other language, with direct HTTP ahead of P2P', () {
      final streams = [
        makeStream(id: 'other', title: '1080p Russian'),
        makeStream(id: 'fallback', title: '1080p English'),
        makeStream(
          id: 'p2p',
          title: '1080p Hindi',
          transport: StreamTransport.torrent,
          url: null,
          infoHash: 'abc123',
        ),
        makeStream(id: 'unknown', title: '1080p WEB-DL'),
        makeStream(id: 'primary', title: '1080p Hindi'),
      ];

      final ranked = StreamRanker.rank(
        streams: streams,
        prefs: prefs,
        displayProfile: phone1080p,
      );

      expect(
        ranked.map((r) => r.stream.id).toList(),
        ['primary', 'fallback', 'unknown', 'other', 'p2p'],
      );
      expect(ranked.last.isAutoPlayEligible, isFalse);
    });

    test('soft device cap prefers 1080p over 4K on 1080p phone, yet picks 4K when only 4K matches primary', () {
      final both = StreamRanker.rank(
        streams: [
          makeStream(id: '4k_hi', title: '4K 2160p Hindi WEB-DL', url: 'https://a.com/4k.mp4'),
          makeStream(id: '1080_hi', title: '1080p Hindi WEB-DL', url: 'https://b.com/1080.mp4'),
          makeStream(id: '480_hi', title: '480p Hindi', url: 'https://c.com/480.mp4'),
        ],
        prefs: prefs,
        displayProfile: phone1080p,
      );
      expect(both.first.stream.id, '1080_hi');
      expect(both[1].stream.id, '4k_hi');
      expect(both[2].stream.id, '480_hi');

      // On a 4K display, 4K beats 1080p cleanly.
      final on4kScreen = StreamRanker.rank(
        streams: [
          makeStream(id: '1080_hi', title: '1080p Hindi WEB-DL', url: 'https://b.com/1080.mp4'),
          makeStream(id: '4k_hi', title: '4K 2160p Hindi WEB-DL', url: 'https://a.com/4k.mp4'),
        ],
        prefs: prefs,
        displayProfile: DeviceDisplayProfile.fromPhysicalShortEdge(2160),
      );
      expect(on4kScreen.first.stream.id, '4k_hi');
    });

    test('demotes dead links and failed session hosts and prefers faster probed servers', () {
      final fast = makeStream(id: 'fast', title: '1080p Hindi', url: 'https://fast.example.com/v.mp4');
      final slow = makeStream(id: 'slow', title: '1080p Hindi', url: 'https://slow.example.com/v.mp4');
      final dead = makeStream(id: 'dead', title: '1080p Hindi', url: 'https://dead.example.com/v.mp4');

      final now = DateTime.now().millisecondsSinceEpoch;
      final ranked = StreamRanker.rank(
        streams: [dead, slow, fast],
        prefs: prefs,
        displayProfile: phone1080p,
        probeCache: {
          fast.dedupKey: StreamProbeResult(
            isAlive: true,
            statusCode: 206,
            ttfbMs: 140,
            estimatedMbps: 22.0,
            probedAtMs: now,
          ),
          slow.dedupKey: StreamProbeResult(
            isAlive: true,
            statusCode: 206,
            ttfbMs: 1400,
            estimatedMbps: 2.0,
            probedAtMs: now,
          ),
          dead.dedupKey: StreamProbeResult(
            isAlive: false,
            statusCode: 404,
            probedAtMs: now,
          ),
        },
      );

      expect(ranked.map((r) => r.stream.id).toList(), ['fast', 'slow', 'dead']);
      expect(ranked.last.isAutoPlayEligible, isFalse);

      // Session failure on fast server demotes it immediately.
      final tracker = HostReliabilityTracker()..recordFailure(fast);
      final reranked = StreamRanker.rank(
        streams: [fast, slow],
        prefs: prefs,
        displayProfile: phone1080p,
        reliabilityTracker: tracker,
      );
      expect(reranked.first.stream.id, 'slow');
    });

    test('penalizes CAM rips below clean 720p', () {
      final ranked = StreamRanker.rank(
        streams: [
          makeStream(id: 'cam', title: '1080p CAMRip Hindi', url: 'https://a.com/cam.mp4'),
          makeStream(id: 'clean720', title: '720p Hindi WEB-DL', url: 'https://b.com/720.mp4'),
        ],
        prefs: prefs,
        displayProfile: phone1080p,
      );
      expect(ranked.first.stream.id, 'clean720');
    });

    test('isDurationCompatibleWithRuntime rejects trailers and wrong-runtime titles', () {
      // 48 min Reacher episode: accepts 46m & 54m, rejects 2m trailer, 22m sitcom, 130m movie
      expect(isDurationCompatibleWithRuntime(46 * 60, 48), isTrue);
      expect(isDurationCompatibleWithRuntime(54 * 60, 48), isTrue);
      expect(isDurationCompatibleWithRuntime(120, 48), isFalse);
      expect(isDurationCompatibleWithRuntime(22 * 60, 48), isFalse);
      expect(isDurationCompatibleWithRuntime(130 * 60, 48), isFalse);
      // Unknown runtime stays allowed
      expect(isDurationCompatibleWithRuntime(46 * 60, null), isTrue);
    });

    test('hides streams flagged with runtimeMismatch completely from ranked list', () {
      final bad = makeStream(
        id: 'wrong_movie',
        title: '1080p Hindi WEB-DL',
        url: 'https://a.com/wrong.m3u8',
      );
      final good = makeStream(
        id: 'right_ep',
        title: '720p English WEB-DL',
        url: 'https://b.com/right.m3u8',
      );
      final ranked = StreamRanker.rank(
        streams: [bad, good],
        prefs: prefs,
        displayProfile: phone1080p,
        probeCache: {
          bad.dedupKey: const StreamProbeResult(
            isAlive: false,
            probedDurationSeconds: 7800,
            runtimeMismatch: true,
            probedAtMs: 1000,
          ),
        },
      );
      expect(ranked.map((r) => r.stream.id).toList(), ['right_ep']);
    });
  });
}
