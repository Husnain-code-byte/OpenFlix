import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../errors/user_error.dart';

/// Matte-black OLED feedback design tokens shared by [AppToast] and
/// [AppStatusCard].
abstract final class AppFeedbackColors {
  static const Color canvas = Color(0xFF000000);
  static const Color surface = Color(0xFF121214);
  static const Color iconBadge = Color(0xFF1A1A1E);
  static const Color border = Color(0xFF27272A);
  static const Color accent = Color(0xFFE50914);
  static const Color textPrimary = Color(0xFFF6F6F3);
  static const Color textMuted = Color(0xA3FFFFFF); // 64% white
  static const Color errorIcon = Color(0xFFFF6B72);
}

/// Compact OLED-black floating status pill for transient messages and errors.
///
/// Features:
/// - Auto-dismisses after 3.5 seconds (configurable).
/// - Swipeable to dismiss immediately.
/// - Global deduplication & cooldown so simultaneous failing requests never
///   stack or repeat identical pills (e.g. multiple rows failing offline).
abstract final class AppToast {
  static OverlayEntry? _activeEntry;
  static Timer? _dismissTimer;
  static final Map<String, DateTime> _cooldowns = <String, DateTime>{};
  static const Duration _defaultCooldown = Duration(seconds: 5);

  /// Shows a compact floating status pill.
  static void show(
    BuildContext context, {
    required String message,
    IconData? icon,
    UserErrorType? dedupType,
    bool isError = false,
    bool anchorTop = false,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(milliseconds: 3500),
    Duration cooldown = _defaultCooldown,
  }) {
    final trimmed = message.trim();
    if (trimmed.isEmpty) return;

    final dedupKey = dedupType != null ? 'type:${dedupType.name}' : 'msg:$trimmed';
    final now = DateTime.now();
    final prev = _cooldowns[dedupKey];
    if (prev != null && now.difference(prev) < cooldown) {
      return;
    }
    _cooldowns[dedupKey] = now;
    if (_cooldowns.length > 32) {
      _cooldowns.removeWhere((_, ts) => now.difference(ts) > const Duration(minutes: 2));
    }

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    dismiss();

    final resolvedIcon = icon ??
        (isError
            ? (dedupType == UserErrorType.offline
                ? Icons.wifi_off_rounded
                : Icons.info_outline_rounded)
            : Icons.check_circle_outline_rounded);

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (overlayContext) => _AppToastOverlay(
        message: trimmed,
        icon: resolvedIcon,
        isError: isError,
        anchorTop: anchorTop,
        actionLabel: actionLabel,
        onAction: onAction == null
            ? null
            : () {
                dismiss();
                onAction();
              },
        onDismissed: () {
          if (_activeEntry == entry) {
            dismiss();
          }
        },
      ),
    );

    _activeEntry = entry;
    overlay.insert(entry);
    _dismissTimer = Timer(duration, () {
      if (_activeEntry == entry) {
        dismiss();
      }
    });
  }

  /// Maps any raw [error] through [UserError.from] and displays a deduplicated
  /// error pill.
  static void showError(
    BuildContext context,
    Object? error, {
    UserErrorType? fallbackType,
    bool anchorTop = false,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final mapped = UserError.from(error, fallbackType: fallbackType);
    show(
      context,
      message: mapped.type == UserErrorType.offline ? mapped.title : mapped.message,
      icon: _iconForType(mapped.type),
      dedupType: mapped.type,
      isError: true,
      anchorTop: anchorTop,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }

  /// Standard pill when background refresh fails while cached titles remain on
  /// screen.
  static void showOfflineCached(
    BuildContext context, {
    String message = 'Offline — showing saved titles',
  }) {
    show(
      context,
      message: message,
      icon: Icons.wifi_off_rounded,
      dedupType: UserErrorType.offline,
      isError: false,
    );
  }

  static void dismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
    try {
      _activeEntry?.remove();
    } catch (_) {}
    _activeEntry = null;
  }

  @visibleForTesting
  static void resetCooldowns() {
    dismiss();
    _cooldowns.clear();
  }

  static IconData _iconForType(UserErrorType type) => switch (type) {
        UserErrorType.offline => Icons.wifi_off_rounded,
        UserErrorType.timeout => Icons.schedule_rounded,
        UserErrorType.noAddons => Icons.extension_off_rounded,
        UserErrorType.noStreams => Icons.link_off_rounded,
        UserErrorType.playbackFailed => Icons.play_disabled_rounded,
        UserErrorType.authRequired => Icons.lock_outline_rounded,
        UserErrorType.unknown => Icons.info_outline_rounded,
      };
}

class _AppToastOverlay extends StatefulWidget {
  const _AppToastOverlay({
    required this.message,
    required this.icon,
    required this.isError,
    required this.anchorTop,
    required this.onDismissed,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final IconData icon;
  final bool isError;
  final bool anchorTop;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onDismissed;

  @override
  State<_AppToastOverlay> createState() => _AppToastOverlayState();
}

class _AppToastOverlayState extends State<_AppToastOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  )..forward();

  late final Animation<double> _opacity = CurvedAnimation(
    parent: _anim,
    curve: const Cubic(0.22, 1.0, 0.36, 1.0),
  );

