import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app_state.dart';
import '../data/session.dart';
import '../domain/models.dart';
import 'playback_engine.dart';
import 'sleep_timer_provider.dart';

/// UI-agnostic controller: Playlist -> yureru Queue -> current Media ID ->
/// engine.load ONE item. Owns auto-advance (completed -> next).
/// Operable from audio_service later (no BuildContext, no widgets).
class PlaybackController {
  final Ref ref;
  bool _hooked = false;
  double _lastAudibleVolume = 1;
  DateTime _lastPosSave = DateTime.fromMillisecondsSinceEpoch(0);

  /// Media id currently loaded in the engine (for position bookkeeping).
  String? _loadedId;
  String? _loadedSourceUri;
  PlayerViewMode? _loadedViewMode;
  int _loadedTimelineOffsetMs = 0;
  int _loadedTrimEndMs = 0;
  final Set<String> _openingIds = {};

  PlaybackController(this.ref) {
    if (engine.volume > 0) _lastAudibleVolume = engine.volume;
    _hookCompleted();
    _hookPositionSaver();
  }

  PlaybackEngine get engine => ref.read(engineProvider);

  Future<void> setVolume(double volume) async {
    final value = volume.clamp(0.0, 1.0).toDouble();
    if (value > 0) _lastAudibleVolume = value;
    ref.read(volumeProvider.notifier).state = value;
    await engine.setVolume(value);
  }

