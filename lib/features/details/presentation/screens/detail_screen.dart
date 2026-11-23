import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/responsive.dart';
import '../../../addons/domain/models/stream_models.dart';
import '../../../home/data/models/meta_model.dart';
import '../../../home/presentation/widgets/pixel_bottom_nav.dart';
import '../../../home/presentation/widgets/poster_card.dart';
import '../../../home/presentation/widgets/poster_row.dart';
import '../../../player/domain/models/player_models.dart';
import '../../../player/domain/models/watch_progress_models.dart';
import '../../../player/presentation/controllers/stream_prefetch_controller.dart';
import '../../../player/presentation/controllers/watch_progress_controller.dart';
import '../../../player/presentation/screens/player_screen.dart';
import '../../../preferences/domain/models/playback_preferences.dart';
import '../../../preferences/presentation/controllers/playback_preferences_controller.dart';
import '../../data/tmdb_models.dart';
import '../controllers/details_controller.dart';
import '../details_text.dart';
import '../widgets/detail_widgets.dart';

/// Figma "Movies & Series details screen" (393×852), built from the per-component exports.
///
/// The hero is 323 high and the content starts 5px into it (top 318 + 4 padding).
/// Content uses 16px gutters with 20px between sections. The three secondary
/// buttons and the three telemetry columns are equal thirds, exactly the frame
/// at 393dp and edge-to-edge on any other width.
class DetailScreen extends ConsumerStatefulWidget {
  const DetailScreen({super.key, required this.meta});

  final MetaModel meta;

  @override
  ConsumerState<DetailScreen> createState() => _DetailScreenState();
}

enum _DetailTab { episodes, related, details }

double get _heroHeight => 323.h;
double get _gutter => 16.w;

const _scrim = LinearGradient(
  begin: Alignment.topCenter,
  end: Alignment.bottomCenter,
  colors: [Color(0x66000000), Color(0x00000000), Color(0xFF000000)],
  stops: [0.0, 0.5, 1.0],
);

