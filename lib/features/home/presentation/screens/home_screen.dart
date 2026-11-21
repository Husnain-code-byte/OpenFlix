import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';


import 'package:cached_network_image/cached_network_image.dart';

import '../../../../core/constants/api_constants.dart';
import '../../../../core/perf/image_perf.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/responsive.dart';
import '../../../addons/domain/models/stream_models.dart';
import '../../../addons/presentation/controllers/addons_controller.dart';
import '../../../player/domain/models/player_models.dart';
import '../../../player/domain/models/watch_progress_models.dart';
import '../../../player/presentation/controllers/watch_progress_controller.dart';
import '../../../player/presentation/screens/player_screen.dart';
import '../../../preferences/domain/models/playback_preferences.dart';
import '../../../preferences/presentation/controllers/playback_preferences_controller.dart';
import '../../data/models/manifest_model.dart';
import '../../data/models/meta_model.dart';
import '../controllers/home_controller.dart';
import '../widgets/catalog_shelf.dart';
import '../widgets/continue_watching_shelf.dart';
import '../widgets/hero_banner.dart';
import '../widgets/pixel_brand.dart';
import '../widgets/shimmer_loading.dart';
import '../widgets/top_nav.dart';
import '../../../details/presentation/screens/detail_screen.dart';
import '../../../my_list/presentation/controllers/my_list_controller.dart';
import '../../../personalization/data/personalized_slots.dart';
import '../../../personalization/presentation/controllers/personalized_rows_controller.dart';
import '../../../personalization/presentation/widgets/personalized_shelf.dart';

