import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/utils/responsive.dart';
import '../../../details/presentation/widgets/detail_widgets.dart' show DetailBackButton;
import '../../../home/presentation/widgets/shimmer_loading.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Tokens
// ─────────────────────────────────────────────────────────────────────────────

/// Semantic colour tokens for every Addons surface. Values come from the Addons
/// Figma frame (116:23) and the app's existing Profile / Details / My List
/// screens so the new screens sit in the same black, hairline-bordered family.
abstract final class AddonsColors {
  static const canvas = Color(0xFF000000);
  static const composer = Color(0xFF191A1E);
  static const card = Color(0xFF141414);
  static const input = Color(0xFF0A0A0A);

  static const hairline = Color(0xFF27272A);
  static const hairlineStrong = Color(0xFF3F3F46);
  static const hairlineFocus = Color(0xFF71717A);
  static const specular = Color(0x14FFFFFF);
  static const ghostFill = Color(0x05FFFFFF);
  static const ghostBorder = Color(0x0FFFFFFF);

  static const tagFill = Color(0xFF1F1F22);
  static const tagBorder = Color(0xFF2F2F35);
  static const badgeFill = Color(0xFF262626);
  static const badgeBorder = Color(0xFF333333);
  static const monogramTop = Color(0xFF2A2A2D);
  static const monogramBottom = Color(0xFF1C1C1F);

  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFFE4E4E7);
  static const textMuted = Color(0xFFA1A1AA);
  static const textFaint = Color(0xFF71717A);
  static const tabInactive = Color(0xFF737373);
  static const divider = Color(0xFF171717);
  static const onLight = Color(0xFF000000);

  static const live = Color(0xFF4ADE80);
  static const liveFill = Color(0x1A4ADE80);
  static const liveBorder = Color(0x334ADE80);
  static const caution = Color(0xFFFBBF24);
  static const cautionFill = Color(0x1AFBBF24);
  static const cautionBorder = Color(0x33FBBF24);
  static const dangerText = Color(0xFFFF8F95);
  static const dangerFill = Color(0x40FF0360);
  static const dangerBorder = Color(0xFF923741);
  static const dangerHairline = Color(0x66923741);

  static const sheetHandle = Color(0xFF363B47);
  static const sheetClose = Color(0xFF242A37);
  static const sheetCloseIcon = Color(0xFFD4D4D4);
  static const focusRing = Color(0xB8FFFFFF);
  static const toast = Color(0xFF16181C);
  static const errorToast = Color(0xFF3A1419);
  static const scrim = Color(0xB3000000);
  static const shadow = Color(0x66000000);
}

/// Motion tokens: the app-wide `Cubic(0.22, 1, 0.36, 1)` curve and the
/// 160–260ms band used by Collections, Profile and Details.
abstract final class AddonsMotion {
  static const Curve emphasized = Cubic(0.22, 1.0, 0.36, 1.0);
  static const Duration press = Duration(milliseconds: 160);
  static const Duration quick = Duration(milliseconds: 180);
  static const Duration standard = Duration(milliseconds: 220);
  static const Duration route = Duration(milliseconds: 260);

  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// Collapses [value] to zero when the OS asks for reduced motion.
  static Duration d(BuildContext context, Duration value) =>
      reduced(context) ? Duration.zero : value;
}

abstract final class AddonsText {
  static TextStyle inter(
    double size, {
    FontWeight weight = FontWeight.w400,
    Color color = AddonsColors.textPrimary,
    double? height,
    double letterSpacing = 0,
    bool tabular = false,
  }) =>
      GoogleFonts.inter(
        fontSize: size.sp,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
        fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
      );

  static TextStyle mono(double size, {Color color = AddonsColors.textSecondary, double? height}) =>
      GoogleFonts.robotoMono(fontSize: size.sp, color: color, height: height);

  static TextStyle pageTitle([double size = 30]) => inter(
        size,
        weight: FontWeight.w700,
        height: 1.2,
        letterSpacing: -0.025 * size,
      );

  static TextStyle sectionTitle() =>
      inter(20, weight: FontWeight.w700, height: 28 / 20, letterSpacing: -0.5);

  static TextStyle body({Color color = AddonsColors.textMuted}) =>
      inter(13, color: color, height: 1.55);