class _DetailScreenState extends ConsumerState<DetailScreen>
    with WidgetsBindingObserver {
  // Preload Inter and Syncopate once per session; subsequent DetailScreen
  // routes skip the FutureBuilder rebuild altogether.
  late final Future<void>? _fonts =
      DetailsText.areFontsReady ? null : DetailsText.ensurePreloaded();

  late _DetailTab _activeTab =
      (widget.meta.type == 'series' || widget.meta.type == 'tv')
          ? _DetailTab.episodes
          : _DetailTab.related;

  DetailsQueryKey get _queryKey => (id: widget.meta.id, type: widget.meta.type);
  String? _lastPrefetchedKey;
  bool _launchedPlayer = false;
  StreamPrefetchController? _prefetchNotifier;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final keyToPause = _lastPrefetchedKey;
    final notifier = _prefetchNotifier;
    if (!_launchedPlayer && keyToPause != null && notifier != null) {
      Future.microtask(() => notifier.pausePrefetch(keyToPause));
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      ref.read(detailsControllerProvider(_queryKey).notifier).refreshIfReleaseArrived();
    }
  }

  StreamQuery _buildStreamQuery(
    DetailsViewState viewState, {
    int? overrideSeason,
    int? overrideEpisode,
    TmdbEpisode? episode,
  }) {
    final d = viewState.details;
    final rawId = widget.meta.id.trim();
    final isSeries =
        (d?.mediaType ?? widget.meta.type) == 'series' ||
        widget.meta.type == 'tv';
    final imdbId = d?.imdbId ?? (rawId.startsWith('tt') ? rawId : null);
    final tmdbId = (d != null && d.tmdbId > 0)
        ? d.tmdbId
        : int.tryParse(rawId);
    final anilistId = rawId.startsWith('anilist:')
        ? int.tryParse(rawId.substring('anilist:'.length))
        : null;
    final yearMatch = RegExp(r'(19|20)\d{2}').firstMatch(
      d?.releaseYear ?? widget.meta.releaseInfo ?? '',
    );
    final year = yearMatch != null ? int.tryParse(yearMatch.group(0)!) : null;

    var seasonNum = episode?.seasonNumber ?? overrideSeason;
    var episodeNum = episode?.episodeNumber ?? overrideEpisode;
    var episodeTitle = episode?.name;
    int? expectedRuntimeMin = isSeries ? episode?.runtimeMinutes : d?.runtimeMinutes;
    if (isSeries && (seasonNum == null || episodeNum == null)) {
      final firstEp = viewState.activeSeasonDetails?.episodes.firstOrNull;
      seasonNum ??=
          firstEp?.seasonNumber ?? viewState.selectedSeasonNumber ?? 1;
      episodeNum ??= firstEp?.episodeNumber ?? 1;
      episodeTitle ??= firstEp?.name;
      expectedRuntimeMin ??= firstEp?.runtimeMinutes;
    } else if (isSeries &&
        (episodeTitle == null || expectedRuntimeMin == null) &&
        seasonNum != null &&
        episodeNum != null) {
      final eps = viewState.seasonsCache[seasonNum]?.episodes;
      if (eps != null) {
        for (final ep in eps) {
          if (ep.episodeNumber == episodeNum) {
            episodeTitle ??= ep.name;
            expectedRuntimeMin ??= ep.runtimeMinutes;
            break;
          }
        }
      }
    }
    expectedRuntimeMin ??= d?.runtimeMinutes;

    final prefs =
        ref.read(playbackPreferencesControllerProvider).valueOrNull ??
            const PlaybackPreferences();

    return StreamQuery(
      mediaType: isSeries ? 'series' : 'movie',
      title: d?.title ?? widget.meta.name,
      year: year,
      imdbId: imdbId,
      tmdbId: tmdbId,
      anilistId: anilistId,
      rawMetaId: rawId,
      sourceAddonId: widget.meta.sourceAddonId,
      season: isSeries ? seasonNum : null,
      episode: isSeries ? episodeNum : null,
      episodeTitle: episodeTitle,
      expectedRuntimeMinutes: expectedRuntimeMin,
      isAnime: viewState.isAnime || anilistId != null,
      preferredLanguages: prefs.preferredLanguagePair,
    );
  }

  void _maybePrefetchStreams(StreamQuery targetQuery) {
    final key = prefetchKeyForQuery(targetQuery);
    if (_lastPrefetchedKey == key) return;
    _lastPrefetchedKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _prefetchNotifier = ref.read(streamPrefetchControllerProvider.notifier);
      _prefetchNotifier!.prefetch(targetQuery);
    });
  }

  void _launchPlayer(
    DetailsViewState viewState,
    StreamQuery query, {
    int initialPositionMs = 0,
  }) {
    HapticFeedback.lightImpact();
    _launchedPlayer = true;
    Navigator.of(context)
        .push<void>(
      openFlixPlayerRoute(
        PlaybackLaunchArgs(
          query: query,
          initialPositionMs: initialPositionMs,
          seasons: viewState.details?.seasons ?? const [],
          seasonsCache: viewState.seasonsCache,
          posterUrl: viewState.details?.posterUrl ?? widget.meta.poster,
          backdropUrl:
              viewState.details?.backdropUrl ?? widget.meta.background,
          logoUrl: viewState.details?.logoUrl ?? widget.meta.logo,
          logoAspectRatio: widget.meta.logoAspectRatio,
          genres: viewState.details?.genres ?? widget.meta.genres,
          imdbRating: viewState.details?.ratingLabel ?? widget.meta.imdbRating,
          releaseYear: viewState.details?.releaseYear ?? widget.meta.releaseInfo,
        ),
      ),
    )
        .whenComplete(() {
      _launchedPlayer = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final activeTab = ref.watch(activeTabProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: PixelBottomNav(
        current: activeTab,
        onChanged: (tab) {
          ref.read(activeTabProvider.notifier).state = tab;
          Navigator.of(context).popUntil((route) => route.isFirst);
        },
      ),
      body: _fonts == null
          ? _buildBody(context)
          : FutureBuilder<void>(
              future: _fonts,
              builder: (context, _) => _buildBody(context),
            ),
    );
  }

  Widget _buildBody(BuildContext context) {
    Responsive.init(context);
    final meta = widget.meta;
    final viewState = ref.watch(detailsControllerProvider(_queryKey));
    final details = viewState.details;
    final isSeries = details != null
        ? details.mediaType == 'series'
        : (meta.type == 'series' || meta.type == 'tv' || viewState.isSeries);
    final width = MediaQuery.sizeOf(context).width;
    final safeTop = MediaQuery.paddingOf(context).top;

    final progressStore =
        ref.watch(watchProgressControllerProvider).valueOrNull;
    ref.watch(playbackPreferencesControllerProvider);
    final rawId = meta.id.trim();
    final savedProgress = progressStore?.lookup(
      imdbId: details?.imdbId ?? (rawId.startsWith('tt') ? rawId : null),
      tmdbId: (details != null && details.tmdbId > 0)
          ? details.tmdbId
          : int.tryParse(rawId),
      anilistId: rawId.startsWith('anilist:')
          ? int.tryParse(rawId.substring('anilist:'.length))
          : null,
      rawId: rawId,
      mediaType: isSeries ? 'series' : 'movie',
    );

    final SeriesPlaybackTarget? seriesTarget = isSeries
        ? resolveSeriesPlaybackTarget(
            entry: savedProgress,
            seasons: details?.seasons ?? const [],
            seasonsCache: viewState.seasonsCache,
          )
        : null;

    final String playLabel;
    final String? playSubtitle;
    final double? playProgress;
    final int playStartMs;
    if (isSeries && seriesTarget != null) {
      playLabel = savedProgress != null ? seriesTarget.buttonLabel : 'Play';
      playSubtitle = seriesTarget.remainingLabel;
      playProgress = seriesTarget.progressFraction;
      playStartMs = seriesTarget.resumePositionMs;
    } else if (!isSeries && savedProgress?.isMovieResumable == true) {
      playLabel = 'Resume';
      playSubtitle = savedProgress!.durationMs > savedProgress.positionMs
          ? formatRemainingTime(
              savedProgress.durationMs - savedProgress.positionMs,
            )
          : null;
      playProgress = savedProgress.movieProgressFraction;
      playStartMs = savedProgress.positionMs;
    } else {
      playLabel = 'Play';
      playSubtitle = null;
      playProgress = null;
      playStartMs = 0;
    }

    final targetQuery = _buildStreamQuery(
      viewState,
      overrideSeason: seriesTarget?.season,
      overrideEpisode: seriesTarget?.episode,
    );
    if (details != null) {
      _maybePrefetchStreams(targetQuery);
    }

    final title = details != null && details.title.isNotEmpty ? details.title : meta.name;
    final released = details?.releaseYear ?? meta.releaseInfo ?? '—';
    final middleLabel = isSeries ? 'Seasons' : 'Duration';
    final middleValue = isSeries
        ? (details?.seasonsCountLabel ?? '—')
        : (details?.runtimeLabel ?? meta.runtime ?? '—');
    final rating = details?.ratingLabel ?? meta.imdbRating ?? '—';
    final synopsis =
        details != null && details.overview.isNotEmpty ? details.overview : (meta.description ?? '');

    final tabs = isSeries
        ? const [_DetailTab.episodes, _DetailTab.related, _DetailTab.details]
        : const [_DetailTab.related, _DetailTab.details];
    final tabLabels = isSeries
        ? const ['Episodes', 'Related', 'Details']
        : const ['Related', 'Details'];
    final rawIndex = tabs.indexOf(_activeTab);
    final selectedIndex = rawIndex >= 0 ? rawIndex : 0;
    final effectiveTab = tabs[selectedIndex];

    return Stack(children: [
      CustomScrollView(
        cacheExtent: 600,
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Hero: 393×323 ─────────────────────────────────────────────────
                SizedBox(
                  height: _heroHeight,
                  child: Stack(fit: StackFit.expand, children: [
                    FallbackNetworkImage(
                      urls: [
                        details?.backdropUrl,
                        details?.textlessPosterUrl,
                        details?.posterUrl,
                        meta.background,
                        meta.landscapePoster,
                        meta.poster,
                        meta.posterFallback,
                      ],
                      fallback: const ColoredBox(color: AppColors.heroBg),
                      memWidth: width,
                      memHeight: _heroHeight,
                    ),
                    const DecoratedBox(decoration: BoxDecoration(gradient: _scrim)),
                    Positioned(
                      left: 44.w,
                      right: 47.w,
                      top: 238.h,
                      height: 77.h,
                      child: DetailWordmark(name: title, logoUrl: details?.logoUrl ?? meta.logo),
                    ),
                  ]),
                ),

                // ── MainContent Header: overlaps the hero by 5px ──────────────────
                Transform.translate(
                  offset: Offset(0, -5.h),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(_gutter, 4.h, _gutter, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Section - PrimaryActionButtons (gap 10)
                        DetailPlayButton(
                          label: playLabel,
                          subtitle: playSubtitle,
                          progress: playProgress,
                          onTap: () => _launchPlayer(
                            viewState,
                            targetQuery,
                            initialPositionMs: playStartMs,
                          ),
                        ),
                        SizedBox(height: 10.h),
                        Row(children: [
                          Expanded(
                            child: DetailActionButton(
                              label: 'My List',
                              active: viewState.isInMyList,
                              animationKind: DetailActionAnimationKind.bookmark,
                              icon: SvgPicture.string(
                                viewState.isInMyList
                                    ? kDetailBookmarkFilledSvg
                                    : kDetailBookmarkSvg,
                                width: 16.r,
                                height: 16.r,
                              ),
                              onTap: () => ref
                                  .read(detailsControllerProvider(_queryKey).notifier)
                                  .toggleMyList(meta: meta),
                            ),
                          ),
                          SizedBox(width: 8.w),
                          Expanded(
                            child: DetailActionButton(
                              label: viewState.userReaction == TmdbUserReaction.liked
                                  ? 'Liked'
                                  : 'Like',
                              active: viewState.userReaction == TmdbUserReaction.liked,
                              animationKind: DetailActionAnimationKind.thumbUp,
                              icon: SvgPicture.string(
                                viewState.userReaction == TmdbUserReaction.liked
                                    ? kDetailLikeFilledSvg
                                    : kDetailLikeSvg,
                                width: 16.r,
                                height: 16.r,
                              ),
                              onTap: () => ref
                                  .read(detailsControllerProvider(_queryKey).notifier)
                                  .toggleLike(meta: meta),
                            ),
                          ),
                          SizedBox(width: 8.w),
                          Expanded(
                            child: DetailActionButton(
                              label: 'Not for me',
                              active: viewState.userReaction == TmdbUserReaction.disliked,
                              animationKind: DetailActionAnimationKind.thumbDown,
                              icon: SvgPicture.string(
                                viewState.userReaction == TmdbUserReaction.disliked
                                    ? kDetailDislikeFilledSvg
                                    : kDetailDislikeSvg,
                                width: 16.r,
                                height: 16.r,
                              ),
                              onTap: () => ref
                                  .read(detailsControllerProvider(_queryKey).notifier)
                                  .toggleDislike(meta: meta),
                            ),
                          ),
                        ]),
                        SizedBox(height: 20.h),
                        _Synopsis(
                          text: synopsis,
                          isLoading: viewState.isInitialLoading && synopsis.isEmpty,
                        ),
                        SizedBox(height: 20.h),
                        // Figma 43:403 "Metadata, season selector and tabs":
                        // For Series: 8px gap between Telemetry, Season Selector Pill, and TabNavigation.
                        // For Movies: 20px gap between Telemetry and TabNavigation.
                        _Telemetry(
                          released: released,
                          middleLabel: middleLabel,
                          middleValue: middleValue,
                          rating: rating,
                        ),
                        if (isSeries) ...[
                          SizedBox(height: 8.h),
                          DetailSeasonSelectorPill(
                            seasonNumber: viewState.selectedSeasonNumber ?? 1,
                            episodeCount: viewState.activeSeasonEpisodeCount,
                            onTap: () => _openSeasonSelector(viewState, details),
                          ),
                          SizedBox(height: 8.h),
                        ] else
                          SizedBox(height: 20.h),
                        DetailTabBar(
                          labels: tabLabels,
                          selected: selectedIndex,
                          onSelected: (i) => setState(() => _activeTab = tabs[i]),
                        ),
                      ],
                    ),
                  ),
                ),
                // 20px visual gap below TabNavigation (compensated for -5px header translate)
                SizedBox(height: 15.h),
              ],
            ),
          ),
          switch (effectiveTab) {
            _DetailTab.episodes =>
              _episodesSliver(viewState, details, meta, savedProgress),
            _DetailTab.related => SliverToBoxAdapter(child: _relatedTab(viewState)),
            _DetailTab.details => SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: _gutter),
                sliver: SliverToBoxAdapter(child: _detailsTab(details, meta, synopsis)),
              ),
          },
          SliverToBoxAdapter(child: SizedBox(height: 43.h)),
        ],
      ),
      // Top status-bar gradient mask preventing vertical scroll clipping under
      // system status bar icons and floating back button on Episodes/Related/Details tabs.
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        height: safeTop + 52.h,
        child: const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xD9000000),
                  Color(0x66000000),
                  Color(0x00000000),
                ],
                stops: [0.0, 0.58, 1.0],
              ),
            ),
          ),
        ),
      ),
      Positioned(
        left: 17.w,
        top: safeTop + 17.h,
        child: DetailBackButton(onTap: () => Navigator.of(context).maybePop()),
      ),
    ]);
  }

  void _openMedia(MetaModel m) {
    HapticFeedback.selectionClick();
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

  Future<void> _openSeasonSelector(
    DetailsViewState viewState,
    TmdbMovieDetails? details,
  ) async {
    final currentSeasonNumber = viewState.selectedSeasonNumber ?? 1;
    final resolved = viewState.resolvedSeasons;
    final seasons = resolved.isNotEmpty
        ? resolved
        : <TmdbSeasonSummary>[
            TmdbSeasonSummary(
              id: currentSeasonNumber,
              seasonNumber: currentSeasonNumber,
              name: 'Season $currentSeasonNumber',
              airDate: details?.releaseYear,
              episodeCount: viewState.activeSeasonEpisodeCount ?? 0,
            ),
          ];

    final pickedSeason = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (sheetContext) => DetailSeasonSelectorSheet(
        seasons: seasons,
        selectedSeasonNumber: currentSeasonNumber,
        onSeasonSelected: (seasonNum) => Navigator.of(sheetContext).pop(seasonNum),
      ),
    );

    if (!mounted || pickedSeason == null) return;
    if (_activeTab != _DetailTab.episodes) {
      setState(() => _activeTab = _DetailTab.episodes);
    }
    if (pickedSeason != currentSeasonNumber || viewState.activeSeasonDetails == null) {
      ref.read(detailsControllerProvider(_queryKey).notifier).selectSeason(pickedSeason);
    }
  }

  /// "Episodes" tab for TV Shows / Series (Figma frame 43:95), virtualized via
  /// [SliverList.builder] so seasons with 170–366+ episodes (e.g. Black Clover,
  /// Bleach) only mount the ~6 visible viewport cards at any time.
  Widget _episodesSliver(
    DetailsViewState viewState,
    TmdbMovieDetails? details,
    MetaModel meta,
    WatchProgressEntry? savedProgress,
  ) {
    final seasonDetails = viewState.activeSeasonDetails;
    if (seasonDetails == null && (viewState.isInitialLoading || viewState.isLoadingSeason)) {
      return SliverToBoxAdapter(
        child: DetailEpisodesSkeleton(inset: _gutter),
      );
    }

    if (seasonDetails == null && viewState.hasFailed) {
      return SliverToBoxAdapter(
        child: DetailErrorRetry(
          inset: _gutter,
          error: viewState.errorMessage,
          onRetry: () => ref.read(detailsControllerProvider(_queryKey).notifier).retry(),
        ),
      );
    }

    final episodes = seasonDetails?.episodes ?? const <TmdbEpisode>[];
    if (episodes.isEmpty) {
      if (viewState.seasonError != null) {
        return SliverToBoxAdapter(
          child: DetailErrorRetry(
            inset: _gutter,
            error: viewState.seasonError,
            onRetry: () => ref
                .read(detailsControllerProvider(_queryKey).notifier)
                .selectSeason(viewState.selectedSeasonNumber ?? 1),
          ),
        );
      }
      return SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: _gutter),
        sliver: SliverToBoxAdapter(
          child: Text(
            'No episodes available.',
            style: DetailsText.inter(size: 12.sp, height: 20 / 12, color: AppColors.heroMeta),
          ),
        ),
      );
    }

    final fallbackStill = details?.backdropUrl ?? meta.background ?? meta.landscapePoster;

    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: _gutter),
      sliver: SliverList.builder(
        itemCount: episodes.length,
        addAutomaticKeepAlives: false,
        addSemanticIndexes: false,
        itemBuilder: (context, i) {
          final ep = episodes[i];
          final epProg =
              savedProgress?.episodeFor(ep.seasonNumber, ep.episodeNumber);
          return Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 16.h),
            child: DetailEpisodeCard(
              key: ValueKey('ep_${ep.seasonNumber}_${ep.episodeNumber}'),
              episode: ep,
              fallbackBackdropUrl: fallbackStill,
              progress: epProg?.progressFraction,
              isWatched: epProg?.completed ?? false,
              onTap: () => _launchPlayer(
                viewState,
                _buildStreamQuery(viewState, episode: ep),
                initialPositionMs:
                    epProg != null && epProg.isResumable ? epProg.positionMs : 0,
              ),
            ),
          );
        },
      ),
    );
  }

  /// OTT rows under the "Related" tab: "More Like This" (TMDB similar),
  /// "Viewers Also Watched" (TMDB recommendations), "Collection" (other
  /// movies in the same TMDB franchise collection, ordered by popularity),
  /// and "Anime Picks" (AniList recommendations for anime titles).
  Widget _relatedTab(DetailsViewState viewState) {
    if (viewState.isInitialLoading) {
      return DetailRelatedSkeleton(inset: _gutter);
    }

    if (viewState.hasFailed) {
      return DetailErrorRetry(
        inset: _gutter,
        error: viewState.errorMessage,
        onRetry: () => ref.read(detailsControllerProvider(_queryKey).notifier).retry(),
      );
    }

    final similarMetas = viewState.similarMetas;
    final recommendedMetas = viewState.recommendedMetas;
    final collectionMetas = viewState.collectionMetas;
    final animePicks = viewState.animePicks;

    final rows = <Widget>[
      if (similarMetas.isNotEmpty)
        PosterRow(
          key: PageStorageKey<String>('similar_${widget.meta.id}'),
          title: 'More Like This',
          inset: _gutter,
          metas: similarMetas,
          onTapMeta: _openMedia,
        ),
      if (recommendedMetas.isNotEmpty)
        PosterRow(
          key: PageStorageKey<String>('recommended_${widget.meta.id}'),
          title: 'Viewers Also Watched',
          inset: _gutter,
          metas: recommendedMetas,
          onTapMeta: _openMedia,
        ),
      if (collectionMetas.isNotEmpty)
        PosterRow(
          key: PageStorageKey<String>('collection_${widget.meta.id}'),
          title: 'Collection',
          inset: _gutter,
          metas: collectionMetas,
          onTapMeta: _openMedia,
        ),
      if (animePicks.isNotEmpty)
        PosterRow(
          key: PageStorageKey<String>('anime_picks_${widget.meta.id}'),
          title: 'Anime Picks',
          inset: _gutter,
          metas: animePicks,
          onTapMeta: _openMedia,
        ),
    ];

    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) SizedBox(height: AppDimens.rowSpacing),
          rows[i],
        ],
      ],
    );
  }

  /// "Details" tab: shows the full untruncated description, Genre section with
  /// label, and Cast section with label, actor photos, and names.
  Widget _detailsTab(TmdbMovieDetails? details, MetaModel meta, String synopsis) {
    final genres = (details != null && details.genres.isNotEmpty) ? details.genres : meta.genres;
    final cast = details?.cast ?? const <TmdbCast>[];
    final fullDescription = synopsis.trim();

    if (fullDescription.isEmpty && genres.isEmpty && cast.isEmpty) {
      return Text(
        'No details available.',
        style: DetailsText.inter(size: 12.sp, height: 20 / 12, color: AppColors.heroMeta),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (fullDescription.isNotEmpty) ...[
          const _DetailSectionHeading(title: 'Description'),
          SizedBox(height: 8.h),
          Text(
            fullDescription,
            style: DetailsText.inter(
              size: 13.5.sp,
              weight: FontWeight.w400,
              color: const Color(0xFFD4D4D4),
              height: 20 / 13.5,
            ).copyWith(letterSpacing: -0.25),
          ),
          if (genres.isNotEmpty || cast.isNotEmpty) SizedBox(height: 24.h),
        ],
        if (genres.isNotEmpty) ...[
          const _DetailSectionHeading(title: 'Genre'),
          SizedBox(height: 10.h),
          Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: [for (final g in genres) _GenrePill(label: g)],
          ),
          if (cast.isNotEmpty) SizedBox(height: 24.h),
        ],
        if (cast.isNotEmpty) ...[
          const _DetailSectionHeading(title: 'Cast'),
          SizedBox(height: 14.h),
          DetailCastGrid(cast: cast),
        ],
      ],
    );
  }
}