/// Runs the hero/shelf pre-warm once per load (guarded, no rebuild churn).
final _prefetchDoneProvider = StateProvider<bool>((ref) => false);

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  final ScrollController _scrollController = ScrollController();
  double _savedHomeScrollOffset = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      ref.read(homeControllerProvider.notifier).refreshIfDayChanged();
      ref.read(personalizedRowsControllerProvider.notifier).refreshIfDayChanged();
    }
  }

  void _handleScroll() {
    if (!mounted || !_scrollController.hasClients) return;
    if (ref.read(homeFilterProvider) == HomeFilter.home) {
      _savedHomeScrollOffset = _scrollController.offset;
    }
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

  /// Opens the Figma "Movies details screen" for [m]. The screen supplies its own
  /// Scaffold and bottom navigation, matching the frame.
  void _showDetails(BuildContext context, MetaModel m) {
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

  List<MetaModel> _heroFor(HomeReady s, HomeFilter f, Map<String, ShelfState> shelves) {
    if (f == HomeFilter.home) return s.hero;
    final pool = buildHeroPool(
      [
        for (final c in _catalogsFor(s, f))
          if ((shelves[c.key]?.metas.isNotEmpty ?? false)) shelves[c.key]!.metas,
      ],
      ApiConstants.heroItems,
    );
    if (f == HomeFilter.anime || f == HomeFilter.categories) {
      return pool;
    }
    return pool.isEmpty ? s.hero : pool;
  }

  /// Shelves for the active heading. Includes user-routed custom Stremio addon
  /// rows positioned `Above` or `Below` built-in shelves.
  List<CatalogItemModel> _catalogsFor(HomeReady s, HomeFilter f) {
    final builtIn = s.catalogs.where((x) => catalogMatchesFilter(x, f)).toList();
    final custom = ref.watch(customCatalogsForFilterProvider(f));
    if (custom.above.isEmpty && custom.below.isEmpty) return builtIn;
    return [
      for (final e in custom.above) e.catalog,
      ...builtIn,
      for (final e in custom.below) e.catalog,
    ];
  }

  PlaybackLaunchArgs _launchArgsFromMeta(MetaModel m) {
    final rawId = m.id.trim();
    final isSeries = m.type == 'series' || m.type == 'tv';
    final imdbId = rawId.startsWith('tt') ? rawId : null;
    final tmdbId = int.tryParse(rawId) ??
        (rawId.startsWith('tmdb:') ? int.tryParse(rawId.substring(5)) : null);
    final anilistId =
        rawId.startsWith('anilist:') ? int.tryParse(rawId.substring(8)) : null;
    final yearMatch = RegExp(r'(19|20)\d{2}').firstMatch(m.releaseInfo ?? '');
    final year = yearMatch != null ? int.tryParse(yearMatch.group(0)!) : null;
    final prefs =
        ref.read(playbackPreferencesControllerProvider).valueOrNull ??
            const PlaybackPreferences();

    final progressEntry = ref
        .read(watchProgressControllerProvider)
        .valueOrNull
        ?.lookup(
          imdbId: imdbId,
          tmdbId: tmdbId,
          anilistId: anilistId,
          rawId: rawId,
          mediaType: isSeries ? 'series' : 'movie',
        );

    int season = 1;
    int episode = 1;
    int startMs = 0;
    if (isSeries) {
      final target = resolveSeriesPlaybackTarget(entry: progressEntry);
      season = target.season;
      episode = target.episode;
      startMs = target.resumePositionMs;
    } else if (progressEntry?.isMovieResumable == true) {
      startMs = progressEntry!.positionMs;
    }

    return PlaybackLaunchArgs(
      query: StreamQuery(
        mediaType: isSeries ? 'series' : 'movie',
        title: m.name,
        year: year,
        imdbId: imdbId,
        tmdbId: tmdbId,
        anilistId: anilistId,
        rawMetaId: rawId,
        sourceAddonId: m.sourceAddonId,
        season: isSeries ? season : null,
        episode: isSeries ? episode : null,
        isAnime: anilistId != null,
        preferredLanguages: prefs.preferredLanguagePair,
      ),
      initialPositionMs: startMs,
      posterUrl: m.poster ?? m.posterFallback,
      backdropUrl: m.background ?? m.landscapePoster,
      logoUrl: m.logo,
      logoAspectRatio: m.logoAspectRatio,
      genres: m.genres,
      imdbRating: m.imdbRating,
      releaseYear: year?.toString() ?? m.releaseInfo,
    );
  }

  PlaybackLaunchArgs _launchArgsFromWatchEntry(WatchProgressEntry entry) {
    final isSeries = entry.mediaType == 'series';
    final prefs =
        ref.read(playbackPreferencesControllerProvider).valueOrNull ??
            const PlaybackPreferences();
    int? season;
    int? episode;
    int startMs = 0;
    int? runtimeMin = entry.expectedRuntimeMinutes;
    if (isSeries) {
      final target = resolveSeriesPlaybackTarget(entry: entry);
      season = target.season;
      episode = target.episode;
      startMs = target.resumePositionMs;
      if (entry.latestEpisodeProgress?.completed == true &&
          entry.nextEpisodeRuntimeMinutes != null) {
        runtimeMin = entry.nextEpisodeRuntimeMinutes;
      }
    } else if (!entry.completed) {
      startMs = entry.positionMs;
    }
    final year = int.tryParse(entry.releaseYear ?? '');
    return PlaybackLaunchArgs(
      query: StreamQuery(
        mediaType: entry.mediaType,
        title: entry.title,
        year: year,
        imdbId: entry.imdbId,
        tmdbId: entry.tmdbId,
        anilistId: entry.anilistId,
        rawMetaId: entry.rawId ?? entry.canonicalId,
        season: season,
        episode: episode,
        expectedRuntimeMinutes: runtimeMin,
        isAnime: entry.isAnime,
        preferredLanguages: prefs.preferredLanguagePair,
      ),
      initialPositionMs: startMs,
      posterUrl: entry.posterUrl,
      backdropUrl: entry.backdropUrl,
      logoUrl: entry.logoUrl,
      logoAspectRatio: entry.logoAspectRatio,
      genres: entry.genres,
      imdbRating: entry.imdbRating,
      releaseYear: entry.releaseYear,
    );
  }

  /// Prefetch upcoming posters into the disk/mem cache so they decode before
  /// the user ever swipes (heroes ahead, then the first shelves).
  void _prefetch(BuildContext context, HomeReady s, Map<String, ShelfState> shelves) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final posterWidthPx = (AppDimens.posterWidth * dpr).round();
    final posterHeightPx = (AppDimens.posterHeight * dpr).round();
    final heroWidthPx = ((MediaQuery.sizeOf(context).width - AppDimens.heroGutter * 2) * dpr).round();
    final heroHeightPx = (AppDimens.heroSlideHeight(context) * dpr).round();

    for (final m in s.hero.take(4)) {
      final raw = m.background ?? m.landscapePoster ?? m.posterFallback ?? m.poster;
      if (raw != null && raw.isNotEmpty) {
        final u = tmdbSized(raw, forWidthPx: heroWidthPx);
        precacheImage(
          ResizeImage.resizeIfNeeded(
            null,
            heroHeightPx,
            CachedNetworkImageProvider(u, cacheManager: PixelImageCache.instance),
          ),
          context,
        );
      }
    }
    for (final c in s.catalogs.take(6)) {
      final metas = shelves[c.key]?.metas ?? const [];
      for (final m in metas.take(8)) {
        final raw = m.poster ?? m.posterFallback;
        if (raw != null && raw.isNotEmpty) {
          final u = tmdbSized(raw, forWidthPx: posterWidthPx);
          precacheImage(
            ResizeImage.resizeIfNeeded(
              null,
              posterHeightPx,
              CachedNetworkImageProvider(u, cacheManager: PixelImageCache.instance),
            ),
            context,
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);
    ref.listen<HomeFilter>(homeFilterProvider, (prev, next) {
      if (prev == next) return;
      if (prev == HomeFilter.home && _scrollController.hasClients) {
        _savedHomeScrollOffset = _scrollController.offset;
      }
      if (next != HomeFilter.home) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0.0);
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_scrollController.hasClients) return;
          if (ref.read(homeFilterProvider) != HomeFilter.home) {
            _scrollController.jumpTo(0.0);
          }
        });
      } else {
        final target = _savedHomeScrollOffset;
        if (_scrollController.hasClients) {
          final maxExtent = _scrollController.position.maxScrollExtent;
          _scrollController.jumpTo(target.clamp(0.0, maxExtent));
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_scrollController.hasClients) return;
          if (ref.read(homeFilterProvider) == HomeFilter.home) {
            final maxExtent = _scrollController.position.maxScrollExtent;
            _scrollController.jumpTo(target.clamp(0.0, maxExtent));
          }
        });
      }
    });

    final state = ref.watch(homeControllerProvider);
    final controller = ref.read(homeControllerProvider.notifier);
    final filter = ref.watch(homeFilterProvider);
    final navHeight = TopNav.heightFor(context);

    // Top navigation floats: it hides on scroll-down and returns on scroll-up.
    // At scroll offset 0 it is exactly the 393×124 Figma frame.
    final topNav = SliverAppBar(
      floating: true,
      snap: true,
      pinned: false,
      automaticallyImplyLeading: false,
      backgroundColor: Colors.black,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: AppDimens.topNavHeight,
      flexibleSpace: ClipRect(
        child: OverflowBox(
          alignment: Alignment.bottomCenter,
          minHeight: navHeight,
          maxHeight: navHeight,
          child: TopNav(
            filter: filter,
            onFilter: (f) => ref.read(homeFilterProvider.notifier).state = f,
            onDownloads: () => _stub(context, 'Downloads are coming soon'),
          ),
        ),
      ),
    );

    final List<Widget> content = switch (state) {
      HomeInitial() || HomeLoading() => [const SliverToBoxAdapter(child: HomeSkeleton())],
      HomeError(:final message) => [
          SliverFillRemaining(
            hasScrollBody: false,
            child: _ErrorView(message: message, onRetry: controller.load),
          ),
        ],
      HomeReady() => _buildReadyContent(context, state, filter, controller, ref),
    };

    // Prefetch once per load — guarded so shelf rebuilds never re-trigger it
    final prefetched = ref.watch(_prefetchDoneProvider);
    if (state is HomeReady && state.hero.isNotEmpty && !prefetched) {
      final s = state;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        if (ref.read(_prefetchDoneProvider)) return;
        ref.read(_prefetchDoneProvider.notifier).state = true;
        _prefetch(context, s, ref.read(shelvesProvider));
      });
    }

    return RefreshIndicator(
      color: AppColors.accent,
      backgroundColor: const Color(0xFF16181C),
      edgeOffset: navHeight,
      onRefresh: () async {
        ref.read(_prefetchDoneProvider.notifier).state = false;
        await Future.wait([
          controller.refresh(),
          ref.read(personalizedRowsControllerProvider.notifier).loadAll(),
        ]);
      },
      child: CustomScrollView(
        controller: _scrollController,
        // cacheExtent: preload extra rows vertically so decodes happen while the opening splash rests
        cacheExtent: 1100,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [topNav, ...content],
      ),
    );
  }

  List<Widget> _buildReadyContent(
    BuildContext context,
    HomeReady s,
    HomeFilter filter,
    HomeController c,
    WidgetRef ref,
  ) {
    final catalogs = _catalogsFor(s, filter);
    if (filter != HomeFilter.anime &&
        filter != HomeFilter.categories &&
        s.addonError != null &&
        (catalogs.isEmpty || s.hero.isEmpty)) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _ErrorView(message: s.addonError!, onRetry: c.load),
        ),
      ];
    }
    return _loaded(context, s, filter, c, ref);
  }

  List<Widget> _loaded(BuildContext context, HomeReady s, HomeFilter filter, HomeController c, WidgetRef ref) {
    final catalogs = _catalogsFor(s, filter);
    final shelves = ref.watch(shelvesProvider);
    final personalizedState = ref.watch(personalizedRowsControllerProvider);
    final progressStore = ref.watch(watchProgressControllerProvider).valueOrNull;
    final continueWatching =
        progressStore?.continueWatchingForFilter(filter) ?? const [];
    final feedEntries = mergeFeedEntries(
      catalogs: catalogs,
      personalizedRows: personalizedState.rowsForFilter(filter),
      slotPositions: PersonalizedSlots.positionsForFilter(filter),
      continueWatchingEntries: continueWatching,
    );
    final footerText = switch (filter) {
      HomeFilter.anime =>
        'Anime discovery powered by AniList (unofficial) · ${catalogs.length} catalogs',
      HomeFilter.categories =>
        'Categories powered by TMDB · ${catalogs.length} categories',
      _ =>
        'Powered by TMDB · ${catalogs.length} catalogs',
    };

    return [
      SliverToBoxAdapter(
        child: HeroBanner(
          items: _heroFor(s, filter, shelves),
          onPlay: (m) => Navigator.of(context).push<void>(
            openFlixPlayerRoute(_launchArgsFromMeta(m)),
          ),
          onMyList: (m) {
            ref.read(myListControllerProvider.notifier).toggleMeta(m);
          },
          onOpen: (m) => _showDetails(context, m),
        ),
      ),
      // Figma: content row starts 26px below the featured film
      SliverToBoxAdapter(child: SizedBox(height: AppDimens.afterHeroGap)),
      SliverList.builder(
        itemCount: feedEntries.length,
        itemBuilder: (_, i) => switch (feedEntries[i]) {
          CatalogFeedEntry(:final catalog) => CatalogShelf(
              key: ValueKey('catalog_${filter.name}_${catalog.key}'),
              catalog: catalog,
              onVisible: () =>
                  c.ensureShelf(catalog.key, fallbackCatalog: catalog),
              onRetry: () => c.retryShelf(catalog.key),
              onTapMeta: (m) => _showDetails(context, m),
            ),
          PersonalizedFeedEntry(:final row) => PersonalizedShelf(
              key: ValueKey('personalized_${filter.name}_${row.bucket.key}'),
              row: row,
              onTapMeta: (m) => _showDetails(context, m),
            ),
          ContinueWatchingFeedEntry(:final entries) => ContinueWatchingShelf(
              key: ValueKey('continue_watching_${filter.name}'),
              entries: entries,
              onResume: (entry) => Navigator.of(context).push<void>(
                openFlixPlayerRoute(_launchArgsFromWatchEntry(entry)),
              ),
              onViewDetails: (entry) => _showDetails(context, entry.toMetaModel()),
              onRemove: (entry) => ref
                  .read(watchProgressControllerProvider.notifier)
                  .clearProgress(entry.canonicalId),
            ),
        },
      ),
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 24.h),
          child: Text(
            footerText,
            textAlign: TextAlign.center,
            style: AppText.heroMeta.copyWith(color: const Color(0xFF4A4A4A)),
          ),
        ),
      ),
    ];
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          PixelAppIcon(size: 84.r),
          SizedBox(height: 20.h),
          Text("Couldn't reach the addon",
              textAlign: TextAlign.center,
              style: AppText.pageTitle.copyWith(fontSize: 20.sp)),
          Padding(
            padding: EdgeInsets.fromLTRB(32.w, 8.h, 32.w, 20.h),
            child: Text('$message\nCheck your connection and try again.',
                textAlign: TextAlign.center, style: AppText.heroMeta.copyWith(color: AppColors.textMuted)),
          ),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      );
}
