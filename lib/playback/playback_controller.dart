import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app_state.dart';
import '../data/session.dart';
import 'playback_engine.dart';

/// UI-agnostic controller: Playlist -> yureru Queue -> current Media ID ->
/// engine.load ONE item. Owns auto-advance (completed -> next).
/// Operable from audio_service later (no BuildContext, no widgets).
class PlaybackController {
  final Ref ref;
  bool _hooked = false;
  DateTime _lastPosSave = DateTime.fromMillisecondsSinceEpoch(0);

  /// Media id currently loaded in the engine (for position bookkeeping).
  String? _loadedId;
  final Set<String> _openingIds = {};

  PlaybackController(this.ref) {
    _hookCompleted();
    _hookPositionSaver();
  }

  PlaybackEngine get engine => ref.read(engineProvider);

  Future<void> setVolume(double volume) async {
    final value = volume.clamp(0.0, 1.0).toDouble();
    ref.read(volumeProvider.notifier).state = value;
    await engine.setVolume(value);
  }

  void _hookCompleted() {
    if (_hooked) return;
    _hooked = true;
    // Engine is a singleton; hook once. Engines may fire both
    // completedStream and onEnded — _onEnded debounces.
    engine.completedStream.listen((_) => _onEnded(), onError: (_) {});
    // Legacy callback path (engines that use onEnded instead of stream).
    engine.onEnded = () => _onEnded();
  }

  DateTime _lastEnded = DateTime.fromMillisecondsSinceEpoch(0);

  /// Periodically remember the position so a restart resumes mid-video.
  /// Throttled; also saved on track switch and on pause.
  void _hookPositionSaver() {
    engine.snapshots.listen((snap) {
      if (!snap.isPlaying || !snap.initialized) return;
      final id = _loadedId ?? ref.read(queueProvider).currentId;
      if (id == null) return;
      final ms = snap.position.inMilliseconds;
      if (ms < 3000) return;
      final now = DateTime.now();
      if (now.difference(_lastPosSave).inSeconds < 10) return;
      _lastPosSave = now;
      unawaited(ref.read(sessionStoreProvider).savePosition(id, ms));
    }, onError: (_) {});
  }

  void saveCurrentPosition() => unawaited(_saveNow());

  Future<void> _saveNow() async {
    final id = _loadedId ?? ref.read(queueProvider).currentId;
    final ms = engine.snapshot.position.inMilliseconds;
    if (id == null || ms < 3000) return;
    await ref.read(sessionStoreProvider).savePosition(id, ms);
  }

  Future<void> prepareForAppExit() async {
    await _saveNow();
    if (engine.snapshot.initialized) await engine.pause();
    await engine.shutdown();
  }

  /// End-of-track handler honoring repeat mode. Debounced because some engines
  /// fire both completedStream and onEnded for the same completion.
  Future<void> _onEnded() async {
    final now = DateTime.now();
    if (now.difference(_lastEnded).inMilliseconds < 400) return;
    _lastEnded = now;
    final q = ref.read(queueProvider);
    final endedId = q.currentId;
    if (endedId != null) {
      await ref.read(sessionStoreProvider).clearPosition(endedId);
    }
    if (q.repeat == 'one') {
      try {
        await engine.seekTo(Duration.zero);
        await engine.play();
      } catch (_) {
        await openCurrent();
      }
      return;
    }
    if (q.repeat == 'off' &&
        q.queue.isNotEmpty &&
        q.index >= q.queue.length - 1) {
      await engine.pause();
      return;
    }
    await playNext();
  }

  Future<void> startPlaylist(String playlistId, {required bool shuffle}) async {
    final lib = ref.read(libraryProvider);
    final pl = lib.playlistById(playlistId);
    if (pl == null || pl.mediaIds.isEmpty) return;
    ref
        .read(queueProvider.notifier)
        .start(pl.mediaIds, playlistId: playlistId, shuffle: shuffle);
    await openCurrent();
  }

