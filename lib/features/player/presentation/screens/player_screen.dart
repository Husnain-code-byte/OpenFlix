import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../../../core/errors/user_error.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../core/widgets/app_feedback.dart';
import '../../../addons/presentation/screens/addons_screen.dart';
import '../../../addons/presentation/widgets/addons_ui_kit.dart';
import '../../../preferences/domain/models/playback_preferences.dart';
import '../../../preferences/presentation/controllers/playback_preferences_controller.dart';
import '../../../preferences/presentation/widgets/language_setup_sheet.dart';
import '../../domain/models/player_models.dart';
import '../../domain/models/skip_segment.dart';
import '../controllers/player_controller.dart';
import '../widgets/player_icons.dart';
import '../widgets/player_modals.dart';

Route<void> openFlixPlayerRoute(PlaybackLaunchArgs args) =>
    PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) => PlayerScreen(args: args),
      transitionsBuilder: (_, animation, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
        child: child,
      ),
    );

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key, required this.args});

  final PlaybackLaunchArgs args;

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with WidgetsBindingObserver {
  PlayerSessionController? _controller;
  Widget? _cachedVideoSurface;
  bool _controlsVisible = true;
  bool _isScrubbing = false;
  double _scrubFraction = 0.0;
  Timer? _autoHideTimer;

  // Cumulative double-tap seek indicator (-10s, -20s, +10s, +20s...)
  int _doubleTapSide = 0; // -1 left, +1 right
  int _doubleTapAccumulatedSecs = 0;
  Timer? _doubleTapFeedbackTimer;

  // Pinch-to-zoom Fit/Fill state
  double _pinchStartScale = 1.0;
  bool _pinchTriggered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _enterLandscapePlayerMode();
    _scheduleAutoHide();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller == null) {
      _controller = PlayerSessionController(
        ProviderScope.containerOf(context, listen: false),
        widget.args,
      );
      // Cache the RepaintBoundary-isolated video surface once so HUD toggles,
      // 60fps seekbar scrubbing, and double-tap feedback never trigger rebuilds
      // or compositor repaints of the native Android video Texture layer.
      _cachedVideoSurface = RepaintBoundary(
        child: _IsolatedVideoSurface(controller: _controller!),
      );
    }
  }

  Future<void> _enterLandscapePlayerMode() async {
    try {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } catch (_) {}
  }

  Future<void> _restorePortraitMode() async {
    try {
      await SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]);
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _controller;
    if (ctrl == null) return;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      ctrl.flushProgress();
    } else if (state == AppLifecycleState.resumed) {
      ctrl.onAppResumed();
      unawaited(_enterLandscapePlayerMode());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoHideTimer?.cancel();
    _doubleTapFeedbackTimer?.cancel();
    _controller?.dispose();
    unawaited(_restorePortraitMode());
    super.dispose();
  }

  void _scheduleAutoHide() {
    _autoHideTimer?.cancel();
    _autoHideTimer = Timer(const Duration(seconds: 4), () {
      final ctrl = _controller;
      if (!mounted || ctrl == null) return;
      if (ctrl.state.isPlaying && !_isScrubbing) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _revealControls() {
    setState(() => _controlsVisible = true);
    _scheduleAutoHide();
  }

  void _toggleControls() {
    if (_controlsVisible) {
      _autoHideTimer?.cancel();
      setState(() => _controlsVisible = false);
    } else {
      _revealControls();
    }
  }

  void _seekTenWithFeedback(int side) {
    final ctrl = _controller;
    if (ctrl == null) return;
    HapticFeedback.lightImpact();
    ctrl.seekRelative(Duration(seconds: side < 0 ? -10 : 10));
    _doubleTapFeedbackTimer?.cancel();
    setState(() {
      if (_doubleTapSide == side) {
        _doubleTapAccumulatedSecs += 10;
      } else {
        _doubleTapSide = side;
        _doubleTapAccumulatedSecs = 10;
      }
    });
    _doubleTapFeedbackTimer = Timer(const Duration(milliseconds: 680), () {
      if (mounted) {
        setState(() {
          _doubleTapSide = 0;
          _doubleTapAccumulatedSecs = 0;
        });
      }
    });
    _scheduleAutoHide();
  }

  static String _formatClock(Duration d) {
    final total = d.inSeconds < 0 ? 0 : d.inSeconds;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    Responsive.init(context);
    final ctrl = _controller;
    if (ctrl == null) {
      return const Scaffold(backgroundColor: Color(0xFF000000));
    }

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          ctrl.flushProgress();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF000000),
        body: Stack(
          fit: StackFit.expand,
          children: [
            // ── Video Surface (Cached + RepaintBoundary isolated from HUD) ──
            _cachedVideoSurface!,

            // ── Full-screen Gesture Layer (Tap, Double-tap ±10s, Pinch Fit/Fill) ──
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onScaleStart: (_) {
                  _pinchStartScale = 1.0;
                  _pinchTriggered = false;
                },
                onScaleUpdate: (details) {
                  if (details.pointerCount < 2 || _pinchTriggered) return;
                  final delta = details.scale - _pinchStartScale;
                  if (delta > 0.16) {
                    _pinchTriggered = true;
                    HapticFeedback.selectionClick();
                    ctrl.toggleFitModeByPinch(true);
                  } else if (delta < -0.16) {
                    _pinchTriggered = true;
                    HapticFeedback.selectionClick();
                    ctrl.toggleFitModeByPinch(false);
                  }
                },
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _toggleControls,
                        onDoubleTap: () => _seekTenWithFeedback(-1),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _toggleControls,
                        onDoubleTap: () => _seekTenWithFeedback(1),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Cumulative Seek Feedback (Double-tap & +/-10s Icon Tap) ────
            if (_doubleTapSide != 0)
              Align(
                alignment: _doubleTapSide < 0
                    ? const Alignment(-0.56, 0)
                    : const Alignment(0.56, 0),
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: 1.0,
                    duration: const Duration(milliseconds: 120),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _doubleTapSide < 0
                              ? Icons.fast_rewind_rounded
                              : Icons.fast_forward_rounded,
                          size: 20.r,
                          color: Colors.white,
                          shadows: const [
                            Shadow(
                              color: Color(0xB3000000),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        SizedBox(width: 5.w),
                        Text(
                          '${_doubleTapSide < 0 ? '-' : '+'}${_doubleTapAccumulatedSecs}s',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            fontFeatures: const [FontFeature.tabularFigures()],
                            shadows: const [
                              Shadow(
                                color: Color(0xB3000000),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // ── Proportional, Dead-Center Figma HUD Overlay ────────────────
            ListenableBuilder(
              listenable: ctrl,
              builder: (context, _) {
                final st = ctrl.state;
                final forceShow = st.errorMessage != null ||
                    st.isInitializing ||
                    st.isSwitchingSource;
                final visible = _controlsVisible || forceShow;

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    IgnorePointer(
                      ignoring: !visible,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOut,
                        opacity: visible ? 1.0 : 0.0,
                        child: _buildHudOverlay(context, ctrl, st),
                      ),
                    ),

                    // ── Skip Intro / Recap (Left) & Skip Outro / Next Episode (Right) ──
                    // Lives outside HUD opacity so skip CTA stays tappable while HUD is
                    // hidden, and glides directly above the seekbar when HUD appears.
                    if (st.errorMessage == null &&
                        !st.isInitializing &&
                        !st.isSwitchingSource)
                      _SkipPromptOverlay(
                        controller: ctrl,
                        hudVisible: visible,
                        isScrubbing: _isScrubbing,
                      ),

                    // Transient OLED status pill (shows even when HUD is hidden, auto-dismisses after 3.5s)
                    if (st.statusBanner != null)
                      Positioned(
                        top: math.max(MediaQuery.viewPaddingOf(context).top, 8.h) +
                            12.h,
                        left: 16.w,
                        right: 16.w,
                        child: IgnorePointer(
                          child: Center(
                            child: AppStatusPill(
                              message: st.statusBanner!,
                              icon: Icons.info_outline_rounded,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHudOverlay(
    BuildContext context,
    PlayerSessionController ctrl,
    PlayerUiState st,
  ) {
    final m = _PlayerHudMetrics.from(context);

    final q = st.query;
    final subTitleLine = q.mediaType == 'series' &&
            q.season != null &&
            q.episode != null
        ? 'S${q.season} E${q.episode}'
            '${q.episodeTitle?.trim().isNotEmpty == true ? ' ${q.episodeTitle!.trim()}' : ''}'
        : (q.year != null ? '${q.year}' : '');

    final hasCustomSpeed = (st.playbackSpeed - 1.0).abs() > 0.01;

    return Stack(
      fit: StackFit.expand,
      children: [
        // ── Top & Bottom Scrim Gradients ──────────────────────────────────
        const IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xB8020507),
                  Color(0x00020507),
                  Color(0x00020507),
                  Color(0xCC020507),
                ],
                stops: [0.0, 0.28, 0.64, 1.0],
              ),
            ),
          ),
        ),

        // ── Zone 1: Mathematical Dead-Center Transport / Error ────────────
        Align(
          alignment: Alignment.center,
          child: st.hasError
              ? _buildErrorCard(context, ctrl, st)
              : _buildTransportControls(ctrl, st, m),
        ),

        // ── Zone 2: Symmetric Top Bar (Figma 159:21 Exact Geometry) ───────
        // Row 1: Close ×  [30*s gap]  Series Title   ...   [Subtitles  1x  Settings]
        // Row 2: Episode title flush-left directly beneath Close × (10*s below title)
        Positioned(
          top: m.topEdgeV,
          left: m.topEdgeH,
          right: m.topEdgeH,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _TactilePlayerButton(
                    semanticLabel: 'Close player',
                    width: m.closeIconSize + m.closeToTitleGap,
                    height: math.max(36.0, m.titleFontSize * 1.25),
                    alignment: Alignment.centerLeft,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.of(context).maybePop();
                    },
                    child: PlayerSvgIcon(
                      PlayerIcons.close,
                      size: m.closeIconSize,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      q.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Inter',
                        fontSize: m.titleFontSize,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                        letterSpacing: -0.35,
                        height: 1.2,
                        shadows: const [
                          Shadow(
                            color: Color(0x88000000),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: (18.0 * m.s).clamp(10.0, 18.0)),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _TactilePlayerButton(
                        semanticLabel: 'Audio and subtitles',
                        height: math.max(36.0, m.settingsIconSize + 10.0),
                        horizontalPadding: 0,
                        onTap: () {
                          _autoHideTimer?.cancel();
                          showPlayerAudioSubtitlesModal(
                            context,
                            controller: ctrl,
                          ).whenComplete(_scheduleAutoHide);
                        },
                        child: PlayerSvgIcon(
                          PlayerIcons.audioSubtitles,
                          size: m.subIconSize,
                        ),
                      ),
                      SizedBox(width: m.topRightIconGap),
                      _TactilePlayerButton(
                        semanticLabel: 'Playback speed',
                        highlighted: hasCustomSpeed,
                        height: math.max(36.0, m.settingsIconSize + 10.0),
                        horizontalPadding: 0,
                        onTap: () {
                          _autoHideTimer?.cancel();
                          showPlayerSpeedModal(
                            context,
                            controller: ctrl,
                          ).whenComplete(_scheduleAutoHide);
                        },
                        child: Text(
                          st.playbackSpeed == 1.0
                              ? '1x'
                              : '${st.playbackSpeed}x',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: m.speedFontSize,
                            fontWeight: FontWeight.w400,
                            color: Colors.white,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                      SizedBox(width: m.topRightIconGap),
                      _TactilePlayerButton(
                        semanticLabel: 'Player settings',
                        height: math.max(36.0, m.settingsIconSize + 10.0),
                        horizontalPadding: 0,
                        alignment: Alignment.centerRight,
                        onTap: () {
                          _autoHideTimer?.cancel();
                          final prefs = ref
                                  .read(playbackPreferencesControllerProvider)
                                  .valueOrNull ??
                              const PlaybackPreferences();
                          showPlayerSettingsModal(
                            context,
                            controller: ctrl,
                            initialPrefs: prefs,
                            onOpenLanguagePicker: () =>
                                showLanguageSetupSheet(context),
                          ).whenComplete(_scheduleAutoHide);
                        },
                        child: PlayerSvgIcon(
                          PlayerIcons.settingsGear,
                          size: m.settingsIconSize,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              if (subTitleLine.isNotEmpty) ...[
                SizedBox(height: m.titleToSubGap),
                Text(
                  subTitleLine,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    fontSize: m.subtitleFontSize,
                    fontWeight: FontWeight.w400,
                    color: Colors.white,
                    height: 1.2,
                    shadows: const [
                      Shadow(
                        color: Color(0x88000000),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),

        // ── Zone 3: Seekbar (80.5% of Top Bar Span) + Borderless Links Pill ──
        Positioned(
          bottom: m.bottomEdgeV,
          left: m.seekbarEdgeH,
          right: m.seekbarEdgeH,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Timeline subtree listens ONLY to timelineNotifier (zero HUD churn)
              ValueListenableBuilder<PlayerTimelineState>(
                valueListenable: ctrl.timelineNotifier,
                builder: (context, tl, _) {
                  final durMs = tl.duration.inMilliseconds;
                  final rawPosMs = tl.position.inMilliseconds;
                  final fraction = _isScrubbing
                      ? _scrubFraction
                      : (durMs > 0 ? (rawPosMs / durMs).clamp(0.0, 1.0) : 0.0);
                  final displayPos = _isScrubbing && durMs > 0
                      ? Duration(
                          milliseconds: (_scrubFraction * durMs).round(),
                        )
                      : tl.position;
                  final remaining = tl.duration > displayPos
                      ? (tl.duration - displayPos)
                      : Duration.zero;
                  final bufFraction = durMs > 0
                      ? (tl.buffered.inMilliseconds / durMs).clamp(0.0, 1.0)
                      : 0.0;

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _ScrubbableSeekbar(
                        fraction: fraction,
                        bufferedFraction: bufFraction,
                        isScrubbing: _isScrubbing,
                        scrubPreviewLabel: _formatClock(displayPos),
                        trackHeight: m.trackHeight,
                        playheadSize: m.playheadSize,
                        touchHeight: m.seekbarTouchHeight,
                        onScrubStart: (f) {
                          _autoHideTimer?.cancel();
                          HapticFeedback.selectionClick();
                          setState(() {
                            _isScrubbing = true;
                            _scrubFraction = f;
                          });
                        },
                        onScrubUpdate: (f) =>
                            setState(() => _scrubFraction = f),
                        onScrubEnd: (f) {
                          setState(() => _isScrubbing = false);
                          if (durMs > 0) {
                            ctrl.seekTo(
                              Duration(milliseconds: (f * durMs).round()),
                            );
                          }
                          _scheduleAutoHide();
                        },
                      ),
                      SizedBox(height: m.trackToTimeGap),
                      SizedBox(
                        height: m.timeRowHeight,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              _formatClock(displayPos),
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: m.timestampFontSize,
                                fontWeight: FontWeight.w400,
                                color: Colors.white,
                                height: 1.2,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '- ${_formatClock(remaining)}',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: m.timestampFontSize,
                                fontWeight: FontWeight.w400,
                                color: Colors.white,
                                height: 1.2,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
              SizedBox(height: m.timeToLinksGap),

              // Dead-center Links pill (Figma 159:47: 112x65 capsule, #303338 fill, NO border)
              SizedBox(
                height: m.linksHeight,
                child: Center(
                  child: _LinksPillButton(
                    height: m.linksHeight,
                    minWidth: m.linksMinWidth,
                    fontSize: m.linksFontSize,
                    onTap: () {
                      _autoHideTimer?.cancel();
                      showPlayerLinksModal(
                        context,
                        controller: ctrl,
                      ).whenComplete(_scheduleAutoHide);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTransportControls(
    PlayerSessionController ctrl,
    PlayerUiState st,
    _PlayerHudMetrics m,
  ) {
    final showSpinner =
        st.isInitializing || st.isSwitchingSource || st.isBuffering;

    // Expand hit area around ±10s icons without inflating their visual gap to Play.
    final hitPadH = ((44.0 - m.seekIconSize) / 2.0).clamp(0.0, 12.0);
    final adjustedGap = math.max(12.0, m.transportVisualGap - hitPadH);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SeekTenButton(
          isForward: false,
          iconSize: m.seekIconSize,
          fontSize: m.seekTenFontSize,
          hitPadH: hitPadH,
          onTap: () => _seekTenWithFeedback(-1),
        ),
        SizedBox(width: adjustedGap),
        _TactileScaleWrapper(
          onTap: () {
            HapticFeedback.lightImpact();
            ctrl.togglePlayPause();
            _scheduleAutoHide();
          },
          child: Container(
            width: m.playCircleSize,
            height: m.playCircleSize,
            decoration: const BoxDecoration(
              color: Color(0xFF333333),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: showSpinner
                ? SizedBox(
                    width: m.playCircleSize * 0.4,
                    height: m.playCircleSize * 0.4,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2.6,
                      color: Colors.white,
                    ),
                  )
                : Padding(
                    padding: EdgeInsets.only(
                      left: st.isPlaying ? 0 : (3.0 * m.s).clamp(2.0, 4.0),
                    ),
                    child: PlayerSvgIcon(
                      st.isPlaying
                          ? PlayerIcons.pauseBars
                          : PlayerIcons.playTriangle,
                      size: m.playCircleSize * 0.37,
                    ),
                  ),
          ),
        ),
        SizedBox(width: adjustedGap),
        _SeekTenButton(
          isForward: true,
          iconSize: m.seekIconSize,
          fontSize: m.seekTenFontSize,
          hitPadH: hitPadH,
          onTap: () => _seekTenWithFeedback(1),
        ),
      ],
    );
  }

  Widget _buildErrorCard(
    BuildContext context,
    PlayerSessionController ctrl,
    PlayerUiState st,
  ) {
    final err = st.error ??
        UserError.from(
          st.errorMessage,
          fallbackType: UserErrorType.playbackFailed,
          logTag: 'PlayerScreen',
        );

    if (err.type == UserErrorType.noAddons) {
      return AppStatusCard.noAddons(
        compact: true,
        onInstallAddons: () {
          Navigator.of(context).pushReplacement<void, void>(
            addonsRoute<void>(const AddonsScreen()),
          );
        },
      );
    }

    final hasLinks = st.rankedStreams.isNotEmpty;
    return AppStatusCard.fromError(
      err,
      compact: true,
      actionLabelOverride: 'Retry',
      onAction: () => ctrl.retryCurrentOrNext(),
      secondaryActionLabel: hasLinks ? 'Switch Link' : null,
      onSecondaryAction: hasLinks
          ? () => showPlayerLinksModal(context, controller: ctrl)
          : null,
    );
  }
}

/// Isolates the native [Video] texture so HUD toggles & seekbar ticks never
/// cause [Video] to rebuild unnecessarily.
class _IsolatedVideoSurface extends StatefulWidget {
  const _IsolatedVideoSurface({required this.controller});
  final PlayerSessionController controller;

  @override
  State<_IsolatedVideoSurface> createState() => _IsolatedVideoSurfaceState();
}

class _IsolatedVideoSurfaceState extends State<_IsolatedVideoSurface> {
  final _videoKey = GlobalKey();
  late VideoFitMode _fitMode;
  late double _subScale;

  @override
  void initState() {
    super.initState();
    _fitMode = widget.controller.state.fitMode;
    _subScale = widget.controller.subtitleScaleNotifier.value;
    widget.controller.addListener(_onControllerChanged);
    widget.controller.subtitleScaleNotifier.addListener(_onSubScaleChanged);
  }

  void _onControllerChanged() {
    final next = widget.controller.state.fitMode;
    if (next != _fitMode && mounted) {
      setState(() => _fitMode = next);
    }
  }

  void _onSubScaleChanged() {
    final next = widget.controller.subtitleScaleNotifier.value;
    if ((next - _subScale).abs() > 0.005 && mounted) {
      setState(() => _subScale = next);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    widget.controller.subtitleScaleNotifier.removeListener(_onSubScaleChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fit = switch (_fitMode) {
      VideoFitMode.fit => BoxFit.contain,
      VideoFitMode.fill => BoxFit.cover,
      VideoFitMode.stretch16x9 => BoxFit.fill,
    };
    final aspect = _fitMode == VideoFitMode.stretch16x9 ? 16 / 9 : null;
    return RepaintBoundary(
      child: ColoredBox(
        color: const Color(0xFF000000),
        child: Video(
          key: _videoKey,
          controller: widget.controller.videoController,
        fit: fit,
        aspectRatio: aspect,
        controls: NoVideoControls,
        wakelock: false,
        pauseUponEnteringBackgroundMode: true,
        subtitleViewConfiguration: SubtitleViewConfiguration(
          visible: true,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 36.0 * _subScale,
            fontWeight: FontWeight.w600,
            height: 1.35,
            color: Colors.white,
            backgroundColor: const Color(0x99000000),
            shadows: const [
              Shadow(color: Colors.black, blurRadius: 4),
            ],
          ),
            textAlign: TextAlign.center,
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
          ),
        ),
      ),
    );
  }
}

class _TactileScaleWrapper extends StatefulWidget {
  const _TactileScaleWrapper({required this.onTap, required this.child});
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_TactileScaleWrapper> createState() => _TactileScaleWrapperState();
}

class _TactileScaleWrapperState extends State<_TactileScaleWrapper> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.90 : 1.0,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Single source of truth for proportional Figma `159:21` & `161:52` player
/// layout metrics across all screen sizes and aspect ratios.
class _PlayerHudMetrics {
  _PlayerHudMetrics.from(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final vp = MediaQuery.viewPaddingOf(context);

    // Figma reference canvas is 1612x720 (exact 0.50 scale on 360dp-tall phones).
    s = (size.height / 720.0).clamp(0.45, 1.20);

    // Symmetric cutout margin so punch-holes never shift the HUD off-center.
    final symmetricCutout = math.max(vp.left, vp.right);

    // Top bar hugs screen edges at Figma's 40/1612 (~2.5%) while clearing cutouts.
    topEdgeH = math.max(symmetricCutout + 6.0, size.width * 0.025);
    topEdgeV = math.max(vp.top, 0.0) + (27.0 * s);

    // Seekbar width is strictly proportional to the top bar's visible span:
    // Figma top bar span = 1523px, seekbar width = 1226px (80.5% of top bar),
    // giving symmetric ~9.75% margins inward from the top bar (~193px @ 1612px).
    final topBarSpan = (size.width - 2 * topEdgeH).clamp(200.0, size.width);
    final seekbarWidth = (topBarSpan * 0.805).clamp(180.0, topBarSpan);
    seekbarEdgeH = (size.width - seekbarWidth) / 2.0;

    // Bottom margin below Links pill: Figma 720 - (599 + 65) = 56px -> 56 * s.
    bottomEdgeV = math.max(vp.bottom, 0.0) + (56.0 * s).clamp(16.0, 56.0);

    // Top bar typography & icons (exact Figma 159:21 ratios):
    closeIconSize = (30.0 * s).clamp(15.0, 30.0);
    closeToTitleGap = (30.0 * s).clamp(13.0, 30.0);
    titleFontSize = (46.0 * s).clamp(21.0, 42.0);
    titleToSubGap = (10.0 * s).clamp(4.0, 10.0);
    subtitleFontSize = (26.0 * s).clamp(12.5, 24.0);
    subIconSize = (33.0 * s).clamp(17.0, 32.0);
    speedFontSize = (27.0 * s).clamp(13.5, 25.0);
    settingsIconSize = (36.0 * s).clamp(18.0, 34.0);
    topRightIconGap = (36.0 * s).clamp(16.0, 36.0);

    // Center transport controls (Figma 159:34, 159:37, 159:40):
    playCircleSize = (103.0 * s).clamp(50.0, 96.0);
    seekIconSize = (48.0 * s).clamp(24.0, 46.0);
    seekTenFontSize = (20.0 * s).clamp(10.0, 19.0);
    transportVisualGap = (86.0 * s).clamp(38.0, 86.0);

    // Seekbar & timestamps (Figma 159:21 & 164:21):
    trackHeight = (10.0 * s).clamp(4.5, 9.0);
    playheadSize = (22.0 * s).clamp(11.0, 20.0);
    seekbarTouchHeight = math.max(24.0, playheadSize + 12.0);
    final trackBottomPadding = (seekbarTouchHeight - trackHeight) / 2.0;
    trackToTimeGap = math.max(0.0, (14.0 * s) - trackBottomPadding);
    timestampFontSize = (18.0 * s).clamp(10.5, 17.0);
    timeRowHeight = timestampFontSize * 1.25;

    // Borderless Links pill (Figma 159:47: 112x65 capsule, #303338 fill, no border):
    linksHeight = (65.0 * s).clamp(32.0, 56.0);
    linksMinWidth = math.max(linksHeight * (112.0 / 65.0), 60.0);
    linksFontSize = (23.0 * s).clamp(12.0, 21.0);
    timeToLinksGap = (2.0 * s).clamp(1.0, 4.0);

    // Skip intro / Skip outro / Next episode (Figma 161:52: 176x56, 24px above track):
    final trackTopFromBottom = bottomEdgeV +
        linksHeight +
        timeToLinksGap +
        timeRowHeight +
        trackToTimeGap +
        trackBottomPadding +
        trackHeight;
    skipBtnHeight = (56.0 * s).clamp(32.0, 48.0);
    skipBtnMinWidth = (skipBtnHeight * (176.0 / 56.0)).clamp(100.0, 160.0);
    skipBtnFontSize = (24.0 * s).clamp(13.0, 21.0);
    skipBtnRadius = (10.0 * s).clamp(6.0, 10.0);
    skipBottomWhenHudVisible =
        trackTopFromBottom + (24.0 * s).clamp(10.0, 24.0);
    skipBottomWhenHudHidden = bottomEdgeV;
  }

  late final double s;
  late final double topEdgeH;
  late final double topEdgeV;
  late final double seekbarEdgeH;
  late final double bottomEdgeV;

  late final double closeIconSize;
  late final double closeToTitleGap;
  late final double titleFontSize;
  late final double titleToSubGap;
  late final double subtitleFontSize;
  late final double subIconSize;
  late final double speedFontSize;
  late final double settingsIconSize;
  late final double topRightIconGap;

  late final double playCircleSize;
  late final double seekIconSize;
  late final double seekTenFontSize;
  late final double transportVisualGap;

  late final double trackHeight;
  late final double playheadSize;
  late final double seekbarTouchHeight;
  late final double trackToTimeGap;
  late final double timestampFontSize;
  late final double timeRowHeight;

  late final double linksHeight;
  late final double linksMinWidth;
  late final double linksFontSize;
  late final double timeToLinksGap;

  late final double skipBtnHeight;
  late final double skipBtnMinWidth;
  late final double skipBtnFontSize;
  late final double skipBtnRadius;
  late final double skipBottomWhenHudVisible;
  late final double skipBottomWhenHudHidden;
}

class _TactilePlayerButton extends StatefulWidget {
  const _TactilePlayerButton({
    required this.semanticLabel,
    required this.onTap,
    required this.child,
    this.highlighted = false,
    this.width,
    this.height = 40,
    this.horizontalPadding = 8,
    this.alignment = Alignment.center,
  });

  final String semanticLabel;
  final VoidCallback onTap;
  final Widget child;
  final bool highlighted;
  final double? width;
  final double height;
  final double horizontalPadding;
  final Alignment alignment;

  @override
  State<_TactilePlayerButton> createState() => _TactilePlayerButtonState();
}

class _TactilePlayerButtonState extends State<_TactilePlayerButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: () {
          HapticFeedback.selectionClick();
          widget.onTap();
        },
        child: AnimatedScale(
          scale: _pressed ? 0.88 : 1.0,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          child: AnimatedOpacity(
            opacity: _pressed ? 0.65 : 1.0,
            duration: const Duration(milliseconds: 110),
            child: SizedBox(
              width: widget.width,
              height: widget.height,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: widget.width != null ? 0 : widget.horizontalPadding,
                ),
                child: Align(
                  alignment: widget.alignment,
                  widthFactor: widget.width != null ? null : 1.0,
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SeekTenButton extends StatelessWidget {
  const _SeekTenButton({
    required this.isForward,
    required this.iconSize,
    required this.fontSize,
    required this.hitPadH,
    required this.onTap,
  });

  final bool isForward;
  final double iconSize;
  final double fontSize;
  final double hitPadH;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => _TactileScaleWrapper(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: hitPadH, vertical: 10),
          child: SizedBox(
            width: iconSize,
            height: iconSize,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PlayerSvgIcon(
                  isForward ? PlayerIcons.forward10 : PlayerIcons.rewind10,
                  size: iconSize,
                ),
                Padding(
                  padding: EdgeInsets.only(top: iconSize * 0.11),
                  child: Text(
                    '10',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: fontSize,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.0,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _ScrubbableSeekbar extends StatelessWidget {
  const _ScrubbableSeekbar({
    required this.fraction,
    required this.bufferedFraction,
    required this.isScrubbing,
    required this.scrubPreviewLabel,
    required this.trackHeight,
    required this.playheadSize,
    required this.touchHeight,
    required this.onScrubStart,
    required this.onScrubUpdate,
    required this.onScrubEnd,
  });

  final double fraction;
  final double bufferedFraction;
  final bool isScrubbing;
  final String scrubPreviewLabel;
  final double trackHeight;
  final double playheadSize;
  final double touchHeight;
  final ValueChanged<double> onScrubStart;
  final ValueChanged<double> onScrubUpdate;
  final ValueChanged<double> onScrubEnd;

  double _calcFraction(BoxConstraints constraints, Offset localPos) {
    if (constraints.maxWidth <= 0) return 0.0;
    return (localPos.dx / constraints.maxWidth).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final clampedF = fraction.clamp(0.0, 1.0);
        final clampedBuf = bufferedFraction.clamp(0.0, 1.0);
        final trackH = isScrubbing ? (trackHeight * 1.3) : trackHeight;
        final dotSize = isScrubbing ? (playheadSize * 1.32) : playheadSize;
        final dotLeft = (w * clampedF - dotSize / 2)
            .clamp(0.0, (w - dotSize).clamp(0.0, w));
        final pillW = 64.w;
        final pillLeft = (w * clampedF - pillW / 2)
            .clamp(0.0, (w - pillW).clamp(0.0, w));

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (d) =>
              onScrubStart(_calcFraction(constraints, d.localPosition)),
          onHorizontalDragUpdate: (d) =>
              onScrubUpdate(_calcFraction(constraints, d.localPosition)),
          onHorizontalDragEnd: (_) => onScrubEnd(clampedF),
          onTapDown: (d) {
            final f = _calcFraction(constraints, d.localPosition);
            onScrubStart(f);
            onScrubEnd(f);
          },
          child: SizedBox(
            height: touchHeight,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.centerLeft,
              children: [
                if (isScrubbing)
                  Positioned(
                    left: pillLeft,
                    top: -32.h,
                    child: Container(
                      width: pillW,
                      height: 26.h,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xE613161F),
                        borderRadius: BorderRadius.circular(8.r),
                        border: Border.all(color: const Color(0x33FFFFFF)),
                      ),
                      child: Text(
                        scrubPreviewLabel,
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                // Background track (Figma #303030)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  height: trackH,
                  decoration: BoxDecoration(
                    color: const Color(0xFF303030),
                    borderRadius: BorderRadius.circular(trackH / 2),
                  ),
                ),
                // Buffered bar
                FractionallySizedBox(
                  widthFactor: clampedBuf,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    height: trackH,
                    decoration: BoxDecoration(
                      color: const Color(0xFF525252),
                      borderRadius: BorderRadius.circular(trackH / 2),
                    ),
                  ),
                ),
                // Elapsed white bar (Figma #FFFFFF)
                FractionallySizedBox(
                  widthFactor: clampedF,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    height: trackH,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(trackH / 2),
                    ),
                  ),
                ),
                // Circular playhead dot (Figma 164:21)
                Positioned(
                  left: dotLeft,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: dotSize,
                    height: dotSize,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LinksPillButton extends StatelessWidget {
  const _LinksPillButton({
    required this.onTap,
    required this.height,
    required this.minWidth,
    required this.fontSize,
  });

  final VoidCallback onTap;
  final double height;
  final double minWidth;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return _TactileScaleWrapper(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        height: height,
        constraints: BoxConstraints(minWidth: minWidth),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: const Color(0xFF303338),
          borderRadius: BorderRadius.circular(height / 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Links',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: fontSize,
                fontWeight: FontWeight.w400,
                color: Colors.white,
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Floating Skip Intro / Recap (left-aligned to seekbar start) and Skip Outro /
/// Post-Credits / Next Episode (right-aligned to seekbar end) overlay.
/// Matches Figma node `161:52` ("Skip intro") and listens exclusively to
/// [PlayerSessionController.activeSkipPromptNotifier] so playback ticks never
/// trigger HUD or video surface rebuilds.
class _SkipPromptOverlay extends StatelessWidget {
  const _SkipPromptOverlay({
    required this.controller,
    required this.hudVisible,
    required this.isScrubbing,
  });

  final PlayerSessionController controller;
  final bool hudVisible;
  final bool isScrubbing;

  @override
  Widget build(BuildContext context) {
    final m = _PlayerHudMetrics.from(context);
    final bottomOffset =
        hudVisible ? m.skipBottomWhenHudVisible : m.skipBottomWhenHudHidden;

    return ValueListenableBuilder<ActiveSkipPrompt?>(
      valueListenable: controller.activeSkipPromptNotifier,
      builder: (context, prompt, _) {
        final show = prompt != null && !isScrubbing;
        final isLeft = prompt?.isLeftAligned ?? true;

        return AnimatedPositioned(
          duration: const Duration(milliseconds: 200),
          curve: const Cubic(0.22, 1, 0.36, 1),
          left: m.seekbarEdgeH,
          right: m.seekbarEdgeH,
          bottom: bottomOffset,
          child: Align(
            alignment: isLeft ? Alignment.bottomLeft : Alignment.bottomRight,
            child: IgnorePointer(
              ignoring: !show,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                curve: const Cubic(0.22, 1, 0.36, 1),
                opacity: show ? 1.0 : 0.0,
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 180),
                  curve: const Cubic(0.22, 1, 0.36, 1),
                  scale: show ? 1.0 : 0.94,
                  alignment:
                      isLeft ? Alignment.bottomLeft : Alignment.bottomRight,
                  child: prompt == null
                      ? const SizedBox.shrink()
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!isLeft &&
                                prompt.autoSkipCountdownSec != null) ...[
                              _SkipDismissButton(
                                size: m.skipBtnHeight,
                                radius: m.skipBtnRadius,
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  controller.dismissActiveSkip();
                                },
                              ),
                              const SizedBox(width: 8),
                            ],
                            _FigmaSkipButton(
                              label: prompt.displayLabel,
                              height: m.skipBtnHeight,
                              minWidth: m.skipBtnMinWidth,
                              fontSize: m.skipBtnFontSize,
                              borderRadius: m.skipBtnRadius,
                              tabularNums: prompt.autoSkipCountdownSec != null,
                              onTap: () {
                                HapticFeedback.lightImpact();
                                controller.triggerActiveSkip();
                              },
                            ),
                            if (isLeft &&
                                prompt.autoSkipCountdownSec != null) ...[
                              const SizedBox(width: 8),
                              _SkipDismissButton(
                                size: m.skipBtnHeight,
                                radius: m.skipBtnRadius,
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  controller.dismissActiveSkip();
                                },
                              ),
                            ],
                          ],
                        ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FigmaSkipButton extends StatelessWidget {
  const _FigmaSkipButton({
    required this.label,
    required this.height,
    required this.minWidth,
    required this.fontSize,
    required this.borderRadius,
    required this.tabularNums,
    required this.onTap,
  });

  final String label;
  final double height;
  final double minWidth;
  final double fontSize;
  final double borderRadius;
  final bool tabularNums;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: _TactileScaleWrapper(
        onTap: onTap,
        child: Container(
          height: height,
          constraints: BoxConstraints(minWidth: minWidth),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(borderRadius),
            boxShadow: const [
              BoxShadow(
                color: Color(0x52000000),
                blurRadius: 14,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: fontSize,
                  fontWeight: FontWeight.w500,
                  height: 1.25,
                  color: const Color(0xFF000000),
                  fontFeatures:
                      tabularNums ? const [FontFeature.tabularFigures()] : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SkipDismissButton extends StatelessWidget {
  const _SkipDismissButton({
    required this.size,
    required this.radius,
    required this.onTap,
  });

  final double size;
  final double radius;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Cancel auto-skip',
      child: _TactileScaleWrapper(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xCC181B26),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: const Color(0x2EFFFFFF)),
          ),
          child: const Icon(
            Icons.close_rounded,
            size: 18,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
