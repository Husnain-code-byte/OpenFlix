import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/errors/user_error.dart';
import '../../../../core/perf/image_perf.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../home/presentation/utils/title_format.dart';
import '../../../home/presentation/widgets/poster_card.dart';
import '../../data/tmdb_models.dart';
import '../details_text.dart';

/// Icon geometry copied verbatim from the Figma "Movies details screen" export.
const kDetailChevronSvg =
    '<svg width="20" height="20" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M13.125 16.25L6.875 10L13.125 3.75" stroke="white" stroke-opacity="0.9" stroke-width="2.29167" stroke-linecap="round" stroke-linejoin="round"/></svg>';

const kDetailPlaySvg =
    '<svg width="20" height="20" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M4.16663 2.5L15.8333 10L4.16663 17.5V2.5Z" fill="black"/></svg>';

const kDetailBookmarkSvg =
    '<svg width="16" height="16" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M3.33337 3.33333C3.33337 2.59745 3.93082 2 4.66671 2H11.3334C12.0693 2 12.6667 2.59745 12.6667 3.33333V14L8.00004 11.6667L3.33337 14V3.33333" stroke="#D4D4D4" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round"/></svg>';

const kDetailBookmarkFilledSvg =
    '<svg width="16" height="16" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M3.33337 3.33333C3.33337 2.59745 3.93082 2 4.66671 2H11.3334C12.0693 2 12.6667 2.59745 12.6667 3.33333V14L8.00004 11.6667L3.33337 14V3.33333Z" fill="white" stroke="white" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round"/></svg>';

const kDetailLikeSvg =
    '<svg width="16" height="16" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M9.33337 6.00004V3.33337C9.33337 2.22954 8.4372 1.33337 7.33337 1.33337L4.66671 7.33337V14.6667H12.1867C12.8516 14.6742 13.4203 14.1908 13.52 13.5334L14.44 7.53337C14.4987 7.14661 14.3846 6.75358 14.1279 6.45838C13.8713 6.16319 13.4979 5.99561 13.1067 6.00004H9.33337M4.66671 14.6667H2.66671C1.93082 14.6667 1.33337 14.0693 1.33337 13.3334V8.66671C1.33337 7.93082 1.93082 7.33337 2.66671 7.33337H4.66671" stroke="#D4D4D4" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round"/></svg>';

const kDetailLikeFilledSvg =
    '<svg width="16" height="16" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M9.33337 6.00004V3.33337C9.33337 2.22954 8.4372 1.33337 7.33337 1.33337L5.1 6.35V14.6667H12.1867C12.8516 14.6742 13.4203 14.1908 13.52 13.5334L14.44 7.53337C14.4987 7.14661 14.3846 6.75358 14.1279 6.45838C13.8713 6.16319 13.4979 5.99561 13.1067 6.00004H9.33337Z" fill="white" stroke="white" stroke-width="0.9" stroke-linejoin="round"/><path d="M3.55 14.6667H2.55C1.88 14.6667 1.33337 14.0693 1.33337 13.3334V8.66671C1.33337 7.93082 1.88 7.33337 2.55 7.33337H3.55V14.6667Z" fill="white" stroke="white" stroke-width="0.9" stroke-linejoin="round"/></svg>';

const kDetailDislikeSvg =
    '<svg width="16" height="16" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M6.6667 10V12.6667C6.6667 13.7705 7.56287 14.6667 8.6667 14.6667L11.3334 8.66667V1.33334H3.81336C3.14851 1.32582 2.57972 1.80929 2.48003 2.46667L1.56003 8.46667C1.50133 8.85344 1.61543 9.24647 1.87212 9.54166C2.12882 9.83686 2.5022 10.0044 2.89336 10H6.6667M11.3334 1.33334H13.3334C14.0693 1.33334 14.6667 1.93079 14.6667 2.66667V7.33334C14.6667 8.06923 14.0693 8.66667 13.3334 8.66667H11.3334" stroke="#D4D4D4" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round"/></svg>';

const kDetailDislikeFilledSvg =
    '<svg width="16" height="16" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M6.6667 10V12.6667C6.6667 13.7705 7.56287 14.6667 8.6667 14.6667L10.9 9.65V1.33334H3.81336C3.14851 1.32582 2.57972 1.80929 2.48003 2.46667L1.56003 8.46667C1.50133 8.85344 1.61543 9.24647 1.87212 9.54166C2.12882 9.83686 2.5022 10.0044 2.89336 10H6.6667Z" fill="white" stroke="white" stroke-width="0.9" stroke-linejoin="round"/><path d="M12.45 1.33334H13.45C14.12 1.33334 14.6667 1.93079 14.6667 2.66667V7.33334C14.6667 8.06923 14.12 8.66667 13.45 8.66667H12.45V1.33334Z" fill="white" stroke="white" stroke-width="0.9" stroke-linejoin="round"/></svg>';

