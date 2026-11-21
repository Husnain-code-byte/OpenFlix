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
import '../../../home/presentation/widgets/poster_row.dart';
import '../../../home/presentation/widgets/shimmer_loading.dart';
import '../controllers/my_list_controller.dart';

const String _kDownloadsIconSvg =
    '<svg width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">'
    '<path d="M12 4V15M12 15L8.5 11.5M12 15L15.5 11.5" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" stroke="white" stroke-opacity="0.95"/>'
    '<path d="M4 19H20" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" stroke="white" stroke-opacity="0.95"/>'
    '</svg>';

/// My List screen modeled on Figma frame `116:23` ("Html → Body → Main - Mobile Device Frame Wrap"):
/// - `MainHeader` (56px, padding `12px 16px 8px 16px`): "My List" 30px bold + Downloads icon.
/// - First horizontal [PosterRow] for saved Movies ("Movies").
/// - Second horizontal [PosterRow] for saved TV Shows ("TV Shows").
/// - Third horizontal [PosterRow] for saved Anime ("Anime").
/// - Shares the exact row heading style ([AppText.rowHeading]), 10px heading gap
///   ([AppDimens.rowGap]), 113×170 [PosterCard] geometry (radius 7, 8px poster gap),
///   12px row spacing ([AppDimens.rowSpacing]), and Better Poster (`btttr.cc`) artwork.
class MyListScreen extends ConsumerStatefulWidget {
  const MyListScreen({super.key});

  @override
  ConsumerState<MyListScreen> createState() => _MyListScreenState();
}

class _MyListScreenState extends ConsumerState<MyListScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<PixelTab>(activeTabProvider, (prev, next) {
      if (prev != next && next == PixelTab.myList && _scrollController.hasClients) {
        _scrollController.jumpTo(0.0);
      }
    });
    final state = ref.watch(myListControllerProvider);
    final notifier = ref.read(myListControllerProvider.notifier);

    return SavedCollectionScreenView(
      title: 'My List',
      keyPrefix: 'my_list',
      state: state,
      onRefresh: notifier.refresh,
      scrollController: _scrollController,
      emptyIconSvg: kDetailBookmarkSvg,
      emptyMoviesSubtitle: 'Movies you add to My List will appear here.',
      emptyTvShowsSubtitle: 'TV shows you add to My List will appear here.',
      emptyAnimeSubtitle: 'Anime you add to My List will appear here.',
    );
  }
}

/// Shared 3-row saved collection view used by both [MyListScreen] and [LikedScreen].
class SavedCollectionScreenView extends ConsumerWidget {
  const SavedCollectionScreenView({
    super.key,
    required this.title,
    required this.keyPrefix,
    required this.state,
    required this.onRefresh,
    required this.emptyIconSvg,
    required this.emptyMoviesSubtitle,
    required this.emptyTvShowsSubtitle,
    required this.emptyAnimeSubtitle,
    this.scrollController,
    this.onBack,
  });

  final String title;
  final String keyPrefix;
  final MyListState state;
  final Future<void> Function() onRefresh;
  final String emptyIconSvg;
  final String emptyMoviesSubtitle;
  final String emptyTvShowsSubtitle;
  final String emptyAnimeSubtitle;
  final ScrollController? scrollController;
  final VoidCallback? onBack;