class _DetailSectionHeading extends StatelessWidget {
  const _DetailSectionHeading({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) => Text(
        title,
        style: DetailsText.inter(
          size: 15.sp,
          weight: FontWeight.w700,
          color: Colors.white,
          height: 22 / 15,
        ).copyWith(letterSpacing: -0.3),
      );
}

/// Figma "Section - Synopsis": 3px top padding, Inter 14.5/20 #D4D4D4 with
/// -0.362 tracking, up to three lines (63px).
class _Synopsis extends StatelessWidget {
  const _Synopsis({required this.text, this.isLoading = false});

  final String text;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return ConstrainedBox(
        constraints: BoxConstraints(minHeight: 63.h),
        child: Padding(
          padding: EdgeInsets.only(top: 6.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 12.h,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(4.r),
                ),
              ),
              SizedBox(height: 8.h),
              Container(
                height: 12.h,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(4.r),
                ),
              ),
              SizedBox(height: 8.h),
              Container(
                height: 12.h,
                width: 220.w,
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(4.r),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: 63.h),
      child: Padding(
        padding: EdgeInsets.only(top: 3.h),
        child: Text(
          text,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: DetailsText.inter(
            size: 14.5.sp,
            height: 20 / 14.5,
            color: const Color(0xFFD4D4D4),
          ).copyWith(letterSpacing: -0.362),
        ),
      ),
    );
  }
}

