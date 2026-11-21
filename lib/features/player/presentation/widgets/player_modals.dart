import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/utils/responsive.dart';
import '../../../preferences/domain/models/playback_preferences.dart';
import '../../domain/models/player_models.dart';
import '../../domain/models/ranked_stream.dart';
import '../controllers/player_controller.dart';
import 'player_icons.dart';

TextStyle _inter({
  double? fontSize,
  FontWeight? fontWeight,
  Color? color,
  double? letterSpacing,
  double? height,
  List<FontFeature>? fontFeatures,
}) =>
    TextStyle(
      fontFamily: 'Inter',
      fontSize: fontSize?.sp,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
      fontFeatures: fontFeatures,
    );

abstract final class _ModalColors {
  static const sheetBg = Color(0xFF13161F);
  static const dragHandle = Color(0xFF363B47);
  static const closeBtn = Color(0xFF242A37);
  static const surfaceRow = Color(0xFF191D29);
  static const activeRow = Color(0x14FFFFFF);
  static const hairline = Color(0x14FFFFFF);
  static const columnDivider = Color(0x1FFFFFFF);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textMuted = Color(0xFFA1A1AA);
  static const textFaint = Color(0xFF71717A);
  static const live = Color(0xFF4ADE80);
  static const liveFill = Color(0x1A4ADE80);
  static const liveBorder = Color(0x334ADE80);
  static const caution = Color(0xFFFBBF24);
  static const cautionFill = Color(0x1AFBBF24);
  static const cautionBorder = Color(0x33FBBF24);
}

Future<T?> _showLandscapePlayerSheet<T>(
  BuildContext context, {
  required Widget Function(BuildContext) builder,
}) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x99000000),
      useSafeArea: true,
      builder: builder,
    );

class _PlayerModalFrame extends StatelessWidget {
  const _PlayerModalFrame({
    required this.width,
    required this.maxHeight,
    required this.header,
    required this.child,
  });