/// Chevron icon for the Season Selector pill (Figma node 43:210).
const kDetailSeasonChevronSvg =
    '<svg width="16" height="16" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M12.6666 6L7.99992 10.6667L3.33325 6" stroke-width="1.33333" stroke-linecap="round" stroke-linejoin="round" stroke="#D1D5DB"/></svg>';

/// Close button "X" icon for the Season Selector modal (Figma node 113:181).
const kSeasonModalCloseSvg =
    '<svg width="16" height="16" viewBox="0 0 16 16" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M4 12L12 4M4 4L12 12" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" stroke="#D4D4D4"/></svg>';

/// Active season white checkmark icon for the Season Selector modal (Figma node 113:226).
const kSeasonModalCheckSvg =
    '<svg width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M5 13L9 17L19 7" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round" stroke="white"/></svg>';

/// Episode thumbnail fallback artwork (Figma node 43:97).
const kEpisodeThumbnailFallbackSvg =
    '<svg width="144" height="80" viewBox="0 0 144 80" fill="none" xmlns="http://www.w3.org/2000/svg"><g clip-path="url(#clip0_43_97)"><path d="M0 0H144V80H0V0V0" fill="#0B131A"/><path d="M42 20C62 13.3333 82 13.3333 102 20L115 80H30L42 20" fill="#14212E"/><path d="M52 46C52 59.7979 60.9617 71 72 71C83.0383 71 92 59.7979 92 46C92 32.2021 83.0383 21 72 21C60.9617 21 52 32.2021 52 46V46" fill="url(#paint0_radial_43_97)"/><path d="M62 42C62 42.6623 62.8962 43.2 64 43.2C65.1038 43.2 66 42.6623 66 42C66 41.3378 65.1038 40.8 64 40.8C62.8962 40.8 62 41.3378 62 42V42" fill="#2B1A13"/><path d="M78 42C78 42.6623 78.8962 43.2 80 43.2C81.1038 43.2 82 42.6623 82 42C82 41.3378 81.1038 40.8 80 40.8C78.8962 40.8 78 41.3378 78 42V42" fill="#2B1A13"/><path d="M72 43L71 52H75" stroke-width="1.2" stroke="#6E4F3A"/><path d="M66 59C70 61.6667 74 61.6667 78 59" stroke-width="1.5" stroke="#6E2D27"/><path d="M42 20C62 13.3333 82 13.3333 102 20C82 30 62 30 42 20V20" fill="#0A1017"/></g><defs><radialGradient id="paint0_radial_43_97" cx="0" cy="0" r="1" gradientUnits="userSpaceOnUse" gradientTransform="translate(72 46) scale(20 25)"><stop stop-color="#FFDFBA"/><stop offset="0.7" stop-color="#AB8265"/><stop offset="1" stop-color="#241A15"/></radialGradient><clipPath id="clip0_43_97"><rect width="144" height="80" fill="white"/></clipPath></defs></svg>';

/// Film title wordmark: the TMDB logo when one exists, otherwise the generated
/// Syncopate wordmark — lead 34/37, rule–connector–rule (10px row), finish 23/28.
class DetailWordmark extends StatelessWidget {
  const DetailWordmark({super.key, required this.name, this.logoUrl});

  final String name;
  final String? logoUrl;

  @override
  Widget build(BuildContext context) {
    if (logoUrl != null) {
      return CachedNetworkImage(
        imageUrl: logoUrl!,
        cacheManager: PixelImageCache.instance,
        fit: BoxFit.contain,
        // Decode at the slot's physical width (302dp); the height follows the
        // logo's own aspect ratio.
        memCacheWidth: (302.w * MediaQuery.devicePixelRatioOf(context)).round(),
        fadeInDuration: const Duration(milliseconds: 250),
        placeholder: (_, __) => _GeneratedWordmark(name: name),
        errorWidget: (_, __, ___) => _GeneratedWordmark(name: name),
      );
    }
    return _GeneratedWordmark(name: name);
  }
}

class _GeneratedWordmark extends StatelessWidget {
  const _GeneratedWordmark({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final p = splitTitle(name);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _FitLine(text: p.lead, size: 34.sp, lineHeight: 37.h),
      if (p.finish != null) ...[
        SizedBox(height: 1.h),
        SizedBox(
          height: 10.h,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(width: p.connector != null ? 30.w : 70.w, height: 1, color: AppColors.heroRule),
            if (p.connector != null) ...[
              SizedBox(width: 10.w),
              Text(p.connector!, style: DetailsText.syncopate(8.sp, 10.h, AppColors.heroConnector)),
              SizedBox(width: 10.w),
              Container(width: 30.w, height: 1, color: AppColors.heroRule),
            ],
          ]),
        ),
        SizedBox(height: 1.h),
        _FitLine(text: p.finish!, size: 23.sp, lineHeight: 28.h),
      ],
    ]);
  }
}

