import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/responsive.dart';
import '../../../details/presentation/screens/detail_screen.dart';
import '../../../details/presentation/widgets/detail_widgets.dart';
import '../../../home/data/models/meta_model.dart';
import '../../../home/presentation/controllers/home_controller.dart';
import '../../../home/presentation/widgets/pixel_bottom_nav.dart';
import '../../../home/presentation/widgets/poster_card.dart';
import '../../../home/presentation/widgets/poster_row.dart';
import '../../../home/presentation/widgets/shimmer_loading.dart';
import '../../data/collection_catalog_resolver.dart';
import '../../data/collection_models.dart';
import '../controllers/collection_details_controller.dart';
import '../widgets/collection_row.dart';
import '../widgets/smooth_gif_image.dart';

const String _kCollectionDetailsDownloadsSvg =
    '<svg width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">'
    '<path d="M12 4V15M12 15L8.5 11.5M12 15L15.5 11.5" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" stroke="white" stroke-opacity="0.95"/>'
    '<path d="M4 19H20" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" stroke="white" stroke-opacity="0.95"/>'
    '</svg>';

/// Figma frame `151:21` ("Collections screen" detail view, `393×852`):
/// - Top `MainHeader` (`56px`): `36×36` Go Back button, `"Collections"` 30px Inter
///   Bold, and `24×24` Downloads action.
/// - Conditional `Movies` / `TV Shows` sliding selector (`46px` height, `11px`
///   side padding, `6px` gap, `#F6F6F3` active pill), shown only when both Movie
///   and TV Show rows exist and multiple rows are available.
/// - Selected collection `371×189` (`10px` radius) hero highlight card playing
///   the selected folder's animated GIF / artwork.
/// - Either a 3-column poster grid (when the active view resolves to a single
///   row) or vertical daily-shuffled `PosterRow` shelves beneath.
class CollectionDetailsScreen extends ConsumerStatefulWidget {
  const CollectionDetailsScreen({
    super.key,
    required this.collection,
    required this.folder,
  });

  final PremadeCollectionModel collection;
  final CollectionFolderModel folder;

  @override
  ConsumerState<CollectionDetailsScreen> createState() =>
      _CollectionDetailsScreenState();
}

