import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/responsive.dart';
import '../../../home/presentation/widgets/pixel_brand.dart';
import '../../../home/presentation/widgets/shimmer_loading.dart';
import '../../data/collection_models.dart';
import '../controllers/collections_controller.dart';
import '../widgets/collection_row.dart';
import '../widgets/collections_hero_banner.dart';
import 'collection_details_screen.dart';

const String _kDownloadsIconSvg =
    '<svg width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">'
    '<path d="M12 4V15M12 15L8.5 11.5M12 15L15.5 11.5" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" stroke="white" stroke-opacity="0.95"/>'
    '<path d="M4 19H20" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" stroke="white" stroke-opacity="0.95"/>'
    '</svg>';

/// Collections tab screen matching Figma frame `151:21` ("Collections screen", `393×852`):
/// - `MainHeader` (56px, padding `12px 16px 8px 16px`): "Collections" 30px bold + Downloads icon.
/// - `8px` top gap -> `371×189` (`radius: 10`) sequential OTT GIF highlight card (non-interactive).
/// - `17px` gap -> landscape `192×112` collection rows (`Streaming`, `Genres`, `Studios` by default).
class CollectionsScreen extends ConsumerStatefulWidget {
  const CollectionsScreen({super.key});

  @override
  ConsumerState<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends ConsumerState<CollectionsScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _showSelectionStub(BuildContext context, String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg, style: AppText.chip),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF16181C),
          shape: const StadiumBorder(),
        ),
      );
  }

  void _onTapFolder(
    BuildContext context,
    PremadeCollectionModel collection,
    CollectionFolderModel folder,
  ) {
    Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (_, __, ___) => CollectionDetailsScreen(
          collection: collection,
          folder: folder,
        ),
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

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);
    final state = ref.watch(collectionsControllerProvider);
    final controller = ref.read(collectionsControllerProvider.notifier);
    final topInset = MediaQuery.paddingOf(context).top;
    final headerTotalHeight = topInset + _CollectionsMainHeader.height;

    final headerSliver = SliverAppBar(
      floating: true,
      snap: true,
      pinned: false,
      primary: false,
      toolbarHeight: headerTotalHeight,
      collapsedHeight: headerTotalHeight,
      expandedHeight: headerTotalHeight,
      automaticallyImplyLeading: false,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      flexibleSpace: ClipRect(
        child: OverflowBox(
          maxHeight: headerTotalHeight,
          minHeight: headerTotalHeight,
          alignment: Alignment.topCenter,
          child: Container(
            color: AppColors.background,
            padding: EdgeInsets.only(top: topInset),
            child: _CollectionsMainHeader(
              onDownloads: () =>
                  _showSelectionStub(context, 'Downloads are coming soon'),
            ),
          ),
        ),
      ),
    );

    return ColoredBox(
      color: AppColors.background,
      child: RefreshIndicator(
        edgeOffset: headerTotalHeight,
        color: AppColors.accent,
        backgroundColor: const Color(0xFF16181C),
        onRefresh: () => controller.load(isRefresh: true),
        child: CustomScrollView(
          controller: _scrollController,
          scrollCacheExtent: const ScrollCacheExtent.pixels(1100),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            headerSliver,
            ...switch (state) {
              CollectionsLoading() => const [
                  SliverToBoxAdapter(child: CollectionsSkeleton()),
                ],
              CollectionsError(:final message) => [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _CollectionsErrorView(
                      message: message,
                      onRetry: controller.load,
                    ),
                  ),
                ],
              CollectionsReady(:final collections) when collections.isEmpty => [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _CollectionsEmptyView(onReload: controller.load),
                  ),
                ],
              CollectionsReady(:final heroItems, :final collections) => [
                  SliverToBoxAdapter(
                    child: SizedBox(height: AppDimens.collectionsHeroTopGap),
                  ),
                  SliverToBoxAdapter(
                    child: CollectionsHeroBanner(items: heroItems),
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(height: AppDimens.afterCollectionsHeroGap),
                  ),
                  SliverList.builder(
                    itemCount: collections.length,
                    itemBuilder: (_, i) {
                      final collection = collections[i];
                      return Padding(
                        padding: EdgeInsets.only(
                          bottom: AppDimens.collectionsRowSpacing,
                        ),
                        child: CollectionRow(
                          key: ValueKey('collection_row_${collection.id}'),
                          collection: collection,
                          onTapFolder: (col, folder) =>
                              _onTapFolder(context, col, folder),
                        ),
                      );
                    },
                  ),
                  SliverToBoxAdapter(
                    child: SizedBox(height: AppDimens.navHeight + 36.h),
                  ),
                ],
            },
          ],
        ),
      ),
    );
  }
}

