import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../playback/playback_engine.dart';

class AmbientFrameNotifier extends StateNotifier<ui.Image?> {
  final PlaybackEngine engine;
  Timer? _timer;
  Timer? _seekCaptureTimer;
  StreamSubscription<PlaybackSnapshot>? _snapshotSubscription;
  bool _enabled;
  bool _cinema;
  bool _playing;
  bool _capturing = false;
  bool _pendingForcedCapture = false;
  bool _wasInitialized;
  Duration _lastPosition;
  int _framesPerSecond;
  int _effectiveFramesPerSecond;
  int _fastCaptureCount = 0;
  Rect? _aperture;
  double _spread;
  double _depth;
  double _softness;

  AmbientFrameNotifier(
    this.engine, {
    bool enabled = true,
    bool cinema = false,
    int framesPerSecond = 30,
    Rect? aperture,
    double spread = 1,
    double depth = 1,
    double softness = 1,
  }) : _enabled = enabled,
       _cinema = cinema,
       _framesPerSecond = framesPerSecond,
       _effectiveFramesPerSecond = framesPerSecond,
       _aperture = aperture,
       _spread = spread,
       _depth = depth,
       _softness = softness,
       _playing = engine.snapshot.isPlaying,
       _wasInitialized = engine.snapshot.initialized,
       _lastPosition = engine.snapshot.position,
       super(null) {
    _snapshotSubscription = engine.snapshots.listen((snapshot) {
      final playing = snapshot.initialized && snapshot.isPlaying;
      final becameInitialized = snapshot.initialized && !_wasInitialized;
      final positionChanged = snapshot.position != _lastPosition;
      final jumped =
          positionChanged &&
          (snapshot.position - _lastPosition).abs() >
              const Duration(milliseconds: 300);
      _wasInitialized = snapshot.initialized;
      _lastPosition = snapshot.position;

      if (_playing != playing) {
        _playing = playing;
        _refresh();
      }
      // A seek can happen while paused, when the periodic capture loop is off.
      // Also refresh on a newly loaded track before playback starts.
      if (_enabled &&
          !_cinema &&
          snapshot.initialized &&
          (becameInitialized || jumped || (!playing && positionChanged))) {
        _scheduleSeekCapture();
      }
    });
    _refresh();
  }

  void _scheduleSeekCapture() {
    _seekCaptureTimer?.cancel();
    _seekCaptureTimer = Timer(const Duration(milliseconds: 70), () {
      unawaited(_capture(force: true));
    });
  }

  void setEnabled(bool value) {
    _enabled = value;
    _refresh();
  }

  void setCinema(bool value) {
    _cinema = value;
    _refresh();
  }

  void setFramesPerSecond(int value) {
    if (_framesPerSecond == value) return;
    _framesPerSecond = value;
    _effectiveFramesPerSecond = value;
    _fastCaptureCount = 0;
    if (_timer != null) {
      _timer?.cancel();
      _timer = null;
      _refresh();
    }
  }

  void setAperture(Rect? value) {
    if (_aperture == value) return;
    _aperture = value;
    if (_enabled && !_cinema && engine.snapshot.initialized) {
      unawaited(_capture(force: true));
    }
  }

  void setGeometry({
    required double spread,
    required double depth,
    required double softness,
  }) {
    if (_spread == spread && _depth == depth && _softness == softness) return;
    _spread = spread;
    _depth = depth;
    _softness = softness;
    if (_enabled && !_cinema && engine.snapshot.initialized) {
      unawaited(_capture(force: true));
    }
  }

  void _refresh() {
    if (!_enabled || _cinema) {
      _timer?.cancel();
      _timer = null;
      _replaceFrame(null);
      return;
    }
    if (!_playing) {
      _timer?.cancel();
      _timer = null;
      if (engine.snapshot.initialized) unawaited(_capture(force: true));
      return;
    }
    if (_timer != null) return;
    unawaited(_capture());
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(
      Duration(microseconds: 1000000 ~/ _effectiveFramesPerSecond),
      (_) => unawaited(_capture()),
    );
  }

  void _adaptCaptureRate(int elapsedMicroseconds) {
    final budget = 1000000 / _effectiveFramesPerSecond;
    if (elapsedMicroseconds > budget * 1.15 && _effectiveFramesPerSecond > 15) {
      _effectiveFramesPerSecond = _effectiveFramesPerSecond > 30 ? 30 : 15;
      _fastCaptureCount = 0;
      _startTimer();
      return;
    }
    if (_effectiveFramesPerSecond >= _framesPerSecond) return;
    if (elapsedMicroseconds < budget * 0.5) {
      _fastCaptureCount++;
      if (_fastCaptureCount >= 60) {
        _effectiveFramesPerSecond = _effectiveFramesPerSecond < 30 ? 30 : 60;
        _fastCaptureCount = 0;
        _startTimer();
      }
    } else {
      _fastCaptureCount = 0;
    }
  }

  Future<void> _capture({bool force = false}) async {
    if (!mounted ||
        !_enabled ||
        _cinema ||
        (!_playing && !force) ||
        !engine.snapshot.initialized ||
        (!engine.snapshot.isPlaying && !force)) {
      return;
    }
    if (_capturing) {
      if (force) _pendingForcedCapture = true;
      return;
    }
    _capturing = true;
    final stopwatch = Stopwatch()..start();
    try {
      final frame = await engine.captureAmbientFrame(
        aperture: _aperture,
        spread: _spread,
        depth: _depth,
        softness: _softness,
      );
      if (mounted && _enabled && !_cinema && frame != null) {
        _replaceFrame(frame);
      } else {
        frame?.dispose();
      }
    } catch (_) {
    } finally {
      stopwatch.stop();
      _capturing = false;
      if (!force && _playing && _timer != null) {
        _adaptCaptureRate(stopwatch.elapsedMicroseconds);
      }
      if (_pendingForcedCapture) {
        _pendingForcedCapture = false;
        unawaited(_capture(force: true));
      }
    }
  }

  void _replaceFrame(ui.Image? frame) {
    final previous = state;
    if (identical(previous, frame)) return;
    state = frame;
    if (previous != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _seekCaptureTimer?.cancel();
    _snapshotSubscription?.cancel();
    state?.dispose();
    super.dispose();
  }
}
