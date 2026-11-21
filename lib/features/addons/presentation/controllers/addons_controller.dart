import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../home/data/models/manifest_model.dart';
import '../../../home/presentation/controllers/home_controller.dart';
import '../../data/addons_storage.dart';
import '../../data/cloudstream_bridge_client.dart';
import '../../data/cloudstream_repo_service.dart';
import '../../data/official_addons_registry.dart';
import '../../data/stremio_addon_service.dart';
import '../../domain/models/addon_models.dart';

/// Resolved custom catalog entry ready for rendering on a specific [HomeFilter] screen.
class CustomCatalogEntry {
  const CustomCatalogEntry({
    required this.addon,
    required this.catalog,
    required this.placement,
  });

  final InstalledStremioAddon addon;
  final CatalogItemModel catalog;
  final CatalogPlacement placement;
}

/// Pending `stremio://` deep-link manifest URL captured from an Android
/// browser `/configure` redirect so the UI can open the install preview sheet.
final pendingDeepLinkManifestProvider = StateProvider<String?>((ref) => null);

/// Live download progress (`0.0..1.0`) keyed by `InstalledCs3Plugin.uid`
/// while `.cs3` archives are downloading & loading on Android.
final cs3InstallProgressProvider =
    StateProvider<Map<String, double>>((ref) => const {});

/// Live 1-tap repository batch install progress keyed by repo ID.
class RepoInstallProgress {
  const RepoInstallProgress({
    required this.repoId,
    required this.stage,
    this.completed = 0,
    this.total = 0,
    this.loaded = 0,
    this.failed = 0,
  });

  final String repoId;
  final String stage; // 'indexing' | 'installing'
  final int completed;
  final int total;
  final int loaded;
  final int failed;

  double get fraction => total > 0 ? (completed / total).clamp(0.0, 1.0) : 0.12;
}

final repoInstallProgressProvider =
    StateProvider<Map<String, RepoInstallProgress>>((ref) => const {});

class AddonsController extends AsyncNotifier<AddonsStoreState> {
  static const _launcherChannel = MethodChannel('openflix/launcher');

  bool _deepLinkInitialized = false;
  bool _savedPluginsBootstrapped = false;
  final Set<String> _activeRepoInstalls = <String>{};

  AddonsStorage get _storage => ref.read(addonsStorageProvider);
  StremioAddonService get _stremioService =>
      ref.read(stremioAddonServiceProvider);
  CloudStreamRepoService get _csRepoService =>
      ref.read(cloudStreamRepoServiceProvider);
  CloudStreamEngine get _csEngine => ref.read(cloudStreamEngineProvider);

  @override
  Future<AddonsStoreState> build() async {
    _initDeepLinkListener();
    final rawLoaded = await _storage.load();
    // Clear any stale in-flight downloading/loading states left over from an
    // interrupted install or app restart so no plugin stays stuck forever.
    final hasInterrupted = rawLoaded.installedCs3Plugins.any(
      (p) => p.loadStatus == Cs3LoadStatus.downloading,
    );
    final loaded = hasInterrupted
        ? rawLoaded.copyWith(
            installedCs3Plugins: [
              for (final p in rawLoaded.installedCs3Plugins)
                if (p.loadStatus == Cs3LoadStatus.downloading)
                  p.copyWith(
                    loadStatus: Cs3LoadStatus.failed,
                    lastError: p.lastError ?? 'Interrupted — tap to retry',
                  )
                else
                  p,
            ],
          )
        : rawLoaded;
    if (hasInterrupted) {
      unawaited(_storage.save(loaded));
    }
    if (!_savedPluginsBootstrapped && loaded.installedCs3Plugins.isNotEmpty) {
      _savedPluginsBootstrapped = true;
      unawaited(_bootstrapSavedCs3Plugins(loaded));
    }
    return loaded;
  }

  void _initDeepLinkListener() {
    if (_deepLinkInitialized) return;
    _deepLinkInitialized = true;
    if (!Platform.isAndroid) return;

    _launcherChannel.setMethodCallHandler((call) async {
      if (call.method == 'onDeepLink') {
        final raw = call.arguments?.toString();
        _handleIncomingDeepLink(raw);
      }
    });

    unawaited(() async {
      try {
        final initial =
            await _launcherChannel.invokeMethod<String>('getInitialDeepLink');
        _handleIncomingDeepLink(initial);
      } catch (_) {}
    }());
  }

