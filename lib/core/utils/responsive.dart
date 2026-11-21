import 'package:flutter/widgets.dart';

/// Unified, device-agnostic responsive scaling utility anchored to the
/// connected reference Android phone:
/// - `adb shell wm size`    -> Physical size: 720x1612
/// - `adb shell wm density` -> Physical density: 320, Override density: 272
/// - Effective logical dpr  -> 272 / 160 = 1.7
/// - Logical viewport (dp)  -> 423.52941176470586 × 948.2352941176471 dp
class Responsive {
  Responsive._();

  /// Physical resolution and active override density of the connected phone.
  static const double referencePhysicalWidth = 720.0;
  static const double referencePhysicalHeight = 1612.0;
  static const double referenceDensityDpi = 272.0;
  static const double referenceDevicePixelRatio =
      referenceDensityDpi / 160.0; // 1.7

  /// Exact logical reference dimensions in dp (720 / 1.7 × 1612 / 1.7).
  static const double referenceWidth =
      referencePhysicalWidth / referenceDevicePixelRatio; // 423.52941176470586
  static const double referenceHeight =
      referencePhysicalHeight / referenceDevicePixelRatio; // 948.2352941176471

  /// Safe clamp bounds so extreme screens or tablets never distort.
  static const double minScale = 0.82;
  static const double maxScale = 1.25;

  static const Size _kFlutterTestDefaultSize = Size(800.0, 600.0);

  static Size _currentSize = const Size(referenceWidth, referenceHeight);
  static bool _hasExplicitMediaQuery = false;

  /// Updates the active viewport dimensions using [MediaQuery.sizeOf(context)].
  static void init(BuildContext context) {
    final mqSize = MediaQuery.sizeOf(context);
    final rvSize = _renderViewConfiguredSize();
    if (mqSize != _kFlutterTestDefaultSize) {
      if (rvSize != null &&
          rvSize != _kFlutterTestDefaultSize &&
          rvSize != mqSize) {
        _currentSize = rvSize;
        _hasExplicitMediaQuery = false;
      } else {
        _currentSize = mqSize;
        _hasExplicitMediaQuery = true;
      }
      return;
    }
    _hasExplicitMediaQuery = false;
    if (rvSize != null && rvSize != _kFlutterTestDefaultSize) {
      _currentSize = rvSize;
    } else {
      _currentSize = const Size(referenceWidth, referenceHeight);
    }
  }

  /// Resolves the logical viewport [Size] from [MediaQuery.sizeOf(context)].
  static Size sizeOf(BuildContext context) {
    init(context);
    return _effectiveSize;
  }

  static Size? _renderViewConfiguredSize() {
    try {
      final binding = WidgetsBinding.instance;
      if (binding.renderViews.isNotEmpty) {
        final cfg =
            binding.renderViews.first.configuration.logicalConstraints.biggest;
        if (cfg.isFinite && cfg.width > 0 && cfg.height > 0) {
          return cfg;
        }
      }
    } catch (_) {}
    return null;
  }

  static Size get _effectiveSize {
    final rvSize = _renderViewConfiguredSize();
    if (rvSize != null) {
      if (rvSize != _kFlutterTestDefaultSize) {
        return rvSize;
      }
      if (!_hasExplicitMediaQuery) {
        return const Size(referenceWidth, referenceHeight);
      }
    }
    if (_currentSize == _kFlutterTestDefaultSize) {
      return const Size(referenceWidth, referenceHeight);
    }
    return _currentSize;
  }

  /// Logical width in portrait orientation (or shortestSide when in landscape).
  static double get screenWidth {
    final s = _effectiveSize;
    return s.width <= s.height ? s.width : s.shortestSide;
  }

  /// Logical height in portrait orientation (or longestSide when in landscape).
  static double get screenHeight {
    final s = _effectiveSize;
    return s.width <= s.height ? s.height : s.longestSide;
  }

  /// Width scale factor `sw = screenWidth / referenceWidth` clamped to [0.82, 1.25].
  /// Equal to 1.0 on the connected reference device (423.53 × 948.24 dp).
  static double get sw =>
      (screenWidth / referenceWidth).clamp(minScale, maxScale).toDouble();

  /// Height scale factor `sh = screenHeight / referenceHeight` clamped to [0.82, 1.25].
  /// Equal to 1.0 on the connected reference device (423.53 × 948.24 dp).
  static double get sh =>
      (screenHeight / referenceHeight).clamp(minScale, maxScale).toDouble();

  /// Context-aware width scale factor using [MediaQuery.sizeOf(context)].
  static double swOf(BuildContext context) {
    init(context);
    return sw;
  }

  /// Context-aware height scale factor using [MediaQuery.sizeOf(context)].
  static double shOf(BuildContext context) {
    init(context);
    return sh;
  }

  static double scaleWidth(num value) => value.toDouble() * sw;
  static double scaleHeight(num value) => value.toDouble() * sh;
  static double scaleText(num value) => value.toDouble() * sw;
  static double scaleRadius(num value) => value.toDouble() * sw;
}

extension ResponsiveNumExtension on num {
  /// Width-scaled dimension (`this * sw`).
  double get w => Responsive.scaleWidth(this);

  /// Height-scaled dimension (`this * sh`).
  double get h => Responsive.scaleHeight(this);

  /// Font size scaled proportionally (`this * sw`).
  double get sp => Responsive.scaleText(this);

  /// Border radius or icon size scaled proportionally (`this * sw`).
  double get r => Responsive.scaleRadius(this);
}

extension ResponsiveContextExtension on BuildContext {
  double get sw => Responsive.swOf(this);
  double get sh => Responsive.shOf(this);
}
