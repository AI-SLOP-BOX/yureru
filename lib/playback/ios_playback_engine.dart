import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player_pip/index.dart' as vp;

import 'media_kit_engine.dart';
import 'playback_engine.dart';

/// Uses AVPlayer/AVPlayerLayer on iOS so the system can take over the layer
/// for PiP. Sources AVPlayer cannot open fall back to the normal mpv engine.
class IosPlaybackEngine implements PlaybackEngine {
  vp.VideoPlayerController? _controller;
  PlaybackEngine? _fallback;
  final PlaybackEngine Function() _createFallback;
  final List<StreamSubscription<dynamic>> _fallbackSubscriptions = [];

  IosPlaybackEngine({PlaybackEngine Function()? fallbackFactory})
    : _createFallback = fallbackFactory ?? MediaKitPlaybackEngine.new;
  PlaybackSnapshot _snapshot = const PlaybackSnapshot();
  Duration? _endAt;
  PlaybackSource? _activeSource;
  final _snapshots = StreamController<PlaybackSnapshot>.broadcast();
  final _completed = StreamController<void>.broadcast();
  final _positions = StreamController<Duration>.broadcast();
  final _durations = StreamController<Duration>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  void Function()? _onEnded;
  bool _didComplete = false;
  bool _switchingToFallback = false;
  double _volume = 1;
  double _speed = 1;

  static const _avFoundationExtensions = <String>{
    'mp4',
    'm4v',
    'mov',
    'm3u8',
    'mp3',
    'm4a',
    'aac',
    'wav',
    'aiff',
    'caf',
  };

  bool _isAvFoundationCandidate(String uri) {
    final parsed = Uri.tryParse(uri);
    final path = parsed?.path ?? uri;
    final extension = path.split('.').last.toLowerCase();
    return _avFoundationExtensions.contains(extension);
  }

  @override
  Future<void> load(PlaybackSource source, {bool autoplay = true}) async {
    await _disposeActive();
    _switchingToFallback = false;
    _activeSource = source;
    _didComplete = false;
    _endAt = source.end;
    _snapshot = const PlaybackSnapshot();
    _snapshots.add(_snapshot);

    if (!_isAvFoundationCandidate(source.uri)) {
      await _loadWithMediaKit(source, autoplay: autoplay);
      return;
    }

    vp.VideoPlayerController? controller;
    try {
      final uri = Uri.tryParse(source.uri);
      final isNetwork =
          uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
      controller = isNetwork
          ? vp.VideoPlayerController.networkUrl(
              uri,
              videoPlayerOptions: vp.VideoPlayerOptions(
                allowBackgroundPlayback: true,
              ),
            )
          : vp.VideoPlayerController.file(
              File(uri?.scheme == 'file' ? uri!.toFilePath() : source.uri),
              videoPlayerOptions: vp.VideoPlayerOptions(
                allowBackgroundPlayback: true,
              ),
            );
      await controller.initialize();
      _controller = controller;
      controller.addListener(_onVideoPlayerChanged);
      await controller.setVolume(_volume);
      await controller.setPlaybackSpeed(_speed);
      if (source.start != null && source.start! > Duration.zero) {
        await controller.seekTo(source.start!);
      }
      if (autoplay) await controller.play();
      _onVideoPlayerChanged();
    } catch (_) {
      controller?.removeListener(_onVideoPlayerChanged);
      _controller = null;
      await controller?.dispose();
      await _loadWithMediaKit(source, autoplay: autoplay);
    }
  }

  Future<void> _loadWithMediaKit(
    PlaybackSource source, {
    required bool autoplay,
  }) async {
    final fallback = _createFallback();
    _fallback = fallback;
    fallback.onEnded = () => _onEnded?.call();
    // Subscribers keep the same streams across AVPlayer/mpv transitions.
    _fallbackSubscriptions.addAll([
      fallback.snapshots.listen((value) {
        _snapshot = value;
        _snapshots.add(value);
      }),
      fallback.positionStream.listen(_positions.add),
      fallback.durationStream.listen(_durations.add),
      fallback.playingStream.listen(_playing.add),
      fallback.completedStream.listen((_) => _completed.add(null)),
    ]);
    await fallback.setVolume(_volume);
    await fallback.setSpeed(_speed);
    await fallback.load(source, autoplay: autoplay);
  }