class _CollectionDetailsScreenState
    extends ConsumerState<CollectionDetailsScreen>
    with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  final Set<String> _scheduledRowKeys = <String>{};

  CollectionDetailsArgs get _args =>
      (collection: widget.collection, folder: widget.folder);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      ref.read(collectionDetailsControllerProvider(_args).notifier).refreshIfDayChanged();
    }
  }

  void _scheduleRowLoad(String rowKey) {
    if (_scheduledRowKeys.contains(rowKey)) return;
    _scheduledRowKeys.add(rowKey);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduledRowKeys.remove(rowKey);
      if (!mounted) return;
      ref
          .read(collectionDetailsControllerProvider(_args).notifier)
          .ensureRowLoaded(rowKey);
    });
  }

  void _openMetaDetails(BuildContext context, MetaModel meta) {
    Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, __, ___) => DetailScreen(meta: meta),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: const Cubic(0.22, 1.0, 0.36, 1.0),
          ),
          child: child,
        ),
      ),
    );
  }

  void _showDownloadsStub(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Downloads are coming soon',
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
          backgroundColor: AppColors.collectionCardOuterBg,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.collectionCardBorder),
          ),
          duration: const Duration(milliseconds: 1400),
        ),
      );
  }

  void _selectTab(
    CollectionDetailsController controller,
    CollectionMediaTab tab,
  ) {
    controller.selectTab(tab);
    if (_scrollController.hasClients && _scrollController.offset > 0) {
      _scrollController.jumpTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);
    final state = ref.watch(collectionDetailsControllerProvider(_args));
    final controller =
        ref.read(collectionDetailsControllerProvider(_args).notifier);
    final topInset = MediaQuery.paddingOf(context).top;
    final activeRows = state.activeRows;
    final topBarHeight = _CollectionDetailsTopBar.heightFor(
      topInset: topInset,
      showMediaTypeSelector: state.showMediaTypeSelector,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: PixelBottomNav(
        current: PixelTab.collections,
        onChanged: (tab) {
          ref.read(activeTabProvider.notifier).state = tab;
          Navigator.of(context).popUntil((route) => route.isFirst);
        },
      ),
      body: RefreshIndicator(
        edgeOffset: topBarHeight,
        color: AppColors.accent,
        backgroundColor: AppColors.collectionCardOuterBg,
        onRefresh: controller.refresh,
        child: CustomScrollView(
          controller: _scrollController,
          scrollCacheExtent: const ScrollCacheExtent.pixels(1100),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              floating: true,
              snap: true,
              pinned: false,
              primary: false,
              toolbarHeight: topBarHeight,
              collapsedHeight: topBarHeight,
              expandedHeight: topBarHeight,
              automaticallyImplyLeading: false,
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              shadowColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              flexibleSpace: ClipRect(
                child: OverflowBox(
                  maxHeight: topBarHeight,
                  minHeight: topBarHeight,
                  alignment: Alignment.topCenter,
                  child: _CollectionDetailsTopBar(
                    topInset: topInset,
                    showMediaTypeSelector: state.showMediaTypeSelector,
                    selectedTab: state.selectedTab,
                    onBack: () => Navigator.of(context).maybePop(),
                    onDownloads: () => _showDownloadsStub(context),
                    onSelectTab: (tab) => _selectTab(controller, tab),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(child: SizedBox(height: 8.h)),
            SliverToBoxAdapter(
              child: _SelectedCollectionHeroCard(
                collectionTitle: widget.collection.title,
                folder: widget.folder,
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(height: AppDimens.afterCollectionsHeroGap),
            ),
            if (activeRows.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _CollectionEmptyState(
                  folderTitle: widget.folder.title,
                  canSwitchTab: state.selectedTab == CollectionMediaTab.movies
                      ? state.visibleSeriesRows.isNotEmpty
                      : state.visibleMovieRows.isNotEmpty,
                  alternateTabLabel:
                      state.selectedTab == CollectionMediaTab.movies
                          ? 'Switch to TV Shows'
                          : 'Switch to Movies',
                  onAlternateTab: () => _selectTab(
                    controller,
                    state.selectedTab == CollectionMediaTab.movies
                        ? CollectionMediaTab.tvShows
                        : CollectionMediaTab.movies,
                  ),
                  onRefresh: controller.refresh,
                ),
              )
            else if (state.isSingleRowGridMode)
              ..._buildSingleRowGridSlivers(
                context,
                row: activeRows.first,
                controller: controller,
              )
            else
              _buildMultiRowSliverList(
                context,
                rows: activeRows,
                controller: controller,
              ),
            SliverToBoxAdapter(
              child: SizedBox(height: AppDimens.navHeight + 36.h),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildSingleRowGridSlivers(
    BuildContext context, {
    required CollectionRowState row,
    required CollectionDetailsController controller,
  }) {
    if (row.status == ShelfStatus.idle) {
      _scheduleRowLoad(row.config.key);
    }

    final headingSliver = SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppDimens.screenPadding,
          0,
          AppDimens.screenPadding,
          AppDimens.rowGap,
        ),
        child: Text(
          row.config.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.rowHeading,
        ),
      ),
    );

    switch (row.status) {
      case ShelfStatus.idle:
      case ShelfStatus.loading:
        return [
          headingSliver,
          SliverPadding(
            padding: EdgeInsets.symmetric(
              horizontal: AppDimens.screenPadding,
            ),
            sliver: const _CollectionGridSkeleton(),
          ),
        ];
      case ShelfStatus.error:
        return [
          headingSliver,
          SliverPadding(
            padding: EdgeInsets.symmetric(
              horizontal: AppDimens.screenPadding,
            ),
            sliver: SliverToBoxAdapter(
              child: _CollectionRowErrorCard(
                title: row.config.title,
                message: row.error,
                onRetry: () => controller.retryRow(row.config.key),
              ),
            ),
          ),
        ];
      case ShelfStatus.loaded:
        if (row.items.isEmpty) {
          return [
            headingSliver,
            SliverFillRemaining(
              hasScrollBody: false,
              child: _CollectionEmptyState(
                folderTitle: row.config.title,
                canSwitchTab: false,
                alternateTabLabel: '',
                onAlternateTab: () {},
                onRefresh: controller.refresh,
              ),
            ),
          ];
        }
        return [
          headingSliver,
          SliverPadding(
            padding: EdgeInsets.symmetric(
              horizontal: AppDimens.screenPadding,
            ),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: AppDimens.posterGap,
                mainAxisSpacing: AppDimens.posterGap,
                childAspectRatio: AppDimens.posterWidth / AppDimens.posterHeight,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final meta = row.items[index];
                  return FittedBox(
                    fit: BoxFit.contain,
                    alignment: Alignment.center,
                    child: SizedBox(
                      width: AppDimens.posterWidth,
                      height: AppDimens.posterHeight,
                      child: PosterCard(
                        meta: meta,
                        onTap: (m) => _openMetaDetails(context, m),
                      ),
                    ),
                  );
                },
                childCount: row.items.length,
              ),
            ),
          ),
        ];
    }
  }

  Widget _buildMultiRowSliverList(
    BuildContext context, {
    required List<CollectionRowState> rows,
    required CollectionDetailsController controller,
  }) {
    return SliverList.builder(
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        switch (row.status) {
          case ShelfStatus.idle:
            _scheduleRowLoad(row.config.key);
            return Padding(
              padding: EdgeInsets.only(bottom: AppDimens.rowSpacing),
              child: ShelfSkeleton(inset: AppDimens.screenPadding),
            );
          case ShelfStatus.loading:
            return Padding(
              padding: EdgeInsets.only(bottom: AppDimens.rowSpacing),
              child: ShelfSkeleton(inset: AppDimens.screenPadding),
            );
          case ShelfStatus.error:
            return Padding(
              padding: EdgeInsets.fromLTRB(
                AppDimens.screenPadding,
                0,
                AppDimens.screenPadding,
                AppDimens.rowSpacing,
              ),
              child: _CollectionRowErrorCard(
                title: row.config.title,
                message: row.error,
                onRetry: () => controller.retryRow(row.config.key),
              ),
            );
          case ShelfStatus.loaded:
            if (row.items.isEmpty) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: EdgeInsets.only(bottom: AppDimens.rowSpacing),
              child: PosterRow(
                title: row.config.title,
                metas: row.items,
                inset: AppDimens.screenPadding,
                onTapMeta: (meta) => _openMetaDetails(context, meta),
              ),
            );
        }
      },
    );
  }
}

