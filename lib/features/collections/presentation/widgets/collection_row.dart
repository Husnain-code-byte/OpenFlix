import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/perf/snap_physics.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/responsive.dart';
import '../../../home/presentation/widgets/pixel_bottom_nav.dart';
import '../../../home/presentation/widgets/poster_card.dart';
import '../../data/collection_models.dart';
import 'smooth_gif_image.dart';

typedef CollectionFolderTapCallback = void Function(
  PremadeCollectionModel collection,
  CollectionFolderModel folder,
);

/// Horizontal landscape collection row matching Figma frame `151:21`
/// (`140px` total height: 15sp Inter Medium heading + 10px gap + 192×112 cards).
class CollectionRow extends StatefulWidget {
  const CollectionRow({
    super.key,
    required this.collection,
    required this.onTapFolder,
    double? inset,
  }) : _inset = inset;

  final PremadeCollectionModel collection;
  final CollectionFolderTapCallback onTapFolder;
  final double? _inset;

  double get inset => _inset ?? AppDimens.collectionsScreenPadding;

  @override
  State<CollectionRow> createState() => _CollectionRowState();
}

class _CollectionRowState extends State<CollectionRow> {
  final ScrollController _scrollController = ScrollController();
  ProviderSubscription<PixelTab>? _tabSub;

