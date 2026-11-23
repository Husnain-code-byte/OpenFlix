import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/user_error.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../home/data/models/manifest_model.dart';
import '../../../home/presentation/widgets/pixel_bottom_nav.dart';
import '../../data/official_addons_registry.dart';
import '../../data/stremio_addon_service.dart';
import '../../domain/models/addon_models.dart';
import '../controllers/addons_controller.dart';
import '../models/addons_ui_models.dart';
import '../widgets/add_addon_composer_card.dart';
import '../widgets/addon_cards.dart';
import '../widgets/addon_sheets.dart';
import '../widgets/addons_ui_kit.dart';

enum _AddonsMainTab { added, official }

enum _OfficialArchitectureFilter { all, cloudstream, stremio }

/// Addons management & discovery screen opened from Profile (`My OpenFlix`) or
/// an incoming `stremio://` deep link.
class AddonsScreen extends ConsumerStatefulWidget {
  const AddonsScreen({super.key});

  static bool get isAnyMounted => _AddonsScreenState._mountedCount > 0;

  @override
  ConsumerState<AddonsScreen> createState() => _AddonsScreenState();
}

class _AddonsScreenState extends ConsumerState<AddonsScreen> {
  static int _mountedCount = 0;

  final TextEditingController _urlController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  _AddonsMainTab _selectedTab = _AddonsMainTab.added;
  _OfficialArchitectureFilter _officialFilter = _OfficialArchitectureFilter.all;

  Set<AddonTargetScreen> _composerTargets = const {};
  AddonButtonPhase _composerPhase = AddonButtonPhase.idle;
  int _composerShakeTrigger = 0;
  String? _composerErrorText;

  bool _refreshingAll = false;
  bool _handlingDeepLink = false;
  final Set<String> _removingIds = <String>{};
  final Set<String> _refreshingAddonIds = <String>{};