class _FitLine extends StatelessWidget {
  const _FitLine({required this.text, required this.size, required this.lineHeight});

  final String text;
  final double size;
  final double lineHeight;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: lineHeight,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            text,
            maxLines: 1,
            softWrap: false,
            textAlign: TextAlign.center,
            style: DetailsText.syncopate(size, lineHeight, AppColors.heroTitle),
          ),
        ),
      );
}

/// Primary "Play" button: full width, 44 high, radius 6, white, with the frame's
/// two-layer shadow. Icon 20, 8px gap, Inter 16/24 bold black.
class DetailPlayButton extends StatelessWidget {
  const DetailPlayButton({
    super.key,
    required this.onTap,
    this.label = 'Play',
    this.subtitle,
    this.progress,
  });

  final VoidCallback onTap;
  final String label;
  final String? subtitle;
  final double? progress;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        height: 44.h,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6.r),
            boxShadow: const [
              BoxShadow(
                color: Color(0x1A000000),
                offset: Offset(0, 10),
                blurRadius: 15,
                spreadRadius: -3,
              ),
              BoxShadow(
                color: Color(0x1A000000),
                offset: Offset(0, 4),
                blurRadius: 6,
                spreadRadius: -4,
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(6.r),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                HapticFeedback.mediumImpact();
                onTap();
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 14.w),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SvgPicture.string(kDetailPlaySvg,
                              width: 20.r, height: 20.r),
                          SizedBox(width: 8.w),
                          Flexible(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: DetailsText.inter(
                                size: 16.sp,
                                weight: FontWeight.w700,
                                color: Colors.black,
                                height: 24 / 16,
                              ),
                            ),
                          ),
                          if (subtitle != null && subtitle!.isNotEmpty) ...[
                            SizedBox(width: 6.w),
                            Text(
                              '· $subtitle',
                              maxLines: 1,
                              style: DetailsText.inter(
                                size: 12.5.sp,
                                weight: FontWeight.w600,
                                color: const Color(0xFF52525B),
                                height: 18 / 12.5,
                              ),
                            ),
                          ],
                        ],
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

enum DetailActionAnimationKind { bookmark, thumbUp, thumbDown }

/// Secondary action — Figma "My List / Like / Not for me Button": 36 high,
/// radius 6, 1px rgba(64,64,64,.8) border, rgba(0,0,0,.4) fill, 16px #D4D4D4
/// icon (or filled white icon when [active]), 6px gap, Inter 12/16 semibold #E5E5E5.
///
/// The button's outer box is strictly `width: double.infinity, height: 36` inside
/// its equal-third `Expanded` slot so changing `"Like"` to `"Liked"` never changes
/// the button's area width or disturbs the 3-column hierarchy.
/// When clicked, plays a tactile pop/tilt animation on the icon.
class DetailActionButton extends StatefulWidget {
  const DetailActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.active = false,
    this.animationKind = DetailActionAnimationKind.bookmark,
  });

  final String label;
  final Widget icon;
  final VoidCallback onTap;
  final bool active;
  final DetailActionAnimationKind animationKind;

  @override
  State<DetailActionButton> createState() => _DetailActionButtonState();
}

