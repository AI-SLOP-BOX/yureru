import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/return_code.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player_pip/index.dart' as vp;

import 'media_kit_engine.dart';
import 'playback_engine.dart';
import 'pip_artwork_movie.dart';

/// Uses AVPlayer/AVPlayerLayer on iOS so the system can take over the layer
/// for PiP. Sources AVPlayer cannot open fall back to media_kit; local WebM
/// sources are converted to a cached H.264 file only when PiP is requested.
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
  bool _normalizationEnabled = false;
  int _sourceEpoch = 0;
  int _timelineOffsetMs = 0;
  String? _pictureInPictureFailure;
  double _volume = 1;
  double _speed = 1;
  Future<ui.Image?> Function()? _ambientFrameSource;

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
    _sourceEpoch++;
    await _disposeActive();
    _switchingToFallback = false;
    _activeSource = source;
    _timelineOffsetMs = source.timelineOffset.inMilliseconds;
    _didComplete = false;
    _endAt = source.end;
    _snapshot = const PlaybackSnapshot();
    _snapshots.add(_snapshot);

    if (_normalizationEnabled || !_isAvFoundationCandidate(source.uri)) {
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
    await fallback.setVolumeNormalizationEnabled(_normalizationEnabled);
    fallback.setAmbientFrameSource(_ambientFrameSource);
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
        position: _toTimelinePosition(endAt),
        duration: _toTimelineDuration(value.duration),
        isPlaying: false,
        initialized: true,
        completed: true,
      );
      _snapshots.add(_snapshot);
      _positions.add(_toTimelinePosition(endAt));
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
      position: _toTimelinePosition(value.position),
      duration: _toTimelineDuration(value.duration),
      isPlaying: value.isPlaying,
      initialized: value.isInitialized,
      completed: value.isCompleted,
    );
    _snapshots.add(_snapshot);
    _positions.add(_toTimelinePosition(value.position));
    _durations.add(_toTimelineDuration(value.duration));
    _playing.add(value.isPlaying);
  }

  Duration _toTimelinePosition(Duration sourcePosition) => Duration(
    milliseconds: (sourcePosition.inMilliseconds - _timelineOffsetMs).clamp(
      0,
      _activeSource?.end == null
          ? (1 << 62)
          : (_activeSource!.end!.inMilliseconds - _timelineOffsetMs).clamp(
              0,
              1 << 62,
            ),
    ),
  );

  Duration _toTimelineDuration(Duration sourceDuration) {
    final end = _activeSource?.end?.inMilliseconds;
    final effectiveEnd = end == null
        ? sourceDuration.inMilliseconds
        : sourceDuration.inMilliseconds.clamp(0, end);
    return Duration(
      milliseconds: (effectiveEnd - _timelineOffsetMs).clamp(0, 1 << 62),
    );
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
      timelineOffset: source.timelineOffset,
      pipArtworkPath: source.pipArtworkPath,
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
    final sourceMs = position.inMilliseconds + _timelineOffsetMs;
    final endMs = _activeSource?.end?.inMilliseconds;
    await _controller?.seekTo(
      Duration(
        milliseconds: endMs == null ? sourceMs : sourceMs.clamp(0, endMs),
      ),
    );
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
    _ambientFrameSource = capture;
    _fallback?.setAmbientFrameSource(capture);
  }

  @override
  ValueListenable<ui.Image?>? get ambientMatteFrameListenable =>
      _fallback?.ambientMatteFrameListenable;

  // AVPlayer has no dynamic-normalization hook. Use the existing media_kit
  // fallback while the feature is enabled; normal iOS playback remains on
  // AVPlayer when the feature is off.
  @override
  bool get supportsVolumeNormalization => true;

  @override
  Future<void> setVolumeNormalizationEnabled(bool enabled) async {
    if (_normalizationEnabled == enabled) return;
    final fallback = _fallback;
    if (fallback != null) {
      await fallback.setVolumeNormalizationEnabled(enabled);
      _normalizationEnabled = enabled;
      return;
    }
    _normalizationEnabled = enabled;
    final controller = _controller;
    if (enabled && controller != null) {
      await _switchToMediaKit(controller);
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
      (_controller?.value.isInitialized == true &&
          _controller?.value.size.width.round() != 0 &&
          _controller?.value.size.height.round() != 0) ||
      (_fallback != null && _isLocalWebM(_activeSource?.uri));

  @override
  String? get pictureInPictureFailure => _pictureInPictureFailure;

  @override
  Future<bool> enterPictureInPicture({
    double? aspectRatio,
    String? artworkPath,
    Rect? sourceRect,
  }) async {
    _pictureInPictureFailure = null;
    if (artworkPath != null) {
      try {
        await _switchArtworkToAvPlayer(artworkPath, _sourceEpoch);
      } catch (error) {
        _pictureInPictureFailure = error.toString();
        return false;
      }
    }
    if (_controller == null && _fallback != null) {
      final source = _activeSource;
      if (source == null || !_isLocalWebM(source.uri)) return false;
      try {
        await _switchWebMToAvPlayer(source, _sourceEpoch);
      } catch (error) {
        _pictureInPictureFailure = error.toString();
        return false;
      }
    }
    final controller = _controller;
    if (controller == null || !supportsPictureInPicture) return false;
    final size = controller.value.size;
    try {
      // The PiP plugin locates the native AVPlayerLayer from the currently
      // attached VideoPlayer widget, so let Flutter attach the replacement
      // WebM-compatible controller before asking AVKit to take it over.
      await WidgetsBinding.instance.endOfFrame;
      final started = await controller.enterPipMode(
        width: size.width.round().clamp(1, 4096),
        height: size.height.round().clamp(1, 4096),
      );
      if (!started) _pictureInPictureFailure = 'iOS did not start system PiP.';
      return started;
    } catch (error) {
      _pictureInPictureFailure = 'iOS could not start system PiP: $error';
      return false;
    }
  }

  Future<void> _switchArtworkToAvPlayer(
    String artworkPath,
    int sourceEpoch,
  ) async {
    final source = _activeSource;
    if (source == null) {
      throw StateError('No active audio is available for PiP.');
    }
    final parsed = Uri.tryParse(source.uri);
    final audioPath = parsed?.scheme == 'file'
        ? parsed!.toFilePath()
        : source.uri;
    final audioFile = File(audioPath);
    if (!await audioFile.exists()) {
      throw StateError('The active audio file is unavailable for PiP.');
    }
    final extension = audioPath.split('.').last.toLowerCase();
    final moviePath = await PipArtworkMovie.prepare(
      mediaId: source.mediaId,
      artworkPath: artworkPath,
      audioPath: audioPath,
      trimEndMs: source.end?.inMilliseconds,
      forceAac: !const {'aac', 'm4a', 'mp4', 'mov', 'mp3'}.contains(extension),
    );
    if (sourceEpoch != _sourceEpoch || !identical(source, _activeSource)) {
      throw StateError('The current track changed before PiP was ready.');
    }
    final fallback = _fallback;
    final oldController = _controller;
    final current = fallback?.snapshot ?? snapshot;
    final wasPlaying = current.isPlaying;
    final controller = vp.VideoPlayerController.file(
      File(moviePath),
      videoPlayerOptions: vp.VideoPlayerOptions(allowBackgroundPlayback: true),
    );
    try {
      await controller.initialize();
      await controller.setVolume(_volume);
      await controller.setPlaybackSpeed(_speed);
      await controller.seekTo(
        Duration(
          milliseconds:
              current.position.inMilliseconds +
              source.timelineOffset.inMilliseconds,
        ),
      );
      await fallback?.pause();
      await oldController?.pause();
      if (oldController != null) {
        oldController.removeListener(_onVideoPlayerChanged);
      }
      _controller = controller;
      controller.addListener(_onVideoPlayerChanged);
      _activeSource = PlaybackSource(
        mediaId: source.mediaId,
        uri: moviePath,
        start: source.start,
        end: source.end,
        timelineOffset: source.timelineOffset,
        pipArtworkPath: source.pipArtworkPath,
      );
      if (fallback != null) {
        for (final subscription in _fallbackSubscriptions) {
          await subscription.cancel();
        }
        _fallbackSubscriptions.clear();
        _fallback = null;
        await fallback.dispose();
      }
      await oldController?.dispose();
      if (wasPlaying) await controller.play();
      _onVideoPlayerChanged();
      // Let the hidden VideoPlayer surface attach its AVPlayerLayer before
      // the PiP plugin locates it.
      await WidgetsBinding.instance.endOfFrame;
    } catch (_) {
      await controller.dispose();
      rethrow;
    }
  }

  bool _isLocalWebM(String? uri) {
    if (uri == null) return false;
    final parsed = Uri.tryParse(uri);
    final path = parsed?.scheme == 'file' ? parsed!.toFilePath() : uri;
    return (parsed == null ||
            parsed.scheme.isEmpty ||
            parsed.scheme == 'file') &&
        path.toLowerCase().endsWith('.webm');
  }

  Future<void> _switchWebMToAvPlayer(
    PlaybackSource source,
    int sourceEpoch,
  ) async {
    final fallback = _fallback;
    if (fallback == null) return;
    // Let the current WebM keep playing while the PiP-compatible copy is
    // prepared, then transfer at the latest playback position.
    final convertedPath = await _prepareWebMForAvPlayer(source);
    if (sourceEpoch != _sourceEpoch || !identical(fallback, _fallback)) {
      throw StateError('The current video changed before PiP was ready.');
    }
    final current = fallback.snapshot;
    final file = Uri.tryParse(convertedPath)?.toFilePath() ?? convertedPath;
    final controller = vp.VideoPlayerController.file(
      File(file),
      videoPlayerOptions: vp.VideoPlayerOptions(allowBackgroundPlayback: true),
    );
    try {
      await controller.initialize();
      await controller.setVolume(_volume);
      await controller.setPlaybackSpeed(_speed);
      await controller.seekTo(
        Duration(
          milliseconds:
              current.position.inMilliseconds +
              source.timelineOffset.inMilliseconds,
        ),
      );
      await fallback.pause();
      _controller = controller;
      controller.addListener(_onVideoPlayerChanged);
      for (final subscription in _fallbackSubscriptions) {
        await subscription.cancel();
      }
      _fallbackSubscriptions.clear();
      _fallback = null;
      await fallback.dispose();
      _activeSource = PlaybackSource(
        mediaId: source.mediaId,
        uri: convertedPath,
        start: source.start,
        end: source.end,
        timelineOffset: source.timelineOffset,
        pipArtworkPath: source.pipArtworkPath,
      );
      if (current.isPlaying) await controller.play();
      _onVideoPlayerChanged();
    } catch (_) {
      await controller.dispose();
      rethrow;
    }
  }

  Future<String> _prepareWebMForAvPlayer(PlaybackSource source) async {
    final parsed = Uri.tryParse(source.uri);
    final inputPath = parsed?.scheme == 'file'
        ? parsed!.toFilePath()
        : source.uri;
    final input = File(inputPath);
    if (!await input.exists()) {
      throw StateError('The WebM source file is unavailable for iOS PiP.');
    }
    final stat = await input.stat();
    final cacheDir = Directory(
      '${(await getTemporaryDirectory()).path}/yureru_pip',
    );
    await cacheDir.create(recursive: true);
    final safeId = source.mediaId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final baseName =
        '${safeId}_${stat.size}_${stat.modified.millisecondsSinceEpoch}_ios';
    final output = File('${cacheDir.path}/$baseName.mp4');
    if (await _isAvPlayerMp4(output)) return output.path;
    if (await output.exists()) await output.delete();
    final partial = File('${output.path}.partial.mp4');
    if (await partial.exists()) await partial.delete();

    final session = await FFmpegKit.executeWithArguments([
      '-hide_banner',
      '-y',
      '-i',
      inputPath,
      '-map',
      '0:v:0',
      '-map',
      '0:a:0?',
      '-sn',
      '-dn',
      '-vf',
      'scale=w=1920:h=1920:force_original_aspect_ratio=decrease:force_divisible_by=2',
      '-fps_mode',
      'passthrough',
      '-c:v',
      'h264_videotoolbox',
      '-b:v',
      '3000k',
      '-tag:v',
      'avc1',
      '-pix_fmt',
      'yuv420p',
      '-c:a',
      'aac',
      '-b:a',
      '192k',
      '-movflags',
      '+faststart',
      partial.path,
    ]);
    if (!ReturnCode.isSuccess(await session.getReturnCode()) ||
        !await _isAvPlayerMp4(partial)) {
      if (await partial.exists()) await partial.delete();
      throw StateError('Could not prepare this WebM video for iOS system PiP.');
    }
    await partial.rename(output.path);
    return output.path;
  }

  Future<bool> _isAvPlayerMp4(File file) async {
    if (!await file.exists() || await file.length() == 0) return false;
    final session = await FFprobeKit.executeWithArguments([
      '-v',
      'error',
      '-select_streams',
      'v:0',
      '-show_entries',
      'stream=codec_name,codec_tag_string',
      '-of',
      'csv=p=0',
      file.path,
    ]);
    final output = (await session.getOutput())?.trim() ?? '';
    return ReturnCode.isSuccess(await session.getReturnCode()) &&
        output
            .split(RegExp(r'\r?\n'))
            .any((line) => line.trim() == 'h264,avc1');
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
    _sourceEpoch++;
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
