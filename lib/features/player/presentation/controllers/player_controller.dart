import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../addons/domain/models/stream_models.dart';
import '../../../details/data/tmdb_models.dart';
import '../../../details/data/tmdb_repository.dart';
import '../../../preferences/domain/models/playback_preferences.dart';
import '../../../preferences/presentation/controllers/playback_preferences_controller.dart';
import '../../data/skip_segments_service.dart';
import '../../data/track_orchestrator.dart';
import '../../domain/models/player_models.dart';
import '../../domain/models/ranked_stream.dart';
import '../../domain/models/skip_segment.dart';
import '../../domain/models/watch_progress_models.dart';
import 'stream_prefetch_controller.dart';
import 'watch_progress_controller.dart';

class PlayerSessionController extends ChangeNotifier {
  PlayerSessionController(this.container, this.initialArgs)
      : _state = PlayerUiState(query: initialArgs.query) {
    _init();
  }

  final ProviderContainer container;
  final PlaybackLaunchArgs initialArgs;

  static const _launcherChannel = MethodChannel('openflix/launcher');
  static const _defaultUserAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/126.0.0.0 Mobile Safari/537.36';

  late Player _player;
  late VideoController _videoController;
  VideoController get videoController => _videoController;

  /// High-frequency timeline notifier (position / duration / buffered).
  /// Kept separate from [ChangeNotifier] so playback ticks never rebuild the
  /// full [PlayerScreen] or [Video] widget.
  final ValueNotifier<PlayerTimelineState> timelineNotifier =
      ValueNotifier<PlayerTimelineState>(const PlayerTimelineState());

  /// Live subtitle text scale notifier for Flutter's native [SubtitleView].
  final ValueNotifier<double> subtitleScaleNotifier = ValueNotifier<double>(1.0);

  /// Isolated notifier for active Skip Intro / Recap / Outro / Next Episode CTA.
  /// Kept separate from [ChangeNotifier] so position ticks never rebuild the HUD
  /// or [Video] widget.
  final ValueNotifier<ActiveSkipPrompt?> activeSkipPromptNotifier =
      ValueNotifier<ActiveSkipPrompt?>(null);

  PlayerUiState _state;
  PlayerUiState get state => _state;

  Duration get currentPosition => timelineNotifier.value.position;
  Duration get currentDuration => timelineNotifier.value.duration;

  late final List<TmdbSeasonSummary> _seasons = [...initialArgs.seasons];
  late final Map<int, TmdbSeasonDetails> _seasonsCache = {
    ...initialArgs.seasonsCache,
  };

  final List<StreamSubscription<dynamic>> _subs = [];
  ProviderSubscription<Map<String, PrefetchSnapshot>>? _prefetchSub;
  Timer? _graceTimer;
  Timer? _stallWatchdog;
  Timer? _pauseScrapingTimer;
  Timer? _progressFlushTimer;
  Timer? _statusBannerTimer;
  Timer? _autoOutroCountdownTimer;

  bool _disposed = false;
  bool _hasStartedFirstOpen = false;
  bool _userLockedStream = false;
  bool _tracksAppliedForOpen = false;
  bool _linksModalOpen = false;
  bool _awaitingResumedFallback = false;
  int _openGeneration = 0;

  // Skip segments & Next Episode promotion state
  List<SkipSegment> _onlineSkipSegments = const [];
  List<SkipSegment> _embeddedSkipSegments = const [];
  List<SkipSegment> _mergedSkipSegments = const [];
  final Set<SkipSegmentType> _dismissedSkipTypes = <SkipSegmentType>{};
  final Set<SkipSegmentType> _autoSkippedTypes = <SkipSegmentType>{};
  bool _reachedNextEpisodePoint = false;
  int _skipFetchGeneration = 0;
  int _chaptersLoadedForGen = -1;
  int? _autoOutroSecondsLeft;
  SkipActionKind? _activeCountdownKind;

  // Switching / Failover memory
  final Set<String> _sessionFailedKeys = <String>{};
  int _pendingResumeMs = 0;
  bool _wasPlayingBeforeSwitch = true;

  // User manual overrides preserved across mid-stream switches
  String? _preferredAudioOverrideLang;
  bool _userManualSubOverride = false;
  bool _userChoseSubOff = false;
  String? _previousSubLang;
  String? _prefetchedNextKey;

