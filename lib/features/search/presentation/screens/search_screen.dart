import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/responsive.dart';
import '../../../details/presentation/screens/detail_screen.dart';
import '../../../home/data/models/meta_model.dart';
import '../../../home/presentation/controllers/home_controller.dart';
import '../../../home/presentation/widgets/catalog_shelf.dart';
import '../../../home/presentation/widgets/poster_row.dart';
import '../../../home/presentation/widgets/shimmer_loading.dart';
import '../controllers/search_controller.dart';

const String _kDownloadsIconSvg =
    '<svg width="24" height="24" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">'
    '<path d="M12 4V15M12 15L8.5 11.5M12 15L15.5 11.5" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" stroke="white" stroke-opacity="0.95"/>'
    '<path d="M4 19H20" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" stroke="white" stroke-opacity="0.95"/>'
    '</svg>';

const String _kSearchMagnifierSvg =
    '<svg width="20" height="20" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">'
    '<path d="M3.3335 9.16666C3.3335 12.3862 5.94732 15 9.16683 15C12.3863 15 15.0002 12.3862 15.0002 9.16666C15.0002 5.94716 12.3863 3.33333 9.16683 3.33333C5.94732 3.33333 3.3335 5.94716 3.3335 9.16666V9.16666" stroke-width="1.66667" stroke="#9CA3AF"/>'
    '<path d="M17.5 17.5L13.875 13.875" stroke-width="1.66667" stroke-linecap="round" stroke="#9CA3AF"/>'
    '</svg>';

const String _kClearSearchSvg =
    '<svg width="12" height="12" viewBox="0 0 12 12" fill="none" xmlns="http://www.w3.org/2000/svg">'
    '<path d="M9 3L3 9" stroke-width="1.25" stroke-linecap="round" stroke="#2B2B2B"/>'
    '<path d="M3 3L9 9" stroke-width="1.25" stroke-linecap="round" stroke="#2B2B2B"/>'
    '</svg>';