class _DetailActionButtonState extends State<DetailActionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildAnimatedIcon(Widget child) {
    return AnimatedBuilder(
      animation: _controller,
      child: child,
      builder: (context, iconChild) {
        final t = _controller.value;
        if (t <= 0.0 || t >= 1.0) return iconChild!;

        double scaleX = 1.0;
        double scaleY = 1.0;
        double angle = 0.0;
        double dy = 0.0;

        switch (widget.animationKind) {
          case DetailActionAnimationKind.thumbUp:
            if (t < 0.36) {
              final p = Curves.easeOutCubic.transform(t / 0.36);
              scaleX = 1.0 + 0.38 * p;
              scaleY = 1.0 + 0.38 * p;
              angle = -0.34 * p;
              dy = -2.8 * p;
            } else if (t < 0.72) {
              final p = Curves.easeInOut.transform((t - 0.36) / 0.36);
              scaleX = 1.38 - 0.46 * p;
              scaleY = 1.38 - 0.46 * p;
              angle = -0.34 + 0.44 * p;
              dy = -2.8 + 3.3 * p;
            } else {
              final p = Curves.easeOutBack.transform((t - 0.72) / 0.28);
              scaleX = 0.92 + 0.08 * p;
              scaleY = 0.92 + 0.08 * p;
              angle = 0.10 * (1.0 - p);
              dy = 0.5 * (1.0 - p);
            }
          case DetailActionAnimationKind.thumbDown:
            if (t < 0.36) {
              final p = Curves.easeOutCubic.transform(t / 0.36);
              scaleX = 1.0 + 0.38 * p;
              scaleY = 1.0 + 0.38 * p;
              angle = 0.34 * p;
              dy = 2.8 * p;
            } else if (t < 0.72) {
              final p = Curves.easeInOut.transform((t - 0.36) / 0.36);
              scaleX = 1.38 - 0.46 * p;
              scaleY = 1.38 - 0.46 * p;
              angle = 0.34 - 0.44 * p;
              dy = 2.8 - 3.3 * p;
            } else {
              final p = Curves.easeOutBack.transform((t - 0.72) / 0.28);
              scaleX = 0.92 + 0.08 * p;
              scaleY = 0.92 + 0.08 * p;
              angle = -0.10 * (1.0 - p);
              dy = -0.5 * (1.0 - p);
            }
          case DetailActionAnimationKind.bookmark:
            if (t < 0.34) {
              final p = Curves.easeOutCubic.transform(t / 0.34);
              scaleX = 1.0 + 0.28 * p;
              scaleY = 1.0 + 0.36 * p;
              dy = -3.0 * p;
            } else if (t < 0.70) {
              final p = Curves.easeInOut.transform((t - 0.34) / 0.36);
              scaleX = 1.28 - 0.36 * p;
              scaleY = 1.36 - 0.46 * p;
              dy = -3.0 + 3.8 * p;
            } else {
              final p = Curves.easeOutBack.transform((t - 0.70) / 0.30);
              scaleX = 0.92 + 0.08 * p;
              scaleY = 0.90 + 0.10 * p;
              dy = 0.8 * (1.0 - p);
            }
        }

        return Transform.translate(
          offset: Offset(0, dy),
          child: Transform.rotate(
            angle: angle,
            child: Transform.scale(
              scaleX: scaleX,
              scaleY: scaleY,
              child: iconChild,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0x66000000),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(6.r)),
          side: const BorderSide(color: Color(0xCC404040)),
        ),
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            _controller.forward(from: 0.0);
            widget.onTap();
          },
          child: SizedBox(
            width: double.infinity,
            height: 36.h,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.w),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    _buildAnimatedIcon(widget.icon),
                    SizedBox(width: 6.w),
                    Text(
                      widget.label,
                      maxLines: 1,
                      softWrap: false,
                      style: DetailsText.inter(
                        size: 12.sp,
                        weight: FontWeight.w600,
                        color: widget.active ? Colors.white : const Color(0xFFE5E5E5),
                        height: 16 / 12,
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      );
}

/// One of the three equal telemetry columns (label above value).
class DetailInfoColumn extends StatelessWidget {
  const DetailInfoColumn({
    super.key,
    required this.label,
    required this.value,
    required this.alignment,
  });

  final String label;
  final String value;
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: alignment,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DetailsText.inter(
              size: 11.sp,
              weight: FontWeight.w500,
              color: const Color(0xFF71717A),
              height: 16.5 / 11,
            ).copyWith(letterSpacing: -0.275),
          ),
          SizedBox(height: 2.h),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DetailsText.inter(
              size: 13.5.sp,
              weight: FontWeight.w600,
              color: const Color(0xFFD4D4D4),
              height: 20.25 / 13.5,
            ),
          ),
        ],
      );
}

/// Figma "Dropdown Pill: Season 1 Selector" (frame 43:204):
/// padding 6px 14px, border-radius 8px, border 0.5px solid rgba(64, 64, 64, 0.80), background #000.
/// Left: "Season 1" (Inter 14/20 w400 #FFF).
/// Right before chevron: "(8 episodes)" (Inter 12/16 w400 #9CA3AF).
/// Chevron: 16×16 with 8px left margin (#D1D5DB).
class DetailSeasonSelectorPill extends StatelessWidget {
  const DetailSeasonSelectorPill({
    super.key,
    required this.seasonNumber,
    this.episodeCount,
    this.onTap,
  });

  final int seasonNumber;
  final int? episodeCount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final epLabel = (episodeCount != null && episodeCount! > 0)
        ? '($episodeCount ${episodeCount == 1 ? 'episode' : 'episodes'})'
        : null;

