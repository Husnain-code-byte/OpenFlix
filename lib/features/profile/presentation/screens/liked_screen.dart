import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../details/presentation/widgets/detail_widgets.dart';
import '../../../home/presentation/widgets/pixel_bottom_nav.dart';
import '../../../my_list/presentation/controllers/my_list_controller.dart';
import '../../../my_list/presentation/screens/my_list_screen.dart';

/// Detail-style view opened from Profile's "Liked" card, matching [MyListScreen]'s
/// 3 horizontal shelves ("Movies", "TV Shows", "Anime") for titles liked on TMDB.
class LikedScreen extends ConsumerStatefulWidget {
  const LikedScreen({super.key});

  @override
  ConsumerState<LikedScreen> createState() => _LikedScreenState();
}

class _LikedScreenState extends ConsumerState<LikedScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(likedControllerProvider);
    final notifier = ref.read(likedControllerProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: PixelBottomNav(
        current: PixelTab.profile,
        onChanged: (tab) {
          ref.read(activeTabProvider.notifier).state = tab;
          Navigator.of(context).popUntil((route) => route.isFirst);
        },
      ),
      body: SavedCollectionScreenView(
        title: 'Liked',
        keyPrefix: 'liked',
        state: state,
        onRefresh: notifier.refresh,
        scrollController: _scrollController,
        emptyIconSvg: kDetailLikeSvg,
        emptyMoviesSubtitle: 'Movies you like will appear here.',
        emptyTvShowsSubtitle: 'TV shows you like will appear here.',
        emptyAnimeSubtitle: 'Anime you like will appear here.',
        onBack: () => Navigator.of(context).pop(),
      ),
    );
  }
}
