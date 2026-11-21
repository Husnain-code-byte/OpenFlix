import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';


import '../../../../core/theme/app_theme.dart';

const _arcPath =
    'M94.5578 272.521C164.601 216.595 256.427 205.495 330.027 229.531C364.892 240.967 396.203 259.662 423.889 284.175C426.558 286.552 428.859 281.599 426.17 278.257C395.221 239.591 355.885 214.37 315.062 205.614C237.414 188.889 146.582 206.167 83.7892 273.049C80.3463 276.672 83.7154 282.479 87.1582 278.856L94.5578 272.521Z';
const _arrowPath = 'M404.111 282.695L431.452 291.61L424.475 248.585L404.111 282.695Z';

/// App icon from Figma frame 32:15 (gradient, glow, arc + "pixel").
class PixelAppIcon extends StatelessWidget {
  const PixelAppIcon({super.key, this.size = 96});
  final double size;

  @override
  Widget build(BuildContext context) {
    final r = 114 / 512 * size;
    return ClipRRect(
      borderRadius: BorderRadius.circular(r),
      child: Image.asset(
        'assets/ic_launcher.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: AppColors.iconGradient,
            borderRadius: BorderRadius.circular(r),
            border: Border.all(color: const Color(0x2E5E9CC9)),
          ),
          child: Stack(alignment: Alignment.center, children: [
            // Soft blue glow (ellipse 190×100, blur 32.5)
            Container(
              width: size * 0.74,
              height: size * 0.39,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.all(Radius.elliptical(size * .37, size * .2)),
                boxShadow: [BoxShadow(color: const Color(0x260063C7), blurRadius: size * .13, spreadRadius: size * .02)],
              ),
            ),
            SizedBox(width: size, height: size, child: const PixelMark(fullCanvas: true)),
          ]),
        ),
      ),
    );
  }
}

/// The arc + "pixel" text. With [fullCanvas] it renders in the 512 icon space;
/// otherwise it's cropped to a header wordmark.
class PixelMark extends StatelessWidget {
  const PixelMark({super.key, this.fullCanvas = false, this.height = 26});
  final bool fullCanvas;
  final double height;

  @override
  Widget build(BuildContext context) {
    final viewBox = fullCanvas ? '0 0 512 512' : '80 196 356 100';
    final svg = '<svg viewBox="$viewBox" xmlns="http://www.w3.org/2000/svg">'
        '<path d="$_arcPath" fill="#0779FF"/><path d="$_arrowPath" fill="#0779FF"/></svg>';
    return LayoutBuilder(builder: (context, c) {
      final w = fullCanvas ? c.maxWidth : height * 356 / 100;
      final h = fullCanvas ? c.maxHeight : height;
      final scale = fullCanvas ? w / 512 : h / 100;
      final dx = fullCanvas ? 179.25 * scale : (179.25 - 80) * scale;
      final baseline = fullCanvas ? 290.5 * scale : (290.5 - 196) * scale;
      final fontSize = 62.18 * scale;
      return SizedBox(
        width: w,
        height: h,
        child: Stack(children: [
          SvgPicture.string(svg, width: w, height: h),
          Positioned(
            left: dx,
            top: baseline - fontSize * 0.95,
            child: Text('pixel',
                style: AppText.brand.copyWith(
                    fontSize: fontSize, fontWeight: FontWeight.w700, color: AppColors.accent, height: 1)),
          ),
        ]),
      );
    });
  }
}
