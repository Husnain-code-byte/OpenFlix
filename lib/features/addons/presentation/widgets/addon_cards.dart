import 'package:flutter/material.dart';

import '../../domain/models/addon_models.dart';
import '../controllers/addons_controller.dart';
import 'add_addon_composer_card.dart' show iconForTargetScreen;
import 'addons_ui_kit.dart';

/// Compact, graphic-forward card for an installed Stremio v3 addon (`Added` tab).
class InstalledStremioAddonCard extends StatelessWidget {
  const InstalledStremioAddonCard({
    super.key,
    required this.addon,
    required this.onToggleEnabled,
    required this.onConfigure,
    required this.onRefresh,
    required this.onRemove,
    this.isRefreshing = false,
    this.onMoveUp,
    this.onMoveDown,
  });

  final InstalledStremioAddon addon;
  final ValueChanged<bool> onToggleEnabled;
  final VoidCallback onConfigure;
  final VoidCallback onRefresh;
  final VoidCallback onRemove;
  final bool isRefreshing;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) {
    final targets = addon.effectiveTargets.toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    return AnimatedOpacity(
      duration: AddonsMotion.d(context, AddonsMotion.quick),
      opacity: addon.enabled ? 1.0 : 0.6,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AddonsColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: addon.enabled ? AddonsColors.hairline : AddonsColors.divider,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                AddonMonogram(
                  label: addon.manifest.name,
                  kindGlyph: AddonIcons.play,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        addon.manifest.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AddonsText.inter(
                          14.5,
                          weight: FontWeight.w700,
                          letterSpacing: -0.3,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (addon.supportsStreams)
                            const AddonBadge('Streams', tone: AddonBadgeTone.live),
                          if (addon.supportsSubtitles)
                            const AddonBadge('Subs'),
                          Text(
                            'v${addon.manifest.version}',
                            style: AddonsText.inter(
                              11,
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
                if (onMoveUp != null || onMoveDown != null) ...[
                  _ReorderPill(onTap: onMoveUp, isUp: true),
                  const SizedBox(width: 4),
                  _ReorderPill(onTap: onMoveDown, isUp: false),
                  const SizedBox(width: 6),
                ],
                AddonSwitch(
                  value: addon.enabled,
                  semanticLabel: 'Toggle ${addon.manifest.name}',
                  onChanged: onToggleEnabled,
                ),
              ],
            ),
            const SizedBox(height: 10),
            AddonPressable(
              borderRadius: 8,
              onTap: onConfigure,
              semanticLabel: 'Edit screens for ${addon.manifest.name}',
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (targets.isEmpty)
                    AddonTag(
                      addon.supportsStreams ? 'Stream only' : 'No screens',
                      iconSvg: AddonIcons.play,
                      iconColor: addon.supportsStreams
                          ? AddonsColors.live
                          : AddonsColors.textMuted,
                      dense: true,
                    )
                  else
                    for (final t in targets)
                      AddonTag(
                        t.label,
                        iconSvg: iconForTargetScreen(t),
                        dense: true,
                      ),
                  if (addon.includeInSearch &&
                      addon.manifest.catalogs.any((c) => c.supportsSearch))
                    const AddonTag(
                      'Search',
                      iconSvg: AddonIcons.search,
                      dense: true,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: AddonsButton(
                    label: 'Configure',
                    iconSvg: AddonIcons.gear,
                    variant: AddonButtonVariant.secondary,
                    height: 36,
                    compact: true,
                    onTap: onConfigure,
                  ),
                ),
                const SizedBox(width: 8),
                _SquareIconAction(
                  svg: AddonIcons.refresh,
                  label: 'Refresh ${addon.manifest.name}',
                  busy: isRefreshing,
                  onTap: isRefreshing ? null : onRefresh,
                ),
                const SizedBox(width: 8),
                _SquareIconAction(
                  svg: AddonIcons.trash,
                  label: 'Remove ${addon.manifest.name}',
                  danger: true,
                  onTap: onRemove,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReorderPill extends StatelessWidget {
  const _ReorderPill({required this.onTap, required this.isUp});

  final VoidCallback? onTap;
  final bool isUp;

  @override
  Widget build(BuildContext context) => AddonPressable(
        borderRadius: 6,
        color: AddonsColors.tagFill,
        borderColor: AddonsColors.tagBorder,
        semanticLabel: isUp ? 'Move addon up' : 'Move addon down',
        onTap: onTap,
        child: SizedBox(
          width: 24,
          height: 24,
          child: Center(
            child: Icon(
              isUp
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 16,
              color: onTap != null
                  ? AddonsColors.textSecondary
                  : AddonsColors.textFaint,
            ),
          ),
        ),
      );
}

class _SquareIconAction extends StatelessWidget {
  const _SquareIconAction({
    required this.svg,
    required this.label,
    required this.onTap,
    this.danger = false,
    this.busy = false,
    this.size = 36,
  });

  final String svg;
  final String label;
  final VoidCallback? onTap;
  final bool danger;
  final bool busy;
  final double size;

  @override
  Widget build(BuildContext context) {
    return AddonPressable(
      borderRadius: 10,
      color: danger ? AddonsColors.dangerFill : AddonsColors.tagFill,
      borderColor: danger ? AddonsColors.dangerBorder : AddonsColors.tagBorder,
      busy: busy,
      haptic: danger ? AddonHaptic.medium : AddonHaptic.light,
      semanticLabel: label,
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: Center(
          child: busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: AddonsColors.textSecondary,
                  ),
                )
              : AddonIcon(
                  svg,
                  size: 15,
                  color: danger
                      ? AddonsColors.dangerText
                      : AddonsColors.textSecondary,
                ),
        ),
      ),
    );
  }
}

/// Compact card for an installed CloudStream 3 repository (`Added` tab).
class InstalledCloudStreamRepoCard extends StatelessWidget {
  const InstalledCloudStreamRepoCard({
    super.key,
    required this.repo,
    required this.plugins,
    required this.onManagePlugins,
    required this.onTogglePluginEnabled,
    required this.onRemoveRepo,
    this.installProgress,
    this.onInstallRemaining,
  });

  final AddedCloudStreamRepo repo;
  final List<InstalledCs3Plugin> plugins;
  final VoidCallback onManagePlugins;
  final void Function(String uid, bool enabled) onTogglePluginEnabled;
  final VoidCallback onRemoveRepo;
  final RepoInstallProgress? installProgress;
  final VoidCallback? onInstallRemaining;

  @override
  Widget build(BuildContext context) {
    final activeCount = plugins
        .where((p) => p.enabled && p.loadStatus == Cs3LoadStatus.loaded)
        .length;
    final loadedCount =
        plugins.where((p) => p.loadStatus == Cs3LoadStatus.loaded).length;
    final failedCount =
        plugins.where((p) => p.loadStatus == Cs3LoadStatus.failed).length;
    final workingCount =
        repo.plugins.where((p) => p.isWorking && !p.isNsfw).length;
    final remainingCount =
        (workingCount - loadedCount).clamp(0, workingCount);
    final isBusy = installProgress != null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AddonsColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: activeCount > 0
              ? AddonsColors.hairlineStrong
              : AddonsColors.hairline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AddonMonogram(
                label: repo.name,
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
                        14.5,
                        weight: FontWeight.w700,
                        letterSpacing: -0.3,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        AddonBadge(
                          '$activeCount/${workingCount > 0 ? workingCount : plugins.length} active',
                          tone: activeCount > 0
                              ? AddonBadgeTone.live
                              : AddonBadgeTone.neutral,
                        ),
                        if (failedCount > 0)
                          AddonBadge(
                            '$failedCount error',
                            tone: AddonBadgeTone.danger,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _SquareIconAction(
                svg: AddonIcons.trash,
                label: 'Remove ${repo.name}',
                danger: true,
                onTap: onRemoveRepo,
              ),
            ],
          ),
          if (plugins.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AddonsColors.input,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AddonsColors.hairline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < plugins.length && i < 3; i++) ...[
                    if (i > 0) const SizedBox(height: 6),
                    _InstalledCs3MiniRow(
                      plugin: plugins[i],
                      onToggleEnabled: (v) =>
                          onTogglePluginEnabled(plugins[i].uid, v),
                      onTapManage: onManagePlugins,
                    ),
                  ],
                  if (plugins.length > 3) ...[
                    const SizedBox(height: 6),
                    AddonPressable(
                      borderRadius: 6,
                      onTap: onManagePlugins,
                      child: Row(
                        children: [
                          Text(
                            '+${plugins.length - 3} more',
                            style: AddonsText.inter(
                              11,
                              weight: FontWeight.w600,
                              color: AddonsColors.textMuted,
                              tabular: true,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const AddonIcon(
                            AddonIcons.chevronRight,
                            size: 12,
                            color: AddonsColors.textFaint,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (isBusy) ...[
            const SizedBox(height: 10),
            _InlineRepoProgressBar(progress: installProgress!),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              if (remainingCount > 0 && onInstallRemaining != null) ...[
                Expanded(
                  child: AddonsButton(
                    label: 'Finish ($remainingCount)',
                    iconSvg: AddonIcons.downloads,
                    variant: AddonButtonVariant.primary,
                    phase: isBusy
                        ? AddonButtonPhase.loading
                        : AddonButtonPhase.idle,
                    loadingLabel: 'Installing...',
                    height: 36,
                    compact: true,
                    onTap: isBusy ? null : onInstallRemaining,
                  ),
                ),
                const SizedBox(width: 8),
                _SquareIconAction(
                  svg: AddonIcons.layers,
                  label: 'Manage ${repo.name} plugins',
                  onTap: onManagePlugins,
                ),
              ] else
                Expanded(
                  child: AddonsButton(
                    label: 'Manage',
                    iconSvg: AddonIcons.layers,
                    variant: AddonButtonVariant.secondary,
                    height: 36,
                    compact: true,
                    onTap: onManagePlugins,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InstalledCs3MiniRow extends StatelessWidget {
  const _InstalledCs3MiniRow({
    required this.plugin,
    required this.onToggleEnabled,
    required this.onTapManage,
  });

  final InstalledCs3Plugin plugin;
  final ValueChanged<bool> onToggleEnabled;
  final VoidCallback onTapManage;

  @override
  Widget build(BuildContext context) {
    final dotColor = switch (plugin.loadStatus) {
      Cs3LoadStatus.loaded => AddonsColors.live,
      Cs3LoadStatus.downloading => AddonsColors.caution,
      Cs3LoadStatus.failed => AddonsColors.dangerText,
      Cs3LoadStatus.pending => AddonsColors.textFaint,
    };

    return Row(
      children: [
        Expanded(
          child: AddonPressable(
            borderRadius: 6,
            onTap: onTapManage,
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    plugin.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AddonsText.inter(
                      12,
                      weight: FontWeight.w600,
                      color: plugin.enabled
                          ? AddonsColors.textPrimary
                          : AddonsColors.textMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        AddonSwitch(
          value: plugin.enabled,
          semanticLabel: 'Toggle ${plugin.name}',
          onChanged: onToggleEnabled,
        ),
      ],
    );
  }
}

/// Sleek, App-Store-style 1-tap card for each official CloudStream repository.
class OfficialCloudStreamRepoCard extends StatelessWidget {
  const OfficialCloudStreamRepoCard({
    super.key,
    required this.entry,
    this.addedRepo,
    this.installedPlugins = const [],
    this.installProgress,
    required this.onTap,
    required this.onCopyUrl,
  });

  final OfficialCloudStreamRepoEntry entry;
  final AddedCloudStreamRepo? addedRepo;
  final List<InstalledCs3Plugin> installedPlugins;
  final RepoInstallProgress? installProgress;
  final VoidCallback onTap;
  final VoidCallback onCopyUrl;

  @override
  Widget build(BuildContext context) {
    final isAdded = addedRepo != null;
    final isBusy = installProgress != null;
    final activeCount = installedPlugins
        .where((p) => p.enabled && p.loadStatus == Cs3LoadStatus.loaded)
        .length;
    final loadedCount = installedPlugins
        .where((p) => p.loadStatus == Cs3LoadStatus.loaded)
        .length;
    final workingCount = addedRepo?.plugins
            .where((p) => p.isWorking && !p.isNsfw)
            .length ??
        0;
    final remainingCount =
        isAdded ? (workingCount - loadedCount).clamp(0, workingCount) : 0;
    final isComplete = isAdded && workingCount > 0 && remainingCount == 0;

    final String pillLabel = isBusy
        ? (installProgress!.stage == 'indexing'
            ? '...'
            : '${installProgress!.completed}/${installProgress!.total}')
        : isComplete
            ? 'Installed'
            : isAdded && remainingCount > 0
                ? 'Finish ($remainingCount)'
                : 'Add';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AddonsColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isComplete
              ? AddonsColors.hairlineStrong
              : AddonsColors.hairline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AddonMonogram(
                label: entry.name,
                kindGlyph: AddonIcons.cloud,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AddonsText.inter(
                        14.5,
                        weight: FontWeight.w700,
                        letterSpacing: -0.3,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        AddonBadge(
                          entry.languageBadge,
                          tone: AddonBadgeTone.caution,
                        ),
                        if (isAdded)
                          AddonBadge(
                            '$activeCount/$workingCount',
                            tone: activeCount > 0
                                ? AddonBadgeTone.live
                                : AddonBadgeTone.neutral,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _SquareIconAction(
                svg: AddonIcons.copy,
                label: 'Copy ${entry.name} URL',
                size: 32,
                onTap: onCopyUrl,
              ),
              const SizedBox(width: 6),
              _CompactRepoActionPill(
                label: pillLabel,
                iconSvg: isComplete ? AddonIcons.check : AddonIcons.plus,
                primary: !isComplete,
                busy: isBusy,
                onTap: isBusy ? null : onTap,
              ),
            ],
          ),
          if (isBusy) ...[
            const SizedBox(height: 10),
            _InlineRepoProgressBar(progress: installProgress!),
          ],
        ],
      ),
    );
  }
}

class _CompactRepoActionPill extends StatelessWidget {
  const _CompactRepoActionPill({
    required this.label,
    required this.iconSvg,
    required this.primary,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final String iconSvg;
  final bool primary;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return AddonPressable(
      borderRadius: 999,
      color: primary ? AddonsColors.textPrimary : AddonsColors.tagFill,
      borderColor:
          primary ? AddonsColors.textPrimary : AddonsColors.hairlineStrong,
      onLight: primary,
      busy: busy,
      semanticLabel: label,
      onTap: onTap,
      child: SizedBox(
        height: 32,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.8,
                    color: primary
                        ? AddonsColors.onLight
                        : AddonsColors.textPrimary,
                  ),
                )
              else
                AddonIcon(
                  iconSvg,
                  size: 12,
                  color: primary
                      ? AddonsColors.onLight
                      : AddonsColors.live,
                ),
              const SizedBox(width: 5),
              Text(
                label,
                style: AddonsText.inter(
                  12,
                  weight: FontWeight.w700,
                  color: primary
                      ? AddonsColors.onLight
                      : AddonsColors.textPrimary,
                  tabular: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineRepoProgressBar extends StatelessWidget {
  const _InlineRepoProgressBar({required this.progress});

  final RepoInstallProgress progress;

  @override
  Widget build(BuildContext context) {
    final isIndexing = progress.stage == 'indexing';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              isIndexing ? 'Fetching index...' : 'Installing providers',
              style: AddonsText.inter(
                11,
                weight: FontWeight.w500,
                color: AddonsColors.textMuted,
              ),
            ),
            const Spacer(),
            if (!isIndexing)
              Text(
                '${progress.completed}/${progress.total}',
                style: AddonsText.inter(
                  11,
                  weight: FontWeight.w600,
                  color: AddonsColors.textSecondary,
                  tabular: true,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: isIndexing ? null : progress.fraction,
            minHeight: 3,
            backgroundColor: AddonsColors.hairline,
            valueColor: const AlwaysStoppedAnimation<Color>(
              AddonsColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

/// Sleek 1-tap card for an official Stremio v3 addon (`Official` tab).
class OfficialStremioAddonCard extends StatelessWidget {
  const OfficialStremioAddonCard({
    super.key,
    required this.entry,
    required this.isInstalled,
    required this.onInstall,
  });

  final OfficialStremioAddonEntry entry;
  final bool isInstalled;
  final VoidCallback onInstall;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AddonsColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color:
              isInstalled ? AddonsColors.hairlineStrong : AddonsColors.hairline,
        ),
      ),
      child: Row(
        children: [
          AddonMonogram(
            label: entry.name,
            kindGlyph: AddonIcons.play,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AddonsText.inter(
                    14.5,
                    weight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final tag in entry.tags.take(2)) AddonBadge(tag),
                    if (isInstalled)
                      const AddonBadge('Added', tone: AddonBadgeTone.live),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _CompactRepoActionPill(
            label: isInstalled ? 'Edit' : 'Add',
            iconSvg: isInstalled ? AddonIcons.gear : AddonIcons.plus,
            primary: !isInstalled,
            busy: false,
            onTap: onInstall,
          ),
        ],
      ),
    );
  }
}