  late final Animation<Offset> _slide = Tween<Offset>(
    begin: Offset(0, widget.anchorTop ? -0.35 : 0.35),
    end: Offset.zero,
  ).animate(_opacity);

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.viewPaddingOf(context);
    final topOffset = padding.top + 14;
    // Sit cleanly above the bottom navigation bar when anchored at the bottom.
    final bottomOffset = padding.bottom + 76;

    return Positioned(
      top: widget.anchorTop ? topOffset : null,
      bottom: widget.anchorTop ? null : bottomOffset,
      left: 16,
      right: 16,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Center(
          child: SlideTransition(
            position: _slide,
            child: FadeTransition(
              opacity: _opacity,
              child: Dismissible(
                key: ValueKey('app_toast_${widget.message}'),
                direction: DismissDirection.horizontal,
                onDismissed: (_) => widget.onDismissed(),
                child: Material(
                  color: Colors.transparent,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 380),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppFeedbackColors.surface,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: AppFeedbackColors.border,
                          width: 1,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x99000000),
                            blurRadius: 18,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            widget.icon,
                            size: 16,
                            color: widget.isError
                                ? AppFeedbackColors.errorIcon
                                : AppFeedbackColors.textPrimary,
                          ),
                          const SizedBox(width: 9),
                          Flexible(
                            child: Text(
                              widget.message,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                height: 1.3,
                                color: AppFeedbackColors.textPrimary,
                              ),
                            ),
                          ),
                          if (widget.actionLabel != null &&
                              widget.onAction != null) ...[
                            const SizedBox(width: 10),
                            GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                widget.onAction!();
                              },
                              child: Text(
                                widget.actionLabel!,
                                style: GoogleFonts.inter(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppFeedbackColors.accent,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact, centered OLED-black status card for actionable empty and error
/// states across OpenFlix (`#121214` card, `1px #27272A` border, `#E50914`
/// primary pill CTA).
class AppStatusCard extends StatelessWidget {
  const AppStatusCard({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
    this.compact = false,
  });

  factory AppStatusCard.fromError(
    UserError error, {
    Key? key,
    VoidCallback? onAction,
    String? actionLabelOverride,
    String? secondaryActionLabel,
    VoidCallback? onSecondaryAction,
    bool compact = false,
  }) =>
      AppStatusCard(
        key: key,
        icon: AppToast._iconForType(error.type),
        title: error.title,
        message: error.message,
        actionLabel: onAction != null ? (actionLabelOverride ?? error.actionLabel) : null,
        onAction: onAction,
        secondaryActionLabel: secondaryActionLabel,
        onSecondaryAction: onSecondaryAction,
        compact: compact,
      );

  /// Standard "No addons installed" empty state with 1-tap navigation to
  /// Addons / Official Addons.
  factory AppStatusCard.noAddons({
    Key? key,
    required VoidCallback onInstallAddons,
    bool compact = false,
  }) =>
      AppStatusCard.fromError(
        UserError.noAddons(),
        key: key,
        onAction: onInstallAddons,
        compact: compact,
      );

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final pad = compact ? 18.0 : 24.0;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 328),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: EdgeInsets.all(pad),
          decoration: BoxDecoration(
            color: AppFeedbackColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppFeedbackColors.border,
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: compact ? 40 : 44,
                height: compact ? 40 : 44,
                decoration: BoxDecoration(
                  color: AppFeedbackColors.iconBadge,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppFeedbackColors.border,
                    width: 1,
                  ),
                ),
                child: Icon(
                  icon,
                  size: compact ? 19 : 21,
                  color: AppFeedbackColors.textPrimary,
                ),
              ),
              SizedBox(height: compact ? 12 : 14),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: compact ? 15 : 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.35,
                  height: 1.2,
                  color: AppFeedbackColors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w400,
                  height: 1.45,
                  color: AppFeedbackColors.textMuted,
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                SizedBox(height: compact ? 14 : 18),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    _PrimaryPillButton(
                      label: actionLabel!,
                      onTap: onAction!,
                    ),
                    if (secondaryActionLabel != null &&
                        onSecondaryAction != null)
                      _SecondaryPillButton(
                        label: secondaryActionLabel!,
                        onTap: onSecondaryAction!,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _PrimaryPillButton extends StatelessWidget {
  const _PrimaryPillButton({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppFeedbackColors.accent,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              letterSpacing: -0.1,
            ),
          ),
        ),
      ),
    );
  }
}

class _SecondaryPillButton extends StatelessWidget {
  const _SecondaryPillButton({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: const StadiumBorder(
        side: BorderSide(color: AppFeedbackColors.border, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppFeedbackColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact OLED-black floating pill widget for inline/player overlays that want
/// the exact same visual language as [AppToast].
class AppStatusPill extends StatelessWidget {
  const AppStatusPill({
    super.key,
    required this.message,
    this.icon,
    this.isError = false,
  });

  final String message;
  final IconData? icon;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppFeedbackColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: AppFeedbackColors.border,
            width: 1,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x88000000),
              blurRadius: 14,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 15,
                color: isError
                    ? AppFeedbackColors.errorIcon
                    : AppFeedbackColors.textPrimary,
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  color: AppFeedbackColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
