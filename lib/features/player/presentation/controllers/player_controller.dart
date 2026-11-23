import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../../core/errors/user_error.dart';
import '../../../addons/domain/models/stream_models.dart';
import '../../../details/data/tmdb_models.dart';
import '../../../details/data/tmdb_repository.dart';
import '../../../preferences/domain/models/playback_preferences.dart';
import '../../../preferences/presentation/controllers/playback_preferences_controller.dart';
import '../../data/skip_segments_service.dart';
import '../../data/stream_metadata_parser.dart';
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
  // Use `auto-copy` on Android so MediaCodec handles supported codecs via safe
  // copy-back buffers (avoiding MediaTek SurfaceTexture deadlocks) and
  // automatically falls back to FFmpeg software decoding for unsupported
  // codecs/profiles (10-bit HEVC, AV1, VC-1, MPEG-2, H.264 Hi10P anime).
  static const _stableAndroidHwdec = 'auto-copy';

  late Player _player;
  late VideoController _videoController;
  late final Future<void> _mpvConfigReady;
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
  Duration get effectivePosition =>
      _lastValidPosition > Duration.zero ? _lastValidPosition : currentPosition;
  Duration get effectiveDuration =>
      _lastValidDuration > Duration.zero ? _lastValidDuration : currentDuration;

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
  Timer? _videoStallTimer;
  Timer? _statusBannerTimer;
  Timer? _autoOutroCountdownTimer;

  bool _disposed = false;
  bool _hasStartedFirstOpen = false;
  bool _userLockedStream = false;
  bool _tracksAppliedForOpen = false;
  bool _linksModalOpen = false;
  bool _awaitingResumedFallback = false;
  bool _isOpeningStream = false;
  bool _isRecoveringStream = false;
  bool _isTransitioningEpisode = false;
  bool _prematureEofDetected = false;
  bool _hasReceivedDurationForOpen = false;
  bool _wakelockEnabled = false;
  bool _hwdecPreferred = true;
  bool _fellBackToSoftwareForStream = false;
  bool _checkingVideoStall = false;
  int _consecutiveVideoStallTicks = 0;
  int _openGeneration = 0;
  int _sameStreamRecoveryAttempts = 0;
  static const int _maxSameStreamRecoveries = 2;

  // Position & duration preservation across stalls, reloads, and premature EOF
  Duration _lastValidPosition = Duration.zero;
  Duration _lastValidDuration = Duration.zero;
  Duration? _pendingPostOpenSeek;
  bool _postOpenSeekDispatched = false;
  Duration? _recoveryBaselinePos;

  // Skip segments & Next Episode promotion state
  List<SkipSegment> _onlineSkipSegments = const [];
  List<SkipSegment> _embeddedSkipSegments = const [];
  List<SkipSegment> _mergedSkipSegments = const [];
  final Set<SkipSegmentType> _dismissedSkipTypes = <SkipSegmentType>{};
  final Set<SkipSegmentType> _autoSkippedTypes = <SkipSegmentType>{};
  bool _reachedNextEpisodePoint = false;
  int _skipFetchGeneration = 0;
  int _chaptersLoadedForGen = -1;
  int _onlineSkipFetchedDurationSec = 0;
  int? _autoOutroSecondsLeft;
  SkipActionKind? _activeCountdownKind;

  // Switching / Failover memory
  final Set<String> _sessionFailedKeys = <String>{};
  final Set<String> _previousEpisodeStreamKeys = <String>{};
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
    if (initialArgs.initialPositionMs > 0) {
      _lastValidPosition = Duration(milliseconds: initialArgs.initialPositionMs);
    }

    final prefs =
        container.read(playbackPreferencesControllerProvider).valueOrNull ??
            const PlaybackPreferences();
    _hwdecPreferred = prefs.hardwareDecoding;
    subtitleScaleNotifier.value = prefs.subtitleScale;

    // 16 MiB forward demuxer budget keeps RAM lean on 3 GB Android devices
    // (<0.7% RAM) while preventing high-bitrate 1080p video packet starvation.
    // libass: false routes decoded embedded & external subtitle text cleanly
    // through Flutter's native SubtitleView (reliable rendering + low RAM).
    _player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 16 * 1024 * 1024,
        libass: false,
        logLevel: MPVLogLevel.error,
      ),
    );
    _videoController = VideoController(
      _player,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: prefs.hardwareDecoding,
        // Use `auto-copy` so MediaCodec handles supported formats cleanly and
        // automatically falls back to FFmpeg software decoding for exotic profiles.
        hwdec: prefs.hardwareDecoding ? _stableAndroidHwdec : 'no',
      ),
    );

    final initialStream = initialArgs.initialStream;
    final hasPlayableInitial =
        initialStream != null && initialStream.canPlayInternally;
    if (hasPlayableInitial) {
      // Lock BEFORE _bindPrefetch(fireImmediately: true) so cached prefetch
      // snapshots never race and override the user-selected stream.
      _hasStartedFirstOpen = true;
      _userLockedStream = true;
    }

    _mpvConfigReady = _configureNativeMpvProperties(prefs);
    _attachPlayerListeners();
    _syncWakelock();
    _startProgressFlushTimer();
    _startVideoStallMonitor();
    _bindPrefetch(_state.query);

    if (hasPlayableInitial) {
      final rankedInitial = RankedStream(
        stream: initialStream,
        meta: StreamMetadataParser.parse(
          initialStream,
          mediaTitle: _state.query.title,
        ),
        languageMatchTier: LanguageMatchTier.originalOrUnknown,
        compositeScore: 1000,
        isAutoPlayEligible: true,
      );
      unawaited(
        _openRankedStream(
          rankedInitial,
          startPosition: Duration(milliseconds: _pendingResumeMs),
          play: true,
        ),
      );
    }
  }

  Future<void> _configureNativeMpvProperties(PlaybackPreferences prefs) async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;

    Future<void> safeSet(String k, String v) async {
      if (_disposed) return;
      try {
        await platform.setProperty(k, v);
      } catch (_) {}
    }

    const lavfReconnectOpts =
        'reconnect=1,reconnect_streamed=1,reconnect_on_network_error=1,'
        'reconnect_on_http_error=5xx,reconnect_delay_max=5';

    // Preserve media_kit's protocol_whitelist / allowed_extensions in demuxer-lavf-o
    // while appending FFmpeg reconnect flags so HLS segment fetches also reconnect.
    final demuxerLavfOpts = [
      'seg_max_retry=5',
      'strict=experimental',
      'allowed_extensions=ALL',
      'protocol_whitelist=[${platform.configuration.protocolWhitelist.join(',')}]',
      lavfReconnectOpts,
    ].join(',');

    // Resilient network & EOF handling:
    // - keep-open=yes keeps the frame/state alive instead of closing on EOF.
    // - network-timeout=20 overrides media_kit's aggressive 5s default.
    // - stream-lavf-o & demuxer-lavf-o enable FFmpeg HTTP/TCP & HLS auto-reconnect.
    await Future.wait([
      safeSet('keep-open', 'yes'),
      safeSet('network-timeout', '20'),
      safeSet('stream-lavf-o', lavfReconnectOpts),
      safeSet('demuxer-lavf-o', demuxerLavfOpts),
      safeSet('force-seekable', 'yes'),
      // Strict 16 MiB / 4 MiB RAM cache ceiling so mpv never starves a 3 GB
      // phone while preventing video packet starvation on 1080p streams and
      // avoiding Android disk-cache I/O stalls.
      safeSet('cache', 'yes'),
      safeSet('cache-on-disk', 'no'),
      safeSet('cache-pause', 'yes'),
      safeSet('cache-pause-wait', '3'),
      safeSet('demuxer-max-bytes', '16MiB'),
      safeSet('demuxer-max-back-bytes', '4MiB'),
      safeSet('demuxer-readahead-secs', '20'),
      safeSet('cache-secs', '20'),
      // Video/audio sync & Android hardware-decoder freeze prevention:
      // - video-sync=audio locks video presentation to audio clock (immune to
      //   Oplus/Android VRR refresh-rate changes).
      // - framedrop=vo + hr-seek-framedrop=yes drop late frames cleanly instead
      //   of freezing for seconds during catch-up/seeks (overrides media_kit's
      //   hr-seek-framedrop=no).
      // - vd-lavc-dr=no & opengl-pbo=no prevent MediaTek/Mali buffer-pool and
      //   GLES upload deadlocks.
      // - correct-pts=yes ensures accurate frame timing on B-frame/VFR streams.
      safeSet('video-sync', 'audio'),
      safeSet('framedrop', 'vo'),
      safeSet('hr-seek-framedrop', 'yes'),
      safeSet('correct-pts', 'yes'),
      safeSet('hwdec-extra-frames', '4'),
      safeSet('vd-lavc-dr', 'no'),
      safeSet('opengl-pbo', 'no'),
      safeSet('vd-lavc-fast', 'yes'),
      safeSet('vd-lavc-skiploopfilter', 'nonref'),
      safeSet('vd-lavc-threads', '0'),
      // Lightweight mobile HDR tone-mapping so 10-bit HDR10/HLG streams look
      // natural on SDR phone panels without stalling low-end mobile GPUs.
      safeSet('tone-mapping', 'reinhard'),
      safeSet('hdr-compute-peak', 'no'),
      safeSet('scale', 'bilinear'),
      safeSet('cscale', 'bilinear'),
      safeSet('dscale', 'bilinear'),
      safeSet('correct-downscaling', 'no'),
      safeSet('dither-depth', 'no'),
      // Universal mobile audio decoding (AC3, E-AC3/Atmos, DTS, DTS-HD, TrueHD,
      // FLAC, Opus, 5.1/7.1): disable raw bitstream passthrough and downmix
      // cleanly to normalized stereo so Android AudioTrack/OpenSL ES never
      // rejects or clips surround tracks.
      safeSet('audio-spdif', ''),
      safeSet('audio-channels', 'stereo'),
      safeSet('ad-lavc-downmix', 'yes'),
      safeSet('audio-normalize-downmix', 'yes'),
      // Subtitles: expose embedded SRT/ASS/PGS/VobSub and preserve ASS styling.
      safeSet('sub-auto', 'no'),
      safeSet('sub-visibility', 'yes'),
      safeSet('sub-ass-override', 'no'),
      safeSet('sub-scale', prefs.subtitleScale.toStringAsFixed(2)),
    ]);
  }

  bool _isNearGenuineEnd(Duration pos, Duration dur) {
    if (dur <= Duration.zero) return false;
    final remaining = dur - pos;
    final frac = pos.inMilliseconds / dur.inMilliseconds;
    return remaining <= const Duration(seconds: 15) || frac >= 0.97;
  }

  void _attachPlayerListeners() {
    _subs.add(
      _player.stream.playing.listen((playing) {
        if (_disposed) return;
        _setState(_state.copyWith(isPlaying: playing));
        _syncWakelock();
        if (playing) {
          _prematureEofDetected = false;
          _maybeSchedulePauseBackgroundScraping();
          _evaluateActiveSkipSegment(effectivePosition);
        } else {
          _cancelAutoOutroCountdown();
          if (effectiveDuration > Duration.zero && !_isOpeningStream) {
            unawaited(flushProgress());
          }
        }
      }),
    );

    _subs.add(
      _player.stream.buffering.listen((buffering) {
        if (_disposed) return;
        _setState(_state.copyWith(isBuffering: buffering));
        _syncWakelock();
        if (!buffering && effectiveDuration > Duration.zero) {
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

        // Ignore spurious Duration.zero emissions during buffering, reload,
        // stream open/stop, or error transitions once we have valid progress.
        if (pos == Duration.zero) {
          if (_lastValidPosition > Duration.zero ||
              _isOpeningStream ||
              _isRecoveringStream ||
              _state.isBuffering ||
              _state.isSwitchingSource) {
            return;
          }
          if (timelineNotifier.value.position != Duration.zero) {
            timelineNotifier.value =
                timelineNotifier.value.copyWith(position: Duration.zero);
          }
          return;
        }

        // If a resume/recovery open intended to start at a saved timestamp,
        // but the remote server ignored mpv's `start=` option and started near
        // 00:00, force a one-shot seek back to the saved timestamp and ignore
        // early low-position ticks while the seek is in flight so
        // _lastValidPosition is never clobbered.
        final pendingSeek = _pendingPostOpenSeek;
        if (pendingSeek != null) {
          if (pos < const Duration(seconds: 4) &&
              pendingSeek > const Duration(seconds: 5)) {
            if (!_postOpenSeekDispatched) {
              _postOpenSeekDispatched = true;
              unawaited(_player.seek(pendingSeek));
            }
            if (timelineNotifier.value.position != pendingSeek) {
              timelineNotifier.value =
                  timelineNotifier.value.copyWith(position: pendingSeek);
            }
            return;
          }
          _pendingPostOpenSeek = null;
          _postOpenSeekDispatched = false;
        }

        final previousResumeMs = _pendingResumeMs;
        _lastValidPosition = pos;
        _pendingResumeMs = pos.inMilliseconds;

        // Once playback advances cleanly for >=5s after recovery, reset the
        // same-stream recovery budget so later transient hiccups can recover.
        final baseline = _recoveryBaselinePos;
        if (baseline != null &&
            _state.isPlaying &&
            !_state.isBuffering &&
            (pos - baseline).abs() >= const Duration(seconds: 5)) {
          _recoveryBaselinePos = null;
          _sameStreamRecoveryAttempts = 0;
        }

        final cur = timelineNotifier.value;
        // Throttle tiny sub-250ms jitters to reduce seekbar repaints.
        if ((pos - cur.position).abs() >= const Duration(milliseconds: 250)) {
          timelineNotifier.value = cur.copyWith(position: pos);
        }

        if (pos.inMilliseconds != previousResumeMs &&
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
          _syncWakelock();
        }
        _maybeSchedulePauseBackgroundScraping();
        _maybePrefetchNextEpisode();
        _evaluateActiveSkipSegment(pos);
      }),
    );

    _subs.add(
      _player.stream.duration.listen((dur) {
        if (_disposed) return;

        // Ignore transient Duration.zero resets during reloads/recoveries so
        // the seekbar and remaining time do not collapse to 00:00.
        if (dur <= Duration.zero) {
          if (_lastValidDuration > Duration.zero &&
              (_isOpeningStream ||
                  _isRecoveringStream ||
                  _state.isSwitchingSource)) {
            return;
          }
          if (_lastValidDuration == Duration.zero) {
            timelineNotifier.value =
                timelineNotifier.value.copyWith(duration: Duration.zero);
          }
          return;
        }

        // Instant TMDB runtime verification: reject trailers or wrong movies/episodes
        // as soon as mpv reads container headers (<500ms), hide the bad link from
        // the Links sheet, and switch cleanly to the next valid link.
        final active = _state.activeStream;
        final expectedMin = _state.query.expectedRuntimeMinutes;
        if (active != null &&
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

        _hasReceivedDurationForOpen = true;
        _lastValidDuration = dur;
        timelineNotifier.value = timelineNotifier.value.copyWith(duration: dur);
        _stallWatchdog?.cancel();
        if (_state.isInitializing || _state.isSwitchingSource) {
          _setState(
            _state.copyWith(
              isInitializing: false,
              isSwitchingSource: false,
            ),
          );
          _syncWakelock();
        }
        _maybeSchedulePauseBackgroundScraping();
        if (_chaptersLoadedForGen != _openGeneration) {
          _chaptersLoadedForGen = _openGeneration;
          unawaited(_readEmbeddedChapters(_openGeneration, dur.inMilliseconds));
        }
        // Re-fetch online skip timestamps (especially AniSkip) once the exact
        // video container duration is known so release-cut matching is accurate.
        if (dur.inSeconds > 0 &&
            (_onlineSkipFetchedDurationSec <= 0 ||
                (dur.inSeconds - _onlineSkipFetchedDurationSec).abs() > 10)) {
          unawaited(
            _fetchOnlineSkipSegments(_state.query, durationSec: dur.inSeconds),
          );
        }
        _rebuildMergedSkipSegments();
        _evaluateActiveSkipSegment(effectivePosition);
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
        if (_state.activeStream == null || _isRecoveringStream) return;

        final lowerErr = err.toLowerCase();

        // Never let a broken/unreachable external subtitle URL disrupt active
        // video playback.
        if (_hasReceivedDurationForOpen &&
            (lowerErr.contains('sub') ||
                lowerErr.contains('.srt') ||
                lowerErr.contains('.vtt') ||
                lowerErr.contains('.ass')) &&
            !lowerErr.contains('video') &&
            !lowerErr.contains('audio') &&
            !lowerErr.contains('demux')) {
          return;
        }

        // If hardware video decoding errors (common on Android MediaCodec with
        // 10-bit HEVC, H.264 Hi10P, AV1, or MediaTek profiles), automatically
        // retry this same stream once with pure software decoding (`hwdec=no`)
        // at `_lastValidPosition` before giving up or failing over.
        if (_hwdecPreferred &&
            !_fellBackToSoftwareForStream &&
            _isDecoderError(lowerErr)) {
          final needsReopen = !_hasReceivedDurationForOpen ||
              (_player.state.width ?? 0) <= 0 ||
              _state.isInitializing ||
              _state.isSwitchingSource;
          unawaited(
            _fallbackToSoftwareDecoding(
              reason: 'decoder error',
              forceReopen: needsReopen,
            ),
          );
          return;
        }

        // During initial open or source switch (before valid playback starts),
        // fail over immediately as before.
        if (_state.isInitializing ||
            _state.isSwitchingSource ||
            _lastValidDuration == Duration.zero) {
          _handleActiveStreamFailure('Playback error: $err');
          return;
        }

        // Mid-stream error during active playback: try reconnecting the same
        // stream at _lastValidPosition before failing over or showing an error.
        if (_sameStreamRecoveryAttempts < _maxSameStreamRecoveries &&
            effectivePosition > Duration.zero) {
          unawaited(
            _recoverActiveStreamAtLastPosition(
              play: _state.isPlaying || _state.isBuffering,
            ),
          );
        } else if (_state.isBuffering) {
          _handleActiveStreamFailure('Playback error: $err');
        }
      }),
    );

    _subs.add(
      _player.stream.completed.listen((done) {
        if (_disposed || !done) return;
        if (_isOpeningStream || _isRecoveringStream) return;

        final dur = effectiveDuration;
        final pos = effectivePosition;

        // Guard against premature EOF caused by transient HTTP/HLS drops:
        // mpv sets eof-reached=true (which pauses playback and marks
        // media_kit's state.completed=true). Never mark the title finished or
        // let a subsequent Play tap reset to 00:00 — seamlessly recover at pos!
        if (dur > Duration.zero && !_isNearGenuineEnd(pos, dur)) {
          debugPrint(
            'Premature EOF detected at ${pos.inSeconds}s / ${dur.inSeconds}s — recovering stream',
          );
          _prematureEofDetected = true;
          unawaited(flushProgress());
          if (_state.activeStream != null &&
              _sameStreamRecoveryAttempts < _maxSameStreamRecoveries) {
            unawaited(_recoverActiveStreamAtLastPosition(play: true));
          } else {
            _handleActiveStreamFailure('Stream connection dropped');
          }
          return;
        }

        _prematureEofDetected = false;
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

  void _syncWakelock({bool force = false}) {
    final shouldHold = !_disposed &&
        _state.errorMessage == null &&
        (_state.isPlaying ||
            _state.isInitializing ||
            _state.isSwitchingSource ||
            _isOpeningStream ||
            _isRecoveringStream ||
            _state.isBuffering);
    _updateWakelock(shouldHold, force: force);
  }

  void _updateWakelock(bool enable, {bool force = false}) {
    if (!force && _wakelockEnabled == enable) return;
    _wakelockEnabled = enable;
    try {
      if (enable) {
        unawaited(WakelockPlus.enable());
      } else {
        unawaited(WakelockPlus.disable());
      }
    } catch (_) {}
  }

  /// Called when the app returns to foreground so screen wake lock stays synced.
  void onAppResumed() {
    if (_disposed) return;
    _syncWakelock(force: true);
  }

  void _startProgressFlushTimer() {
    _progressFlushTimer?.cancel();
    _progressFlushTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_disposed && _state.isPlaying && currentDuration > Duration.zero) {
        unawaited(flushProgress());
      }
    });
  }

  /// Periodically checks libmpv's `avsync` drift while playing with hardware
  /// decoding enabled. If the video decoder stalls >=1.8s behind the audio
  /// clock for 2 consecutive checks (6s) while audio keeps playing, cleanly
  /// falls back to software decoding (`hwdec=no`) and re-syncs playback.
  void _startVideoStallMonitor() {
    _videoStallTimer?.cancel();
    _videoStallTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      unawaited(_checkVideoSyncHealth());
    });
  }

  bool _isDecoderError(String lowerErr) {
    return lowerErr.contains('mediacodec') ||
        lowerErr.contains('hwdec') ||
        lowerErr.contains('c2.mtk') ||
        lowerErr.contains('amc') ||
        lowerErr.contains('video decoder') ||
        lowerErr.contains('avcodec') ||
        lowerErr.contains('codec') ||
        lowerErr.contains('vo_gpu') ||
        lowerErr.contains('error decoding');
  }

  Future<void> _checkVideoSyncHealth() async {
    if (_disposed ||
        _checkingVideoStall ||
        !_hwdecPreferred ||
        _fellBackToSoftwareForStream ||
        !_state.isPlaying ||
        _state.isBuffering ||
        _state.isInitializing ||
        _state.isSwitchingSource ||
        _isOpeningStream ||
        _isRecoveringStream ||
        _isTransitioningEpisode) {
      _consecutiveVideoStallTicks = 0;
      return;
    }

    final platform = _player.platform;
    if (platform is! NativePlayer) return;

    _checkingVideoStall = true;
    try {
      // Detect black-screen / no-video-frames hardware decode failure where
      // audio and timeline advance normally but video width stays 0/null.
      final hasVideoTrack = _player.state.tracks.video
          .any((v) => v.id != 'auto' && v.id != 'no');
      final width = _player.state.width ?? 0;
      if (hasVideoTrack &&
          width <= 0 &&
          effectiveDuration > Duration.zero &&
          effectivePosition > const Duration(seconds: 2)) {
        _consecutiveVideoStallTicks++;
        if (_consecutiveVideoStallTicks >= 2) {
          _consecutiveVideoStallTicks = 0;
          await _fallbackToSoftwareDecoding(
            reason: 'no video frames from hwdec',
            forceReopen: true,
          );
        }
        return;
      }

      final hwdecCurrent = (await platform.getProperty('hwdec-current')).trim();
      if (hwdecCurrent.isEmpty || hwdecCurrent == 'no') {
        _consecutiveVideoStallTicks = 0;
        return;
      }
      final rawSync = (await platform.getProperty('avsync')).trim();
      final avsync = double.tryParse(rawSync);
      if (avsync != null && avsync.abs() >= 1.8) {
        _consecutiveVideoStallTicks++;
        if (_consecutiveVideoStallTicks >= 2) {
          _consecutiveVideoStallTicks = 0;
          await _fallbackToSoftwareDecoding(
            reason: 'hwdec stall (avsync=${avsync.toStringAsFixed(2)}s)',
          );
        }
      } else {
        _consecutiveVideoStallTicks = 0;
      }
    } catch (_) {
      _consecutiveVideoStallTicks = 0;
    } finally {
      _checkingVideoStall = false;
    }
  }

  Future<void> _fallbackToSoftwareDecoding({
    required String reason,
    bool forceReopen = false,
  }) async {
    if (_disposed || _fellBackToSoftwareForStream) return;
    final platform = _player.platform;
    if (platform is! NativePlayer) return;

    _fellBackToSoftwareForStream = true;
    _consecutiveVideoStallTicks = 0;
    debugPrint('Video hardware decode fallback to software: $reason');

    try {
      await platform.setProperty('hwdec', 'no');
      final pos = effectivePosition;
      final active = _state.activeStream;
      final shouldReopen =
          forceReopen || !_hasReceivedDurationForOpen || (_player.state.width ?? 0) <= 0;

      if (shouldReopen && active != null && !_isRecoveringStream) {
        _isRecoveringStream = true;
        _pendingResumeMs = pos.inMilliseconds;
        _showStatusBanner('Retrying with software decoding...');
        _setState(
          _state.copyWith(
            isSwitchingSource: true,
            isBuffering: true,
            clearError: true,
          ),
        );
        _syncWakelock();
        try {
          await _openRankedStream(
            active,
            startPosition: pos,
            play: true,
            isRecovery: true,
          );
        } finally {
          _isRecoveringStream = false;
        }
        return;
      }

      if (!_disposed && pos > Duration.zero) {
        await _player.seek(pos);
      }
      if (!_disposed) {
        _showStatusBanner('Switched to smooth software decoding');
      }
    } catch (_) {}
  }

  Future<void> _restorePreferredHwdecIfNeeded() async {
    if (!_fellBackToSoftwareForStream) return;
    _fellBackToSoftwareForStream = false;
    _consecutiveVideoStallTicks = 0;
    if (!_hwdecPreferred) return;
    final platform = _player.platform;
    if (platform is NativePlayer) {
      try {
        await platform.setProperty('hwdec', _stableAndroidHwdec);
      } catch (_) {}
    }
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
    if (_disposed ||
        _isTransitioningEpisode ||
        snap.key != _currentPrefetchKey) {
      return;
    }
    if (snap.query.season != _state.query.season ||
        snap.query.episode != _state.query.episode) {
      return;
    }

    final filteredRanked = snap.rankedStreams;
    final mergedExternalSubs = _mergedExternalSubtitles(snap);
    final subOpts = TrackOrchestrator.buildSubtitleOptions(
      _player.state.tracks.subtitle,
      mergedExternalSubs,
    );

    _setState(
      _state.copyWith(
        isResolvingLinks: snap.isResolving || snap.isProbing,
        hasMoreSources: snap.hasMoreProviders,
        hasAnyStreamAddon: snap.hasAnyStreamAddon,
        rankedStreams: filteredRanked,
        subtitleOptions: subOpts,
      ),
    );

    if (_tracksAppliedForOpen &&
        !_userManualSubOverride &&
        _state.selectedSubtitleId == 'off' &&
        mergedExternalSubs.isNotEmpty) {
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
              r.isAutoPlayEligible &&
              !_sessionFailedKeys.contains(r.dedupKey) &&
              !_previousEpisodeStreamKeys.contains(r.dedupKey))
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
        final mapped = snap.hasAnyStreamAddon
            ? UserError.noStreams()
            : UserError.noAddons();
        _setState(
          _state.copyWith(
            isInitializing: false,
            isSwitchingSource: false,
            isBuffering: false,
            error: mapped,
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
    if (_disposed || _hasStartedFirstOpen || _isTransitioningEpisode) return;
    if (snap.key != _currentPrefetchKey ||
        snap.query.season != _state.query.season ||
        snap.query.episode != _state.query.episode) {
      return;
    }

    bool isAllowedForEpisode(RankedStream r) =>
        r.stream.canPlayInternally &&
        !_sessionFailedKeys.contains(r.dedupKey) &&
        !_previousEpisodeStreamKeys.contains(r.dedupKey);

    final primaryBest = snap.bestPlayableStream;
    final best = (primaryBest != null && isAllowedForEpisode(primaryBest))
        ? primaryBest
        : snap.rankedStreams.where(isAllowedForEpisode).firstOrNull;
    if (best == null) {
      _hasStartedFirstOpen = true;
      final mapped = snap.hasAnyStreamAddon
          ? UserError.noStreams()
          : UserError.noAddons();
      _setState(
        _state.copyWith(
          isInitializing: false,
          isResolvingLinks: false,
          hasAnyStreamAddon: snap.hasAnyStreamAddon,
          error: mapped,
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
    bool isRecovery = false,
  }) async {
    final url = candidate.stream.internalPlayableUrl;
    if (url == null || url.isEmpty) {
      _handleActiveStreamFailure('Invalid stream URL');
      return;
    }

    // Guard against accidental re-opening of an already healthy active stream
    // (e.g., duplicate callbacks or UI lifecycle triggers).
    if (!isRecovery &&
        _state.activeStream?.dedupKey == candidate.dedupKey &&
        _hasReceivedDurationForOpen &&
        !_player.state.completed &&
        !_prematureEofDetected) {
      if (play && !_state.isPlaying) {
        await _player.play();
      }
      return;
    }

    final gen = ++_openGeneration;
    final targetPrefetchKey = _currentPrefetchKey;
    _isOpeningStream = true;
    _hasReceivedDurationForOpen = false;
    _prematureEofDetected = false;
    _tracksAppliedForOpen = false;
    _embeddedSkipSegments = const [];
    _chaptersLoadedForGen = -1;
    _rebuildMergedSkipSegments();
    _stallWatchdog?.cancel();
    _pauseScrapingTimer?.cancel();
    _pauseScrapingTimer = null;

    if (!isRecovery) {
      _sameStreamRecoveryAttempts = 0;
      _recoveryBaselinePos = null;
      _consecutiveVideoStallTicks = 0;
      unawaited(_restorePreferredHwdecIfNeeded());
    }

    final effectiveStart =
        startPosition > Duration.zero ? startPosition : Duration.zero;
    _postOpenSeekDispatched = false;
    if (effectiveStart > Duration.zero) {
      _lastValidPosition = effectiveStart;
      _pendingResumeMs = effectiveStart.inMilliseconds;
      _pendingPostOpenSeek = effectiveStart;
    } else {
      _pendingPostOpenSeek = null;
    }

    final headers = candidate.stream.buildRequestHeaders(
      defaultUserAgent: _defaultUserAgent,
    );

    _setState(
      _state.copyWith(
        activeStream: candidate,
        isBuffering: true,
        clearError: true,
      ),
    );
    _syncWakelock();

    // Ensure resilient libmpv network/cache properties are applied before the
    // first HTTP/HLS request is issued.
    await _mpvConfigReady;
    if (_disposed ||
        gen != _openGeneration ||
        _currentPrefetchKey != targetPrefetchKey) {
      return;
    }

    final watchdogTimeout =
        isRecovery ? const Duration(seconds: 10) : const Duration(seconds: 7);
    _stallWatchdog = Timer(watchdogTimeout, () {
      if (_disposed || gen != _openGeneration) return;
      final stalledAtStart = !_hasReceivedDurationForOpen ||
          (_state.isBuffering &&
              (_player.state.position - effectiveStart).abs() <
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
          start: effectiveStart > Duration.zero ? effectiveStart : null,
        ),
        play: play,
      );
      if (play && _state.playbackSpeed != 1.0 && !_disposed && gen == _openGeneration) {
        await _player.setRate(_state.playbackSpeed);
      }
    } catch (e) {
      if (!_disposed && gen == _openGeneration) {
        _handleActiveStreamFailure(e.toString());
      }
    } finally {
      if (gen == _openGeneration) {
        _isOpeningStream = false;
      }
    }
  }

  /// Seamlessly reloads the current stream at [_lastValidPosition] after a
  /// premature network EOF or dropped HTTP/HLS connection.
  Future<void> _recoverActiveStreamAtLastPosition({
    required bool play,
    bool resetRetryBudget = false,
  }) async {
    if (_disposed || _isRecoveringStream) return;
    final active = _state.activeStream;
    if (active == null) return;

    if (resetRetryBudget) {
      _sameStreamRecoveryAttempts = 0;
    }
    _sameStreamRecoveryAttempts++;
    _isRecoveringStream = true;
    _prematureEofDetected = false;

    final resumePos = effectivePosition;
    _pendingResumeMs = resumePos.inMilliseconds;
    _recoveryBaselinePos = resumePos;

    _showStatusBanner('Reconnecting stream...');
    _setState(
      _state.copyWith(
        isSwitchingSource: true,
        isBuffering: true,
        clearError: true,
      ),
    );
    _syncWakelock();

    try {
      await _openRankedStream(
        active,
        startPosition: resumePos,
        play: play,
        isRecovery: true,
      );
    } finally {
      _isRecoveringStream = false;
    }
  }

  void _handleActiveStreamFailure(
    String reason, {
    bool forceFailover = false,
  }) {
    _stallWatchdog?.cancel();
    _pauseScrapingTimer?.cancel();
    _pauseScrapingTimer = null;

    // Before failing over or surfacing a decoder error, automatically retry
    // the same stream once in pure software decode mode (`hwdec=no`) at
    // `_lastValidPosition`.
    if (!forceFailover &&
        _hwdecPreferred &&
        !_fellBackToSoftwareForStream &&
        _state.activeStream != null &&
        _isDecoderError(reason.toLowerCase())) {
      unawaited(
        _fallbackToSoftwareDecoding(
          reason: reason,
          forceReopen: true,
        ),
      );
      return;
    }

    final savedPos = effectivePosition;
    final resumeMs = savedPos > Duration.zero
        ? savedPos.inMilliseconds
        : _pendingResumeMs;
    _pendingResumeMs = resumeMs;

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
      final mapped = UserError.from(
        reason,
        fallbackType: UserErrorType.playbackFailed,
        logTag: 'PlayerController.userLocked',
      );
      _setState(
        _state.copyWith(
          isInitializing: false,
          isSwitchingSource: false,
          isBuffering: false,
          error: mapped,
        ),
      );
      _syncWakelock();
      return;
    }

    final eligible = _state.rankedStreams
        .where((r) =>
            r.isAutoPlayEligible &&
            !_sessionFailedKeys.contains(r.dedupKey) &&
            !_previousEpisodeStreamKeys.contains(r.dedupKey))
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
      _syncWakelock();
      unawaited(
        container
            .read(streamPrefetchControllerProvider.notifier)
            .resumePrefetch(_currentPrefetchKey),
      );
      return;
    }

    final mapped = UserError.from(
      reason,
      fallbackType: UserErrorType.playbackFailed,
      logTag: 'PlayerController.failure',
    );
    _setState(
      _state.copyWith(
        isInitializing: false,
        isSwitchingSource: false,
        isBuffering: false,
        error: mapped,
      ),
    );
    _syncWakelock();
  }

  List<ResolvedSubtitle> _mergedExternalSubtitles(PrefetchSnapshot? snap) {
    final activeSubs =
        _state.activeStream?.stream.subtitles ?? const <ResolvedSubtitle>[];
    final snapSubs = snap?.subtitles ?? const <ResolvedSubtitle>[];
    if (activeSubs.isEmpty) return snapSubs;
    if (snapSubs.isEmpty) return activeSubs;
    final seen = <String>{};
    final out = <ResolvedSubtitle>[];
    for (final s in [...activeSubs, ...snapSubs]) {
      final key = s.url.trim();
      if (key.isEmpty || !seen.add(key)) continue;
      out.add(s);
    }
    return out;
  }

  void _onTracksUpdated(Tracks tracks) {
    final prefSnap =
        container.read(streamPrefetchControllerProvider)[_currentPrefetchKey];
    final externalSubs = _mergedExternalSubtitles(prefSnap);
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
    if (!next.stream.canPlayInternally) {
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

    final savedPos = effectivePosition;
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
    final savedPos = effectivePosition;
    if (savedPos > Duration.zero) {
      _pendingResumeMs = savedPos.inMilliseconds;
    }
    _sessionFailedKeys.clear();
    _hasStartedFirstOpen = false;
    _userLockedStream = false;
    _awaitingResumedFallback = false;
    _prematureEofDetected = false;
    _sameStreamRecoveryAttempts = 0;
    _setState(
      _state.copyWith(
        isInitializing: true,
        clearError: true,
      ),
    );
    _syncWakelock();
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
      final rawUrl = ext.url.trim();
      final normalizedUrl = rawUrl.startsWith('//') ? 'https:$rawUrl' : rawUrl;
      final parsedUri = Uri.tryParse(normalizedUrl);
      if (parsedUri == null ||
          (parsedUri.scheme != 'http' &&
              parsedUri.scheme != 'https' &&
              parsedUri.scheme != 'file')) {
        throw FormatException('Unsupported subtitle URI: $rawUrl');
      }
      String uriToLoad = normalizedUrl;
      if (ext.headers.isNotEmpty) {
        uriToLoad = await _downloadExternalSubToTemp(
          ext,
          normalizedUrl: normalizedUrl,
        );
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

  Future<String> _downloadExternalSubToTemp(
    ResolvedSubtitle sub, {
    String? normalizedUrl,
  }) async {
    final targetUrl = normalizedUrl ?? sub.url.trim();
    final lowerUrl = targetUrl.toLowerCase();
    final ext = lowerUrl.contains('.ass')
        ? '.ass'
        : lowerUrl.contains('.ssa')
            ? '.ssa'
            : lowerUrl.contains('.vtt')
                ? '.vtt'
                : lowerUrl.contains('.sup')
                    ? '.sup'
                    : lowerUrl.contains('.sub')
                        ? '.sub'
                        : '.srt';
    final file = File(
      '${Directory.systemTemp.path}/openflix_sub_${targetUrl.hashCode}$ext',
    );
    if (!await file.exists()) {
      final resp = await _subDio.get<List<int>>(
        targetUrl,
        options: Options(
          headers: sub.headers,
          responseType: ResponseType.bytes,
        ),
      );
      await file.writeAsBytes(resp.data ?? const [], flush: true);
    }
    return Uri.file(file.path).toString();
  }

  Future<void> togglePlayPause() async {
    if (_disposed || _isOpeningStream || _isRecoveringStream) return;

    // Normal pause: never re-open or lose playback position.
    if (_state.isPlaying && !_player.state.completed) {
      await _player.pause();
      return;
    }

    // Resuming playback: guard against media_kit's built-in behavior where
    // calling play()/playOrPause() while state.completed == true executes
    // `seek(Duration.zero)` and restarts the stream from 00:00.
    final resumePos = effectivePosition;
    final dur = effectiveDuration;
    final isGenuineEnd =
        dur > Duration.zero && resumePos > Duration.zero && _isNearGenuineEnd(resumePos, dur);

    if (_player.state.completed || _prematureEofDetected) {
      if (isGenuineEnd) {
        // User genuinely finished the video and tapped Play to replay.
        _prematureEofDetected = false;
        _lastValidPosition = Duration.zero;
        _pendingResumeMs = 0;
        _pendingPostOpenSeek = null;
        await _player.seek(Duration.zero);
        await _player.play();
        return;
      }

      if (_state.activeStream != null && resumePos > Duration.zero) {
        await _recoverActiveStreamAtLastPosition(
          play: true,
          resetRetryBudget: true,
        );
        return;
      }
    }

    // Normal unpause: restore position if mpv drifted back to 0 while paused.
    if (resumePos > const Duration(seconds: 2) &&
        _player.state.position < const Duration(seconds: 1)) {
      await _player.seek(resumePos);
    }
    await _player.play();
  }

  Future<void> seekTo(Duration target) async {
    final dur = effectiveDuration;
    final clamped = dur > Duration.zero
        ? Duration(
            milliseconds: target.inMilliseconds.clamp(0, dur.inMilliseconds),
          )
        : (target.isNegative ? Duration.zero : target);
    _lastValidPosition = clamped;
    _pendingResumeMs = clamped.inMilliseconds;
    _pendingPostOpenSeek = null;
    _postOpenSeekDispatched = false;
    _prematureEofDetected = false;
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
      seekTo(effectivePosition + delta);

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
    _onlineSkipFetchedDurationSec = 0;
    _cancelAutoOutroCountdown();
    if (activeSkipPromptNotifier.value != null) {
      activeSkipPromptNotifier.value = null;
    }
  }

  Future<void> _fetchOnlineSkipSegments(
    StreamQuery query, {
    int? durationSec,
  }) async {
    final fetchGen = _skipFetchGeneration;
    final effectiveDurSec = (durationSec != null && durationSec > 0)
        ? durationSec
        : (effectiveDuration.inSeconds > 0
            ? effectiveDuration.inSeconds
            : null);
    if (effectiveDurSec != null) {
      _onlineSkipFetchedDurationSec = effectiveDurSec;
    }
    try {
      final repo = container.read(skipSegmentsRepositoryProvider);
      final segments = await repo.fetchOnlineSegments(
        query,
        durationSec: effectiveDurSec,
      );
      if (_disposed || fetchGen != _skipFetchGeneration) return;
      _onlineSkipSegments = segments;
      _rebuildMergedSkipSegments();
      _evaluateActiveSkipSegment(effectivePosition);
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
      _evaluateActiveSkipSegment(effectivePosition);
    } catch (_) {}
  }

  void _rebuildMergedSkipSegments() {
    _mergedSkipSegments = SkipSegmentsRepository.mergeAndSanitize(
      embedded: _embeddedSkipSegments,
      online: _onlineSkipSegments,
      durationMs: effectiveDuration.inMilliseconds,
      isAnime: _state.query.isAnime,
    );
  }

  SkipSegment? _segmentOfType(SkipSegmentType type) {
    for (final s in _mergedSkipSegments) {
      if (s.type == type) return s;
    }
    return null;
  }

  /// True once playback is near the true end of the episode (used for Continue
  /// Watching promotion and showing the standalone Next Episode prompt when no
  /// Skip Outro segment is active).
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

    if (hasPostCreditsAfterOutro) {
      return posMs >= postCredits.endMs - 10000 ||
          (dur - pos) <= const Duration(seconds: 15);
    }

    if (outro != null) {
      // Wait until outro finishes (or we're in the final 15s of video) so Play
      // Next stays coordinated near the actual end and never crowds Skip Outro.
      if (posMs >= outro.endMs) {
        return (dur - pos) <= const Duration(seconds: 20) ||
            (durMs - outro.endMs) <= 15000;
      }
      return (dur - pos) <= const Duration(seconds: 10);
    }

    final frac = posMs / durMs;
    final rem = dur - pos;
    return frac >= 0.94 || (rem <= const Duration(seconds: 25) && frac >= 0.88);
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
    if (_disposed || _isTransitioningEpisode) return;
    final dur = effectiveDuration;
    if (dur <= Duration.zero) {
      _clearSkipPrompt();
      return;
    }

    final posMs = pos.inMilliseconds;
    final durMs = dur.inMilliseconds;
    final isSeries = _state.query.mediaType == 'series';
    final nextQ =
        isSeries ? (_state.nextEpisodeQuery ?? _resolveNextEpisodeQuery()) : null;

    // Quietly prefetch the next episode and promote Continue Watching once the
    // user enters the outro or reaches the final stretch of the episode.
    final outroSeg = _segmentOfType(SkipSegmentType.outro);
    final reachedEndRegion = _isAtNextEpisodePoint(pos, dur) ||
        (outroSeg != null &&
            posMs >= outroSeg.startMs &&
            (durMs - outroSeg.endMs) <= 5000);
    if (isSeries && reachedEndRegion) {
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
    //    Uses isPromptActiveAt so Skip Intro appears 3.5s before intro.start
    //    through intro.end, and Skip Outro is NEVER overwritten by Play Next.
    for (final seg in _mergedSkipSegments) {
      if (!seg.isPromptActiveAt(posMs)) continue;
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
        if (isSeries && nextQ != null) {
          _triggerNextEpisodePrefetchIfNeeded(nextQ);
        }
        final hasPostCredits =
            postCredits != null && postCredits.startMs >= seg.startMs;
        final remainingAfterOutroMs = durMs - seg.endMs;
        if (hasPostCredits) {
          candidate = ActiveSkipPrompt(
            segment: seg,
            actionKind: SkipActionKind.skipCredits,
            targetSeekMs: postCredits.startMs,
          );
        } else if (remainingAfterOutroMs > 5000) {
          // Content continues after outro (e.g. post-credits / preview): seek
          // cleanly to outro.end.
          candidate = ActiveSkipPrompt(
            segment: seg,
            actionKind: SkipActionKind.skipCredits,
            targetSeekMs: seg.endMs,
          );
        } else if (isSeries && nextQ != null) {
          // Outro runs right up to the end of the episode (<=5s left): still
          // display "Skip outro", and advance cleanly to next episode on tap.
          candidate = ActiveSkipPrompt(
            segment: seg,
            actionKind: SkipActionKind.skipCredits,
            advancesToNextEpisode: true,
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

    // 2. Coordinated Next Episode prompt near the actual end of the episode
    //    (only when no Recap / Intro / Outro prompt is currently active).
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

    if (candidate == null ||
        _dismissedSkipTypes.contains(candidate.segment.type)) {
      _clearSkipPrompt();
      return;
    }

    final prefs =
        container.read(playbackPreferencesControllerProvider).valueOrNull ??
            const PlaybackPreferences();

    // Auto-skip Intro & Recap ONLY once playback actually reaches segment.startMs
    // (never during the 3.5s pre-intro manual button lead-in).
    if (_state.isPlaying &&
        prefs.autoSkipIntroRecap &&
        (candidate.actionKind == SkipActionKind.skipIntro ||
            candidate.actionKind == SkipActionKind.skipRecap) &&
        candidate.segment.isActiveAt(posMs) &&
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

    // Auto-skip Outro (instant jump to post-credits / outro end, or 5s
    // cancellable countdown when advancing to the Next Episode).
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
          !candidate.advancesToNextEpisode &&
          candidate.targetSeekMs != null) {
        _autoSkippedTypes.add(SkipSegmentType.outro);
        _clearSkipPrompt();
        _showStatusBanner('Skipped outro');
        unawaited(seekTo(Duration(milliseconds: candidate.targetSeekMs!)));
        return;
      }
      if (candidate.actionKind == SkipActionKind.nextEpisode ||
          candidate.advancesToNextEpisode) {
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

    if (prompt.actionKind == SkipActionKind.nextEpisode ||
        prompt.advancesToNextEpisode) {
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
    _hwdecPreferred = enabled;
    _fellBackToSoftwareForStream = false;
    _consecutiveVideoStallTicks = 0;
    await container
        .read(playbackPreferencesControllerProvider.notifier)
        .setHardwareDecoding(enabled);
    final platform = _player.platform;
    if (platform is NativePlayer) {
      try {
        await platform.setProperty(
          'hwdec',
          enabled ? _stableAndroidHwdec : 'no',
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
    if (_disposed || _isTransitioningEpisode) return;
    final nextQ = _state.nextEpisodeQuery ?? _resolveNextEpisodeQuery();
    if (nextQ == null) return;
    if (nextQ.season == _state.query.season &&
        nextQ.episode == _state.query.episode) {
      return;
    }

    _isTransitioningEpisode = true;
    try {
      // SYNCHRONOUSLY detach previous episode subscription & invalidate all
      // in-flight opens/timers BEFORE any `await`, so a prefetch map emission
      // during `flushProgress()` or `_player.stop()` can NEVER trigger
      // `_tryStartFirstPlayable()` on the previous episode's cached snapshot.
      final prevPrefetchKey = _currentPrefetchKey;
      final prevActiveKey = _state.activeStream?.dedupKey;
      if (prevActiveKey != null && prevActiveKey.isNotEmpty) {
        _previousEpisodeStreamKeys.add(prevActiveKey);
      }

      _prefetchSub?.close();
      _prefetchSub = null;
      _openGeneration++;
      _skipFetchGeneration++;
      _stallWatchdog?.cancel();
      _graceTimer?.cancel();
      _graceTimer = null;
      _pauseScrapingTimer?.cancel();
      _pauseScrapingTimer = null;
      _cancelAutoOutroCountdown();
      activeSkipPromptNotifier.value = null;

      await flushProgress(forceCompleted: true);
      if (_disposed) return;

      // Pause/clear previous episode prefetch so its streams cannot bleed over.
      final prefetchNotifier =
          container.read(streamPrefetchControllerProvider.notifier);
      prefetchNotifier.pausePrefetch(prevPrefetchKey);

      await _player.stop();
      if (_disposed) return;

      // Atomically clear all previous-episode playback state BEFORE updating
      // `_state.query` to `nextQ` and re-subscribing to prefetch.
      _sessionFailedKeys.clear();
      _hasStartedFirstOpen = false;
      _userLockedStream = false;
      _awaitingResumedFallback = false;
      _isOpeningStream = false;
      _isRecoveringStream = false;
      _prematureEofDetected = false;
      _hasReceivedDurationForOpen = false;
      _sameStreamRecoveryAttempts = 0;
      _lastValidPosition = Duration.zero;
      _lastValidDuration = Duration.zero;
      _pendingPostOpenSeek = null;
      _postOpenSeekDispatched = false;
      _recoveryBaselinePos = null;
      _pendingResumeMs = 0;
      _prefetchedNextKey = null;
      _tracksAppliedForOpen = false;
      timelineNotifier.value = const PlayerTimelineState();
      _resetSkipSegmentsForEpisode();

      _setState(
        PlayerUiState(
          query: nextQ,
          isInitializing: true,
          isResolvingLinks: true,
          playbackSpeed: _state.playbackSpeed,
          fitMode: _state.fitMode,
        ),
      );
      _syncWakelock();
    } finally {
      _isTransitioningEpisode = false;
    }

    if (!_disposed) {
      _bindPrefetch(nextQ);
    }
  }

  Future<void> flushProgress({bool forceCompleted = false}) async {
    final dur = effectiveDuration.inMilliseconds;
    final pos = effectivePosition.inMilliseconds;
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
    _statusBannerTimer = Timer(const Duration(milliseconds: 3500), () {
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
    _videoStallTimer?.cancel();
    _statusBannerTimer?.cancel();
    _autoOutroCountdownTimer?.cancel();
    _prefetchSub?.close();
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _updateWakelock(false, force: true);
    timelineNotifier.dispose();
    subtitleScaleNotifier.dispose();
    activeSkipPromptNotifier.dispose();
    _player.dispose();
    super.dispose();
  }
}
