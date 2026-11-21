import 'dart:async';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/perf/image_perf.dart';
import '../../../../core/perf/snap_physics.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/responsive.dart';
import '../../../details/data/tmdb_repository.dart';
import '../../../details/presentation/details_text.dart';
import '../../../details/presentation/widgets/detail_widgets.dart';
import '../../../personalization/presentation/widgets/clean_notch_engine.dart';
import '../../../player/domain/models/watch_progress_models.dart';
import '../controllers/home_controller.dart';
import 'pixel_bottom_nav.dart';

/// Compact 16:9 Continue Watching shelf (Figma `124:243`: `170×98`, radius `8`,
/// `1px solid #262626`, `#0F172A` surface, `4px` `#FFFFFF` progress bar over
/// `#374151`), rendered with the 3-pass `CleanNotchEngine` frosted landscape
/// backdrop + Clearlogo styling from the legacy landscape personalized cards.
class ContinueWatchingShelf extends StatefulWidget {
  const ContinueWatchingShelf({
    super.key,
    required this.entries,
    required this.onResume,
    required this.onViewDetails,
    required this.onRemove,
    double? inset,
  }) : _inset = inset;

  static double get cardWidth => 170.w;
  static double get cardHeight => 98.w;
  static double get cardRadius => 8.r;
  static double get footerHeight => 28.h;
  static double get cardStride => cardWidth + AppDimens.posterGap;

  final List<WatchProgressEntry> entries;
  final ValueChanged<WatchProgressEntry> onResume;
  final ValueChanged<WatchProgressEntry> onViewDetails;
  final ValueChanged<WatchProgressEntry> onRemove;
  final double? _inset;

  double get inset => _inset ?? AppDimens.screenPadding;

  @override
  State<ContinueWatchingShelf> createState() => _ContinueWatchingShelfState();
}

