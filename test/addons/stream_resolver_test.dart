import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel/features/addons/data/addons_storage.dart';
import 'package:pixel/features/addons/data/cloudstream_bridge_client.dart';
import 'package:pixel/features/addons/data/stremio_addon_service.dart';
import 'package:pixel/features/addons/domain/models/addon_models.dart';
import 'package:pixel/features/addons/domain/models/stream_models.dart';
import 'package:pixel/features/addons/presentation/controllers/addons_controller.dart';
import 'package:pixel/features/addons/presentation/controllers/stream_resolver_controller.dart';
import 'package:pixel/features/anime/data/anime_id_map.dart';
import 'package:pixel/features/home/data/models/manifest_model.dart';

class _FakeStreamStremioService extends StremioAddonService {
  _FakeStreamStremioService(this._streamsByKey, {this.subs = const []})
      : super(Dio());

  final Map<String, List<ResolvedStream>> _streamsByKey;
  final List<ResolvedSubtitle> subs;
  final List<String> queriedVideoIds = [];

  @override
  Future<List<ResolvedStream>> fetchStreams(
    InstalledStremioAddon addon,
    String type,
    String videoId, {
    CancelToken? cancelToken,
  }) async {
    queriedVideoIds.add(videoId);
    return _streamsByKey['${addon.id}:$type:$videoId'] ?? const [];
  }

  @override
  Future<List<ResolvedSubtitle>> fetchSubtitles(
    InstalledStremioAddon addon,
    String type,
    String videoId, {
    CancelToken? cancelToken,
  }) async =>
      subs;
}

class _FakeCsResolverEngine implements CloudStreamEngine {
  final List<String> cancelledRequests = [];
  StreamQuery? lastQuery;

  @override
  Future<void> cancelStreamResolution(String requestId) async {
    cancelledRequests.add(requestId);
  }

  @override
  Future<Cs3InstallOutcome> installPlugin({
    required String uid,
    required String repoId,
    required String internalName,
    required String downloadUrl,
    String? expectedSha256,
    bool enabled = true,
  }) async =>
      const Cs3InstallOutcome(status: Cs3LoadStatus.loaded);

  @override
  Future<Map<String, Cs3InstallOutcome>> loadSavedPlugins(
    List<InstalledCs3Plugin> plugins,
  ) async =>
      const {};

  @override
  Future<bool> setPluginEnabled(String uid, bool enabled) async => true;

  @override
  Future<bool> uninstallPlugin(String uid, {String? localFilePath}) async =>
      true;

  @override
  Stream<Cs3StreamEvent> resolveStreams({
    required String requestId,
    required StreamQuery query,
  }) {
    lastQuery = query;
    return Stream<Cs3StreamEvent>.fromIterable([
      Cs3StreamLinkEvent(
        requestId,
        const ResolvedStream(
          id: 'cs3_1',
          architecture: AddonArchitecture.cloudstream,
          addonId: 'CineStream',
          addonName: 'CineStream',
          providerName: 'CineStream',
          title: 'CineStream 4K HLS',
          transport: StreamTransport.hls,
          url: 'https://cs3.example.com/4k.m3u8',
          qualityLabel: '4K',
          qualityRank: 2160,
        ),
      ),
      Cs3SubtitleEvent(
        requestId,
        'CineStream',
        const ResolvedSubtitle(
          url: 'https://subs.example.com/en.vtt',
          language: 'en',
          sourceName: 'CineStream',
        ),
      ),
      Cs3ProviderDoneEvent(
        requestId,
        providerName: 'CineStream',
        streamCount: 1,
        elapsedMs: 120,
      ),
      Cs3ResolutionCompleteEvent(requestId),
    ]);
  }
}

