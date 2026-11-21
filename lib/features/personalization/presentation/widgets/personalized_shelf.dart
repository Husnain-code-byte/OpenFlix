import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';

import '../../../../core/perf/image_perf.dart';
import '../../../../core/perf/snap_physics.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/responsive.dart';
import '../../../home/data/models/meta_model.dart';
import '../../../home/presentation/controllers/home_controller.dart';
import '../../../home/presentation/widgets/pixel_bottom_nav.dart';
import '../../../home/presentation/widgets/poster_card.dart';
import '../../data/personalized_slots.dart';
import 'clean_notch_engine.dart';

/// Renders a single personalized recommendation shelf (`"Because you liked <Title>"`
/// in [PersonalizedRowStyle.tall] or `"Because you added <Title> to your list"` in
/// [PersonalizedRowStyle.landscape]), with identical row heading typography
/// ([AppText.rowHeading]), `10px` heading gap ([AppDimens.rowGap]), `8px` poster
/// gap ([AppDimens.posterGap]), and `12px` bottom spacing ([AppDimens.rowSpacing])
/// as all other rows.
class PersonalizedShelf extends StatefulWidget {
  const PersonalizedShelf({
    super.key,
    required this.row,
    required this.onTapMeta,
    double? inset,
  }) : _inset = inset;

  final PersonalizedRowData row;
  final ValueChanged<MetaModel> onTapMeta;
  final double? _inset;

  double get inset => _inset ?? AppDimens.screenPadding;

  @override
  State<PersonalizedShelf> createState() => _PersonalizedShelfState();
}

class _PersonalizedShelfState extends State<PersonalizedShelf> {
  final ScrollController _scrollController = ScrollController();
  ProviderSubscription<PixelTab>? _tabSub;
  ProviderSubscription<HomeFilter>? _filterSub;

  void _resetScroll() {
    if (_scrollController.hasClients && _scrollController.offset != 0.0) {
      _scrollController.jumpTo(0.0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_tabSub == null && _filterSub == null) {
      try {
        final container = ProviderScope.containerOf(context, listen: false);
        _tabSub = container.listen<PixelTab>(
          activeTabProvider,
          (prev, next) {
            if (prev != null && prev != next) _resetScroll();
          },
        );
        _filterSub = container.listen<HomeFilter>(
          homeFilterProvider,
          (prev, next) {
            if (prev != null && prev != next) _resetScroll();
          },
        );
      } catch (_) {
        // Standalone widget test without a ProviderScope ancestor.
      }
    }
  }

  @override
  void didUpdateWidget(covariant PersonalizedShelf oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.row.bucket != widget.row.bucket ||
        oldWidget.row.sourceMeta.id != widget.row.sourceMeta.id) {
      _resetScroll();
    }
  }

  @override
  void dispose() {
    _tabSub?.close();
    _filterSub?.close();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);
    final row = widget.row;
    final inset = widget.inset;
    final onTapMeta = widget.onTapMeta;