  void _resetScroll() {
    if (_scrollController.hasClients && _scrollController.offset != 0.0) {
      _scrollController.jumpTo(0.0);
    }
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
            if (prev != null && prev != next) _resetScroll();
          },
        );
      } catch (_) {
        // Standalone widget test without a ProviderScope ancestor.
      }
    }
  }

  @override
  void didUpdateWidget(covariant CollectionRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.collection.id != widget.collection.id) {
      _resetScroll();
    }
  }

  @override
  void dispose() {
    _tabSub?.close();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);
    final folders = widget.collection.folders;
    final effectiveInset = widget.inset;
    final stride = AppDimens.collectionCardStride;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: effectiveInset),
          child: Text(
            widget.collection.title,
            style: GoogleFonts.inter(
              fontSize: 15.sp,
              fontWeight: FontWeight.w500,
              color: AppColors.rowHeading,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        SizedBox(height: AppDimens.rowGap),
        SizedBox(
          height: AppDimens.collectionCardHeight,
          child: ListView.builder(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            physics: PosterSnapPhysics(
              itemExtent: stride,
            ),
            itemExtent: stride,
            padding: EdgeInsets.symmetric(horizontal: effectiveInset),
            addAutomaticKeepAlives: false,
            addSemanticIndexes: false,
            scrollCacheExtent: const ScrollCacheExtent.pixels(0),
            itemCount: folders.length,
            itemBuilder: (_, i) => Padding(
              padding: EdgeInsets.only(right: AppDimens.posterGap),
              child: CollectionFolderCard(
                folder: folders[i],
                collectionTitle: widget.collection.title,
                onTap: () => widget.onTapFolder(widget.collection, folders[i]),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 192×112 landscape collection card matching Figma `151:21`
/// (`border-radius: 8px`, `border: 1px solid #262626`, `#171717` frame, `#262626` inner bg).
class CollectionFolderCard extends StatefulWidget {
  const CollectionFolderCard({
    super.key,
    required this.folder,
    required this.collectionTitle,
    required this.onTap,
  });

  final CollectionFolderModel folder;
  final String collectionTitle;
  final VoidCallback onTap;

  @override
  State<CollectionFolderCard> createState() => _CollectionFolderCardState();
}

class _CollectionFolderCardState extends State<CollectionFolderCard> {
  bool _gifReady = false;
  bool _gifFailed = false;

  @override
  void didUpdateWidget(covariant CollectionFolderCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.folder.focusGifUrl != widget.folder.focusGifUrl ||
        oldWidget.folder.focusGifEnabled != widget.folder.focusGifEnabled) {
      _gifReady = false;
      _gifFailed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final folder = widget.folder;
    final coverUrl = folder.coverImageUrl;
    final hasCover = coverUrl != null && coverUrl.isNotEmpty;
    final gifUrl = folder.focusGifUrl;
    final hasGif = !_gifFailed && gifUrl != null && gifUrl.isNotEmpty;
    final showStaticBase = !hasGif || !_gifReady;

    return RepaintBoundary(
      child: Container(
        width: AppDimens.collectionCardWidth,
        height: AppDimens.collectionCardHeight,
        padding: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: AppColors.collectionCardOuterBg,
          borderRadius: BorderRadius.circular(AppDimens.collectionCardRadius),
          border: Border.all(color: AppColors.collectionCardBorder, width: 1),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppDimens.collectionCardRadius - 1),
          child: ColoredBox(
            color: AppColors.collectionCardInnerBg,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (showStaticBase)
                  if (hasCover)
                    Stack(
                      fit: StackFit.expand,
                      children: [
                        FallbackNetworkImage(
                          urls: [coverUrl],
                          memWidth: AppDimens.collectionCardWidth,
                          memHeight: AppDimens.collectionCardHeight,
                          placeholder: const ColoredBox(
                            color: AppColors.collectionCardInnerBg,
                          ),
                          fallback: CollectionFolderFallback(
                            folder: folder,
                            collectionTitle: widget.collectionTitle,
                          ),
                        ),
                        if (coverUrl.contains('image.tmdb.org') ||
                            !folder.hideTitle)
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: IgnorePointer(
                              child: Container(
                                padding: EdgeInsets.fromLTRB(
                                  10.w,
                                  18.h,
                                  10.w,
                                  8.h,
                                ),
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Color(0x00000000),
                                      Color(0xB8000000),
                                      Color(0xE6000000),
                                    ],
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    if (folder.coverEmoji != null) ...[
                                      Text(
                                        folder.coverEmoji!,
                                        style: TextStyle(fontSize: 13.sp),
                                      ),
                                      SizedBox(width: 5.w),
                                    ],
                                    Expanded(
                                      child: Text(
                                        folder.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.inter(
                                          fontSize: 12.5.sp,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textPrimary,
                                          letterSpacing: -0.2,
                                          shadows: const [
                                            Shadow(
                                              color: Color(0xCC000000),
                                              blurRadius: 6,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    )
                  else
                    CollectionFolderFallback(
                      folder: folder,
                      collectionTitle: widget.collectionTitle,
                    ),
                if (hasGif)
                  SmoothGifImage(
                    key: ValueKey('smooth_card_$gifUrl'),
                    url: gifUrl,
                    fit: BoxFit.cover,
                    targetWidthPx: 384,
                    loop: true,
                    onFirstFrame: () {
                      if (mounted && !_gifReady) {
                        setState(() => _gifReady = true);
                      }
                    },
                    onError: () {
                      if (mounted) {
                        setState(() {
                          _gifReady = false;
                          _gifFailed = true;
                        });
                      }
                    },
                  ),
                Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      widget.onTap();
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Fallback card rendered when collection artwork fails or is unavailable.
class CollectionFolderFallback extends StatelessWidget {
  const CollectionFolderFallback({
    super.key,
    required this.folder,
    required this.collectionTitle,
  });

  final CollectionFolderModel folder;
  final String collectionTitle;

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
            collectionTitle.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.rowHeading.copyWith(
              fontSize: 9.sp,
              fontWeight: FontWeight.w600,
              color: AppColors.accent,
              letterSpacing: 1,
            ),
          ),
          Row(
            children: [
              if (folder.coverEmoji != null) ...[
                Text(
                  folder.coverEmoji!,
                  style: TextStyle(fontSize: 18.sp),
                ),
                SizedBox(width: 6.w),
              ],
              Expanded(
                child: Text(
                  folder.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.rowHeading.copyWith(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