  void _onVideoPlayerChanged() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final value = controller.value;
    if (value.hasError && !_switchingToFallback) {
      unawaited(_switchToMediaKit(controller));
      return;
    }
    final endAt = _endAt;
    if (endAt != null && value.position >= endAt && !_didComplete) {
      _didComplete = true;
      unawaited(controller.pause());
      unawaited(controller.seekTo(endAt));
      _snapshot = PlaybackSnapshot(
        position: endAt,
        duration: value.duration,
        isPlaying: false,
        initialized: true,
        completed: true,
      );
      _snapshots.add(_snapshot);
      _positions.add(endAt);
      _playing.add(false);
      _completed.add(null);
      _onEnded?.call();
      return;
    }
    final completedNow = value.isCompleted && !_didComplete;
    if (completedNow) {
      _didComplete = true;
      _completed.add(null);
      _onEnded?.call();
    } else if (!value.isCompleted &&
        (endAt == null || value.position < endAt)) {
      _didComplete = false;
    }
    _snapshot = PlaybackSnapshot(
      position: value.position,
      duration: value.duration,
      isPlaying: value.isPlaying,
      initialized: value.isInitialized,
      completed: value.isCompleted,
    );
    _snapshots.add(_snapshot);
    _positions.add(value.position);
    _durations.add(value.duration);
    _playing.add(value.isPlaying);
  }

  Future<void> _switchToMediaKit(vp.VideoPlayerController controller) async {
    final source = _activeSource;
    if (source == null || _switchingToFallback) return;
    _switchingToFallback = true;
    final resumePosition = controller.value.position;
    final shouldResume = controller.value.isPlaying;
    final fallbackSource = PlaybackSource(
      mediaId: source.mediaId,
      uri: source.uri,
      start: resumePosition,
      end: source.end,
    );
    controller.removeListener(_onVideoPlayerChanged);
    _controller = null;
    await controller.dispose();
    await _loadWithMediaKit(fallbackSource, autoplay: shouldResume);
  }

  Future<void> _disposeActive() async {
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      controller.removeListener(_onVideoPlayerChanged);
      await controller.dispose();
    }
    for (final subscription in _fallbackSubscriptions) {
      await subscription.cancel();
    }
    _fallbackSubscriptions.clear();
    final fallback = _fallback;
    _fallback = null;
    await fallback?.dispose();
  }

  @override
  Future<void> open(String mediaId, String pathOrUrl) =>
      load(PlaybackSource(mediaId: mediaId, uri: pathOrUrl));

  @override
  Future<void> play() async {
    final fallback = _fallback;
    if (fallback != null) return fallback.play();
    await _controller?.play();
  }

  @override
  Future<void> pause() async {
    final fallback = _fallback;
    if (fallback != null) return fallback.pause();
    await _controller?.pause();
  }

  @override
  Future<void> seekTo(Duration position) async {
    final fallback = _fallback;
    if (fallback != null) return fallback.seekTo(position);
    await _controller?.seekTo(position);
  }

  @override
  Future<void> setSpeed(double speed) => setPlaybackRate(speed);

  @override
  Future<void> setPlaybackRate(double rate) async {
    _speed = rate;
    final fallback = _fallback;
    if (fallback != null) return fallback.setPlaybackRate(rate);
    await _controller?.setPlaybackSpeed(rate);
  }

  @override
  Future<ui.Image?> captureAmbientFrame({
    Rect? aperture,
    double spread = 1,
    double depth = 1,
    double softness = 1,
  }) async => _fallback?.captureAmbientFrame(
    aperture: aperture,
    spread: spread,
    depth: depth,
    softness: softness,
  );

  @override
  void setAmbientFrameSource(Future<ui.Image?> Function()? capture) {
    _fallback?.setAmbientFrameSource(capture);
  }

  @override
  ValueListenable<ui.Image?>? get ambientMatteFrameListenable =>
      _fallback?.ambientMatteFrameListenable;

  // Keep AVPlayer/PiP available; do not silently change backends for an effect.
  @override
  bool get supportsVolumeNormalization => false;

  @override
  Future<void> setVolumeNormalizationEnabled(bool enabled) async {
    if (enabled) {
      throw UnsupportedError('AVPlayer audio filtering is unavailable');
    }
  }

  @override
  Future<String?> readEmbeddedLyrics() async => _fallback?.readEmbeddedLyrics();

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0, 1);
    final fallback = _fallback;
    if (fallback != null) return fallback.setVolume(_volume);
    await _controller?.setVolume(_volume);
  }

  @override
  double get volume => _fallback?.volume ?? _volume;

  @override
  Future<void> setVideoTrackEnabled(bool enabled) async {
    if (_fallback case final fallback?) {
      await fallback.setVideoTrackEnabled(enabled);
    }
  }

  @override
  Future<void> setVideoOutputSize({int? width, int? height}) async {
    if (_fallback case final fallback?) {
      await fallback.setVideoOutputSize(width: width, height: height);
    }
  }

  @override
  bool get supportsPictureInPicture =>
      _controller?.value.isInitialized == true &&
      _controller?.value.size.width.round() != 0 &&
      _controller?.value.size.height.round() != 0;

  @override
  Future<bool> enterPictureInPicture() async {
    final controller = _controller;
    if (controller == null || !supportsPictureInPicture) return false;
    final size = controller.value.size;
    try {
      return await controller.enterPipMode(
        width: size.width.round().clamp(1, 4096),
        height: size.height.round().clamp(1, 4096),
      );
    } catch (_) {
      return false;
    }
  }

  @override
  Stream<Duration> get positionStream => _positions.stream;
  @override
  Stream<Duration> get durationStream => _durations.stream;
  @override
  Stream<bool> get playingStream => _playing.stream;
  @override
  Stream<void> get completedStream => _completed.stream;
  @override
  PlaybackSnapshot get snapshot => _fallback?.snapshot ?? _snapshot;
  @override
  Stream<PlaybackSnapshot> get snapshots => _snapshots.stream;
  @override
  double? get videoAspectRatio =>
      _fallback?.videoAspectRatio ??
      (_controller?.value.isInitialized == true
          ? _controller!.value.aspectRatio
          : null);

  @override
  Widget buildVideoView({Key? key, BoxFit fit = BoxFit.contain}) {
    final fallback = _fallback;
    if (fallback != null) return fallback.buildVideoView(key: key, fit: fit);
    final controller = _controller;
    if (controller == null) return SizedBox(key: key);
    return vp.VideoPlayer(controller, key: key);
  }

  @override
  Stream<dynamic> get events => snapshots;
  @override
  PlaybackSnapshot get last => snapshot;
  @override
  void Function()? get onEnded => _onEnded;
  @override
  set onEnded(void Function()? callback) {
    _onEnded = callback;
    _fallback?.onEnded = callback;
  }

  @override
  Future<void> dispose() async {
    await _disposeActive();
    await _snapshots.close();
    await _completed.close();
    await _positions.close();
    await _durations.close();
    await _playing.close();
  }

  @override
  Future<void> shutdown() => dispose();
}
