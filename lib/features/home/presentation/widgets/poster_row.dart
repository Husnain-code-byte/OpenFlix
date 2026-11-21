import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/perf/snap_physics.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/responsive.dart';
import '../../data/models/meta_model.dart';
import '../controllers/home_controller.dart';
import 'pixel_bottom_nav.dart';
import 'poster_card.dart';

/// The home screen's content row (Figma "Content row"): the heading in
/// [AppText.rowHeading], a 10px gap, then a snap-scrolling rail of 113×170
/// [PosterCard]s (radius 7, same shadow) spaced 8px apart.
///
/// The home shelves and the details screen's "More like this" both render this
/// widget, so the two rows can never drift apart. [inset] is the row's leading
/// gutter: 8 on home (the page gutter) and 16 on the details screen (its
/// content gutter, so the heading lines up with the rest of that screen).
class PosterRow extends StatefulWidget {
  const PosterRow({
    super.key,
    required this.title,
    required this.metas,
    required this.onTapMeta,
    double? inset,
  }) : _inset = inset;

  final String title;
  final List<MetaModel> metas;
  final ValueChanged<MetaModel> onTapMeta;
  final double? _inset;

  double get inset => _inset ?? AppDimens.screenPadding;

  @override
  State<PosterRow> createState() => _PosterRowState();
}

class _PosterRowState extends State<PosterRow> {
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
  void didUpdateWidget(covariant PosterRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.title != widget.title) {
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
    final effectiveInset = widget.inset;
    final stride = AppDimens.posterStride;
    final shadowPad = 12.h;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: effectiveInset),
          child: Text(
            widget.title,
            style: AppText.rowHeading,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        SizedBox(height: AppDimens.rowGap),
        SizedBox(
          // +12.h below the posters leaves room for their 0 8 20 shadow.
          height: AppDimens.posterHeight + shadowPad,
          child: ListView.builder(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            physics: PosterSnapPhysics(itemExtent: stride),
            itemExtent: stride,
            padding: EdgeInsets.fromLTRB(effectiveInset, 0, effectiveInset, shadowPad),
            addAutomaticKeepAlives: false,
            addSemanticIndexes: false,
            cacheExtent: stride * 2,
            itemCount: widget.metas.length,
            itemBuilder: (_, i) => Padding(
              padding: EdgeInsets.only(right: AppDimens.posterGap),
              child: PosterCard(meta: widget.metas[i], onTap: widget.onTapMeta),
            ),
          ),
        ),
      ],
    );
  }
}