/// Floating `TopNav`-style bar for `CollectionDetailsScreen`, unifying the
/// Collections header row and the conditional `Movies` / `TV Shows` pill selector
/// into one scrollable `SliverAppBar` unit matching `HomeScreen`.
class _CollectionDetailsTopBar extends StatelessWidget {
  const _CollectionDetailsTopBar({
    required this.topInset,
    required this.showMediaTypeSelector,
    required this.selectedTab,
    required this.onBack,
    required this.onDownloads,
    required this.onSelectTab,
  });

  final double topInset;
  final bool showMediaTypeSelector;
  final CollectionMediaTab selectedTab;
  final VoidCallback onBack;
  final VoidCallback onDownloads;
  final ValueChanged<CollectionMediaTab> onSelectTab;

  static double get _topPad => 8.h;
  static double get _bottomPadWithSelector => 14.h;
  static double get _bottomPadCompact => 10.h;

  static double heightFor({
    required double topInset,
    required bool showMediaTypeSelector,
  }) =>
      topInset +
      (showMediaTypeSelector
          ? AppDimens.topNavHeight
          : _topPad + AppDimens.headerH + _bottomPadCompact);

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);
    return Container(
      color: AppColors.background,
      padding: EdgeInsets.only(
        top: topInset + _topPad,
        bottom: showMediaTypeSelector ? _bottomPadWithSelector : _bottomPadCompact,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.only(
              left: AppDimens.rowLeft,
              right: AppDimens.rowLeft,
            ),
            child: SizedBox(
              height: AppDimens.headerH,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  DetailBackButton(onTap: onBack),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: Text(
                      'Collections',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: AppDimens.titleFontSize,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        height: 1.15,
                        letterSpacing: -0.7,
                      ),
                    ),
                  ),
                  SizedBox(width: 8.w),
                  _HeaderIconAction(
                    tooltip: 'Downloads',
                    onTap: onDownloads,
                    child: SvgPicture.string(
                      _kCollectionDetailsDownloadsSvg,
                      width: 24.r,
                      height: 24.r,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (showMediaTypeSelector) ...[
            SizedBox(height: AppDimens.headerGap),
            _CollectionMediaTypeSelector(
              selectedTab: selectedTab,
              onSelect: onSelectTab,
            ),
          ],
        ],
      ),
    );
  }
}