  static TextStyle eyebrow() => inter(
        10,
        weight: FontWeight.w600,
        color: AddonsColors.textFaint,
        height: 15 / 10,
        letterSpacing: 0.6,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Icons (24-unit, white strokes — tinted at runtime)
// ─────────────────────────────────────────────────────────────────────────────

abstract final class AddonIcons {
  static const _o = '<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">';
  static const _s = 'stroke="white" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"';

  static const downloads =
      '$_o<path d="M12 4V15M12 15L8.5 11.5M12 15L15.5 11.5" $_s/><path d="M4 19H20" $_s/></svg>';
  static const plus = '$_o<path d="M12 5V19M19 12H5" stroke="white" stroke-width="2.2" stroke-linecap="round"/></svg>';
  static const tick =
      '<svg viewBox="0 0 8 8" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M7.14893 0.220215C5.39795 2.71956 3.59863 5.03271 1.75098 7.15967C1.61133 7.3208 1.48958 7.40137 1.38574 7.40137C1.26758 7.40137 1.05452 7.08984 0.746582 6.4668C0.248861 5.46061 0 4.85905 0 4.66211C0 4.59049 0.0483398 4.50635 0.14502 4.40967C0.352702 4.19124 0.499512 4.08203 0.585449 4.08203C0.664225 4.08203 0.748372 4.20736 0.837891 4.45801C1.07422 5.09538 1.32308 5.66292 1.58447 6.16064C3.39632 4.32731 5.18848 2.27376 6.96094 0L7.14893 0.220215Z" fill="white"/></svg>';
  static const check = '$_o<path d="M5 12.5L9.5 17L19 7.5" stroke="white" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/></svg>';
  static const close = '$_o<path d="M6 18L18 6M6 6L18 18" $_s/></svg>';
  static const gear =
      '$_o<path d="M10.3 4.3c.43-1.75 2.93-1.75 3.36 0a1.73 1.73 0 0 0 2.58 1.07c1.54-.94 3.31.83 2.37 2.37a1.73 1.73 0 0 0 1.07 2.58c1.75.43 1.75 2.93 0 3.36a1.73 1.73 0 0 0-1.07 2.58c.94 1.54-.83 3.31-2.37 2.37a1.73 1.73 0 0 0-2.58 1.07c-.43 1.75-2.93 1.75-3.36 0a1.73 1.73 0 0 0-2.58-1.07c-1.54.94-3.31-.83-2.37-2.37a1.73 1.73 0 0 0-1.07-2.58c-1.75-.43-1.75-2.93 0-3.36a1.73 1.73 0 0 0 1.07-2.58c-.94-1.54.83-3.31 2.37-2.37 1 .6 2.3.07 2.58-1.07Z" $_s/><circle cx="12" cy="12" r="3" $_s/></svg>';
  static const trash =
      '$_o<path d="M19 7l-.87 12.14A2 2 0 0 1 16.14 21H7.86a2 2 0 0 1-1.99-1.86L5 7M10 11v6M14 11v6M15 7V4a1 1 0 0 0-1-1h-4a1 1 0 0 0-1 1v3M4 7h16" $_s/></svg>';
  static const cloud =
      '$_o<path d="M7 18.5h10.5a4 4 0 0 0 .6-7.96A5.5 5.5 0 0 0 7.4 9.1 4.75 4.75 0 0 0 7 18.5Z" $_s/></svg>';
  static const play = '$_o<path d="M8 5.5v13l10-6.5-10-6.5Z" fill="white"/></svg>';
  static const shield =
      '$_o<path d="M12 3l7.5 3v5.5c0 4.6-3.2 8.4-7.5 9.5-4.3-1.1-7.5-4.9-7.5-9.5V6L12 3Z" $_s/><path d="M8.8 12.2l2.2 2.2 4.4-4.6" $_s/></svg>';
  static const search = '$_o<circle cx="11" cy="11" r="6.5" $_s/><path d="M16 16l4 4" $_s/></svg>';
  static const pencil = '$_o<path d="M4 20h4L19 9a2.83 2.83 0 0 0-4-4L4 16v4Z" $_s/><path d="M13.5 6.5l4 4" $_s/></svg>';
  static const refresh =
      '$_o<path d="M20 11a8 8 0 0 0-14.9-3.5M4 4v4h4M4 13a8 8 0 0 0 14.9 3.5M20 20v-4h-4" $_s/></svg>';
  static const sparkle =
      '$_o<path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8L12 3Z" $_s/><path d="M19 15.5l.7 1.8 1.8.7-1.8.7-.7 1.8-.7-1.8-1.8-.7 1.8-.7.7-1.8Z" $_s/></svg>';
  static const layers = '$_o<path d="M12 3l9 5-9 5-9-5 9-5Z" $_s/><path d="M3 13l9 5 9-5" $_s/></svg>';
  static const subtitles =
      '$_o<rect x="3" y="5" width="18" height="14" rx="3" $_s/><path d="M7 12h3M13 12h4M7 15.5h6M15.5 15.5h1.5" $_s/></svg>';
  static const info = '$_o<circle cx="12" cy="12" r="9" $_s/><path d="M12 11v5M12 8h.01" $_s/></svg>';
  static const alert = '$_o<circle cx="12" cy="12" r="9" $_s/><path d="M12 7.5V13M12 16.2h.01" $_s/></svg>';
  static const chevronRight = '$_o<path d="M9 6l6 6-6 6" $_s/></svg>';
  static const link =
      '$_o<path d="M10 14a4 4 0 0 0 5.66 0l3-3a4 4 0 0 0-5.66-5.66l-1 1" $_s/><path d="M14 10a4 4 0 0 0-5.66 0l-3 3a4 4 0 0 0 5.66 5.66l1-1" $_s/></svg>';
  static const globe =
      '$_o<circle cx="12" cy="12" r="9" $_s/><path d="M3 12h18M12 3c2.5 2.7 3.5 5.7 3.5 9s-1 6.3-3.5 9c-2.5-2.7-3.5-5.7-3.5-9s1-6.3 3.5-9Z" $_s/></svg>';
  static const clipboard =
      '$_o<path d="M9 5H7.5A2.5 2.5 0 0 0 5 7.5v11A2.5 2.5 0 0 0 7.5 21h9a2.5 2.5 0 0 0 2.5-2.5v-11A2.5 2.5 0 0 0 16.5 5H15" $_s/><rect x="9" y="3" width="6" height="4" rx="1.2" $_s/></svg>';
  static const copy =
      '$_o<rect x="8" y="8" width="12" height="12" rx="2.5" $_s/><path d="M16 8V6.5A2.5 2.5 0 0 0 13.5 4h-7A2.5 2.5 0 0 0 4 6.5v7A2.5 2.5 0 0 0 6.5 16H8" $_s/></svg>';
  static const home =
      '$_o<path d="M4 10.5L12 4l8 6.5V19a1.5 1.5 0 0 1-1.5 1.5h-4.5v-5.5h-4v5.5H5.5A1.5 1.5 0 0 1 4 19v-8.5Z" $_s/></svg>';
  static const film =
      '$_o<rect x="3" y="5" width="18" height="14" rx="2.5" $_s/><path d="M7 5v14M17 5v14M3 9.5h4M17 9.5h4M3 14.5h4M17 14.5h4" $_s/></svg>';
  static const tv =
      '$_o<rect x="3" y="6.5" width="18" height="12.5" rx="2.5" $_s/><path d="M8.5 3.5L12 6.5l3.5-3" $_s/></svg>';
  static const grid =
      '$_o<rect x="4" y="4" width="6.5" height="6.5" rx="1.5" $_s/><rect x="13.5" y="4" width="6.5" height="6.5" rx="1.5" $_s/><rect x="4" y="13.5" width="6.5" height="6.5" rx="1.5" $_s/><rect x="13.5" y="13.5" width="6.5" height="6.5" rx="1.5" $_s/></svg>';
  static const eyeOff =
      '$_o<path d="M3 3l18 18M10.6 5.1A9.7 9.7 0 0 1 12 5c5 0 8.5 4.5 9.5 7-.4 1-1.2 2.3-2.4 3.5M6.3 6.3C4.3 7.6 3 9.6 2.5 12c1 2.5 4.5 7 9.5 7 1.7 0 3.2-.5 4.5-1.3M9.9 9.9a3 3 0 0 0 4.2 4.2" $_s/></svg>';
  static const puzzle =
      '<svg viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M9.05484 1.68828C10.0032 1.82578 10.7473 2.64245 10.8082 3.59745C10.8207 3.79578 10.8057 3.97245 10.764 4.16661C10.7182 4.38328 10.5382 4.62411 10.6748 4.84245C10.7407 4.94911 10.8365 4.98745 10.9557 4.99995H12.4998C13.1673 5.02245 13.7898 5.25411 14.2673 5.73245C14.7457 6.20995 14.9773 6.83245 14.9998 7.49995V9.04411C15.0098 9.13411 15.0165 9.18328 15.0748 9.25411C15.2407 9.45495 15.4565 9.34995 15.6565 9.28495C15.8107 9.23411 15.954 9.20578 16.119 9.19328C16.4923 9.16546 16.8661 9.2404 17.1998 9.40995C18.8173 10.2274 18.6548 12.6024 16.9457 13.1983C16.6815 13.2899 16.3982 13.3283 16.119 13.3066C15.9617 13.2952 15.8063 13.2644 15.6565 13.2149C15.4257 13.1399 15.1415 13.0233 15.0198 13.3408L14.9998 13.4558V15.8333C14.9582 17.0849 14.109 18.1391 12.839 18.3108L12.4998 18.3333H10.9223C10.8332 18.3233 10.7873 18.3183 10.7165 18.2616C10.4665 18.0658 10.6482 17.7483 10.6682 17.4999C10.6823 17.3191 10.674 17.1499 10.639 16.9716C10.5401 16.4873 10.2602 16.0589 9.85635 15.7739C9.45251 15.4888 8.95515 15.3685 8.46567 15.4374C8.07339 15.4984 7.70923 15.6782 7.42225 15.9525C7.13527 16.2268 6.93928 16.5825 6.86067 16.9716C6.82657 17.1455 6.81675 17.3233 6.8315 17.4999C6.85234 17.7683 7.059 18.1766 6.68984 18.3141L6.57734 18.3333H4.1665C3.90984 18.3249 3.74984 18.3116 3.5015 18.2441C2.38817 17.9383 1.70484 16.9633 1.6665 15.8333V13.4224C1.6765 13.3333 1.6815 13.2874 1.73817 13.2166C1.934 12.9666 2.2515 13.1483 2.49984 13.1683C2.68067 13.1824 2.84984 13.1741 3.02817 13.1391C3.46476 13.0504 3.85756 12.8143 4.14069 12.4703C4.42382 12.1263 4.58005 11.6954 4.58317 11.2499C4.58005 10.8044 4.42382 10.3736 4.14069 10.0296C3.85756 9.68563 3.46476 9.44949 3.02817 9.36078C2.85425 9.32668 2.67645 9.31686 2.49984 9.33161C2.2515 9.35161 1.934 9.53328 1.73817 9.28328C1.6815 9.21161 1.6765 9.16661 1.6665 9.07745V7.49995C1.67484 7.24328 1.68817 7.08328 1.75567 6.83495C1.86984 6.41995 2.094 6.03661 2.399 5.73245C2.8765 5.25411 3.499 5.02245 4.1665 4.99995H6.544C6.634 4.98995 6.68317 4.98328 6.754 4.92495C7.0065 4.71661 6.78734 4.40911 6.73567 4.16661C6.69381 3.97998 6.67893 3.7883 6.6915 3.59745C6.76734 2.40495 7.87567 1.51828 9.05484 1.68828Z" fill="white"/></svg>';
}

class AddonIcon extends StatelessWidget {
  const AddonIcon(this.svg, {super.key, this.size = 16, this.color = AddonsColors.textPrimary});

  final String svg;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SvgPicture.string(
        svg,
        width: size.r,
        height: size.r,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Interaction primitives
// ─────────────────────────────────────────────────────────────────────────────

enum AddonHaptic { none, selection, light, medium }

void addonHaptic(AddonHaptic haptic) {
  switch (haptic) {
    case AddonHaptic.none:
      break;
    case AddonHaptic.selection:
      HapticFeedback.selectionClick();
    case AddonHaptic.light:
      HapticFeedback.lightImpact();
    case AddonHaptic.medium:
      HapticFeedback.mediumImpact();
  }
}

/// The single tappable surface every Addons control is built on:
/// `scale(0.98)` press, haptic tick, 2px focus ring, and a 42% disabled dim.
/// [busy] blocks taps without dimming (used while a button shows progress).
class AddonPressable extends StatefulWidget {
  const AddonPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.borderRadius = 10,
    this.color = Colors.transparent,
    this.borderColor,
    this.haptic = AddonHaptic.selection,
    this.semanticLabel,
    this.selected,
    this.busy = false,
    this.onLight = false,
    this.pressedScale = 0.98,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double borderRadius;
  final Color color;
  final Color? borderColor;
  final AddonHaptic haptic;
  final String? semanticLabel;
  final bool? selected;
  final bool busy;
  final bool onLight;
  final double pressedScale;

  @override
  State<AddonPressable> createState() => _AddonPressableState();
}

class _AddonPressableState extends State<AddonPressable> {
  bool _pressed = false;
  bool _focused = false;

  bool get _interactive => widget.onTap != null && !widget.busy;

  @override
  void didUpdateWidget(covariant AddonPressable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_interactive && _pressed) _pressed = false;
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(widget.borderRadius);
    final duration = AddonsMotion.d(context, AddonsMotion.press);
    final dimmed = widget.onTap == null && !widget.busy;

    return Semantics(
      button: true,
      enabled: _interactive,
      selected: widget.selected,
      label: widget.semanticLabel,
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: duration,
        curve: AddonsMotion.emphasized,
        child: AnimatedOpacity(
          opacity: dimmed ? 0.42 : 1.0,
          duration: duration,
          curve: AddonsMotion.emphasized,
          child: Material(
            color: widget.color,
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: widget.borderColor == null ? BorderSide.none : BorderSide(color: widget.borderColor!),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _interactive
                  ? () {
                      addonHaptic(widget.haptic);
                      widget.onTap!();
                    }
                  : null,
              onLongPress: widget.onLongPress,
              onHighlightChanged: _interactive ? (v) => setState(() => _pressed = v) : null,
              onFocusChange: (v) => setState(() => _focused = v),
              splashColor: widget.onLight ? const Color(0x14000000) : const Color(0x14FFFFFF),
              highlightColor: widget.onLight ? const Color(0x0A000000) : const Color(0x0AFFFFFF),
              child: DecoratedBox(
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: _focused ? Border.all(color: AddonsColors.focusRing, width: 2) : null,
                ),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum AddonButtonVariant { primary, secondary, danger, ghost }

enum AddonButtonPhase { idle, loading, success }

/// White primary / dark secondary / danger / ghost button. Label, progress and
/// success morph into each other through a scale+fade cross-switch.
class AddonsButton extends StatelessWidget {
  const AddonsButton({
    super.key,
    required this.label,
    this.onTap,
    this.iconSvg,
    this.variant = AddonButtonVariant.primary,
    this.phase = AddonButtonPhase.idle,
    this.loadingLabel,
    this.successLabel,
    this.height = 44,
    this.expand = true,
    this.compact = false,
    this.haptic = AddonHaptic.light,
  });

  final String label;
  final VoidCallback? onTap;
  final String? iconSvg;
  final AddonButtonVariant variant;
  final AddonButtonPhase phase;
  final String? loadingLabel;
  final String? successLabel;
  final double height;
  final bool expand;
  final bool compact;
  final AddonHaptic haptic;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg, Color? border) = switch (variant) {
      AddonButtonVariant.primary => (AddonsColors.textPrimary, AddonsColors.onLight, null),
      AddonButtonVariant.secondary => (AddonsColors.tagFill, AddonsColors.textSecondary, AddonsColors.tagBorder),
      AddonButtonVariant.danger => (AddonsColors.dangerFill, AddonsColors.textPrimary, AddonsColors.dangerBorder),
      AddonButtonVariant.ghost => (Colors.transparent, AddonsColors.textSecondary, AddonsColors.hairline),
    };
    final style = AddonsText.inter(
      compact ? 12.5 : 13.5,
      weight: FontWeight.w700,
      color: fg,
      height: 1.2,
      letterSpacing: 0.2,
    );
    final iconSize = compact ? 14.0 : 16.0;

    final Widget content = switch (phase) {
      AddonButtonPhase.idle => Row(
          key: ValueKey('idle-$label'),
          mainAxisSize: MainAxisSize.min,
          children: [
            if (iconSvg != null) ...[
              AddonIcon(iconSvg!, size: iconSize, color: fg),
              const SizedBox(width: 8),
            ],
            Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: style)),
          ],
        ),
      AddonButtonPhase.loading => Row(
          key: const ValueKey('loading'),
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 1.8, color: fg),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(loadingLabel ?? label, maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
            ),
          ],
        ),
      AddonButtonPhase.success => Row(
          key: const ValueKey('success'),
          mainAxisSize: MainAxisSize.min,
          children: [
            AddonPopIn(child: AddonIcon(AddonIcons.check, size: iconSize, color: fg)),
            const SizedBox(width: 6),
            Flexible(
              child: Text(successLabel ?? 'Done', maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
            ),
          ],
        ),
    };

    return SizedBox(
      height: height.h,
      width: expand ? double.infinity : null,
      child: AddonPressable(
        color: bg,
        borderColor: border,
        borderRadius: 10.r,
        onTap: onTap,
        busy: phase != AddonButtonPhase.idle,
        onLight: variant == AddonButtonVariant.primary,
        haptic: haptic,
        semanticLabel: label,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: (compact ? 12 : 16).w),
          child: Center(
            child: AnimatedSwitcher(
              duration: AddonsMotion.d(context, AddonsMotion.standard),
              switchInCurve: AddonsMotion.emphasized,
              switchOutCurve: AddonsMotion.emphasized,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: ScaleTransition(scale: Tween<double>(begin: 0.94, end: 1).animate(anim), child: child),
              ),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

/// Small elastic pop used for checkmarks the moment something becomes true.
class AddonPopIn extends StatelessWidget {
  const AddonPopIn({super.key, required this.child, this.from = 0.4});

  final Widget child;
  final double from;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: from, end: 1),
        duration: AddonsMotion.d(context, const Duration(milliseconds: 320)),
        curve: Curves.easeOutBack,
        child: child,
        builder: (_, v, c) => Transform.scale(scale: v, child: c),
      );
}

/// Compact iOS-weight switch: white track when on, thumb glides on transform.
class AddonSwitch extends StatelessWidget {
  const AddonSwitch({super.key, required this.value, required this.onChanged, this.semanticLabel});

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final d = AddonsMotion.d(context, AddonsMotion.standard);
    return Semantics(
      toggled: value,
      label: semanticLabel,
      child: AddonPressable(
        borderRadius: 999,
        pressedScale: 0.94,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: SizedBox(
          width: 40,
          height: 24,
          child: Stack(
            children: [
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AddonsColors.tagFill,
                    borderRadius: BorderRadius.all(Radius.circular(999)),
                    border: Border.fromBorderSide(BorderSide(color: AddonsColors.hairlineStrong)),
                  ),
                ),
              ),
              Positioned.fill(
                child: AnimatedOpacity(
                  opacity: value ? 1 : 0,
                  duration: d,
                  curve: AddonsMotion.emphasized,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      color: AddonsColors.textPrimary,
                      borderRadius: BorderRadius.all(Radius.circular(999)),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 3,
                top: 3,
                child: AnimatedSlide(
                  offset: Offset(value ? 16 / 18 : 0, 0),
                  duration: d,
                  curve: AddonsMotion.emphasized,
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: Stack(
                      children: [
                        const Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(color: AddonsColors.textMuted, shape: BoxShape.circle),
                          ),
                        ),
                        Positioned.fill(
                          child: AnimatedOpacity(
                            opacity: value ? 1 : 0,
                            duration: d,
                            child: const DecoratedBox(
                              decoration: BoxDecoration(color: AddonsColors.onLight, shape: BoxShape.circle),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Visual atoms
// ─────────────────────────────────────────────────────────────────────────────

/// Geometric monochrome monogram badge (Figma "Geometric Monochrome Monogram
/// Badge"): initials on a soft top-lit tile, with an optional source glyph
/// (play = Stremio, cloud = CloudStream) docked bottom-right.
class AddonMonogram extends StatelessWidget {
  const AddonMonogram({super.key, required this.label, this.size = 44, this.radius = 10, this.kindGlyph});

  final String label;
  final double size;
  final double radius;
  final String? kindGlyph;

  static String initialsOf(String label) {
    final words = label
        .replaceAll(RegExp(r'[^A-Za-z0-9 ]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) {
      final w = words.first;
      return w.substring(0, math.min(2, w.length)).toUpperCase();
    }
    return (words[0][0] + words[1][0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(color: AddonsColors.badgeBorder),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [AddonsColors.monogramTop, AddonsColors.monogramBottom],
                  ),
                ),
                child: Center(
                  child: Text(
                    initialsOf(label),
                    maxLines: 1,
                    style: AddonsText.inter(
                      size * 0.34,
                      weight: FontWeight.w700,
                      letterSpacing: -0.4,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ),
            if (kindGlyph != null)
              Positioned(
                right: -4,
                bottom: -4,
                child: Container(
                  width: 18,
                  height: 18,
                  decoration: BoxDecoration(
                    color: AddonsColors.canvas,
                    shape: BoxShape.circle,
                    border: Border.all(color: AddonsColors.badgeBorder),
                  ),
                  alignment: Alignment.center,
                  child: AddonIcon(kindGlyph!, size: 10, color: AddonsColors.textSecondary),
                ),
              ),
          ],
        ),
      );
}

/// Figma "Background+Border" target tag: 8px radius, #1F1F22 fill, 11px label.
class AddonTag extends StatelessWidget {
  const AddonTag(this.label, {super.key, this.iconSvg, this.dense = false, this.iconColor});

  final String label;
  final String? iconSvg;
  final bool dense;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 8, vertical: dense ? 1 : 2),
        decoration: BoxDecoration(
          color: AddonsColors.tagFill,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AddonsColors.tagBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (iconSvg != null) ...[
              AddonIcon(iconSvg!, size: dense ? 10 : 11, color: iconColor ?? AddonsColors.textMuted),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AddonsText.inter(dense ? 10 : 11, color: AddonsColors.textSecondary, height: 1.5),
              ),
            ),
          ],
        ),
      );
}

enum AddonBadgeTone { neutral, live, caution, danger }

/// Tiny status badge ("Official", "Paused", "Update").
class AddonBadge extends StatelessWidget {
  const AddonBadge(this.label, {super.key, this.tone = AddonBadgeTone.neutral});

  final String label;
  final AddonBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final (Color fill, Color border, Color text) = switch (tone) {
      AddonBadgeTone.neutral => (AddonsColors.badgeFill, AddonsColors.badgeBorder, AddonsColors.textSecondary),
      AddonBadgeTone.live => (AddonsColors.liveFill, AddonsColors.liveBorder, AddonsColors.live),
      AddonBadgeTone.caution => (AddonsColors.cautionFill, AddonsColors.cautionBorder, AddonsColors.caution),
      AddonBadgeTone.danger => (AddonsColors.dangerFill, AddonsColors.dangerHairline, AddonsColors.dangerText),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      child: Text(label, maxLines: 1, style: AddonsText.inter(10, color: text, height: 1.5, weight: FontWeight.w500)),
    );
  }
}

class AddonsSectionHeader extends StatelessWidget {
  const AddonsSectionHeader({super.key, required this.iconSvg, required this.title, this.caption, this.trailing});

  final String iconSvg;
  final String title;
  final String? caption;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: AddonsColors.card,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: AddonsColors.hairline),
            ),
            alignment: Alignment.center,
            child: AddonIcon(iconSvg, size: 15, color: AddonsColors.textSecondary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AddonsText.inter(14.5, weight: FontWeight.w700, letterSpacing: -0.3, height: 1.25),
                ),
                if (caption != null && caption!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    caption!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AddonsText.inter(11.5, color: AddonsColors.textFaint, height: 1.3, tabular: true),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      );
}

/// Shared MainHeader for Addons routes: 56px, `12 12 16 8` padding, back
/// chevron, 30px title, trailing quick action — identical to My List / Liked.
class AddonsPageHeader extends StatelessWidget {
  const AddonsPageHeader({
    super.key,
    required this.title,
    required this.onBack,
    this.trailing,
    this.titleSize = 30,
    this.onTitleLongPress,
  });

  final String title;
  final VoidCallback onBack;
  final Widget? trailing;
  final double titleSize;
  final VoidCallback? onTitleLongPress;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 56.h,
        child: Padding(
          padding: EdgeInsets.fromLTRB(12.w, 12.h, 16.w, 8.h),
          child: Row(
            children: [
              DetailBackButton(onTap: onBack),
              SizedBox(width: 8.w),
              Expanded(
                child: GestureDetector(
                  onLongPress: onTitleLongPress,
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AddonsText.pageTitle(titleSize),
                  ),
                ),
              ),
              if (trailing != null) ...[SizedBox(width: 8.w), trailing!],
            ],
          ),
        ),
      );
}

class AddonHeaderIconButton extends StatelessWidget {
  const AddonHeaderIconButton({super.key, required this.svg, required this.label, required this.onTap});

  final String svg;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 32.r,
        height: 32.r,
        child: AddonPressable(
          borderRadius: 999,
          semanticLabel: label,
          onTap: onTap,
          child: Center(child: AddonIcon(svg, size: 24, color: const Color(0xF2FFFFFF))),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Motion helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Staggered entrance: fade + 14px rise, 45ms apart, capped at 8 steps.
class AddonStaggerIn extends StatefulWidget {
  const AddonStaggerIn({
    super.key,
    required this.index,
    required this.child,
    this.step = const Duration(milliseconds: 45),
    this.maxSteps = 8,
  });

  final int index;
  final Widget child;
  final Duration step;
  final int maxSteps;

  @override
  State<AddonStaggerIn> createState() => _AddonStaggerInState();
}

class _AddonStaggerInState extends State<AddonStaggerIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 340));
  late final CurvedAnimation _curve = CurvedAnimation(parent: _c, curve: AddonsMotion.emphasized);
  Timer? _timer;
  bool _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scheduled) return;
    _scheduled = true;
    if (AddonsMotion.reduced(context)) {
      _c.value = 1;
      return;
    }
    _timer = Timer(widget.step * widget.index.clamp(0, widget.maxSteps), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _curve.dispose();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _curve,
        child: AnimatedBuilder(
          animation: _curve,
          child: widget.child,
          builder: (_, child) => Transform.translate(offset: Offset(0, 14 * (1 - _curve.value)), child: child),
        ),
      );
}

/// Horizontal error shake, fired whenever [trigger] changes.
class AddonShake extends StatefulWidget {
  const AddonShake({super.key, required this.trigger, required this.child});

  final int trigger;
  final Widget child;

  @override
  State<AddonShake> createState() => _AddonShakeState();
}

class _AddonShakeState extends State<AddonShake> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  @override
  void didUpdateWidget(covariant AddonShake oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trigger != widget.trigger && !AddonsMotion.reduced(context)) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (_, child) {
          final t = _c.value;
          final dx = math.sin(t * math.pi * 6) * 7 * (1 - t);
          return Transform.translate(offset: Offset(dx, 0), child: child);
        },
      );
}

/// Collapses an entry out of a list: fade + nudge, then height closes.
class AddonRemovable extends StatefulWidget {
  const AddonRemovable({super.key, required this.removing, required this.child});

  final bool removing;
  final Widget child;

  @override
  State<AddonRemovable> createState() => _AddonRemovableState();
}

class _AddonRemovableState extends State<AddonRemovable> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
  late final Animation<double> _fade = Tween<double>(begin: 1, end: 0)
      .animate(CurvedAnimation(parent: _c, curve: const Interval(0, 0.5, curve: Curves.easeOut)));
  late final Animation<double> _size = Tween<double>(begin: 1, end: 0)
      .animate(CurvedAnimation(parent: _c, curve: const Interval(0.3, 1, curve: AddonsMotion.emphasized)));

  @override
  void initState() {
    super.initState();
    if (widget.removing) _c.value = 1;
  }

  @override
  void didUpdateWidget(covariant AddonRemovable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.removing != oldWidget.removing) {
      widget.removing ? _c.forward() : _c.reverse();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizeTransition(
        sizeFactor: _size,
        alignment: Alignment.topCenter,
        child: FadeTransition(
          opacity: _fade,
          child: AnimatedBuilder(
            animation: _c,
            child: widget.child,
            builder: (_, child) => Transform.translate(offset: Offset(18 * _c.value, 0), child: child),
          ),
        ),
      );
}

/// Draw-on success mark: circle sweeps, check strokes in, a soft ring bursts.
class AddonSuccessCheck extends StatefulWidget {
  const AddonSuccessCheck({super.key, this.size = 56, this.color = AddonsColors.textPrimary});

  final double size;
  final Color color;

  @override
  State<AddonSuccessCheck> createState() => _AddonSuccessCheckState();
}

class _AddonSuccessCheckState extends State<AddonSuccessCheck> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 760));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (AddonsMotion.reduced(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: widget.size,
        child: CustomPaint(painter: _SuccessCheckPainter(progress: _c, color: widget.color)),
      );
}

