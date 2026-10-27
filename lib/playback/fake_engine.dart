import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'playback_engine.dart';

/// Test double: no media_kit involved. Drives controller logic unit tests.
class FakePlaybackEngine implements PlaybackEngine {
  PlaybackSource? loaded;
  int playCalls = 0, pauseCalls = 0;
  List<Duration> seeks = [];
  List<double> rates = [];
  double vol = 1.0;
  PlaybackSnapshot snap = const PlaybackSnapshot(
    position: Duration.zero,
    duration: Duration(seconds: 100),
    isPlaying: false,
    initialized: true,
  );
  final _completed = StreamController<void>.broadcast();
  void Function()? _onEnded;
  bool disposed = false;

  void emitCompleted() {
    snap = PlaybackSnapshot(
      position: snap.position,
      duration: snap.duration,
      isPlaying: false,
      initialized: true,
      completed: true,
    );
    _completed.add(null);
    _onEnded?.call();
  }

  @override
  Future<void> load(PlaybackSource s, {bool autoplay = true}) async {
    loaded = s;
    snap = PlaybackSnapshot(
      position: Duration.zero,
      duration: snap.duration,
      isPlaying: autoplay,
      initialized: true,
    );
  }

  @override
  Future<void> open(String id, String uri) =>
      load(PlaybackSource(mediaId: id, uri: uri));
  @override
  Future<void> play() async {
    playCalls++;
    snap = PlaybackSnapshot(
      position: snap.position,
      duration: snap.duration,
      isPlaying: true,
      initialized: true,
    );
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    snap = PlaybackSnapshot(
      position: snap.position,
      duration: snap.duration,
      isPlaying: false,
      initialized: true,
    );
  }

  @override
  Future<void> seekTo(Duration p) async {
    seeks.add(p);
    snap = PlaybackSnapshot(
      position: p,
      duration: snap.duration,
      isPlaying: snap.isPlaying,
      initialized: true,
    );
  }

  @override
  Future<void> setSpeed(double s) async {
    rates.add(s);
  }

  @override
  Future<void> setPlaybackRate(double r) => setSpeed(r);
  @override
  Future<ui.Image?> captureAmbientFrame({
    Rect? aperture,
    double spread = 1,
    double depth = 1,
    double softness = 1,
  }) async => null;

  @override
  void setAmbientFrameSource(Future<ui.Image?> Function()? capture) {}

  @override
  ValueListenable<ui.Image?>? get ambientMatteFrameListenable => null;
  @override
  Future<String?> readEmbeddedLyrics() async => null;
  @override
  Future<void> setVolume(double v) async {
    vol = v.clamp(0.0, 1.0);
  }

  @override
  double get volume => vol;
  bool normalizationEnabled = false;
  @override
  bool get supportsVolumeNormalization => true;
  @override
  Future<void> setVolumeNormalizationEnabled(bool enabled) async {
    normalizationEnabled = enabled;
  }

  bool videoTrackEnabled = true;
  @override
  Future<void> setVideoTrackEnabled(bool enabled) async {
    videoTrackEnabled = enabled;
  }

  @override
  Future<void> setVideoOutputSize({int? width, int? height}) async {}

  @override
  bool get supportsPictureInPicture => false;

  @override
  Future<bool> enterPictureInPicture() async => false;

  @override
  Stream<Duration> get positionStream => Stream.value(snap.position);
  @override
  Stream<Duration> get durationStream => Stream.value(snap.duration);
  @override
  Stream<bool> get playingStream => Stream.value(snap.isPlaying);
  @override
  Stream<void> get completedStream => _completed.stream;
  @override
  PlaybackSnapshot get snapshot => snap;
  @override
  Stream<PlaybackSnapshot> get snapshots => Stream.value(snap);
  @override
  double? get videoAspectRatio => null;
  @override
  Widget buildVideoView({Key? key, BoxFit fit = BoxFit.contain}) =>
      Container(key: key);
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
    disposed = true;
    await _completed.close();
  }

  @override
  Future<void> shutdown() => dispose();
}
