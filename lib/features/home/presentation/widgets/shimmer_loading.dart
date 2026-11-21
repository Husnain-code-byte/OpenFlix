import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/responsive.dart';

class PixelShimmer extends StatelessWidget {
  const PixelShimmer({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Shimmer.fromColors(
        baseColor: const Color(0xFF121418),
        highlightColor: const Color(0xFF1E2228),
        period: const Duration(milliseconds: 1400),
        child: child,
      );
}

class _Box extends StatelessWidget {
  const _Box({this.width, required this.height, this.radius = 6, this.color = Colors.white});
  final double? width;
  final double height;
  final double radius;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(radius)),
      );
}

class ShelfSkeleton extends StatelessWidget {
  const ShelfSkeleton({
    super.key,
    this.titleWidth = 90,
    double? inset,
  }) : _inset = inset;
  final double titleWidth;
  final double? _inset;

  double get inset => _inset ?? AppDimens.screenPadding;

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);
    final effectiveInset = inset;
    return PixelShimmer(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: effectiveInset),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _Box(width: titleWidth.w, height: 15.h, radius: 4.r),
          SizedBox(height: AppDimens.rowGap),
          SizedBox(
            height: AppDimens.posterHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 4,
              separatorBuilder: (_, __) => SizedBox(width: AppDimens.posterGap),
              itemBuilder: (_, __) => _Box(
                width: AppDimens.posterWidth,
                height: AppDimens.posterHeight,
                radius: AppDimens.posterRadius,
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Skeleton matching the Figma `354×480` featured hero card (`AppDimens.heroSlideHeight`).
class HeroBannerSkeleton extends StatelessWidget {
  const HeroBannerSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);
    const dim = Color(0x40000000);
    return SizedBox(
      height: AppDimens.heroSlideHeight(context),
      child: Padding(
        padding: EdgeInsets.fromLTRB(AppDimens.heroGutter, AppDimens.heroTopPad, AppDimens.heroGutter, 0),
        child: Align(
          alignment: Alignment.topCenter,
          child: Container(
            height: AppDimens.heroCardHeight(context),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.heroBg,
              borderRadius: BorderRadius.circular(AppDimens.heroRadius),
              border: Border.all(color: AppColors.heroBorder),
            ),
            child: Stack(fit: StackFit.expand, children: [
              PixelShimmer(child: Container(color: Colors.white)),
              Positioned(
                left: 15.w,
                right: 15.w,
                bottom: 15.h,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  _Box(width: 190.w, height: 37.h, color: dim),
                  SizedBox(height: 1.h),
                  _Box(width: 70.w, height: 10.h, color: dim),
                  SizedBox(height: 1.h),
                  _Box(width: 230.w, height: 28.h, color: dim),
                  SizedBox(height: 12.h),
                  _Box(width: 180.w, height: 15.h, color: dim),
                  SizedBox(height: 5.h),
                  _Box(width: 150.w, height: 14.h, color: dim),
                  SizedBox(height: 12.h),
                  Row(children: [
                    Expanded(child: _Box(height: 42.h, radius: 5.r, color: dim)),
                    SizedBox(width: 10.w),
                    Expanded(child: _Box(height: 42.h, radius: 5.r, color: dim)),
                  ]),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Skeleton matching the Figma layout: 354×480 hero card → 26px → poster rows.
class HomeSkeleton extends StatelessWidget {
  const HomeSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const HeroBannerSkeleton(),
      SizedBox(height: AppDimens.afterHeroGap),
      const ShelfSkeleton(titleWidth: 70),
      SizedBox(height: 24.h),
      const ShelfSkeleton(titleWidth: 110),
      SizedBox(height: 24.h),
      const ShelfSkeleton(titleWidth: 85),
    ]);
  }
}