/// Figma `MainHeader` (`151:70`): `height: 56px`, `padding: 12px 16px 8px 16px`.
class _CollectionsMainHeader extends StatelessWidget {
  const _CollectionsMainHeader({required this.onDownloads});

  static double get height => 56.h;

  final VoidCallback onDownloads;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 8.h),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Collections',
                style: GoogleFonts.inter(
                  fontSize: 30.sp,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  height: 36 / 30,
                  letterSpacing: -0.75,
                ),
              ),
              SizedBox(
                width: 24.r,
                height: 24.r,
                child: Material(
                  color: Colors.transparent,
                  child: InkResponse(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onDownloads();
                    },
                    radius: 20.r,
                    child: Center(
                      child: SvgPicture.string(
                        _kDownloadsIconSvg,
                        width: 24.r,
                        height: 24.r,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

/// Skeleton matching Figma `151:21`: 8px top gap -> 189px hero -> 17px gap -> 3 landscape rows.
class CollectionsSkeleton extends StatelessWidget {
  const CollectionsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: AppDimens.collectionsHeroTopGap),
          const CollectionsHeroSkeleton(),
          SizedBox(height: AppDimens.afterCollectionsHeroGap),
          const _CollectionRowSkeleton(titleWidth: 74),
          SizedBox(height: AppDimens.collectionsRowSpacing),
          const _CollectionRowSkeleton(titleWidth: 56),
          SizedBox(height: AppDimens.collectionsRowSpacing),
          const _CollectionRowSkeleton(titleWidth: 60),
        ],
      ),
    );
  }
}

/// 371×189 rounded highlight card shimmer (`radius: 10`, horizontal padding `11`).
class CollectionsHeroSkeleton extends StatelessWidget {
  const CollectionsHeroSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: AppDimens.collectionsScreenPadding,
      ),
      child: PixelShimmer(
        child: Container(
          width: double.infinity,
          height: AppDimens.collectionsHeroHeight,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppDimens.collectionsHeroRadius),
          ),
        ),
      ),
    );
  }
}

class _CollectionRowSkeleton extends StatelessWidget {
  const _CollectionRowSkeleton({required this.titleWidth});

  final double titleWidth;

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);
    return PixelShimmer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: AppDimens.collectionsScreenPadding,
            ),
            child: Container(
              width: titleWidth.w,
              height: 15.h,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(4.r),
              ),
            ),
          ),
          SizedBox(height: AppDimens.rowGap),
          SizedBox(
            height: AppDimens.collectionCardHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.symmetric(
                horizontal: AppDimens.collectionsScreenPadding,
              ),
              itemCount: 3,
              separatorBuilder: (_, __) =>
                  SizedBox(width: AppDimens.posterGap),
              itemBuilder: (_, __) => Container(
                width: AppDimens.collectionCardWidth,
                height: AppDimens.collectionCardHeight,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.circular(AppDimens.collectionCardRadius),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CollectionsEmptyView extends StatelessWidget {
  const _CollectionsEmptyView({required this.onReload});

  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.collections_bookmark_outlined,
              size: 56,
              color: AppColors.textMuted,
            ),
            const SizedBox(height: 16),
            Text(
              'No collections available',
              textAlign: TextAlign.center,
              style: AppText.pageTitle.copyWith(fontSize: 20),
            ),
            const SizedBox(height: 8),
            Text(
              'Premade collections could not be found. Try reloading to restore your rows.',
              textAlign: TextAlign.center,
              style: AppText.heroMeta.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: onReload,
              child: const Text('Reload'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CollectionsErrorView extends StatelessWidget {
  const _CollectionsErrorView({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const PixelAppIcon(size: 84),
            const SizedBox(height: 20),
            Text(
              "Couldn't load collections",
              textAlign: TextAlign.center,
              style: AppText.pageTitle.copyWith(fontSize: 20),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppText.heroMeta.copyWith(color: AppColors.textMuted),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