void main() {
  group('StreamResolverController', () {
    test(
        'enriches AniList IDs via AnimeIdMap, fans out across Stremio & CS3, dedups & sorts direct-first',
        () async {
      final tmpDir = await Directory.systemTemp.createTemp('openflix_res_');
      addTearDown(() => tmpDir.delete(recursive: true));

      final storage =
          AddonsStorage(fileOverride: File('${tmpDir.path}/state.json'));

      final stremioAddon = InstalledStremioAddon(
        id: 'org.stream.test',
        manifestUrl: 'https://stream.test/manifest.json',
        baseUrl: 'https://stream.test',
        manifest: ManifestModel.fromJson(const {
          'id': 'org.stream.test',
          'name': 'StreamTest',
          'version': '1.0.0',
          'types': ['series'],
          'resources': ['stream', 'subtitles'],
          'idPrefixes': ['tt'],
        }),
      );

      await storage.save(
        AddonsStoreState(
          safetyAccepted: true,
          stremioAddons: [stremioAddon],
          installedCs3Plugins: const [
            InstalledCs3Plugin(
              uid: 'cs_megix::CineStream',
              repoId: 'cs_megix',
              internalName: 'CineStream',
              name: 'CineStream',
              downloadUrl: 'https://example.com/CineStream.cs3',
              enabled: true,
              loadStatus: Cs3LoadStatus.loaded,
            ),
          ],
        ),
      );

      final fakeAnimeMap = AnimeIdMap()
        ..populate(
          {
            21: const AnimeIds(imdbId: 'tt0388629', tmdbId: 37854),
          },
          {'imdb:tt0388629': 21, 'series:37854': 21},
        );

      final fakeStremio = _FakeStreamStremioService(
        {
          'org.stream.test:series:tt0388629:1:2': const [
            ResolvedStream(
              id: 's_torrent',
              architecture: AddonArchitecture.stremio,
              addonId: 'org.stream.test',
              addonName: 'StreamTest',
              providerName: 'TorrentSource',
              title: '1080p Torrent',
              transport: StreamTransport.torrent,
              infoHash: '1111222233334444555566667777888899990000',
              qualityLabel: '1080p',
              qualityRank: 1080,
            ),
            // Duplicate of CS3 URL to verify dedup
            ResolvedStream(
              id: 's_dup',
              architecture: AddonArchitecture.stremio,
              addonId: 'org.stream.test',
              addonName: 'StreamTest',
              providerName: 'DirectMirror',
              title: 'Duplicate 4K HLS',
              transport: StreamTransport.hls,
              url: 'https://cs3.example.com/4k.m3u8',
              qualityLabel: '4K',
              qualityRank: 2160,
            ),
          ],
        },
        subs: const [
          ResolvedSubtitle(
            url: 'https://subs.example.com/ar.srt',
            language: 'ar',
            sourceName: 'StreamTest',
          ),
        ],
      );

      final fakeCsEngine = _FakeCsResolverEngine();

      final container = ProviderContainer(
        overrides: [
          addonsStorageProvider.overrideWithValue(storage),
          animeIdMapProvider.overrideWithValue(fakeAnimeMap),
          stremioAddonServiceProvider.overrideWithValue(fakeStremio),
          cloudStreamEngineProvider.overrideWithValue(fakeCsEngine),
        ],
      );
      addTearDown(container.dispose);

      await container.read(addonsControllerProvider.future);

      await container.read(streamResolverProvider.notifier).resolve(
            const StreamQuery(
              mediaType: 'series',
              title: 'One Piece',
              rawMetaId: 'anilist:21',
              season: 1,
              episode: 2,
            ),
          );

      final resolved = container.read(streamResolverProvider);
      expect(resolved.isResolving, isFalse);
      expect(fakeStremio.queriedVideoIds, ['tt0388629:1:2']);
      expect(fakeCsEngine.lastQuery?.imdbId, 'tt0388629');
      expect(fakeCsEngine.lastQuery?.tmdbId, 37854);
      expect(fakeCsEngine.lastQuery?.isAnime, isTrue);

      // Dedup keeps 2 unique streams sorted direct/HLS first
      expect(resolved.streams, hasLength(2));
      expect(resolved.streams.first.transport, StreamTransport.hls);
      expect(resolved.streams.last.transport, StreamTransport.torrent);
      expect(resolved.subtitles, hasLength(2));
    });
  });
}
