import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/models/addon_models.dart';
import '../models/addons_ui_models.dart';
import 'addons_ui_kit.dart';

/// Minimalistic, graphic-forward composer card for adding Stremio v3 manifests
/// or CloudStream 3 repositories. No destination screens are pre-selected.
class AddAddonComposerCard extends StatefulWidget {
  const AddAddonComposerCard({
    super.key,
    required this.controller,
    required this.selectedTargets,
    required this.onToggleTarget,
    required this.onClearTargets,
    required this.onSelectAllTargets,
    required this.onSubmit,
    required this.phase,
    required this.shakeTrigger,
    this.errorText,
    this.onPresetSelected,
  });

  final TextEditingController controller;
  final Set<AddonTargetScreen> selectedTargets;
  final ValueChanged<AddonTargetScreen> onToggleTarget;
  final VoidCallback onClearTargets;
  final VoidCallback onSelectAllTargets;
  final VoidCallback onSubmit;
  final AddonButtonPhase phase;
  final int shakeTrigger;
  final String? errorText;
  final ValueChanged<({String url, Set<AddonTargetScreen> targets})>?
      onPresetSelected;

  @override
  State<AddAddonComposerCard> createState() => _AddAddonComposerCardState();
}

class _AddAddonComposerCardState extends State<AddAddonComposerCard> {
  final FocusNode _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChange);
    widget.controller.addListener(_onTextChange);
  }

  @override
  void didUpdateWidget(covariant AddAddonComposerCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChange);
      widget.controller.addListener(_onTextChange);
    }
  }

  void _onFocusChange() {
    if (mounted) setState(() => _focused = _focusNode.hasFocus);
  }

  void _onTextChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_onFocusChange)
      ..dispose();
    widget.controller.removeListener(_onTextChange);
    super.dispose();
  }

  Future<void> _handlePaste() async {
    addonHaptic(AddonHaptic.light);
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      if (text != null && text.isNotEmpty) {
        widget.controller.text = text;
        widget.controller.selection =
            TextSelection.collapsed(offset: text.length);
        return;
      }
    } catch (_) {}
    if (mounted) {
      showAddonsToast(context, 'Clipboard is empty');
    }
  }

  @override
  Widget build(BuildContext context) {
    final detected = DetectedAddonInputUi.analyze(widget.controller.text);
    final isCloudStream =
        detected.kind == DetectedInputKindUi.cloudStreamRepoJson ||
            detected.kind == DetectedInputKindUi.cloudStreamShortcode;
    final hasError = widget.errorText != null && widget.errorText!.isNotEmpty;
    final selectedCount = widget.selectedTargets.length;

    final String ctaLabel = isCloudStream
        ? 'Add Repository'
        : (selectedCount == 0
            ? 'Add Addon'
            : 'Add · $selectedCount ${selectedCount == 1 ? 'Screen' : 'Screens'}');

    final String shortBadge = switch (detected.kind) {
      DetectedInputKindUi.empty => 'Stremio · CS3',
      DetectedInputKindUi.stremioManifest => 'Stremio v3',
      DetectedInputKindUi.cloudStreamRepoJson => 'CS3 Repo',
      DetectedInputKindUi.cloudStreamShortcode => 'CS3 Code',
      DetectedInputKindUi.invalid => 'Invalid',
    };

    return AddonShake(
      trigger: widget.shakeTrigger,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AddonsColors.composer,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color:
                hasError ? AddonsColors.dangerHairline : AddonsColors.hairline,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x38000000),
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Compact visual header
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AddonsColors.canvas,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AddonsColors.hairline),
                  ),
                  child: const Center(
                    child: AddonIcon(
                      AddonIcons.puzzle,
                      size: 14,
                      color: AddonsColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Add Addon',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AddonsText.inter(
                      16,
                      weight: FontWeight.w700,
                      letterSpacing: -0.4,
                      height: 1.2,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedSwitcher(
                  duration: AddonsMotion.d(context, AddonsMotion.quick),
                  switchInCurve: AddonsMotion.emphasized,
                  switchOutCurve: AddonsMotion.emphasized,
                  child: AddonBadge(
                    shortBadge,
                    key: ValueKey<String>(shortBadge),
                    tone: switch (detected.kind) {
                      DetectedInputKindUi.empty => AddonBadgeTone.neutral,
                      DetectedInputKindUi.stremioManifest =>
                        AddonBadgeTone.live,
                      DetectedInputKindUi.cloudStreamRepoJson ||
                      DetectedInputKindUi.cloudStreamShortcode =>
                        AddonBadgeTone.caution,
                      DetectedInputKindUi.invalid => AddonBadgeTone.danger,
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Monospace URL input with Paste & Clear
            AnimatedContainer(
              duration: AddonsMotion.d(context, AddonsMotion.quick),
              curve: AddonsMotion.emphasized,
              padding: const EdgeInsets.fromLTRB(12, 5, 5, 5),
              decoration: BoxDecoration(
                color: AddonsColors.input,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: hasError
                      ? AddonsColors.dangerBorder
                      : (_focused
                          ? AddonsColors.hairlineFocus
                          : AddonsColors.hairline),
                  width: _focused ? 1.3 : 1.0,
                ),
              ),
              child: Row(
                children: [
                  const AddonIcon(
                    AddonIcons.link,
                    size: 14,
                    color: AddonsColors.textFaint,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: widget.controller,
                      focusNode: _focusNode,
                      style:
                          AddonsText.mono(12, color: AddonsColors.textPrimary),
                      cursorColor: AddonsColors.textPrimary,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => widget.onSubmit(),
                      decoration: InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 6),
                        hintText: 'Manifest or repo URL...',
                        hintStyle:
                            AddonsText.mono(12, color: AddonsColors.textFaint),
                      ),
                    ),
                  ),
                  if (widget.controller.text.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    AddonPressable(
                      borderRadius: 6,
                      semanticLabel: 'Clear URL',
                      onTap: widget.controller.clear,
                      child: const SizedBox(
                        width: 26,
                        height: 26,
                        child: Center(
                          child: AddonIcon(
                            AddonIcons.close,
                            size: 13,
                            color: AddonsColors.textMuted,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 4),
                  AddonPressable(
                    color: AddonsColors.badgeFill,
                    borderColor: AddonsColors.hairlineStrong,
                    borderRadius: 8,
                    semanticLabel: 'Paste URL from clipboard',
                    onTap: _handlePaste,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 6,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const AddonIcon(
                            AddonIcons.clipboard,
                            size: 12,
                            color: AddonsColors.textSecondary,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'Paste',
                            style: AddonsText.inter(
                              11,
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
            ),

            if (hasError)
              Padding(
                padding: const EdgeInsets.only(top: 8),
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
                        widget.errorText!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AddonsText.inter(
                          11,
                          weight: FontWeight.w500,
                          color: AddonsColors.dangerText,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 12),

            // Screen routing icons (or compact CS3 stream indicator)
            AnimatedSwitcher(
              duration: AddonsMotion.d(context, AddonsMotion.standard),
              switchInCurve: AddonsMotion.emphasized,
              switchOutCurve: AddonsMotion.emphasized,
              child: isCloudStream
                  ? const _CloudStreamCompactPill(key: ValueKey('cs3-pill'))
                  : Column(
                      key: const ValueKey('stremio-matrix'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Text('SCREENS', style: AddonsText.eyebrow()),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: selectedCount == 0
                                    ? AddonsColors.liveFill
                                    : AddonsColors.tagFill,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: selectedCount == 0
                                      ? AddonsColors.liveBorder
                                      : AddonsColors.tagBorder,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (selectedCount == 0) ...[
                                    const AddonIcon(
                                      AddonIcons.play,
                                      size: 8,
                                      color: AddonsColors.live,
                                    ),
                                    const SizedBox(width: 4),
                                  ],
                                  Text(
                                    selectedCount == 0
                                        ? 'Stream only'
                                        : '$selectedCount selected',
                                    style: AddonsText.inter(
                                      10,
                                      weight: FontWeight.w600,
                                      color: selectedCount == 0
                                          ? AddonsColors.live
                                          : AddonsColors.textSecondary,
                                      tabular: true,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Spacer(),
                            if (selectedCount > 0)
                              AddonPressable(
                                borderRadius: 6,
                                color: AddonsColors.tagFill,
                                borderColor: AddonsColors.tagBorder,
                                onTap: widget.onClearTargets,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  child: Text(
                                    'Clear',
                                    style: AddonsText.inter(
                                      10,
                                      weight: FontWeight.w600,
                                      color: AddonsColors.textMuted,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _TargetScreensGrid(
                          selectedTargets: widget.selectedTargets,
                          onToggle: widget.onToggleTarget,
                        ),
                      ],
                    ),
            ),

            const SizedBox(height: 12),

            AddonsButton(
              label: ctaLabel,
              iconSvg: AddonIcons.plus,
              phase: widget.phase,
              loadingLabel: isCloudStream ? 'Installing...' : 'Fetching...',
              successLabel: isCloudStream ? 'Installed' : 'Added',
              height: 40,
              onTap: widget.onSubmit,
            ),
          ],
        ),
      ),
    );
  }
}

String iconForTargetScreen(AddonTargetScreen target) => switch (target) {
      AddonTargetScreen.home => AddonIcons.home,
      AddonTargetScreen.movies => AddonIcons.film,
      AddonTargetScreen.tvShows => AddonIcons.tv,
      AddonTargetScreen.anime => AddonIcons.sparkle,
      AddonTargetScreen.categories => AddonIcons.grid,
    };

/// 5-target screen matrix with crisp icons:
/// Row 1: `Home` · `Movies` · `TV Shows`
/// Row 2: `Anime` · `Categories`
class _TargetScreensGrid extends StatelessWidget {
  const _TargetScreensGrid({
    required this.selectedTargets,
    required this.onToggle,
  });

  final Set<AddonTargetScreen> selectedTargets;
  final ValueChanged<AddonTargetScreen> onToggle;

  @override
  Widget build(BuildContext context) {
    const row1 = [
      AddonTargetScreen.home,
      AddonTargetScreen.movies,
      AddonTargetScreen.tvShows,
    ];
    const row2 = [
      AddonTargetScreen.anime,
      AddonTargetScreen.categories,
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            for (var i = 0; i < row1.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: _TargetScreenChip(
                  target: row1[i],
                  selected: selectedTargets.contains(row1[i]),
                  onTap: () => onToggle(row1[i]),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < row2.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: _TargetScreenChip(
                  target: row2[i],
                  selected: selectedTargets.contains(row2[i]),
                  onTap: () => onToggle(row2[i]),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _TargetScreenChip extends StatelessWidget {
  const _TargetScreenChip({
    required this.target,
    required this.selected,
    required this.onTap,
  });

  final AddonTargetScreen target;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: AddonPressable(
        borderRadius: 10,
        color: selected ? AddonsColors.textPrimary : AddonsColors.canvas,
        borderColor:
            selected ? AddonsColors.textPrimary : AddonsColors.hairline,
        onLight: selected,
        selected: selected,
        semanticLabel: '${target.label} destination screen',
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected)
                  const AddonPopIn(
                    child: AddonIcon(
                      AddonIcons.tick,
                      size: 9,
                      color: AddonsColors.onLight,
                    ),
                  )
                else
                  AddonIcon(
                    iconForTargetScreen(target),
                    size: 13,
                    color: AddonsColors.textMuted,
                  ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    target.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AddonsText.inter(
                      12,
                      weight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? AddonsColors.onLight
                          : AddonsColors.textMuted,
                      height: 16 / 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CloudStreamCompactPill extends StatelessWidget {
  const _CloudStreamCompactPill({super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: AddonsColors.canvas,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AddonsColors.cautionBorder),
        ),
        child: Row(
          children: [
            const AddonIcon(
              AddonIcons.cloud,
              size: 15,
              color: AddonsColors.caution,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'CloudStream · Streams on Play',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AddonsText.inter(
                  12,
                  weight: FontWeight.w600,
                  color: AddonsColors.textSecondary,
                ),
              ),
            ),
            const AddonBadge('.cs3', tone: AddonBadgeTone.caution),
          ],
        ),
      );
}
