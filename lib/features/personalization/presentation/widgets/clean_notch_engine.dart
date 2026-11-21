import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Processed result of the 3-Pass Clean Notch Poster Backdrop Blur Engine
/// (`render_clean_notch.py` / `TITLE_BACKDROP_BLUR_ROADMAP.md`).
class ProcessedCleanNotchPoster {
  const ProcessedCleanNotchPoster({
    required this.image,
    required this.bgR,
    required this.bgG,
    required this.bgB,
    required this.bgLum,
    this.notchColor = const Color(0xD6CED4E0),
    this.notchInkColor = const Color(0xF20A0C10),
  });

  final ui.Image image;
  final double bgR;
  final double bgG;
  final double bgB;
  final double bgLum;
  final Color notchColor;
  final Color notchInkColor;
}

/// Processed result of the Clean Notch Clearlogo Engine
/// (`composite_logo` in `render_clean_notch.py:194-278`).
class ProcessedCleanNotchLogo {
  const ProcessedCleanNotchLogo({
    required this.image,
    required this.aspectRatio,
  });

  final ui.Image image;
  final double aspectRatio;
}

/// Verbatim Dart port of the PostersPlus `clean_notch` rendering pipeline:
/// - Pass 1: Feathered Artwork Frosting (`_vignette_frost_band`, 24% width radius,
///   4x downscale-blur-bicubic-upscale, normalized power-1.5 LUT mask)
/// - Pass 2: Luminance Levelling (`_vignette_level_band`, bleed > 3.0 budget dimming)
/// - Pass 3: 36-bin Chroma-Weighted Hue Histogram with skin/shadow noise gates,
///   0.40 reference luma equalization, and CIELAB C* <= 27.0 chroma clamping
/// - Clearlogo Alpha Trimming (`alpha > 32`), Geometric Mean Area Scaling, and
///   Background-Aware Contrast Rescue (`composite_logo`)
/// - Clean Mode Genre + Rating resolution and optical alignment (`render_clean_rating`)
class CleanNotchEngine {
  CleanNotchEngine._();

  /// Working canvas dimensions for Tall cards (1.5x supersampled 176x328 -> fits w342 bucket).
  static const int canvasWidth = 264;
  static const int canvasHeight = 492;

  /// Working canvas dimensions for Landscape cards (1.5x supersampled 305x172 -> fits w500 bucket).
  static const int canvasLandscapeWidth = 458;
  static const int canvasLandscapeHeight = 258;

  /// Bottom frosted vignette height ratio (50% of tall/portrait poster height, 56% of landscape height).
  static const double bottomHeightRatio = 0.50;
  static const double landscapeBottomHeightRatio = 0.56;

  /// Peak alpha (225 / 255 = 88.2% for tall/portrait, 232 / 255 = 91.0% for landscape).
  static const int maxAlpha = 225;
  static const int landscapeMaxAlpha = 232;

  /// Max supersampled canvas width for Hero clean_notch poster processing (1.5x ~360dp card width).
  static const int heroCanvasWidth = 540;

  /// Non-linear easing exponent (power-1.5 curve).
  static const double bottomGradientCurve = 1.5;

  /// Vignette color parameters from `clean_notch`.
  static const double vignetteSaturation = 2.5;
  static const double vignetteLightness = 1.3;
  static const double vignetteBlur = 1.0;

  /// Clearlogo & fallback title bottom anchor ratio (`21%` on tall, `21.5%` on landscape).
  static const double logoBottomMarginRatio = 0.21;
  static const double landscapeLogoBottomMarginRatio = 0.215;

  /// Clean Metadata Row (`"{Genre} ★ {Score}"`) typography & optical center constants
  /// (`render_clean_notch.py:1477-1556` & `CLEAN_METADATA_ROW_ROADMAP.md`).
  static const double metadataFontSizeRatio = 0.071;
  static const double metadataCenterYRatio = 0.910;
  static const double landscapeMetadataFontSizeRatio = 0.072;
  static const double landscapeMetadataCenterYRatio = 0.895;
  static const FontWeight metadataFontWeight = FontWeight.w500;
  static const Color metadataTextColor = Color(0xFFD0D4DC);

  static final Map<String, ProcessedCleanNotchPoster> _posterCache = {};
  static final Map<String, Future<ProcessedCleanNotchPoster?>> _inflightPosters = {};

  static final Map<String, ProcessedCleanNotchLogo> _logoCache = {};
  static final Map<String, Future<ProcessedCleanNotchLogo?>> _inflightLogos = {};

  /// Serializes GPU texture readbacks so multiple cards entering the viewport during
  /// a fling never stall the raster thread simultaneously.
  static Future<void> _taskQueue = Future<void>.value();

  static Future<T?> _enqueueTask<T>(Future<T?> Function() action) {
    final completer = Completer<T?>();
    _taskQueue = _taskQueue.then((_) async {
      try {
        // Yield a microtask/frame turn so active scroll frames stay at 120fps.
        await Future<void>.delayed(Duration.zero);
        completer.complete(await action());
      } catch (_) {
        completer.complete(null);
      }
    });
    return completer.future;
  }

  static ProcessedCleanNotchPoster? getCachedPoster(String url) => _posterCache[url];

  static ProcessedCleanNotchLogo? getCachedLogo(String key) => _logoCache[key];