class _HeaderIconAction extends StatefulWidget {
  const _HeaderIconAction({
    required this.tooltip,
    required this.onTap,
    required this.child,
  });

  final String tooltip;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_HeaderIconAction> createState() => _HeaderIconActionState();
}

class _HeaderIconActionState extends State<_HeaderIconAction> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.tooltip,
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 160),
        curve: const Cubic(0.22, 1.0, 0.36, 1.0),
        child: SizedBox(
          width: 28,
          height: 28,
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkResponse(
              onTap: () {
                HapticFeedback.selectionClick();
                widget.onTap();
              },
              onHighlightChanged: (v) => setState(() => _pressed = v),
              focusColor: AppColors.textPrimary.withValues(alpha: 0.14),
              hoverColor: AppColors.textPrimary.withValues(alpha: 0.08),
              radius: 20,
              child: Center(child: widget.child),
            ),
          ),
        ),
      ),
    );
  }
}

/// Figma `Section - MediaTypeSelector` (`height: 46`, `top: 92`, side padding
/// `11px`, `6px` gap, `#F6F6F3` sliding selection pill with `15px` radius).
class _CollectionMediaTypeSelector extends StatelessWidget {
  const _CollectionMediaTypeSelector({
    required this.selectedTab,
    required this.onSelect,
  });

  final CollectionMediaTab selectedTab;
  final ValueChanged<CollectionMediaTab> onSelect;

  static double get _gap => AppDimens.chipGap;
  static double get _height => AppDimens.rowH;
  static double get _radius => AppDimens.navPillRadius;
  static const Color _activePillColor = Color(0xFFF6F6F3);
  static const Color _activeTextColor = Color(0xFF0F0F0F);
  static const Color _inactiveTextColor = Color(0xFFF6F6F3);
  static const Color _inactiveBgColor = Color(0x12FFFFFF); // ~0.07 alpha
  static const Color _inactiveBorderColor = Color(0x17FFFFFF); // ~0.09 alpha
  static const Curve _motionCurve = Cubic(0.22, 1.0, 0.36, 1.0);

