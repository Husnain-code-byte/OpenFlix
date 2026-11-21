import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../home/data/models/manifest_model.dart';
import '../../data/official_addons_registry.dart';
import '../../data/stremio_addon_service.dart';
import '../../domain/models/addon_models.dart';
import '../controllers/addons_controller.dart';
import 'addons_ui_kit.dart';

/// Result returned when saving or installing a Stremio addon from
/// [StremioAddonConfigureSheet].
class StremioConfigureResult {
  const StremioConfigureResult({
    required this.placements,
    required this.includeInSearch,
  });

  final List<CatalogPlacement> placements;
  final bool includeInSearch;
}

/// Interactive Stremio Addon Configuration & Per-Catalog Screen Placement Sheet.
///
/// Supports:
/// - External `/configure` launcher with `stremio://` deep-link capture.
/// - Quick Screen Routing across all 5 OpenFlix screens (`Home`, `Movies`,
///   `TV Shows`, `Anime`, `Categories`) or stream-only (`0` screens).
/// - Shelf placement (`Below Built-in Shelves` vs `Pinned to Top`) + Search toggle.
/// - Per-catalog enable & screen assignment overrides.
class StremioAddonConfigureSheet extends StatefulWidget {
  const StremioAddonConfigureSheet({
    super.key,
    required this.manifest,
    required this.manifestUrl,
    required this.initialPlacements,
    this.initialIncludeInSearch = true,
    this.isNewInstall = false,
    this.onOpenExternalConfigure,
    this.onRefreshManifest,
  });

  final ManifestModel manifest;
  final String manifestUrl;
  final List<CatalogPlacement> initialPlacements;
  final bool initialIncludeInSearch;
  final bool isNewInstall;
  final VoidCallback? onOpenExternalConfigure;
  final Future<void> Function()? onRefreshManifest;

  @override
  State<StremioAddonConfigureSheet> createState() =>
      _StremioAddonConfigureSheetState();
}