class _SuccessCheckPainter extends CustomPainter {
  _SuccessCheckPainter({required this.progress, required this.color}) : super(repaint: progress);

  final Animation<double> progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    final center = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 4;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2, size.shortestSide / 22)
      ..strokeCap = StrokeCap.round;

    if (t > 0.45) {
      final b = ((t - 0.45) / 0.55).clamp(0.0, 1.0);
      canvas.drawCircle(
        center,
        r * (1 + 0.32 * b),
        Paint()
          ..color = color.withValues(alpha: 0.35 * (1 - b))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }

    final c = Curves.easeOutCubic.transform((t / 0.5).clamp(0.0, 1.0));
    canvas.drawArc(Rect.fromCircle(center: center, radius: r), -math.pi / 2, math.pi * 2 * c, false, stroke);

    final k = ((t - 0.4) / 0.6).clamp(0.0, 1.0);
    if (k > 0) {
      final box = Rect.fromCircle(center: center, radius: r);
      final path = Path()
        ..moveTo(box.left + box.width * 0.29, box.top + box.height * 0.52)
        ..lineTo(box.left + box.width * 0.44, box.top + box.height * 0.66)
        ..lineTo(box.left + box.width * 0.72, box.top + box.height * 0.37);
      final eased = Curves.easeOutCubic.transform(k);
      for (final metric in path.computeMetrics()) {
        canvas.drawPath(metric.extractPath(0, metric.length * eased), stroke);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SuccessCheckPainter old) => old.color != color;
}

/// Determinate ring used while a plugin downloads (value eases between ticks).
class AddonProgressRing extends StatelessWidget {
  const AddonProgressRing({super.key, required this.value, this.size = 32});

  final double value;
  final double size;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(end: value.clamp(0.0, 1.0)),
        duration: AddonsMotion.d(context, const Duration(milliseconds: 120)),
        builder: (_, v, __) => SizedBox.square(
          dimension: size,
          child: CustomPaint(
            painter: _RingPainter(v),
            child: Center(
              child: Text(
                '${(v * 100).round()}',
                style: AddonsText.inter(9.5, weight: FontWeight.w700, tabular: true, height: 1),
              ),
            ),
          ),
        ),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value);

  final double value;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final deflated = rect.deflate(2);
    canvas.drawArc(
      deflated,
      0,
      math.pi * 2,
      false,
      Paint()
        ..color = AddonsColors.hairlineStrong
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4,
    );
    canvas.drawArc(
      deflated,
      -math.pi / 2,
      math.pi * 2 * value,
      false,
      Paint()
        ..color = AddonsColors.textPrimary
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 2.4,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.value != value;
}

// ─────────────────────────────────────────────────────────────────────────────
// Skeletons, state cards, sheets, toasts, routes
// ─────────────────────────────────────────────────────────────────────────────

class AddonSkeletonBox extends StatelessWidget {
  const AddonSkeletonBox({super.key, this.width, required this.height, this.radius = 6});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(radius)),
      );
}