  Future<void> openCurrent() async {
    final q = ref.read(queueProvider);
    final lib = ref.read(libraryProvider);
    final id = q.currentId;
    if (id == null) return;
    final m = lib.byId(id);
    if (m == null) {
      // Library entry vanished (deleted) but queue still holds the id:
      // drop it and advance instead of silently keeping old playback.
      ref.read(queueProvider.notifier).removeId(id);
      final next = ref.read(queueProvider);
      if (next.hasCurrent && next.currentId != id) {
        await openCurrent();
      } else {
        await engine.pause();
      }
      return;
    }
    // Queue taps can arrive through both the row and its play affordance.
    // Do not open the same media twice while its first load is still running.
    if (_loadedId == id && engine.snapshot.initialized) return;
    if (!_openingIds.add(id)) return;
    try {
      // Push rate first so engine.load() opens with the right speed.
      await engine.setPlaybackRate(q.speed);
      // Remember where the outgoing track stopped before switching.
      if (_loadedId != null && _loadedId != id) await _saveNow();
      final start = await _savedStart(id, m.durationMs);
      await ref.read(sessionStoreProvider).markActiveMedia(id);
      try {
        await engine.load(
          PlaybackSource(mediaId: id, uri: m.localPath, start: start),
          autoplay: true,
        );
        _loadedId = id;
      } catch (_) {
        // Missing/unreadable file: drop and move on instead of hanging.
        ref.read(queueProvider.notifier).removeId(id);
        final next = ref.read(queueProvider);
        if (next.hasCurrent) {
          await openCurrent();
        }
      }
    } finally {
      _openingIds.remove(id);
    }
  }

  Future<Duration?> _savedStart(String id, int? durationMs) async {
    try {
      final store = ref.read(sessionStoreProvider);
      final ms = (await store.loadPositions())[id];
      if (ms == null || ms <= 3000) return null;
      // A position at the end is stale; start a completed video from the top.
      if (durationMs != null && ms >= durationMs - 1000) {
        await store.clearPosition(id);
        return null;
      }
      return Duration(milliseconds: ms);
    } catch (_) {
      // A failed position lookup must not prevent the video from playing.
      return null;
    }
  }

  Future<void> playNext() async {
    ref.read(queueProvider.notifier).next();
    await openCurrent();
  }

  Future<void> playPrev() async {
    ref.read(queueProvider.notifier).previous();
    await openCurrent();
  }

  Future<void> toggle() async {
    // Empty queue + never-loaded engine: no-op (avoids creating a
    // player with nothing to play). If the engine already holds media
    // (initialized), still allow play/pause delegation.
    if (!ref.read(queueProvider).hasCurrent && !engine.snapshot.initialized) {
      return;
    }
    final s = engine.snapshot;
    if (s.isPlaying) {
      await engine.pause();
      unawaited(_saveNow());
    } else {
      await engine.play();
    }
  }

  Future<void> seekTo(Duration pos) => engine.seekTo(pos);
  Future<void> seekBy(Duration delta) async {
    final snap = engine.snapshot;
    final cur = snap.position;
    var target = cur + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (snap.duration > Duration.zero && target > snap.duration) {
      target = snap.duration;
    }
    await engine.seekTo(target);
  }

  Future<void> setSpeed(double speed) async {
    ref.read(queueProvider.notifier).setSpeed(speed);
    await engine.setPlaybackRate(speed);
  }

  Future<void> cycleSpeed(List<double> speeds) async {
    if (speeds.isEmpty) return;
    final q = ref.read(queueProvider);
    final i = speeds.indexOf(q.speed);
    final n = speeds[(i + 1) % speeds.length];
    await setSpeed(n);
  }

  /// Restore last session: queue layout (unknown ids pruned) plus the
  /// paused engine preloaded at the saved position. No autoplay, no
  /// screen change — the user resumes with one tap.
  Future<void> restoreSession() async {
    try {
      final store = ref.read(sessionStoreProvider);
      final saved = await store.loadQueue();
      if (saved == null) return;
      final lib = ref.read(libraryProvider);
      ref.read(queueProvider.notifier).restore(saved, {
        for (final m in lib.media) m.id,
      });
      final q = ref.read(queueProvider);
      final id = q.currentId;
      if (id == null) return;
      final m = lib.byId(id);
      if (m == null) return;
      final start = await _savedStart(id, m.durationMs);
      await engine.setPlaybackRate(q.speed);
      await engine.load(
        PlaybackSource(mediaId: id, uri: m.localPath, start: start),
        autoplay: false,
      );
      _loadedId = id;
      ref.read(viewingPlayerProvider.notifier).state = true;
    } catch (_) {
      // Session restore must never break launch.
    }
  }

  /// Handler called when a media item is deleted from the library.
  /// Removes it from queue and advances or pauses if it was currently loaded.
  Future<void> handleMediaRemoved(String id) async {
    final q = ref.read(queueProvider);
    if (!q.queue.contains(id)) return;
    final wasCurrent = q.currentId == id;
    ref.read(queueProvider.notifier).removeId(id);
    if (wasCurrent) {
      final next = ref.read(queueProvider);
      if (next.hasCurrent) {
        await openCurrent();
      } else {
        await engine.pause();
        _loadedId = null;
      }
    }
  }
}

final playbackControllerProvider = Provider<PlaybackController>(
  (ref) => PlaybackController(ref),
);
