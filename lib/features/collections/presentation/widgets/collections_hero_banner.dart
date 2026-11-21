import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/perf/image_perf.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/responsive.dart';
import '../../../home/presentation/widgets/pixel_bottom_nav.dart';
import '../../../home/presentation/widgets/shimmer_loading.dart';
import '../../data/collection_models.dart';
import 'smooth_gif_image.dart';

/// Top OTT GIF highlight card (Figma 151:21: `371×189`, radius `10px`, `#171717`).
///
/// Plays each OTT GIF through to its final frame via [SmoothGifImage] before
/// crossfading + subtly scaling into the next item. Purely decorative (non-interactive).
class CollectionsHeroBanner extends StatefulWidget {
  const CollectionsHeroBanner({
    super.key,
    required this.items,
  });

  final List<CollectionHeroItem> items;

  @override
  State<CollectionsHeroBanner> createState() => _CollectionsHeroBannerState();
}

class _CollectionsHeroBannerState extends State<CollectionsHeroBanner> {
  static const Cubic _easeOutExpo = Cubic(0.22, 1, 0.36, 1);
  static const Cubic _easeInQuad = Cubic(0.4, 0, 1, 1);

  ProviderSubscription<PixelTab>? _tabSub;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _warmNext();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_tabSub == null) {
      try {
        final container = ProviderScope.containerOf(context, listen: false);
        _tabSub = container.listen<PixelTab>(
          activeTabProvider,
          (prev, next) {
            if (prev != null &&
                prev != next &&
                next == PixelTab.collections &&
                mounted) {
              if (_index != 0) {
                setState(() => _index = 0);
                _warmNext();
              }
            }
          },
        );
      } catch (_) {
        // Standalone widget test without a ProviderScope ancestor.
      }
    }
  }

  @override
  void didUpdateWidget(covariant CollectionsHeroBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items.length != oldWidget.items.length &&
        _index >= widget.items.length) {
      _index = 0;
    }
    _warmNext();
  }

  void _warmNext() {
    if (widget.items.length < 2) return;
    final next = widget.items[(_index + 1) % widget.items.length];
    for (final url in [next.gifUrl, next.fallbackCoverUrl]) {
      if (url != null && url.isNotEmpty) {
        try {
          unawaited(
            PixelImageCache.instance
                .getSingleFile(url)
                .then<void>((_) {}, onError: (_) {}),
          );
        } catch (_) {
          // Ignore cache warm errors in tests without platform plugins.
        }
      }
    }
  }

  void _advanceToNext() {
    if (!mounted || widget.items.length < 2) return;
    setState(() {
      _index = (_index + 1) % widget.items.length;
    });
    _warmNext();
  }

  @override
  void dispose() {
    _tabSub?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);
    final currentItem =
        widget.items.isNotEmpty ? widget.items[_index % widget.items.length] : null;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppDimens.collectionsScreenPadding,
      ),
      child: Container(
        key: const ValueKey('collections_hero_card'),
        width: double.infinity,
        height: AppDimens.collectionsHeroHeight,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.collectionCardOuterBg,
          borderRadius: BorderRadius.circular(AppDimens.collectionsHeroRadius),
          border: Border.all(color: AppColors.collectionCardBorder, width: 1),
        ),
        child: ClipRRect(
          borderRadius:
              BorderRadius.circular(AppDimens.collectionsHeroRadius - 1),
          child: currentItem == null
              ? const SizedBox.expand()
              : IgnorePointer(
                  child: AnimatedSwitcher(
                    key: const ValueKey('collections_hero_switcher'),
                    duration: const Duration(milliseconds: 520),
                    switchInCurve: _easeOutExpo,
                    switchOutCurve: _easeInQuad,
                    layoutBuilder:
                        (Widget? currentChild, List<Widget> previousChildren) {
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          ...previousChildren,
                          if (currentChild != null) currentChild,
                        ],
                      );
                    },
                    transitionBuilder:
                        (Widget child, Animation<double> animation) {
                      final scale = Tween<double>(
                        begin: 1.04,
                        end: 1.0,
                      ).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: _easeOutExpo,
                        ),
                      );
                      return FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: scale,
                          child: child,
                        ),
                      );
                    },
                    child: _HeroGifSlide(
                      key: ValueKey('hero_${currentItem.id}_$_index'),
                      item: currentItem,
                      onCompleted: _advanceToNext,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _HeroGifSlide extends StatefulWidget {
  const _HeroGifSlide({
    super.key,
    required this.item,
    required this.onCompleted,
  });

  final CollectionHeroItem item;
  final VoidCallback onCompleted;

  @override
  State<_HeroGifSlide> createState() => _HeroGifSlideState();
}

class _HeroGifSlideState extends State<_HeroGifSlide> {
  Timer? _fallbackTimer;
  bool _gifReady = false;
  bool _primaryFailed = false;
  bool _completedFired = false;

  @override
  void initState() {
    super.initState();
    _scheduleFallbackTimer();
  }

  @override
  void didUpdateWidget(covariant _HeroGifSlide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.gifUrl != widget.item.gifUrl) {
      _fallbackTimer?.cancel();
      _gifReady = false;
      _primaryFailed = false;
      _completedFired = false;
      _scheduleFallbackTimer();
    }
  }

  void _scheduleFallbackTimer() {
    _fallbackTimer?.cancel();
    if (widget.item.gifUrl.isEmpty) {
      _fallbackTimer = Timer(widget.item.duration, _triggerCompleted);
    } else {
      _fallbackTimer = Timer(
        widget.item.duration * 3 + const Duration(seconds: 6),
        _triggerCompleted,
      );
    }
  }

  void _triggerCompleted() {
    if (!mounted || _completedFired) return;
    _completedFired = true;
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    widget.onCompleted();
  }

  void _handleImageError() {
    if (!mounted || _primaryFailed) return;
    setState(() {
      _primaryFailed = true;
      _gifReady = false;
    });
    _fallbackTimer?.cancel();
    _fallbackTimer = Timer(widget.item.duration, _triggerCompleted);
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fallbackUrl = widget.item.fallbackCoverUrl;
    final hasGif = widget.item.gifUrl.isNotEmpty && !_primaryFailed;
    final showFallback = !_gifReady || !hasGif;

    return RepaintBoundary(
      child: Semantics(
        label: '${widget.item.title} highlight',
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (showFallback)
              if (fallbackUrl != null && fallbackUrl.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: fallbackUrl,
                  cacheManager: PixelImageCache.instance,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  placeholder: (_, __) => const PixelShimmer(
                    child: ColoredBox(color: AppColors.collectionCardInnerBg),
                  ),
                  errorWidget: (_, __, ___) =>
                      _HeroFallbackTile(title: widget.item.title),
                )
              else
                _HeroFallbackTile(title: widget.item.title),
            if (hasGif)
              SmoothGifImage(
                key: ValueKey('smooth_hero_${widget.item.gifUrl}'),
                url: widget.item.gifUrl,
                fit: BoxFit.cover,
                targetWidthPx: 742,
                loop: false,
                onFirstFrame: () {
                  if (mounted && !_gifReady) {
                    setState(() => _gifReady = true);
                  }
                },
                onCompleted: _triggerCompleted,
                onError: _handleImageError,
              ),
          ],
        ),
      ),
    );
  }
}

class _HeroFallbackTile extends StatelessWidget {
  const _HeroFallbackTile({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.iconGradient),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Text(
        title,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppText.pageTitle.copyWith(letterSpacing: -0.025),
      ),
    );
  }
}
