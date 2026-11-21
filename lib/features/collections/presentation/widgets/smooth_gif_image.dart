import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../../core/perf/image_perf.dart';

/// Vsync-driven animated GIF/WebP player that decodes downscaled frames into a
/// private [ui.Codec] and prefetches frame `N+1` while frame `N` displays.
class SmoothGifImage extends StatefulWidget {
  const SmoothGifImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.targetWidthPx,
    this.loop = true,
    this.onFirstFrame,
    this.onCompleted,
    this.onError,
  });

  final String url;
  final BoxFit fit;
  final int? targetWidthPx;
  final bool loop;
  final VoidCallback? onFirstFrame;
  final VoidCallback? onCompleted;
  final VoidCallback? onError;

  @override
  State<SmoothGifImage> createState() => _SmoothGifImageState();
}

class _SmoothGifImageState extends State<SmoothGifImage>
    with SingleTickerProviderStateMixin {
  static const Duration _lookaheadTolerance = Duration(milliseconds: 4);
  static const Duration _defaultFrameDuration = Duration(milliseconds: 40);
  static const Duration _zeroFrameFallback = Duration(milliseconds: 100);

  late final Ticker _ticker;
  ui.Codec? _codec;
  int _frameCount = 1;
  int _framesShownInLoop = 0;

  ui.Image? _currentImage;
  ui.FrameInfo? _prefetchedFrame;
  bool _isPrefetching = false;

  Duration _currentFrameDuration = _defaultFrameDuration;
  Duration _nextFrameTarget = Duration.zero;
  bool _hasStartedClock = false;
  bool _completedNotified = false;
  bool _isPaused = false;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final shouldPause =
        !TickerMode.valuesOf(context).enabled ||
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    if (shouldPause == _isPaused) return;
    _isPaused = shouldPause;
    if (_isPaused) {
      if (_ticker.isActive) {
        _ticker.stop();
        _hasStartedClock = false;
      }
    } else if (_codec != null &&
        _frameCount > 1 &&
        (widget.loop || !_completedNotified)) {
      _startTicker();
    }
  }

  @override
  void didUpdateWidget(covariant SmoothGifImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.targetWidthPx != widget.targetWidthPx) {
      _load();
    } else if (oldWidget.loop != widget.loop &&
        widget.loop &&
        _codec != null &&
        _frameCount > 1 &&
        !_isPaused &&
        !_ticker.isActive) {
      _completedNotified = false;
      _startTicker();
    }
  }

  void _startTicker() {
    if (_ticker.isActive || _isPaused) return;
    _hasStartedClock = false;
    _ticker.start();
  }

  Duration _sanitizeFrameDuration(Duration raw) {
    return raw <= Duration.zero ? _zeroFrameFallback : raw;
  }

  void _scheduleDisposeImage(ui.Image? image) {
    if (image == null) return;
    SchedulerBinding.instance.addPostFrameCallback(
      (_) => image.dispose(),
      debugLabel: 'SmoothGifImage.disposeOldImage',
    );
  }

  void _resetPlayback({bool clearCurrentImage = true}) {
    if (_ticker.isActive) {
      _ticker.stop();
    }
    _codec?.dispose();
    _codec = null;
    _prefetchedFrame?.image.dispose();
    _prefetchedFrame = null;
    if (clearCurrentImage) {
      _scheduleDisposeImage(_currentImage);
      _currentImage = null;
    }
    _frameCount = 1;
    _framesShownInLoop = 0;
    _isPrefetching = false;
    _currentFrameDuration = _defaultFrameDuration;
    _nextFrameTarget = Duration.zero;
    _hasStartedClock = false;
    _completedNotified = false;
  }

  Future<void> _load() async {
    final gen = ++_loadGeneration;
    _resetPlayback();

    try {
      final file = await PixelImageCache.instance.getSingleFile(widget.url);
      if (!mounted || gen != _loadGeneration) return;

      final buffer = await ui.ImmutableBuffer.fromFilePath(file.path);
      if (!mounted || gen != _loadGeneration) return;

      final targetW = widget.targetWidthPx;
      final codec =
          await PaintingBinding.instance.instantiateImageCodecWithSize(
        buffer,
        getTargetSize: targetW != null
            ? (int intrinsicWidth, int intrinsicHeight) {
                if (targetW > 0 && targetW < intrinsicWidth) {
                  return ui.TargetImageSize(width: targetW);
                }
                return const ui.TargetImageSize();
              }
            : null,
      );
      if (!mounted || gen != _loadGeneration) {
        codec.dispose();
        return;
      }

      _codec = codec;
      _frameCount = codec.frameCount;

      final firstFrame = await codec.getNextFrame();
      if (!mounted || gen != _loadGeneration) {
        firstFrame.image.dispose();
        return;
      }

      _showFrame(firstFrame, notifyFirst: true);

      if (_frameCount > 1) {
        _prefetchNextFrame(gen);
        if (!_isPaused) {
          _startTicker();
        }
      }
    } catch (_) {
      if (!mounted || gen != _loadGeneration) return;
      widget.onError?.call();
    }
  }

  void _showFrame(ui.FrameInfo frame, {bool notifyFirst = false}) {
    final oldImage = _currentImage;
    setState(() {
      _currentImage = frame.image;
    });
    _scheduleDisposeImage(oldImage);

    _currentFrameDuration = _sanitizeFrameDuration(frame.duration);
    _framesShownInLoop += 1;

    if (notifyFirst) {
      widget.onFirstFrame?.call();
    }
  }

  Future<void> _prefetchNextFrame(int gen) async {
    if (_isPrefetching || _codec == null || !mounted || gen != _loadGeneration) {
      return;
    }
    if (!widget.loop && _framesShownInLoop >= _frameCount) {
      return;
    }
    _isPrefetching = true;
    try {
      final next = await _codec!.getNextFrame();
      if (!mounted || gen != _loadGeneration) {
        next.image.dispose();
        return;
      }
      _prefetchedFrame?.image.dispose();
      _prefetchedFrame = next;
    } catch (_) {
      // Skip decode failure on prefetch; ticker will retry or hold current frame.
    } finally {
      _isPrefetching = false;
    }
  }

  void _onTick(Duration elapsed) {
    if (!mounted || _codec == null) return;

    if (!_hasStartedClock) {
      _hasStartedClock = true;
      _nextFrameTarget = elapsed + _currentFrameDuration;
      return;
    }

    if (elapsed + _lookaheadTolerance < _nextFrameTarget) {
      return;
    }

    if (!widget.loop && _framesShownInLoop >= _frameCount) {
      _ticker.stop();
      if (!_completedNotified) {
        _completedNotified = true;
        widget.onCompleted?.call();
      }
      return;
    }

    final readyFrame = _prefetchedFrame;
    if (readyFrame == null) {
      // Decoder still busy on slow hardware; hold current frame without burst skip.
      _prefetchNextFrame(_loadGeneration);
      return;
    }
    _prefetchedFrame = null;

    _showFrame(readyFrame);
    _nextFrameTarget += _currentFrameDuration;
    if (_nextFrameTarget < elapsed) {
      _nextFrameTarget = elapsed + _currentFrameDuration;
    }

    _prefetchNextFrame(_loadGeneration);
  }

  @override
  void dispose() {
    _loadGeneration += 1;
    _resetPlayback();
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final img = _currentImage;
    if (img == null) return const SizedBox.shrink();
    return RawImage(
      image: img,
      fit: widget.fit,
      width: double.infinity,
      height: double.infinity,
      filterQuality: FilterQuality.medium,
    );
  }
}