  final Dio _subDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 6),
      receiveTimeout: const Duration(seconds: 8),
    ),
  );

  String get _currentPrefetchKey => prefetchKeyForQuery(_state.query);

  void _init() {
    _pendingResumeMs = initialArgs.initialPositionMs;

    final prefs =
        container.read(playbackPreferencesControllerProvider).valueOrNull ??
            const PlaybackPreferences();
    subtitleScaleNotifier.value = prefs.subtitleScale;

    // Tight 12 MiB demuxer budget keeps RAM lean on 3 GB Android devices.
    // libass: false routes decoded embedded & external subtitle text cleanly
    // through Flutter's native SubtitleView (reliable rendering + low RAM).
    _player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 12 * 1024 * 1024,
        libass: false,
        logLevel: MPVLogLevel.error,
      ),
    );
    _videoController = VideoController(
      _player,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: prefs.hardwareDecoding,
        // Prefer zero-copy MediaCodec surface decoding before CPU copy fallback.
        hwdec: prefs.hardwareDecoding ? 'mediacodec,mediacodec-copy' : 'no',
      ),
    );

    _configureNativeMpvProperties(prefs);
    _attachPlayerListeners();
    _startProgressFlushTimer();
    _bindPrefetch(_state.query);
  }

  void _configureNativeMpvProperties(PlaybackPreferences prefs) {
    final platform = _player.platform;
    if (platform is NativePlayer) {
      Future<void> safeSet(String k, String v) async {
        try {
          await platform.setProperty(k, v);
        } catch (_) {}
      }

      unawaited(safeSet('network-timeout', '15'));
      unawaited(safeSet('reconnect', 'yes'));
      // Strict demuxer memory ceiling so mpv never starves a 3 GB phone.
      unawaited(safeSet('demuxer-max-bytes', '12MiB'));
      unawaited(safeSet('demuxer-max-back-bytes', '4MiB'));
      unawaited(safeSet('demuxer-readahead-secs', '10'));
      unawaited(safeSet('cache-secs', '10'));
      // Smooth playback on mobile SoCs (PowerVR / Mali / Adreno):
      // lightweight bilinear GPU scaling & frame dropping to keep A/V locked.
      unawaited(safeSet('framedrop', 'vo'));
      unawaited(safeSet('vd-lavc-fast', 'yes'));
      unawaited(safeSet('vd-lavc-skiploopfilter', 'nonref'));
      unawaited(safeSet('vd-lavc-threads', '4'));
      unawaited(safeSet('scale', 'bilinear'));
      unawaited(safeSet('cscale', 'bilinear'));
      unawaited(safeSet('dscale', 'bilinear'));
      unawaited(safeSet('correct-downscaling', 'no'));
      unawaited(safeSet('dither-depth', 'no'));
      unawaited(safeSet('sub-auto', 'no'));
      unawaited(safeSet('sub-visibility', 'yes'));
      unawaited(safeSet('sub-scale', prefs.subtitleScale.toStringAsFixed(2)));
    }
  }

  void _attachPlayerListeners() {
    _subs.add(
      _player.stream.playing.listen((playing) {
        if (_disposed) return;
        _updateWakelock(playing);
        _setState(_state.copyWith(isPlaying: playing));
        if (playing) {
          _maybeSchedulePauseBackgroundScraping();
          _evaluateActiveSkipSegment(currentPosition);
        } else {
          _cancelAutoOutroCountdown();
          if (currentDuration > Duration.zero) {
            unawaited(flushProgress());
          }
        }
      }),
    );

    _subs.add(
      _player.stream.buffering.listen((buffering) {
        if (_disposed) return;
        _setState(_state.copyWith(isBuffering: buffering));
        if (!buffering && currentDuration > Duration.zero) {
          _stallWatchdog?.cancel();
          if (_state.isInitializing || _state.isSwitchingSource) {
            _setState(
              _state.copyWith(
                isInitializing: false,
                isSwitchingSource: false,
              ),
            );
          }
          _maybeSchedulePauseBackgroundScraping();
        }
      }),
    );

    _subs.add(
      _player.stream.position.listen((pos) {
        if (_disposed) return;
        final cur = timelineNotifier.value;
        // Throttle tiny sub-250ms jitters to reduce seekbar repaints.
        if ((pos - cur.position).abs() >= const Duration(milliseconds: 250) ||
            pos == Duration.zero) {
          timelineNotifier.value = cur.copyWith(position: pos);
        }
        if (pos > Duration.zero) {
          if (pos.inMilliseconds != _pendingResumeMs &&
              (_state.isInitializing || _state.isSwitchingSource)) {
            _stallWatchdog?.cancel();
          }
          if (_state.isInitializing || _state.isSwitchingSource) {
            _setState(
              _state.copyWith(
                isInitializing: false,
                isSwitchingSource: false,
              ),
            );
          }
          _maybeSchedulePauseBackgroundScraping();
        }
        _maybePrefetchNextEpisode();
        _evaluateActiveSkipSegment(pos);
      }),
    );

    _subs.add(
      _player.stream.duration.listen((dur) {
        if (_disposed) return;
        // Instant TMDB runtime verification: reject trailers or wrong movies/episodes
        // as soon as mpv reads container headers (<500ms), hide the bad link from
        // the Links sheet, and switch cleanly to the next valid link.
        final active = _state.activeStream;
        final expectedMin = _state.query.expectedRuntimeMinutes;
        if (dur > Duration.zero &&
            active != null &&
            expectedMin != null &&
            expectedMin > 0 &&
            !isDurationCompatibleWithRuntime(dur.inSeconds, expectedMin)) {
          container
              .read(streamPrefetchControllerProvider.notifier)
              .markStreamRuntimeMismatch(_currentPrefetchKey, active.stream);
          unawaited(_player.stop());
          _handleActiveStreamFailure(
            'Skipped mismatched video (${dur.inMinutes}m vs ${expectedMin}m)',
            forceFailover: true,
          );
          return;
        }

        timelineNotifier.value = timelineNotifier.value.copyWith(duration: dur);
        if (dur > Duration.zero) {
          _stallWatchdog?.cancel();
          if (_state.isInitializing || _state.isSwitchingSource) {
            _setState(
              _state.copyWith(
                isInitializing: false,
                isSwitchingSource: false,
              ),
            );
          }
          _maybeSchedulePauseBackgroundScraping();
          if (_chaptersLoadedForGen != _openGeneration) {
            _chaptersLoadedForGen = _openGeneration;
            unawaited(_readEmbeddedChapters(_openGeneration, dur.inMilliseconds));
          }
          _rebuildMergedSkipSegments();
          _evaluateActiveSkipSegment(currentPosition);
        }
      }),
    );

    _subs.add(
      _player.stream.buffer.listen((buf) {
        if (_disposed) return;
        final cur = timelineNotifier.value;
        if ((buf - cur.buffered).abs() >= const Duration(milliseconds: 500)) {
          timelineNotifier.value = cur.copyWith(buffered: buf);
        }
      }),
    );

    _subs.add(
      _player.stream.tracks.listen((tracks) {
        if (_disposed) return;
        _onTracksUpdated(tracks);
      }),
    );

    _subs.add(
      _player.stream.error.listen((err) {
        if (_disposed) return;
        if (err.trim().isEmpty) return;
        debugPrint('Player error: $err');
        if (_state.activeStream != null &&
            (_state.isInitializing ||
                _state.isSwitchingSource ||
                _state.isBuffering ||
                currentDuration == Duration.zero)) {
          _handleActiveStreamFailure('Playback error: $err');
        }
      }),
    );

    _subs.add(
      _player.stream.completed.listen((done) {
        if (_disposed || !done) return;
        unawaited(flushProgress(forceCompleted: true));
        final prefs =
            container.read(playbackPreferencesControllerProvider).valueOrNull ??
                const PlaybackPreferences();
        if (prefs.autoPlayNextEpisode && _state.nextEpisodeQuery != null) {
          unawaited(playNextEpisode());
        }
      }),
    );
  }

  /// Once the chosen link is playing cleanly (duration known, position moving,
  /// not buffering), pause background provider scraping after 1.5s so CPU, RAM,
  /// and network go 100% to smooth video playback. Scraping resumes on demand
  /// if the user opens the Links modal.
  void _maybeSchedulePauseBackgroundScraping() {
    if (_disposed || _linksModalOpen || _awaitingResumedFallback) return;
    if (!_state.isResolvingLinks) return;
    if (!_state.isPlaying ||
        _state.isBuffering ||
        currentDuration <= Duration.zero ||
        currentPosition <= Duration.zero) {
      return;
    }
    if (_pauseScrapingTimer != null) return;
    final key = _currentPrefetchKey;
    _pauseScrapingTimer = Timer(const Duration(milliseconds: 1500), () {
      _pauseScrapingTimer = null;
      if (_disposed || _linksModalOpen || _awaitingResumedFallback) return;
      if (_state.isPlaying && !_state.isBuffering && currentDuration > Duration.zero) {
        container
            .read(streamPrefetchControllerProvider.notifier)
            .pausePrefetch(key);
      }
    });
  }

  /// Called when the user opens the Links/Sources sheet inside the player.
  /// Keeps playback butter-smooth (does NOT restart heavy scraping automatically
  /// while video is playing unless zero links are available); user can tap
  /// "Scan more" inside the modal if they want additional providers.
  void onLinksModalOpened() {
    _linksModalOpen = true;
    _pauseScrapingTimer?.cancel();
    _pauseScrapingTimer = null;
    if (_state.rankedStreams.isEmpty) {
      unawaited(
        container
            .read(streamPrefetchControllerProvider.notifier)
            .resumePrefetch(_currentPrefetchKey, skipProbe: _state.isPlaying),
      );
    }
  }

  /// Called when the Links/Sources sheet closes. Re-pauses background scraping
  /// if video is already playing smoothly.
  void onLinksModalClosed() {
    _linksModalOpen = false;
    if (_state.isPlaying &&
        !_state.isBuffering &&
        currentDuration > Duration.zero &&
        !_awaitingResumedFallback) {
      container
          .read(streamPrefetchControllerProvider.notifier)
          .pausePrefetch(_currentPrefetchKey);
    }
  }

  /// Explicit manual button inside Links sheet to scan remaining providers.
  void loadMoreSources() {
    unawaited(
      container
          .read(streamPrefetchControllerProvider.notifier)
          .resumePrefetch(_currentPrefetchKey, skipProbe: _state.isPlaying),
    );
  }

  void _updateWakelock(bool playing) {
    try {
      if (playing) {
        unawaited(WakelockPlus.enable());
      } else {
        unawaited(WakelockPlus.disable());
      }
    } catch (_) {}
  }

  void _startProgressFlushTimer() {
    _progressFlushTimer?.cancel();
    _progressFlushTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_disposed && _state.isPlaying && currentDuration > Duration.zero) {
        unawaited(flushProgress());
      }
    });
  }

  void _bindPrefetch(StreamQuery query) {
    _prefetchSub?.close();
    _graceTimer?.cancel();
    _graceTimer = null;
    _pauseScrapingTimer?.cancel();
    _pauseScrapingTimer = null;
    final key = prefetchKeyForQuery(query);

    final notifier = container.read(streamPrefetchControllerProvider.notifier);
    notifier.pauseOtherKeys(key);

    _prefetchSub = container.listen<Map<String, PrefetchSnapshot>>(
      streamPrefetchControllerProvider,
      (prev, next) {
        if (_disposed) return;
        final snap = next[key];
        if (snap != null) {
          _onPrefetchSnapshot(snap);
        }
      },
      fireImmediately: true,
    );

    _resetSkipSegmentsForEpisode();
    unawaited(_ensureEpisodeMetadataLoaded(query));
    unawaited(_fetchOnlineSkipSegments(query));
    unawaited(notifier.prefetch(query));
  }

  /// Ensures `S{season} E{episode} {episodeTitle}` is always populated (even
  /// when launched directly from Continue Watching, Home Hero, or Next Episode)
  /// and caches season details for accurate next-episode resolution.
  Future<void> _ensureEpisodeMetadataLoaded(StreamQuery query) async {
    if (query.mediaType != 'series' ||
        query.season == null ||
        query.episode == null) {
      return;
    }
    final seasonNum = query.season!;
    final episodeNum = query.episode!;
    final targetKey = prefetchKeyForQuery(query);

    bool applyFromSeason(TmdbSeasonDetails details) {
      TmdbEpisode? match;
      for (final ep in details.episodes) {
        if (ep.episodeNumber == episodeNum) {
          match = ep;
          break;
        }
      }
      if (match == null) {
        for (final ep in details.allEpisodes) {
          if (ep.episodeNumber == episodeNum) {
            match = ep;
            break;
          }
        }
      }
      if (match == null) return false;
      final epName = match.name.trim();
      final hasTitle = _state.query.episodeTitle?.trim().isNotEmpty == true;
      final needsTitle = !hasTitle && epName.isNotEmpty;
      final needsRuntime =
          (_state.query.expectedRuntimeMinutes == null ||
              _state.query.expectedRuntimeMinutes! <= 0) &&
          match.runtimeMinutes != null &&
          match.runtimeMinutes! > 0;
      if ((needsTitle || needsRuntime) &&
          !_disposed &&
          _currentPrefetchKey == targetKey) {
        _setState(
          _state.copyWith(
            query: _state.query.copyWith(
              episodeTitle: needsTitle ? epName : null,
              expectedRuntimeMinutes:
                  needsRuntime ? match.runtimeMinutes : null,
            ),
          ),
        );
      }
      return true;
    }

    // 1. Fast path: already in local season cache.
    final cached = _seasonsCache[seasonNum];
    if (cached != null && applyFromSeason(cached)) {
      return;
    }

    // 2. Fetch season details from memoized TmdbRepository.
    try {
      final tmdbRepo = container.read(tmdbRepositoryProvider);
      var tvTmdbId = query.tmdbId;
      if (tvTmdbId == null || tvTmdbId <= 0) {
        final lookupId = (query.imdbId?.trim().isNotEmpty == true)
            ? query.imdbId!.trim()
            : (query.anilistId != null && query.anilistId! > 0)
                ? 'anilist:${query.anilistId}'
                : (query.rawMetaId?.trim().isNotEmpty == true)
                    ? query.rawMetaId!.trim()
                    : null;
        if (lookupId == null) return;
        final core = await tmdbRepo.fetchCoreDetails(lookupId, type: 'series');
        if (_disposed || _currentPrefetchKey != targetKey) return;
        if (core.tmdbId > 0) tvTmdbId = core.tmdbId;
        if (_seasons.isEmpty && core.seasons.isNotEmpty) {
          _seasons.addAll(core.seasons);
        }
      }
      if (tvTmdbId == null || tvTmdbId <= 0) return;

      final seasonDetails =
          await tmdbRepo.fetchSeasonDetails(tvTmdbId, seasonNum);
      if (_disposed) return;
      _seasonsCache[seasonNum] = seasonDetails;
      if (_currentPrefetchKey == targetKey) {
        applyFromSeason(seasonDetails);
      }
    } catch (_) {
      // Non-critical metadata enrichment; never disrupt playback.
    }
  }

  void _onPrefetchSnapshot(PrefetchSnapshot snap) {
    if (_disposed || snap.key != _currentPrefetchKey) return;

    final filteredRanked = snap.rankedStreams;
    final subOpts = TrackOrchestrator.buildSubtitleOptions(
      _player.state.tracks.subtitle,
      snap.subtitles,
    );

    _setState(
      _state.copyWith(
        isResolvingLinks: snap.isResolving || snap.isProbing,
        hasMoreSources: snap.hasMoreProviders,
        rankedStreams: filteredRanked,
        subtitleOptions: subOpts,
      ),
    );

    if (_tracksAppliedForOpen &&
        !_userManualSubOverride &&
        _state.selectedSubtitleId == 'off' &&
        snap.subtitles.isNotEmpty) {
      final prefs =
          container.read(playbackPreferencesControllerProvider).valueOrNull ??
              const PlaybackPreferences();
      final activeAudio = _state.audioOptions
          .where((a) => a.id == _state.selectedAudioId)
          .firstOrNull;
      final smartSub = TrackOrchestrator.selectInitialSubtitle(
        options: subOpts,
        prefs: prefs,
        activeAudioLang: activeAudio?.normalizedLang ??
            _state.activeStream?.meta.detectedAudioLanguages.firstOrNull,
      );
      if (!smartSub.isOff) {
        unawaited(_applySubtitleOption(smartSub, markManual: false));
      }
    }

    // If previous link failed and we resumed scraping to find a fresh link:
    if (_awaitingResumedFallback && !_userLockedStream) {
      final freshCandidate = filteredRanked
          .where((r) =>
              r.isAutoPlayEligible && !_sessionFailedKeys.contains(r.dedupKey))
          .firstOrNull;
      if (freshCandidate != null) {
        _awaitingResumedFallback = false;
        _showStatusBanner('Switching to ${freshCandidate.stream.providerName}...');
        unawaited(
          _openRankedStream(
            freshCandidate,
            startPosition: Duration(milliseconds: _pendingResumeMs),
            play: true,
          ),
        );
        return;
      }
      if (!snap.isResolving && !snap.isProbing) {
        _awaitingResumedFallback = false;
        _setState(
          _state.copyWith(
            isInitializing: false,
            isSwitchingSource: false,
            isBuffering: false,
            errorMessage:
                'No working streams found. Tap Links to inspect all sources.',
          ),
        );
      }
      return;
    }

    // NEVER let background arrivals override a stream already opened or chosen by user.
    if (_hasStartedFirstOpen || _userLockedStream) return;

    // 1. Instant open when pre-fetch finished resolving + probing, OR high-confidence pick arrived.
    if (!snap.isResolving && !snap.isProbing) {
      _graceTimer?.cancel();
      _graceTimer = null;
      _tryStartFirstPlayable(snap);
      return;
    }

    if (snap.hasHighConfidencePick && _graceTimer == null) {
      _graceTimer = Timer(const Duration(milliseconds: 900), () {
        _graceTimer = null;
        if (_disposed || _hasStartedFirstOpen) return;
        final latest =
            container.read(streamPrefetchControllerProvider)[_currentPrefetchKey] ??
                snap;
        _tryStartFirstPlayable(latest);
      });
    } else if (snap.bestPlayableStream != null && _graceTimer == null) {
      // Even if best pick isn't Primary+probed yet, don't stall user past 3.5s
      // once a playable direct stream is already available.
      _graceTimer = Timer(const Duration(milliseconds: 3500), () {
        _graceTimer = null;
        if (_disposed || _hasStartedFirstOpen) return;
        final latest =
            container.read(streamPrefetchControllerProvider)[_currentPrefetchKey] ??
                snap;
        _tryStartFirstPlayable(latest);
      });
    }
  }

  void _tryStartFirstPlayable(PrefetchSnapshot snap) {
    if (_disposed || _hasStartedFirstOpen) return;
    final best = snap.bestPlayableStream;
    if (best == null) {
      _hasStartedFirstOpen = true;
      _setState(
        _state.copyWith(
          isInitializing: false,
          isResolvingLinks: false,
          errorMessage: snap.hasAnyStreamAddon
              ? 'No direct streams found for this title. Tap Links to inspect available sources or torrents.'
              : 'No stream addons enabled yet. Install an official CloudStream repo or Stremio addon in Addons.',
        ),
      );
      return;
    }

    _hasStartedFirstOpen = true;
    unawaited(
      _openRankedStream(
        best,
        startPosition: Duration(milliseconds: _pendingResumeMs),
        play: true,
      ),
    );
  }

  Future<void> _openRankedStream(
    RankedStream candidate, {
    required Duration startPosition,
    required bool play,
  }) async {
    final url = candidate.stream.url;
    if (url == null || url.isEmpty) {
      _handleActiveStreamFailure('Invalid stream URL');
      return;
    }

    final gen = ++_openGeneration;
    _tracksAppliedForOpen = false;
    _embeddedSkipSegments = const [];
    _chaptersLoadedForGen = -1;
    _rebuildMergedSkipSegments();
    _stallWatchdog?.cancel();
    _pauseScrapingTimer?.cancel();
    _pauseScrapingTimer = null;

    final headers = <String, String>{
      'User-Agent': _defaultUserAgent,
      ...candidate.stream.headers,
      if (candidate.stream.referer != null &&
          candidate.stream.referer!.trim().isNotEmpty &&
          !candidate.stream.headers.containsKey('Referer'))
        'Referer': candidate.stream.referer!.trim(),
    };

    _setState(
      _state.copyWith(
        activeStream: candidate,
        isBuffering: true,
        clearError: true,
      ),
    );

    _stallWatchdog = Timer(const Duration(seconds: 7), () {
      if (_disposed || gen != _openGeneration) return;
      final stalledAtStart = currentDuration == Duration.zero ||
          (_state.isBuffering &&
              (currentPosition - startPosition).abs() <
                  const Duration(seconds: 1));
      if (stalledAtStart &&
          (_state.isInitializing || _state.isSwitchingSource)) {
        _handleActiveStreamFailure('Source timed out');
      }
    });

    try {
      await _player.open(
        Media(
          url,
          httpHeaders: headers,
          start: startPosition > Duration.zero ? startPosition : null,
        ),
        play: play,
      );
      if (play && _state.playbackSpeed != 1.0) {
        await _player.setRate(_state.playbackSpeed);
      }
    } catch (e) {
      if (!_disposed && gen == _openGeneration) {
        _handleActiveStreamFailure(e.toString());
      }
    }
  }

  void _handleActiveStreamFailure(
    String reason, {
    bool forceFailover = false,
  }) {
    _stallWatchdog?.cancel();
    _pauseScrapingTimer?.cancel();
    _pauseScrapingTimer = null;

    final current = _state.activeStream;
    if (current != null) {
      _sessionFailedKeys.add(current.dedupKey);
      container
          .read(streamPrefetchControllerProvider.notifier)
          .markStreamFailed(_currentPrefetchKey, current.stream);
    }

    // If the user explicitly picked a link and it errored (not a runtime mismatch),
    // respect their choice and let them retry or pick another link instead of
    // silently hijacking playback to a random link.
    if (_userLockedStream && !forceFailover) {
      _setState(
        _state.copyWith(
          isInitializing: false,
          isSwitchingSource: false,
          isBuffering: false,
          errorMessage: reason,
        ),
      );
      return;
    }

    final resumeMs = currentPosition > Duration.zero
        ? currentPosition.inMilliseconds
        : _pendingResumeMs;

    final eligible = _state.rankedStreams
        .where((r) =>
            r.isAutoPlayEligible && !_sessionFailedKeys.contains(r.dedupKey))
        .toList()
      ..sort((a, b) => b.compositeScore.compareTo(a.compositeScore));
    final nextCandidate = eligible.firstOrNull;

    if (nextCandidate != null) {
      _showStatusBanner('Switching to ${nextCandidate.stream.providerName}...');
      _pendingResumeMs = resumeMs;
      _wasPlayingBeforeSwitch = true;
      unawaited(
        _openRankedStream(
          nextCandidate,
          startPosition: Duration(milliseconds: resumeMs),
          play: _wasPlayingBeforeSwitch,
        ),
      );
      return;
    }

    // If more providers were paused earlier, resume them automatically to find a fallback.
    if (_state.hasMoreSources) {
      _pendingResumeMs = resumeMs;
      _awaitingResumedFallback = true;
      _userLockedStream = false;
      _showStatusBanner('Searching more sources...');
      _setState(
        _state.copyWith(
          isSwitchingSource: true,
          isResolvingLinks: true,
          clearError: true,
        ),
      );
      unawaited(
        container
            .read(streamPrefetchControllerProvider.notifier)
            .resumePrefetch(_currentPrefetchKey),
      );
      return;
    }

    _setState(
      _state.copyWith(
        isInitializing: false,
        isSwitchingSource: false,
        isBuffering: false,
        errorMessage: reason,
      ),
    );
  }

  void _onTracksUpdated(Tracks tracks) {
    final prefSnap =
        container.read(streamPrefetchControllerProvider)[_currentPrefetchKey];
    final externalSubs = prefSnap?.subtitles ?? const <ResolvedSubtitle>[];
    final audioOpts = TrackOrchestrator.buildAudioOptions(tracks.audio);
    final subOpts = TrackOrchestrator.buildSubtitleOptions(
      tracks.subtitle,
      externalSubs,
    );

    final hasRealMediaTracks =
        tracks.video.any((v) => v.id != 'auto' && v.id != 'no') ||
            audioOpts.isNotEmpty;

    _setState(
      _state.copyWith(
        audioOptions: audioOpts,
        subtitleOptions: subOpts,
      ),
    );

    if (!hasRealMediaTracks || _tracksAppliedForOpen) return;
    _tracksAppliedForOpen = true;
    unawaited(_applyInitialTracks(audioOpts, subOpts));
  }

  Future<void> _applyInitialTracks(
    List<PlayerAudioOption> audioOpts,
    List<PlayerSubtitleOption> subOpts,
  ) async {
    final prefs =
        container.read(playbackPreferencesControllerProvider).valueOrNull ??
            const PlaybackPreferences();

    final pickedAudio = TrackOrchestrator.selectInitialAudio(
      options: audioOpts,
      prefs: prefs,
      preferredOverrideLang: _preferredAudioOverrideLang,
    );

    if (pickedAudio != null) {
      await _player.setAudioTrack(pickedAudio.track);
      _setState(_state.copyWith(selectedAudioId: pickedAudio.id));
    }

    final activeAudioLang = pickedAudio?.normalizedLang ??
        _state.activeStream?.meta.detectedAudioLanguages.firstOrNull;

    final pickedSub = TrackOrchestrator.selectInitialSubtitle(
      options: subOpts,
      prefs: prefs,
      activeAudioLang: activeAudioLang,
      userManualOverride: _userManualSubOverride,
      userChoseOff: _userChoseSubOff,
      previousSubLang: _previousSubLang,
    );
    await _applySubtitleOption(pickedSub, markManual: false);
  }

  Future<void> switchStream(RankedStream next) async {
    if (!next.stream.transport.isPlayableDirect) {
      await openExternalStream(next.stream);
      return;
    }
    // Lock the user's explicit selection so background link resolution NEVER
    // overrides or replaces what the user chose to play.
    _graceTimer?.cancel();
    _graceTimer = null;
    _hasStartedFirstOpen = true;
    _userLockedStream = true;
    _awaitingResumedFallback = false;

    final savedPos = currentPosition;
    final wasPlaying = _state.isPlaying;
    _pendingResumeMs = savedPos.inMilliseconds;
    _wasPlayingBeforeSwitch = wasPlaying;

    await flushProgress();
    _setState(
      _state.copyWith(
        isSwitchingSource: true,
        isInitializing: false,
        clearError: true,
      ),
    );
    await _openRankedStream(
      next,
      startPosition: savedPos,
      play: wasPlaying,
    );
  }

  Future<void> retryCurrentOrNext() async {
    _sessionFailedKeys.clear();
    _hasStartedFirstOpen = false;
    _userLockedStream = false;
    _awaitingResumedFallback = false;
    _setState(
      _state.copyWith(
        isInitializing: true,
        clearError: true,
      ),
    );
    await container
        .read(streamPrefetchControllerProvider.notifier)
        .prefetch(_state.query, forceRefresh: true);
  }

  Future<void> selectAudioTrack(PlayerAudioOption option) async {
    _preferredAudioOverrideLang = option.normalizedLang;
    await _player.setAudioTrack(option.track);
    _setState(_state.copyWith(selectedAudioId: option.id));

    if (!_userManualSubOverride) {
      final prefs =
          container.read(playbackPreferencesControllerProvider).valueOrNull ??
              const PlaybackPreferences();
      final smartSub = TrackOrchestrator.selectInitialSubtitle(
        options: _state.subtitleOptions,
        prefs: prefs,
        activeAudioLang: option.normalizedLang,
      );
      await _applySubtitleOption(smartSub, markManual: false);
    }
  }

  Future<void> selectSubtitleOption(PlayerSubtitleOption option) =>
      _applySubtitleOption(option, markManual: true);

  Future<void> _applySubtitleOption(
    PlayerSubtitleOption option, {
    required bool markManual,
  }) async {
    if (markManual) {
      _userManualSubOverride = true;
      _userChoseSubOff = option.isOff;
      _previousSubLang = option.isOff ? null : option.normalizedLang;
    }

    if (option.isOff) {
      await _player.setSubtitleTrack(SubtitleTrack.no());
      _setState(_state.copyWith(selectedSubtitleId: 'off'));
      return;
    }

    if (!option.isExternal && option.embeddedTrack != null) {
      await _player.setSubtitleTrack(option.embeddedTrack!);
      _setState(_state.copyWith(selectedSubtitleId: option.id));
      return;
    }

    final ext = option.externalSubtitle;
    if (ext == null) return;
    _setState(_state.copyWith(selectedSubtitleId: option.id));

    try {
      String uriToLoad = ext.url;
      if (ext.headers.isNotEmpty) {
        uriToLoad = await _downloadExternalSubToTemp(ext);
      }
      await _player.setSubtitleTrack(
        SubtitleTrack.uri(
          uriToLoad,
          title: option.displayLabel,
          language: option.normalizedLang ?? ext.language,
        ),
      );
    } catch (e) {
      _showStatusBanner('Could not load subtitle track');
      debugPrint('External sub load error: $e');
    }
  }

  Future<String> _downloadExternalSubToTemp(ResolvedSubtitle sub) async {
    final lowerUrl = sub.url.toLowerCase();
    final ext = lowerUrl.contains('.ass')
        ? '.ass'
        : lowerUrl.contains('.vtt')
            ? '.vtt'
            : '.srt';
    final file = File(
      '${Directory.systemTemp.path}/openflix_sub_${sub.url.hashCode}$ext',
    );
    if (!await file.exists()) {
      final resp = await _subDio.get<List<int>>(
        sub.url,
        options: Options(
          headers: sub.headers,
          responseType: ResponseType.bytes,
        ),
      );
      await file.writeAsBytes(resp.data ?? const [], flush: true);
    }
    return Uri.file(file.path).toString();
  }

  Future<void> togglePlayPause() => _player.playOrPause();

  Future<void> seekTo(Duration target) async {
    final dur = currentDuration;
    final clamped = dur > Duration.zero
        ? Duration(
            milliseconds: target.inMilliseconds.clamp(0, dur.inMilliseconds),
          )
        : (target.isNegative ? Duration.zero : target);
    await _player.seek(clamped);
    timelineNotifier.value = timelineNotifier.value.copyWith(position: clamped);
    if (dur > Duration.zero &&
        _reachedNextEpisodePoint &&
        !_isAtNextEpisodePoint(clamped, dur)) {
      _reachedNextEpisodePoint = false;
    }
    _evaluateActiveSkipSegment(clamped);
    if (dur > Duration.zero) {
      unawaited(flushProgress());
    }
  }

  Future<void> seekRelative(Duration delta) =>
      seekTo(currentPosition + delta);

  Future<void> setSpeed(double rate) async {
    await _player.setRate(rate);
    _setState(_state.copyWith(playbackSpeed: rate));
  }

  void setFitMode(VideoFitMode mode) {
    _setState(_state.copyWith(fitMode: mode));
  }

  void toggleFitModeByPinch(bool zoomIn) {
    final target = zoomIn ? VideoFitMode.fill : VideoFitMode.fit;
    if (_state.fitMode == target) return;
    _setState(_state.copyWith(fitMode: target));
    _showStatusBanner(zoomIn ? 'Zoomed to fill' : 'Original aspect fit');
  }

  Future<void> setSubtitleScale(double scale) async {
    subtitleScaleNotifier.value = scale;
    await container
        .read(playbackPreferencesControllerProvider.notifier)
        .setSubtitleScale(scale);
    final platform = _player.platform;
    if (platform is NativePlayer) {
      try {
        await platform.setProperty('sub-scale', scale.toStringAsFixed(2));
      } catch (_) {}
    }
  }

  Future<void> setAutoPlayNext(bool enabled) => container
      .read(playbackPreferencesControllerProvider.notifier)
      .setAutoPlayNext(enabled);

  Future<void> setAutoSkipIntroRecap(bool enabled) async {
    await container
        .read(playbackPreferencesControllerProvider.notifier)
        .setAutoSkipIntroRecap(enabled);
    if (enabled) {
      _evaluateActiveSkipSegment(currentPosition);
    }
  }

  Future<void> setAutoSkipOutro(bool enabled) async {
    await container
        .read(playbackPreferencesControllerProvider.notifier)
        .setAutoSkipOutro(enabled);
    if (!enabled) {
      _cancelAutoOutroCountdown();
    } else {
      _evaluateActiveSkipSegment(currentPosition);
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Skip Intro / Recap / Outro / Post-Credits & Smart Next Episode
  // ───────────────────────────────────────────────────────────────────────────

  void _resetSkipSegmentsForEpisode() {
    _skipFetchGeneration++;
    _onlineSkipSegments = const [];
    _embeddedSkipSegments = const [];
    _mergedSkipSegments = const [];
    _dismissedSkipTypes.clear();
    _autoSkippedTypes.clear();
    _reachedNextEpisodePoint = false;
    _chaptersLoadedForGen = -1;
    _cancelAutoOutroCountdown();
    if (activeSkipPromptNotifier.value != null) {
      activeSkipPromptNotifier.value = null;
    }
  }

  Future<void> _fetchOnlineSkipSegments(StreamQuery query) async {
    final fetchGen = _skipFetchGeneration;
    try {
      final repo = container.read(skipSegmentsRepositoryProvider);
      final durSec = currentDuration.inSeconds > 0
          ? currentDuration.inSeconds
          : null;
      final segments = await repo.fetchOnlineSegments(
        query,
        durationSec: durSec,
      );
      if (_disposed || fetchGen != _skipFetchGeneration) return;
      _onlineSkipSegments = segments;
      _rebuildMergedSkipSegments();
      _evaluateActiveSkipSegment(currentPosition);
    } catch (_) {}
  }

  Future<void> _readEmbeddedChapters(int openGen, int durationMs) async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    try {
      final raw = await platform.getProperty('chapter-list');
      if (_disposed || openGen != _openGeneration) return;
      final parsed = MpvChapterParser.parse(raw, durationMs: durationMs);
      if (parsed.isEmpty) return;
      _embeddedSkipSegments = parsed;
      _rebuildMergedSkipSegments();
      _evaluateActiveSkipSegment(currentPosition);
    } catch (_) {}
  }

  void _rebuildMergedSkipSegments() {
    _mergedSkipSegments = SkipSegmentsRepository.mergeAndSanitize(
      embedded: _embeddedSkipSegments,
      online: _onlineSkipSegments,
      durationMs: currentDuration.inMilliseconds,
    );
  }

  SkipSegment? _segmentOfType(SkipSegmentType type) {
    for (final s in _mergedSkipSegments) {
      if (s.type == type) return s;
    }
    return null;
  }

  bool _isAtNextEpisodePoint(Duration pos, Duration dur) {
    if (_state.query.mediaType != 'series' || dur <= Duration.zero) {
      return false;
    }
    final posMs = pos.inMilliseconds;
    final durMs = dur.inMilliseconds;

    final outro = _segmentOfType(SkipSegmentType.outro);
    final postCredits = _segmentOfType(SkipSegmentType.postCredits);
    final hasPostCreditsAfterOutro = outro != null &&
        postCredits != null &&
        postCredits.startMs >= outro.startMs;

    if (outro != null) {
      if (!hasPostCreditsAfterOutro && posMs >= outro.startMs) {
        return true;
      }
      if (hasPostCreditsAfterOutro && posMs >= postCredits.endMs - 8000) {
        return true;
      }
      if (posMs >= outro.endMs - 2000 && !hasPostCreditsAfterOutro) {
        return true;
      }
    }

    final frac = posMs / durMs;
    final rem = dur - pos;
    return frac >= 0.88 || (rem <= const Duration(seconds: 45) && frac >= 0.78);
  }

  void _triggerNextEpisodePrefetchIfNeeded(StreamQuery nextQ) {
    final nextKey = prefetchKeyForQuery(nextQ);
    if (_prefetchedNextKey != nextKey) {
      _prefetchedNextKey = nextKey;
      unawaited(
        container.read(streamPrefetchControllerProvider.notifier).prefetch(nextQ),
      );
    }
    if (_state.nextEpisodeQuery != nextQ) {
      _setState(_state.copyWith(nextEpisodeQuery: nextQ));
    }
  }

  void _evaluateActiveSkipSegment(Duration pos) {
    if (_disposed) return;
    final dur = currentDuration;
    if (dur <= Duration.zero) {
      _clearSkipPrompt();
      return;
    }

    final posMs = pos.inMilliseconds;
    final durMs = dur.inMilliseconds;
    final isSeries = _state.query.mediaType == 'series';
    final nextQ = isSeries ? (_state.nextEpisodeQuery ?? _resolveNextEpisodeQuery()) : null;

    // Promote the next episode in Continue Watching as soon as the user reaches
    // the Next Episode point (outro without post-credits, or final ~12%/45s).
    if (isSeries && _isAtNextEpisodePoint(pos, dur)) {
      if (nextQ != null) {
        _triggerNextEpisodePrefetchIfNeeded(nextQ);
      }
      if (!_reachedNextEpisodePoint) {
        _reachedNextEpisodePoint = true;
        unawaited(flushProgress(forceCompleted: true));
      }
    }

    ActiveSkipPrompt? candidate;
    final postCredits = _segmentOfType(SkipSegmentType.postCredits);

    // 1. Check explicit segments in priority order: recap -> intro -> outro.
    for (final seg in _mergedSkipSegments) {
      if (!seg.isActiveAt(posMs)) continue;
      if (seg.type == SkipSegmentType.recap) {
        candidate = ActiveSkipPrompt(
          segment: seg,
          actionKind: SkipActionKind.skipRecap,
          targetSeekMs: seg.endMs,
        );
        break;
      }
      if (seg.type == SkipSegmentType.intro) {
        candidate = ActiveSkipPrompt(
          segment: seg,
          actionKind: SkipActionKind.skipIntro,
          targetSeekMs: seg.endMs,
        );
        break;
      }
      if (seg.type == SkipSegmentType.outro) {
        if (postCredits != null && postCredits.startMs >= seg.startMs) {
          candidate = ActiveSkipPrompt(
            segment: seg,
            actionKind: SkipActionKind.skipToPostCredits,
            targetSeekMs: postCredits.startMs,
          );
        } else if (isSeries && nextQ != null) {
          _triggerNextEpisodePrefetchIfNeeded(nextQ);
          candidate = ActiveSkipPrompt(
            segment: seg,
            actionKind: SkipActionKind.nextEpisode,
            nextEpisodeBadge: 'S${nextQ.season ?? 1}E${nextQ.episode ?? 1}',
          );
        } else {
          candidate = ActiveSkipPrompt(
            segment: seg,
            actionKind: SkipActionKind.skipCredits,
            targetSeekMs: seg.endMs,
          );
        }
        break;
      }
    }

    // 2. Fallback Next Episode CTA for series when no explicit outro covers the
    // end (or after a post-credits scene finishes).
    if (candidate == null && isSeries && nextQ != null) {
      final insidePostCredits =
          postCredits != null && postCredits.isActiveAt(posMs);
      if (!insidePostCredits && _isAtNextEpisodePoint(pos, dur)) {
        _triggerNextEpisodePrefetchIfNeeded(nextQ);
        candidate = ActiveSkipPrompt(
          segment: SkipSegment(
            type: SkipSegmentType.outro,
            startMs: posMs,
            endMs: durMs,
            source: SkipSegmentSource.fallbackEnd,
          ),
          actionKind: SkipActionKind.nextEpisode,
          nextEpisodeBadge: 'S${nextQ.season ?? 1}E${nextQ.episode ?? 1}',
        );
      }
    }

    if (candidate == null || _dismissedSkipTypes.contains(candidate.segment.type)) {
      _clearSkipPrompt();
      return;
    }

    final prefs =
        container.read(playbackPreferencesControllerProvider).valueOrNull ??
            const PlaybackPreferences();

    // Auto-skip Intro & Recap (once per segment type to avoid rewind loops).
    if (_state.isPlaying &&
        prefs.autoSkipIntroRecap &&
        (candidate.actionKind == SkipActionKind.skipIntro ||
            candidate.actionKind == SkipActionKind.skipRecap) &&
        !_autoSkippedTypes.contains(candidate.segment.type) &&
        candidate.targetSeekMs != null) {
      _autoSkippedTypes.add(candidate.segment.type);
      _clearSkipPrompt();
      final label = candidate.actionKind == SkipActionKind.skipIntro
          ? 'Skipped intro'
          : 'Skipped recap';
      _showStatusBanner(label);
      unawaited(seekTo(Duration(milliseconds: candidate.targetSeekMs!)));
      return;
    }

    // Auto-skip Outro (instant jump to post-credits / credits end, or 5s
    // cancellable countdown for Next Episode).
    if (_state.isPlaying &&
        prefs.autoSkipOutro &&
        !_autoSkippedTypes.contains(SkipSegmentType.outro)) {
      if (candidate.actionKind == SkipActionKind.skipToPostCredits &&
          candidate.targetSeekMs != null) {
        _autoSkippedTypes.add(SkipSegmentType.outro);
        _clearSkipPrompt();
        _showStatusBanner('Skipped to post-credits');
        unawaited(seekTo(Duration(milliseconds: candidate.targetSeekMs!)));
        return;
      }
      if (candidate.actionKind == SkipActionKind.skipCredits &&
          candidate.targetSeekMs != null) {
        _autoSkippedTypes.add(SkipSegmentType.outro);
        _clearSkipPrompt();
        _showStatusBanner('Skipped outro');
        unawaited(seekTo(Duration(milliseconds: candidate.targetSeekMs!)));
        return;
      }
      if (candidate.actionKind == SkipActionKind.nextEpisode) {
        _ensureAutoOutroCountdown(candidate);
        return;
      }
    }

    _cancelAutoOutroCountdown();
    if (activeSkipPromptNotifier.value != candidate) {
      activeSkipPromptNotifier.value = candidate;
    }
  }

  void _ensureAutoOutroCountdown(ActiveSkipPrompt basePrompt) {
    if (_autoOutroCountdownTimer != null &&
        _activeCountdownKind == basePrompt.actionKind) {
      return;
    }
    _cancelAutoOutroCountdown();
    _activeCountdownKind = basePrompt.actionKind;
    _autoOutroSecondsLeft = 5;
    activeSkipPromptNotifier.value =
        basePrompt.copyWith(autoSkipCountdownSec: _autoOutroSecondsLeft);

    _autoOutroCountdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_disposed || !_state.isPlaying) {
        _cancelAutoOutroCountdown();
        return;
      }
      final left = (_autoOutroSecondsLeft ?? 1) - 1;
      if (left <= 0) {
        _autoSkippedTypes.add(SkipSegmentType.outro);
        _cancelAutoOutroCountdown();
        activeSkipPromptNotifier.value = null;
        unawaited(playNextEpisode());
        return;
      }
      _autoOutroSecondsLeft = left;
      final cur = activeSkipPromptNotifier.value ?? basePrompt;
      activeSkipPromptNotifier.value =
          cur.copyWith(autoSkipCountdownSec: left);
    });
  }

  void _cancelAutoOutroCountdown() {
    _autoOutroCountdownTimer?.cancel();
    _autoOutroCountdownTimer = null;
    _autoOutroSecondsLeft = null;
    _activeCountdownKind = null;
  }

  void _clearSkipPrompt() {
    _cancelAutoOutroCountdown();
    if (activeSkipPromptNotifier.value != null) {
      activeSkipPromptNotifier.value = null;
    }
  }

  /// Executes the currently visible Skip / Smart Outro / Next Episode action.
  Future<void> triggerActiveSkip() async {
    final prompt = activeSkipPromptNotifier.value;
    if (prompt == null) return;
    _cancelAutoOutroCountdown();

    if (prompt.actionKind == SkipActionKind.nextEpisode) {
      _autoSkippedTypes.add(SkipSegmentType.outro);
      activeSkipPromptNotifier.value = null;
      await playNextEpisode();
      return;
    }

    final targetMs = prompt.targetSeekMs;
    _autoSkippedTypes.add(prompt.segment.type);
    activeSkipPromptNotifier.value = null;
    if (targetMs != null) {
      await seekTo(Duration(milliseconds: targetMs));
    }
  }

  /// Dismisses the active skip prompt & cancels any auto-skip countdown.
  void dismissActiveSkip() {
    final prompt = activeSkipPromptNotifier.value;
    if (prompt != null) {
      _dismissedSkipTypes.add(prompt.segment.type);
      _autoSkippedTypes.add(prompt.segment.type);
    }
    _clearSkipPrompt();
  }

  Future<void> setHardwareDecoding(bool enabled) async {
    await container
        .read(playbackPreferencesControllerProvider.notifier)
        .setHardwareDecoding(enabled);
    final platform = _player.platform;
    if (platform is NativePlayer) {
      try {
        await platform.setProperty(
          'hwdec',
          enabled ? 'mediacodec,mediacodec-copy' : 'no',
        );
      } catch (_) {}
    }
  }

  Future<bool> openExternalStream(ResolvedStream stream) async {
    final target = stream.playableOrCopyableTarget;
    if (target == null) return false;
    try {
      return await _launcherChannel.invokeMethod<bool>(
            'openUrl',
            {'url': target},
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  void _maybePrefetchNextEpisode() {
    if (_state.query.mediaType != 'series') return;
    final dur = currentDuration;
    if (dur <= Duration.zero) return;
    final pos = currentPosition;
    final frac = pos.inMilliseconds / dur.inMilliseconds;
    final rem = dur - pos;
    if (frac < 0.88 && rem > const Duration(seconds: 45)) return;

    final nextQ = _resolveNextEpisodeQuery();
    if (nextQ == null) return;
    final nextKey = prefetchKeyForQuery(nextQ);
    if (_prefetchedNextKey != nextKey) {
      _prefetchedNextKey = nextKey;
      unawaited(
        container.read(streamPrefetchControllerProvider.notifier).prefetch(nextQ),
      );
    }
    if (!_state.showNextEpisodePrompt || _state.nextEpisodeQuery != nextQ) {
      _setState(
        _state.copyWith(
          nextEpisodeQuery: nextQ,
          showNextEpisodePrompt: true,
        ),
      );
    }
  }

  StreamQuery? _resolveNextEpisodeQuery() {
    final q = _state.query;
    final s = q.season ?? 1;
    final e = q.episode ?? 1;

    final cachedSeason = _seasonsCache[s];
    if (cachedSeason != null) {
      final sorted = [...cachedSeason.episodes]
        ..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
      for (final ep in sorted) {
        if (ep.episodeNumber > e) {
          return StreamQuery(
            mediaType: q.mediaType,
            title: q.title,
            originalTitle: q.originalTitle,
            year: q.year,
            imdbId: q.imdbId,
            tmdbId: q.tmdbId,
            anilistId: q.anilistId,
            kitsuId: q.kitsuId,
            malId: q.malId,
            rawMetaId: q.rawMetaId,
            sourceAddonId: q.sourceAddonId,
            season: s,
            episode: ep.episodeNumber,
            episodeTitle: ep.name,
            expectedRuntimeMinutes: ep.runtimeMinutes,
            isAnime: q.isAnime,
            preferredLanguages: q.preferredLanguages,
          );
        }
      }
      final nextSeason = _seasons
          .where((ss) => ss.seasonNumber > s)
          .toList()
        ..sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));
      if (nextSeason.isNotEmpty) {
        final targetSeason = nextSeason.first;
        final nextEps = _seasonsCache[targetSeason.seasonNumber]?.episodes;
        final firstEp = nextEps?.firstOrNull;
        return StreamQuery(
          mediaType: q.mediaType,
          title: q.title,
          originalTitle: q.originalTitle,
          year: q.year,
          imdbId: q.imdbId,
          tmdbId: q.tmdbId,
          anilistId: q.anilistId,
          kitsuId: q.kitsuId,
          malId: q.malId,
          rawMetaId: q.rawMetaId,
          sourceAddonId: q.sourceAddonId,
          season: targetSeason.seasonNumber,
          episode: firstEp?.episodeNumber ?? 1,
          episodeTitle: firstEp?.name,
          expectedRuntimeMinutes: firstEp?.runtimeMinutes,
          isAnime: q.isAnime,
          preferredLanguages: q.preferredLanguages,
        );
      }
      return null;
    }

    final summary = _seasons.where((ss) => ss.seasonNumber == s).firstOrNull;
    if (summary != null &&
        summary.episodeCount > 0 &&
        e >= summary.episodeCount) {
      final nextSeasons = _seasons
          .where((ss) => ss.seasonNumber > s)
          .toList()
        ..sort((a, b) => a.seasonNumber.compareTo(b.seasonNumber));
      if (nextSeasons.isEmpty) return null;
      return StreamQuery(
        mediaType: q.mediaType,
        title: q.title,
        originalTitle: q.originalTitle,
        year: q.year,
        imdbId: q.imdbId,
        tmdbId: q.tmdbId,
        anilistId: q.anilistId,
        kitsuId: q.kitsuId,
        malId: q.malId,
        rawMetaId: q.rawMetaId,
        sourceAddonId: q.sourceAddonId,
        season: nextSeasons.first.seasonNumber,
        episode: 1,
        isAnime: q.isAnime,
        preferredLanguages: q.preferredLanguages,
      );
    }

    return StreamQuery(
      mediaType: q.mediaType,
      title: q.title,
      originalTitle: q.originalTitle,
      year: q.year,
      imdbId: q.imdbId,
      tmdbId: q.tmdbId,
      anilistId: q.anilistId,
      kitsuId: q.kitsuId,
      malId: q.malId,
      rawMetaId: q.rawMetaId,
      sourceAddonId: q.sourceAddonId,
      season: s,
      episode: e + 1,
      isAnime: q.isAnime,
      preferredLanguages: q.preferredLanguages,
    );
  }

  Future<void> playNextEpisode() async {
    final nextQ = _state.nextEpisodeQuery ?? _resolveNextEpisodeQuery();
    if (nextQ == null) return;
    await flushProgress(forceCompleted: true);

    _stallWatchdog?.cancel();
    _graceTimer?.cancel();
    _graceTimer = null;
    _pauseScrapingTimer?.cancel();
    _pauseScrapingTimer = null;
    _sessionFailedKeys.clear();
    _hasStartedFirstOpen = false;
    _userLockedStream = false;
    _awaitingResumedFallback = false;
    _pendingResumeMs = 0;
    _prefetchedNextKey = null;

    await _player.stop();
    timelineNotifier.value = const PlayerTimelineState();

    _setState(
      PlayerUiState(
        query: nextQ,
        isInitializing: true,
        isResolvingLinks: true,
        playbackSpeed: _state.playbackSpeed,
        fitMode: _state.fitMode,
      ),
    );
    _bindPrefetch(nextQ);
  }

  Future<void> flushProgress({bool forceCompleted = false}) async {
    final dur = currentDuration.inMilliseconds;
    final pos = currentPosition.inMilliseconds;
    final effectiveCompleted = forceCompleted ||
        (_state.query.mediaType == 'series' && _reachedNextEpisodePoint);
    if (dur <= 0 && !effectiveCompleted) return;
    final q = _state.query;
    final isSeries = q.mediaType == 'series';
    final isDone = effectiveCompleted || isPositionCompleted(pos, dur);
    StreamQuery? nextQ;
    bool seriesFinished = false;
    if (isSeries && isDone) {
      nextQ = _state.nextEpisodeQuery ?? _resolveNextEpisodeQuery();
      final hasKnownSeasonInfo =
          _seasons.isNotEmpty || _seasonsCache.isNotEmpty;
      seriesFinished = nextQ == null && hasKnownSeasonInfo;
    }
    await container
        .read(watchProgressControllerProvider.notifier)
        .recordProgress(
          mediaType: q.mediaType,
          title: q.title,
          imdbId: q.imdbId,
          tmdbId: q.tmdbId,
          anilistId: q.anilistId,
          rawId: q.rawMetaId,
          isAnime: q.isAnime,
          posterUrl: initialArgs.posterUrl,
          backdropUrl: initialArgs.backdropUrl,
          logoUrl: initialArgs.logoUrl,
          logoAspectRatio: initialArgs.logoAspectRatio,
          genres: initialArgs.genres,
          imdbRating: initialArgs.imdbRating,
          releaseYear: initialArgs.releaseYear ?? q.year?.toString(),
          expectedRuntimeMinutes: q.expectedRuntimeMinutes,
          season: q.season,
          episode: q.episode,
          positionMs: pos,
          durationMs: dur,
          forceCompleted: effectiveCompleted,
          nextSeason: nextQ?.season,
          nextEpisode: nextQ?.episode,
          nextEpisodeRuntimeMinutes: nextQ?.expectedRuntimeMinutes,
          seriesCompleted: seriesFinished,
        );
  }

  void _showStatusBanner(String msg) {
    _statusBannerTimer?.cancel();
    _setState(_state.copyWith(statusBanner: msg));
    _statusBannerTimer = Timer(const Duration(seconds: 3), () {
      if (!_disposed) {
        _setState(_state.copyWith(clearStatusBanner: true));
      }
    });
  }

  void _setState(PlayerUiState next) {
    if (_disposed || next == _state) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    unawaited(flushProgress());
    final keyToPause = _currentPrefetchKey;
    try {
      final prefetchNotifier =
          container.read(streamPrefetchControllerProvider.notifier);
      Future.microtask(() => prefetchNotifier.pausePrefetch(keyToPause));
    } catch (_) {}

    _disposed = true;
    _graceTimer?.cancel();
    _stallWatchdog?.cancel();
    _pauseScrapingTimer?.cancel();
    _progressFlushTimer?.cancel();
    _statusBannerTimer?.cancel();
    _autoOutroCountdownTimer?.cancel();
    _prefetchSub?.close();
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _updateWakelock(false);
    timelineNotifier.dispose();
    subtitleScaleNotifier.dispose();
    activeSkipPromptNotifier.dispose();
    _player.dispose();
    super.dispose();
  }
}