/// Shimmer wrapper shared with Home skeletons.
class AddonShimmer extends StatelessWidget {
  const AddonShimmer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => PixelShimmer(child: child);
}

enum AddonStateTone { neutral, error }

/// Inline empty / error card with a single recovery action.
class AddonsStateCard extends StatelessWidget {
  const AddonsStateCard({
    super.key,
    required this.iconSvg,
    required this.title,
    required this.body,
    this.actionLabel,
    this.actionIconSvg,
    this.onAction,
    this.tone = AddonStateTone.neutral,
  });

  final String iconSvg;
  final String title;
  final String body;
  final String? actionLabel;
  final String? actionIconSvg;
  final VoidCallback? onAction;
  final AddonStateTone tone;

  @override
  Widget build(BuildContext context) {
    final isError = tone == AddonStateTone.error;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      decoration: BoxDecoration(
        color: AddonsColors.ghostFill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isError ? AddonsColors.dangerHairline : AddonsColors.ghostBorder),
      ),
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isError ? AddonsColors.dangerFill : AddonsColors.card,
              shape: BoxShape.circle,
              border: Border.all(color: isError ? AddonsColors.dangerHairline : AddonsColors.hairline),
            ),
            alignment: Alignment.center,
            child: AddonIcon(iconSvg, size: 20, color: isError ? AddonsColors.dangerText : AddonsColors.textSecondary),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AddonsText.inter(16, weight: FontWeight.w700, letterSpacing: -0.3, height: 1.3),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Text(body, textAlign: TextAlign.center, style: AddonsText.body()),
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: 18),
            AddonsButton(
              label: actionLabel!,
              iconSvg: actionIconSvg,
              onTap: onAction,
              variant: AddonButtonVariant.secondary,
              expand: false,
              compact: true,
              height: 38,
            ),
          ],
        ],
      ),
    );
  }
}