  /// Western Genre Priority Ordering verbatim from `config.py:754-758` &
  /// `CLEAN_METADATA_ROW_ROADMAP.md` Section 2.1.
  static const List<String> _genrePriorityOrder = [
    'Horror',
    'Thriller',
    'Mystery',
    'Sci-Fi',
    'Crime',
    'Comedy',
    'Romance',
    'Fantasy',
    'Animation',
    'Family',
    'Action',
    'History',
    'Music',
    'War',
    'Western',
    'Documentary',
    'Drama',
    'Adventure',
    'Reality',
    'Kids',
    'News',
    'Soap',
    'Talk',
  ];

  static String _normalizeGenreName(String raw) {
    final trimmed = raw.trim();
    switch (trimmed) {
      case 'Science Fiction':
      case 'Sci-Fi & Fantasy':
        return 'Sci-Fi';
      case 'Action & Adventure':
        return 'Action';
      case 'War & Politics':
        return 'War';
      default:
        return trimmed;
    }
  }

  /// Resolves the single primary genre according to `clean_notch` priority order.
  static String? resolvePrimaryGenre(List<String> genres) {
    if (genres.isEmpty) return null;
    final normalized = <String>[
      for (final g in genres)
        if (g.trim().isNotEmpty) _normalizeGenreName(g),
    ];
    if (normalized.isEmpty) return null;

    for (final priority in _genrePriorityOrder) {
      for (final g in normalized) {
        if (g.toLowerCase() == priority.toLowerCase()) {
          return priority;
        }
      }
    }
    return normalized.first;
  }

  /// Formats the Clean Mode metadata label (`"{Genre} ★ {Score}"`) verbatim from
  /// `main.py:3353-3364` and `CLEAN_METADATA_ROW_ROADMAP.md`.
  static String? formatCleanMetadataLabel({
    required List<String> genres,
    required String? rawRating,
  }) {
    final primaryGenre = resolvePrimaryGenre(genres);
    final genreLabel = primaryGenre == 'Documentary' ? 'Doc' : (primaryGenre ?? '');

    String? scoreText;
    if (rawRating != null && rawRating.trim().isNotEmpty) {
      final val = double.tryParse(rawRating.trim());
      if (val != null && val > 0) {
        if (val >= 100.0) {
          scoreText = '10';
        } else if (val > 10.0) {
          final s = val / 10.0;
          scoreText = s >= 9.95 ? '10' : s.toStringAsFixed(1);
        } else {
          scoreText = val >= 9.95 ? '10' : val.toStringAsFixed(1);
        }
      }
    }

    if (genreLabel.isNotEmpty && scoreText != null) {
      return '$genreLabel ★ $scoreText';
    } else if (scoreText != null) {
      return '★ $scoreText';
    } else if (genreLabel.isNotEmpty) {
      return genreLabel;
    }
    return null;
  }

  /// Maps primary genre to its bundled fallback title font family
  /// (`main.py:3087-3106` & `FLUTTER_CLEAN_NOTCH_GUIDE.md`).
  static String genreFallbackFontFamily(String? genre) {
    switch (genre) {
      case 'Horror':
      case 'Thriller':
      case 'Mystery':
        return 'Creepster';
      case 'Action':
      case 'Sci-Fi':
      case 'Adventure':
      case 'Fantasy':
      case 'Western':
        return 'BebasNeue';
      case 'Comedy':
      case 'Animation':
      case 'Family':
        return 'Pacifico';
      case 'Drama':
      case 'Romance':
      case 'History':
      case 'Music':
        return 'PlayfairDisplay';
      case 'Crime':
      case 'War':
      case 'Documentary':
      case 'Doc':
        return 'Oswald';
      default:
        return 'NotoSerif';
    }
  }

  /// Computes the Geometric Mean Area target dimensions for the Clearlogo
  /// (`tmdb.py:2325-2342` / `render_clean_notch.py:214-227`).
  static Size computeLogoTargetSize({
    required double cardWidth,
    required double cardHeight,
    required double aspectRatio,
    bool isLandscape = false,
  }) {
    final maxW = isLandscape ? cardWidth * 0.62 : cardWidth * 0.75;
    final maxH = isLandscape
        ? cardHeight * 0.26
        : math.min(cardHeight * 0.20, 170.0 * (cardHeight / 750.0));
    final safeAspect = aspectRatio.clamp(0.25, 12.0);
    final target = math.sqrt(maxW * maxH);
    var newW = target * math.sqrt(safeAspect);
    var newH = target / math.sqrt(safeAspect);

    if (newW > maxW) {
      newH *= maxW / newW;
      newW = maxW;
    }
    if (newH > maxH) {
      newW *= maxH / newH;
      newH = maxH;
    }
    return Size(math.max(1.0, newW), math.max(1.0, newH));
  }

  /// Executes the full 3-pass Clean Notch bottom vignette pipeline on [rawImage]
  /// and caches the resulting [ProcessedCleanNotchPoster] by [cacheKey].
  static Future<ProcessedCleanNotchPoster?> processPoster({
    required String cacheKey,
    required ui.Image rawImage,
    bool isLandscape = false,
  }) {
    final w = isLandscape ? canvasLandscapeWidth : canvasWidth;
    final h = isLandscape ? canvasLandscapeHeight : canvasHeight;
    final alignment =
        isLandscape ? const Alignment(0, -0.15) : const Alignment(0, -0.2);
    return _processCachedPoster(
      cacheKey: cacheKey,
      rawImage: rawImage,
      targetWidth: w,
      targetHeight: h,
      alignment: alignment,
      isLandscape: isLandscape,
      filterQuality: FilterQuality.low,
    );
  }

