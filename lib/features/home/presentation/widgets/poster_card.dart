import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';


import '../../../../core/perf/image_perf.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/responsive.dart';
import '../../data/models/meta_model.dart';


/// Cached network image with three low-end protections:
/// 1. [memWidth]/[memHeight] cap the decoded bitmap size (RAM),
/// 2. [PixelImageCache] persists images on disk for 30 days,
/// 3. TMDB URLs in [urls] are bucketed down to the displayed size.
class FallbackNetworkImage extends StatefulWidget {
  const FallbackNetworkImage({
    super.key,
    required this.urls,
    required this.fallback,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.memWidth,
    this.memHeight,
    this.fadeIn = const Duration(milliseconds: 250),
    this.placeholder,
    this.onImageResolved,
  });

  final List<String?> urls;
  final Widget fallback;
  final BoxFit fit;
  final Alignment alignment;
  final double? memWidth;
  final double? memHeight;
  final Duration fadeIn;

  /// Shown while loading. Defaults to a flat surface tile (posters); pass
  /// `SizedBox.shrink()` for see-through content such as title logos.
  final Widget? placeholder;

  /// Optional callback invoked once per resolved network image URL/provider.
  final void Function(String url, ImageProvider provider)? onImageResolved;

  @override
  State<FallbackNetworkImage> createState() => _FallbackNetworkImageState();
}

class _FallbackNetworkImageState extends State<FallbackNetworkImage> {
  int _i = 0;
  late List<String> _urls = _extractUrls(widget.urls);
  String? _lastResolvedUrl;
  ImageProvider? _lastResolvedProvider;

  static List<String> _extractUrls(List<String?> raw) => [
        for (final u in raw)
          if (u != null && u.isNotEmpty) u,
      ];

  static bool _sameUrls(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void didUpdateWidget(covariant FallbackNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextUrls = _extractUrls(widget.urls);
    if (!_sameUrls(_urls, nextUrls)) {
      _urls = nextUrls;
      _i = 0;
      _lastResolvedUrl = null;
      _lastResolvedProvider = null;
    } else if (oldWidget.onImageResolved == null &&
        widget.onImageResolved != null) {
      _lastResolvedUrl = null;
      _lastResolvedProvider = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final urls = _urls;
    if (_i >= urls.length) return widget.fallback;

    final dpr = MediaQuery.devicePixelRatioOf(context);
    final w = widget.memWidth != null ? (widget.memWidth! * dpr).round() : null;
    final h = widget.memHeight != null ? (widget.memHeight! * dpr).round() : null;
    // Decode with ONE bound so the bitmap keeps its aspect ratio. Passing both
    // makes Flutter resize to exactly w×h (ResizeImagePolicy.exact), which
    // squashed backdrops and stretched logos. `cover` slots are bound by height
    // (posters, hero art and backdrops are at least as wide, relative to their
    // height, as the slots they fill); `contain` slots are bound by width.
    final byHeight = h != null && widget.fit == BoxFit.cover;
    final cacheWidth = byHeight ? null : w;
    final cacheHeight = byHeight ? h : (w == null ? h : null);
    final url = tmdbSized(urls[_i], forWidthPx: w ?? 1280);
    final placeholder = widget.placeholder ?? const ColoredBox(color: AppColors.surface2);
    final onResolved = widget.onImageResolved;

    return CachedNetworkImage(
      key: ValueKey(url),
      imageUrl: url,
      fit: widget.fit,
      alignment: widget.alignment,
      cacheManager: PixelImageCache.instance,
      memCacheWidth: cacheWidth,
      memCacheHeight: cacheHeight,
      // "low" avoids the expensive sampling pass for tiny poster slots
      filterQuality: FilterQuality.low,
      fadeInDuration: widget.fadeIn,
      imageBuilder: onResolved == null
          ? null
          : (_, imageProvider) {
              if (_lastResolvedUrl != url ||
                  _lastResolvedProvider != imageProvider) {
                _lastResolvedUrl = url;
                _lastResolvedProvider = imageProvider;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) widget.onImageResolved?.call(url, imageProvider);
                });
              }
              return Image(
                image: imageProvider,
                fit: widget.fit,
                alignment: widget.alignment,
                filterQuality: FilterQuality.low,
              );
            },
      // Static placeholder on purpose: an animated shimmer per loading poster
      // means dozens of live AnimationControllers during a fling — pure jank
      // on low-RAM phones. A flat tile costs nothing.
      placeholder: (_, __) => placeholder,
      errorWidget: (_, __, ___) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _i++);
        });
        return placeholder;
      },
    );
  }
}

/// Poster fallback rendered when images fail — mirrors the app icon look.
class PosterFallback extends StatelessWidget {
  const PosterFallback({super.key, required this.meta});
  final MetaModel meta;

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.iconGradient),
      padding: EdgeInsets.all(10.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            meta.type.toUpperCase(),
            style: AppText.rowHeading.copyWith(
              fontSize: 9.sp,
              fontWeight: FontWeight.w600,
              color: AppColors.accent,
              letterSpacing: 1,
            ),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              meta.name,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: AppText.rowHeading.copyWith(
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
                height: 1.2,
              ),
            ),
            if (meta.releaseInfo != null)
              Text(meta.releaseInfo!, style: AppText.heroMeta.copyWith(fontSize: 10.sp)),
          ]),
        ],
      ),
    );
  }
}

/// Figma: 113×170, radius 7, shadow 0 8 20 rgba(0,0,0,.4)
class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.meta,
    required this.onTap,
  });
  final MetaModel meta;
  final ValueChanged<MetaModel> onTap;

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);
    final radius = BorderRadius.circular(AppDimens.posterRadius);
    return Container(
      width: AppDimens.posterWidth,
      height: AppDimens.posterHeight,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: AppDimens.posterShadow,
        color: AppColors.surface2,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(fit: StackFit.expand, children: [
          FallbackNetworkImage(
            urls: [meta.poster, meta.posterFallback],
            memWidth: AppDimens.posterWidth,
            memHeight: AppDimens.posterHeight,
            fallback: PosterFallback(meta: meta),
          ),
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                onTap(meta);
              },
            ),
          ),
        ]),
      ),
    );
  }
}
