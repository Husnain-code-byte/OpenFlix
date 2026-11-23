import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';


import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/responsive.dart';
import '../../data/models/manifest_model.dart';
import '../../data/models/meta_model.dart';
import '../controllers/home_controller.dart';
import 'poster_row.dart';
import 'shimmer_loading.dart';

/// One home shelf: a skeleton while loading, a retry tile on error, otherwise
/// the shared [PosterRow] (heading, 10px gap, 113×170 posters spaced 8px apart).
///
/// Watches ONLY its own entry in [shelvesProvider] — other shelves updating
/// never rebuild this row. Rows keep their state when scrolled off-screen
/// so no catalog is ever re-fetched.
class CatalogShelf extends ConsumerStatefulWidget {
  const CatalogShelf({
    super.key,
    required this.catalog,
    required this.onVisible,
    required this.onRetry,
    required this.onTapMeta,
  });

  final CatalogItemModel catalog;
  final VoidCallback onVisible;
  final VoidCallback onRetry;
  final ValueChanged<MetaModel> onTapMeta;

  @override
  ConsumerState<CatalogShelf> createState() => _CatalogShelfState();
}

class _CatalogShelfState extends ConsumerState<CatalogShelf> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  /// Guards against requesting the same load twice, and is reset as soon as the
  /// shelf leaves `idle` so a later reset (pull-to-refresh) re-triggers it.
  bool _requested = false;

  @override
  void initState() {
    super.initState();
    // Built lazily by the parent SliverList ⇒ being built ≈ near the viewport.
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onVisible());
  }

  /// A row's State outlives pull-to-refresh (keep-alive), so `initState` never
  /// fires again. Re-requesting here is what makes every row reload after a
  /// refresh instead of shimmering forever.
  void _ensureRequested(ShelfStatus status) {
    if (status != ShelfStatus.idle) {
      _requested = false;
      return;
    }
    if (_requested) return;
    _requested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onVisible();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    Responsive.init(context);
    final s = ref.watch(shelvesProvider.select((m) => m[widget.catalog.key])) ?? ShelfState(catalog: widget.catalog);
    _ensureRequested(s.status);

    if (s.metas.isEmpty) {
      // Never inject per-row error boxes into the feed: silently collapse
      // individual failed/empty rows; screen-level offline/failure state is
      // handled once by the parent screen when all primary rows fail.
      if (s.status == ShelfStatus.loaded || s.status == ShelfStatus.error) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: EdgeInsets.only(bottom: AppDimens.rowSpacing),
        child: ShelfSkeleton(titleWidth: (40 + s.catalog.name.length * 7).clamp(60, 220).toDouble()),
      );
    }

    return _buildLoaded(s);
  }

  Widget _buildLoaded(ShelfState s) {
    // Catalog names repeat across types ("For You", "Popular"), so the type is appended in the same style.
    final heading = '${s.catalog.name} · ${s.catalog.typeLabel}';

    return Padding(
      padding: EdgeInsets.only(bottom: AppDimens.rowSpacing),
      child: PosterRow(title: heading, metas: s.metas, onTapMeta: widget.onTapMeta),
    );
  }
}