  final double width;
  final double maxHeight;
  final Widget header;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);
    return Align(
      alignment: Alignment.bottomCenter,
      child: Container(
        width: width,
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: BoxDecoration(
          color: _ModalColors.sheetBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
          border: Border.all(color: _ModalColors.hairline),
          boxShadow: const [
            BoxShadow(
              color: Color(0x88000000),
              blurRadius: 32,
              offset: Offset(0, -8),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 10.h),
              Center(
                child: Container(
                  width: 44.w,
                  height: 4.h,
                  decoration: BoxDecoration(
                    color: _ModalColors.dragHandle,
                    borderRadius: BorderRadius.circular(9999),
                  ),
                ),
              ),
              SizedBox(height: 10.h),
              header,
              const Divider(height: 1, color: _ModalColors.hairline),
              Flexible(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class _CloseModalButton extends StatelessWidget {
  const _CloseModalButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          width: 32.r,
          height: 32.r,
          decoration: const BoxDecoration(
            color: _ModalColors.closeBtn,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: PlayerSvgIcon(PlayerIcons.modalClose, size: 15.r),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Audio & Subtitles Two-Column Modal (Figma 50:179 — Corrected Ratio & Divider)
// ─────────────────────────────────────────────────────────────────────────────

Future<void> showPlayerAudioSubtitlesModal(
  BuildContext context, {
  required PlayerSessionController controller,
}) =>
    _showLandscapePlayerSheet<void>(
      context,
      builder: (_) => _PlayerAudioSubtitlesSheet(controller: controller),
    );

class _PlayerAudioSubtitlesSheet extends StatelessWidget {
  const _PlayerAudioSubtitlesSheet({required this.controller});

  final PlayerSessionController controller;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final modalWidth =
        (size.width * 0.72).clamp(340.0, 640.0).clamp(0.0, size.width - 24);
    final maxH = (size.height * 0.80).clamp(240.0, 440.0);
    final bodyHeight = (maxH - 68).clamp(160.0, 360.0);

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final st = controller.state;
        return _PlayerModalFrame(
          width: modalWidth,
          maxHeight: maxH,
          header: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Audio & Subtitles',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _inter(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: _ModalColors.textPrimary,
                      letterSpacing: -0.35,
                    ),
                  ),
                ),
                _CloseModalButton(onTap: () => Navigator.of(context).pop()),
              ],
            ),
          ),
          child: SizedBox(
            height: bodyHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left column: Audio Tracks
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ColumnHeader(
                        icon: Icons.volume_up_rounded,
                        title: 'Audio',
                        count: st.audioOptions.length,
                      ),
                      Expanded(
                        child: st.audioOptions.isEmpty
                            ? _EmptyTrackHint(
                                text: st.isInitializing
                                    ? 'Detecting audio tracks...'
                                    : 'Default stream audio',
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  4,
                                  12,
                                  14,
                                ),
                                itemCount: st.audioOptions.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(height: 4),
                                itemBuilder: (context, idx) {
                                  final opt = st.audioOptions[idx];
                                  final selected =
                                      opt.id == st.selectedAudioId;
                                  return _TrackOptionRow(
                                    title: opt.displayLabel,
                                    detail: opt.codecDetail,
                                    selected: selected,
                                    onTap: () {
                                      HapticFeedback.selectionClick();
                                      controller.selectAudioTrack(opt);
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),

                // Crisp vertical column separator between Audio & Subtitles
                const VerticalDivider(
                  width: 1,
                  thickness: 1,
                  indent: 8,
                  endIndent: 12,
                  color: _ModalColors.columnDivider,
                ),

                // Right column: Subtitles (Off + Embedded + Addon Subtitles)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _ColumnHeader(
                        icon: Icons.closed_caption_rounded,
                        title: 'Subtitles',
                        count: (st.subtitleOptions.length - 1).clamp(0, 999),
                      ),
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 14),
                          itemCount: st.subtitleOptions.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 4),
                          itemBuilder: (context, idx) {
                            final opt = st.subtitleOptions[idx];
                            final selected = opt.id == st.selectedSubtitleId;
                            return _TrackOptionRow(
                              title: opt.displayLabel,
                              detail: opt.detail,
                              selected: selected,
                              onTap: () {
                                HapticFeedback.selectionClick();
                                controller.selectSubtitleOption(opt);
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ColumnHeader extends StatelessWidget {
  const _ColumnHeader({
    required this.icon,
    required this.title,
    required this.count,
  });

  final IconData icon;
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 14, 6),
      child: Row(
        children: [
          Icon(icon, size: 15, color: _ModalColors.textMuted),
          const SizedBox(width: 6),
          Text(
            title,
            style: _inter(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: _ModalColors.textPrimary,
              letterSpacing: -0.2,
            ),
          ),
          const Spacer(),
          if (count > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _ModalColors.surfaceRow,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _ModalColors.hairline),
              ),
              child: Text(
                '$count',
                style: _inter(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: _ModalColors.textMuted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TrackOptionRow extends StatelessWidget {
  const _TrackOptionRow({
    required this.title,
    this.detail,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String? detail;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? _ModalColors.activeRow : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? const Color(0x28FFFFFF) : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _inter(
                        fontSize: 14,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected
                            ? _ModalColors.textPrimary
                            : const Color(0xFFD4D4D8),
                      ),
                    ),
                    if (detail != null && detail!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        detail!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _inter(
                          fontSize: 11,
                          color: _ModalColors.textFaint,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                const PlayerSvgIcon(PlayerIcons.activeCheck, size: 18),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyTrackHint extends StatelessWidget {
  const _EmptyTrackHint({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          text,
          style: _inter(
            fontSize: 12.5,
            color: _ModalColors.textFaint,
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Links / Sources Switcher Modal (Matches Figma #13161F Design System)
// ─────────────────────────────────────────────────────────────────────────────

Future<void> showPlayerLinksModal(
  BuildContext context, {
  required PlayerSessionController controller,
}) async {
  controller.onLinksModalOpened();
  try {
    await _showLandscapePlayerSheet<void>(
      context,
      builder: (_) => _PlayerLinksSheet(controller: controller),
    );
  } finally {
    controller.onLinksModalClosed();
  }
}

class _PlayerLinksSheet extends StatelessWidget {
  const _PlayerLinksSheet({required this.controller});

  final PlayerSessionController controller;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final modalWidth =
        (size.width * 0.74).clamp(320.0, 680.0).clamp(0.0, size.width - 24);
    final maxH = (size.height * 0.82).clamp(260.0, 500.0);

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final st = controller.state;
        final activeKey = st.activeStream?.dedupKey;
        final directStreams = st.rankedStreams
            .where((r) => r.stream.transport.isPlayableDirect)
            .toList(growable: false);
        final otherStreams = st.rankedStreams
            .where((r) => !r.stream.transport.isPlayableDirect)
            .toList(growable: false);

        return _PlayerModalFrame(
          width: modalWidth,
          maxHeight: maxH,
          header: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 16, 12),
            child: Row(
              children: [
                const Icon(
                  Icons.hub_rounded,
                  size: 18,
                  color: _ModalColors.textPrimary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Sources',
                  style: _inter(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: _ModalColors.textPrimary,
                    letterSpacing: -0.35,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _ModalColors.surfaceRow,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: _ModalColors.hairline),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (st.isResolvingLinks) ...[
                        const SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: _ModalColors.live,
                          ),
                        ),
                        const SizedBox(width: 5),
                      ],
                      Text(
                        '${st.rankedStreams.length}',
                        style: _inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _ModalColors.textMuted,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
                if (st.isResolvingLinks) ...[
                  const SizedBox(width: 8),
                  Text(
                    'Scanning...',
                    style: _inter(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: _ModalColors.textFaint,
                    ),
                  ),
                ] else if (st.hasMoreSources) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      controller.loadMoreSources();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _ModalColors.surfaceRow,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: _ModalColors.hairline),
                      ),
                      child: Text(
                        'Scan more',
                        style: _inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _ModalColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                _CloseModalButton(onTap: () => Navigator.of(context).pop()),
              ],
            ),
          ),
          child: st.rankedStreams.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (st.isResolvingLinks)
                        const CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        )
                      else
                        const Icon(
                          Icons.link_off_rounded,
                          size: 28,
                          color: _ModalColors.textMuted,
                        ),
                      const SizedBox(height: 10),
                      Text(
                        st.isResolvingLinks
                            ? 'Scanning installed addons & probing fastest links...'
                            : 'No stream links returned for this title.',
                        textAlign: TextAlign.center,
                        style: _inter(
                          fontSize: 13.5,
                          color: _ModalColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
                  addAutomaticKeepAlives: false,
                  addSemanticIndexes: false,
                  itemCount: directStreams.length +
                      (otherStreams.isNotEmpty ? 1 + otherStreams.length : 0),
                  itemBuilder: (context, index) {
                    if (index < directStreams.length) {
                      final item = directStreams[index];
                      return Padding(
                        padding: EdgeInsets.only(top: index == 0 ? 0 : 8),
                        child: RepaintBoundary(
                          child: _RankedStreamTile(
                            key: ValueKey(item.dedupKey),
                            ranked: item,
                            isActive: item.dedupKey == activeKey,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              Navigator.of(context).pop();
                              if (item.dedupKey != activeKey) {
                                controller.switchStream(item);
                              }
                            },
                          ),
                        ),
                      );
                    }
                    final otherOffset = index - directStreams.length;
                    if (otherOffset == 0) {
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
                        child: Text(
                          'EXTERNAL / TORRENT (${otherStreams.length})',
                          style: _inter(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.7,
                            color: _ModalColors.textFaint,
                          ),
                        ),
                      );
                    }
                    final ext = otherStreams[otherOffset - 1];
                    return Padding(
                      padding: EdgeInsets.only(top: otherOffset == 1 ? 0 : 8),
                      child: RepaintBoundary(
                        child: _RankedStreamTile(
                          key: ValueKey('ext_${ext.dedupKey}'),
                          ranked: ext,
                          isActive: false,
                          onTap: () {
                            HapticFeedback.lightImpact();
                            Navigator.of(context).pop();
                            controller.openExternalStream(ext.stream);
                          },
                        ),
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}

class _RankedStreamTile extends StatelessWidget {
  const _RankedStreamTile({
    super.key,
    required this.ranked,
    required this.isActive,
    required this.onTap,
  });

  final RankedStream ranked;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = ranked.stream;
    final isExternalOnly = !s.transport.isPlayableDirect;
    final isDead = ranked.probe != null && !ranked.probe!.isAlive;
    final speed = ranked.speedLabel;
    final langLabel = ranked.languageSummaryLabel;

    return Opacity(
      opacity: isDead ? 0.52 : 1.0,
      child: Material(
        color: isActive ? _ModalColors.activeRow : _ModalColors.surfaceRow,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isActive
                    ? const Color(0x4DFFFFFF)
                    : _ModalColors.hairline,
              ),
            ),
            child: Row(
              children: [
                // Resolution / Transport Pill
                Container(
                  constraints: const BoxConstraints(minWidth: 52),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: ranked.meta.resolutionHeight >= 2160
                        ? _ModalColors.cautionFill
                        : (isActive
                            ? _ModalColors.liveFill
                            : const Color(0xFF0E1118)),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: ranked.meta.resolutionHeight >= 2160
                          ? _ModalColors.cautionBorder
                          : (isActive
                              ? _ModalColors.liveBorder
                              : _ModalColors.hairline),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        ranked.resolutionBadge,
                        style: _inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: ranked.meta.resolutionHeight >= 2160
                              ? _ModalColors.caution
                              : (isActive
                                  ? _ModalColors.live
                                  : _ModalColors.textPrimary),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        s.transport.badgeLabel,
                        style: _inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: _ModalColors.textFaint,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                // Stream title + provider + codec/language/speed pills
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${s.providerName} · ${s.addonName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _inter(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: _ModalColors.textPrimary,
                              ),
                            ),
                          ),
                          if (speed != null)
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _ModalColors.liveFill,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: _ModalColors.liveBorder,
                                ),
                              ),
                              child: Text(
                                speed,
                                style: _inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: _ModalColors.live,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            )
                          else if (isDead)
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0x28FF4D58),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'Offline',
                                style: _inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFFFF8F95),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        s.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _inter(
                          fontSize: 11.5,
                          color: _ModalColors.textMuted,
                        ),
                      ),
                      if (langLabel != null ||
                          ranked.codecSummaryBadges.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 5,
                          runSpacing: 4,
                          children: [
                            if (langLabel != null)
                              _TinySourceChip(
                                langLabel,
                                highlight: ranked.languageMatchTier ==
                                        LanguageMatchTier.primaryDirect ||
                                    ranked.languageMatchTier ==
                                        LanguageMatchTier.primaryMultiAudio,
                              ),
                            for (final chip in ranked.codecSummaryBadges)
                              _TinySourceChip(chip),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(width: 8),
                if (isActive)
                  const PlayerSvgIcon(PlayerIcons.activeCheck, size: 20)
                else if (isExternalOnly)
                  const Icon(
                    Icons.open_in_new_rounded,
                    size: 16,
                    color: _ModalColors.textMuted,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TinySourceChip extends StatelessWidget {
  const _TinySourceChip(this.label, {this.highlight = false});

  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: highlight ? _ModalColors.liveFill : const Color(0xFF222736),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: highlight ? _ModalColors.liveBorder : _ModalColors.hairline,
        ),
      ),
      child: Text(
        label,
        style: _inter(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: highlight ? _ModalColors.live : _ModalColors.textMuted,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Playback Speed & Settings Modals
// ─────────────────────────────────────────────────────────────────────────────

Future<void> showPlayerSpeedModal(
  BuildContext context, {
  required PlayerSessionController controller,
}) =>
    _showLandscapePlayerSheet<void>(
      context,
      builder: (_) => _PlayerSpeedSheet(controller: controller),
    );

class _PlayerSpeedSheet extends StatelessWidget {
  const _PlayerSpeedSheet({required this.controller});
  final PlayerSessionController controller;

  static const _rates = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final modalWidth = (size.width * 0.44).clamp(280.0, 400.0);
    final maxH = (size.height * 0.76).clamp(220.0, 420.0);

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final cur = controller.state.playbackSpeed;
        return _PlayerModalFrame(
          width: modalWidth,
          maxHeight: maxH,
          header: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Playback Speed',
                    style: _inter(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: _ModalColors.textPrimary,
                    ),
                  ),
                ),
                _CloseModalButton(onTap: () => Navigator.of(context).pop()),
              ],
            ),
          ),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            shrinkWrap: true,
            itemCount: _rates.length,
            separatorBuilder: (_, __) => const SizedBox(height: 4),
            itemBuilder: (context, i) {
              final r = _rates[i];
              final label = r == 1.0 ? '1x · Normal' : '${r}x';
              final selected = (cur - r).abs() < 0.01;
              return _TrackOptionRow(
                title: label,
                selected: selected,
                onTap: () {
                  HapticFeedback.selectionClick();
                  controller.setSpeed(r);
                  Navigator.of(context).pop();
                },
              );
            },
          ),
        );
      },
    );
  }
}

Future<void> showPlayerSettingsModal(
  BuildContext context, {
  required PlayerSessionController controller,
  required PlaybackPreferences initialPrefs,
  required VoidCallback onOpenLanguagePicker,
}) =>
    _showLandscapePlayerSheet<void>(
      context,
      builder: (_) => _PlayerSettingsSheet(
        controller: controller,
        initialPrefs: initialPrefs,
        onOpenLanguagePicker: onOpenLanguagePicker,
      ),
    );

class _PlayerSettingsSheet extends StatefulWidget {
  const _PlayerSettingsSheet({
    required this.controller,
    required this.initialPrefs,
    required this.onOpenLanguagePicker,
  });

  final PlayerSessionController controller;
  final PlaybackPreferences initialPrefs;
  final VoidCallback onOpenLanguagePicker;

  @override
  State<_PlayerSettingsSheet> createState() => _PlayerSettingsSheetState();
}

class _PlayerSettingsSheetState extends State<_PlayerSettingsSheet> {
  late bool _autoPlayNext;
  late bool _autoSkipIntroRecap;
  late bool _autoSkipOutro;
  late bool _hwDecode;
  late double _subScale;

  @override
  void initState() {
    super.initState();
    _autoPlayNext = widget.initialPrefs.autoPlayNextEpisode;
    _autoSkipIntroRecap = widget.initialPrefs.autoSkipIntroRecap;
    _autoSkipOutro = widget.initialPrefs.autoSkipOutro;
    _hwDecode = widget.initialPrefs.hardwareDecoding;
    _subScale = widget.initialPrefs.subtitleScale;
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final modalWidth =
        (size.width * 0.56).clamp(300.0, 500.0).clamp(0.0, size.width - 24);
    final maxH = (size.height * 0.80).clamp(240.0, 440.0);

    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final st = widget.controller.state;
        return _PlayerModalFrame(
          width: modalWidth,
          maxHeight: maxH,
          header: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Player Settings',
                    style: _inter(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: _ModalColors.textPrimary,
                    ),
                  ),
                ),
                _CloseModalButton(onTap: () => Navigator.of(context).pop()),
              ],
            ),
          ),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            shrinkWrap: true,
            children: [
              Text(
                'ASPECT RATIO',
                style: _inter(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7,
                  color: _ModalColors.textFaint,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  for (var i = 0; i < VideoFitMode.values.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          widget.controller.setFitMode(VideoFitMode.values[i]);
                        },
                        child: Container(
                          height: 36,
                          decoration: BoxDecoration(
                            color: st.fitMode == VideoFitMode.values[i]
                                ? Colors.white
                                : _ModalColors.surfaceRow,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _ModalColors.hairline),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            VideoFitMode.values[i].label,
                            style: _inter(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: st.fitMode == VideoFitMode.values[i]
                                  ? Colors.black
                                  : _ModalColors.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    'Subtitle Size',
                    style: _inter(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: _ModalColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${(_subScale * 100).round()}%',
                    style: _inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _ModalColors.textMuted,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              Slider(
                value: _subScale,
                min: 0.7,
                max: 1.5,
                divisions: 8,
                activeColor: Colors.white,
                inactiveColor: _ModalColors.dragHandle,
                onChanged: (v) {
                  setState(() => _subScale = v);
                  widget.controller.setSubtitleScale(v);
                },
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Auto-play next episode',
                  style: _inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: _ModalColors.textPrimary,
                  ),
                ),
                value: _autoPlayNext,
                activeThumbColor: Colors.white,
                onChanged: (v) {
                  setState(() => _autoPlayNext = v);
                  widget.controller.setAutoPlayNext(v);
                },
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Auto-skip intro & recap',
                  style: _inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: _ModalColors.textPrimary,
                  ),
                ),
                value: _autoSkipIntroRecap,
                activeThumbColor: Colors.white,
                onChanged: (v) {
                  setState(() => _autoSkipIntroRecap = v);
                  widget.controller.setAutoSkipIntroRecap(v);
                },
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Auto-skip outro',
                  style: _inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: _ModalColors.textPrimary,
                  ),
                ),
                value: _autoSkipOutro,
                activeThumbColor: Colors.white,
                onChanged: (v) {
                  setState(() => _autoSkipOutro = v);
                  widget.controller.setAutoSkipOutro(v);
                },
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Hardware decoding',
                  style: _inter(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: _ModalColors.textPrimary,
                  ),
                ),
                value: _hwDecode,
                activeThumbColor: Colors.white,
                onChanged: (v) {
                  setState(() => _hwDecode = v);
                  widget.controller.setHardwareDecoding(v);
                },
              ),
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.onOpenLanguagePicker();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: _ModalColors.hairline),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.translate_rounded, size: 16),
                label: Text(
                  'Change Watch Languages',
                  style: _inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