  @override
  void initState() {
    super.initState();
    _mountedCount++;
    _urlController.addListener(_clearComposerErrorOnEdit);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final pending = ref.read(pendingDeepLinkManifestProvider);
      if (pending != null && pending.trim().isNotEmpty) {
        unawaited(_consumeDeepLink(pending));
      }
    });
  }

  void _clearComposerErrorOnEdit() {
    if (_composerErrorText != null && _urlController.text.trim().isNotEmpty) {
      setState(() => _composerErrorText = null);
    }
  }

  @override
  void dispose() {
    _mountedCount = (_mountedCount - 1).clamp(0, 1 << 20);
    _urlController
      ..removeListener(_clearComposerErrorOnEdit)
      ..dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<bool> _ensureSafetyAccepted(
    AddonsStoreState store, {
    required String targetName,
    required bool isCloudStream,
  }) async {
    if (store.safetyAccepted) return true;
    final accepted = await showAddonsSheet<bool>(
      context,
      builder: (_) => AddonSafetyNoticeSheet(
        targetName: targetName,
        isCloudStream: isCloudStream,
      ),
    );
    if (accepted == true && mounted) {
      await ref.read(addonsControllerProvider.notifier).acceptSafetyNotice();
      return true;
    }
    return false;
  }

  void _toggleComposerTarget(AddonTargetScreen target) {
    setState(() {
      if (_composerTargets.contains(target)) {
        _composerTargets = {..._composerTargets}..remove(target);
      } else {
        _composerTargets = {..._composerTargets, target};
      }
    });
  }

  Future<void> _consumeDeepLink(String rawUrl) async {
    if (_handlingDeepLink) return;
    _handlingDeepLink = true;
    final controller = ref.read(addonsControllerProvider.notifier);
    controller.clearPendingDeepLink();
    try {
      final store =
          await ref.read(addonsControllerProvider.future);
      if (!mounted) return;
      final ok = await _ensureSafetyAccepted(
        store,
        targetName: rawUrl,
        isCloudStream: false,
      );
      if (!ok || !mounted) return;

      showAddonsToast(context, 'Loading configured Stremio manifest...');
      final preview = await controller.previewStremioManifest(rawUrl);
      if (!mounted) return;
      await _openStremioInstallSheet(
        manifestUrl: preview.manifestUrl,
        manifest: preview.manifest,
        isOfficial: false,
      );
    } catch (e) {
      if (mounted) {
        final mapped = UserError.from(e, logTag: 'AddonsScreen.deepLink');
        showAddonsToast(
          context,
          mapped.type == UserErrorType.offline
              ? mapped.title
              : "Couldn't load that addon link. Please try again.",
          isError: true,
        );
      }
    } finally {
      _handlingDeepLink = false;
    }
  }

  Future<void> _handleComposerSubmit(AddonsStoreState store) async {
    FocusScope.of(context).unfocus();
    final raw = _urlController.text.trim();
    final detected = DetectedAddonInputUi.analyze(raw);

    if (detected.kind == DetectedInputKindUi.empty ||
        detected.kind == DetectedInputKindUi.invalid) {
      addonHaptic(AddonHaptic.medium);
      setState(() {
        _composerShakeTrigger++;
        _composerErrorText = detected.kind == DetectedInputKindUi.empty
            ? 'Paste a Stremio manifest.json URL, CloudStream repo.json URL, or shortcode first.'
            : 'Invalid URL format. Use https://.../manifest.json, a GitHub repo.json link, or a shortcode.';
      });
      return;
    }

    final isCs3 = detected.kind == DetectedInputKindUi.cloudStreamRepoJson ||
        detected.kind == DetectedInputKindUi.cloudStreamShortcode;

    final ok = await _ensureSafetyAccepted(
      store,
      targetName: raw,
      isCloudStream: isCs3,
    );
    if (!ok || !mounted) return;

    setState(() {
      _composerErrorText = null;
      _composerPhase = AddonButtonPhase.loading;
    });

    final controller = ref.read(addonsControllerProvider.notifier);

    try {
      if (isCs3) {
        final official = kOfficialCloudStreamRepos
            .where((o) =>
                o.shortcode.toLowerCase() == raw.toLowerCase() ||
                o.repoUrl.toLowerCase() == raw.toLowerCase())
            .firstOrNull;
        final summary = await controller.installCloudStreamRepoComplete(
          raw,
          official: official,
        );
        if (!mounted) return;
        setState(() {
          _composerPhase = AddonButtonPhase.success;
          _selectedTab = _AddonsMainTab.added;
        });
        showAddonsToast(
          context,
          summary.failedCount == 0
              ? '${summary.repo.name} added · ${summary.loadedCount} providers ready'
              : '${summary.repo.name} added · ${summary.loadedCount} active (${summary.failedCount} skipped)',
        );
        await Future<void>.delayed(
          AddonsMotion.d(context, const Duration(milliseconds: 420)),
        );
        if (!mounted) return;
        setState(() {
          _composerPhase = AddonButtonPhase.idle;
          _urlController.clear();
        });
        return;
      }

      // Stremio manifest v3 install flow
      final preview = await controller.previewStremioManifest(raw);
      if (!mounted) return;

      // If provider requires web /configure first, open the configure sheet;
      // otherwise install immediately in 1 tap with the composer's selected screens.
      if (preview.manifest.behaviorHints.configurationRequired) {
        setState(() => _composerPhase = AddonButtonPhase.idle);
        final installed = await _openStremioInstallSheet(
          manifestUrl: preview.manifestUrl,
          manifest: preview.manifest,
          overrideTargets: {..._composerTargets},
          isOfficial: false,
        );
        if (installed && mounted) {
          setState(() {
            _composerPhase = AddonButtonPhase.success;
            _selectedTab = _AddonsMainTab.added;
          });
          await Future<void>.delayed(
            AddonsMotion.d(context, const Duration(milliseconds: 420)),
          );
          if (!mounted) return;
          setState(() {
            _composerPhase = AddonButtonPhase.idle;
            _urlController.clear();
          });
        }
        return;
      }

      final installed = await controller.installOrUpdateStremioAddon(
        manifestUrl: preview.manifestUrl,
        manifest: preview.manifest,
        quickTargetOverride:
            preview.manifest.catalogs.isEmpty ? const {} : {..._composerTargets},
        isOfficial: false,
      );
      if (!mounted) return;
      final targets = installed.effectiveTargets;
      setState(() {
        _composerPhase = AddonButtonPhase.success;
        _selectedTab = _AddonsMainTab.added;
      });
      showAddonsToast(
        context,
        targets.isEmpty
            ? '${preview.manifest.name} added for Detail & Play'
            : '${preview.manifest.name} added to ${targets.map((e) => e.label).join(', ')}',
      );
      await Future<void>.delayed(
        AddonsMotion.d(context, const Duration(milliseconds: 420)),
      );
      if (!mounted) return;
      setState(() {
        _composerPhase = AddonButtonPhase.idle;
        _urlController.clear();
      });
    } catch (e) {
      if (!mounted) return;
      final mapped = UserError.from(e, logTag: 'AddonsScreen.composer');
      addonHaptic(AddonHaptic.medium);
      setState(() {
        _composerPhase = AddonButtonPhase.idle;
        _composerShakeTrigger++;
        _composerErrorText = mapped.message;
      });
    }
  }

  Future<bool> _openStremioInstallSheet({
    required String manifestUrl,
    required ManifestModel manifest,
    Set<AddonTargetScreen>? overrideTargets,
    required bool isOfficial,
  }) async {
    final controller = ref.read(addonsControllerProvider.notifier);
    final initialPlacements =
        StremioAddonService.defaultPlacementsForManifest(
      manifest,
      userOverride: manifest.catalogs.isEmpty ? const {} : overrideTargets,
    );

    final result = await showAddonsSheet<StremioConfigureResult>(
      context,
      builder: (_) => StremioAddonConfigureSheet(
        manifest: manifest,
        manifestUrl: manifestUrl,
        initialPlacements: initialPlacements,
        isNewInstall: true,
        onOpenExternalConfigure: () => _openExternalConfigure(manifestUrl),
      ),
    );
    if (result == null || !mounted) return false;

    final installed = await controller.installOrUpdateStremioAddon(
      manifestUrl: manifestUrl,
      manifest: manifest,
      placements: result.placements,
      includeInSearch: result.includeInSearch,
      isOfficial: isOfficial,
    );
    if (!mounted) return true;

    final targets = installed.effectiveTargets;
    showAddonsToast(
      context,
      targets.isEmpty
          ? '${manifest.name} added for Detail & Play'
          : '${manifest.name} added to ${targets.map((e) => e.label).join(', ')}',
    );
    return true;
  }

  Future<void> _openConfigureForInstalledStremio(
    InstalledStremioAddon addon,
  ) async {
    final controller = ref.read(addonsControllerProvider.notifier);
    final result = await showAddonsSheet<StremioConfigureResult>(
      context,
      builder: (_) => StremioAddonConfigureSheet(
        manifest: addon.manifest,
        manifestUrl: addon.manifestUrl,
        initialPlacements: addon.catalogPlacements,
        initialIncludeInSearch: addon.includeInSearch,
        onOpenExternalConfigure: () =>
            _openExternalConfigure(addon.manifestUrl),
        onRefreshManifest: () => _refreshSingleStremio(addon),
      ),
    );
    if (result == null || !mounted) return;

    await controller.updateStremioAddonPlacement(
      addonId: addon.id,
      placements: result.placements,
      includeInSearch: result.includeInSearch,
    );
    if (!mounted) return;
    final union = {
      for (final p in result.placements)
        if (p.enabled) ...p.targetScreens,
    };
    showAddonsToast(
      context,
      union.isEmpty
          ? '${addon.manifest.name} set to Streaming Only'
          : '${addon.manifest.name} routed to ${union.map((e) => e.label).join(', ')}',
    );
  }

  Future<void> _openExternalConfigure(String manifestUrl) async {
    final configureUrl = StremioAddonService.deriveConfigureUrl(manifestUrl);
    final opened = await ref
        .read(addonsControllerProvider.notifier)
        .openExternalUrl(configureUrl);
    if (!mounted) return;
    if (!opened) {
      showAddonsToast(
        context,
        "Couldn't open your browser right now.",
        isError: true,
      );
    }
  }

  Future<void> _refreshSingleStremio(InstalledStremioAddon addon) async {
    setState(() => _refreshingAddonIds.add(addon.id));
    try {
      await ref
          .read(addonsControllerProvider.notifier)
          .refreshStremioManifest(addon.id);
      if (mounted) {
        showAddonsToast(context, 'Refreshed ${addon.manifest.name}');
      }
    } catch (e) {
      if (mounted) {
        final mapped = UserError.from(e, logTag: 'AddonsScreen.refresh');
        showAddonsToast(
          context,
          mapped.type == UserErrorType.offline
              ? mapped.title
              : "Couldn't refresh ${addon.manifest.name}.",
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _refreshingAddonIds.remove(addon.id));
    }
  }

  Future<void> _removeStremioAddon(InstalledStremioAddon addon) async {
    setState(() => _removingIds.add(addon.id));
    await Future<void>.delayed(
      AddonsMotion.d(context, const Duration(milliseconds: 240)),
    );
    await ref
        .read(addonsControllerProvider.notifier)
        .removeStremioAddon(addon.id);
    if (!mounted) return;
    setState(() => _removingIds.remove(addon.id));
    showAddonsToast(context, 'Removed ${addon.manifest.name}');
  }

  Future<void> _removeCloudStreamRepo(AddedCloudStreamRepo repo) async {
    setState(() => _removingIds.add(repo.id));
    await Future<void>.delayed(
      AddonsMotion.d(context, const Duration(milliseconds: 240)),
    );
    await ref
        .read(addonsControllerProvider.notifier)
        .removeCloudStreamRepo(repo.id);
    if (!mounted) return;
    setState(() => _removingIds.remove(repo.id));
    showAddonsToast(context, 'Removed ${repo.name}');
  }

  Future<void> _handleTapOfficialCloudStreamRepo(
    AddonsStoreState store,
    OfficialCloudStreamRepoEntry entry,
    AddedCloudStreamRepo? existingRepo,
    int activePluginCount,
  ) async {
    final ok = await _ensureSafetyAccepted(
      store,
      targetName: entry.name,
      isCloudStream: true,
    );
    if (!ok || !mounted) return;

    // Already fully installed -> open optional manager sheet; otherwise
    // finish installing any remaining/failed providers in 1 tap.
    if (existingRepo != null) {
      final workingCount = existingRepo.plugins
          .where((p) => p.isWorking && (!p.isNsfw || store.showNsfw))
          .length;
      final loadedCount = store.installedCs3Plugins
          .where(
            (p) =>
                p.repoId == existingRepo.id &&
                p.loadStatus == Cs3LoadStatus.loaded,
          )
          .length;
      if (workingCount > 0 && loadedCount >= workingCount) {
        await _openCloudStreamRepoSheet(existingRepo.id);
        return;
      }
    }

    // 1-tap complete install: index repo + download & load all working providers
    try {
      final summary = await ref
          .read(addonsControllerProvider.notifier)
          .installCloudStreamRepoComplete(entry.repoUrl, official: entry);
      if (!mounted) return;
      if (summary.loadedCount > 0) {
        showAddonsToast(
          context,
          summary.failedCount == 0
              ? '${entry.name} installed · ${summary.loadedCount} providers active'
              : '${entry.name} installed · ${summary.loadedCount} active (${summary.failedCount} skipped)',
        );
      } else {
        showAddonsToast(
          context,
          '${entry.name} indexed (${summary.totalCount} checked, 0 active). Tap Manage Plugins for details.',
          isError: true,
        );
      }
    } catch (e) {
      if (!mounted) return;
      final mapped = UserError.from(e, logTag: 'AddonsScreen.installCs3');
      showAddonsToast(
        context,
        mapped.type == UserErrorType.offline
            ? mapped.title
            : "Couldn't install ${entry.name}. Please try again.",
        isError: true,
      );
    }
  }

  Future<void> _handleTapOfficialStremioAddon(
    AddonsStoreState store,
    OfficialStremioAddonEntry entry,
  ) async {
    final existing =
        store.stremioAddons.where((a) => a.id == entry.id).firstOrNull;
    if (existing != null) {
      await _openConfigureForInstalledStremio(existing);
      return;
    }
    final ok = await _ensureSafetyAccepted(
      store,
      targetName: entry.name,
      isCloudStream: false,
    );
    if (!ok || !mounted) return;

    try {
      final preview = await ref
          .read(addonsControllerProvider.notifier)
          .previewStremioManifest(entry.manifestUrl);
      if (!mounted) return;
      final added = await _openStremioInstallSheet(
        manifestUrl: preview.manifestUrl,
        manifest: preview.manifest,
        isOfficial: true,
      );
      if (added && mounted) {
        setState(() => _selectedTab = _AddonsMainTab.added);
      }
    } catch (e) {
      if (mounted) {
        final mapped = UserError.from(e, logTag: 'AddonsScreen.installStremio');
        showAddonsToast(
          context,
          mapped.type == UserErrorType.offline
              ? mapped.title
              : "Couldn't load ${entry.name}. Please try again.",
          isError: true,
        );
      }
    }
  }

  Future<void> _openCloudStreamRepoSheet(String repoId) async {
    await showAddonsSheet<void>(
      context,
      builder: (_) => CloudStreamRepoBrowserSheet(repoId: repoId),
    );
  }

  Future<void> _finishCloudStreamRepo(AddedCloudStreamRepo repo) async {
    final summary = await ref
        .read(addonsControllerProvider.notifier)
        .installAllWorkingPlugins(repo.id);
    if (!mounted) return;
    showAddonsToast(
      context,
      summary.failed == 0
          ? '${repo.name} · ${summary.loaded} providers ready'
          : '${repo.name} · ${summary.loaded} active (${summary.failed} failed)',
      isError: summary.loaded == 0,
    );
  }

  Future<void> _handleRefreshAll() async {
    if (_refreshingAll) return;
    setState(() => _refreshingAll = true);
    try {
      await ref.read(addonsControllerProvider.notifier).refreshAllAddons();
      if (mounted) showAddonsToast(context, 'Addons refreshed');
    } finally {
      if (mounted) setState(() => _refreshingAll = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);
    ref.listen<String?>(pendingDeepLinkManifestProvider, (prev, next) {
      if (next != null && next.trim().isNotEmpty && mounted) {
        unawaited(_consumeDeepLink(next));
      }
    });

    final storeAsync = ref.watch(addonsControllerProvider);
    final topInset = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: PixelBottomNav(
        current: PixelTab.profile,
        onChanged: (tab) {
          ref.read(activeTabProvider.notifier).state = tab;
          Navigator.of(context).popUntil((route) => route.isFirst);
        },
      ),
      body: ColoredBox(
        color: AddonsColors.canvas,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(height: topInset),
            AddonsPageHeader(
              title: 'Addons',
              onBack: () => Navigator.of(context).maybePop(),
              trailing: _refreshingAll
                  ? const SizedBox(
                      width: 32,
                      height: 32,
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AddonsColors.textPrimary,
                          ),
                        ),
                      ),
                    )
                  : AddonHeaderIconButton(
                      svg: AddonIcons.refresh,
                      label: 'Refresh Addons',
                      onTap: _handleRefreshAll,
                    ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: AddonsMotion.d(context, AddonsMotion.standard),
                switchInCurve: AddonsMotion.emphasized,
                switchOutCurve: AddonsMotion.emphasized,
                child: storeAsync.when(
                  loading: () =>
                      const _AddonsScreenSkeleton(key: ValueKey('skeleton')),
                  error: (err, _) => Padding(
                    key: const ValueKey('error'),
                    padding: const EdgeInsets.all(20),
                    child: AppStatusCard.fromError(
                      UserError.from(err, logTag: 'AddonsScreen.store'),
                      onAction: () => ref.invalidate(addonsControllerProvider),
                    ),
                  ),
                  data: (store) => _buildContent(context, store),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, AddonsStoreState store) {
    final officialTotalCount =
        kOfficialCloudStreamRepos.length + kOfficialStremioAddons.length;

    return ListView(
      key: const ValueKey('content'),
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
      children: [
        AddAddonComposerCard(
          controller: _urlController,
          selectedTargets: _composerTargets,
          onToggleTarget: _toggleComposerTarget,
          onClearTargets: () => setState(() => _composerTargets = const {}),
          onSelectAllTargets: () => setState(
            () => _composerTargets = AddonTargetScreen.values.toSet(),
          ),
          onSubmit: () => _handleComposerSubmit(store),
          phase: _composerPhase,
          shakeTrigger: _composerShakeTrigger,
          errorText: _composerErrorText,
        ),
        const SizedBox(height: 20),
        _AddonsTabBar(
          selectedTab: _selectedTab,
          addedCount: store.totalInstalledEntryCount,
          officialCount: officialTotalCount,
          onSelect: (tab) => setState(() => _selectedTab = tab),
        ),
        const SizedBox(height: 16),
        AnimatedSwitcher(
          duration: AddonsMotion.d(context, AddonsMotion.standard),
          switchInCurve: AddonsMotion.emphasized,
          switchOutCurve: AddonsMotion.emphasized,
          child: _selectedTab == _AddonsMainTab.added
              ? _buildAddedTab(context, store)
              : _buildOfficialTab(context, store),
        ),
      ],
    );
  }

  Widget _buildAddedTab(BuildContext context, AddonsStoreState store) {
    final sortedStremio = [...store.stremioAddons]
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    final repos = store.cloudStreamRepos;

    if (sortedStremio.isEmpty && repos.isEmpty) {
      return AddonsStateCard(
        key: const ValueKey('added-empty'),
        iconSvg: AddonIcons.puzzle,
        title: 'No Addons Yet',
        body: 'Paste a manifest or repo link above, or pick from Official.',
        actionLabel: 'Browse Official',
        actionIconSvg: AddonIcons.cloud,
        onAction: () => setState(() => _selectedTab = _AddonsMainTab.official),
      );
    }

    final controller = ref.read(addonsControllerProvider.notifier);
    final repoProgressMap = ref.watch(repoInstallProgressProvider);

    return Column(
      key: const ValueKey('added-list'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < sortedStremio.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          AddonStaggerIn(
            key: ValueKey<String>('stremio-${sortedStremio[i].id}'),
            index: i,
            child: AddonRemovable(
              removing: _removingIds.contains(sortedStremio[i].id),
              child: InstalledStremioAddonCard(
                addon: sortedStremio[i],
                isRefreshing:
                    _refreshingAddonIds.contains(sortedStremio[i].id),
                onToggleEnabled: (enabled) =>
                    controller.toggleStremioAddon(sortedStremio[i].id, enabled),
                onConfigure: () =>
                    _openConfigureForInstalledStremio(sortedStremio[i]),
                onRefresh: () => _refreshSingleStremio(sortedStremio[i]),
                onRemove: () => _removeStremioAddon(sortedStremio[i]),
                onMoveUp: sortedStremio.length > 1 && i > 0
                    ? () => controller.reorderStremioAddons(i, i - 1)
                    : null,
                onMoveDown: sortedStremio.length > 1 &&
                        i < sortedStremio.length - 1
                    ? () => controller.reorderStremioAddons(i, i + 2)
                    : null,
              ),
            ),
          ),
        ],
        for (var j = 0; j < repos.length; j++) ...[
          if (sortedStremio.isNotEmpty || j > 0) const SizedBox(height: 12),
          Builder(
            builder: (context) {
              final repo = repos[j];
              final plugins = store.installedCs3Plugins
                  .where((p) => p.repoId == repo.id)
                  .toList(growable: false);
              return AddonStaggerIn(
                key: ValueKey<String>('csrepo-${repo.id}'),
                index: sortedStremio.length + j,
                child: AddonRemovable(
                  removing: _removingIds.contains(repo.id),
                  child: InstalledCloudStreamRepoCard(
                    repo: repo,
                    plugins: plugins,
                    installProgress: repoProgressMap[repo.id],
                    onManagePlugins: () => _openCloudStreamRepoSheet(repo.id),
                    onInstallRemaining: () => _finishCloudStreamRepo(repo),
                    onTogglePluginEnabled: (uid, enabled) =>
                        controller.toggleCs3Plugin(uid, enabled),
                    onRemoveRepo: () => _removeCloudStreamRepo(repo),
                  ),
                ),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildOfficialTab(BuildContext context, AddonsStoreState store) {
    final showCs3 = _officialFilter == _OfficialArchitectureFilter.all ||
        _officialFilter == _OfficialArchitectureFilter.cloudstream;
    final showStremio = _officialFilter == _OfficialArchitectureFilter.all ||
        _officialFilter == _OfficialArchitectureFilter.stremio;

    final addedRepoById = {
      for (final r in store.cloudStreamRepos) r.id: r,
    };
    final repoProgressMap = ref.watch(repoInstallProgressProvider);

    return Column(
      key: ValueKey<String>('official-${_officialFilter.name}'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _ArchitectureFilterChip(
                label:
                    'All · ${kOfficialCloudStreamRepos.length + kOfficialStremioAddons.length}',
                selected: _officialFilter == _OfficialArchitectureFilter.all,
                onTap: () => setState(
                  () => _officialFilter = _OfficialArchitectureFilter.all,
                ),
              ),
              const SizedBox(width: 8),
              _ArchitectureFilterChip(
                label: 'CloudStream · ${kOfficialCloudStreamRepos.length}',
                iconSvg: AddonIcons.cloud,
                selected:
                    _officialFilter == _OfficialArchitectureFilter.cloudstream,
                onTap: () => setState(
                  () =>
                      _officialFilter = _OfficialArchitectureFilter.cloudstream,
                ),
              ),
              const SizedBox(width: 8),
              _ArchitectureFilterChip(
                label: 'Stremio · ${kOfficialStremioAddons.length}',
                iconSvg: AddonIcons.play,
                selected:
                    _officialFilter == _OfficialArchitectureFilter.stremio,
                onTap: () => setState(
                  () => _officialFilter = _OfficialArchitectureFilter.stremio,
                ),
              ),
            ],
          ),
        ),
        if (showCs3) ...[
          const SizedBox(height: 16),
          const AddonsSectionHeader(
            iconSvg: AddonIcons.cloud,
            title: 'CloudStream',
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < kOfficialCloudStreamRepos.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            Builder(
              builder: (context) {
                final entry = kOfficialCloudStreamRepos[i];
                final addedRepo = addedRepoById[entry.id];
                final installedPlugins = store.installedCs3Plugins
                    .where((p) => p.repoId == entry.id)
                    .toList(growable: false);
                final activeCount = installedPlugins
                    .where((p) => p.enabled && p.loadStatus == Cs3LoadStatus.loaded)
                    .length;
                return AddonStaggerIn(
                  index: i,
                  child: OfficialCloudStreamRepoCard(
                    entry: entry,
                    addedRepo: addedRepo,
                    installedPlugins: installedPlugins,
                    installProgress: repoProgressMap[entry.id],
                    onTap: () => _handleTapOfficialCloudStreamRepo(
                      store,
                      entry,
                      addedRepo,
                      activeCount,
                    ),
                    onCopyUrl: () {
                      Clipboard.setData(ClipboardData(text: entry.repoUrl));
                      showAddonsToast(
                        context,
                        'Copied ${entry.name} URL',
                      );
                    },
                  ),
                );
              },
            ),
          ],
        ],
        if (showStremio) ...[
          const SizedBox(height: 18),
          const AddonsSectionHeader(
            iconSvg: AddonIcons.play,
            title: 'Stremio',
          ),
          const SizedBox(height: 10),
          if (kOfficialStremioAddons.isEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AddonsColors.card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AddonsColors.hairline),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AddonsColors.canvas,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AddonsColors.hairline),
                    ),
                    child: const Center(
                      child: AddonIcon(
                        AddonIcons.play,
                        size: 16,
                        color: AddonsColors.textMuted,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Official Stremio',
                          style: AddonsText.inter(
                            14,
                            weight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Coming soon · Paste custom URL above',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AddonsText.inter(
                            11.5,
                            color: AddonsColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AddonPressable(
                    borderRadius: 999,
                    color: AddonsColors.tagFill,
                    borderColor: AddonsColors.hairlineStrong,
                    onTap: () => _scrollController.animateTo(
                      0,
                      duration: AddonsMotion.d(context, AddonsMotion.standard),
                      curve: AddonsMotion.emphasized,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const AddonIcon(
                            AddonIcons.link,
                            size: 11,
                            color: AddonsColors.textSecondary,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Paste',
                            style: AddonsText.inter(
                              11.5,
                              weight: FontWeight.w600,
                              color: AddonsColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            for (var i = 0; i < kOfficialStremioAddons.length; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              AddonStaggerIn(
                index: i,
                child: OfficialStremioAddonCard(
                  entry: kOfficialStremioAddons[i],
                  isInstalled: store.stremioAddons
                      .any((a) => a.id == kOfficialStremioAddons[i].id),
                  onInstall: () => _handleTapOfficialStremioAddon(
                    store,
                    kOfficialStremioAddons[i],
                  ),
                ),
              ),
            ],
        ],
      ],
    );
  }
}

class _AddonsTabBar extends StatelessWidget {
  const _AddonsTabBar({
    required this.selectedTab,
    required this.addedCount,
    required this.officialCount,
    required this.onSelect,
  });

  final _AddonsMainTab selectedTab;
  final int addedCount;
  final int officialCount;
  final ValueChanged<_AddonsMainTab> onSelect;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AddonsColors.divider)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 1),
        child: Row(
          children: [
            _TabItem(
              label: 'Added',
              count: addedCount,
              active: selectedTab == _AddonsMainTab.added,
              onTap: () => onSelect(_AddonsMainTab.added),
            ),
            const SizedBox(width: 24),
            _TabItem(
              label: 'Official',
              count: officialCount,
              active: selectedTab == _AddonsMainTab.official,
              onTap: () => onSelect(_AddonsMainTab.official),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final d = AddonsMotion.d(context, const Duration(milliseconds: 200));
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (active) return;
        addonHaptic(AddonHaptic.selection);
        onTap();
      },
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedDefaultTextStyle(
                  duration: d,
                  curve: Curves.easeOut,
                  style: AddonsText.inter(
                    16,
                    weight: FontWeight.w700,
                    color: active
                        ? AddonsColors.textPrimary
                        : AddonsColors.tabInactive,
                    height: 24 / 16,
                  ),
                  child: Text(label),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: active ? AddonsColors.badgeFill : AddonsColors.card,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: active
                          ? AddonsColors.hairlineStrong
                          : AddonsColors.hairline,
                    ),
                  ),
                  child: Text(
                    '$count',
                    style: AddonsText.inter(
                      10.5,
                      weight: FontWeight.w700,
                      color: active
                          ? AddonsColors.textPrimary
                          : AddonsColors.tabInactive,
                      tabular: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 2.5,
            child: AnimatedOpacity(
              opacity: active ? 1 : 0,
              duration: d,
              curve: Curves.easeOut,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  color: AddonsColors.textPrimary,
                  borderRadius: BorderRadius.all(Radius.circular(999)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArchitectureFilterChip extends StatelessWidget {
  const _ArchitectureFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.iconSvg,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? iconSvg;

  @override
  Widget build(BuildContext context) => AddonPressable(
        borderRadius: 10,
        color: selected ? AddonsColors.textPrimary : AddonsColors.card,
        borderColor: selected ? AddonsColors.textPrimary : AddonsColors.hairline,
        onLight: selected,
        selected: selected,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (iconSvg != null) ...[
                AddonIcon(
                  iconSvg!,
                  size: 13,
                  color:
                      selected ? AddonsColors.onLight : AddonsColors.textSecondary,
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: AddonsText.inter(
                  12,
                  weight: selected ? FontWeight.w700 : FontWeight.w500,
                  color:
                      selected ? AddonsColors.onLight : AddonsColors.textSecondary,
                  tabular: true,
                ),
              ),
            ],
          ),
        ),
      );
}

class _AddonsScreenSkeleton extends StatelessWidget {
  const _AddonsScreenSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          decoration: BoxDecoration(
            color: AddonsColors.composer,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AddonsColors.hairline),
          ),
          child: const AddonShimmer(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    AddonSkeletonBox(width: 118, height: 22, radius: 6),
                    AddonSkeletonBox(width: 108, height: 18, radius: 6),
                  ],
                ),
                SizedBox(height: 16),
                AddonSkeletonBox(width: 160, height: 12, radius: 4),
                SizedBox(height: 8),
                AddonSkeletonBox(height: 40, radius: 10),
                SizedBox(height: 16),
                AddonSkeletonBox(width: 220, height: 12, radius: 4),
                SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: AddonSkeletonBox(height: 34, radius: 10)),
                    SizedBox(width: 8),
                    Expanded(child: AddonSkeletonBox(height: 34, radius: 10)),
                    SizedBox(width: 8),
                    Expanded(child: AddonSkeletonBox(height: 34, radius: 10)),
                  ],
                ),
                SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: AddonSkeletonBox(height: 34, radius: 10)),
                    SizedBox(width: 8),
                    Expanded(child: AddonSkeletonBox(height: 34, radius: 10)),
                  ],
                ),
                SizedBox(height: 14),
                AddonSkeletonBox(height: 40, radius: 10),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        const AddonShimmer(
          child: Row(
            children: [
              AddonSkeletonBox(width: 76, height: 22, radius: 6),
              SizedBox(width: 24),
              AddonSkeletonBox(width: 84, height: 22, radius: 6),
            ],
          ),
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < 2; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AddonsColors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AddonsColors.hairline),
            ),
            child: const AddonShimmer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AddonSkeletonBox(width: 44, height: 44, radius: 10),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            AddonSkeletonBox(width: 170, height: 16, radius: 4),
                            SizedBox(height: 6),
                            AddonSkeletonBox(width: 110, height: 14, radius: 4),
                          ],
                        ),
                      ),
                      AddonSkeletonBox(width: 40, height: 24, radius: 999),
                    ],
                  ),
                  SizedBox(height: 14),
                  AddonSkeletonBox(height: 12, radius: 4),
                  SizedBox(height: 6),
                  AddonSkeletonBox(width: 240, height: 12, radius: 4),
                  SizedBox(height: 14),
                  Row(
                    children: [
                      AddonSkeletonBox(width: 58, height: 20, radius: 6),
                      SizedBox(width: 6),
                      AddonSkeletonBox(width: 56, height: 20, radius: 8),
                      SizedBox(width: 6),
                      AddonSkeletonBox(width: 64, height: 20, radius: 8),
                    ],
                  ),
                  SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(child: AddonSkeletonBox(height: 38, radius: 10)),
                      SizedBox(width: 10),
                      Expanded(child: AddonSkeletonBox(height: 38, radius: 10)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