/// Same sheet chrome as the Season selector: black, 28px top radius, hairline
/// edge, drag handle, round close button.
Future<T?> showAddonsSheet<T>(BuildContext context, {required WidgetBuilder builder}) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: AddonsColors.scrim,
      elevation: 0,
      builder: builder,
    );

class AddonsSheetFrame extends StatelessWidget {
  const AddonsSheetFrame({
    super.key,
    this.title,
    this.header,
    required this.body,
    this.footer,
    this.showClose = true,
    this.maxHeightFactor = 0.9,
  });

  final String? title;
  final Widget? header;
  final Widget body;
  final Widget? footer;
  final bool showClose;
  final double maxHeightFactor;

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);
    final mq = MediaQuery.of(context);
    final bottomInset = mq.padding.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: mq.size.height * maxHeightFactor),
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: AddonsColors.canvas,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(28.r)),
              side: const BorderSide(color: AddonsColors.specular),
            ),
            shadows: const [BoxShadow(color: Color(0xCC000000), offset: Offset(0, -10), blurRadius: 35)],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28.r)),
            child: Material(
              color: Colors.transparent,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: 12.h, bottom: 12.h),
                    child: Center(
                      child: Container(
                        width: 44.w,
                        height: 4.h,
                        decoration: BoxDecoration(
                          color: AddonsColors.sheetHandle,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                  ),
                  if (title != null || header != null)
                    Padding(
                      padding: EdgeInsets.fromLTRB(24.w, 0, 20.w, 16.h),
                      child: Row(
                        children: [
                          Expanded(
                            child: header ??
                                Text(
                                  title!,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: AddonsText.sectionTitle(),
                                ),
                          ),
                          if (showClose) ...[
                            SizedBox(width: 12.w),
                            AddonPressable(
                              color: AddonsColors.sheetClose,
                              borderRadius: 999,
                              semanticLabel: 'Close',
                              onTap: () => Navigator.of(context).maybePop(),
                              child: SizedBox(
                                width: 32.r,
                                height: 32.r,
                                child: const Center(
                                  child: AddonIcon(AddonIcons.close, size: 16, color: AddonsColors.sheetCloseIcon),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  Flexible(child: body),
                  if (footer != null)
                    Padding(
                      padding: EdgeInsets.fromLTRB(24.w, 12.h, 24.w, 16.h + bottomInset),
                      child: footer,
                    )
                  else
                    SizedBox(height: bottomInset + 8.h),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void showAddonsToast(
  BuildContext context,
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  bool isError = false,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          message,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AddonsText.inter(13, weight: FontWeight.w600),
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? AddonsColors.errorToast : AddonsColors.toast,
        shape: const StadiumBorder(),
        duration: const Duration(milliseconds: 3200),
        action: actionLabel == null
            ? null
            : SnackBarAction(
                label: actionLabel,
                textColor: AddonsColors.textPrimary,
                onPressed: onAction ?? () {},
              ),
      ),
    );
}

/// Route used by every Addons push: fade + 2% rise on the app curve.
Route<T> addonsRoute<T>(Widget page) => PageRouteBuilder<T>(
      transitionDuration: AddonsMotion.route,
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) {
        final curved = CurvedAnimation(parent: animation, curve: AddonsMotion.emphasized);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 0.02), end: Offset.zero).animate(curved),
            child: child,
          ),
        );
      },
    );