  /// Runs the exact same 3-pass Clean Notch Tall/Landscape poster pipeline on
  /// [rawImage] cropped to the Hero card's aspect ratio so the Hero card blends
  /// identically into its dominant-color bottom section with zero separate overlay sheet.
  static Future<ProcessedCleanNotchPoster?> processHeroPoster({
    required String cacheKey,
    required ui.Image rawImage,
    required double aspectRatio,
  }) {
    final safeAspect = aspectRatio.isFinite ? aspectRatio.clamp(0.4, 2.0) : 0.67;
    final targetW = math.min(rawImage.width, heroCanvasWidth).clamp(240, heroCanvasWidth);
    final targetH = (targetW / safeAspect).round().clamp(160, 810);
    return _processCachedPoster(
      cacheKey: cacheKey,
      rawImage: rawImage,
      targetWidth: targetW,
      targetHeight: targetH,
      alignment: Alignment.center,
      isLandscape: safeAspect >= 1.1,
      filterQuality: FilterQuality.medium,
    );
  }

  static Future<ProcessedCleanNotchPoster?> _processCachedPoster({
    required String cacheKey,
    required ui.Image rawImage,
    required int targetWidth,
    required int targetHeight,
    required Alignment alignment,
    required bool isLandscape,
    required FilterQuality filterQuality,
  }) {
    final cached = _posterCache[cacheKey];
    if (cached != null) return Future.value(cached);

    return _inflightPosters.putIfAbsent(cacheKey, () async {
      final cloned = rawImage.clone();
      try {
        final result = await _enqueueTask(
          () => _runPosterPipeline(
            cloned,
            targetWidth: targetWidth,
            targetHeight: targetHeight,
            alignment: alignment,
            isLandscape: isLandscape,
            filterQuality: filterQuality,
          ),
        );
        if (result != null) {
          if (_posterCache.length >= 160) {
            _posterCache.remove(_posterCache.keys.first);
          }
          _posterCache[cacheKey] = result;
        }
        return result;
      } catch (_) {
        return null;
      } finally {
        cloned.dispose();
        _inflightPosters.remove(cacheKey);
      }
    });
  }