class _StremioAddonConfigureSheetState
    extends State<StremioAddonConfigureSheet> {
  late List<CatalogPlacement> _placements = _normalizeInitialPlacements();
  late CatalogShelfPosition _shelfPosition = _detectInitialShelfPosition();
  late Set<AddonTargetScreen> _targets = _computeTargets(_placements);
  late bool _includeInSearch = widget.initialIncludeInSearch;
  bool _showSuccessOverlay = false;
  bool _refreshing = false;

  List<CatalogItemModel> get _browsableCatalogs => widget.manifest.catalogs
      .where((c) => !c.hasRequiredExtra)
      .toList(growable: false);

  bool get _hasCatalogs => _browsableCatalogs.isNotEmpty;

  bool get _isConfigurable =>
      widget.manifest.behaviorHints.configurable ||
      widget.manifest.behaviorHints.configurationRequired;

  List<CatalogPlacement> _normalizeInitialPlacements() {
    final byKey = {
      for (final p in widget.initialPlacements) p.catalogKey: p,
    };
    final defaults =
        StremioAddonService.defaultPlacementsForManifest(widget.manifest);
    return [
      for (final d in defaults) byKey[d.catalogKey] ?? d,
    ];
  }

  CatalogShelfPosition _detectInitialShelfPosition() {
    for (final p in _placements) {
      if (p.enabled && p.targetScreens.isNotEmpty) return p.position;
    }
    return CatalogShelfPosition.belowBuiltIn;
  }

  static Set<AddonTargetScreen> _computeTargets(
    List<CatalogPlacement> placements,
  ) {
    final union = <AddonTargetScreen>{};
    for (final p in placements) {
      if (p.enabled) union.addAll(p.targetScreens);
    }
    return union;
  }

  void _toggleTopLevelTarget(AddonTargetScreen screen) {
    setState(() {
      if (_targets.contains(screen)) {
        _targets = {..._targets}..remove(screen);
      } else {
        _targets = {..._targets, screen};
      }
      _placements = [
        for (final p in _placements)
          if (widget.manifest.catalogs
              .any((c) => c.baseKey == p.catalogKey && !c.hasRequiredExtra))
            p.copyWith(
              enabled: (_targets.contains(screen)
                      ? {...p.targetScreens, screen}
                      : ({...p.targetScreens}..remove(screen)))
                  .isNotEmpty,
              targetScreens: _targets.contains(screen)
                  ? {...p.targetScreens, screen}
                  : ({...p.targetScreens}..remove(screen)),
              position: _shelfPosition,
            )
          else
            p,
      ];
    });
  }

  void _applyTargetsToAllRows(Set<AddonTargetScreen> next) {
    setState(() {
      _targets = {...next};
      _placements = [
        for (final p in _placements)
          if (widget.manifest.catalogs
              .any((c) => c.baseKey == p.catalogKey && !c.hasRequiredExtra))
            p.copyWith(
              enabled: next.isNotEmpty,
              targetScreens: {...next},
              position: _shelfPosition,
            )
          else
            p,
      ];
    });
  }

  void _setShelfPosition(CatalogShelfPosition pos) {
    setState(() {
      _shelfPosition = pos;
      _placements = [
        for (final p in _placements) p.copyWith(position: pos),
      ];
    });
  }

  void _toggleRowEnabled(String catalogKey, bool enabled) {
    setState(() {
      _placements = [
        for (final p in _placements)
          if (p.catalogKey == catalogKey) p.copyWith(enabled: enabled) else p,
      ];
      _targets = _computeTargets(_placements);
    });
  }

  void _toggleRowTarget(String catalogKey, AddonTargetScreen screen) {
    setState(() {
      _placements = [
        for (final p in _placements)
          if (p.catalogKey == catalogKey)
            () {
              final nextScreens = {...p.targetScreens};
              if (nextScreens.contains(screen)) {
                nextScreens.remove(screen);
              } else {
                nextScreens.add(screen);
              }
              return p.copyWith(
                targetScreens: nextScreens,
                enabled: nextScreens.isNotEmpty,
                position: _shelfPosition,
              );
            }()
          else
            p,
      ];
      _targets = _computeTargets(_placements);
    });
  }

  Future<void> _handleRefresh() async {
    if (widget.onRefreshManifest == null || _refreshing) return;
    setState(() => _refreshing = true);
    try {
      await widget.onRefreshManifest!();
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _handleSave() async {
    addonHaptic(AddonHaptic.medium);
    setState(() => _showSuccessOverlay = true);
    await Future<void>.delayed(
      AddonsMotion.d(context, const Duration(milliseconds: 520)),
    );
    if (!mounted) return;
    Navigator.of(context).pop(
      StremioConfigureResult(
        placements: _placements,
        includeInSearch: _includeInSearch,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.manifest;
    final capLabels = <String>[
      if (m.catalogs.isNotEmpty) '${_browsableCatalogs.length} Catalogs',
      if (m.supportsResource('stream')) 'Streams',
      if (m.supportsResource('meta')) 'Metadata',
      if (m.supportsResource('subtitles')) 'Subtitles',
    ];

    return AddonsSheetFrame(
      header: Row(
        children: [
          AddonMonogram(
            label: m.name,
            size: 40,
            kindGlyph: AddonIcons.play,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AddonsText.inter(
                    17,
                    weight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'v${m.version} · ${capLabels.isEmpty ? m.id : capLabels.join(' · ')}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AddonsText.inter(
                    12,
                    color: AddonsColors.textMuted,
                    tabular: true,
                  ),
                ),
              ],
            ),
          ),
          if (widget.onRefreshManifest != null) ...[
            const SizedBox(width: 8),
            AddonPressable(
              borderRadius: 999,
              color: AddonsColors.card,
              borderColor: AddonsColors.hairline,
              busy: _refreshing,
              semanticLabel: 'Refresh manifest',
              onTap: _handleRefresh,
              child: SizedBox(
                width: 32,
                height: 32,
                child: Center(
                  child: _refreshing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.8,
                            color: AddonsColors.textSecondary,
                          ),
                        )
                      : const AddonIcon(
                          AddonIcons.refresh,
                          size: 15,
                          color: AddonsColors.textSecondary,
                        ),
                ),
              ),
            ),
          ],
        ],
      ),
      body: AnimatedSwitcher(
        duration: AddonsMotion.d(context, AddonsMotion.standard),
        child: _showSuccessOverlay
            ? Padding(
                key: const ValueKey('success'),
                padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AddonSuccessCheck(size: 64),
                    const SizedBox(height: 16),
                    Text(
                      widget.isNewInstall
                          ? '${m.name} Added'
                          : 'Screen Placement Updated',
                      textAlign: TextAlign.center,
                      style: AddonsText.inter(18, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _targets.isEmpty
                          ? 'Active as a stream/subtitle provider on Detail & Play screens.'
                          : 'Routed to ${_targets.map((e) => e.label).join(', ')}.',
                      textAlign: TextAlign.center,
                      style: AddonsText.body(),
                    ),
                  ],
                ),
              )
            : ListView(
                key: const ValueKey('form'),
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
                children: [
                  if (m.behaviorHints.configurationRequired) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: AddonsColors.cautionFill,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AddonsColors.cautionBorder),
                      ),
                      child: Row(
                        children: [
                          const AddonIcon(
                            AddonIcons.alert,
                            size: 16,
                            color: AddonsColors.caution,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'This addon requires provider configuration (Debrid/settings) on its web page. Open /configure below — tapping Install returns here automatically via stremio://.',
                              style: AddonsText.inter(
                                11.5,
                                color: AddonsColors.textPrimary,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Manifest URL & External /configure launcher
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AddonsColors.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AddonsColors.hairline),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const AddonIcon(
                              AddonIcons.link,
                              size: 14,
                              color: AddonsColors.textFaint,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.manifestUrl,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AddonsText.mono(
                                  11,
                                  color: AddonsColors.textSecondary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            AddonPressable(
                              borderRadius: 6,
                              color: AddonsColors.tagFill,
                              borderColor: AddonsColors.tagBorder,
                              onTap: () {
                                Clipboard.setData(
                                  ClipboardData(text: widget.manifestUrl),
                                );
                                showAddonsToast(context, 'Manifest URL copied');
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                child: Text(
                                  'Copy',
                                  style: AddonsText.inter(
                                    10.5,
                                    weight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_isConfigurable &&
                            widget.onOpenExternalConfigure != null) ...[
                          const SizedBox(height: 10),
                          AddonsButton(
                            label: 'Open Provider /configure Page (stremio://)',
                            iconSvg: AddonIcons.globe,
                            variant: AddonButtonVariant.secondary,
                            height: 36,
                            compact: true,
                            onTap: widget.onOpenExternalConfigure,
                          ),
                        ],
                      ],
                    ),
                  ),

                  if (_hasCatalogs) ...[
                    const SizedBox(height: 18),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'DESTINATION SCREENS',
                          style: AddonsText.eyebrow(),
                        ),
                        Row(
                          children: [
                            AddonPressable(
                              borderRadius: 6,
                              onTap: () => _applyTargetsToAllRows(
                                AddonTargetScreen.values.toSet(),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                child: Text(
                                  'All Screens',
                                  style: AddonsText.inter(
                                    11,
                                    weight: FontWeight.w600,
                                    color: AddonsColors.textSecondary,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            AddonPressable(
                              borderRadius: 6,
                              onTap: () => _applyTargetsToAllRows(
                                const <AddonTargetScreen>{},
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                child: Text(
                                  'Stream Only',
                                  style: AddonsText.inter(
                                    11,
                                    weight: FontWeight.w600,
                                    color: AddonsColors.textMuted,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final screen in AddonTargetScreen.values)
                          _SheetScreenPill(
                            screen: screen,
                            selected: _targets.contains(screen),
                            onTap: () => _toggleTopLevelTarget(screen),
                          ),
                      ],
                    ),

                    const SizedBox(height: 18),
                    Text('SHELF PLACEMENT & SEARCH', style: AddonsText.eyebrow()),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AddonsColors.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AddonsColors.hairline),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              for (final pos
                                  in CatalogShelfPosition.values) ...[
                                if (pos != CatalogShelfPosition.values.first)
                                  const SizedBox(width: 8),
                                Expanded(
                                  child: AddonPressable(
                                    borderRadius: 8,
                                    color: _shelfPosition == pos
                                        ? AddonsColors.textPrimary
                                        : AddonsColors.input,
                                    borderColor: _shelfPosition == pos
                                        ? AddonsColors.textPrimary
                                        : AddonsColors.hairline,
                                    onLight: _shelfPosition == pos,
                                    onTap: () => _setShelfPosition(pos),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
                                      child: Center(
                                        child: Text(
                                          pos.label,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: AddonsText.inter(
                                            11.5,
                                            weight: FontWeight.w700,
                                            color: _shelfPosition == pos
                                                ? AddonsColors.onLight
                                                : AddonsColors.textSecondary,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              const AddonIcon(
                                AddonIcons.search,
                                size: 16,
                                color: AddonsColors.textMuted,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Include in Search Tab',
                                      style: AddonsText.inter(
                                        13,
                                        weight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      'Search-capable catalogs contribute rows to global Search.',
                                      style: AddonsText.inter(
                                        11,
                                        color: AddonsColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              AddonSwitch(
                                value: _includeInSearch,
                                onChanged: (v) =>
                                    setState(() => _includeInSearch = v),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 18),
                    Text(
                      'PER-CATALOG ROW ROUTING (${_browsableCatalogs.length})',
                      style: AddonsText.eyebrow(),
                    ),
                    const SizedBox(height: 8),
                    for (var i = 0; i < _browsableCatalogs.length; i++) ...[
                      if (i > 0) const SizedBox(height: 10),
                      Builder(
                        builder: (context) {
                          final catalog = _browsableCatalogs[i];
                          final placement = _placements.firstWhere(
                            (p) => p.catalogKey == catalog.baseKey,
                            orElse: () => CatalogPlacement(
                              catalogKey: catalog.baseKey,
                              enabled: false,
                              targetScreens: const {},
                            ),
                          );
                          return _CatalogRowRoutingTile(
                            catalog: catalog,
                            placement: placement,
                            onToggleEnabled: (v) =>
                                _toggleRowEnabled(catalog.baseKey, v),
                            onToggleScreen: (s) =>
                                _toggleRowTarget(catalog.baseKey, s),
                          );
                        },
                      ),
                    ],
                  ] else ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AddonsColors.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AddonsColors.hairline),
                      ),
                      child: Row(
                        children: [
                          const AddonIcon(
                            AddonIcons.play,
                            size: 18,
                            color: AddonsColors.live,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'This manifest provides streams/subtitles/metadata with no Home catalog shelves. Tap below to activate it on Detail & Play screens.',
                              style: AddonsText.inter(
                                12,
                                color: AddonsColors.textSecondary,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
      ),
      footer: _showSuccessOverlay
          ? null
          : AddonsButton(
              label: widget.isNewInstall
                  ? (_targets.isEmpty
                      ? 'Install Streaming Addon'
                      : 'Add to ${_targets.length} Selected Screen${_targets.length == 1 ? '' : 's'}')
                  : 'Save Placement & Settings',
              iconSvg: widget.isNewInstall ? AddonIcons.plus : AddonIcons.check,
              onTap: _handleSave,
            ),
    );
  }
}

class _SheetScreenPill extends StatelessWidget {
  const _SheetScreenPill({
    required this.screen,
    required this.selected,
    required this.onTap,
  });

  final AddonTargetScreen screen;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AddonPressable(
        borderRadius: 10,
        color: selected ? AddonsColors.textPrimary : AddonsColors.card,
        borderColor: selected ? AddonsColors.textPrimary : AddonsColors.hairline,
        onLight: selected,
        selected: selected,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected) ...[
                const AddonPopIn(
                  child: AddonIcon(
                    AddonIcons.tick,
                    size: 9,
                    color: AddonsColors.onLight,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                screen.label,
                style: AddonsText.inter(
                  12,
                  weight: selected ? FontWeight.w700 : FontWeight.w500,
                  color:
                      selected ? AddonsColors.onLight : AddonsColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
}

class _CatalogRowRoutingTile extends StatelessWidget {
  const _CatalogRowRoutingTile({
    required this.catalog,
    required this.placement,
    required this.onToggleEnabled,
    required this.onToggleScreen,
  });

  final CatalogItemModel catalog;
  final CatalogPlacement placement;
  final ValueChanged<bool> onToggleEnabled;
  final ValueChanged<AddonTargetScreen> onToggleScreen;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AddonsColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: placement.enabled ? AddonsColors.hairline : AddonsColors.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AddonBadge(catalog.typeLabel),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  placement.customTitle?.isNotEmpty == true
                      ? placement.customTitle!
                      : catalog.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AddonsText.inter(
                    13,
                    weight: FontWeight.w700,
                    color: placement.enabled
                        ? AddonsColors.textPrimary
                        : AddonsColors.textMuted,
                  ),
                ),
              ),
              AddonSwitch(
                value: placement.enabled,
                onChanged: onToggleEnabled,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final screen in AddonTargetScreen.values)
                AddonPressable(
                  borderRadius: 7,
                  color:
                      placement.enabled && placement.targetScreens.contains(screen)
                          ? AddonsColors.textPrimary
                          : AddonsColors.input,
                  borderColor:
                      placement.enabled && placement.targetScreens.contains(screen)
                          ? AddonsColors.textPrimary
                          : AddonsColors.hairline,
                  onLight: placement.enabled &&
                      placement.targetScreens.contains(screen),
                  onTap: () => onToggleScreen(screen),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    child: Text(
                      screen.label,
                      style: AddonsText.inter(
                        11,
                        weight: placement.enabled &&
                                placement.targetScreens.contains(screen)
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: placement.enabled &&
                                placement.targetScreens.contains(screen)
                            ? AddonsColors.onLight
                            : AddonsColors.textMuted,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sheet 2: CloudStream Two-Step Repository Plugin Browser (Live Riverpod)
// ─────────────────────────────────────────────────────────────────────────────

class CloudStreamRepoBrowserSheet extends ConsumerStatefulWidget {
  const CloudStreamRepoBrowserSheet({
    super.key,
    required this.repoId,
  });

  final String repoId;

  @override
  ConsumerState<CloudStreamRepoBrowserSheet> createState() =>
      _CloudStreamRepoBrowserSheetState();
}

class _CloudStreamRepoBrowserSheetState
    extends ConsumerState<CloudStreamRepoBrowserSheet> {
  String _query = '';
  String _selectedTypeFilter = 'All';
  bool _installingAll = false;
  bool _refreshingRepo = false;

  static const _typeFilters = ['All', 'Movie', 'TvSeries', 'Anime'];

  Future<void> _installAllWorking() async {
    if (_installingAll) return;
    setState(() => _installingAll = true);
    try {
      await ref
          .read(addonsControllerProvider.notifier)
          .installAllWorkingPlugins(widget.repoId);
    } finally {
      if (mounted) setState(() => _installingAll = false);
    }
  }

  Future<void> _refreshRepo(AddedCloudStreamRepo repo) async {
    if (_refreshingRepo) return;
    setState(() => _refreshingRepo = true);
    try {
      final official = kOfficialCloudStreamRepos
          .where((o) => o.id == repo.id)
          .firstOrNull;
      await ref.read(addonsControllerProvider.notifier).addOrRefreshCloudStreamRepo(
            repo.repoUrl,
            official: official,
          );
      if (mounted) {
        showAddonsToast(context, 'Refreshed ${repo.name}');
      }
    } catch (e) {
      if (mounted) {
        showAddonsToast(
          context,
          'Refresh failed: ${e.toString().replaceFirst('Exception: ', '')}',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _refreshingRepo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store =
        ref.watch(addonsControllerProvider).valueOrNull ?? const AddonsStoreState();
    final progressMap = ref.watch(cs3InstallProgressProvider);
    final repo = store.cloudStreamRepos
        .where((r) => r.id == widget.repoId)
        .firstOrNull;

    if (repo == null) {
      return AddonsSheetFrame(
        title: 'CloudStream Repository',
        body: Padding(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
          child: AddonsStateCard(
            iconSvg: AddonIcons.cloud,
            title: 'Repository Removed',
            body: 'This CloudStream repository is no longer in your library.',
            actionLabel: 'Close',
            onAction: () => Navigator.of(context).pop(),
          ),
        ),
      );
    }

    final showNsfw = store.showNsfw;
    final installedByUid = {
      for (final p in store.installedCs3Plugins)
        if (p.repoId == repo.id) p.uid: p,
    };

    final filtered = repo.plugins.where((p) {
      if (p.isNsfw && !showNsfw) return false;
      if (_selectedTypeFilter != 'All' &&
          !p.tvTypes.any(
            (t) => t.toLowerCase() == _selectedTypeFilter.toLowerCase(),
          )) {
        return false;
      }
      if (_query.trim().isNotEmpty) {
        final q = _query.trim().toLowerCase();
        return p.name.toLowerCase().contains(q) ||
            p.language.toLowerCase().contains(q) ||
            (p.description ?? '').toLowerCase().contains(q);
      }
      return true;
    }).toList(growable: false);

    final activeCount = installedByUid.values
        .where((p) => p.enabled && p.loadStatus == Cs3LoadStatus.loaded)
        .length;

    final workingRemaining = repo.plugins.where((p) {
      if (!p.isWorking) return false;
      if (p.isNsfw && !showNsfw) return false;
      final uid = InstalledCs3Plugin.makeUid(repo.id, p.internalName);
      final existing = installedByUid[uid];
      return existing == null || existing.loadStatus != Cs3LoadStatus.loaded;
    }).length;

    return AddonsSheetFrame(
      maxHeightFactor: 0.92,
      header: Row(
        children: [
          AddonMonogram(
            label: repo.name,
            size: 40,
            kindGlyph: AddonIcons.cloud,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  repo.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AddonsText.inter(
                    17,
                    weight: FontWeight.w700,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${repo.languageBadge ?? 'Multi'} · $activeCount/${repo.plugins.length} .cs3 active',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AddonsText.inter(
                    12,
                    color: AddonsColors.textMuted,
                    tabular: true,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          AddonPressable(
            borderRadius: 999,
            color: AddonsColors.card,
            borderColor: AddonsColors.hairline,
            busy: _refreshingRepo,
            semanticLabel: 'Refresh ${repo.name} plugin list',
            onTap: () => _refreshRepo(repo),
            child: SizedBox(
              width: 32,
              height: 32,
              child: Center(
                child: _refreshingRepo
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.8,
                          color: AddonsColors.textSecondary,
                        ),
                      )
                    : const AddonIcon(
                        AddonIcons.refresh,
                        size: 15,
                        color: AddonsColors.textSecondary,
                      ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Search & Filter Controls
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: AddonsColors.input,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AddonsColors.hairline),
                  ),
                  child: Row(
                    children: [
                      const AddonIcon(
                        AddonIcons.search,
                        size: 15,
                        color: AddonsColors.textFaint,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          onChanged: (v) => setState(() => _query = v),
                          style: AddonsText.inter(13),
                          cursorColor: AddonsColors.textPrimary,
                          decoration: InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 8),
                            hintText:
                                'Filter ${repo.plugins.length} .cs3 providers by name or language...',
                            hintStyle: AddonsText.inter(
                              12.5,
                              color: AddonsColors.textFaint,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final f in _typeFilters) ...[
                              if (f != _typeFilters.first)
                                const SizedBox(width: 6),
                              AddonPressable(
                                borderRadius: 8,
                                color: _selectedTypeFilter == f
                                    ? AddonsColors.textPrimary
                                    : AddonsColors.card,
                                borderColor: _selectedTypeFilter == f
                                    ? AddonsColors.textPrimary
                                    : AddonsColors.hairline,
                                onLight: _selectedTypeFilter == f,
                                onTap: () =>
                                    setState(() => _selectedTypeFilter = f),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  child: Text(
                                    f == 'TvSeries' ? 'TV Shows' : f,
                                    style: AddonsText.inter(
                                      11,
                                      weight: _selectedTypeFilter == f
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: _selectedTypeFilter == f
                                          ? AddonsColors.onLight
                                          : AddonsColors.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    AddonPressable(
                      borderRadius: 8,
                      color: showNsfw
                          ? AddonsColors.dangerFill
                          : AddonsColors.tagFill,
                      borderColor: showNsfw
                          ? AddonsColors.dangerBorder
                          : AddonsColors.tagBorder,
                      onTap: () => ref
                          .read(addonsControllerProvider.notifier)
                          .setShowNsfw(!showNsfw),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        child: Text(
                          showNsfw ? '18+ Shown' : '18+ Hidden',
                          style: AddonsText.inter(
                            10.5,
                            weight: FontWeight.w600,
                            color: showNsfw
                                ? AddonsColors.dangerText
                                : AddonsColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          Expanded(
            child: filtered.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: AddonsStateCard(
                      iconSvg: AddonIcons.search,
                      title: 'No matching .cs3 plugins',
                      body:
                          'Try clearing the search filter or enabling additional categories.',
                      actionLabel: 'Reset Filters',
                      onAction: () => setState(() {
                        _query = '';
                        _selectedTypeFilter = 'All';
                      }),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final plugin = filtered[index];
                      final uid = InstalledCs3Plugin.makeUid(
                        repo.id,
                        plugin.internalName,
                      );
                      final installed = installedByUid[uid];
                      final progress = progressMap[uid];
                      return _Cs3PluginTile(
                        plugin: plugin,
                        installed: installed,
                        progress: progress,
                        onInstall: () => ref
                            .read(addonsControllerProvider.notifier)
                            .installCs3Plugin(repo.id, plugin),
                        onUninstall: () => ref
                            .read(addonsControllerProvider.notifier)
                            .uninstallCs3Plugin(uid),
                        onToggleEnabled: (v) => ref
                            .read(addonsControllerProvider.notifier)
                            .toggleCs3Plugin(uid, v),
                      );
                    },
                  ),
          ),
        ],
      ),
      footer: Row(
        children: [
          Expanded(
            flex: 2,
            child: AddonsButton(
              label: 'Remove Repo',
              iconSvg: AddonIcons.trash,
              variant: AddonButtonVariant.danger,
              height: 42,
              compact: true,
              onTap: () async {
                Navigator.of(context).pop();
                await ref
                    .read(addonsControllerProvider.notifier)
                    .removeCloudStreamRepo(repo.id);
              },
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 3,
            child: AddonsButton(
              label: workingRemaining > 0
                  ? 'Install All Working ($workingRemaining)'
                  : 'Done ($activeCount Active)',
              iconSvg:
                  workingRemaining > 0 ? AddonIcons.downloads : AddonIcons.check,
              phase: _installingAll
                  ? AddonButtonPhase.loading
                  : AddonButtonPhase.idle,
              loadingLabel: 'Loading .cs3 DEX...',
              height: 42,
              onTap: workingRemaining > 0
                  ? _installAllWorking
                  : () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}

class _Cs3PluginTile extends StatelessWidget {
  const _Cs3PluginTile({
    required this.plugin,
    required this.installed,
    required this.progress,
    required this.onInstall,
    required this.onUninstall,
    required this.onToggleEnabled,
  });

  final Cs3PluginMeta plugin;
  final InstalledCs3Plugin? installed;
  final double? progress;
  final VoidCallback onInstall;
  final VoidCallback onUninstall;
  final ValueChanged<bool> onToggleEnabled;

  @override
  Widget build(BuildContext context) {
    final status = installed?.loadStatus;
    final isDownloading =
        progress != null || status == Cs3LoadStatus.downloading;
    final isFailed = status == Cs3LoadStatus.failed;
    final isLoaded = status == Cs3LoadStatus.loaded;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AddonsColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isFailed ? AddonsColors.dangerHairline : AddonsColors.hairline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AddonMonogram(
                label: plugin.name,
                size: 38,
                radius: 9,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            plugin.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AddonsText.inter(
                              13.5,
                              weight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'v${plugin.version}',
                          style: AddonsText.inter(
                            11,
                            color: AddonsColors.textFaint,
                            tabular: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        AddonBadge(plugin.language),
                        for (final t in plugin.tvTypes)
                          AddonBadge(
                            t,
                            tone: t.toLowerCase() == 'nsfw'
                                ? AddonBadgeTone.danger
                                : AddonBadgeTone.neutral,
                          ),
                        if (plugin.status != 1)
                          const AddonBadge(
                            'Down',
                            tone: AddonBadgeTone.caution,
                          ),
                        if (plugin.fileSizeKb > 0)
                          Text(
                            '${plugin.fileSizeKb} KB .cs3',
                            style: AddonsText.inter(
                              10.5,
                              color: AddonsColors.textFaint,
                              tabular: true,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isDownloading)
                AddonProgressRing(value: progress ?? 0.3, size: 34)
              else if (isLoaded && installed != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AddonSwitch(
                      value: installed!.enabled,
                      onChanged: onToggleEnabled,
                    ),
                    const SizedBox(width: 8),
                    AddonPressable(
                      borderRadius: 8,
                      color: AddonsColors.dangerFill,
                      borderColor: AddonsColors.dangerHairline,
                      onTap: onUninstall,
                      semanticLabel: 'Uninstall ${plugin.name}',
                      child: const SizedBox(
                        width: 32,
                        height: 32,
                        child: Center(
                          child: AddonIcon(
                            AddonIcons.trash,
                            size: 14,
                            color: AddonsColors.dangerText,
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              else if (isFailed)
                AddonsButton(
                  label: 'Retry',
                  iconSvg: AddonIcons.refresh,
                  variant: AddonButtonVariant.danger,
                  expand: false,
                  compact: true,
                  height: 32,
                  onTap: onInstall,
                )
              else
                AddonsButton(
                  label: 'Install',
                  iconSvg: AddonIcons.plus,
                  expand: false,
                  compact: true,
                  height: 34,
                  onTap: plugin.url.isEmpty ? null : onInstall,
                ),
            ],
          ),
          if ((plugin.description ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              plugin.description!.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AddonsText.inter(
                11.5,
                color: AddonsColors.textMuted,
                height: 1.4,
              ),
            ),
          ],
          if (isLoaded &&
              installed != null &&
              installed!.registeredProviderNames.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final pName in installed!.registeredProviderNames)
                  AddonTag(pName, dense: true, iconSvg: AddonIcons.play),
              ],
            ),
          ],
          if (installed?.lastError != null &&
              installed!.lastError!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AddonsColors.dangerFill,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AddonsColors.dangerHairline),
              ),
              child: Row(
                children: [
                  const AddonIcon(
                    AddonIcons.alert,
                    size: 13,
                    color: AddonsColors.dangerText,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      installed!.lastError!,
                      style: AddonsText.inter(
                        11,
                        color: AddonsColors.dangerText,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sheet 3: One-Time Third-Party / .cs3 Safety Opt-in Sheet
// ─────────────────────────────────────────────────────────────────────────────

class AddonSafetyNoticeSheet extends StatelessWidget {
  const AddonSafetyNoticeSheet({
    super.key,
    required this.targetName,
    required this.isCloudStream,
  });

  final String targetName;
  final bool isCloudStream;

  @override
  Widget build(BuildContext context) {
    return AddonsSheetFrame(
      title: 'Third-Party Addon Safety Notice',
      body: Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AddonsColors.card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AddonsColors.cautionBorder),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AddonIcon(
                    AddonIcons.shield,
                    size: 22,
                    color: AddonsColors.caution,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Not Installed by Default for Your Safety',
                          style: AddonsText.inter(
                            13.5,
                            weight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isCloudStream
                              ? 'CloudStream (.cs3) extensions run community-maintained scraping bytecode inside a sandboxed read-only DEX loader. Only enable repositories and providers you trust.'
                              : 'Stremio manifests connect directly to external third-party servers. OpenFlix never pre-installs external stream or catalog providers without your consent.',
                          style: AddonsText.inter(
                            12,
                            color: AddonsColors.textMuted,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Selected: $targetName',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AddonsText.inter(
                12,
                weight: FontWeight.w600,
                color: AddonsColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
      footer: Row(
        children: [
          Expanded(
            child: AddonsButton(
              label: 'Cancel',
              variant: AddonButtonVariant.secondary,
              onTap: () => Navigator.of(context).pop(false),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: AddonsButton(
              label: 'I Understand · Continue',
              iconSvg: AddonIcons.shield,
              onTap: () => Navigator.of(context).pop(true),
            ),
          ),
        ],
      ),
    );
  }
}