  @override
  Widget build(BuildContext context) {
    final isSeries = selectedTab == CollectionMediaTab.tvShows;
    final gap = _gap;
    final radius = _radius;

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppDimens.rowLeft,
      ),
      child: SizedBox(
        height: _height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final pillWidth = (constraints.maxWidth - gap) / 2;
            final slideDx =
                pillWidth > 0 && isSeries ? (pillWidth + gap) / pillWidth : 0.0;

            return Stack(
              children: [
                // Static unselected glass shells underneath.
                Row(
                  children: [
                    Expanded(child: _buildInactiveShell()),
                    SizedBox(width: gap),
                    Expanded(child: _buildInactiveShell()),
                  ],
                ),
                // GPU-only Transform.translate sliding white indicator pill.
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: pillWidth > 0 ? pillWidth : 0,
                  child: AnimatedSlide(
                    offset: Offset(slideDx, 0),
                    duration: const Duration(milliseconds: 200),
                    curve: _motionCurve,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: _activePillColor,
                        borderRadius: BorderRadius.circular(radius),
                      ),
                    ),
                  ),
                ),
                // Interactive accessible labels above the sliding pill.
                Row(
                  children: [
                    Expanded(
                      child: _MediaTypeTabButton(
                        label: 'Movies',
                        selected: !isSeries,
                        activeTextColor: _activeTextColor,
                        inactiveTextColor: _inactiveTextColor,
                        radius: radius,
                        onTap: () => onSelect(CollectionMediaTab.movies),
                      ),
                    ),
                    SizedBox(width: gap),
                    Expanded(
                      child: _MediaTypeTabButton(
                        label: 'TV Shows',
                        selected: isSeries,
                        activeTextColor: _activeTextColor,
                        inactiveTextColor: _inactiveTextColor,
                        radius: radius,
                        onTap: () => onSelect(CollectionMediaTab.tvShows),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildInactiveShell() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _inactiveBgColor,
        borderRadius: BorderRadius.circular(_radius),
        border: Border.all(color: _inactiveBorderColor, width: 1),
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _MediaTypeTabButton extends StatefulWidget {
  const _MediaTypeTabButton({
    required this.label,
    required this.selected,
    required this.activeTextColor,
    required this.inactiveTextColor,
    required this.radius,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color activeTextColor;
  final Color inactiveTextColor;
  final double radius;
  final VoidCallback onTap;

  @override
  State<_MediaTypeTabButton> createState() => _MediaTypeTabButtonState();
}

class _MediaTypeTabButtonState extends State<_MediaTypeTabButton> {
  bool _pressed = false;
  bool _hovered = false;
  bool _focused = false;

  static const Curve _curve = Cubic(0.22, 1.0, 0.36, 1.0);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.label,
      child: FocusableActionDetector(
        onShowHoverHighlight: (v) => setState(() => _hovered = v),
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        child: AnimatedScale(
          scale: _pressed ? 0.98 : 1.0,
          duration: const Duration(milliseconds: 160),
          curve: _curve,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(widget.radius),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                widget.onTap();
              },
              onHighlightChanged: (v) => setState(() => _pressed = v),
              borderRadius: BorderRadius.circular(widget.radius),
              splashColor: Colors.transparent,
              highlightColor: AppColors.textPrimary.withValues(alpha: 0.06),
              child: Container(
                height: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(widget.radius),
                  border: _focused
                      ? Border.all(
                          color: AppColors.textPrimary.withValues(alpha: 0.72),
                          width: 2,
                        )
                      : (_hovered && !widget.selected
                          ? Border.all(
                              color:
                                  AppColors.textPrimary.withValues(alpha: 0.18),
                              width: 1,
                            )
                          : null),
                ),
                alignment: Alignment.center,
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 180),
                  curve: _curve,
                  style: GoogleFonts.inter(
                    fontSize: AppDimens.chipFontSize,
                    fontWeight: FontWeight.w600,
                    color: widget.selected
                        ? widget.activeTextColor
                        : widget.inactiveTextColor,
                    letterSpacing: -0.2,
                  ),
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Non-interactive `371×189` (`10px` radius) selected collection highlight card
/// showing the folder's animated GIF seamlessly faded over its static artwork.
class _SelectedCollectionHeroCard extends StatefulWidget {
  const _SelectedCollectionHeroCard({
    required this.collectionTitle,
    required this.folder,
  });

  final String collectionTitle;
  final CollectionFolderModel folder;

  @override
  State<_SelectedCollectionHeroCard> createState() =>
      _SelectedCollectionHeroCardState();
}

class _SelectedCollectionHeroCardState
    extends State<_SelectedCollectionHeroCard> {
  bool _gifReady = false;
  bool _gifFailed = false;

  @override
  void didUpdateWidget(covariant _SelectedCollectionHeroCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.folder.focusGifUrl != widget.folder.focusGifUrl) {
      _gifReady = false;
      _gifFailed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final folder = widget.folder;
    final gifUrl = folder.focusGifUrl;
    final hasGif = !_gifFailed && gifUrl != null && gifUrl.isNotEmpty;
    final staticUrls = <String>[
      if (folder.heroBackdropUrl != null && folder.heroBackdropUrl!.isNotEmpty)
        folder.heroBackdropUrl!,
      if (folder.coverImageUrl != null && folder.coverImageUrl!.isNotEmpty)
        folder.coverImageUrl!,
    ];
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final decodeWidth =
        ((MediaQuery.sizeOf(context).width -
                    AppDimens.collectionsScreenPadding * 2) *
                dpr)
            .round()
            .clamp(400, 960);

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppDimens.collectionsScreenPadding,
      ),
      child: Semantics(
        image: true,
        label: '${folder.title} collection highlight',
        child: Container(
          height: AppDimens.collectionsHeroHeight,
          decoration: BoxDecoration(
            color: AppColors.collectionCardOuterBg,
            borderRadius: BorderRadius.circular(AppDimens.collectionsHeroRadius),
            border: Border.all(color: AppColors.collectionCardBorder, width: 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: ClipRRect(
            borderRadius:
                BorderRadius.circular(AppDimens.collectionsHeroRadius - 1),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (staticUrls.isNotEmpty)
                  FallbackNetworkImage(
                    urls: staticUrls,
                    fit: BoxFit.cover,
                    memWidth: decodeWidth.toDouble(),
                    fallback: CollectionFolderFallback(
                      folder: folder,
                      collectionTitle: widget.collectionTitle,
                    ),
                  )
                else
                  CollectionFolderFallback(
                    folder: folder,
                    collectionTitle: widget.collectionTitle,
                  ),
                if (hasGif)
                  AnimatedOpacity(
                    opacity: _gifReady ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 220),
                    curve: const Cubic(0.22, 1.0, 0.36, 1.0),
                    child: SmoothGifImage(
                      url: gifUrl,
                      fit: BoxFit.cover,
                      targetWidthPx: decodeWidth,
                      loop: true,
                      onFirstFrame: () {
                        if (mounted && !_gifReady) {
                          setState(() => _gifReady = true);
                        }
                      },
                      onError: () {
                        if (mounted) {
                          setState(() {
                            _gifFailed = true;
                            _gifReady = false;
                          });
                        }
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

class _CollectionGridSkeleton extends StatelessWidget {
  const _CollectionGridSkeleton();

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);
    return SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: AppDimens.posterGap,
        mainAxisSpacing: AppDimens.posterGap,
        childAspectRatio: AppDimens.posterWidth / AppDimens.posterHeight,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) => PixelShimmer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.all(
                Radius.circular(AppDimens.posterRadius),
              ),
            ),
            child: const SizedBox.expand(),
          ),
        ),
        childCount: 9,
      ),
    );
  }
}

class _CollectionRowErrorCard extends StatelessWidget {
  const _CollectionRowErrorCard({
    required this.title,
    required this.onRetry,
    this.message,
  });

  final String title;
  final String? message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.collectionCardOuterBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.collectionCardBorder, width: 1),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.wifi_off_rounded,
            size: 20,
            color: AppColors.textMuted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Could not load $title',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Tap retry to fetch this row again.',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _ActionPillButton(label: 'Retry', onPressed: onRetry),
        ],
      ),
    );
  }
}

class _CollectionEmptyState extends StatelessWidget {
  const _CollectionEmptyState({
    required this.folderTitle,
    required this.canSwitchTab,
    required this.alternateTabLabel,
    required this.onAlternateTab,
    required this.onRefresh,
  });

  final String folderTitle;
  final bool canSwitchTab;
  final String alternateTabLabel;
  final VoidCallback onAlternateTab;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.movie_filter_outlined,
                size: 32,
                color: AppColors.textMuted,
              ),
              const SizedBox(height: 12),
              Text(
                'No qualifying shelves in $folderTitle',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.25,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Rows with fewer than 20 titles are hidden automatically. Try switching media type or refreshing.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  height: 1.5,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _ActionPillButton(label: 'Refresh', onPressed: onRefresh),
                  if (canSwitchTab)
                    _ActionPillButton(
                      label: alternateTabLabel,
                      onPressed: onAlternateTab,
                      subtle: true,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionPillButton extends StatefulWidget {
  const _ActionPillButton({
    required this.label,
    required this.onPressed,
    this.subtle = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool subtle;

  @override
  State<_ActionPillButton> createState() => _ActionPillButtonState();
}

class _ActionPillButtonState extends State<_ActionPillButton> {
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 160),
        curve: const Cubic(0.22, 1.0, 0.36, 1.0),
        child: Material(
          color: widget.subtle
              ? AppColors.collectionCardOuterBg
              : AppColors.textPrimary,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              widget.onPressed();
            },
            onHighlightChanged: (v) => setState(() => _pressed = v),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _focused
                      ? AppColors.accent
                      : (widget.subtle
                          ? AppColors.collectionCardBorder
                          : Colors.transparent),
                  width: _focused ? 2 : 1,
                ),
              ),
              child: Text(
                widget.label,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: widget.subtle
                      ? AppColors.textPrimary
                      : AppColors.background,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