  /// Shared across layouts, so leaving a muted view preserves the restore level.
  Future<void> toggleMute() =>
      setVolume(ref.read(volumeProvider) == 0 ? _lastAudibleVolume : 0);

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
      final ms = _videoTimelinePositionMs(id, snap.position.inMilliseconds);
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
    final ms = _videoTimelinePositionMs(
      id,
      engine.snapshot.position.inMilliseconds,
    );
    if (id == null || ms < 3000) return;
    await ref.read(sessionStoreProvider).savePosition(id, ms);
  }

  int _videoTimelinePositionMs(String? id, int viewPositionMs) {
    if (id == null ||
        _loadedId != id ||
        _loadedViewMode != PlayerViewMode.image) {
      return viewPositionMs;
    }
    return viewPositionMs + _loadedTimelineOffsetMs;
  }

  Future<void> pauseAndRemember() async {
    if (engine.snapshot.initialized) await engine.pause();
    await _saveNow();
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
    final sleep = await ref
        .read(sleepTimerProvider.notifier)
        .trackEnded(endedId);
    if (endedId != null) {
      await ref.read(sessionStoreProvider).clearPosition(endedId);
    }
    if (sleep) return;
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

  Future<void> openCurrent({bool usePreferredViewMode = true}) async {
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
    final viewNotifier = ref.read(playerViewModeProvider.notifier);
    await viewNotifier.ready;
    final desiredMode = usePreferredViewMode
        ? viewNotifier.preferred
        : ref.read(playerViewModeProvider);
    final effectiveMode = switch (m.viewAvailability) {
      MediaViewAvailability.both => desiredMode,
      MediaViewAvailability.mediaOnly => PlayerViewMode.media,
      MediaViewAvailability.artworkOnly => PlayerViewMode.image,
    };
    viewNotifier.setEffective(effectiveMode);
    final isArtworkView = effectiveMode == PlayerViewMode.image;
    // Queue taps can arrive through both the row and its play affordance.
    // Do not open the same media twice while its first load is still running.
    if (_loadedId == id && engine.snapshot.initialized) {
      await syncCurrentViewSource();
      return;
    }
    if (!_openingIds.add(id)) return;
    try {
      await ref.read(audioSettingsProvider.notifier).ready;
      // Push rate first so engine.load() opens with the right speed.
      await engine.setPlaybackRate(q.speed);
      await engine.setVideoTrackEnabled(
        ref.read(playerViewModeProvider) == PlayerViewMode.media,
      );
      // Remember where the outgoing track stopped before switching.
      if (_loadedId != null && _loadedId != id) await _saveNow();
      final sourceMedia = _sourceMediaForView(m);
      final videoStart = await _savedStart(id, m.durationMs);
      var start = videoStart ?? Duration.zero;
      var timelineOffset = Duration.zero;
      if (ref.read(playerViewModeProvider) == PlayerViewMode.image) {
        timelineOffset = Duration(milliseconds: m.artworkAudioOffsetMs);
        start = Duration(
          milliseconds:
              (start.inMilliseconds - m.artworkAudioOffsetMs).clamp(
                0,
                1 << 62,
              ) +
              m.artworkAudioOffsetMs,
        );
        final sourceDurationMs = sourceMedia.durationMs;
        if (sourceDurationMs != null &&
            start.inMilliseconds >= sourceDurationMs) {
          start = Duration(
            milliseconds: sourceDurationMs > 500 ? sourceDurationMs - 500 : 0,
          );
        }
      }
      await ref.read(sessionStoreProvider).markActiveMedia(id);
      try {
        await engine.load(
          PlaybackSource(
            mediaId: id,
            uri: sourceMedia.localPath,
            start: start,
            timelineOffset: timelineOffset,
            end: isArtworkView && m.artworkAudioEndMs > 0
                ? Duration(milliseconds: m.artworkAudioEndMs)
                : null,
            pipArtworkPath: isArtworkView
                ? m.artworkPath ?? m.thumbnailPath
                : null,
          ),
          autoplay: true,
        );
        _loadedId = id;
        _loadedSourceUri = sourceMedia.localPath;
        _loadedViewMode = ref.read(playerViewModeProvider);
        _loadedTimelineOffsetMs = timelineOffset.inMilliseconds;
        _loadedTrimEndMs = isArtworkView ? m.artworkAudioEndMs : 0;
        await _recordPlayback(id);
      } catch (_) {
        if (sourceMedia.localPath != m.localPath) {
          try {
            await engine.load(
              PlaybackSource(mediaId: id, uri: m.localPath, start: videoStart),
              autoplay: true,
            );
            _loadedId = id;
            _loadedSourceUri = m.localPath;
            _loadedViewMode = ref.read(playerViewModeProvider);
            _loadedTimelineOffsetMs = 0;
            _loadedTrimEndMs = 0;
            await _recordPlayback(id);
            return;
          } catch (_) {}
        }
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

  MediaItem _sourceMediaForView(MediaItem media) {
    if (ref.read(playerViewModeProvider) != PlayerViewMode.image) return media;
    final sourceId = media.artworkAudioMediaId;
    if (sourceId != null) {
      return ref.read(libraryProvider).byId(sourceId) ?? media;
    }
    final sourcePath = media.artworkAudioPath;
    if (sourcePath != null) {
      return media.copyWith(localPath: sourcePath, durationMs: null);
    }
    return media;
  }

  /// Swap only the underlying audio when the user changes video/jacket mode.
  /// The queue and displayed media item remain the same.
  Future<void> syncCurrentViewSource() async {
    final queue = ref.read(queueProvider);
    final media = queue.currentId == null
        ? null
        : ref.read(libraryProvider).byId(queue.currentId!);
    if (media == null) return;
    final sourceMedia = _sourceMediaForView(media);
    final useVideoTrack =
        ref.read(playerViewModeProvider) == PlayerViewMode.media;
    final snapshot = engine.snapshot;
    final targetMode = ref.read(playerViewModeProvider);
    final videoTimelineMs =
        snapshot.position.inMilliseconds +
        (_loadedViewMode == PlayerViewMode.image ? _loadedTimelineOffsetMs : 0);
    final targetTimelineOffset = targetMode == PlayerViewMode.image
        ? media.artworkAudioOffsetMs
        : 0;
    final targetTrimEnd = targetMode == PlayerViewMode.image
        ? media.artworkAudioEndMs
        : 0;
    final targetStartMs =
        (targetMode == PlayerViewMode.image
                ? (videoTimelineMs - media.artworkAudioOffsetMs).clamp(
                        0,
                        1 << 62,
                      ) +
                      media.artworkAudioOffsetMs
                : videoTimelineMs)
            .clamp(0, 1 << 62);
    final targetStart = Duration(milliseconds: targetStartMs);
    await engine.setVideoTrackEnabled(useVideoTrack);
    if (_loadedId == media.id &&
        _loadedSourceUri == sourceMedia.localPath &&
        _loadedTimelineOffsetMs == targetTimelineOffset &&
        _loadedTrimEndMs == targetTrimEnd &&
        _loadedViewMode == targetMode) {
      return;
    }
    if (_loadedId == media.id &&
        _loadedSourceUri == sourceMedia.localPath &&
        _loadedTimelineOffsetMs == targetTimelineOffset &&
        _loadedTrimEndMs == targetTrimEnd) {
      _loadedViewMode = targetMode;
      return;
    }
    var start = targetStart;
    final maxMs = sourceMedia.durationMs;
    if (maxMs != null && start.inMilliseconds >= maxMs) {
      start = Duration(milliseconds: maxMs > 500 ? maxMs - 500 : 0);
    }
    await engine.setPlaybackRate(queue.speed);
    try {
      await engine.load(
        PlaybackSource(
          mediaId: media.id,
          uri: sourceMedia.localPath,
          start: start,
          timelineOffset: Duration(milliseconds: targetTimelineOffset),
          end: targetTrimEnd > 0 ? Duration(milliseconds: targetTrimEnd) : null,
          pipArtworkPath: targetMode == PlayerViewMode.image
              ? media.artworkPath ?? media.thumbnailPath
              : null,
        ),
        autoplay: snapshot.isPlaying,
      );
      _loadedId = media.id;
      _loadedSourceUri = sourceMedia.localPath;
      _loadedViewMode = targetMode;
      _loadedTimelineOffsetMs = targetTimelineOffset;
      _loadedTrimEndMs = targetTrimEnd;
    } catch (_) {
      if (sourceMedia.localPath == media.localPath) return;
      await engine.load(
        PlaybackSource(
          mediaId: media.id,
          uri: media.localPath,
          start: Duration(milliseconds: videoTimelineMs),
        ),
        autoplay: snapshot.isPlaying,
      );
      _loadedId = media.id;
      _loadedSourceUri = media.localPath;
      _loadedViewMode = targetMode;
      _loadedTimelineOffsetMs = 0;
      _loadedTrimEndMs = 0;
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
      await _recordPlayback(
        _loadedId ?? ref.read(queueProvider).currentId,
        countAsPlay: false,
      );
    }
  }

  Future<void> _recordPlayback(String? id, {bool countAsPlay = true}) async {
    if (id == null) return;
    try {
      await ref
          .read(libraryProvider.notifier)
          .recordPlayback(id, countAsPlay: countAsPlay);
    } catch (_) {
      // History storage must never make a playable source get skipped.
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
      final viewNotifier = ref.read(playerViewModeProvider.notifier);
      await viewNotifier.ready;
      viewNotifier.setEffective(switch (m.viewAvailability) {
        MediaViewAvailability.both => viewNotifier.preferred,
        MediaViewAvailability.mediaOnly => PlayerViewMode.media,
        MediaViewAvailability.artworkOnly => PlayerViewMode.image,
      });
      final sourceMedia = _sourceMediaForView(m);
      var start = await _savedStart(id, m.durationMs) ?? Duration.zero;
      var timelineOffset = Duration.zero;
      if (ref.read(playerViewModeProvider) == PlayerViewMode.image) {
        timelineOffset = Duration(milliseconds: m.artworkAudioOffsetMs);
        start = Duration(
          milliseconds:
              (start.inMilliseconds - m.artworkAudioOffsetMs).clamp(
                0,
                1 << 62,
              ) +
              m.artworkAudioOffsetMs,
        );
      }
      await ref.read(audioSettingsProvider.notifier).ready;
      await engine.setPlaybackRate(q.speed);
      await engine.setVideoTrackEnabled(
        ref.read(playerViewModeProvider) == PlayerViewMode.media,
      );
      await engine.load(
        PlaybackSource(
          mediaId: id,
          uri: sourceMedia.localPath,
          start: start,
          timelineOffset: timelineOffset,
          end:
              ref.read(playerViewModeProvider) == PlayerViewMode.image &&
                  m.artworkAudioEndMs > 0
              ? Duration(milliseconds: m.artworkAudioEndMs)
              : null,
          pipArtworkPath:
              ref.read(playerViewModeProvider) == PlayerViewMode.image
              ? m.artworkPath ?? m.thumbnailPath
              : null,
        ),
        autoplay: false,
      );
      _loadedId = id;
      _loadedSourceUri = sourceMedia.localPath;
      _loadedViewMode = ref.read(playerViewModeProvider);
      _loadedTimelineOffsetMs = timelineOffset.inMilliseconds;
      _loadedTrimEndMs =
          ref.read(playerViewModeProvider) == PlayerViewMode.image
          ? m.artworkAudioEndMs
          : 0;
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
        _loadedSourceUri = null;
        _loadedViewMode = null;
        _loadedTimelineOffsetMs = 0;
        _loadedTrimEndMs = 0;
      }
    }
  }
}

final playbackControllerProvider = Provider<PlaybackController>(
  (ref) => PlaybackController(ref),
);