  static Future<Uint8List?> _rasterizeCroppedRgba(
    ui.Image srcImage,
    int w,
    int h, {
    Alignment alignment = Alignment.center,
    FilterQuality filterQuality = FilterQuality.low,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final srcSize = Size(srcImage.width.toDouble(), srcImage.height.toDouble());
    final dstRect = Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
    final fitted = applyBoxFit(BoxFit.cover, srcSize, dstRect.size);
    final srcRect = alignment.inscribe(
      fitted.source,
      Offset.zero & srcSize,
    );
    canvas.drawImageRect(
      srcImage,
      srcRect,
      dstRect,
      Paint()..filterQuality = filterQuality,
    );
    final picture = recorder.endRecording();
    final normImage = await picture.toImage(w, h);
    final byteData = await normImage.toByteData(format: ui.ImageByteFormat.rawRgba);
    normImage.dispose();
    if (byteData == null) return null;
    return Uint8List.fromList(byteData.buffer.asUint8List());
  }

  static Future<ProcessedCleanNotchPoster?> _runPosterPipeline(
    ui.Image srcImage, {
    required int targetWidth,
    required int targetHeight,
    required Alignment alignment,
    required bool isLandscape,
    required FilterQuality filterQuality,
  }) async {
    // 1. Normalise canvas to target aspect & alignment.
    final rawBytes = await _rasterizeCroppedRgba(
      srcImage,
      targetWidth,
      targetHeight,
      alignment: alignment,
      filterQuality: filterQuality,
    );
    if (rawBytes == null) return null;

    // 2. Run the entire 3-pass CPU pixel pipeline on a background worker isolate
    // so zero pixel loops execute on the main UI thread during scroll.
    final (outPixels, bgR, bgG, bgB, bgLum, notchR, notchG, notchB, inkIsDark) =
        await Isolate.run(
      () => _processPosterBytesIsolate(
        rawBytes,
        targetWidth,
        targetHeight,
        isLandscape,
      ),
    );

    final outImage = await _decodePixelsToImage(outPixels, targetWidth, targetHeight);
    return ProcessedCleanNotchPoster(
      image: outImage,
      bgR: bgR,
      bgG: bgG,
      bgB: bgB,
      bgLum: bgLum,
      notchColor: Color.fromARGB(216, notchR, notchG, notchB),
      notchInkColor:
          inkIsDark ? const Color(0xF20A0C10) : const Color(0xF5EEEEF0),
    );
  }

  static (Uint8List, double, double, double, double, int, int, int, bool)
      _processPosterBytesIsolate(
    Uint8List pixels,
    int w,
    int h,
    bool isLandscape,
  ) {
    // 2. Extract Dominant Hue via 36-bin Chroma-Weighted Hue Histogram (64x64 box average).
    final (centreHue, conf) = _extractDominantHue(pixels, w, h);
    final (notchR, notchG, notchB, inkIsDark) = _computeFrostedNotchTint(centreHue, conf);

    // 3. Precompute Power-1.5 Alpha LUT & Normalized Frost Mask.
    final bandRatio = isLandscape ? landscapeBottomHeightRatio : bottomHeightRatio;
    final peakAlpha = isLandscape ? landscapeMaxAlpha : maxAlpha;
    final bottomHeight = math.max(1, (h * bandRatio).round());
    final bottomStart = h - bottomHeight;
    final easedBot = Uint8List(bottomHeight);
    final frostMask = Uint8List(bottomHeight);
    final denom = math.max(1, bottomHeight - 1).toDouble();

    for (var y = 0; y < bottomHeight; y++) {
      final t = y / denom;
      final eased = ((1.0 - math.pow(1.0 - t, bottomGradientCurve)) * peakAlpha)
          .round()
          .clamp(0, 255);
      easedBot[y] = eased;
      frostMask[y] = ((eased * 255.0) / peakAlpha).round().clamp(0, 255);
    }

    // 4. Pass 1: Feathered Artwork Frosting (_vignette_frost_band).
    _applyFrostBlur(
      pixels: pixels,
      width: w,
      height: h,
      bottomStart: bottomStart,
      bottomHeight: bottomHeight,
      frostMask: frostMask,
    );

    // 5. Pass 2: Luminance Levelling (_vignette_level_band).
    _applyLuminanceLevelling(
      pixels: pixels,
      width: w,
      bottomStart: bottomStart,
      bottomHeight: bottomHeight,
      easedBot: easedBot,
      frostMask: frostMask,
    );

    // 6. Pass 3: Chromatic Tint Overlay with CIELAB C* Clamping (_vignette_tint_band).
    final (tintR, tintG, tintB) = _computeChromaticTint(centreHue, conf);
    for (var y = 0; y < bottomHeight; y++) {
      final alpha = easedBot[y] / 255.0;
      final invAlpha = 1.0 - alpha;
      final rowOffset = (bottomStart + y) * w * 4;
      for (var x = 0; x < w; x++) {
        final idx = rowOffset + x * 4;
        pixels[idx] = (pixels[idx] * invAlpha + tintR * alpha).round().clamp(0, 255);
        pixels[idx + 1] = (pixels[idx + 1] * invAlpha + tintG * alpha).round().clamp(0, 255);
        pixels[idx + 2] = (pixels[idx + 2] * invAlpha + tintB * alpha).round().clamp(0, 255);
      }
    }

    // 7. Measure background RGB & luminance in the Clearlogo zone
    // for Background-Aware Contrast Rescue.
    final logoY1 = (h * (isLandscape ? 0.52 : 0.59)).round().clamp(0, h - 1);
    final logoY2 = (h * 0.79).round().clamp(logoY1 + 1, h);
    final logoX1 = (w * (isLandscape ? 0.19 : 0.125)).round().clamp(0, w - 1);
    final logoX2 = (w * (isLandscape ? 0.81 : 0.875)).round().clamp(logoX1 + 1, w);
    var sumR = 0.0;
    var sumG = 0.0;
    var sumB = 0.0;
    var count = 0;
    for (var y = logoY1; y < logoY2; y += 2) {
      final rowOff = y * w * 4;
      for (var x = logoX1; x < logoX2; x += 2) {
        final idx = rowOff + x * 4;
        sumR += pixels[idx];
        sumG += pixels[idx + 1];
        sumB += pixels[idx + 2];
        count++;
      }
    }
    final bgR = count > 0 ? sumR / count : 16.0;
    final bgG = count > 0 ? sumG / count : 20.0;
    final bgB = count > 0 ? sumB / count : 30.0;
    final bgLum = (0.2126 * bgR + 0.7152 * bgG + 0.0722 * bgB) / 255.0;

    return (pixels, bgR, bgG, bgB, bgLum, notchR, notchG, notchB, inkIsDark);
  }

  /// Pass 3A: 36-bin Chroma-Weighted Hue Histogram verbatim from `render_clean_notch.py:74-104`.
  static (double, double) _extractDominantHue(Uint8List pixels, int width, int height) {
    const grid = 64;
    final hist = Float64List(36);

    for (var gy = 0; gy < grid; gy++) {
      final y0 = (gy * height) ~/ grid;
      final y1 = math.max(y0 + 1, ((gy + 1) * height) ~/ grid);
      for (var gx = 0; gx < grid; gx++) {
        final x0 = (gx * width) ~/ grid;
        final x1 = math.max(x0 + 1, ((gx + 1) * width) ~/ grid);

        var rSum = 0;
        var gSum = 0;
        var bSum = 0;
        var cnt = 0;
        for (var y = y0; y < y1; y++) {
          final rowOff = y * width * 4;
          for (var x = x0; x < x1; x++) {
            final idx = rowOff + x * 4;
            rSum += pixels[idx];
            gSum += pixels[idx + 1];
            bSum += pixels[idx + 2];
            cnt++;
          }
        }
        final inv = 1.0 / (cnt * 255.0);
        final r = rSum * inv;
        final g = gSum * inv;
        final b = bSum * inv;

        final maxc = math.max(r, math.max(g, b));
        final minc = math.min(r, math.min(g, b));
        final chroma = maxc - minc;
        final safe = math.max(chroma, 1e-6);

        double hue;
        if (chroma <= 1e-6) {
          hue = 0.0;
        } else if (maxc == r) {
          var h6 = (g - b) / safe;
          h6 = h6 - (h6 / 6.0).floorToDouble() * 6.0;
          if (h6 < 0) h6 += 6.0;
          hue = h6 / 6.0;
        } else if (maxc == g) {
          hue = ((b - r) / safe + 2.0) / 6.0;
        } else {
          hue = ((r - g) / safe + 4.0) / 6.0;
        }
        if (hue < 0.0) hue += 1.0;
        if (hue >= 1.0) hue -= 1.0;

        final sat = maxc > 0.0 ? chroma / math.max(maxc, 1e-6) : 0.0;

        // Skin tone & shadow noise gates
        final isSkin = (r > g) &&
            (g > b) &&
            (hue >= 0.015) &&
            (hue <= 0.11) &&
            (sat >= 0.20) &&
            (sat <= 0.68) &&
            (maxc >= 0.35);
        final darkGate = ((maxc - 0.06) / (0.16 - 0.06)).clamp(0.0, 1.0);
        final weight = chroma * (isSkin ? 0.5 : 1.0) * darkGate;

        final bin = (hue * 36.0).floor().clamp(0, 35);
        hist[bin] += weight / (grid * grid);
      }
    }

    final support = Float64List(36);
    for (var b = 0; b < 36; b++) {
      var s = 0.0;
      for (var off = -3; off <= 3; off++) {
        final idx = (b + off + 36) % 36;
        s += (1.0 - off.abs() / 4.0) * hist[idx];
      }
      support[b] = s;
    }

    var peak = 0;
    var peakVal = support[0];
    for (var b = 1; b < 36; b++) {
      if (support[b] > peakVal) {
        peakVal = support[b];
        peak = b;
      }
    }

    final conf = ((peakVal - 0.006) / (0.028 - 0.006)).clamp(0.0, 1.0);
    final centreHue = (peak + 0.5) / 36.0;
    return (centreHue, conf);
  }

  /// Pass 1: Feathered Artwork Frosting verbatim from `render_clean_notch.py:136-150`.
  static void _applyFrostBlur({
    required Uint8List pixels,
    required int width,
    required int height,
    required int bottomStart,
    required int bottomHeight,
    required Uint8List frostMask,
  }) {
    final radius = math.min(width, height) * 0.24 * vignetteBlur;
    final shrink = math.max(1, (radius / 4.0).floor());
    final smallW = math.max(2, width ~/ shrink);
    final smallH = math.max(2, bottomHeight ~/ shrink);

    // 1. Box-downsample bottom band into smallW x smallH.
    final smallR = Float32List(smallW * smallH);
    final smallG = Float32List(smallW * smallH);
    final smallB = Float32List(smallW * smallH);

    for (var sy = 0; sy < smallH; sy++) {
      final y0 = bottomStart + (sy * bottomHeight) ~/ smallH;
      final y1 = math.max(y0 + 1, bottomStart + ((sy + 1) * bottomHeight) ~/ smallH);
      for (var sx = 0; sx < smallW; sx++) {
        final x0 = (sx * width) ~/ smallW;
        final x1 = math.max(x0 + 1, ((sx + 1) * width) ~/ smallW);
        var rSum = 0;
        var gSum = 0;
        var bSum = 0;
        var cnt = 0;
        for (var y = y0; y < y1; y++) {
          final rowOff = y * width * 4;
          for (var x = x0; x < x1; x++) {
            final idx = rowOff + x * 4;
            rSum += pixels[idx];
            gSum += pixels[idx + 1];
            bSum += pixels[idx + 2];
            cnt++;
          }
        }
        final sIdx = sy * smallW + sx;
        smallR[sIdx] = rSum / cnt;
        smallG[sIdx] = gSum / cnt;
        smallB[sIdx] = bSum / cnt;
      }
    }

    // 2. Separable Gaussian blur with sigma = radius / shrink (~4.0 px).
    final sigma = math.max(0.8, radius / shrink);
    final kRadius = (sigma * 3.0).ceil();
    final kernel = Float32List(kRadius * 2 + 1);
    var kSum = 0.0;
    for (var i = -kRadius; i <= kRadius; i++) {
      final w = math.exp(-(i * i) / (2.0 * sigma * sigma));
      kernel[i + kRadius] = w;
      kSum += w;
    }
    for (var i = 0; i < kernel.length; i++) {
      kernel[i] /= kSum;
    }

    final tmpR = Float32List(smallW * smallH);
    final tmpG = Float32List(smallW * smallH);
    final tmpB = Float32List(smallW * smallH);

    // Horizontal pass
    for (var y = 0; y < smallH; y++) {
      final rowOff = y * smallW;
      for (var x = 0; x < smallW; x++) {
        var rAcc = 0.0;
        var gAcc = 0.0;
        var bAcc = 0.0;
        for (var k = -kRadius; k <= kRadius; k++) {
          final cx = (x + k).clamp(0, smallW - 1);
          final kw = kernel[k + kRadius];
          final idx = rowOff + cx;
          rAcc += smallR[idx] * kw;
          gAcc += smallG[idx] * kw;
          bAcc += smallB[idx] * kw;
        }
        final outIdx = rowOff + x;
        tmpR[outIdx] = rAcc;
        tmpG[outIdx] = gAcc;
        tmpB[outIdx] = bAcc;
      }
    }

    // Vertical pass
    for (var y = 0; y < smallH; y++) {
      for (var x = 0; x < smallW; x++) {
        var rAcc = 0.0;
        var gAcc = 0.0;
        var bAcc = 0.0;
        for (var k = -kRadius; k <= kRadius; k++) {
          final cy = (y + k).clamp(0, smallH - 1);
          final kw = kernel[k + kRadius];
          final idx = cy * smallW + x;
          rAcc += tmpR[idx] * kw;
          gAcc += tmpG[idx] * kw;
          bAcc += tmpB[idx] * kw;
        }
        final outIdx = y * smallW + x;
        smallR[outIdx] = rAcc;
        smallG[outIdx] = gAcc;
        smallB[outIdx] = bAcc;
      }
    }

    // 3. Fast 4-tap bilinear upsample back to (width x bottomHeight) and composite with frostMask.
    for (var y = 0; y < bottomHeight; y++) {
      final maskA = frostMask[y];
      if (maskA == 0) continue;
      final alpha = maskA / 255.0;
      final invAlpha = 1.0 - alpha;

      final fy = ((y + 0.5) * smallH / bottomHeight) - 0.5;
      final iy = fy.floor();
      final ty = fy - iy;
      final ity = 1.0 - ty;
      final y0 = iy.clamp(0, smallH - 1) * smallW;
      final y1 = (iy + 1).clamp(0, smallH - 1) * smallW;

      final rowOff = (bottomStart + y) * width * 4;
      for (var x = 0; x < width; x++) {
        final fx = ((x + 0.5) * smallW / width) - 0.5;
        final ix = fx.floor();
        final tx = fx - ix;
        final itx = 1.0 - tx;

        final x0 = ix.clamp(0, smallW - 1);
        final x1 = (ix + 1).clamp(0, smallW - 1);

        final w00 = itx * ity;
        final w10 = tx * ity;
        final w01 = itx * ty;
        final w11 = tx * ty;

        final i00 = y0 + x0;
        final i10 = y0 + x1;
        final i01 = y1 + x0;
        final i11 = y1 + x1;

        final bR = smallR[i00] * w00 + smallR[i10] * w10 + smallR[i01] * w01 + smallR[i11] * w11;
        final bG = smallG[i00] * w00 + smallG[i10] * w10 + smallG[i01] * w01 + smallG[i11] * w11;
        final bB = smallB[i00] * w00 + smallB[i10] * w10 + smallB[i01] * w01 + smallB[i11] * w11;

        final idx = rowOff + x * 4;
        pixels[idx] = (pixels[idx] * invAlpha + bR * alpha).round().clamp(0, 255);
        pixels[idx + 1] = (pixels[idx + 1] * invAlpha + bG * alpha).round().clamp(0, 255);
        pixels[idx + 2] = (pixels[idx + 2] * invAlpha + bB * alpha).round().clamp(0, 255);
      }
    }
  }

  /// Pass 2: Luminance Levelling verbatim from `render_clean_notch.py:151-161`.
  static void _applyLuminanceLevelling({
    required Uint8List pixels,
    required int width,
    required int bottomStart,
    required int bottomHeight,
    required Uint8List easedBot,
    required Uint8List frostMask,
  }) {
    var weightedLumaSum = 0.0;
    var weightSum = 0.0;

    for (var y = 0; y < bottomHeight; y++) {
      final wNorm = easedBot[y] / maxAlpha;
      if (wNorm <= 0) continue;
      final rowOff = (bottomStart + y) * width * 4;
      var rowLuma = 0.0;
      for (var x = 0; x < width; x++) {
        final idx = rowOff + x * 4;
        rowLuma += 0.299 * pixels[idx] + 0.587 * pixels[idx + 1] + 0.114 * pixels[idx + 2];
      }
      weightedLumaSum += rowLuma * wNorm;
      weightSum += width * wNorm;
    }

    final artLuma = weightSum > 1e-6 ? weightedLumaSum / weightSum : 0.0;
    final bleed = (1.0 - maxAlpha / 255.0) * artLuma;

    if (bleed > 3.0) {
      var k = math.max(0.12, 3.0 / bleed);
      final sliderAmount = math.min(1.0, math.max(vignetteSaturation / 3.0, vignetteBlur));
      k = 1.0 - (1.0 - k) * sliderAmount;

      for (var y = 0; y < bottomHeight; y++) {
        final maskA = frostMask[y];
        if (maskA == 0) continue;
        final alpha = maskA / 255.0;
        final invAlpha = 1.0 - alpha;
        final rowOff = (bottomStart + y) * width * 4;
        for (var x = 0; x < width; x++) {
          final idx = rowOff + x * 4;
          final r = pixels[idx];
          final g = pixels[idx + 1];
          final b = pixels[idx + 2];
          pixels[idx] = (r * invAlpha + (r * k) * alpha).round().clamp(0, 255);
          pixels[idx + 1] = (g * invAlpha + (g * k) * alpha).round().clamp(0, 255);
          pixels[idx + 2] = (b * invAlpha + (b * k) * alpha).round().clamp(0, 255);
        }
      }
    }
  }

  /// Pass 3B: Chromatic Tint with 0.40 Luma Equalization & CIELAB C* Clamping
  /// verbatim from `render_clean_notch.py:163-189`.
  static (int, int, int) _computeChromaticTint(double centreHue, double conf) {
    final fullRgb = _hsvToRgb(centreHue, 1.0, 1.0);
    final hueLuma = math.max(
      0.299 * fullRgb.$1 + 0.587 * fullRgb.$2 + 0.114 * fullRgb.$3,
      1e-6,
    );
    final hueRatio = 0.40 / hueLuma;
    final vScale = math.sqrt(hueRatio);
    final sScale = math.sqrt(math.min(1.0, hueRatio));

    final strength = math.min(1.0, vignetteSaturation / 3.0) * conf;
    final sEff = 1.0 * strength * sScale;
    final vEff = math.min(
      1.0,
      0.38 * strength * vScale * vignetteLightness.clamp(0.4, 2.5),
    );

    var tr = 255.0 * vEff * (1.0 - sEff * (1.0 - fullRgb.$1));
    var tg = 255.0 * vEff * (1.0 - sEff * (1.0 - fullRgb.$2));
    var tb = 255.0 * vEff * (1.0 - sEff * (1.0 - fullRgb.$3));

    // CIELAB C* Chroma Clamping
    double srgbToLin(double c255) {
      final c = (c255 / 255.0).clamp(0.0, 1.0);
      return c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    }

    final rLin = srgbToLin(tr);
    final gLin = srgbToLin(tg);
    final bLin = srgbToLin(tb);

    final x = (0.4124 * rLin + 0.3576 * gLin + 0.1805 * bLin) / 0.95047;
    final y = (0.2126 * rLin + 0.7152 * gLin + 0.0722 * bLin) / 1.00000;
    final z = (0.0193 * rLin + 0.1192 * gLin + 0.9505 * bLin) / 1.08883;

    double labF(double t) =>
        t > 0.008856 ? math.pow(t, 1.0 / 3.0).toDouble() : (7.787 * t + 16.0 / 116.0);

    final fx = labF(x);
    final fy = labF(y);
    final fz = labF(z);

    final aStar = 500.0 * (fx - fy);
    final bStar = 200.0 * (fy - fz);
    final chromaVal = math.sqrt(aStar * aStar + bStar * bStar);

    final ceiling = 27.0 * strength;
    if (chromaVal > ceiling && chromaVal > 0.0) {
      final grey = 0.299 * tr + 0.587 * tg + 0.114 * tb;
      final ratio = ceiling / chromaVal;
      tr = grey + (tr - grey) * ratio;
      tg = grey + (tg - grey) * ratio;
      tb = grey + (tb - grey) * ratio;
    }

    return (
      tr.round().clamp(0, 255),
      tg.round().clamp(0, 255),
      tb.round().clamp(0, 255),
    );
  }

  /// Frosted Reference Tint for the Top Center Notch (`awards.py:1888-1968` & `render_clean_notch.py:351-372`):
  /// Uses `frost_saturation = 1.2`, `frost_reference = true` (`v = 0.88`, `_FLOOR = 0.62` luma),
  /// and `_frost_ink` (`#0A0C10` dark ink when luma >= 0.45, else `#EEEEF0` light ink).
  static (int, int, int, bool) _computeFrostedNotchTint(double centreHue, double conf) {
    const frostSaturation = 1.2;
    const v = 0.88;
    final sEff = math.min(1.0, 0.72 * frostSaturation) * conf;
    var (r, g, b) = _hsvToRgb(centreHue, sEff, v);
    final lum0 = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    const floorLuma = 0.62;
    if (lum0 < floorLuma && lum0 < 1.0) {
      final lift = (floorLuma - lum0) / (1.0 - lum0);
      r = r + (1.0 - r) * lift;
      g = g + (1.0 - g) * lift;
      b = b + (1.0 - b) * lift;
    }
    final lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
    final inkIsDark = lum >= 0.45;
    return (
      (r * 255.0).round().clamp(0, 255),
      (g * 255.0).round().clamp(0, 255),
      (b * 255.0).round().clamp(0, 255),
      inkIsDark,
    );
  }

  static (double, double, double) _hsvToRgb(double h, double s, double v) {
    if (s <= 0.0) return (v, v, v);
    final hh = (h - h.floorToDouble()) * 6.0;
    final i = hh.floor();
    final ff = hh - i;
    final p = v * (1.0 - s);
    final q = v * (1.0 - (s * ff));
    final t = v * (1.0 - (s * (1.0 - ff)));
    switch (i % 6) {
      case 0:
        return (v, t, p);
      case 1:
        return (q, v, p);
      case 2:
        return (p, v, t);
      case 3:
        return (p, q, v);
      case 4:
        return (t, p, v);
      default:
        return (v, p, q);
    }
  }

  /// Processes a Clearlogo (`composite_logo` in `render_clean_notch.py:194-278`):
  /// 1. Alpha-trims transparent padding at threshold `alpha > 32`
  /// 2. Evaluates Euclidean color distance & luminance against the underlying
  ///    poster vignette (`bgR, bgG, bgB, bgLum`) and auto-whitens dark-on-dark logos.
  static Future<ProcessedCleanNotchLogo?> processLogo({
    required String cacheKey,
    required ui.Image rawLogo,
    double bgR = 16.0,
    double bgG = 20.0,
    double bgB = 30.0,
    double bgLum = 0.08,
  }) {
    final cached = _logoCache[cacheKey];
    if (cached != null) return Future.value(cached);

    return _inflightLogos.putIfAbsent(cacheKey, () async {
      try {
        final result = await _enqueueTask(
          () => _runLogoPipeline(
            rawLogo,
            bgR: bgR,
            bgG: bgG,
            bgB: bgB,
            bgLum: bgLum,
          ),
        );
        if (result != null) {
          if (_logoCache.length >= 160) {
            _logoCache.remove(_logoCache.keys.first);
          }
          _logoCache[cacheKey] = result;
        }
        return result;
      } catch (_) {
        return null;
      } finally {
        _inflightLogos.remove(cacheKey);
      }
    });
  }

  static Future<ProcessedCleanNotchLogo?> _runLogoPipeline(
    ui.Image srcLogo, {
    required double bgR,
    required double bgG,
    required double bgB,
    required double bgLum,
  }) async {
    final w = srcLogo.width;
    final h = srcLogo.height;
    if (w <= 0 || h <= 0) return null;

    final byteData = await srcLogo.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) return null;
    final rgba = Uint8List.fromList(byteData.buffer.asUint8List());

    final (cropped, cropW, cropH) = await Isolate.run(
      () => _processLogoBytesIsolate(rgba, w, h, bgR, bgG, bgB, bgLum),
    );

    final outImage = await _decodePixelsToImage(cropped, cropW, cropH);
    return ProcessedCleanNotchLogo(
      image: outImage,
      aspectRatio: cropW / cropH,
    );
  }