/// Figma frame `116:23` ("Html → Body → Main - Mobile Device Frame Wrap"):
/// - `MainHeader` (56px, padding `12px 16px 8px 16px`): "Search" 30px bold + Downloads icon.
/// - `Section - SearchBarContainer` (60px, padding `8px 16px`): 44px `#2B2B2B` pill (radius 12)
///   with 20×20 `#9CA3AF` magnifier icon, 17px white query input, and 20×20 `#6A6A6A` clear button.
/// - Multi-source horizontal `PosterRow`s combining all search-capable installed addons
///   and the user's TMDB API key (`TMDB · Movies` and `TMDB · Series`).
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _textController;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    final initialQuery = ref.read(searchControllerProvider).query;
    _textController = TextEditingController(text: initialQuery);
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

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
    _focusNode.unfocus();
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

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);
    final searchState = ref.watch(searchControllerProvider);
    final searchNotifier = ref.read(searchControllerProvider.notifier);

    if (_textController.text != searchState.query) {
      _textController.value = TextEditingValue(
        text: searchState.query,
        selection: TextSelection.collapsed(offset: searchState.query.length),
      );
    }

    final topInset = MediaQuery.paddingOf(context).top;

    return ColoredBox(
      color: AppColors.background,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: topInset),
          _SearchMainHeader(
            onDownloads: () => _stub(context, 'Downloads are coming soon'),
          ),
          _SearchBarSection(
            controller: _textController,
            focusNode: _focusNode,
            hasText: searchState.query.isNotEmpty,
            onChanged: searchNotifier.setQuery,
            onSubmitted: searchNotifier.submitSearch,
            onClear: () {
              HapticFeedback.selectionClick();
              _textController.clear();
              searchNotifier.clearQuery();
            },
          ),
          Expanded(
            child: searchState.hasActiveQuery
                ? _ActiveSearchResultsView(
                    state: searchState,
                    onTapMeta: (m) => _openDetails(context, m),
                  )
                : _DiscoveryShelvesView(
                    onTapMeta: (m) => _openDetails(context, m),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Figma `Header - MainHeader` (`116:29`):
/// `height: 56px`, `padding: 12px 16px 8px 16px`, space-between.
class _SearchMainHeader extends StatelessWidget {
  const _SearchMainHeader({required this.onDownloads});

  final VoidCallback onDownloads;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 56.h,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 8.h),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                'Search',
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

/// Figma `Section - SearchBarContainer` (`116:37`):
/// `height: 60px`, `padding: 8px 16px`, inner pill `height: 44px`, `padding: 0 12px`,
/// `borderRadius: 12px`, `background: #2B2B2B`.
class _SearchBarSection extends StatelessWidget {
  const _SearchBarSection({
    required this.controller,
    required this.focusNode,
    required this.hasText,
    required this.onChanged,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool hasText;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final inputStyle = GoogleFonts.inter(
      fontSize: 17.sp,
      fontWeight: FontWeight.w400,
      color: Colors.white,
      height: 25.5 / 17,
      letterSpacing: -0.425,
    );

    final hintStyle = GoogleFonts.inter(
      fontSize: 17.sp,
      fontWeight: FontWeight.w400,
      color: const Color(0xFF9CA3AF),
      height: 25.5 / 17,
      letterSpacing: -0.425,
    );

    return SizedBox(
      height: 60.h,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
        child: Container(
          height: 44.h,
          padding: EdgeInsets.symmetric(horizontal: 12.w),
          decoration: BoxDecoration(
            color: const Color(0xFF2B2B2B),
            borderRadius: BorderRadius.circular(12.r),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Padding(
                padding: EdgeInsets.only(right: 10.w),
                child: SvgPicture.string(
                  _kSearchMagnifierSvg,
                  width: 20.r,
                  height: 20.r,
                ),
              ),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  onChanged: onChanged,
                  onSubmitted: onSubmitted,
                  style: inputStyle,
                  cursorColor: Colors.white,
                  cursorWidth: 2.0,
                  cursorHeight: 19.55.sp,
                  cursorRadius: const Radius.circular(1),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Search movies, series...',
                    hintStyle: hintStyle,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              if (hasText)
                Padding(
                  padding: EdgeInsets.only(left: 6.w),
                  child: GestureDetector(
                    onTap: onClear,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: 20.r,
                      height: 20.r,
                      decoration: const BoxDecoration(
                        color: Color(0xFF6A6A6A),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: SvgPicture.string(
                        _kClearSearchSvg,
                        width: 12.r,
                        height: 12.r,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Renders active search result rows across all search-capable installed addons
/// and the user's TMDB API key.
class _ActiveSearchResultsView extends StatelessWidget {
  const _ActiveSearchResultsView({
    required this.state,
    required this.onTapMeta,
  });

  final SearchState state;
  final ValueChanged<MetaModel> onTapMeta;

  @override
  Widget build(BuildContext context) {
    final rows = state.rows;

    if (rows.isEmpty && state.isSearching) {
      return ListView(
        padding: EdgeInsets.only(top: 16.h, bottom: 24.h),
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          ShelfSkeleton(),
          ShelfSkeleton(),
          ShelfSkeleton(),
        ],
      );
    }

    if (rows.isEmpty && !state.isSearching) {
      return Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 32.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'No results for “${state.query.trim()}”',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 17.sp,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: 8.h),
              Text(
                'Try searching for another movie, series, or actor.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w400,
                  color: const Color(0xFF8B8B8B),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.only(top: 16.h, bottom: 24.h),
      cacheExtent: 900,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: rows.length + (state.isSearching ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= rows.length) {
          return const ShelfSkeleton();
        }
        final row = rows[index];
        return Padding(
          padding: EdgeInsets.only(bottom: AppDimens.rowSpacing),
          child: PosterRow(
            key: PageStorageKey<String>('search_row_${row.key}_${state.query.trim()}'),
            title: row.title,
            metas: row.metas,
            onTapMeta: onTapMeta,
          ),
        );
      },
    );
  }
}

/// Default discovery rows shown when the search bar is empty, matching the
/// Figma `116:23` initial browse rows ("For You · Movies", "For You · Series", etc.).
class _DiscoveryShelvesView extends ConsumerWidget {
  const _DiscoveryShelvesView({required this.onTapMeta});

  final ValueChanged<MetaModel> onTapMeta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final homeState = ref.watch(homeControllerProvider);
    final homeController = ref.read(homeControllerProvider.notifier);

    return switch (homeState) {
      HomeInitial() || HomeLoading() => ListView(
          padding: EdgeInsets.only(top: 16.h, bottom: 24.h),
          children: const [
            ShelfSkeleton(),
            ShelfSkeleton(),
            ShelfSkeleton(),
          ],
        ),
      HomeError() => const SizedBox.shrink(),
      HomeReady(:final catalogs) => ListView.builder(
          padding: EdgeInsets.only(top: 16.h, bottom: 24.h),
          cacheExtent: 900,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          itemCount: catalogs.length,
          itemBuilder: (context, index) {
            final cat = catalogs[index];
            return CatalogShelf(
              key: ValueKey('search_discovery_${cat.key}'),
              catalog: cat,
              onVisible: () => homeController.ensureShelf(cat.key),
              onRetry: () => homeController.retryShelf(cat.key),
              onTapMeta: onTapMeta,
            );
          },
        ),
    };
  }
}