    if (row.isLoading && row.items.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(bottom: AppDimens.rowSpacing),
        child: _PersonalizedRowSkeleton(
          title: row.title,
          style: row.style,
          inset: inset,
        ),
      );
    }

    if (row.items.isEmpty) {
      return const SizedBox.shrink();
    }

    final stride = AppDimens.posterStride;
    final shadowPad = 12.h;

    return Padding(
      padding: EdgeInsets.only(bottom: AppDimens.rowSpacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: inset),
            child: Text(
              row.title,
              style: AppText.rowHeading,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(height: AppDimens.rowGap),
          SizedBox(
            // +12.h leaves room below the standard posters for their 0 8 20 shadow.
            height: AppDimens.posterHeight + shadowPad,
            child: ListView.builder(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              physics: PosterSnapPhysics(itemExtent: stride),
              itemExtent: stride,
              padding: EdgeInsets.fromLTRB(inset, 0, inset, shadowPad),
              addAutomaticKeepAlives: false,
              addSemanticIndexes: false,
              cacheExtent: stride * 2,
              itemCount: row.items.length,
              itemBuilder: (_, i) {
                final meta = row.items[i];
                return Padding(
                  padding: EdgeInsets.only(right: AppDimens.posterGap),
                  child: PosterCard(meta: meta, onTap: onTapMeta),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// PostersPlus `clean_notch` Tall Card (`176 × 328`):
/// 1. **Base Textless Artwork (`iso_639_1 == null`)**: Fitted with `BoxFit.cover` and
///    `Alignment(0, -0.2)` (head-safe upper-center crop).
/// 2. **3-Pass Frosted Blur & Chromatic Vignette (`CleanNotchEngine`)**:
///    - Pass 1: Feathered Artwork Frosting (`W * 0.24` Gaussian blur over bottom 50%
///      masked by normalized power-1.5 LUT).
///    - Pass 2: Luminance Levelling (`bleed > 3.0` budget dimming).
///    - Pass 3: 36-bin Chroma-Weighted Hue Histogram (`0.40` reference luma equalization +
///      CIELAB `C* <= 27.0` clamping) composited with `max_alpha = 225` (`88.2%`).
/// 3. **Clearlogo / Genre-Aware Fallback Title**:
///    - Alpha-trimmed (`alpha > 32`), sized via Geometric Mean Area (`maxW = W * 0.75`,
///      `maxH = min(H * 0.20, 170 * H / 750)`), contrast-rescued against background
///      luminance, and bottom-pinned at `bottom: H * 0.21` (`68.88 px`).
/// 4. **Clean Metadata Row (`"{Genre} ★ {Score}"`)**:
///    - Optical center `Y = H * 0.910` (`298.48 px`) with `-10%` baseline nudge in
///      `Inter` Bold (`W * 0.090` = `15.84 px`), color `#C8C8C8`.
class PersonalizedTallCard extends StatefulWidget {
  const PersonalizedTallCard({
    super.key,
    required this.meta,
    required this.onTap,
  });

  final MetaModel meta;
  final ValueChanged<MetaModel> onTap;

  static const _shadow = [
    BoxShadow(
      color: Color(0x1A000000),
      blurRadius: 25,
      spreadRadius: -5,
      offset: Offset(0, 20),
    ),
    BoxShadow(
      color: Color(0x1A000000),
      blurRadius: 10,
      spreadRadius: -6,
      offset: Offset(0, 8),
    ),
  ];

  /// Power-1.5 bottom vignette LUT fallback (`max_alpha = 225`) used while the
  /// 3-pass pixel buffer is decoding on first frame.
  static const _fallbackBottomVignette = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0x0010141E),
      Color(0x2810141E),
      Color(0x4E10141E),
      Color(0x7010141E),
      Color(0x8F10141E),
      Color(0xAA10141E),
      Color(0xC210141E),
      Color(0xD410141E),
      Color(0xE110141E),
    ],
    stops: [0.0, 0.125, 0.25, 0.375, 0.50, 0.625, 0.75, 0.875, 1.0],
  );

  @override
  State<PersonalizedTallCard> createState() => _PersonalizedTallCardState();
}

class _PersonalizedTallCardState extends State<PersonalizedTallCard> {
  ProcessedCleanNotchPoster? _processedPoster;
  ui.Image? _rawPosterImage;
  ImageStream? _posterStream;
  ImageStreamListener? _posterListener;
  String? _resolvedPosterUrl;
  int _urlIndex = 0;
  bool _allFailed = false;

  List<String> get _candidateUrls => [
        for (final u in [
          widget.meta.tallPoster,
          widget.meta.poster,
          widget.meta.posterFallback,
        ])
          if (u != null && u.isNotEmpty) u,
      ];

  @override
  void initState() {
    super.initState();
    _syncPosterResolution();
  }

  @override
  void didUpdateWidget(covariant PersonalizedTallCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.meta.id != widget.meta.id ||
        oldWidget.meta.tallPoster != widget.meta.tallPoster ||
        oldWidget.meta.poster != widget.meta.poster) {
      _urlIndex = 0;
      _allFailed = false;
      _rawPosterImage = null;
      _syncPosterResolution();
    }
  }

  @override
  void dispose() {
    _unsubscribePoster();
    super.dispose();
  }

  void _unsubscribePoster() {
    if (_posterStream != null && _posterListener != null) {
      _posterStream!.removeListener(_posterListener!);
    }
    _posterStream = null;
    _posterListener = null;
  }

  void _syncPosterResolution() {
    _unsubscribePoster();
    final urls = _candidateUrls;
    if (_urlIndex >= urls.length) {
      _resolvedPosterUrl = null;
      _processedPoster = null;
      _rawPosterImage = null;
      _allFailed = true;
      return;
    }

    final rawUrl = urls[_urlIndex];
    final sizedUrl = tmdbSized(rawUrl, forWidthPx: CleanNotchEngine.canvasWidth);
    _resolvedPosterUrl = sizedUrl;
    _allFailed = false;

    final cached = CleanNotchEngine.getCachedPoster(sizedUrl);
    if (cached != null) {
      _processedPoster = cached;
      _rawPosterImage = null;
      return;
    }

    _processedPoster = null;
    final provider = CachedNetworkImageProvider(
      sizedUrl,
      cacheManager: PixelImageCache.instance,
      maxHeight: CleanNotchEngine.canvasHeight,
    );
    final stream = provider.resolve(ImageConfiguration.empty);
    _posterStream = stream;
    _posterListener = ImageStreamListener(
      (info, _) async {
        final targetUrl = sizedUrl;
        if (!mounted || _resolvedPosterUrl != targetUrl) return;

        // Render the decoded base image immediately on the first frame while the
        // background isolate computes the 3-pass clean_notch frosted vignette.
        if (_rawPosterImage == null && _processedPoster == null) {
          setState(() {
            _rawPosterImage = info.image;
          });
        }

        final processed = await CleanNotchEngine.processPoster(
          cacheKey: targetUrl,
          rawImage: info.image,
        );
        if (!mounted || _resolvedPosterUrl != targetUrl || processed == null) {
          return;
        }
        setState(() {
          _processedPoster = processed;
        });
      },
      onError: (_, __) {
        if (!mounted) return;
        if (_urlIndex + 1 < _candidateUrls.length) {
          setState(() {
            _urlIndex++;
            _syncPosterResolution();
          });
        } else {
          setState(() {
            _allFailed = true;
          });
        }
      },
    );
    stream.addListener(_posterListener!);
  }

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);
    final cardW = PersonalizedSlots.tallWidth; // 176.w
    final cardH = PersonalizedSlots.tallHeight; // 328.w
    final meta = widget.meta;
    final radius = BorderRadius.circular(PersonalizedSlots.tallRadius);
    final processed = _processedPoster;
    final rawPoster = _rawPosterImage;
    final metadataLabel = CleanNotchEngine.formatCleanMetadataLabel(
      genres: meta.genres,
      rawRating: meta.imdbRating,
    );
    final primaryGenre = CleanNotchEngine.resolvePrimaryGenre(meta.genres);

    return Container(
      width: cardW,
      height: cardH,
      decoration: BoxDecoration(
        borderRadius: radius,
        color: const Color(0xFF12141D),
        boxShadow: PersonalizedTallCard._shadow,
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(
          color: const Color(0x14FFFFFF), // 1px hairline border (rgba 255,255,255,0.08)
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Layer 1 & 2: Base Textless Artwork + 3-Pass Frosted Blur & Chromatic Vignette
            if (processed != null)
              RawImage(
                image: processed.image,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.low,
              )
            else ...[
              if (rawPoster != null)
                RawImage(
                  image: rawPoster,
                  fit: BoxFit.cover,
                  alignment: const Alignment(0, -0.2),
                  filterQuality: FilterQuality.low,
                )
              else if (_allFailed)
                PosterFallback(meta: meta)
              else
                const ColoredBox(color: AppColors.surface2),
              // Zero-cost power-1.5 dark vignette fallback while background isolate computes
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: cardH * CleanNotchEngine.bottomHeightRatio,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: PersonalizedTallCard._fallbackBottomVignette,
                  ),
                ),
              ),
            ],

            // Layer 3: Clearlogo / Genre-Aware Fallback Title pinned to bottom: H * 0.21 (68.88px)
            Positioned(
              left: cardW * 0.125, // 22.0px (12.5% margin -> 75% max width = 132.0px)
              right: cardW * 0.125,
              bottom: cardH * CleanNotchEngine.logoBottomMarginRatio, // 68.88px
              child: _CleanNotchTitleLockup(
                name: meta.name,
                logoUrl: meta.logo,
                logoAspectRatio: meta.logoAspectRatio,
                primaryGenre: primaryGenre,
                bgR: processed?.bgR ?? 16.0,
                bgG: processed?.bgG ?? 20.0,
                bgB: processed?.bgB ?? 30.0,
                bgLum: processed?.bgLum ?? 0.08,
              ),
            ),

            // Layer 4: Clean Metadata Row ("{Genre} ★ {Score}") at optical center Y = H * 0.910
            if (metadataLabel != null && metadataLabel.isNotEmpty)
              _CleanNotchMetadataRow(
                label: metadataLabel,
                cardWidth: cardW,
                cardHeight: cardH,
              ),

            Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.onTap(meta);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// PostersPlus `clean_notch` Landscape Poster Card (`305 × 172` ~16:9):
/// - Step 1: Textless 16:9 backdrop fitted with `BoxFit.cover` and `Alignment(0, -0.15)`
/// - Step 2: 3-Pass Frosted Blur + Luminance Levelling + Dominant-Color Chromatic Vignette
///   (`CleanNotchEngine.processPoster(..., isLandscape: true)`) over the bottom `56%` (`96.3px`)
///   feathered by the Power-1.5 alpha curve so there is zero seam between image and title
/// - Step 3: Horizontally centered Clearlogo / Genre-Aware Fallback Title in the lower-middle
///   section (`bottom: H * 0.215 = 37.0px`, Geometric Mean Area sizing `maxW = 189.1px`, `maxH = 44.7px`)
/// - Step 4: Clean Metadata Row (`"{Genre} ★ {Score}"`) centered underneath at `Y = H * 0.895` (`153.9px`)
///   in `Inter` Semi-Bold (`FontWeight.w600`), `#C8C8C8` silver off-white.
class PersonalizedLandscapeCard extends StatefulWidget {
  const PersonalizedLandscapeCard({
    super.key,
    required this.meta,
    required this.onTap,
  });

  final MetaModel meta;
  final ValueChanged<MetaModel> onTap;

  static const _shadow = [
    BoxShadow(
      color: Color(0x26000000),
      blurRadius: 16,
      spreadRadius: -3,
      offset: Offset(0, 10),
    ),
    BoxShadow(
      color: Color(0x1F000000),
      blurRadius: 6,
      spreadRadius: -4,
      offset: Offset(0, 4),
    ),
  ];

  static const _fallbackBottomVignette = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0x000A0C12), // 0% at top of 56% band
      Color(0x520A0C12), // 25%
      Color(0x9E0A0C12), // 50%
      Color(0xC90A0C12), // 75%
      Color(0xE80A0C12), // 100% (~91% peak alpha)
    ],
    stops: [0.0, 0.25, 0.50, 0.75, 1.0],
  );

  @override
  State<PersonalizedLandscapeCard> createState() =>
      _PersonalizedLandscapeCardState();
}

