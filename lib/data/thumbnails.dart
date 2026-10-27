import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'package:path_provider/path_provider.dart';

import 'importer.dart';

/// Best-of-N frame JPEG thumbnails via the native channel (macOS:
/// AVFoundation samples several timestamps, skips near-black/white frames
/// and returns the most textured one).
/// Disk-cached per media id under the temp dir; any failure yields null
/// and callers fall back to the gradient placeholder.
class ThumbnailService {
  static final Map<String, Future<File?>> _inflight = {};

  /// At most this many concurrent native generations. AVFoundation seeks
  /// contend with mpv decode for hardware; unbounded bursts during list
  /// builds cause dropped video frames (perceived A/V lag).
  static const _maxConcurrent = 2;
  static int _active = 0;
  static final List<Completer<void>> _waiters = <Completer<void>>[];

  static Future<T> _throttled<T>(Future<T> Function() job) async {
    while (_active >= _maxConcurrent) {
      final gate = Completer<void>();
      _waiters.add(gate);
      await gate.future;
    }
    _active++;
    try {
      return await job();
    } finally {
      _active--;
      if (_waiters.isNotEmpty) _waiters.removeAt(0).complete();
    }
  }

  /// Current cache file location (exposed for tests).
  /// Older generations are deleted on rewrite. The best-frame timestamp
  /// rides along in a `.txt` sidecar so the home preview can loop the
  /// bright section instead of black head.
  static Future<File> cacheFileFor(
    String mediaId, {
    bool highRes = false,
  }) async {
    final dir = await getTemporaryDirectory();
    final suffix = highRes ? '.hi.v3.jpg' : '.v3.jpg';
    return File('${dir.path}/yureru_thumbs/$mediaId$suffix');
  }

  static Future<List<File>> legacyCacheFilesFor(String mediaId) async {
    final dir = await getTemporaryDirectory();
    return [
      File('${dir.path}/yureru_thumbs/$mediaId.jpg'),
      File('${dir.path}/yureru_thumbs/$mediaId.jpg.txt'),
      File('${dir.path}/yureru_thumbs/$mediaId.v2.jpg'),
      File('${dir.path}/yureru_thumbs/$mediaId.v2.jpg.txt'),
    ];
  }

  /// Best-frame timestamp (ms) when the thumbnail was generated, if known.
  static Future<int?> bestTimeMsFor(String mediaId) async {
    try {
      final out = await cacheFileFor(mediaId);
      final sidecar = File('${out.path}.txt');
      if (!await sidecar.exists()) return null;
      return int.tryParse((await sidecar.readAsString()).trim());
    } catch (_) {
      return null;
    }
  }

  static Future<File?> forMedia({
    required String mediaId,
    required String localPath,
    int maxWidth = 320,
    bool highRes = false,
  }) {
    if (localPath.startsWith('http://') || localPath.startsWith('https://')) {
      return Future.value(null);
    }
    final key = highRes ? '$mediaId@hi' : mediaId;
    return _inflight.putIfAbsent(
      key,
      () =>
          _make(
            mediaId: mediaId,
            localPath: localPath,
            maxWidth: highRes ? 1280 : maxWidth,
            highRes: highRes,
            // NOTE: block body — returning _inflight.remove()'s value would
            // resolve this future with itself (the stored entry) and deadlock.
          ).whenComplete(() {
            _inflight.remove(key);
          }),
    );
  }

  static Future<File?> _make({
    required String mediaId,
    required String localPath,
    required int maxWidth,
    bool highRes = false,
  }) async {
    try {
      // TODO: mobile (video_thumbnail) / Windows / Linux backends.
      if (!Platform.isMacOS) return null;
      // Check existence asynchronously without blocking UI event loop.
      if (!await File(localPath).exists()) {
        return null;
      }
      final out = await cacheFileFor(mediaId, highRes: highRes);
      if (await out.exists()) {
        // Migrate pre-sidecar caches: regenerate once so the best-time
        // sidecar exists for the preview loop.
        try {
          if (highRes || await File('${out.path}.txt').exists()) return out;
          await out.delete();
        } catch (_) {
          return out;
        }
      }
      if (_isWebm(localPath)) {
        return _throttled(
          () => _generateWebm(
            mediaId: mediaId,
            localPath: localPath,
            output: out,
          ),
        );
      }
      return _throttled(
        () => _generate(mediaId, localPath, maxWidth, highRes: highRes),
      );
    } catch (e) {
      debugPrint('thumb: skipped $mediaId: $e');
      return null;
    }
  }

  static bool _isWebm(String path) =>
      path.toLowerCase().split('?').first.endsWith('.webm');

