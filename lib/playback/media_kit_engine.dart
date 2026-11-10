import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/return_code.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'package:path_provider/path_provider.dart';
import 'ambient_colors.dart';
import 'playback_engine.dart';
import 'pip_artwork_movie.dart';

/// media_kit-backed engine. The ONLY place importing media_kit(_video).
/// Owns one mk.Player + lazily-created mkv.VideoController for the view.
/// yureru Queue stays outside: we open exactly one Media per load().
class MediaKitPlaybackEngine implements PlaybackEngine {
  static const _backgroundPlaybackChannel = MethodChannel(
    'yureru/media_picker',
  );
  static const _nativePipChannel = MethodChannel('yureru/native_pip');
  MediaKitPlaybackEngine() {
    _nativePipChannel.setMethodCallHandler(_handleNativePipCall);
  }

  mk.Player? _player;
  mkv.VideoController? _vc;
  PlaybackSource? _activeSource;
  PlaybackSnapshot _snap = const PlaybackSnapshot();
  final _snapCtrl = StreamController<PlaybackSnapshot>.broadcast();
  final _completedCtrl = StreamController<void>.broadcast();
  final _positions = StreamController<Duration>.broadcast();
  final _durations = StreamController<Duration>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  void Function()? _onEnded;
  bool _completedFired = false;
  bool _nativePipActive = false;
  bool _nativePipUsesWebKit = false;
  String? _pictureInPictureFailure;
  final List<StreamSubscription> _subs = [];
  double _rate = 1.0;
  double _volume = 1.0;
  bool _normalizationEnabled = false;
  int _timelineOffsetMs = 0;
  String? _lastPlayerError;
  final ValueNotifier<ui.Image?> _ambientMatteFrame = ValueNotifier(null);
  Future<ui.Image?> Function()? _ambientFrameSource;
  AmbientEdgeColors? _previousAmbientEdges;
  (Rect?, double, double, double)? _ambientGeometry;

  mk.Player _ensurePlayer() {
    final existing = _player;
    if (existing != null) return existing;
    final p = mk.Player();
    _player = p;
    p.setVolume(_volume * 100); // media_kit uses 0..100
    _subs.add(
      p.stream.log.listen((entry) {
        if (entry.level == 'error') {
          _lastPlayerError = entry.text;
          debugPrint('media_kit: ${entry.text}');
        }
      }),
    );
    _subs.add(
      p.stream.position.listen((d) {
        // While PiP is active, its native player owns time. Late mpv ticks
        // from the paused in-app player must not pull the displayed state
        // backward or make the transport control look stopped.
        if (_nativePipActive) return;
        final timelinePosition = _toTimelinePosition(d);
        _positions.add(timelinePosition);
        _snap = PlaybackSnapshot(
          position: timelinePosition,
          duration: _snap.duration,
          isPlaying: _snap.isPlaying,
          initialized: true,
          completed: false,
        );
        _snapCtrl.add(_snap);
        if (_nativePipActive) {
          unawaited(
            _nativePipChannel.invokeMethod<void>('updatePosition', {
              'position': d.inMicroseconds / Duration.microsecondsPerSecond,
              'duration':
                  _sourceDuration.inMicroseconds /
                  Duration.microsecondsPerSecond,
            }),
          );
        }
      }),
    );
    _subs.add(
      p.stream.duration.listen((d) {
        final timelineDuration = _toTimelineDuration(d);
        _durations.add(timelineDuration);
        _snap = PlaybackSnapshot(
          position: _snap.position,
          duration: timelineDuration,
          isPlaying: _snap.isPlaying,
          initialized: true,
          completed: false,
        );
        _snapCtrl.add(_snap);
      }),
    );
    _subs.add(
      p.stream.playing.listen((playing) {
        if (_nativePipActive) return;
        _playing.add(playing);
        _snap = PlaybackSnapshot(
          position: _snap.position,
          duration: _snap.duration,
          isPlaying: playing,
          initialized: _snap.initialized,
          completed: false,
        );
        _snapCtrl.add(_snap);
        if (_nativePipActive) {
          unawaited(
            _nativePipChannel.invokeMethod<void>('setPlaying', playing),
          );
        }
        unawaited(_setAndroidBackgroundPlayback(playing));
      }),
    );
    _subs.add(
      p.stream.completed.listen((done) {
        if (done == true) _fireCompleted();
      }),
    );
    return p;
  }