class _PersonalizedLandscapeCardState extends State<PersonalizedLandscapeCard> {
  String? _resolvedBackdropUrl;
  ProcessedCleanNotchPoster? _processedPoster;
  ui.Image? _rawBackdropImage;
  ImageStream? _backdropStream;
  ImageStreamListener? _backdropListener;
  int _urlIndex = 0;
  bool _allFailed = false;

  List<String> get _candidateUrls => [
        for (final u in [
          widget.meta.landscapePoster,
          widget.meta.background,
          widget.meta.posterFallback,
          widget.meta.poster,
        ])
          if (u != null && u.isNotEmpty) u,
      ];

  @override
  void initState() {
    super.initState();
    _syncBackdropResolution();
  }

  @override
  void didUpdateWidget(covariant PersonalizedLandscapeCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.meta.id != widget.meta.id ||
        oldWidget.meta.landscapePoster != widget.meta.landscapePoster ||
        oldWidget.meta.background != widget.meta.background) {
      _urlIndex = 0;
      _allFailed = false;
      _rawBackdropImage = null;
      _syncBackdropResolution();
    }
  }

  @override
  void dispose() {
    _unsubscribeBackdrop();
    super.dispose();
  }

  void _unsubscribeBackdrop() {
    if (_backdropStream != null && _backdropListener != null) {
      _backdropStream!.removeListener(_backdropListener!);
    }
    _backdropStream = null;
    _backdropListener = null;
  }

  void _syncBackdropResolution() {
    _unsubscribeBackdrop();
    final urls = _candidateUrls;
    if (_urlIndex >= urls.length) {
      _resolvedBackdropUrl = null;
      _processedPoster = null;
      _rawBackdropImage = null;
      _allFailed = true;
      return;
    }

    final rawUrl = urls[_urlIndex];
    final sizedUrl = tmdbSized(
      rawUrl,
      forWidthPx: CleanNotchEngine.canvasLandscapeWidth,
    );
    final cacheKey = 'landscape|$sizedUrl';
    _resolvedBackdropUrl = cacheKey;
    _allFailed = false;

    final cached = CleanNotchEngine.getCachedPoster(cacheKey);
    if (cached != null) {
      _processedPoster = cached;
      _rawBackdropImage = null;
      return;
    }

    _processedPoster = null;
    final provider = CachedNetworkImageProvider(
      sizedUrl,
      cacheManager: PixelImageCache.instance,
      maxWidth: CleanNotchEngine.canvasLandscapeWidth,
    );
    final stream = provider.resolve(ImageConfiguration.empty);
    _backdropStream = stream;
    _backdropListener = ImageStreamListener(
      (info, _) async {
        final targetKey = cacheKey;
        if (!mounted || _resolvedBackdropUrl != targetKey) return;

        if (_rawBackdropImage == null && _processedPoster == null) {
          setState(() {
            _rawBackdropImage = info.image;
          });
        }

        final processed = await CleanNotchEngine.processPoster(
          cacheKey: targetKey,
          rawImage: info.image,
          isLandscape: true,
        );
        if (!mounted || _resolvedBackdropUrl != targetKey || processed == null) {
          return;
        }
        setState(() {
          _processedPoster = processed;
        });
      },
      onError: (_, __) {
        if (!mounted) return;
        if (_urlIndex + 1 < _candidateUrls.length) {
          setState(() {
            _urlIndex++;
            _syncBackdropResolution();
          });
        } else {
          setState(() {
            _allFailed = true;
          });
        }
      },
    );
    stream.addListener(_backdropListener!);
  }

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);
    final cardW = PersonalizedSlots.landscapeWidth; // 305.w
    final cardH = PersonalizedSlots.landscapeHeight; // 172.w
    final meta = widget.meta;
    final radius = BorderRadius.circular(PersonalizedSlots.landscapeRadius);
    final processed = _processedPoster;
    final rawBackdrop = _rawBackdropImage;
    final metadataLabel = CleanNotchEngine.formatCleanMetadataLabel(
      genres: meta.genres,
      rawRating: meta.imdbRating,
    );
    final primaryGenre = CleanNotchEngine.resolvePrimaryGenre(meta.genres);

    return Container(
      width: cardW,
      height: cardH,
      decoration: BoxDecoration(
        borderRadius: radius,
        color: const Color(0xFF12141D),
        boxShadow: PersonalizedLandscapeCard._shadow,
      ),
      foregroundDecoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(
          color: const Color(0x14FFFFFF), // 1px hairline border (rgba 255,255,255,0.08)
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Layer 1 & 2: Base 16:9 Artwork + 3-Pass Frosted Blur & Dominant-Color Vignette
            if (processed != null)
              RawImage(
                image: processed.image,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.low,
              )
            else ...[
              if (rawBackdrop != null)
                RawImage(
                  image: rawBackdrop,
                  fit: BoxFit.cover,
                  alignment: const Alignment(0, -0.15),
                  filterQuality: FilterQuality.low,
                )
              else if (_allFailed)
                PosterFallback(meta: meta)
              else
                const ColoredBox(color: AppColors.surface2),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: cardH * CleanNotchEngine.landscapeBottomHeightRatio,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: PersonalizedLandscapeCard._fallbackBottomVignette,
                  ),
                ),
              ),
            ],

            // Layer 3: Horizontally Centered Stylized Title in the Lower-Middle Section
            Positioned(
              left: cardW * 0.19, // 57.95px margin -> 62% max width (189.1px)
              right: cardW * 0.19,
              bottom: cardH * CleanNotchEngine.landscapeLogoBottomMarginRatio, // 37.0px
              child: _CleanNotchTitleLockup(
                name: meta.name,
                logoUrl: meta.logo,
                logoAspectRatio: meta.logoAspectRatio,
                primaryGenre: primaryGenre,
                bgR: processed?.bgR ?? 16.0,
                bgG: processed?.bgG ?? 20.0,
                bgB: processed?.bgB ?? 30.0,
                bgLum: processed?.bgLum ?? 0.08,
                isLandscape: true,
              ),
            ),

            // Layer 4: Clean Metadata Row ("{Genre} ★ {Score}") Centered Underneath
            if (metadataLabel != null && metadataLabel.isNotEmpty)
              _CleanNotchMetadataRow(
                label: metadataLabel,
                cardWidth: cardW,
                cardHeight: cardH,
                isLandscape: true,
              ),

            // Layer 5: Top-Center Clean Notch Badge (Landscape Only, Where Appropriate)
            if (meta.notchText != null && meta.notchText!.trim().isNotEmpty)
              Positioned(
                top: 0,
                left: 56,
                right: 56,
                child: Align(
                  alignment: Alignment.topCenter,
                  child: _CleanNotchTopBadge(
                    label: meta.notchText!.trim(),
                    backgroundColor: processed?.notchColor ?? const Color(0xD8CED4E0),
                    inkColor: processed?.notchInkColor ?? const Color(0xF20A0C10),
                  ),
                ),
              ),

            Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.onTap(meta);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Step 3 of `clean_notch` (`render_clean_notch.py:194-278`):
