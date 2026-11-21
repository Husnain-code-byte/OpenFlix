import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel/features/addons/data/addons_storage.dart';
import 'package:pixel/features/addons/data/cloudstream_bridge_client.dart';
import 'package:pixel/features/addons/data/cloudstream_repo_service.dart';
import 'package:pixel/features/addons/data/official_addons_registry.dart';
import 'package:pixel/features/addons/domain/models/addon_models.dart';
import 'package:pixel/features/addons/domain/models/stream_models.dart';
import 'package:pixel/features/addons/presentation/controllers/addons_controller.dart';
import 'package:pixel/features/home/data/models/manifest_model.dart';
import 'package:pixel/features/home/presentation/controllers/home_controller.dart';

class _FakeCsEngine implements CloudStreamEngine {
  final List<String> uninstalledUids = [];
  final Map<String, bool> enabledMap = {};
  Cs3LoadStatus nextStatus = Cs3LoadStatus.loaded;

  @override
  Future<void> cancelStreamResolution(String requestId) async {}

  @override
  Future<Cs3InstallOutcome> installPlugin({
    required String uid,
    required String repoId,
    required String internalName,
    required String downloadUrl,
    String? expectedSha256,
    bool enabled = true,
  }) async {
    return Cs3InstallOutcome(
      status: nextStatus,
      localFilePath: '/tmp/$internalName.cs3',
      providers: nextStatus == Cs3LoadStatus.loaded ? [internalName] : const [],
      error: nextStatus == Cs3LoadStatus.failed ? 'Corrupt .cs3' : null,
    );
  }

  @override
  Future<Map<String, Cs3InstallOutcome>> loadSavedPlugins(
    List<InstalledCs3Plugin> plugins,
  ) async =>
      const {};

  @override
  Stream<Cs3StreamEvent> resolveStreams({
    required String requestId,
    required StreamQuery query,
  }) =>
      const Stream.empty();

  @override
  Future<bool> setPluginEnabled(String uid, bool enabled) async {
    enabledMap[uid] = enabled;
    return true;
  }

  @override
  Future<bool> uninstallPlugin(String uid, {String? localFilePath}) async {
    uninstalledUids.add(uid);
    return true;
  }
}

class _StubRepoDio implements Dio {
  _StubRepoDio(this._routes);

  final Map<String, String> _routes;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<Response<T>> get<T>(
    String path, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
    ProgressCallback? onReceiveProgress,
  }) async {
    final payload = _routes[path];
    if (payload == null) {
      throw DioException(requestOptions: RequestOptions(path: path));
    }
    return Response<T>(
      requestOptions: RequestOptions(path: path),
      statusCode: 200,
      data: payload as T,
    );
  }
}