/// Figma "Metadata Telemetry Bar" (70px): a 4px margin, then 1px #18181B rules
/// around 12px padding and three equal columns (Released · Duration/Seasons · Rating).
class _Telemetry extends StatelessWidget {
  const _Telemetry({
    required this.released,
    required this.middleLabel,
    required this.middleValue,
    required this.rating,
  });

  final String released;
  final String middleLabel;
  final String middleValue;
  final String rating;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: 4.h),
        child: Container(
          // 66 + the 4px margin = the frame's 70px; grows with large system fonts.
          constraints: BoxConstraints(minHeight: 66.h),
          padding: EdgeInsets.symmetric(vertical: 12.h),
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: Color(0xE618181B)),
              bottom: BorderSide(color: Color(0xE618181B)),
            ),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: 8.w),
                child: DetailInfoColumn(
                  label: 'Released',
                  value: released,
                  alignment: CrossAxisAlignment.start,
                ),
              ),
            ),
            Expanded(
              child: DetailInfoColumn(
                label: middleLabel,
                value: middleValue,
                alignment: CrossAxisAlignment.center,
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: 8.w),
                child: DetailInfoColumn(
                  label: 'Rating',
                  value: rating,
                  alignment: CrossAxisAlignment.end,
                ),
              ),
            ),
          ]),
        ),
      );
}

class _GenrePill extends StatelessWidget {
  const _GenrePill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
        decoration: BoxDecoration(
          color: const Color(0x66000000),
          borderRadius: BorderRadius.circular(6.r),
          border: Border.all(color: const Color(0xCC404040)),
        ),
        child: Text(
          label,
          style: DetailsText.inter(
            size: 12.sp,
            weight: FontWeight.w600,
            color: const Color(0xFFE5E5E5),
            height: 16 / 12,
          ),
        ),
      );
}