class _ContinueWatchingShelfState extends State<ContinueWatchingShelf> {
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
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _tabSub?.close();
    _filterSub?.close();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _openOptionsSheet(WatchProgressEntry entry) async {
    HapticFeedback.selectionClick();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x99000000),
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ContinueWatchingOptionsSheet(
        entry: entry,
        onViewDetails: () {
          Navigator.of(context).pop();
          widget.onViewDetails(entry);
        },
        onRemove: () {
          Navigator.of(context).pop();
          widget.onRemove(entry);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);
    if (widget.entries.isEmpty) return const SizedBox.shrink();

    final effectiveInset = widget.inset;
    final stride = ContinueWatchingShelf.cardStride;
    final bottomPad = 6.h;

    return Padding(
      padding: EdgeInsets.only(bottom: AppDimens.rowSpacing),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: effectiveInset),
            child: Text(
              'Continue Watching',
              style: AppText.rowHeading,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(height: AppDimens.rowGap),
          SizedBox(
            height: ContinueWatchingShelf.cardHeight +
                ContinueWatchingShelf.footerHeight +
                bottomPad,
            child: ListView.builder(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              physics: PosterSnapPhysics(
                itemExtent: stride,
              ),
              itemExtent: stride,
              padding: EdgeInsets.fromLTRB(effectiveInset, 0, effectiveInset, bottomPad),
              addAutomaticKeepAlives: false,
              addSemanticIndexes: false,
              itemCount: widget.entries.length,
              itemBuilder: (_, i) {
                final entry = widget.entries[i];
                return Padding(
                  padding: EdgeInsets.only(right: AppDimens.posterGap),
                  child: RepaintBoundary(
                    child: ContinueWatchingCard(
                      key: ValueKey('cw_${entry.canonicalId}'),
                      entry: entry,
                      onTap: () => widget.onResume(entry),
                      onMoreTap: () => _openOptionsSheet(entry),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class ContinueWatchingCard extends ConsumerStatefulWidget {
  const ContinueWatchingCard({
    super.key,
    required this.entry,
    required this.onTap,
    required this.onMoreTap,
  });

  final WatchProgressEntry entry;
  final VoidCallback onTap;
  final VoidCallback onMoreTap;

  static const _fallbackBg = LinearGradient(
    begin: Alignment.bottomLeft,
    end: Alignment.topRight,
    colors: [Color(0xFF1E1B4B), Color(0xFF581C87), Color(0xFF0369A1)],
  );

  static const _fallbackBottomVignette = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x00090A0F), Color(0xCC090A0F), Color(0xEB090A0F)],
    stops: [0.0, 0.55, 1.0],
  );

  @override
  ConsumerState<ContinueWatchingCard> createState() =>
      _ContinueWatchingCardState();
}

class _ContinueWatchingCardState extends ConsumerState<ContinueWatchingCard> {
  String? _enrichedBackdropUrl;
  String? _enrichedLogoUrl;
  double? _enrichedLogoAspectRatio;

  ProcessedCleanNotchPoster? _processedPoster;
  ui.Image? _rawBackdrop;
  ImageStream? _posterStream;
  ImageStreamListener? _posterListener;
  String? _activePosterKey;
  int _urlIndex = 0;

  ProcessedCleanNotchLogo? _processedLogo;
  ui.Image? _rawLogo;
  ImageStream? _logoStream;
  ImageStreamListener? _logoListener;
  String? _activeLogoKey;
  bool _logoFailed = false;

  String? get _effectiveLogo => _enrichedLogoUrl ?? widget.entry.logoUrl;
  double? get _effectiveLogoRatio =>
      _enrichedLogoAspectRatio ?? widget.entry.logoAspectRatio;

  List<String> get _candidateImageUrls => [
        if (_enrichedBackdropUrl != null && _enrichedBackdropUrl!.isNotEmpty)
          _enrichedBackdropUrl!,
        if (widget.entry.backdropUrl != null &&
            widget.entry.backdropUrl!.isNotEmpty)
          widget.entry.backdropUrl!,
        if (widget.entry.posterUrl != null &&
            widget.entry.posterUrl!.isNotEmpty)
          widget.entry.posterUrl!,
      ];

  @override
  void initState() {
    super.initState();
    _maybeEnrichArtwork();
    _resolveBackdrop();
    _resolveLogo();
  }

  @override
  void didUpdateWidget(covariant ContinueWatchingCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.canonicalId != widget.entry.canonicalId ||
        oldWidget.entry.backdropUrl != widget.entry.backdropUrl ||
        oldWidget.entry.posterUrl != widget.entry.posterUrl ||
        oldWidget.entry.logoUrl != widget.entry.logoUrl) {
      _enrichedBackdropUrl = null;
      _enrichedLogoUrl = null;
      _enrichedLogoAspectRatio = null;
      _urlIndex = 0;
      _rawBackdrop = null;
      _processedPoster = null;
      _rawLogo = null;
      _processedLogo = null;
      _maybeEnrichArtwork();
      _resolveBackdrop();
      _resolveLogo();
    }
  }

  @override
  void dispose() {
    _unsubscribePoster();
    _unsubscribeLogo();
    super.dispose();
  }

  Future<void> _maybeEnrichArtwork() async {
    final e = widget.entry;
    if ((e.backdropUrl?.isNotEmpty == true) && (e.logoUrl?.isNotEmpty == true)) {
      return;
    }
    final tmdbId = e.tmdbId ?? int.tryParse(e.rawId ?? '');
    if (tmdbId == null || tmdbId <= 0) return;
    try {
      final repo = ref.read(tmdbRepositoryProvider);
      final art = await repo.fetchPersonalizedCardArtwork(tmdbId, e.mediaType);
      if (!mounted) return;
      final newBg = art.landscapeBackdropUrl ?? art.standardPosterUrl;
      final newLogo = art.logoUrl;
      if (newBg != null || newLogo != null) {
        setState(() {
          if (newBg != null && newBg.isNotEmpty) _enrichedBackdropUrl = newBg;
          if (newLogo != null && newLogo.isNotEmpty) {
            _enrichedLogoUrl = newLogo;
            _enrichedLogoAspectRatio = art.logoAspectRatio;
          }
        });
        _resolveBackdrop();
        _resolveLogo();
      }
    } catch (_) {}
  }

  void _unsubscribePoster() {
    if (_posterStream != null && _posterListener != null) {
      _posterStream!.removeListener(_posterListener!);
    }
    _posterStream = null;
    _posterListener = null;
  }

  void _unsubscribeLogo() {
    if (_logoStream != null && _logoListener != null) {
      _logoStream!.removeListener(_logoListener!);
    }
    _logoStream = null;
    _logoListener = null;
  }

  void _resolveBackdrop() {
    _unsubscribePoster();
    final urls = _candidateImageUrls;
    if (_urlIndex >= urls.length) return;

    final sized = tmdbSized(urls[_urlIndex], forWidthPx: 420);
    final cacheKey = 'cw_land|$sized';
    if (_activePosterKey == cacheKey &&
        (_processedPoster != null || _rawBackdrop != null)) {
      return;
    }
    _activePosterKey = cacheKey;

    final cached = CleanNotchEngine.getCachedPoster(cacheKey);
    if (cached != null) {
      _processedPoster = cached;
      _rawBackdrop = null;
      return;
    }

    final provider = CachedNetworkImageProvider(
      sized,
      cacheManager: PixelImageCache.instance,
      maxWidth: 420,
    );
    final stream = provider.resolve(ImageConfiguration.empty);
    _posterStream = stream;
    _posterListener = ImageStreamListener(
      (info, _) async {
        if (!mounted || _activePosterKey != cacheKey) return;
        if (_rawBackdrop == null && _processedPoster == null) {
          setState(() => _rawBackdrop = info.image);
        }
        final processed = await CleanNotchEngine.processPoster(
          cacheKey: cacheKey,
          rawImage: info.image,
          isLandscape: true,
        );
        if (!mounted || _activePosterKey != cacheKey) return;
        if (processed != null) {
          setState(() => _processedPoster = processed);
          _resolveLogo();
        }
      },
      onError: (_, __) {
        if (!mounted || _activePosterKey != cacheKey) return;
        if (_urlIndex + 1 < urls.length) {
          _urlIndex++;
          _resolveBackdrop();
        }
      },
    );
    stream.addListener(_posterListener!);
  }

  void _resolveLogo() {
    _unsubscribeLogo();
    final rawUrl = _effectiveLogo;
    if (rawUrl == null || rawUrl.isEmpty) {
      _processedLogo = null;
      _rawLogo = null;
      _activeLogoKey = null;
      _logoFailed = false;
      return;
    }
    final bgLum = _processedPoster?.bgLum ?? 0.08;
    final bgR = _processedPoster?.bgR ?? 16.0;
    final bgG = _processedPoster?.bgG ?? 20.0;
    final bgB = _processedPoster?.bgB ?? 30.0;

    final sized = tmdbSized(rawUrl, forWidthPx: 260);
    final cacheKey = 'cw_logo|$sized|lum:${(bgLum * 10).round()}';
    if (_activeLogoKey == cacheKey && _processedLogo != null) return;
    _activeLogoKey = cacheKey;
    _logoFailed = false;

    final cached = CleanNotchEngine.getCachedLogo(cacheKey);
    if (cached != null) {
      _processedLogo = cached;
      _rawLogo = null;
      return;
    }

    final provider = CachedNetworkImageProvider(
      sized,
      cacheManager: PixelImageCache.instance,
      maxWidth: 260,
    );
    final stream = provider.resolve(ImageConfiguration.empty);
    _logoStream = stream;
    _logoListener = ImageStreamListener(
      (info, _) async {
        if (!mounted || _activeLogoKey != cacheKey) return;
        if (_rawLogo == null && _processedLogo == null) {
          setState(() => _rawLogo = info.image);
        }
        final processed = await CleanNotchEngine.processLogo(
          cacheKey: cacheKey,
          rawLogo: info.image,
          bgR: bgR,
          bgG: bgG,
          bgB: bgB,
          bgLum: bgLum,
        );
        if (!mounted || _activeLogoKey != cacheKey) return;
        if (processed == null) {
          setState(() => _logoFailed = true);
        } else {
          setState(() => _processedLogo = processed);
        }
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
    Responsive.init(context);
    final entry = widget.entry;
    final cardW = ContinueWatchingShelf.cardWidth;
    final cardH = ContinueWatchingShelf.cardHeight;
    final radius = BorderRadius.circular(ContinueWatchingShelf.cardRadius);
    final progress = entry.continueWatchingProgressFraction.clamp(0.0, 1.0);
    final epBadge = entry.continueWatchingEpisodeBadge;
    final remLabel = entry.continueWatchingRemainingLabel;
    final processed = _processedPoster;
    final rawBg = _rawBackdrop;

    return SizedBox(
      width: cardW,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 170×98 Landscape Poster Card (Figma 124:243 + CleanNotch Styling) ──
          Container(
            width: cardW,
            height: cardH,
            decoration: BoxDecoration(
              borderRadius: radius,
              color: const Color(0xFF0F172A),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            foregroundDecoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: const Color(0xFF262626), width: 1),
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (processed != null)
                    RawImage(
                      image: processed.image,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.low,
                    )
                  else if (rawBg != null) ...[
                    RawImage(
                      image: rawBg,
                      fit: BoxFit.cover,
                      alignment: const Alignment(0, -0.15),
                      filterQuality: FilterQuality.low,
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: cardH * 0.62,
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: ContinueWatchingCard._fallbackBottomVignette,
                        ),
                      ),
                    ),
                  ] else
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: ContinueWatchingCard._fallbackBg,
                      ),
                    ),

                  // Centered Clearlogo or Fallback Title (matching landscape card styling)
                  Positioned(
                    left: 16.w,
                    right: 16.w,
                    bottom: 12.w,
                    child: _buildTitleLockup(),
                  ),

                  // Bottom 4px White Progress Bar (#FFFFFF on #374151, Figma 124:243)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 4.h,
                    child: ColoredBox(
                      color: const Color(0xFF374151),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: progress,
                          heightFactor: 1.0,
                          child: const SizedBox.expand(
                            child: ColoredBox(color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Full-card tap target to resume immediately
                  Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        widget.onTap();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Under-Poster Footer: S1E1 + Remaining Time (left) & 3 Dots (right) ──
          SizedBox(
            height: ContinueWatchingShelf.footerHeight,
            child: Padding(
              padding: EdgeInsets.only(top: 5.h, left: 2.w),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          if (epBadge != null) ...[
                            TextSpan(
                              text: epBadge,
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 11.5.sp,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                            const TextSpan(text: '  '),
                          ],
                          TextSpan(
                            text: remLabel,
                            style: TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 11.sp,
                              fontWeight: FontWeight.w400,
                              color: const Color(0xFF9CA3AF),
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onMoreTap,
                    child: SizedBox(
                      width: 24.w,
                      height: 22.h,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Icon(
                          Icons.more_vert_rounded,
                          size: 16.r,
                          color: const Color(0xFF9CA3AF),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTitleLockup() {
    final maxW = 132.w;
    final maxH = 34.w;
    final logo = _processedLogo;
    if (logo != null && !_logoFailed) {
      final size = CleanNotchEngine.computeLogoTargetSize(
        cardWidth: ContinueWatchingShelf.cardWidth,
        cardHeight: ContinueWatchingShelf.cardHeight,
        aspectRatio: logo.aspectRatio,
        isLandscape: true,
      );
      return Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: size.width.clamp(0.0, maxW),
          height: size.height.clamp(0.0, maxH),
          child: RawImage(
            image: logo.image,
            fit: BoxFit.contain,
            alignment: Alignment.bottomCenter,
            filterQuality: FilterQuality.low,
          ),
        ),
      );
    }

    final rawLogo = _rawLogo;
    if (rawLogo != null && !_logoFailed) {
      final aspect = _effectiveLogoRatio ??
          (rawLogo.height > 0 ? rawLogo.width / rawLogo.height : 2.5);
      final size = CleanNotchEngine.computeLogoTargetSize(
        cardWidth: ContinueWatchingShelf.cardWidth,
        cardHeight: ContinueWatchingShelf.cardHeight,
        aspectRatio: aspect,
        isLandscape: true,
      );
      return Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: size.width.clamp(0.0, maxW),
          height: size.height.clamp(0.0, maxH),
          child: RawImage(
            image: rawLogo,
            fit: BoxFit.contain,
            alignment: Alignment.bottomCenter,
            filterQuality: FilterQuality.low,
          ),
        ),
      );
    }

    // Crisp fallback title when Clearlogo is absent or still resolving
    return Text(
      widget.entry.title.toUpperCase(),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontFamily: 'Inter',
        fontSize: 11.5.sp,
        fontWeight: FontWeight.w800,
        color: Colors.white,
        letterSpacing: 0.4,
        height: 1.15,
        shadows: const [
          Shadow(color: Color(0xCC000000), blurRadius: 6, offset: Offset(0, 1)),
        ],
      ),
    );
  }
}

/// Bottom sheet opened from the 3-dots menu under a Continue Watching card.
/// Matches [DetailSeasonSelectorSheet] chrome (`#000000` sheet, `28px` top radius,
/// `1px rgba(255,255,255,0.08)` border, `#363B47` drag handle, `#242A37` circular
/// close button) with the title name as header and `View Details` +
/// `Remove from Continue Watching` actions.
class ContinueWatchingOptionsSheet extends StatelessWidget {
  const ContinueWatchingOptionsSheet({
    super.key,
    required this.entry,
    required this.onViewDetails,
    required this.onRemove,
  });

  final WatchProgressEntry entry;
  final VoidCallback onViewDetails;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Container(
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
              // Header: Selected Title Name + Circular Close Button
              Padding(
                padding: EdgeInsets.fromLTRB(24.w, 0, 24.w, 18.h),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: 12.w),
                        child: Text(
                          entry.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DetailsText.inter(
                            size: 20.sp,
                            weight: FontWeight.w700,
                            color: Colors.white,
                            height: 30 / 20,
                          ).copyWith(letterSpacing: -0.5),
                        ),
                      ),
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
              // Actions
              Padding(
                padding: EdgeInsets.fromLTRB(24.w, 4.h, 24.w, 24.h + bottomInset),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ContinueWatchingActionRow(
                      icon: Icons.info_outline_rounded,
                      title: 'View Details',
                      subtitle: entry.mediaType == 'series'
                          ? 'Open title page, episodes & info'
                          : 'Open title page & info',
                      onTap: () {
                        HapticFeedback.selectionClick();
                        onViewDetails();
                      },
                    ),
                    SizedBox(height: 16.h),
                    _ContinueWatchingActionRow(
                      icon: Icons.delete_outline_rounded,
                      title: 'Remove from Continue Watching',
                      subtitle: 'Removes this title from your Continue Watching row',
                      isDestructive: true,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        onRemove();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContinueWatchingActionRow extends StatelessWidget {
  const _ContinueWatchingActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isDestructive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) {
    final tint = isDestructive ? const Color(0xFFFF6B6B) : Colors.white;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10.r),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 4.h),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(icon, size: 22.r, color: tint),
            SizedBox(width: 14.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DetailsText.inter(
                      size: 16.5.sp,
                      weight: FontWeight.w600,
                      color: tint,
                      height: 24 / 16.5,
                    ).copyWith(letterSpacing: -0.35),
                  ),
                  SizedBox(height: 1.h),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DetailsText.inter(
                      size: 12.5.sp,
                      weight: FontWeight.w400,
                      color: const Color(0xFF8491A5),
                      height: 18 / 12.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