    return Material(
      color: Colors.black,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8.r)),
        side: const BorderSide(color: Color(0xCC404040), width: 0.5),
      ),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap?.call();
        },
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
          child: SizedBox(
            height: 20.h,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    'Season $seasonNumber',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DetailsText.inter(
                      size: 14.sp,
                      weight: FontWeight.w400,
                      color: Colors.white,
                      height: 20 / 14,
                    ),
                  ),
                ),
                if (epLabel != null)
                  Padding(
                    padding: EdgeInsets.only(top: 1.h),
                    child: Text(
                      epLabel,
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      style: DetailsText.inter(
                        size: 12.sp,
                        weight: FontWeight.w400,
                        color: const Color(0xFF9CA3AF),
                        height: 16 / 12,
                      ),
                    ),
                  ),
                Padding(
                  padding: EdgeInsets.only(left: 8.w),
                  child: SvgPicture.string(
                    kDetailSeasonChevronSvg,
                    width: 16.r,
                    height: 16.r,
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

/// Figma "Section - Modal container slide-up bottom sheet" (frame 113:174):
/// - Container: background #13161F, border-radius 28px 28px 0 0,
///   border-top 1px solid rgba(255, 255, 255, 0.04),
///   box-shadow 0 -10px 35px 0 rgba(0, 0, 0, 0.80), padding-top 12px.
/// - Drag Handle: 44×4, border-radius 9999px, #363B47, padding-bottom 12px.
/// - Header: padding 0 24px 16px 24px, "Select season" (Inter 20/30 w700 #FFF, letter-spacing -0.5px)
///   + 32×32 circular close button (#242A37) with 16×16 X icon (#D4D4D4).
/// - Season List Rows: padding 4px 24px 24px 24px; each row shows "Season N"
///   (Inter 17/25.5 w600 #FFF, letter-spacing -0.425px), 1px gap,
///   "8 episodes   2021" (Inter 13/19.5 w400 #8491A5, letter-spacing 0.325px),
///   and a 24×24 white checkmark on the active season.
class DetailSeasonSelectorSheet extends StatelessWidget {
  const DetailSeasonSelectorSheet({
    super.key,
    required this.seasons,
    required this.selectedSeasonNumber,
    required this.onSeasonSelected,
  });

  final List<TmdbSeasonSummary> seasons;
  final int selectedSeasonNumber;
  final ValueChanged<int> onSeasonSelected;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final maxSheetHeight = MediaQuery.sizeOf(context).height * 0.72;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxSheetHeight),
      child: Container(
        decoration: ShapeDecoration(
          color: Colors.black,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28.r)),
            side: const BorderSide(color: Color(0x14FFFFFF), width: 1),
          ),
          shadows: const [
            BoxShadow(
              color: Color(0xCC000000),
              offset: Offset(0, -10),
              blurRadius: 35,
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: Padding(
            padding: EdgeInsets.only(top: 12.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top Center Drag Handle
                Padding(
                  padding: EdgeInsets.only(bottom: 12.h),
                  child: Center(
                    child: Container(
                      width: 44.w,
                      height: 4.h,
                      decoration: BoxDecoration(
                        color: const Color(0xFF363B47),
                        borderRadius: BorderRadius.circular(9999),
                      ),
                    ),
                  ),
                ),
                // Modal Header (Title + Close Button)
                Padding(
                  padding: EdgeInsets.fromLTRB(24.w, 0, 24.w, 16.h),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'Select season',
                        style: DetailsText.inter(
                          size: 20.sp,
                          weight: FontWeight.w700,
                          color: Colors.white,
                          height: 30 / 20,
                        ).copyWith(letterSpacing: -0.5),
                      ),
                      Material(
                        color: const Color(0xFF242A37),
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            Navigator.of(context).pop();
                          },
                          child: SizedBox(
                            width: 32.r,
                            height: 32.r,
                            child: Center(
                              child: SvgPicture.string(
                                kSeasonModalCloseSvg,
                                width: 16.r,
                                height: 16.r,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Season List Rows
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.fromLTRB(24.w, 4.h, 24.w, 24.h + bottomInset),
                    itemCount: seasons.length,
                    separatorBuilder: (_, __) => SizedBox(height: 16.h),
                    itemBuilder: (context, index) {
                      final season = seasons[index];
                      final isSelected = season.seasonNumber == selectedSeasonNumber;
                      return _SeasonSheetRow(
                        season: season,
                        isSelected: isSelected,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onSeasonSelected(season.seasonNumber);
                        },
                      );
                    },
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

class _SeasonSheetRow extends StatelessWidget {
  const _SeasonSheetRow({
    required this.season,
    required this.isSelected,
    required this.onTap,
  });

  final TmdbSeasonSummary season;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10.r),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 2.h),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      season.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DetailsText.inter(
                        size: 17.sp,
                        weight: FontWeight.w600,
                        color: Colors.white,
                        height: 25.5 / 17,
                      ).copyWith(letterSpacing: -0.425),
                    ),
                    SizedBox(height: 1.h),
                    Text(
                      season.episodesAndYearLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DetailsText.inter(
                        size: 13.sp,
                        weight: FontWeight.w400,
                        color: const Color(0xFF8491A5),
                        height: 19.5 / 13,
                      ).copyWith(letterSpacing: 0.325),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Padding(
                  padding: EdgeInsets.only(left: 12.w, right: 4.w),
                  child: SvgPicture.string(
                    kSeasonModalCheckSvg,
                    width: 24.r,
                    height: 24.r,
                  ),
                ),
            ],
          ),
        ),
      );
}

/// Figma "EpisodeList → Episode 1 Card Item" (frame 43:95, 358×127):
/// - Thumbnail: 144×80, border-radius 6px, background #171717
/// - Title & Metadata (right of thumbnail, left-padded 12px, vertically centered):
///   - Title: "1. Leavetaking" (Inter 14/20 w700 #FFF)
///   - Gap: 3.5px
///   - Runtime & Date row (gap 6px, Inter 11/16.5 w400 #9CA3AF): "55min"  "November 18, 2021"
/// - Synopsis (below thumbnail, padding-top 8px, padding-right 29.79px, height 39px):
///   - 2 lines max, 12px/19.5px w400 #9CA3AF
class _EpisodeThumbnailFallback extends StatelessWidget {
  const _EpisodeThumbnailFallback();

  @override
  Widget build(BuildContext context) => SvgPicture.string(
        kEpisodeThumbnailFallbackSvg,
        width: 144.w,
        height: 80.w,
        fit: BoxFit.cover,
      );
}

/// Figma "EpisodeList → Episode 1 Card Item" (frame 43:95, 358×127):
/// - Thumbnail: 144×80, border-radius 6px, background #171717
/// - Title & Metadata (right of thumbnail, left-padded 12px, vertically centered):
///   - Title: "1. Leavetaking" (Inter 14/20 w700 #FFF)
///   - Gap: 3.5px
///   - Runtime & Date row (gap 6px, Inter 11/16.5 w400 #9CA3AF): "55min"  "November 18, 2021"
/// - Synopsis (below thumbnail, padding-top 8px, padding-right 29.79px, height 39px):
///   - 2 lines max, 12px/19.5px w400 #9CA3AF
class DetailEpisodeCard extends StatelessWidget {
  const DetailEpisodeCard({
    super.key,
    required this.episode,
    this.fallbackBackdropUrl,
    this.progress,
    this.isWatched = false,
    this.onTap,
  });

  final TmdbEpisode episode;
  final String? fallbackBackdropUrl;
  final double? progress;
  final bool isWatched;
  final VoidCallback? onTap;

  static TextStyle get _titleStyle => DetailsText.inter(
        size: 14.sp,
        weight: FontWeight.w700,
        color: Colors.white,
        height: 20 / 14,
      );

  static TextStyle get _metaStyle => DetailsText.inter(
        size: 11.sp,
        weight: FontWeight.w400,
        color: const Color(0xFF9CA3AF),
        height: 16.5 / 11,
      );

  static TextStyle get _synopsisStyle => DetailsText.inter(
        size: 12.sp,
        weight: FontWeight.w400,
        color: const Color(0xFF9CA3AF),
        height: 19.5 / 12,
      );

  @override
  Widget build(BuildContext context) {
    final titleText = '${episode.episodeNumber}. ${episode.name}';
    final runtimeText = episode.compactRuntimeLabel;
    final dateText = episode.formattedAirDate;
    final synopsisText = episode.overview;
    final thumbW = 144.w;
    final thumbH = 80.w;

    return Stack(
      children: [
        SizedBox(
          width: double.infinity,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top 80px row: 144×80 Thumbnail + Vertically Centered Title & Metadata
              SizedBox(
                height: thumbH,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Episode Thumbnail (144×80, radius 6, #171717)
                    Container(
                      width: thumbW,
                      height: thumbH,
                      decoration: BoxDecoration(
                        color: const Color(0xFF171717),
                        borderRadius: BorderRadius.all(Radius.circular(6.r)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          FallbackNetworkImage(
                            urls: [episode.stillUrl, fallbackBackdropUrl],
                            memWidth: thumbW,
                            memHeight: thumbH,
                            fadeIn: const Duration(milliseconds: 120),
                            placeholder:
                                const ColoredBox(color: Color(0xFF171717)),
                            fallback: const _EpisodeThumbnailFallback(),
                          ),
                          if (isWatched)
                            Positioned(
                              top: 5.r,
                              right: 5.r,
                              child: Container(
                                width: 18.r,
                                height: 18.r,
                                decoration: const BoxDecoration(
                                  color: Color(0xB8000000),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Icons.check_rounded,
                                  size: 12.r,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          if ((progress != null && progress! > 0) || isWatched)
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              height: 3.5.h,
                              child: ColoredBox(
                                color: const Color(0xFF374151),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: FractionallySizedBox(
                                    widthFactor: isWatched
                                        ? 1.0
                                        : progress!.clamp(0.0, 1.0),
                                    heightFactor: 1.0,
                                    child: const SizedBox.expand(
                                      child: ColoredBox(
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Episode Details (Title & Metadata): padding-left 12px
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(left: 12.w, top: 2.h),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              titleText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _titleStyle,
                            ),
                            if (runtimeText != null || dateText != null) ...[
                              SizedBox(height: 3.5.h),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  if (runtimeText != null)
                                    Text(
                                      runtimeText,
                                      maxLines: 1,
                                      style: _metaStyle,
                                    ),
                                  if (runtimeText != null && dateText != null)
                                    SizedBox(width: 6.w),
                                  if (dateText != null)
                                    Flexible(
                                      child: Text(
                                        dateText,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: _metaStyle,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Episode Synopsis text (padding-top 8px, padding-right 29.79px, height 39px)
              if (synopsisText.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(top: 8.h, right: 29.79.w),
                  child: SizedBox(
                    height: 39.h,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        synopsisText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: _synopsisStyle,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // Click identification ripple on top: low-opacity black shimmer
        Positioned.fill(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.all(Radius.circular(6.r)),
              splashColor: const Color(0x59000000), // translucent black (~35%)
              highlightColor: const Color(0x40000000), // translucent black (~25%)
              onTap: onTap == null
                  ? null
                  : () {
                      HapticFeedback.selectionClick();
                      onTap!();
                    },
            ),
          ),
        ),
      ],
    );
  }
}

/// Figma "Section - TabNavigation": tabs 24px apart on a 1px #171717 divider.
///
/// The active tab's indicator (2.5px, fully rounded, white) sits inside the
/// Stack sized by the tab's text, so its width automatically matches the
/// active label ("Episodes" ~72.2px, "Related" ~58.8px, "Details" ~54.5px).
class DetailTabBar extends StatelessWidget {
  const DetailTabBar({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFF171717))),
        ),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 1),
          child: Row(children: [
            for (var i = 0; i < labels.length; i++) ...[
              if (i > 0) SizedBox(width: 24.w),
              DetailTabButton(
                label: labels[i],
                active: i == selected,
                onTap: () => onSelected(i),
              ),
            ],
          ]),
        ),
      );
}

class DetailTabButton extends StatelessWidget {
  const DetailTabButton({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  static const _duration = Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (active) return;
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Stack(children: [
          Padding(
            padding: EdgeInsets.only(bottom: 10.h),
            child: AnimatedDefaultTextStyle(
              duration: _duration,
              curve: Curves.easeOut,
              style: DetailsText.inter(
                size: 16.sp,
                weight: FontWeight.w700,
                color: active ? Colors.white : const Color(0xFF737373),
                height: 24 / 16,
              ),
              child: Text(label, maxLines: 1, softWrap: false),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 2.5.h,
            child: AnimatedOpacity(
              opacity: active ? 1 : 0,
              duration: _duration,
              curve: Curves.easeOut,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.all(Radius.circular(1.25.r)),
                ),
              ),
            ),
          ),
        ]),
      );
}

/// Floating back control: 36×36 at 17/17, chevron only, no background fill.
class DetailBackButton extends StatelessWidget {
  const DetailBackButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: SizedBox(
            width: 36.r,
            height: 36.r,
            child: Center(child: SvgPicture.string(kDetailChevronSvg, width: 20.r, height: 20.r)),
          ),
        ),
      );
}

/// Static low-overhead skeleton for the Episode List while season episodes load.
class DetailEpisodesSkeleton extends StatelessWidget {
  const DetailEpisodesSkeleton({super.key, this.inset = 16.0});

  final double inset;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(horizontal: inset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const _SkeletonEpisodeItem(),
            SizedBox(height: 16.h),
            const _SkeletonEpisodeItem(),
            SizedBox(height: 16.h),
            const _SkeletonEpisodeItem(),
          ],
        ),
      );
}

class _SkeletonEpisodeItem extends StatelessWidget {
  const _SkeletonEpisodeItem();

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 127.h,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 80.w,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 144.w,
                    height: 80.w,
                    decoration: BoxDecoration(
                      color: const Color(0xFF171717),
                      borderRadius: BorderRadius.circular(6.r),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 130.w,
                          height: 14.h,
                          decoration: BoxDecoration(
                            color: AppColors.surface2,
                            borderRadius: BorderRadius.circular(4.r),
                          ),
                        ),
                        SizedBox(height: 8.h),
                        Container(
                          width: 150.w,
                          height: 11.h,
                          decoration: BoxDecoration(
                            color: AppColors.surface2,
                            borderRadius: BorderRadius.circular(4.r),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 12.h),
            Container(
              width: double.infinity,
              height: 11.h,
              margin: EdgeInsets.only(right: 30.w),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(4.r),
              ),
            ),
            SizedBox(height: 8.h),
            Container(
              width: 240.w,
              height: 11.h,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(4.r),
              ),
            ),
          ],
        ),
      );
}

/// Static low-overhead skeleton for the two Related OTT rows while core
/// metadata is in flight.
class DetailRelatedSkeleton extends StatelessWidget {
  const DetailRelatedSkeleton({super.key, this.inset = 16.0});

  final double inset;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _SkeletonRail(inset: inset, titleWidth: 104.w),
          SizedBox(height: AppDimens.rowSpacing),
          _SkeletonRail(inset: inset, titleWidth: 148.w),
        ],
      );
}

class _SkeletonRail extends StatelessWidget {
  const _SkeletonRail({required this.inset, required this.titleWidth});

  final double inset;
  final double titleWidth;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: inset),
            child: Container(
              width: titleWidth,
              height: 15.h,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(4.r),
              ),
            ),
          ),
          SizedBox(height: AppDimens.rowGap),
          SizedBox(
            height: AppDimens.posterHeight + 12.h,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(inset, 0, inset, 12.h),
              itemExtent: AppDimens.posterStride,
              itemCount: 4,
              itemBuilder: (_, __) => Padding(
                padding: EdgeInsets.only(right: AppDimens.posterGap),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(AppDimens.posterRadius),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
}

/// Compact OLED retry boundary shown when TMDB metadata or episodes fail.
class DetailErrorRetry extends StatelessWidget {
  const DetailErrorRetry({
    super.key,
    required this.onRetry,
    this.error,
    this.inset = 16.0,
  });

  final VoidCallback onRetry;
  final Object? error;
  final double inset;

  @override
  Widget build(BuildContext context) {
    final mapped = UserError.from(error, logTag: 'DetailErrorRetry');
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 16.h),
      child: AppStatusCard.fromError(
        mapped,
        onAction: onRetry,
        compact: true,
      ),
    );
  }
}

