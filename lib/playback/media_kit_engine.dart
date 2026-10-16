import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'playback_engine.dart';

/// media_kit-backed engine. The ONLY place importing media_kit(_video).
/// Owns one mk.Player + lazily-created mkv.VideoController for the view.
/// yureru Queue stays outside: we open exactly one Media per load().
class MediaKitPlaybackEngine implements PlaybackEngine {
  mk.Player? _player;
  mkv.VideoController? _vc;
  PlaybackSnapshot _snap = const PlaybackSnapshot();
  final _snapCtrl = StreamController<PlaybackSnapshot>.broadcast();
  final _completedCtrl = StreamController<void>.broadcast();
  void Function()? _onEnded;
  bool _completedFired = false;
  final List<StreamSubscription> _subs = [];
  double _rate = 1.0;
  double _volume = 1.0;

  mk.Player _ensurePlayer() {
    final existing = _player;
    if (existing != null) return existing;
    final p = mk.Player();
    _player = p;
    p.setVolume(_volume * 100); // media_kit uses 0..100
    _subs.add(
      p.stream.position.listen((d) {
        _snap = PlaybackSnapshot(
          position: d,
          duration: _snap.duration,
          isPlaying: _snap.isPlaying,
          initialized: true,
          completed: false,
        );
        _snapCtrl.add(_snap);
      }),
    );
    _subs.add(
      p.stream.duration.listen((d) {
        _snap = PlaybackSnapshot(
          position: _snap.position,
          duration: d,
          isPlaying: _snap.isPlaying,
          initialized: true,
          completed: false,
        );
        _snapCtrl.add(_snap);
      }),
    );
    _subs.add(
      p.stream.playing.listen((playing) {
        _snap = PlaybackSnapshot(
          position: _snap.position,
          duration: _snap.duration,
          isPlaying: playing,
          initialized: _snap.initialized,
          completed: false,
        );
        _snapCtrl.add(_snap);
      }),
    );
    _subs.add(
      p.stream.completed.listen((done) {
        if (done == true) _fireCompleted();
      }),
    );
    return p;
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
    _completedFired = false;
    final p = _ensurePlayer();
    await _enableHardwareDecoding(p);
    await _ensureVideoController(p);
    _snap = const PlaybackSnapshot(initialized: false);
    _snapCtrl.add(_snap);
    await p.open(
      mk.Media(source.uri, start: source.start, end: source.end),
      play: autoplay,
    );
    if (_rate != 1.0) await p.setRate(_rate);
    _snap = PlaybackSnapshot(
      position: p.state.position,
      duration: p.state.duration,
      isPlaying: p.state.playing,
      initialized: true,
    );
    _snapCtrl.add(_snap);
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
  Future<void> open(String mediaId, String pathOrUrl) =>
      load(PlaybackSource(mediaId: mediaId, uri: pathOrUrl), autoplay: true);

  @override
  Future<void> play() async => _ensurePlayer().play();
  @override
  Future<void> pause() async => _ensurePlayer().pause();
  @override
  Future<void> seekTo(Duration pos) async => _ensurePlayer().seek(pos);
  @override
  Future<void> setSpeed(double speed) async {
    _rate = speed;
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
  Stream<Duration> get positionStream =>
      _player?.stream.position ?? const Stream.empty();
  @override
  Stream<Duration> get durationStream =>
      _player?.stream.duration ?? const Stream.empty();
  @override
  Stream<bool> get playingStream =>
      _player?.stream.playing ?? const Stream.empty();
  @override
  Stream<void> get completedStream => _completedCtrl.stream;
  @override
  PlaybackSnapshot get snapshot => _snap;
  @override
  Stream<PlaybackSnapshot> get snapshots => _snapCtrl.stream;
  @override
  double? get videoAspectRatio {
    final state = _player?.state;
    final width = state?.width;
    final height = state?.height;
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    return width / height;
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
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _player?.dispose();
    _player = null;
    _vc = null;
    // NOTE: snapshot/completed controllers stay open — the engine lives as a
    // singleton via provider for the whole app lifetime. Closing them here
    // would break any later load() with "add after close".
  }

  @override
  Future<void> shutdown() => dispose();
}