  Duration _toTimelinePosition(Duration sourcePosition) => Duration(
    milliseconds: (sourcePosition.inMilliseconds - _timelineOffsetMs).clamp(
      0,
      _timelineEndMs ?? (1 << 62),
    ),
  );

  int? get _timelineEndMs {
    final end = _activeSource?.end?.inMilliseconds;
    return end == null ? null : (end - _timelineOffsetMs).clamp(0, 1 << 62);
  }

  Duration get _timelineOffsetDuration =>
      Duration(milliseconds: _timelineOffsetMs);

  Duration get _sourcePosition => _snap.position + _timelineOffsetDuration;

  Duration get _sourceDuration => _snap.duration + _timelineOffsetDuration;

  Duration _toTimelineDuration(Duration sourceDuration) {
    final sourceEnd = _activeSource?.end?.inMilliseconds;
    final effectiveEnd = sourceEnd == null
        ? sourceDuration.inMilliseconds
        : sourceDuration.inMilliseconds.clamp(0, sourceEnd);
    return Duration(
      milliseconds: (effectiveEnd - _timelineOffsetMs).clamp(0, 1 << 62),
    );
  }

  void _fireCompleted() {
    if (_completedFired) return;
    _completedFired = true;
    _snap = PlaybackSnapshot(
      position: _snap.position,
      duration: _snap.duration,
      isPlaying: false,
      initialized: true,
      completed: true,
    );
    _snapCtrl.add(_snap);
    _completedCtrl.add(null);
    _onEnded?.call();
  }

  @override
  Future<void> load(PlaybackSource source, {bool autoplay = true}) async {
    final continueInNativePip = _nativePipActive;
    _activeSource = source;
    _timelineOffsetMs = source.timelineOffset.inMilliseconds;
    _completedFired = false;
    _previousAmbientEdges = null;
    _ambientGeometry = null;
    _replaceAmbientMatteFrame(null);
    final p = _ensurePlayer();
    await _enableHardwareDecoding(p);
    await _ensureVideoController(p);
    _snap = const PlaybackSnapshot(initialized: false);
    _snapCtrl.add(_snap);
    await p.open(
      mk.Media(source.uri, start: source.start, end: source.end),
      // Start normalized tracks only after the filter is attached, so the
      // first audio samples receive the same processing as the rest.
      play: autoplay && !_normalizationEnabled && !continueInNativePip,
    );
    if (_normalizationEnabled && !continueInNativePip) {
      final platform = p.platform;
      if (platform is mk.NativePlayer) {
        await _applyVolumeNormalization(platform, true);
      }
      if (autoplay) await p.play();
    }
    await _setAndroidBackgroundPlayback(autoplay && p.state.playing);
    if (_rate != 1.0) await p.setRate(_rate);
    _snap = PlaybackSnapshot(
      position: _toTimelinePosition(p.state.position),
      duration: _toTimelineDuration(p.state.duration),
      isPlaying: p.state.playing,
      initialized: true,
    );
    _snapCtrl.add(_snap);
    if (continueInNativePip) {
      String pipUri;
      if (source.pipArtworkPath != null) {
        try {
          final audioPath = _localPath(source.uri);
          final extension = audioPath.split('.').last.toLowerCase();
          pipUri = await PipArtworkMovie.prepare(
            mediaId: source.mediaId,
            artworkPath: source.pipArtworkPath!,
            audioPath: audioPath,
            trimEndMs: source.end?.inMilliseconds,
            forceAac: !const {
              'aac',
              'm4a',
              'mp4',
              'mov',
              'mp3',
            }.contains(extension),
          );
        } catch (_) {
          // If the next jacket cannot be prepared, keep the PiP session alive
          // on the source video/audio instead of failing the queue transition.
          pipUri =
              _nativePipUsesWebKit &&
                  _localPath(source.uri).toLowerCase().endsWith('.webm')
              ? source.uri
              : await _pictureInPictureSource(source);
        }
      } else {
        pipUri =
            _nativePipUsesWebKit &&
                _localPath(source.uri).toLowerCase().endsWith('.webm')
            ? source.uri
            : await _pictureInPictureSource(source);
      }
      final updated = await _nativePipChannel.invokeMethod<bool>('update', {
        'uri': pipUri,
        'playing': autoplay,
        'position':
            p.state.position.inMicroseconds / Duration.microsecondsPerSecond,
        'duration':
            p.state.duration.inMicroseconds / Duration.microsecondsPerSecond,
        'rate': _rate,
      });
      if (updated != true) {
        _nativePipActive = false;
        _nativePipUsesWebKit = false;
        if (autoplay) await p.play();
      }
    }
  }