void main() {
  group('AddonsController & Storage', () {
    test('starts with zero addons installed by default for safety', () async {
      final tmpDir = await Directory.systemTemp.createTemp('openflix_addons_');
      addTearDown(() => tmpDir.delete(recursive: true));

      final storage = AddonsStorage(fileOverride: File('${tmpDir.path}/state.json'));
      final fakeEngine = _FakeCsEngine();

      final container = ProviderContainer(
        overrides: [
          addonsStorageProvider.overrideWithValue(storage),
          cloudStreamEngineProvider.overrideWithValue(fakeEngine),
        ],
      );
      addTearDown(container.dispose);

      final store = await container.read(addonsControllerProvider.future);
      expect(store.safetyAccepted, isFalse);
      expect(store.showNsfw, isFalse);
      expect(store.stremioAddons, isEmpty);
      expect(store.cloudStreamRepos, isEmpty);
      expect(store.installedCs3Plugins, isEmpty);
      expect(container.read(hasAnyStreamSourceProvider), isFalse);
      expect(container.read(installedAddonsCountProvider), 0);
      expect(kOfficialCloudStreamRepos, hasLength(8));
      expect(kOfficialStremioAddons, isEmpty);
    });

    test('persists Stremio addon placement (above/below + search) across reloads',
        () async {
      final tmpDir = await Directory.systemTemp.createTemp('openflix_stremio_');
      addTearDown(() => tmpDir.delete(recursive: true));
      final stateFile = File('${tmpDir.path}/state.json');

      final container1 = ProviderContainer(
        overrides: [
          addonsStorageProvider
              .overrideWithValue(AddonsStorage(fileOverride: stateFile)),
          cloudStreamEngineProvider.overrideWithValue(_FakeCsEngine()),
        ],
      );

      await container1.read(addonsControllerProvider.future);
      final ctrl = container1.read(addonsControllerProvider.notifier);

      final manifest = ManifestModel.fromJson(const {
        'id': 'org.custom.cat',
        'version': '1.0.0',
        'name': 'Custom Cat',
        'resources': ['catalog', 'stream'],
        'types': ['movie', 'series'],
        'catalogs': [
          {
            'id': 'picks',
            'type': 'movie',
            'name': 'Top Picks',
            'extraSupported': ['search'],
          },
          {
            'id': 'shows',
            'type': 'series',
            'name': 'Top Shows',
          },
        ],
      });

      await ctrl.acceptSafetyNotice();
      await ctrl.installOrUpdateStremioAddon(
        manifestUrl: 'https://custom.cat/manifest.json',
        manifest: manifest,
        placements: [
          const CatalogPlacement(
            catalogKey: 'movie/picks',
            enabled: true,
            targetScreens: {AddonTargetScreen.home, AddonTargetScreen.movies},
            position: CatalogShelfPosition.aboveBuiltIn,
          ),
          const CatalogPlacement(
            catalogKey: 'series/shows',
            enabled: true,
            targetScreens: {AddonTargetScreen.home},
            position: CatalogShelfPosition.belowBuiltIn,
          ),
        ],
        includeInSearch: true,
      );

      final homeCustom = container1.read(customCatalogsForFilterProvider(HomeFilter.home));
      expect(homeCustom.above.map((e) => e.catalog.id), ['picks']);
      expect(homeCustom.below.map((e) => e.catalog.id), ['shows']);
      expect(container1.read(enabledSearchStremioAddonsProvider), hasLength(1));
      expect(container1.read(hasAnyStreamSourceProvider), isTrue);

      container1.dispose();

      // Reload from disk in a fresh ProviderContainer
      final container2 = ProviderContainer(
        overrides: [
          addonsStorageProvider
              .overrideWithValue(AddonsStorage(fileOverride: stateFile)),
          cloudStreamEngineProvider.overrideWithValue(_FakeCsEngine()),
        ],
      );
      addTearDown(container2.dispose);

      final reloaded = await container2.read(addonsControllerProvider.future);
      expect(reloaded.safetyAccepted, isTrue);
      expect(reloaded.stremioAddons, hasLength(1));
      expect(reloaded.stremioAddons.first.id, 'org.custom.cat');

      final reloadedMovies =
          container2.read(customCatalogsForFilterProvider(HomeFilter.movies));
      expect(reloadedMovies.above.map((e) => e.catalog.key), ['org.custom.cat::movie/picks']);

      // Disable addon and verify removal from Home & Search
      await container2
          .read(addonsControllerProvider.notifier)
          .toggleStremioAddon('org.custom.cat', false);
      expect(
        container2
            .read(customCatalogsForFilterProvider(HomeFilter.home))
            .above,
        isEmpty,
      );
      expect(container2.read(enabledSearchStremioAddonsProvider), isEmpty);
    });

    test('indexes CloudStream repo, installs .cs3 plugin, toggles & uninstalls',
        () async {
      final tmpDir = await Directory.systemTemp.createTemp('openflix_cs3_');
      addTearDown(() => tmpDir.delete(recursive: true));

      final repoUrl = kOfficialCloudStreamRepos.first.repoUrl;
      const pluginsUrl = 'https://example.com/cs3_plugins.json';
      final fakeDio = _StubRepoDio({
        repoUrl: jsonEncode({
          'manifestVersion': 2,
          'name': 'Megix Repo',
          'pluginLists': [pluginsUrl],
        }),
        pluginsUrl: jsonEncode([
          {
            'name': 'Bollyflix',
            'internalName': 'Bollyflix',
            'url': 'https://example.com/Bollyflix.cs3',
            'version': 3,
            'status': 1,
            'tvTypes': ['Movie'],
            'language': 'hi',
          },
        ]),
      });

      final fakeEngine = _FakeCsEngine();
      final container = ProviderContainer(
        overrides: [
          addonsStorageProvider.overrideWithValue(
            AddonsStorage(fileOverride: File('${tmpDir.path}/state.json')),
          ),
          cloudStreamEngineProvider.overrideWithValue(fakeEngine),
          cloudStreamRepoServiceProvider
              .overrideWithValue(CloudStreamRepoService(fakeDio)),
        ],
      );
      addTearDown(container.dispose);

      await container.read(addonsControllerProvider.future);
      final ctrl = container.read(addonsControllerProvider.notifier);

      final repo = await ctrl.addOrRefreshCloudStreamRepo(
        repoUrl,
        official: kOfficialCloudStreamRepos.first,
      );
      expect(repo.plugins, hasLength(1));

      await ctrl.installAllWorkingPlugins(repo.id);
      var store = container.read(addonsControllerProvider).requireValue;
      expect(store.installedCs3Plugins, hasLength(1));
      expect(store.installedCs3Plugins.first.loadStatus, Cs3LoadStatus.loaded);
      expect(container.read(hasAnyStreamSourceProvider), isTrue);

      final uid = store.installedCs3Plugins.first.uid;
      await ctrl.toggleCs3Plugin(uid, false);
      expect(fakeEngine.enabledMap[uid], isFalse);
      expect(container.read(hasAnyStreamSourceProvider), isFalse);

      await ctrl.uninstallCs3Plugin(uid);
      expect(fakeEngine.uninstalledUids, contains(uid));
      store = container.read(addonsControllerProvider).requireValue;
      expect(store.installedCs3Plugins, isEmpty);
    });
  });
}