/// - Alpha-trims transparent Clearlogo margins (`alpha > 32`)
/// - Scales via Geometric Mean Area (`maxW = W * 0.75 = 132px`, `maxH = min(H * 0.20, 170 * H / 750) = 65.6px` on tall;
///   `maxW = W * 0.62 = 189.1px`, `maxH = H * 0.26 = 44.7px` on landscape)
/// - Performs Background-Aware Contrast Rescue against the frosted poster background (`bgR, bgG, bgB, bgLum`)
/// - Falls back to genre-matched bundled display typography when no logo is present.
class _CleanNotchTitleLockup extends StatefulWidget {
  const _CleanNotchTitleLockup({
    required this.name,
    this.logoUrl,
    this.logoAspectRatio,
    this.primaryGenre,
    required this.bgR,
    required this.bgG,
    required this.bgB,
    required this.bgLum,
    this.isLandscape = false,
  });

  final String name;
  final String? logoUrl;
  final double? logoAspectRatio;
  final String? primaryGenre;
  final double bgR;
  final double bgG;
  final double bgB;
  final double bgLum;
  final bool isLandscape;

  @override
  State<_CleanNotchTitleLockup> createState() => _CleanNotchTitleLockupState();
}

class _CleanNotchTitleLockupState extends State<_CleanNotchTitleLockup> {
  ProcessedCleanNotchLogo? _processedLogo;
  ui.Image? _rawLogoImage;
  ImageStream? _logoStream;
  ImageStreamListener? _logoListener;
  String? _activeKey;
  bool _logoFailed = false;