  Future<void> _enableHardwareDecoding(mk.Player player) async {
    // Ask mpv to use a safe hardware decoder when the platform provides one.
    // `auto-safe` falls back to software decoding for unsupported codecs or
    // devices, so AV1 playback remains available without requiring hardware
    // AV1 support.
    final platform = player.platform;
    if (platform is mk.NativePlayer) {
      try {
        await platform.setProperty('hwdec', 'auto-safe');
      } catch (_) {
        // Hardware decoding is an optimization; software playback can proceed.
      }
    }
  }

  Future<void> _ensureVideoController(mk.Player player) async {
    final controller = _vc ??= mkv.VideoController(player);
    try {
      await controller.platform.future;
    } catch (_) {
      // Audio playback can still proceed if native video output is unavailable.
    }
  }

  @override
  bool get supportsVolumeNormalization => true;

  @override
  Future<void> setVolumeNormalizationEnabled(bool enabled) async {
    if (_normalizationEnabled == enabled) return;
    final player = _player;
    final platform = player?.platform;
    if (_activeSource != null) {
      if (platform is! mk.NativePlayer) {
        throw UnsupportedError('Native audio filtering is unavailable');
      }
      await _applyVolumeNormalization(platform, enabled);
    }
    _normalizationEnabled = enabled;
  }

  Future<void> _applyVolumeNormalization(
    mk.NativePlayer platform,
    bool enabled,
  ) async {
    _lastPlayerError = null;
    final filters = await platform.getProperty('af');
    final isApplied = filters.contains('yureru_normalize');
    if (isApplied == enabled) return;
    await platform.command(
      enabled
          ? [
              'af',
              'add',
              '@yureru_normalize:lavfi=[dynaudnorm=f=150:g=15:p=0.9:m=4:r=0.15]',
            ]
          : ['af', 'remove', '@yureru_normalize'],
    );
    final updatedFilters = await platform.getProperty('af');
    if (updatedFilters.contains('yureru_normalize') != enabled) {
      final playerError = _lastPlayerError;
      throw StateError(
        'Volume normalization filter was not added. '
        'Current filters: $updatedFilters'
        '${playerError == null ? '' : ' | mpv: $playerError'}',
      );
    }
  }

