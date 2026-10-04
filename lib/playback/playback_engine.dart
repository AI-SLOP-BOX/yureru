import 'package:flutter/widgets.dart';

/// Snapshot of playback state. Pure Dart/Flutter types only.
/// media_kit types must never leak past the engine implementation.
class PlaybackSnapshot {
  final Duration position;
  final Duration duration;
  final bool isPlaying;
  final bool initialized;
  final bool completed;
  const PlaybackSnapshot({
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.isPlaying = false,
    this.initialized = false,
    this.completed = false,
  });
}

/// Immutable source: local file path or http(s) URL (future LAN streaming
/// `http://192.168.x.x:xxxx/media/{mediaId}`). Engine decides how to open it.
/// Optional [start]/[end] bound playback (mpv-native, no seek race).
class PlaybackSource {
  final String mediaId;
  final String uri;
  final Duration? start;
  final Duration? end;
  const PlaybackSource({
    required this.mediaId,
    required this.uri,
    this.start,
    this.end,
  });
  bool get isNetwork => uri.startsWith('http://') || uri.startsWith('https://');
}

/// Engine abstraction. UI talks only to this + PlaybackController.
/// Queue ownership stays in yureru (QueueNotifier); engines play ONE item.
abstract class PlaybackEngine {
  /// Back-compat: open by id + path-or-url.
  Future<void> open(String mediaId, String pathOrUrl) =>
      load(PlaybackSource(mediaId: mediaId, uri: pathOrUrl), autoplay: true);
  Future<void> load(PlaybackSource source, {bool autoplay = true});
  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration pos);
  Future<void> setSpeed(double speed); // alias of setPlaybackRate
  Future<void> setPlaybackRate(double rate) => setSpeed(rate);

  /// Volume 0.0 (mute) .. 1.0 (full).
  Future<void> setVolume(double volume);
  double get volume;

  /// Enable or disable video track (for audio-only / battery saving mode)
  Future<void> setVideoTrackEnabled(bool enabled) async {}

  Future<void> dispose();

  Stream<Duration> get positionStream;
  Stream<Duration> get durationStream;
  Stream<bool> get playingStream;
  Stream<void> get completedStream;

  PlaybackSnapshot get snapshot;
  Stream<PlaybackSnapshot> get snapshots;
  double? get videoAspectRatio;

  /// Video output widget. Implemented by engines with video support.
  /// Returned as plain Widget so presentation never imports media_kit.
  Widget buildVideoView({Key? key, BoxFit fit = BoxFit.contain});

  // Legacy compat for existing UI (deprecated, prefer streams/snapshot).
  Stream<dynamic> get events => snapshots;
  PlaybackSnapshot get last => snapshot;
  void Function()? get onEnded;
  set onEnded(void Function()? cb);
}
