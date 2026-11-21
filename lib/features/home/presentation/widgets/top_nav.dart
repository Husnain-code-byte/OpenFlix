import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/responsive.dart';
import '../controllers/home_controller.dart';

const _downloadSvg =
    '<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><defs><clipPath id="c"><rect width="24" height="24" fill="white"/></clipPath></defs><g clip-path="url(#c)"><path d="M12 0V18.3529M17.3333 12.7059L12 18.3529L6.66667 12.7059M0 24H24" stroke="#F6F6F3" stroke-width="1.7" stroke-linecap="round"/></g></svg>';

/// Canonical hierarchy — the order never changes, only which heading is promoted.
const _order = <HomeFilter>[
  HomeFilter.home,
  HomeFilter.movies,
  HomeFilter.tvShows,
  HomeFilter.anime,
  HomeFilter.categories,
];

const _labels = <HomeFilter, String>{
  HomeFilter.home: 'Home',
  HomeFilter.movies: 'Movies',
  HomeFilter.tvShows: 'TV Shows',
  HomeFilter.anime: 'Anime',
  HomeFilter.categories: 'Categories',
};

/// Base widths from the Figma export ("Home" reuses the Movies width — both
/// 6 letters). At build time these are scaled so the chip row fills the
/// available width with EQUAL 12px margins on both sides.
const _widths = <HomeFilter, double>{
  HomeFilter.home: 65,
  HomeFilter.movies: 65,
  HomeFilter.tvShows: 89,
  HomeFilter.anime: 67,
  HomeFilter.categories: 132,
};

const _rightMargin = 12.0;

/// Where a heading sits for a given selection.
class _Slot {
  const _Slot(this.rect, this.fontSize, this.isChip);
  final Rect rect;
  final double fontSize;
  final bool isChip;
}

/// Figma "Netflix top navigation".
///
/// Tapping a heading promotes it: its text flies up into the title slot (16 → 28)
/// while the outgoing title flies down into the first free slot and the remaining
/// chips slide sideways to close the gap. The hierarchy itself is fixed, so a
/// demoted heading always returns to its own place in the row.
class TopNav extends StatefulWidget {
  const TopNav({
    super.key,
    required this.filter,
    required this.onFilter,
    required this.onDownloads,
  });

  final HomeFilter filter;
  final ValueChanged<HomeFilter> onFilter;
  final VoidCallback onDownloads;

  /// Total height including the status-bar inset.
  static double heightFor(BuildContext context) {
    Responsive.init(context);
    return AppDimens.topNavHeight + MediaQuery.paddingOf(context).top;
  }

  @override
  State<TopNav> createState() => _TopNavState();
}

