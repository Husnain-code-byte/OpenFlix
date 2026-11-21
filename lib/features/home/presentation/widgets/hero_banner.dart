import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/responsive.dart';
import '../../../my_list/presentation/controllers/my_list_controller.dart';
import '../../../personalization/presentation/widgets/clean_notch_engine.dart';
import '../../data/models/meta_model.dart';
import '../../data/repositories/hero_artwork_repository.dart';
import '../utils/title_format.dart';
import 'poster_card.dart';
import 'shimmer_loading.dart';

const _playSvg =
    '<svg viewBox="0 0 14 17" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M0 0L14 8.5L0 17V0Z" fill="#090D0E"/></svg>';
const _bookmarkSvg =
    '<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M16 4H8C6.9 4 6 4.9 6 6V19C6 19.36 6.19 19.69 6.5 19.87C6.81 20.05 7.19 20.04 7.5 19.87L11.99 17.21L16.48 19.87C16.64 19.96 16.81 20.01 16.99 20.01C17.17 20.01 17.33 19.97 17.49 19.88C17.8 19.7 17.99 19.37 17.99 19.01V6.01C17.99 4.91 17.09 4.01 15.99 4.01L16 4ZM16 12V17.25L12.51 15.18C12.3564 15.0864 12.1799 15.0368 12 15.0368C11.8201 15.0368 11.6436 15.0864 11.49 15.18L8 17.25V6H16V12Z" fill="white"/></svg>';
const _bookmarkFilledSvg =
    '<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg"><path d="M16 4H8C6.9 4 6 4.9 6 6V19C6 19.36 6.19 19.69 6.5 19.87C6.81 20.05 7.19 20.04 7.5 19.87L11.99 17.21L16.48 19.87C16.64 19.96 16.81 20.01 16.99 20.01C17.17 20.01 17.33 19.97 17.49 19.88C17.8 19.7 17.99 19.37 17.99 19.01V6.01C17.99 4.91 17.09 4.01 15.99 4.01L16 4Z" fill="white"/></svg>';

/// Swipeable row of Figma "Featured film" cards (auto-advances every 7s).
class HeroBanner extends StatefulWidget {
  const HeroBanner({
    super.key,
    required this.items,
    required this.onPlay,
    required this.onMyList,
    required this.onOpen,
  });

  final List<MetaModel> items;
  final ValueChanged<MetaModel> onPlay;
  final ValueChanged<MetaModel> onMyList;
  final ValueChanged<MetaModel> onOpen;

  @override
  State<HeroBanner> createState() => _HeroBannerState();
}

class _HeroBannerState extends State<HeroBanner> {
  final _page = PageController();
  int _index = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startAutoPlay();
  }

  @override
  void didUpdateWidget(covariant HeroBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items.length != oldWidget.items.length) {
      if (_index >= widget.items.length) {
        _index = 0;
        if (_page.hasClients) _page.jumpToPage(0);
      }
      _startAutoPlay();
    }
  }

  void _startAutoPlay() {
    _timer?.cancel();
    if (widget.items.length < 2) return;
    _timer = Timer.periodic(const Duration(seconds: 7), (_) {
      if (!_page.hasClients) return;
      final next = (_index + 1) % widget.items.length;
      _page.animateToPage(next, duration: const Duration(milliseconds: 600), curve: Curves.easeOutCubic);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);
    return SizedBox(
      height: AppDimens.heroSlideHeight(context),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: widget.items.isEmpty
            ? const HeroBannerSkeleton(key: ValueKey('hero_banner_skeleton'))
            : PageView.builder(
                key: const ValueKey('hero_banner_pageview'),
                controller: _page,
                itemCount: widget.items.length,
                onPageChanged: (i) {
                  _index = i;
                  _startAutoPlay(); // restart the timer after a manual swipe
                },
                // Each slide paints in its own layer, so a swipe only composites —
                // the gradient/text of the neighbouring slide is never repainted.
                itemBuilder: (_, i) => RepaintBoundary(
                  child: _HeroSlide(
                    meta: widget.items[i],
                    onPlay: widget.onPlay,
                    onMyList: widget.onMyList,
                    onOpen: widget.onOpen,
                  ),
                ),
              ),
      ),
    );
  }
}