  @override
  void initState() {
    super.initState();
    _syncLogoResolution();
  }

  @override
  void didUpdateWidget(covariant _CleanNotchTitleLockup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.logoUrl != widget.logoUrl ||
        (oldWidget.bgLum - widget.bgLum).abs() > 0.08) {
      if (oldWidget.logoUrl != widget.logoUrl) {
        _rawLogoImage = null;
      }
      _syncLogoResolution();
    }
  }

  @override
  void dispose() {
    _unsubscribeLogo();
    super.dispose();
  }

  void _unsubscribeLogo() {
    if (_logoStream != null && _logoListener != null) {
      _logoStream!.removeListener(_logoListener!);
    }
    _logoStream = null;
    _logoListener = null;
  }

  void _syncLogoResolution() {
    _unsubscribeLogo();
    final rawUrl = widget.logoUrl;
    if (rawUrl == null || rawUrl.isEmpty) {
      _processedLogo = null;
      _rawLogoImage = null;
      _activeKey = null;
      _logoFailed = false;
      return;
    }

    final sizedUrl = tmdbSized(rawUrl, forWidthPx: 300);
    final lumBucket = (widget.bgLum * 10).round();
    final cacheKey = '$sizedUrl|lum:$lumBucket';
    _activeKey = cacheKey;
    _logoFailed = false;

    final cached = CleanNotchEngine.getCachedLogo(cacheKey);
    if (cached != null) {
      _processedLogo = cached;
      _rawLogoImage = null;
      return;
    }

    final provider = CachedNetworkImageProvider(
      sizedUrl,
      cacheManager: PixelImageCache.instance,
      maxWidth: 342,
    );
    final stream = provider.resolve(ImageConfiguration.empty);
    _logoStream = stream;
    _logoListener = ImageStreamListener(
      (info, _) async {
        final key = cacheKey;
        if (!mounted || _activeKey != key) return;
        if (_rawLogoImage == null && _processedLogo == null) {
          setState(() {
            _rawLogoImage = info.image;
          });
        }
        final processed = await CleanNotchEngine.processLogo(
          cacheKey: key,
          rawLogo: info.image,
          bgR: widget.bgR,
          bgG: widget.bgG,
          bgB: widget.bgB,
          bgLum: widget.bgLum,
        );
        if (!mounted || _activeKey != key) return;
        if (processed == null) {
          setState(() => _logoFailed = true);
          return;
        }
        setState(() {
          _processedLogo = processed;
        });
      },
      onError: (_, __) {
        if (!mounted) return;
        setState(() => _logoFailed = true);
      },
    );
    stream.addListener(_logoListener!);
  }

  @override
  Widget build(BuildContext context) {
    final fallback = _CleanNotchFallbackTitle(
      name: widget.name,
      primaryGenre: widget.primaryGenre,
      isLandscape: widget.isLandscape,
    );

    final rawUrl = widget.logoUrl;
    if (rawUrl == null || rawUrl.isEmpty || _logoFailed) {
      return fallback;
    }

    final cardW = widget.isLandscape
        ? PersonalizedSlots.landscapeWidth
        : PersonalizedSlots.tallWidth;
    final cardH = widget.isLandscape
        ? PersonalizedSlots.landscapeHeight
        : PersonalizedSlots.tallHeight;

    final processed = _processedLogo;
    if (processed != null) {
      final targetSize = CleanNotchEngine.computeLogoTargetSize(
        cardWidth: cardW,
        cardHeight: cardH,
        aspectRatio: processed.aspectRatio,
        isLandscape: widget.isLandscape,
      );
      return Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: targetSize.width,
          height: targetSize.height,
          child: RawImage(
            image: processed.image,
            width: targetSize.width,
            height: targetSize.height,
            fit: BoxFit.contain,
            alignment: Alignment.bottomCenter,
            filterQuality: FilterQuality.low,
          ),
        ),
      );
    }

    final rawLogo = _rawLogoImage;
    if (rawLogo != null) {
      final rawAspect = rawLogo.height > 0
          ? rawLogo.width / rawLogo.height
          : (widget.logoAspectRatio ?? 2.4);
      final initialSize = CleanNotchEngine.computeLogoTargetSize(
        cardWidth: cardW,
        cardHeight: cardH,
        aspectRatio: widget.logoAspectRatio ?? rawAspect,
        isLandscape: widget.isLandscape,
      );
      return Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: initialSize.width,
          height: initialSize.height,
          child: RawImage(
            image: rawLogo,
            width: initialSize.width,
            height: initialSize.height,
            fit: BoxFit.contain,
            alignment: Alignment.bottomCenter,
            filterQuality: FilterQuality.low,
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

/// Genre-aware fallback title renderer verbatim from `render_clean_notch.py:1303-1474`:
/// - Uses bundled `clean_notch` display fonts (`Creepster`, `BebasNeue`, `Pacifico`,
///   `PlayfairDisplay`, `Oswald`, `NotoSerif`)
/// - Fits 1 or 2 balanced lines inside `maxW = W * 0.75` (`132.0px`),
///   `maxH = min(H * 0.20, 170 * H / 750)` (`65.6px`) on tall or `189.1 × 44.7px` on landscape.
class _CleanNotchFallbackTitle extends StatelessWidget {
  const _CleanNotchFallbackTitle({
    required this.name,
    this.primaryGenre,
    this.isLandscape = false,
  });

  final String name;
  final String? primaryGenre;
  final bool isLandscape;

  @override
  Widget build(BuildContext context) {
    final fontFamily = CleanNotchEngine.genreFallbackFontFamily(primaryGenre);
    final isAllCapsFont = fontFamily == 'BebasNeue' ||
        fontFamily == 'Oswald' ||
        fontFamily == 'Creepster';
    final displayTitle = isAllCapsFont ? name.trim().toUpperCase() : name.trim();
    final maxW = isLandscape
        ? PersonalizedSlots.landscapeWidth * 0.62 // 189.1
        : PersonalizedSlots.tallWidth * 0.75; // 132.0
    final maxH = isLandscape
        ? PersonalizedSlots.landscapeHeight * 0.26 // 44.72
        : 65.6;

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxW,
          maxHeight: maxH,
        ),
        child: Text(
          displayTitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: fontFamily,
            fontSize: isLandscape
                ? (isAllCapsFont ? 20.5 : 17.5)
                : (isAllCapsFont ? 24.0 : 20.0),
            fontWeight: FontWeight.w700,
            color: Colors.white,
            height: 1.08,
            letterSpacing: isAllCapsFont ? 0.6 : -0.2,
            shadows: const [
              Shadow(
                color: Color(0xB4000000),
                blurRadius: 6,
                offset: Offset(0, 2.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Step 4 of `clean_notch` (`render_clean_notch.py:1477-1556` & `CLEAN_METADATA_ROW_ROADMAP.md`):
/// - Renders `"{Genre} ★ {Score}"` at optical center `Y = H * 0.910` (tall) or `H * 0.895` (landscape)
///   with `-10%` font size upward baseline nudge
/// - Font: bundled `Inter` Semi-Bold (`FontWeight.w600`), size `W * 0.082` (`14.4px` on `176w` tall)
///   or `H * 0.072` (`12.4px` on `172h` landscape)
/// - Color: `Color(0xFFC8C8C8)` (`#C8C8C8` silver off-white)
class _CleanNotchMetadataRow extends StatelessWidget {
  const _CleanNotchMetadataRow({
    required this.label,
    required this.cardWidth,
    required this.cardHeight,
    this.isLandscape = false,
  });

  final String label;
  final double cardWidth;
  final double cardHeight;
  final bool isLandscape;

  @override
  Widget build(BuildContext context) {
    final fontSize = isLandscape
        ? cardHeight * CleanNotchEngine.landscapeMetadataFontSizeRatio // 12.38px on 172h
        : cardWidth * CleanNotchEngine.metadataFontSizeRatio; // 14.43px on 176w
    final centerY = isLandscape
        ? cardHeight * CleanNotchEngine.landscapeMetadataCenterYRatio // 153.94px on 172h
        : cardHeight * CleanNotchEngine.metadataCenterYRatio; // 298.48px on 328h
    // Apply the -10% upward optical baseline nudge from render_clean_notch.py:1553
    final topY = centerY - (fontSize * 0.65);
    final horizontalMargin = cardWidth * (isLandscape ? 0.14 : 0.07);

    return Positioned(
      top: topY,
      left: horizontalMargin,
      right: horizontalMargin,
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            label,
            maxLines: 1,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: CleanNotchEngine.metadataFontWeight,
              letterSpacing: 0.25,
              color: CleanNotchEngine.metadataTextColor,
              height: 1.1,
              fontFeatures: const [ui.FontFeature.tabularFigures()],
              shadows: const [
                Shadow(
                  color: Color(0xAA000000),
                  blurRadius: 4,
                  offset: Offset(0, 1.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Top-Center Clean Notch Badge (`awards.py:1656-1768` & `render_clean_notch.py:351-372`):
/// - Flush with the top edge (`top: 0`), horizontally centered in the top middle of landscape cards
/// - Uses the poster's dominant hue frosted reference tint (`backgroundColor`) and contrast ink (`inkColor`)
/// - Square top corners + `6.5px` rounded bottom corners (`BorderRadius.vertical(bottom: Radius.circular(6.5))`).
class _CleanNotchTopBadge extends StatelessWidget {
  const _CleanNotchTopBadge({
    required this.label,
    required this.backgroundColor,
    required this.inkColor,
  });

  final String label;
  final Color backgroundColor;
  final Color inkColor;

  @override
  Widget build(BuildContext context) {
    const borderRadius = BorderRadius.only(
      bottomLeft: Radius.circular(6.5),
      bottomRight: Radius.circular(6.5),
    );
    return CustomPaint(
      foregroundPainter: const _NotchPillBorderPainter(),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10.5, 3.0, 10.5, 3.5),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: borderRadius,
          boxShadow: const [
            BoxShadow(
              color: Color(0x40000000),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 8.6,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.65,
            height: 1.05,
            color: inkColor,
          ),
        ),
      ),
    );
  }
}

/// Paints a 0.75px specular glass hairline around the left, bottom, and right
/// edges (omitting the top edge flush against the card top) without triggering
/// Flutter's `Border` + `borderRadius` uniform-border assertion.
class _NotchPillBorderPainter extends CustomPainter {
  const _NotchPillBorderPainter();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    const strokeWidth = 0.75;
    const inset = strokeWidth * 0.5;
    const left = inset;
    final clampedR =
        (6.5 - inset).clamp(0.0, math.min(size.width * 0.5, size.height)).toDouble();
    final right = size.width - inset;
    final bottom = size.height - inset;

    final path = Path()
      ..moveTo(left, 0)
      ..lineTo(left, bottom - clampedR)
      ..arcToPoint(
        Offset(left + clampedR, bottom),
        radius: Radius.circular(clampedR),
        clockwise: false,
      )
      ..lineTo(right - clampedR, bottom)
      ..arcToPoint(
        Offset(right, bottom - clampedR),
        radius: Radius.circular(clampedR),
        clockwise: false,
      )
      ..lineTo(right, 0);

    final paint = Paint()
      ..color = const Color(0x40FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..isAntiAlias = true;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _NotchPillBorderPainter oldDelegate) => false;
}

/// Geometry-matched shimmer skeleton for a personalized row while its artwork resolves.
class _PersonalizedRowSkeleton extends StatelessWidget {
  const _PersonalizedRowSkeleton({
    required this.title,
    required this.style,
    required this.inset,
  });

  final String title;
  final PersonalizedRowStyle style;
  final double inset;

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);
    final shadowPad = 12.h;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: inset),
          child: Text(
            title,
            style: AppText.rowHeading,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        SizedBox(height: AppDimens.rowGap),
        Shimmer.fromColors(
          baseColor: AppColors.surface,
          highlightColor: AppColors.surface2,
          period: const Duration(milliseconds: 1400),
          child: SizedBox(
            height: AppDimens.posterHeight + shadowPad,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(inset, 0, inset, shadowPad),
              itemCount: 4,
              separatorBuilder: (_, __) => SizedBox(width: AppDimens.posterGap),
              itemBuilder: (_, __) => Container(
                width: AppDimens.posterWidth,
                height: AppDimens.posterHeight,
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
}