  void _stub(BuildContext context, String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: AppText.chip),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF16181C),
        shape: const StadiumBorder(),
      ));
  }

  void _openDetails(BuildContext context, MetaModel m) {
    Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (_, __, ___) => DetailScreen(meta: m),
        transitionsBuilder: (_, animation, __, child) => FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        ),
      ),
    );
  }

  void _browseCategory(WidgetRef ref, HomeFilter filter) {
    HapticFeedback.selectionClick();
    onBack?.call();
    ref.read(homeFilterProvider.notifier).state = filter;
    ref.read(activeTabProvider.notifier).state = PixelTab.home;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Responsive.init(context);
    final topInset = MediaQuery.paddingOf(context).top;

    return ColoredBox(
      color: AppColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: topInset),
          _SavedCollectionMainHeader(
            title: title,
            onBack: onBack,
            onDownloads: () => _stub(context, 'Downloads are coming soon'),
          ),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.accent,
              backgroundColor: const Color(0xFF16181C),
              onRefresh: onRefresh,
              child: _buildBody(context, ref),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref) {
    if (state.isLoading && state.items.isEmpty) {
      return ListView(
        padding: EdgeInsets.only(top: 16.h, bottom: 24.h),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: AppDimens.rowSpacing),
            child: const ShelfSkeleton(titleWidth: 64),
          ),
          Padding(
            padding: EdgeInsets.only(bottom: AppDimens.rowSpacing),
            child: const ShelfSkeleton(titleWidth: 84),
          ),
          Padding(
            padding: EdgeInsets.only(bottom: AppDimens.rowSpacing),
            child: const ShelfSkeleton(titleWidth: 58),
          ),
        ],
      );
    }

    if (state.errorMessage != null && state.items.isEmpty) {
      return ListView(
        padding: EdgeInsets.only(top: 16.h, bottom: 24.h),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _SavedCollectionErrorTile(
            title: title,
            onRetry: onRefresh,
          ),
        ],
      );
    }

    final rows = [
      (
        key: '${keyPrefix}_movies_row',
        title: 'Movies',
        metas: state.movies,
        subtitle: emptyMoviesSubtitle,
        ctaLabel: 'Browse Movies',
        filter: HomeFilter.movies,
      ),
      (
        key: '${keyPrefix}_tv_shows_row',
        title: 'TV Shows',
        metas: state.tvShows,
        subtitle: emptyTvShowsSubtitle,
        ctaLabel: 'Browse TV Shows',
        filter: HomeFilter.tvShows,
      ),
      (
        key: '${keyPrefix}_anime_row',
        title: 'Anime',
        metas: state.anime,
        subtitle: emptyAnimeSubtitle,
        ctaLabel: 'Browse Anime',
        filter: HomeFilter.anime,
      ),
    ];

    return ListView(
      controller: scrollController,
      padding: EdgeInsets.only(top: 16.h, bottom: 24.h),
      scrollCacheExtent: const ScrollCacheExtent.pixels(900),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        for (final row in rows)
          Padding(
            padding: EdgeInsets.only(bottom: AppDimens.rowSpacing),
            child: row.metas.isNotEmpty
                ? PosterRow(
                    key: ValueKey<String>(row.key),
                    title: row.title,
                    metas: row.metas,
                    onTapMeta: (m) => _openDetails(context, m),
                  )
                : _EmptyCollectionRow(
                    title: row.title,
                    subtitle: row.subtitle,
                    ctaLabel: row.ctaLabel,
                    iconSvg: emptyIconSvg,
                    onBrowse: () => _browseCategory(ref, row.filter),
                  ),
          ),
      ],
    );
  }
}

/// Figma `Header - MainHeader` (`116:29`):
/// `height: 56px`, `padding: 12px 16px 8px 16px`, space-between.
class _SavedCollectionMainHeader extends StatelessWidget {
  const _SavedCollectionMainHeader({
    required this.title,
    required this.onDownloads,
    this.onBack,
  });

  final String title;
  final VoidCallback onDownloads;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 56.h,
        child: Padding(
          padding: EdgeInsets.fromLTRB(onBack != null ? 12.w : 16.w, 12.h, 16.w, 8.h),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (onBack != null) ...[
                DetailBackButton(onTap: onBack!),
                SizedBox(width: 8.w),
              ],
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 30.sp,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 36 / 30,
                    letterSpacing: -0.75,
                  ),
                ),
              ),
              SizedBox(width: 8.w),
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

/// Empty state for an individual collection shelf ("Movies", "TV Shows", or "Anime"),
/// preserving the exact row heading and 170px shelf geometry.
class _EmptyCollectionRow extends StatelessWidget {
  const _EmptyCollectionRow({
    required this.title,
    required this.subtitle,
    required this.ctaLabel,
    required this.iconSvg,
    required this.onBrowse,
  });

  final String title;
  final String subtitle;
  final String ctaLabel;
  final String iconSvg;
  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: AppDimens.screenPadding),
            child: Text(
              title,
              style: AppText.rowHeading,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          SizedBox(height: AppDimens.rowGap),
          Container(
            height: AppDimens.posterHeight,
            width: double.infinity,
            margin: EdgeInsets.symmetric(horizontal: AppDimens.screenPadding),
            padding: EdgeInsets.symmetric(horizontal: 24.w),
            decoration: BoxDecoration(
              color: const Color(0x05FFFFFF),
              border: Border.all(color: const Color(0x0FFFFFFF)),
              borderRadius: BorderRadius.circular(AppDimens.posterRadius),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SvgPicture.string(
                  iconSvg,
                  width: 22.r,
                  height: 22.r,
                ),
                SizedBox(height: 10.h),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.heroMeta.copyWith(
                    fontSize: 13.sp,
                    color: AppColors.textMuted,
                  ),
                ),
                SizedBox(height: 12.h),
                Material(
                  color: AppColors.navPillFill,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppDimens.navPillRadius),
                    side: const BorderSide(color: AppColors.navPillBorder),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: onBrowse,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                      child: Text(
                        ctaLabel,
                        style: AppText.chip.copyWith(fontSize: 13.sp),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
}

class _SavedCollectionErrorTile extends StatelessWidget {
  const _SavedCollectionErrorTile({
    required this.title,
    required this.onRetry,
  });

  final String title;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
        height: AppDimens.posterHeight,
        margin: EdgeInsets.symmetric(horizontal: AppDimens.screenPadding),
        decoration: BoxDecoration(
          color: const Color(0x05FFFFFF),
          border: Border.all(color: const Color(0x0FFFFFFF)),
          borderRadius: BorderRadius.circular(AppDimens.posterRadius),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "Couldn't load $title",
              style: AppText.heroMeta.copyWith(fontSize: 13.sp, color: AppColors.textMuted),
            ),
            SizedBox(height: 10.h),
            OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
}