class _HeroSlide extends ConsumerStatefulWidget {
  const _HeroSlide({required this.meta, required this.onPlay, required this.onMyList, required this.onOpen});
  final MetaModel meta;
  final ValueChanged<MetaModel> onPlay;
  final ValueChanged<MetaModel> onMyList;
  final ValueChanged<MetaModel> onOpen;

  @override
  ConsumerState<_HeroSlide> createState() => _HeroSlideState();
}

class _HeroSlideState extends ConsumerState<_HeroSlide> {
  static const _fallbackHeroVignette = LinearGradient(
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

  ProcessedCleanNotchPoster? _processedHero;
  String? _activeHeroKey;
  ImageStream? _imageStream;
  ImageStreamListener? _imageListener;

  @override
  void didUpdateWidget(covariant _HeroSlide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.meta.id != widget.meta.id) {
      _detachImageStream();
      _processedHero = null;
      _activeHeroKey = null;
    }
  }

  @override
  void dispose() {
    _detachImageStream();
    super.dispose();
  }

  void _detachImageStream() {
    if (_imageStream != null && _imageListener != null) {
      _imageStream!.removeListener(_imageListener!);
    }
    _imageStream = null;
    _imageListener = null;
  }

  void _resolveHeroPoster({
    required String url,
    required ImageProvider provider,
    required double aspectRatio,
  }) {
    final cacheKey = 'hero:$url@${aspectRatio.toStringAsFixed(2)}';
    if (_activeHeroKey == cacheKey && _processedHero != null) return;
    _activeHeroKey = cacheKey;

    final cached = CleanNotchEngine.getCachedPoster(cacheKey);
    if (cached != null) {
      _detachImageStream();
      if (mounted && _processedHero != cached) {
        setState(() => _processedHero = cached);
      }
      return;
    }

    _detachImageStream();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (imageInfo, _) {
        if (_activeHeroKey != cacheKey) {
          stream.removeListener(listener);
          return;
        }
        final clonedImage = imageInfo.image.clone();
        _detachImageStream();
        unawaited(
          _extractAndApplyHeroPoster(
            cacheKey: cacheKey,
            clonedImage: clonedImage,
            aspectRatio: aspectRatio,
          ),
        );
      },
      onError: (_, __) {
        if (_activeHeroKey == cacheKey) {
          _detachImageStream();
        }
      },
    );
    _imageStream = stream;
    _imageListener = listener;
    stream.addListener(listener);
  }

  Future<void> _extractAndApplyHeroPoster({
    required String cacheKey,
    required ui.Image clonedImage,
    required double aspectRatio,
  }) async {
    try {
      final processed = await CleanNotchEngine.processHeroPoster(
        cacheKey: cacheKey,
        rawImage: clonedImage,
        aspectRatio: aspectRatio,
      );
      if (!mounted || _activeHeroKey != cacheKey || processed == null) {
        return;
      }
      setState(() => _processedHero = processed);
    } finally {
      clonedImage.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final meta = widget.meta;
    ref.watch(myListControllerProvider);
    final isInMyList = ref.read(myListControllerProvider.notifier).isMetaInMyList(meta);
    final artworkAsync = ref.watch(heroArtworkProvider((imdbId: meta.id, type: meta.type)));
    final artwork = artworkAsync.valueOrNull;
    final isResolvingTmdbHero =
        artworkAsync.isLoading && (meta.id.startsWith('tt') || int.tryParse(meta.id) != null);
    final genreLine = meta.genres.isEmpty ? typeLabel(meta.type) : meta.genres.take(3).join('  ·  ');
    final releaseLine = [meta.releaseInfo, formatRuntime(meta.runtime), typeLabel(meta.type)]
        .whereType<String>()
        .where((e) => e.isNotEmpty)
        .join('  ·  ');
    final cardHeight = AppDimens.heroSlideHeight(context) - AppDimens.heroTopPad;
    final processedHero = _processedHero;

    return Padding(
      // Featured film: padding 6 18 0 18
      padding: EdgeInsets.fromLTRB(AppDimens.heroGutter, AppDimens.heroTopPad, AppDimens.heroGutter, 0),
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          height: cardHeight,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.heroBg,
            borderRadius: BorderRadius.circular(AppDimens.heroRadius),
            border: Border.all(color: AppColors.heroBorder),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Stack(fit: StackFit.expand, children: [
              LayoutBuilder(builder: (context, constraints) {
                if (isResolvingTmdbHero) {
                  return const PixelShimmer(
                    child: ColoredBox(color: Colors.white),
                  );
                }
                final heroAspect = (cardHeight > 0 ? constraints.maxWidth / cardHeight : 0.68).clamp(0.4, 2.0);
                final fallbackBandRatio = heroAspect >= 1.1
                    ? CleanNotchEngine.landscapeBottomHeightRatio
                    : CleanNotchEngine.bottomHeightRatio;
                return Stack(fit: StackFit.expand, children: [
                  FallbackNetworkImage(
                    // The catalog item's `poster` is designed for small catalog cards.
                    // The featured card prefers TMDB's language-neutral poster and
                    // backdrop, then falls back to the item's clean background.
                    urls: [
                      artwork?.posterUrl,
                      artwork?.backdropUrl,
                      meta.background,
                      meta.landscapePoster,
                      meta.posterFallback,
                      meta.poster,
                    ],
                    memWidth: constraints.maxWidth,
                    memHeight: AppDimens.heroSlideHeight(context),
                    placeholder: const PixelShimmer(
                      child: ColoredBox(color: Colors.white),
                    ),
                    fallback: const ColoredBox(color: AppColors.heroBg),
                    onImageResolved: (url, provider) {
                      _resolveHeroPoster(
                        url: url,
                        provider: provider,
                        aspectRatio: heroAspect,
                      );
                    },
                  ),
                  if (processedHero != null)
                    RawImage(
                      image: processedHero.image,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.medium,
                    )
                  else
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: cardHeight * fallbackBandRatio,
                      child: const IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(gradient: _fallbackHeroVignette),
                        ),
                      ),
                    ),
                ]);
              }),
              // Tapping the poster opens details; buttons below sit above this layer.
              Positioned.fill(
                child: InkWell(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    widget.onOpen(meta);
                  },
                ),
              ),
              // Poster information: 322 wide, 16px from the card edges (15 + 1px border)
              Positioned(
                left: 15.w,
                right: 15.w,
                bottom: 15.h,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  _HeroTitle(
                    name: meta.name,
                    // The catalog item's logo is already a TMDB logo, so prefer it: the
                    // title then never swaps images when TMDB's lookup returns.
                    logoUrl: meta.logo ?? artwork?.logoUrl,
                  ),
                  SizedBox(height: 12.h),
                  Text(
                    genreLine,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.heroGenre,
                  ),
                  if (releaseLine.isNotEmpty) ...[
                    SizedBox(height: 5.h),
                    Text(
                      releaseLine,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.heroMeta,
                    ),
                  ],
                  SizedBox(height: 12.h),
                  Row(children: [
                    Expanded(
                      child: _HeroButton(
                        color: AppColors.textPrimary,
                        icon: SvgPicture.string(_playSvg, width: 14.r, height: 17.r),
                        label: 'Play',
                        labelColor: AppColors.onLight,
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          widget.onPlay(meta);
                        },
                      ),
                    ),
                    SizedBox(width: 10.w),
                    Expanded(
                      child: _HeroButton(
                        color: AppColors.heroSecondaryBtn,
                        icon: SvgPicture.string(
                          isInMyList ? _bookmarkFilledSvg : _bookmarkSvg,
                          width: 24.r,
                          height: 24.r,
                        ),
                        label: 'My List',
                        labelColor: AppColors.textPrimary,
                        animateBookmark: true,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          widget.onMyList(meta);
                        },
                      ),
                    ),
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

class _HeroTitle extends StatelessWidget {
  const _HeroTitle({required this.name, this.logoUrl});

  final String name;
  final String? logoUrl;

  @override
  Widget build(BuildContext context) {
    final fallback = _TitleWordmark(name: name);
    if (logoUrl == null) return fallback;
    final logoW = 302.w;
    final logoH = 82.h;
    return SizedBox(
      width: logoW,
      height: logoH,
      child: FallbackNetworkImage(
        urls: [logoUrl],
        fit: BoxFit.contain,
        memWidth: logoW,
        memHeight: logoH,
        // Transparent while loading; the default poster tile would show a box.
        placeholder: const SizedBox.shrink(),
        fallback: fallback,
      ),
    );
  }
}

/// 42px tall, radius 5, icon + 8px gap + Arimo 15 bold label.
/// When [animateBookmark] is true, tapping triggers the exact 420ms 3-stage
/// bookmark bounce/pop animation used by the Details screen "My List" button.
class _HeroButton extends StatefulWidget {
  const _HeroButton({
    required this.color,
    required this.icon,
    required this.label,
    required this.labelColor,
    required this.onTap,
    this.animateBookmark = false,
  });
  final Color color;
  final Widget icon;
  final String label;
  final Color labelColor;
  final VoidCallback onTap;
  final bool animateBookmark;

  @override
  State<_HeroButton> createState() => _HeroButtonState();
}

class _HeroButtonState extends State<_HeroButton>
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
    if (!widget.animateBookmark) return child;
    return AnimatedBuilder(
      animation: _controller,
      child: child,
      builder: (context, iconChild) {
        final t = _controller.value;
        if (t <= 0.0 || t >= 1.0) return iconChild!;

        double scaleX = 1.0;
        double scaleY = 1.0;
        double dy = 0.0;

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

        return Transform.translate(
          offset: Offset(0, dy),
          child: Transform.scale(
            scaleX: scaleX,
            scaleY: scaleY,
            child: iconChild,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) => Material(
        color: widget.color,
        borderRadius: BorderRadius.circular(5.r),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            if (widget.animateBookmark) {
              _controller.forward(from: 0.0);
            }
            widget.onTap();
          },
          child: SizedBox(
            height: 42.h,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _buildAnimatedIcon(widget.icon),
              SizedBox(width: 8.w),
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.heroButton(widget.labelColor),
                ),
              ),
            ]),
          ),
        ),
      );
}