  static (Uint8List, int, int) _processLogoBytesIsolate(
    Uint8List rgba,
    int w,
    int h,
    double bgR,
    double bgG,
    double bgB,
    double bgLum,
  ) {
    // 1. Alpha trimming > 32 (fallback > 0)
    var minX = w;
    var minY = h;
    var maxX = -1;
    var maxY = -1;

    for (var y = 0; y < h; y++) {
      final rowOff = y * w * 4;
      for (var x = 0; x < w; x++) {
        final a = rgba[rowOff + x * 4 + 3];
        if (a > 32) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }

    if (maxX < minX || maxY < minY) {
      minX = 0;
      minY = 0;
      maxX = w - 1;
      maxY = h - 1;
    }

    final cropW = maxX - minX + 1;
    final cropH = maxY - minY + 1;
    final cropped = Uint8List(cropW * cropH * 4);

    var visSumR = 0.0;
    var visSumG = 0.0;
    var visSumB = 0.0;
    var visCount = 0;

    var solidCount = 0;
    var solidBrightCount = 0;
    var solidLumSum = 0.0;

    for (var cy = 0; cy < cropH; cy++) {
      final srcRow = (minY + cy) * w * 4;
      final dstRow = cy * cropW * 4;
      for (var cx = 0; cx < cropW; cx++) {
        final sIdx = srcRow + (minX + cx) * 4;
        final dIdx = dstRow + cx * 4;
        final r = rgba[sIdx];
        final g = rgba[sIdx + 1];
        final b = rgba[sIdx + 2];
        final a = rgba[sIdx + 3];
        cropped[dIdx] = r;
        cropped[dIdx + 1] = g;
        cropped[dIdx + 2] = b;
        cropped[dIdx + 3] = a;

        if (a > 64) {
          visSumR += r;
          visSumG += g;
          visSumB += b;
          visCount++;
        }
        if (a >= 128) {
          final lum = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;
          solidLumSum += lum;
          solidCount++;
          if (lum >= 0.60) solidBrightCount++;
        }
      }
    }

    // 2. Background-Aware Contrast Rescue (render_clean_notch.py:239-277)
    if (visCount > 0) {
      final meanR = visSumR / visCount;
      final meanG = visSumG / visCount;
      final meanB = visSumB / visCount;

      var varSum = 0.0;
      for (var i = 0; i < cropped.length; i += 4) {
        if (cropped[i + 3] > 64) {
          final dr = cropped[i] - meanR;
          final dg = cropped[i + 1] - meanG;
          final db = cropped[i + 2] - meanB;
          varSum += math.sqrt(dr * dr + dg * dg + db * db);
        }
      }
      final variance = (varSum / visCount) / 441.673;
      final dist = math.sqrt(
            (meanR - bgR) * (meanR - bgR) +
                (meanG - bgG) * (meanG - bgG) +
                (meanB - bgB) * (meanB - bgB),
          ) /
          441.673;

      var shouldRecolor = false;
      var targetColor = 255;

      if (dist < 0.25 && variance <= 0.16) {
        shouldRecolor = true;
        targetColor = bgLum > 0.66 ? 20 : 255;
      } else if (bgLum < 0.40 && solidCount > 0) {
        final brightRatio = solidBrightCount / solidCount;
        final meanLum = solidLumSum / solidCount;
        if (brightRatio < 0.05 && meanLum <= 0.20) {
          shouldRecolor = true;
          targetColor = 255;
        }
      }

      if (shouldRecolor) {
        for (var i = 0; i < cropped.length; i += 4) {
          if (cropped[i + 3] > 30) {
            cropped[i] = targetColor;
            cropped[i + 1] = targetColor;
            cropped[i + 2] = targetColor;
          }
        }
      }
    }

    return (cropped, cropW, cropH);
  }

  static Future<ui.Image> _decodePixelsToImage(
    Uint8List rgba,
    int width,
    int height,
  ) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }
}