  void _handleIncomingDeepLink(String? raw) {
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final normalized = StremioAddonService.normalizeManifestUrl(raw);
      ref.read(pendingDeepLinkManifestProvider.notifier).state = normalized;
    } catch (_) {}
  }

  void clearPendingDeepLink() {
    ref.read(pendingDeepLinkManifestProvider.notifier).state = null;
  }

  Future<void> _bootstrapSavedCs3Plugins(AddonsStoreState snapshot) async {
    final outcomes =
        await _csEngine.loadSavedPlugins(snapshot.installedCs3Plugins);
    if (outcomes.isEmpty) return;

    final current = state.valueOrNull ?? snapshot;
    final nextPlugins = [
      for (final p in current.installedCs3Plugins)
        if (outcomes.containsKey(p.uid))
          p.copyWith(
            loadStatus: outcomes[p.uid]!.status,
            localFilePath: outcomes[p.uid]!.localFilePath ?? p.localFilePath,
            registeredProviderNames: outcomes[p.uid]!.providers,
            lastError: outcomes[p.uid]!.error,
            clearError: outcomes[p.uid]!.error == null,
          )
        else
          p,
    ];
    await _persist(current.copyWith(installedCs3Plugins: nextPlugins));
  }

  Future<void> _persist(AddonsStoreState next) async {
    state = AsyncData(next);
    await _storage.save(next);
  }

  Future<void> acceptSafetyNotice() async {
    final current = state.valueOrNull ?? const AddonsStoreState();
    if (current.safetyAccepted) return;
    await _persist(current.copyWith(safetyAccepted: true));
  }

  Future<void> setShowNsfw(bool show) async {
    final current = state.valueOrNull ?? const AddonsStoreState();
    if (current.showNsfw == show) return;
    await _persist(current.copyWith(showNsfw: show));
  }

  Future<bool> openExternalUrl(String url) async {
    try {
      final ok = await _launcherChannel.invokeMethod<bool>(
        'openUrl',
        {'url': url},
      );
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Stremio v3 Addons
  // ───────────────────────────────────────────────────────────────────────────

  Future<({String manifestUrl, ManifestModel manifest})> previewStremioManifest(
    String rawInput, {
    CancelToken? cancelToken,
  }) async {
    final normalized = StremioAddonService.normalizeManifestUrl(rawInput);
    final manifest =
        await _stremioService.fetchManifest(normalized, cancelToken: cancelToken);
    return (manifestUrl: normalized, manifest: manifest);
  }

  Future<InstalledStremioAddon> installOrUpdateStremioAddon({
    required String manifestUrl,
    required ManifestModel manifest,
    List<CatalogPlacement>? placements,
    Set<AddonTargetScreen>? quickTargetOverride,
    CatalogShelfPosition position = CatalogShelfPosition.belowBuiltIn,
    bool includeInSearch = true,
    bool isOfficial = false,
  }) async {
    final current = state.valueOrNull ?? const AddonsStoreState();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final normalized = StremioAddonService.normalizeManifestUrl(manifestUrl);
    final baseUrl = StremioAddonService.deriveBaseUrl(normalized);

    final resolvedPlacements = placements ??
        StremioAddonService.defaultPlacementsForManifest(
          manifest,
          userOverride: quickTargetOverride,
          position: position,
        );

    final existingIdx =
        current.stremioAddons.indexWhere((a) => a.id == manifest.id);
    final existing = existingIdx >= 0 ? current.stremioAddons[existingIdx] : null;

    final entry = InstalledStremioAddon(
      id: manifest.id,
      manifestUrl: normalized,
      baseUrl: baseUrl,
      manifest: manifest,
      enabled: existing?.enabled ?? true,
      orderIndex: existing?.orderIndex ?? current.stremioAddons.length,
      isOfficial: isOfficial || (existing?.isOfficial ?? false),
      includeInSearch: includeInSearch,
      catalogPlacements: resolvedPlacements,
      installedAtMs: existing?.installedAtMs ?? nowMs,
      lastUpdatedAtMs: nowMs,
    );

    final updatedList = [
      for (final a in current.stremioAddons)
        if (a.id != entry.id) a,
    ];
    if (existingIdx >= 0) {
      updatedList.insert(existingIdx.clamp(0, updatedList.length), entry);
    } else {
      updatedList.insert(0, entry);
    }

    await _persist(current.copyWith(stremioAddons: updatedList));
    return entry;
  }

  Future<void> updateStremioAddonPlacement({
    required String addonId,
    required List<CatalogPlacement> placements,
    required bool includeInSearch,
  }) async {
    final current = state.valueOrNull ?? const AddonsStoreState();
    final nextList = [
      for (final a in current.stremioAddons)
        if (a.id == addonId)
          a.copyWith(
            catalogPlacements: placements,
            includeInSearch: includeInSearch,
            lastUpdatedAtMs: DateTime.now().millisecondsSinceEpoch,
          )
        else
          a,
    ];
    await _persist(current.copyWith(stremioAddons: nextList));
  }

  Future<void> toggleStremioAddon(String addonId, bool enabled) async {
    final current = state.valueOrNull ?? const AddonsStoreState();
    final nextList = [
      for (final a in current.stremioAddons)
        if (a.id == addonId) a.copyWith(enabled: enabled) else a,
    ];
    await _persist(current.copyWith(stremioAddons: nextList));
  }

  Future<void> reorderStremioAddons(int oldIndex, int newIndex) async {
    final current = state.valueOrNull ?? const AddonsStoreState();
    final list = [...current.stremioAddons];
    if (oldIndex < 0 || oldIndex >= list.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    final item = list.removeAt(oldIndex);
    list.insert(newIndex.clamp(0, list.length), item);
    final reindexed = [
      for (var i = 0; i < list.length; i++) list[i].copyWith(orderIndex: i),
    ];
    await _persist(current.copyWith(stremioAddons: reindexed));
  }

  Future<void> refreshStremioManifest(String addonId) async {
    final current = state.valueOrNull ?? const AddonsStoreState();
    final existing =
        current.stremioAddons.where((a) => a.id == addonId).firstOrNull;
    if (existing == null) return;

    final fresh = await _stremioService.fetchManifest(existing.manifestUrl);
    // Preserve user's existing per-catalog placements where catalog keys still match.
    final prevByKey = {
      for (final p in existing.catalogPlacements) p.catalogKey: p,
    };
    final defaults = StremioAddonService.defaultPlacementsForManifest(fresh);
    final mergedPlacements = [
      for (final d in defaults) prevByKey[d.catalogKey] ?? d,
    ];

    final nextList = [
      for (final a in current.stremioAddons)
        if (a.id == addonId)
          a.copyWith(
            manifest: fresh,
            catalogPlacements: mergedPlacements,
            lastUpdatedAtMs: DateTime.now().millisecondsSinceEpoch,
          )
        else
          a,
    ];
    await _persist(current.copyWith(stremioAddons: nextList));
  }

  Future<void> removeStremioAddon(String addonId) async {
    final current = state.valueOrNull ?? const AddonsStoreState();
    final nextList =
        current.stremioAddons.where((a) => a.id != addonId).toList();
    await _persist(current.copyWith(stremioAddons: nextList));
  }

  // ───────────────────────────────────────────────────────────────────────────
  // CloudStream 3 Repositories & .cs3 Plugins
  // ───────────────────────────────────────────────────────────────────────────

  Future<AddedCloudStreamRepo> addOrRefreshCloudStreamRepo(
    String inputOrUrl, {
    OfficialCloudStreamRepoEntry? official,
    CancelToken? cancelToken,
  }) async {
    final repo = await _csRepoService.fetchRepoIndex(
      inputOrUrl,
      official: official,
      cancelToken: cancelToken,
    );
    final current = state.valueOrNull ?? const AddonsStoreState();
    final existingIdx =
        current.cloudStreamRepos.indexWhere((r) => r.id == repo.id);
    final nextRepos = [...current.cloudStreamRepos];
    if (existingIdx >= 0) {
      nextRepos[existingIdx] = repo;
    } else {
      nextRepos.add(repo);
    }
    await _persist(current.copyWith(cloudStreamRepos: nextRepos));
    return repo;
  }

  Future<void> removeCloudStreamRepo(String repoId) async {
    final current = state.valueOrNull ?? const AddonsStoreState();
    final toRemove = current.installedCs3Plugins
        .where((p) => p.repoId == repoId)
        .toList();
    for (final p in toRemove) {
      await _csEngine.uninstallPlugin(p.uid, localFilePath: p.localFilePath);
    }
    await _persist(
      current.copyWith(
        cloudStreamRepos:
            current.cloudStreamRepos.where((r) => r.id != repoId).toList(),
        installedCs3Plugins:
            current.installedCs3Plugins.where((p) => p.repoId != repoId).toList(),
      ),
    );
  }

  Future<InstalledCs3Plugin> installCs3Plugin(
    String repoId,
    Cs3PluginMeta pluginMeta, {
    bool persist = true,
  }) async {
    final uid = InstalledCs3Plugin.makeUid(repoId, pluginMeta.internalName);

    // Mark downloading in both store state and live progress map.
    _setProgress(uid, 0.2);
    final pendingEntry = InstalledCs3Plugin(
      uid: uid,
      repoId: repoId,
      internalName: pluginMeta.internalName,
      name: pluginMeta.name,
      downloadUrl: pluginMeta.url,
      version: pluginMeta.version,
      apiVersion: pluginMeta.apiVersion,
      tvTypes: pluginMeta.tvTypes,
      language: pluginMeta.language,
      iconUrl: pluginMeta.iconUrl,
      fileSize: pluginMeta.fileSize,
      fileHash: pluginMeta.fileHash,
      enabled: true,
      loadStatus: Cs3LoadStatus.downloading,
    );
    await _upsertCs3Plugin(pendingEntry, persist: persist);

    _setProgress(uid, 0.55);
    Cs3InstallOutcome outcome;
    try {
      outcome = await _csEngine
          .installPlugin(
            uid: uid,
            repoId: repoId,
            internalName: pluginMeta.internalName,
            downloadUrl: pluginMeta.url,
            expectedSha256: pluginMeta.fileHash,
            enabled: true,
          )
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      outcome = Cs3InstallOutcome(
        status: Cs3LoadStatus.failed,
        error: e.toString().replaceFirst('Exception: ', ''),
      );
    }
    _setProgress(uid, 1.0);

    final finalized = pendingEntry.copyWith(
      localFilePath: outcome.localFilePath,
      loadStatus: outcome.status,
      lastError: outcome.error,
      clearError: outcome.error == null,
      registeredProviderNames: outcome.providers,
    );
    await _upsertCs3Plugin(finalized, persist: persist);
    _clearProgress(uid);
    return finalized;
  }

  /// 1-tap complete repository install: fetches & indexes `repo.json` +
  /// `plugins.json`, then downloads and loads all working `.cs3` providers
  /// concurrently so the repository is immediately ready for streaming.
  Future<({
    AddedCloudStreamRepo repo,
    int loadedCount,
    int failedCount,
    int totalCount,
  })> installCloudStreamRepoComplete(
    String inputOrUrl, {
    OfficialCloudStreamRepoEntry? official,
    CancelToken? cancelToken,
  }) async {
    final progressKey = official?.id ?? inputOrUrl;
    _setRepoProgress(
      progressKey,
      RepoInstallProgress(repoId: progressKey, stage: 'indexing'),
    );
    try {
      final repo = await addOrRefreshCloudStreamRepo(
        inputOrUrl,
        official: official,
        cancelToken: cancelToken,
      );
      if (progressKey != repo.id) {
        _clearRepoProgress(progressKey);
      }
      final summary = await installAllWorkingPlugins(repo.id);
      return (
        repo: repo,
        loadedCount: summary.loaded,
        failedCount: summary.failed,
        totalCount: summary.total,
      );
    } catch (_) {
      _clearRepoProgress(progressKey);
      rethrow;
    }
  }

  Future<({int loaded, int failed, int total})> installAllWorkingPlugins(
    String repoId,
  ) async {
    if (_activeRepoInstalls.contains(repoId)) {
      final current = state.valueOrNull ?? const AddonsStoreState();
      final active = current.installedCs3Plugins
          .where((p) => p.repoId == repoId && p.loadStatus == Cs3LoadStatus.loaded)
          .length;
      return (loaded: active, failed: 0, total: active);
    }
    _activeRepoInstalls.add(repoId);

    try {
      final current = state.valueOrNull ?? const AddonsStoreState();
      final repo =
          current.cloudStreamRepos.where((r) => r.id == repoId).firstOrNull;
      if (repo == null) return (loaded: 0, failed: 0, total: 0);

      final installedLoadedUids = {
        for (final p in current.installedCs3Plugins)
          if (p.loadStatus == Cs3LoadStatus.loaded) p.uid,
      };

      final candidates = repo.plugins.where((p) {
        if (!p.isWorking) return false;
        if (p.isNsfw && !current.showNsfw) return false;
        final uid = InstalledCs3Plugin.makeUid(repoId, p.internalName);
        return !installedLoadedUids.contains(uid);
      }).toList();

      final alreadyLoadedInRepo = current.installedCs3Plugins
          .where(
            (p) => p.repoId == repoId && p.loadStatus == Cs3LoadStatus.loaded,
          )
          .length;

      if (candidates.isEmpty) {
        return (
          loaded: alreadyLoadedInRepo,
          failed: 0,
          total: alreadyLoadedInRepo,
        );
      }

      var completed = 0;
      var loaded = alreadyLoadedInRepo;
      var failed = 0;
      final total = candidates.length;

      _setRepoProgress(
        repoId,
        RepoInstallProgress(
          repoId: repoId,
          stage: 'installing',
          completed: 0,
          total: total,
          loaded: loaded,
          failed: 0,
        ),
      );

      // Run up to 4 concurrent native .cs3 downloads + loads with coalesced
      // state updates and periodic persistence (no file-rename races).
      var cursor = 0;
      Future<void> worker() async {
        while (true) {
          if (cursor >= candidates.length) return;
          final plugin = candidates[cursor++];
          final result = await installCs3Plugin(
            repoId,
            plugin,
            persist: false,
          );
          completed++;
          if (result.loadStatus == Cs3LoadStatus.loaded) {
            loaded++;
          } else {
            failed++;
          }
          _setRepoProgress(
            repoId,
            RepoInstallProgress(
              repoId: repoId,
              stage: 'installing',
              completed: completed,
              total: total,
              loaded: loaded,
              failed: failed,
            ),
          );
          if (completed % 4 == 0) {
            final snap = state.valueOrNull;
            if (snap != null) {
              unawaited(_storage.save(snap));
            }
          }
        }
      }

      final concurrency = candidates.length < 4 ? candidates.length : 4;
      await Future.wait([for (var i = 0; i < concurrency; i++) worker()]);

      final finalState = state.valueOrNull;
      if (finalState != null) {
        await _storage.save(finalState);
      }
      return (
        loaded: loaded,
        failed: failed,
        total: alreadyLoadedInRepo + total,
      );
    } finally {
      _activeRepoInstalls.remove(repoId);
      _clearRepoProgress(repoId);
    }
  }

  Future<void> toggleCs3Plugin(String uid, bool enabled) async {
    await _csEngine.setPluginEnabled(uid, enabled);
    final current = state.valueOrNull ?? const AddonsStoreState();
    final nextPlugins = [
      for (final p in current.installedCs3Plugins)
        if (p.uid == uid) p.copyWith(enabled: enabled) else p,
    ];
    await _persist(current.copyWith(installedCs3Plugins: nextPlugins));
  }

  Future<void> uninstallCs3Plugin(String uid) async {
    final current = state.valueOrNull ?? const AddonsStoreState();
    final target =
        current.installedCs3Plugins.where((p) => p.uid == uid).firstOrNull;
    if (target != null) {
      await _csEngine.uninstallPlugin(
        uid,
        localFilePath: target.localFilePath,
      );
    }
    await _persist(
      current.copyWith(
        installedCs3Plugins:
            current.installedCs3Plugins.where((p) => p.uid != uid).toList(),
      ),
    );
  }

  Future<void> refreshAllAddons() async {
    final current = state.valueOrNull ?? const AddonsStoreState();
    for (final stremio in current.stremioAddons) {
      try {
        await refreshStremioManifest(stremio.id);
      } catch (e) {
        debugPrint('Refresh Stremio ${stremio.id} failed: $e');
      }
    }
    for (final repo in current.cloudStreamRepos) {
      try {
        final official = kOfficialCloudStreamRepos
            .where((o) => o.id == repo.id)
            .firstOrNull;
        await addOrRefreshCloudStreamRepo(repo.repoUrl, official: official);
      } catch (e) {
        debugPrint('Refresh CS3 repo ${repo.id} failed: $e');
      }
    }
  }

  Future<void> _upsertCs3Plugin(
    InstalledCs3Plugin plugin, {
    bool persist = true,
  }) async {
    final base = state.valueOrNull ?? const AddonsStoreState();
    final nextList = [
      for (final p in base.installedCs3Plugins)
        if (p.uid == plugin.uid) plugin else p,
    ];
    if (!base.installedCs3Plugins.any((p) => p.uid == plugin.uid)) {
      nextList.add(plugin);
    }
    final next = base.copyWith(installedCs3Plugins: nextList);
    state = AsyncData(next);
    if (persist) {
      await _storage.save(next);
    }
  }

  void _setProgress(String uid, double value) {
    final map = {...ref.read(cs3InstallProgressProvider)};
    map[uid] = value;
    ref.read(cs3InstallProgressProvider.notifier).state = map;
  }

  void _clearProgress(String uid) {
    final map = {...ref.read(cs3InstallProgressProvider)}..remove(uid);
    ref.read(cs3InstallProgressProvider.notifier).state = map;
  }

  void _setRepoProgress(String key, RepoInstallProgress progress) {
    final map = {...ref.read(repoInstallProgressProvider)};
    map[key] = progress;
    ref.read(repoInstallProgressProvider.notifier).state = map;
  }

  void _clearRepoProgress(String key) {
    final map = {...ref.read(repoInstallProgressProvider)}..remove(key);
    ref.read(repoInstallProgressProvider.notifier).state = map;
  }
}

final addonsControllerProvider =
    AsyncNotifierProvider<AddonsController, AddonsStoreState>(
  AddonsController.new,
);

AddonTargetScreen targetScreenForHomeFilter(HomeFilter f) => switch (f) {
      HomeFilter.home => AddonTargetScreen.home,
      HomeFilter.movies => AddonTargetScreen.movies,
      HomeFilter.tvShows => AddonTargetScreen.tvShows,
      HomeFilter.anime => AddonTargetScreen.anime,
      HomeFilter.categories => AddonTargetScreen.categories,
    };

/// Returns all enabled custom Stremio catalog rows assigned to [filter], split
/// into `above` (pinned to top) and `below` (after built-in shelves).
final customCatalogsForFilterProvider = Provider.family<
    ({List<CustomCatalogEntry> above, List<CustomCatalogEntry> below}),
    HomeFilter>((ref, filter) {
  final store = ref.watch(addonsControllerProvider).valueOrNull;
  if (store == null || store.stremioAddons.isEmpty) {
    return (above: const [], below: const []);
  }

  final targetScreen = targetScreenForHomeFilter(filter);
  final above = <CustomCatalogEntry>[];
  final below = <CustomCatalogEntry>[];

  final sortedAddons = [...store.stremioAddons]
    ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

  for (final addon in sortedAddons) {
    if (!addon.enabled) continue;
    for (final cat in addon.manifest.catalogs) {
      if (cat.hasRequiredExtra) continue;
      final placement = addon.placementFor(cat);
      if (placement == null || !placement.enabled) continue;
      if (!placement.targetScreens.contains(targetScreen)) continue;

      final namespaced = cat.copyWithAddon(
        addon.id,
        addon.manifest.name,
        customName: placement.customTitle,
      );
      final entry = CustomCatalogEntry(
        addon: addon,
        catalog: namespaced,
        placement: placement,
      );
      if (placement.position == CatalogShelfPosition.aboveBuiltIn) {
        above.add(entry);
      } else {
        below.add(entry);
      }
    }
  }

  return (above: above, below: below);
});

final enabledSearchStremioAddonsProvider =
    Provider<List<InstalledStremioAddon>>((ref) {
  final store = ref.watch(addonsControllerProvider).valueOrNull;
  if (store == null) return const [];
  return store.stremioAddons
      .where(
        (a) =>
            a.enabled &&
            a.includeInSearch &&
            a.manifest.catalogs.any((c) => c.supportsSearch),
      )
      .toList();
});

final hasAnyStreamSourceProvider = Provider<bool>((ref) {
  final store = ref.watch(addonsControllerProvider).valueOrNull;
  return store?.hasAnyStreamSource ?? false;
});

final installedAddonsCountProvider = Provider<int>((ref) {
  final store = ref.watch(addonsControllerProvider).valueOrNull;
  return store?.totalInstalledEntryCount ?? 0;
});