  /// AVFoundation does not decode WebM on macOS. Use the same mpv backend as
  /// playback for this container, then cache its JPEG frame just like the
  /// AVFoundation path. The temporary player is always disposed to release
  /// its decoder and file handles.
  static Future<File?> _generateWebm({
    required String mediaId,
    required String localPath,
    required File output,
  }) async {
    final player = mk.Player();
    final controller = mkv.VideoController(
      player,
      configuration: const mkv.VideoControllerConfiguration(
        width: 640,
        height: 360,
      ),
    );
    try {
      await controller.platform.future.timeout(const Duration(seconds: 15));
      await controller.setSize(width: 640, height: 360);
      await player.setVolume(0);
      await player
          .open(mk.Media(localPath), play: true)
          .timeout(const Duration(seconds: 30));
      var duration = player.state.duration;
      if (duration <= Duration.zero) {
        duration = await player.stream.duration
            .firstWhere((value) => value > Duration.zero)
            .timeout(const Duration(seconds: 15));
      }
      await controller.waitUntilFirstFrameRendered.timeout(
        const Duration(seconds: 15),
      );
      final target = duration > Duration.zero
          ? Duration(milliseconds: duration.inMilliseconds ~/ 3)
          : Duration.zero;
      await player.seek(target).timeout(const Duration(seconds: 10));
      // Let mpv decode the sought frame before requesting the screenshot.
      await Future<void>.delayed(const Duration(seconds: 1));
      await player.pause();
      final bytes = await player
          .screenshot(format: 'image/jpeg')
          .timeout(const Duration(seconds: 15));
      if (bytes == null || bytes.isEmpty) return null;
      await output.parent.create(recursive: true);
      await output.writeAsBytes(bytes, flush: true);
      if (target.inMilliseconds >= 0) {
        try {
          await File(
            '${output.path}.txt',
          ).writeAsString('${target.inMilliseconds}');
        } catch (_) {}
      }
      // Drop older generations so the WebM thumbnail appears immediately.
      try {
        for (final legacy in await legacyCacheFilesFor(mediaId)) {
          if (legacy.path != output.path && await legacy.exists()) {
            await legacy.delete();
          }
        }
      } catch (_) {}
      return output;
    } catch (e) {
      debugPrint('thumb: mpv WebM skipped $mediaId: $e');
      return null;
    } finally {
      await player.dispose();
    }
  }

  static Future<File?> _generate(
    String mediaId,
    String localPath,
    int maxWidth, {
    bool highRes = false,
  }) async {
    try {
      final out = await cacheFileFor(mediaId, highRes: highRes);
      // Another waiter may have finished first; re-check inside the gate.
      if (await out.exists()) {
        try {
          if (highRes || await File('${out.path}.txt').exists()) return out;
        } catch (_) {
          return out;
        }
      }
      final res = await mediaPickerChannel.invokeMethod<Map>('makeThumbnail', {
        'path': localPath,
        'maxWidth': maxWidth,
      });
      final data = res?['jpg'] as Uint8List?;
      final bestMs = (res?['timeMs'] as num?)?.toInt();
      if (data == null || data.isEmpty) return null;
      await out.parent.create(recursive: true);
      await out.writeAsBytes(data, flush: true);
      if (bestMs != null && bestMs >= 0) {
        try {
          await File('${out.path}.txt').writeAsString('$bestMs');
        } catch (_) {}
      }
      // Drop older generations so the better frame shows.
      try {
        for (final legacy in await legacyCacheFilesFor(mediaId)) {
          if (legacy.path != out.path && await legacy.exists()) {
            await legacy.delete();
          }
        }
      } catch (_) {}
      return out;
    } catch (e) {
      debugPrint('thumb: skipped $mediaId: $e');
      return null;
    }
  }
}

/// Duration probe companion to [ThumbnailService]. Same guards, same
/// no-throw contract; results cached in memory for the session.
class DurationService {
  static final Map<String, Future<int?>> _inflight = {};
  static final Map<String, int> _cache = {};

  static Future<int?> forMedia({
    required String mediaId,
    required String localPath,
  }) {
    final hit = _cache[mediaId];
    if (hit != null) return Future.value(hit);
    if (localPath.startsWith('http://') || localPath.startsWith('https://')) {
      return Future.value(null);
    }
    return _inflight.putIfAbsent(
      mediaId,
      () => _probe(mediaId: mediaId, localPath: localPath).whenComplete(() {
        _inflight.remove(mediaId);
      }),
    );
  }

  static Future<int?> _probe({
    required String mediaId,
    required String localPath,
  }) async {
    try {
      // TODO: mobile / Windows / Linux backends.
      if (!Platform.isMacOS) return null;
      if (!await File(localPath).exists()) {
        return null;
      }
      final ms = await mediaPickerChannel.invokeMethod<int>('probeDuration', {
        'path': localPath,
      });
      if (ms == null || ms <= 0) return null;
      _cache[mediaId] = ms;
      return ms;
    } catch (e) {
      debugPrint('duration: skipped $mediaId: $e');
      return null;
    }
  }
}