class _TopNavState extends State<TopNav> with SingleTickerProviderStateMixin {
  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
  );

  /// Travel uses a decelerating curve; the size swap overshoots slightly so the
  /// promoted title lands with a little weight.
  late final CurvedAnimation _move = CurvedAnimation(parent: _clock, curve: Curves.easeOutCubic);
  late final CurvedAnimation _pop = CurvedAnimation(parent: _clock, curve: Curves.easeOutBack);
  late final CurvedAnimation _fade = CurvedAnimation(parent: _clock, curve: Curves.easeInOut);

  late HomeFilter _from = widget.filter;
  late HomeFilter _to = widget.filter;

  final Map<String, double> _textWidths = {};

  @override
  void initState() {
    super.initState();
    _clock.value = 1; // the first build is already settled — no intro animation
    // Normalise once a flight lands: with _from == _to every slot is at rest,
    // so no stale "old layout" rects can ever linger between taps.
    _clock.addStatusListener((status) {
      if (status == AnimationStatus.completed && _from != _to) {
        setState(() => _from = _to);
      }
    });
    // Google Fonts may still be downloading when the title width is first measured,
    // which would leave it a few px off x=13. Re-measure once it has settled.
    Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      setState(_textWidths.clear);
    });
  }

  @override
  void didUpdateWidget(covariant TopNav oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filter != widget.filter) {
      // An interruption snaps the previous flight to its target first, so the
      // next one always starts from a coherent layout.
      _from = _to;
      _to = widget.filter;
      HapticFeedback.selectionClick();
      _clock.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _move.dispose();
    _pop.dispose();
    _fade.dispose();
    _clock.dispose();
    super.dispose();
  }

  double _textWidth(String label, double size) {
    final key = '$label@$size';
    return _textWidths[key] ??= () {
      final tp = TextPainter(
        text: TextSpan(text: label, style: AppText.chip.copyWith(fontSize: size)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      return tp.width;
    }();
  }

  /// Scale the base chip widths so the row fills [avail] with 12.w on each side.
  double _chipScale(double avail, double activeSum) {
    // Four chips in the row → three gaps.
    final rightMargin = _rightMargin.w;
    final free = avail - AppDimens.rowLeft - rightMargin - AppDimens.chipGap * 3;
    return free / activeSum;
  }

  double _activeWidthSum(HomeFilter sel) {
    final row = _order.where((e) => e != sel);
    double sum = 0;
    for (final item in row) {
      sum += _widths[item]!;
    }
    return sum;
  }

  _Slot _slotOf(HomeFilter sel, HomeFilter item, double scale) {
    if (item == sel) {
      final w = _textWidth(_labels[item]!, AppDimens.titleFontSize);
      return _Slot(
        Rect.fromLTWH(AppDimens.titleLeft, 0, w, AppDimens.headerH),
        AppDimens.titleFontSize,
        false,
      );
    }
    final row = _order.where((e) => e != sel).toList();
    final i = row.indexOf(item);
    var x = AppDimens.rowLeft;
    for (var j = 0; j < i; j++) {
      x += _widths[row[j]]! * scale + AppDimens.chipGap;
    }
    return _Slot(
      Rect.fromLTWH(x, AppDimens.rowTop, _widths[item]! * scale, AppDimens.rowH),
      AppDimens.chipFontSize,
      true,
    );
  }

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);
    final top = MediaQuery.paddingOf(context).top;
    return Container(
      color: Colors.black,
      padding: EdgeInsets.only(top: 8.h + top, bottom: 14.h),
      child: LayoutBuilder(
        builder: (context, c) {
          final activeSum = _activeWidthSum(_to);
          final scale = _chipScale(c.maxWidth, activeSum);
          return SizedBox(
            // 44.h header + 12.h gap + 46.h chip row
            height: AppDimens.headerH + AppDimens.headerGap + AppDimens.rowH,
            child: AnimatedBuilder(
              animation: _clock,
              builder: (context, _) {
                final t = _move.value;
                return Stack(children: [
                  // ── Chip pills ────────────────────────────────────────────────
                  // The promoted/relegated heading's pill holds its place and
                  // cross-fades, so its text appears to fly free of it.
                  for (final item in _order) _buildBox(item, t, scale),

                  // ── Tap targets (sized to the resting chip, under the labels) ──
                  for (final item in _order)
                    if (item != _to)
                      Positioned.fromRect(
                        rect: _slotOf(_to, item, scale).rect,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(AppDimens.navPillRadius),
                            onTap: () => widget.onFilter(item),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),

                  // ── Flying labels ─────────────────────────────────────────────
                  for (final item in _order) _buildLabel(item, t, scale),

                  // ── Static header action (right edge) ─────────────────────────
                  Positioned(
                    top: 0,
                    height: AppDimens.headerH,
                    right: 8.w,
                    child: Center(
                      child: InkResponse(
                        radius: 22.r,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          widget.onDownloads();
                        },
                        child: Padding(
                          padding: EdgeInsets.all(10.w),
                          child: SvgPicture.string(_downloadSvg, width: 24.r, height: 24.r),
                        ),
                      ),
                    ),
                  ),
                ]);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildBox(HomeFilter item, double t, double scale) {
    // The page title NEVER has a pill. This is structural — not an opacity
    // that happens to reach zero — so the heading can't end up boxed even if
    // an animation is interrupted or a stale frame is painted. Only while the
    // flight is actually running does the promoted heading's old pill linger
    // (fading out at the chip slot it left behind).
    if (item == _to && !_clock.isAnimating) return const SizedBox.shrink();

    final a = _slotOf(_from, item, scale);
    final b = _slotOf(_to, item, scale);
    final Rect rect;
    final double opacity;
    if (!b.isChip) {
      if (!a.isChip) return const SizedBox.shrink(); // title → title: nothing
      rect = a.rect; // leaving the row: pill holds its old slot and fades out
      opacity = lerpDouble(1, 0, _fade.value)!;
    } else if (a.isChip) {
      rect = Rect.lerp(a.rect, b.rect, t)!; // both chips: the pill slides across
      opacity = 1;
    } else {
      rect = b.rect; // joining the row: pill fades in at its target
      opacity = lerpDouble(0, 1, _fade.value)!;
    }

    if (opacity <= 0.001) return const SizedBox.shrink();

    return Positioned.fromRect(
      rect: rect,
      child: IgnorePointer(
        child: Opacity(
          opacity: opacity,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.navPillFill,
              borderRadius: BorderRadius.circular(AppDimens.navPillRadius),
              border: Border.all(color: AppColors.navPillBorder),
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(HomeFilter item, double t, double scale) {
    final a = _slotOf(_from, item, scale);
    final b = _slotOf(_to, item, scale);
    final rect = Rect.lerp(a.rect, b.rect, t)!;
    final size = lerpDouble(a.fontSize, b.fontSize, _pop.value)!;

    return Positioned.fromRect(
      rect: rect,
      child: IgnorePointer(
        child: Center(
          // `visible` lets the text draw past its box mid-flight instead of clipping
          child: Text(
            _labels[item]!,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            style: AppText.chip.copyWith(fontSize: size),
          ),
        ),
      ),
    );
  }
}