/// Responsive 3-column grid of Cast members displaying each actor's photo
/// (`profileUrl` with a circular dark avatar fallback), actor name, and character.
class DetailCastGrid extends StatelessWidget {
  const DetailCastGrid({super.key, required this.cast});

  final List<TmdbCast> cast;

  @override
  Widget build(BuildContext context) {
    final visibleCast = cast.take(15).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        const columns = 3;
        final horizontalGap = 12.w;
        final itemWidth =
            ((constraints.maxWidth - horizontalGap * (columns - 1)) / columns).clamp(70.w, 160.w);

        return Wrap(
          spacing: horizontalGap,
          runSpacing: 16.h,
          children: [
            for (final member in visibleCast)
              SizedBox(
                width: itemWidth,
                child: _DetailCastCard(member: member),
              ),
          ],
        );
      },
    );
  }
}

class _DetailCastCard extends StatelessWidget {
  const _DetailCastCard({required this.member});

  final TmdbCast member;

  @override
  Widget build(BuildContext context) {
    final avatarSize = 72.r;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: avatarSize,
          height: avatarSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF171717),
            border: Border.all(color: const Color(0x26FFFFFF), width: 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: FallbackNetworkImage(
            urls: [member.profileUrl],
            memWidth: avatarSize,
            memHeight: avatarSize,
            fit: BoxFit.cover,
            placeholder: const ColoredBox(color: Color(0xFF171717)),
            fallback: _CastInitialsFallback(name: member.name),
          ),
        ),
        SizedBox(height: 8.h),
        Text(
          member.name,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: DetailsText.inter(
            size: 12.sp,
            weight: FontWeight.w600,
            color: const Color(0xFFE5E5E5),
            height: 16 / 12,
          ),
        ),
        if (member.character.trim().isNotEmpty) ...[
          SizedBox(height: 2.h),
          Text(
            member.character,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: DetailsText.inter(
              size: 11.sp,
              weight: FontWeight.w400,
              color: const Color(0xFF9CA3AF),
              height: 15 / 11,
            ),
          ),
        ],
      ],
    );
  }
}

class _CastInitialsFallback extends StatelessWidget {
  const _CastInitialsFallback({required this.name});

  final String name;

  String _initials(String raw) {
    final parts = raw.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: const Color(0xFF18181B),
        child: Center(
          child: Text(
            _initials(name),
            style: DetailsText.inter(
              size: 18.sp,
              weight: FontWeight.w700,
              color: const Color(0xFF71717A),
              height: 1,
            ),
          ),
        ),
      );
}