  @override
  Future<String?> readEmbeddedLyrics() async {
    final player = _player;
    if (player == null) return null;
    final platform = player.platform;
    if (platform is! mk.NativePlayer) return null;
    try {
      final count =
          int.tryParse(await platform.getProperty('metadata/list/count')) ?? 0;
      final tags = <String, String>{};
      for (var i = 0; i < count; i++) {
        final key = await platform.getProperty('metadata/list/$i/key');
        if (key.toLowerCase().contains('lyric')) {
          final normalizedKey = key.toLowerCase().replaceAll(
            RegExp(r'[^a-z]'),
            '',
          );
          tags[normalizedKey] = await platform.getProperty(
            'metadata/list/$i/value',
          );
        }
      }
      for (final preferred in const [
        'syncedlyrics',
        'synchronizedlyrics',
        'lyrics',
        'unsyncedlyrics',
      ]) {
        final value = tags[preferred];
        if (value?.trim().isNotEmpty == true) return value;
      }
      for (final value in tags.values) {
        if (value.trim().isNotEmpty) return value;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> open(String mediaId, String pathOrUrl) =>
      load(PlaybackSource(mediaId: mediaId, uri: pathOrUrl), autoplay: true);

  @override
  Future<void> play() async {
    if (_nativePipActive) {
      await _nativePipChannel.invokeMethod<void>('setPlaying', true);
      return;
    }
    await _ensurePlayer().play();
    await _setAndroidBackgroundPlayback(true);
  }

  @override
  Future<void> pause() async {
    if (_nativePipActive) {
      await _nativePipChannel.invokeMethod<void>('setPlaying', false);
      return;
    }
    await _ensurePlayer().pause();
    await _setAndroidBackgroundPlayback(false);
  }

  Future<void> _setAndroidBackgroundPlayback(bool playing) async {
    if (!Platform.isAndroid) return;
    try {
      await _backgroundPlaybackChannel.invokeMethod<void>(
        'setBackgroundPlayback',
        playing,
      );
    } catch (_) {
      // Foreground playback remains usable if the optional Android service
      // cannot be started (for example, on an older or restricted device).
    }
  }

  @override
  Future<void> seekTo(Duration pos) async {
    if (_nativePipActive) {
      await _nativePipChannel.invokeMethod<void>(
        'seekTo',
        (pos + _timelineOffsetDuration).inMicroseconds /
            Duration.microsecondsPerSecond,
      );
      return;
    }
    final sourceMs = pos.inMilliseconds + _timelineOffsetMs;
    final endMs = _activeSource?.end?.inMilliseconds;
    await _ensurePlayer().seek(
      Duration(
        milliseconds: endMs == null ? sourceMs : sourceMs.clamp(0, endMs),
      ),
    );
  }

  @override
  Future<void> setSpeed(double speed) async {
    _rate = speed;
    if (_nativePipActive) {
      await _nativePipChannel.invokeMethod<void>('setRate', {
        'rate': speed,
        'playing': _snap.isPlaying,
      });
      return;
    }
    await _ensurePlayer().setRate(speed);
  }

  @override
  Future<void> setPlaybackRate(double rate) => setSpeed(rate);

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    final p = _player;
    if (p != null) await p.setVolume(_volume * 100);
  }

  @override
  double get volume => _volume;

  @override
  Future<void> setVideoTrackEnabled(bool enabled) async {
    final p = _player;
    if (p != null) {
      // Toggle mpv video track: 'no' disables decoding, 'auto' selects default track
      await p.setVideoTrack(
        enabled ? mk.VideoTrack.auto() : mk.VideoTrack.no(),
      );
    }
  }

  @override
  Future<ui.Image?> captureAmbientFrame({
    Rect? aperture,
    double spread = 1,
    double depth = 1,
    double softness = 1,
  }) async {
    ui.Image? image;
    try {
      // media_kit's macOS screenshot API runs `screenshot-raw` against mpv
      // from a Dart worker. Crash reports show mpv aborting in its swscale
      // configuration path, so use Flutter's rendered surface capture instead
      // of risking a process-wide abort from an optional ambient effect.
      image = await _ambientFrameSource?.call();
      if (image == null) return null;
      final pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (pixels == null) return null;
      final sampled = sampleAmbientEdges(
        pixels.buffer.asUint8List(pixels.offsetInBytes, pixels.lengthInBytes),
        image.width,
        image.height,
      );
      final previous = _previousAmbientEdges;
      final smoothed = previous == null
          ? sampled
          : updateAmbientEdges(previous, sampled);
      final geometry = (aperture, spread, depth, softness);
      if (identical(previous, smoothed) && _ambientGeometry == geometry) {
        return null;
      }
      final frame = await renderAmbientGlow(
        smoothed,
        aperture: aperture,
        spread: spread,
        depth: depth,
        softness: softness,
        // This field is enlarged to the window and blurred by Flutter. A
        // 240×135 render keeps the gradients smooth while cutting per-frame
        // pixel work by about 44% compared with 320×180.
        renderWidth: 240,
        renderHeight: 135,
      );
      _previousAmbientEdges = smoothed;
      _ambientGeometry = geometry;
      // Ambient light belongs outside the rendered video only. Keep the
      // sampled frame out of the video texture so no picture or letterbox
      // pixels can be washed over by a foreground overlay.
      _replaceAmbientMatteFrame(null);
      return frame;
    } catch (_) {
      return null;
    } finally {
      image?.dispose();
    }
  }

  @override
  void setAmbientFrameSource(Future<ui.Image?> Function()? capture) {
    _ambientFrameSource = capture;
  }

  @override
  Future<void> setVideoOutputSize({int? width, int? height}) async {
    // media_kit_video does not support changing output dimensions on Android.
    // The system owns the output size for native mobile PiP as well.
    if (Platform.isAndroid || Platform.isIOS) return;
    final controller = _vc;
    if (controller == null) return;
    try {
      await controller.platform.future;
      await controller.setSize(width: width, height: height);
    } catch (_) {
      // Keep PiP usable if a renderer does not support output resizing.
    }
  }

  @override
  bool get supportsPictureInPicture {
    return Platform.isMacOS && _activeSource != null;
  }

  @override
  String? get pictureInPictureFailure => _pictureInPictureFailure;

  @override
  Future<bool> enterPictureInPicture({
    double? aspectRatio,
    String? artworkPath,
    Rect? sourceRect,
  }) async {
    // Starting PiP is idempotent. Do not turn an already-visible PiP window
    // off just because the toolbar action is invoked again.
    if (_nativePipActive) return true;
    if (_activeSource == null) return false;
    _pictureInPictureFailure = null;
    final wasPlaying = _snap.isPlaying;
    try {
      final source = _activeSource!;
      final sourcePath = _localPath(source.uri);
      final isWebM = sourcePath.toLowerCase().endsWith('.webm');
      if (artworkPath != null) {
        final audioExtension = sourcePath.split('.').last.toLowerCase();
        final forceAac = !const {
          'aac',
          'm4a',
          'mp4',
          'mov',
          'mp3',
        }.contains(audioExtension);
        var stillMovie = await PipArtworkMovie.prepare(
          mediaId: source.mediaId,
          artworkPath: artworkPath,
          audioPath: sourcePath,
          trimEndMs: source.end?.inMilliseconds,
          forceAac: forceAac,
        );
        if (wasPlaying) await pause();
        var started = await _startNativePip(
          stillMovie,
          wasPlaying,
          sourceRect: sourceRect,
        );
        if (!started && !forceAac) {
          stillMovie = await PipArtworkMovie.prepare(
            mediaId: source.mediaId,
            artworkPath: artworkPath,
            audioPath: sourcePath,
            trimEndMs: source.end?.inMilliseconds,
            forceAac: true,
          );
          started = await _startNativePip(
            stillMovie,
            wasPlaying,
            sourceRect: sourceRect,
          );
        }
        if (!started) {
          if (wasPlaying) await play();
          return false;
        }
        _nativePipActive = true;
        _nativePipUsesWebKit = false;
        return true;
      }
      if (isWebM) {
        final videoCodec = await _videoCodec(sourcePath);
        if (videoCodec == 'av1') {
          // AVPlayer cannot open the WebM container, but Apple Silicon with
          // AV1 hardware decode can play AV1 in MP4. Remux the video stream
          // without decoding/re-encoding it, converting only Opus audio to
          // AAC, then hand the compatible file to system PiP.
          final pipUri = await _pictureInPictureSource(source);
          if (wasPlaying) await pause();
          final started = await _startNativePip(
            pipUri,
            wasPlaying,
            sourceRect: sourceRect,
          );
          if (started) {
            _nativePipActive = true;
            _nativePipUsesWebKit = false;
            return true;
          }
          // Older Macs without AV1 hardware decode may still play the source
          // through WebKit. Try that route without starting a long transcode.
          final webKitStarted = await _startWebKitPip(source, wasPlaying);
          if (webKitStarted) {
            _nativePipActive = true;
            _nativePipUsesWebKit = true;
            return true;
          }
          if (wasPlaying) await play();
          return false;
        }

        // Start the original WebM in the system WebKit PiP player first. A
        // full-file transcode can take a minute and must never block the
        // user's PiP button. Use a prior conversion only as a fast fallback.
        final started = await _startWebKitPip(source, wasPlaying);
        if (started) {
          _nativePipActive = true;
          _nativePipUsesWebKit = true;
          return true;
        }
        final cached = await _cachedPictureInPictureSource(source);
        if (cached == null) {
          if (wasPlaying) await play();
          return false;
        }
        if (wasPlaying) await pause();
        final startedCached = await _startNativePip(
          cached,
          wasPlaying,
          sourceRect: sourceRect,
        );
        if (!startedCached && wasPlaying) await play();
        if (startedCached) _nativePipActive = true;
        return startedCached;
      }

      var pipUri = await _pictureInPictureSource(source);
      if (wasPlaying) await pause();
      var started = await _startNativePip(
        pipUri,
        wasPlaying,
        sourceRect: sourceRect,
      );
      if (!started && Platform.isMacOS) {
        final converted = await _pictureInPictureSource(source, force: true);
        if (converted != pipUri) {
          pipUri = converted;
          if (wasPlaying) await pause();
          started = await _startNativePip(
            pipUri,
            wasPlaying,
            sourceRect: sourceRect,
          );
        }
      }
      if (!started) {
        if (wasPlaying) await play();
        return false;
      }
      _nativePipActive = true;
      _nativePipUsesWebKit = false;
      return true;
    } catch (error) {
      _pictureInPictureFailure = error.toString();
      if (wasPlaying) await play();
      return false;
    }
  }

  String _localPath(String uri) {
    final parsed = Uri.tryParse(uri);
    return parsed?.scheme == 'file' ? parsed!.toFilePath() : uri;
  }

  Future<bool> _startNativePip(
    String uri,
    bool playing, {
    Rect? sourceRect,
  }) async {
    final sourceRectMap = sourceRect == null
        ? null
        : <String, double>{
            'left': sourceRect.left,
            'top': sourceRect.top,
            'width': sourceRect.width,
            'height': sourceRect.height,
          };
    final started =
        await _nativePipChannel.invokeMethod<bool>('start', {
          'playing': playing,
          'uri': uri,
          'position':
              _sourcePosition.inMicroseconds / Duration.microsecondsPerSecond,
          'duration':
              _sourceDuration.inMicroseconds / Duration.microsecondsPerSecond,
          'rate': _rate,
          if (sourceRectMap != null) 'sourceRect': sourceRectMap,
        }) ??
        false;
    if (!started) {
      _pictureInPictureFailure = await _nativePipChannel.invokeMethod<String>(
        'lastStartFailure',
      );
    }
    return started;
  }

  Future<bool> _startWebKitPip(PlaybackSource source, bool playing) async {
    if (playing) await pause();
    return await _nativePipChannel.invokeMethod<bool>('startWebKit', {
          'uri': source.uri,
          'playing': playing,
          'position':
              _sourcePosition.inMicroseconds / Duration.microsecondsPerSecond,
          'duration':
              _sourceDuration.inMicroseconds / Duration.microsecondsPerSecond,
          'rate': _rate,
        }) ??
        false;
  }

  Future<String?> _videoCodec(String path) async {
    final session = await FFprobeKit.executeWithArguments([
      '-v',
      'error',
      '-select_streams',
      'v:0',
      '-show_entries',
      'stream=codec_name',
      '-of',
      'default=noprint_wrappers=1:nokey=1',
      path,
    ]);
    if (!ReturnCode.isSuccess(await session.getReturnCode())) return null;
    return (await session.getOutput())?.trim().split(RegExp(r'\r?\n')).first;
  }

  Future<String?> _cachedPictureInPictureSource(PlaybackSource source) async {
    if (!Platform.isMacOS) return null;
    final sourcePath = _localPath(source.uri);
    final input = File(sourcePath);
    if (!await input.exists()) return null;
    final stat = await input.stat();
    final cacheDir = Directory(
      '${(await getTemporaryDirectory()).path}/yureru_pip',
    );
    final safeId = source.mediaId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    for (final suffix in ['_av1.mp4', '_vtp.mp4', '_vt.mp4']) {
      final candidate = File(
        '${cacheDir.path}/${safeId}_${stat.size}_${stat.modified.millisecondsSinceEpoch}$suffix',
      );
      final valid = suffix == '_av1.mp4'
          ? await _isValidAv1PipMp4(candidate)
          : await _isValidPipMp4(candidate);
      if (valid) return candidate.path;
    }
    return null;
  }

  Future<String> _pictureInPictureSource(
    PlaybackSource source, {
    bool force = false,
  }) async {
    if (!Platform.isMacOS) return source.uri;
    final uri = Uri.tryParse(source.uri);
    final sourcePath = uri?.scheme == 'file' ? uri!.toFilePath() : source.uri;
    if (!force && !sourcePath.toLowerCase().endsWith('.webm')) {
      return source.uri;
    }

    final input = File(sourcePath);
    if (!await input.exists()) return source.uri;
    final stat = await input.stat();
    final remuxAv1 =
        !force &&
        sourcePath.toLowerCase().endsWith('.webm') &&
        await _videoCodec(sourcePath) == 'av1';
    final cacheDir = Directory(
      '${(await getTemporaryDirectory()).path}/yureru_pip',
    );
    await cacheDir.create(recursive: true);
    final safeId = source.mediaId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final outputSuffix = remuxAv1 ? '_av1.mp4' : '_vtp.mp4';
    final output = File(
      '${cacheDir.path}/${safeId}_${stat.size}_${stat.modified.millisecondsSinceEpoch}$outputSuffix',
    );
    final validOutput = remuxAv1
        ? await _isValidAv1PipMp4(output)
        : await _isValidPipMp4(output);
    if (validOutput) return output.path;
    if (await output.exists()) await output.delete();

    // Never let AVPlayer see an MP4 while FFmpeg is still writing it. A
    // partially written MP4 can contain megabytes of media data but no moov
    // index, and is otherwise easy to mistake for a completed conversion.
    final temporaryOutput = File(
      '${cacheDir.path}/${safeId}_${stat.size}_${stat.modified.millisecondsSinceEpoch}$outputSuffix.partial.mp4',
    );
    if (await temporaryOutput.exists()) await temporaryOutput.delete();

    final arguments = remuxAv1
        ? <String>[
            '-hide_banner',
            '-y',
            '-i',
            sourcePath,
            '-map',
            '0:v:0',
            '-map',
            '0:a:0?',
            '-sn',
            '-dn',
            '-c:v',
            'copy',
            '-tag:v',
            'av01',
            '-c:a',
            'aac',
            '-b:a',
            '192k',
            '-movflags',
            '+faststart',
            temporaryOutput.path,
          ]
        : <String>[
            '-hide_banner',
            '-y',
            '-i',
            sourcePath,
            '-map',
            '0:v:0',
            '-map',
            '0:a:0?',
            '-sn',
            '-dn',
            '-vf',
            'scale=w=1280:h=1280:force_original_aspect_ratio=decrease:force_divisible_by=2',
            '-fps_mode',
            'passthrough',
            '-c:v',
            'h264_videotoolbox',
            '-b:v',
            '1800k',
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
            temporaryOutput.path,
          ];
    final session = await FFmpegKit.executeWithArguments(arguments);
    if (!ReturnCode.isSuccess(await session.getReturnCode()) ||
        !(remuxAv1
            ? await _isValidAv1PipMp4(temporaryOutput)
            : await _isValidPipMp4(temporaryOutput))) {
      try {
        await temporaryOutput.delete();
      } catch (_) {}
      throw StateError('Could not prepare this video for macOS system PiP.');
    }

    await temporaryOutput.rename(output.path);
    return output.path;
  }

  Future<bool> _isValidPipMp4(File file) async {
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

  Future<bool> _isValidAv1PipMp4(File file) async {
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
        output.split(RegExp(r'\r?\n')).any((line) => line.trim() == 'av1,av01');
  }

  Future<dynamic> _handleNativePipCall(MethodCall call) async {
    switch (call.method) {
      case 'playRequested':
        await play();
        break;
      case 'pauseRequested':
        await pause();
        break;
      case 'seekRequested':
        final seconds = (call.arguments as num?)?.toDouble();
        if (seconds != null && seconds.isFinite) {
          final current =
              _sourcePosition.inMicroseconds / Duration.microsecondsPerSecond;
          final duration =
              _sourceDuration.inMicroseconds / Duration.microsecondsPerSecond;
          final target = (current + seconds).clamp(
            0.0,
            duration > 0 ? duration : double.infinity,
          );
          await _ensurePlayer().seek(
            Duration(
              microseconds: (target * Duration.microsecondsPerSecond).round(),
            ),
          );
        }
        break;
      case 'stopped':
        _nativePipActive = false;
        _nativePipUsesWebKit = false;
        final state = call.arguments is Map
            ? Map<String, dynamic>.from(call.arguments as Map)
            : const <String, dynamic>{};
        final position = (state['position'] as num?)?.toDouble();
        if (position != null && position.isFinite) {
          await _ensurePlayer().seek(
            Duration(
              microseconds: (position * Duration.microsecondsPerSecond).round(),
            ),
          );
        }
        if (state['playing'] == true) await _ensurePlayer().play();
        break;
      case 'completed':
        _fireCompleted();
        break;
      case 'positionUpdated':
        final state = call.arguments is Map
            ? Map<String, dynamic>.from(call.arguments as Map)
            : const <String, dynamic>{};
        final seconds = (state['position'] as num?)?.toDouble();
        if (seconds != null && seconds.isFinite) {
          final position = Duration(
            microseconds: (seconds * Duration.microsecondsPerSecond).round(),
          );
          final durationSeconds = (state['duration'] as num?)?.toDouble();
          final duration = durationSeconds != null && durationSeconds.isFinite
              ? Duration(
                  microseconds:
                      (durationSeconds * Duration.microsecondsPerSecond)
                          .round(),
                )
              : _snap.duration;
          _positions.add(position);
          _playing.add(state['playing'] == true);
          _snap = PlaybackSnapshot(
            position: position,
            duration: duration,
            isPlaying: state['playing'] == true,
            initialized: true,
          );
          _snapCtrl.add(_snap);
        }
        break;
      case 'playbackStateChanged':
        // The native PiP surface is the active audio/video player. Starting
        // the in-app player here would play the same track a second time.
        final playing = call.arguments == true;
        _playing.add(playing);
        _snap = PlaybackSnapshot(
          position: _snap.position,
          duration: _snap.duration,
          isPlaying: playing,
          initialized: true,
          completed: false,
        );
        _snapCtrl.add(_snap);
        break;
    }
    return null;
  }

  @override
  Stream<Duration> get positionStream => _positions.stream;
  @override
  Stream<Duration> get durationStream => _durations.stream;
  @override
  Stream<bool> get playingStream => _playing.stream;
  @override
  Stream<void> get completedStream => _completedCtrl.stream;
  @override
  PlaybackSnapshot get snapshot => _snap;
  @override
  Stream<PlaybackSnapshot> get snapshots => _snapCtrl.stream;
  @override
  double? get videoAspectRatio {
    final state = _player?.state;
    // `aspect` is already the display aspect ratio. Applying the demuxer's
    // rotation again turns landscape sources into portrait PiP windows even
    // though media_kit_video still renders them landscape.
    final displayAspect = state?.videoParams.aspect;
    if (displayAspect != null && displayAspect.isFinite && displayAspect > 0) {
      return displayAspect;
    }
    final width = state?.width;
    final height = state?.height;
    if (width != null && height != null && width > 0 && height > 0) {
      return width / height;
    }
    return null;
  }

  @override
  ValueListenable<ui.Image?> get ambientMatteFrameListenable =>
      _ambientMatteFrame;

  void _replaceAmbientMatteFrame(ui.Image? image) {
    final previous = _ambientMatteFrame.value;
    if (identical(previous, image)) return;
    _ambientMatteFrame.value = image;
    if (previous != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
  }

  @override
  Widget buildVideoView({Key? key, BoxFit fit = BoxFit.contain}) {
    final p = _ensurePlayer();
    _vc ??= mkv.VideoController(p);
    return mkv.Video(
      key: key,
      controller: _vc!,
      fit: fit,
      controls: mkv.NoVideoControls,
    );
  }

  @override
  Stream<dynamic> get events => snapshots;
  @override
  PlaybackSnapshot get last => snapshot;
  @override
  void Function()? get onEnded => _onEnded;
  @override
  set onEnded(void Function()? cb) => _onEnded = cb;

  @override
  Future<void> dispose() async {
    if (_nativePipActive) {
      _nativePipActive = false;
      try {
        await _nativePipChannel.invokeMethod<void>('stop');
      } catch (_) {
        // App shutdown must still release the normal playback engine.
      }
    }
    await _setAndroidBackgroundPlayback(false);
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _player?.dispose();
    _player = null;
    _vc = null;
    _replaceAmbientMatteFrame(null);
    // NOTE: snapshot/completed controllers stay open — the engine lives as a
    // singleton via provider for the whole app lifetime. Closing them here
    // would break any later load() with "add after close".
  }

  @override
  Future<void> shutdown() => dispose();
}
