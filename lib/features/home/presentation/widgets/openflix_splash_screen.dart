import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../../core/utils/responsive.dart';

/// Opening splash screen from Figma frame 114:23 (`Html → Body → MobileViewportContainer`).
///
/// Renders each of the 8 arched letters (`O`, `P`, `E`, `N`, `F`, `L`, `I`, `X`)
/// as individual vector paths in the `1024×571` (`111:62`) reference coordinate
/// space, animates them in one-by-one, holds the full `OPENFLIX` wordmark for a
/// split second while background catalogs and posters warm up, and then fades
/// out smoothly to reveal the Home screen.
class OpenFlixSplashScreen extends StatefulWidget {
  const OpenFlixSplashScreen({
    super.key,
    required this.isHomeReady,
    required this.onFinished,
  });

  /// True once the initial Home shelves have resolved and started pre-caching posters.
  final bool isHomeReady;

  /// Called once the exit fade completes so the parent can unmount the overlay.
  final VoidCallback onFinished;

  @override
  State<OpenFlixSplashScreen> createState() => _OpenFlixSplashScreenState();
}

class _OpenFlixSplashScreenState extends State<OpenFlixSplashScreen>
    with TickerProviderStateMixin {
  /// Drives the staggered per-letter emergence (0..620ms).
  late final AnimationController _enterController;

  /// Drives the subtle rest breathing & exit fade-out (0..240ms).
  late final AnimationController _exitController;

  Timer? _restTimer;
  Timer? _maxHoldTimer;
  bool _minRestElapsed = false;
  bool _exiting = false;

  @override
  void initState() {
    super.initState();
    _enterController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );
    _exitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );

    _enterController.forward().whenComplete(() {
      if (!mounted) return;
      // Let the full OPENFLIX wordmark rest on screen for a split second (~460ms)
      _restTimer = Timer(const Duration(milliseconds: 460), () {
        if (!mounted) return;
        _minRestElapsed = true;
        if (widget.isHomeReady) {
          _triggerExit();
        }
      });
      // Cap any extra wait for slow networks so the splash remains a split-second experience
      _maxHoldTimer = Timer(const Duration(milliseconds: 920), () {
        if (!mounted) return;
        _triggerExit();
      });
    });
  }

  @override
  void didUpdateWidget(covariant OpenFlixSplashScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isHomeReady && _minRestElapsed && !_exiting) {
      _triggerExit();
    }
  }

  void _triggerExit() {
    if (_exiting || !mounted) return;
    _exiting = true;
    _restTimer?.cancel();
    _maxHoldTimer?.cancel();
    _exitController.forward().whenComplete(() {
      if (mounted) widget.onFinished();
    });
  }

  @override
  void dispose() {
    _restTimer?.cancel();
    _maxHoldTimer?.cancel();
    _enterController.dispose();
    _exitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);
    return AnimatedBuilder(
      animation: Listenable.merge([_enterController, _exitController]),
      builder: (context, _) {
        final exitT = Curves.easeInOutCubic.transform(_exitController.value);
        final screenOpacity = (1.0 - exitT).clamp(0.0, 1.0);
        final wordmarkScale = 1.0 + (0.016 * _enterController.value) + (0.028 * exitT);

        return IgnorePointer(
          ignoring: _exiting,
          child: Opacity(
            opacity: screenOpacity,
            child: ColoredBox(
              color: Colors.black,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Centered 340px container with 4px horizontal padding and 111/62 aspect ratio
                  Center(
                    child: SizedBox(
                      width: 340.w,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4.w),
                        child: AspectRatio(
                          aspectRatio: 111 / 62,
                          child: Transform.scale(
                            scale: wordmarkScale,
                            child: CustomPaint(
                              painter: _OpenFlixWordmarkPainter(
                                enterProgress: _enterController.value,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Bottom Home Indicator Pill (Figma 114:23: 144×4.5, radius 9999, rgba(64,64,64,0.80), bottom 12px)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 12.h,
                    child: Center(
                      child: Container(
                        width: 144.w,
                        height: 4.5.h,
                        decoration: BoxDecoration(
                          color: const Color.fromRGBO(64, 64, 64, 0.80),
                          borderRadius: BorderRadius.circular(9999),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LetterSpec {
  const _LetterSpec({
    required this.center,
    required this.buildPath,
  });

  final Offset center;
  final Path Function() buildPath;
}

class _OpenFlixWordmarkPainter extends CustomPainter {
  _OpenFlixWordmarkPainter({required this.enterProgress});

  final double enterProgress;

  static final List<_LetterSpec> _letters = [
    // 0: O (x: 106..203, y: 175..392)
    _LetterSpec(
      center: const Offset(154.5, 283.5),
      buildPath: () => Path()
        ..fillType = PathFillType.evenOdd
        ..moveTo(106, 220)
        ..cubicTo(106, 190, 125, 175, 154.5, 175)
        ..cubicTo(184, 175, 203, 190, 203, 220)
        ..lineTo(203, 344)
        ..cubicTo(203, 374, 184, 391, 154.5, 392)
        ..cubicTo(125, 393, 106, 376, 106, 346)
        ..close()
        ..moveTo(138.5, 220)
        ..cubicTo(138.5, 209, 144.5, 204.5, 154.5, 204.5)
        ..cubicTo(164.5, 204.5, 170.5, 209, 170.5, 220)
        ..lineTo(170.5, 345)
        ..cubicTo(170.5, 355, 164.5, 360.5, 154.5, 360.5)
        ..cubicTo(144.5, 360.5, 138.5, 355, 138.5, 345)
        ..close(),
    ),
    // 1: P (x: 223.5..316.5, y: 177..380)
    _LetterSpec(
      center: const Offset(270.0, 278.5),
      buildPath: () => Path()
        ..fillType = PathFillType.evenOdd
        ..moveTo(223.5, 177)
        ..lineTo(274, 177)
        ..cubicTo(302, 177, 316.5, 193, 316.5, 222)
        ..lineTo(316.5, 255)
        ..cubicTo(316.5, 284, 302, 301.5, 274, 301.5)
        ..lineTo(255.5, 301.5)
        ..lineTo(255.5, 377.5)
        ..lineTo(223.5, 380)
        ..close()
        ..moveTo(255.5, 205.5)
        ..lineTo(273, 205.5)
        ..cubicTo(281.5, 205.5, 285.5, 211, 285.5, 222)
        ..lineTo(285.5, 255)
        ..cubicTo(285.5, 266, 281.5, 272, 273, 272)
        ..lineTo(255.5, 272)
        ..close(),
    ),
    // 2: E (x: 332.5..415.5, y: 177..371)
    _LetterSpec(
      center: const Offset(374.0, 274.0),
      buildPath: () => Path()
        ..moveTo(332.5, 177)
        ..lineTo(415.5, 177)
        ..lineTo(415.5, 205)
        ..lineTo(364.5, 205)
        ..lineTo(364.5, 255.5)
        ..lineTo(405.5, 255.5)
        ..lineTo(405.5, 284.5)
        ..lineTo(364.5, 284.5)
        ..lineTo(364.5, 341)
        ..lineTo(415.5, 340)
        ..lineTo(415.5, 367.5)
        ..lineTo(332.5, 371)
        ..close(),
    ),
    // 3: N (x: 433.5..534.5, y: 177..366.5)
    _LetterSpec(
      center: const Offset(484.0, 271.8),
      buildPath: () => Path()
        ..moveTo(433.5, 177)
        ..lineTo(473.5, 177)
        ..lineTo(505.5, 283.5)
        ..lineTo(505.5, 177)
        ..lineTo(534.5, 177)
        ..lineTo(534.5, 366)
        ..lineTo(502, 366)
        ..lineTo(463, 239.5)
        ..lineTo(463, 366.5)
        ..lineTo(433.5, 366.5)
        ..close(),
    ),
    // 4: F (x: 556.5..639.5, y: 177..366.5)
    _LetterSpec(
      center: const Offset(598.0, 271.8),
      buildPath: () => Path()
        ..moveTo(556.5, 177)
        ..lineTo(639.5, 177)
        ..lineTo(639.5, 205.5)
        ..lineTo(588.5, 205.5)
        ..lineTo(588.5, 260.5)
        ..lineTo(628.5, 260.5)
        ..lineTo(628.5, 289.5)
        ..lineTo(588.5, 289.5)
        ..lineTo(588.5, 366.5)
        ..lineTo(556.5, 366)
        ..close(),
    ),
    // 5: L (x: 655.5..738.5, y: 177..374)
    _LetterSpec(
      center: const Offset(697.0, 275.5),
      buildPath: () => Path()
        ..moveTo(655.5, 177)
        ..lineTo(687.5, 177)
        ..lineTo(687.5, 342)
        ..lineTo(738.5, 345.5)
        ..lineTo(738.5, 374)
        ..lineTo(655.5, 369)
        ..close(),
    ),
    // 6: I (x: 753.5..785.5, y: 177..378.5)
    _LetterSpec(
      center: const Offset(769.5, 277.8),
      buildPath: () => Path()
        ..moveTo(753.5, 177)
        ..lineTo(785.5, 177)
        ..lineTo(785.5, 378.5)
        ..lineTo(753.5, 376)
        ..close(),
    ),
    // 7: X (x: 799.5..917.0, y: 177..395.5)
    _LetterSpec(
      center: const Offset(858.2, 286.2),
      buildPath: () => Path()
        ..moveTo(802.5, 177)
        ..lineTo(836.5, 177)
        ..lineTo(859, 243.5)
        ..lineTo(884, 177)
        ..lineTo(916.5, 177)
        ..lineTo(878, 279)
        ..lineTo(917, 395.5)
        ..lineTo(881.5, 390)
        ..lineTo(857, 318)
        ..lineTo(831.5, 383.5)
        ..lineTo(799.5, 380)
        ..lineTo(838, 278.5)
        ..close(),
    ),
  ];

  static final List<Path> _cachedPaths = [
    for (final spec in _letters) spec.buildPath(),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 1024.0, size.height / 571.0);

    final count = _letters.length;
    const step = 0.072; // 7 * 0.072 = 0.504, plus 0.496 duration = 1.0
    const span = 0.496;

    for (var i = 0; i < count; i++) {
      final start = i * step;
      final raw = ((enterProgress - start) / span).clamp(0.0, 1.0);
      if (raw <= 0.0) continue;

      final easeOut = Curves.easeOutCubic.transform(raw);
      final easeBack = Curves.easeOutBack.transform(raw);
      final spec = _letters[i];
      final path = _cachedPaths[i];

      // Subtle vertical rise + scale-in around each letter's own geometric center
      final dy = (1.0 - easeOut) * 24.0;
      final scaleX = 0.82 + 0.18 * easeBack;
      final scaleY = 0.68 + 0.32 * easeBack;
      final alpha = Curves.easeOut.transform((raw * 1.35).clamp(0.0, 1.0));

      canvas.save();
      canvas.translate(spec.center.dx, spec.center.dy + dy);
      canvas.scale(scaleX, scaleY);
      canvas.translate(-spec.center.dx, -spec.center.dy);

      // Soft crimson glow pulse as the letter lands
      final glowStrength = (1.0 - (raw - 0.55).abs() * 1.6).clamp(0.18, 1.0) * alpha;
      final glowPaint = Paint()
        ..color = const Color(0xFFE50914).withValues(alpha: 0.28 * glowStrength)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14);
      canvas.drawPath(path, glowPaint);

      // Crisp brand crimson letter fill matching reference #D90B13 / #E50914
      final fillPaint = Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 175),
          const Offset(0, 395),
          [
            const Color(0xFFE50914).withValues(alpha: alpha),
            const Color(0xFFD90B13).withValues(alpha: alpha),
          ],
        );
      canvas.drawPath(path, fillPaint);

      canvas.restore();
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _OpenFlixWordmarkPainter oldDelegate) =>
      oldDelegate.enterProgress != enterProgress;
}
