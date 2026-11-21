import 'package:flutter/painting.dart';
import 'package:google_fonts/google_fonts.dart';

/// Typography for the details screen, matching the Figma export (Inter for body
/// and buttons, Syncopate for the title wordmark).
///
/// These fonts are fetched once and cached on disk. They are only requested when
/// a details screen opens, never at app start, so the home screen's startup is
/// not affected.
class DetailsText {
  DetailsText._();

  static bool _fontsReady = false;
  static Future<void>? _preloadFuture;

  /// True once the details typography has resolved in this session, avoiding
  /// redundant `FutureBuilder` rebuilds on subsequent Details routes.
  static bool get areFontsReady => _fontsReady;

  /// Preloads Inter and Syncopate once per session with a bounded timeout.
  static Future<void> ensurePreloaded() {
    if (_fontsReady) return Future<void>.value();
    return _preloadFuture ??= GoogleFonts.pendingFonts(preloadStyles)
        .timeout(const Duration(milliseconds: 1500))
        .catchError((_) => <void>[])
        .whenComplete(() => _fontsReady = true);
  }

  static TextStyle inter({
    required double size,
    FontWeight weight = FontWeight.w400,
    Color color = const Color(0xFFFFFFFF),
    double? height,
  }) =>
      GoogleFonts.inter(fontSize: size, fontWeight: weight, color: color, height: height);

  static TextStyle syncopate(double size, double lineHeight, Color color) => GoogleFonts.syncopate(
        fontSize: size,
        height: lineHeight / size,
        fontWeight: FontWeight.w700,
        color: color,
      );

  /// Every style the details screen uses, so they can be fetched in one call.
  static final List<TextStyle> preloadStyles = [
    inter(size: 11),
    inter(size: 12),
    inter(size: 12, weight: FontWeight.w600),
    inter(size: 14),
    inter(size: 14.5),
    inter(size: 13.5, weight: FontWeight.w600),
    inter(size: 14, weight: FontWeight.w600),
    inter(size: 14, weight: FontWeight.w700),
    inter(size: 15, weight: FontWeight.w500),
    inter(size: 16, weight: FontWeight.w700),
    syncopate(34, 37, const Color(0xFFFFFFFF)),
    syncopate(23, 28, const Color(0xFFFFFFFF)),
    syncopate(8, 10, const Color(0xFFFFFFFF)),
  ];
}