/// Film title wordmark: width 302, gap 1 — lead (34/37), connector row, finish (23/28).
class _TitleWordmark extends StatelessWidget {
  const _TitleWordmark({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    final p = splitTitle(name);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 10.w),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _FitLine(text: p.lead, size: 34, lineHeight: 37),
        if (p.finish != null) ...[
          SizedBox(height: 1.h),
          SizedBox(
            height: 10.h,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(width: (p.connector != null ? 30 : 70).w, height: 1, color: AppColors.heroRule),
              if (p.connector != null) ...[
                SizedBox(width: 10.w),
                Text(p.connector!, style: AppText.syncopate(8, 10, AppColors.heroConnector)),
                SizedBox(width: 10.w),
                Container(width: 30.w, height: 1, color: AppColors.heroRule),
              ],
            ]),
          ),
          SizedBox(height: 1.h),
          _FitLine(text: p.finish!, size: 23, lineHeight: 28),
        ],
      ]),
    );
  }
}

/// Renders at the Figma size; only scales down if a real title would overflow the wordmark width.
class _FitLine extends StatelessWidget {
  const _FitLine({required this.text, required this.size, required this.lineHeight});
  final String text;
  final double size;
  final double lineHeight;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            text,
            maxLines: 1,
            softWrap: false,
            textAlign: TextAlign.center,
            style: AppText.syncopate(size, lineHeight, AppColors.heroTitle),
          ),
        ),
      );
}
