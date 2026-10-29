import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:media_kit/media_kit.dart' as mk;
import 'package:path_provider/path_provider.dart';

import 'importer.dart';

/// Best-of-N JPEG thumbnails from local media. macOS uses AVFoundation;
/// Android, iOS, Windows and Linux use the bundled media_kit decoder.
/// Disk-cached per media id under app support; any failure yields null
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
    final dir = await _cacheDirectory();
    final suffix = highRes ? '.hi.v3.jpg' : '.v3.jpg';
    return File('${dir.path}/yureru_thumbs/$mediaId$suffix');
  }

  static Future<List<File>> legacyCacheFilesFor(String mediaId) async {
    final dir = await _cacheDirectory();
    return [
      File('${dir.path}/yureru_thumbs/$mediaId.jpg'),
      File('${dir.path}/yureru_thumbs/$mediaId.jpg.txt'),
      File('${dir.path}/yureru_thumbs/$mediaId.v2.jpg'),
      File('${dir.path}/yureru_thumbs/$mediaId.v2.jpg.txt'),
    ];
  }

  static Future<Directory> _cacheDirectory() async {
    try {
      return await getApplicationSupportDirectory();
    } catch (_) {
      return getTemporaryDirectory();
    }
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
      if (Platform.isMacOS && _isWebm(localPath)) {
        // mpv's screenshot-raw command aborts inside libmpv on this macOS
        // build. If ffmpeg is installed, extract frames in a child process
        // instead so imported WebM files can still get persistent thumbnails.
        return _throttled(
          () => _generateWebmWithFfmpeg(
            mediaId,
            localPath,
            maxWidth,
            highRes: highRes,
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

  static Future<String?> _findFfmpeg() async {
    final candidates = <String>[
      '/opt/homebrew/bin/ffmpeg',
      '/usr/local/bin/ffmpeg',
      '/opt/local/bin/ffmpeg',
      for (final dir in (Platform.environment['PATH'] ?? '').split(':'))
        if (dir.isNotEmpty) '$dir/ffmpeg',
    ];
    for (final candidate in candidates.toSet()) {
      if (await File(candidate).exists()) return candidate;
    }
    return null;
  }

  static Future<File?> _generateWebmWithFfmpeg(
    String mediaId,
    String localPath,
    int maxWidth, {
    required bool highRes,
  }) async {
    final ffmpeg = await _findFfmpeg();
    if (ffmpeg == null) return null;
    final out = await cacheFileFor(mediaId, highRes: highRes);
    await out.parent.create(recursive: true);
    final scratch = await Directory.systemTemp.createTemp('yureru-thumb-');
    try {
      Uint8List? bestFrame;
      var bestScore = double.negativeInfinity;
      var bestTime = 0;
      for (final seconds in const [1, 3, 6, 12]) {
        final frame = File('${scratch.path}/frame-$seconds.jpg');
        try {
          final result = await Process.run(ffmpeg, [
            '-v',
            'error',
            '-ss',
            '$seconds',
            '-i',
            localPath,
            '-frames:v',
            '1',
            '-vf',
            'scale=$maxWidth:-2',
            '-q:v',
            '3',
            '-y',
            frame.path,
          ]).timeout(const Duration(seconds: 12));
          if (result.exitCode != 0 || !await frame.exists()) continue;
          final bytes = await frame.readAsBytes();
          final score = _frameScore(bytes);
          if (score != null && score > bestScore) {
            bestFrame = bytes;
            bestScore = score;
            bestTime = seconds * 1000;
          }
        } catch (_) {
          // Some videos are shorter than a sample point; continue to others.
        }
      }
      if (bestFrame == null) return null;
      await out.writeAsBytes(bestFrame, flush: true);
      await File('${out.path}.txt').writeAsString('$bestTime');
      return out;
    } catch (error) {
      debugPrint('thumb: ffmpeg skipped $mediaId: $error');
      return null;
    } finally {
      try {
        await scratch.delete(recursive: true);
      } catch (_) {}
    }
  }

  static Future<File?> _generate(
    String mediaId,
    String localPath,
    int maxWidth, {
    bool highRes = false,
  }) async {
    try {
      if (!Platform.isMacOS) {
        return await _generateWithMediaKit(
          mediaId,
          localPath,
          maxWidth,
          highRes: highRes,
        );
      }
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

  /// Uses the same bundled decoder as playback on Android, iOS, Windows and
  /// Linux. Multiple seek samples are scored for detail and usable exposure,
  /// matching the native macOS best-frame behavior without another plugin.
  static Future<File?> _generateWithMediaKit(
    String mediaId,
    String localPath,
    int maxWidth, {
    required bool highRes,
  }) async {
    final player = mk.Player();
    try {
      await player.open(mk.Media(Uri.file(localPath).toString()), play: false);
      var duration = player.state.duration;
      if (duration <= Duration.zero) {
        duration = await player.stream.duration
            .firstWhere((value) => value > Duration.zero)
            .timeout(const Duration(seconds: 8));
      }
      if (duration <= Duration.zero) return null;

      Uint8List? bestFrame;
      var bestScore = double.negativeInfinity;
      var bestTimeMs = 0;
      for (final fraction in const [0.12, 0.34, 0.58, 0.82]) {
        final timeMs = (duration.inMilliseconds * fraction).round();
        await player.seek(Duration(milliseconds: timeMs));
        await Future<void>.delayed(const Duration(milliseconds: 180));
        final bytes = await player.screenshot(format: 'image/jpeg');
        final score = bytes == null ? null : _frameScore(bytes);
        if (bytes != null &&
            bytes.isNotEmpty &&
            score != null &&
            score > bestScore) {
          bestFrame = bytes;
          bestScore = score;
          bestTimeMs = timeMs;
        }
      }
      if (bestFrame == null) return null;

      final decoded = img.decodeJpg(bestFrame);
      if (decoded == null) return null;
      final thumbnail = img.copyResize(
        decoded,
        width: maxWidth,
        interpolation: img.Interpolation.average,
      );
      final out = await cacheFileFor(mediaId, highRes: highRes);
      await out.parent.create(recursive: true);
      await out.writeAsBytes(
        img.encodeJpg(thumbnail, quality: 88),
        flush: true,
      );
      await File('${out.path}.txt').writeAsString('$bestTimeMs');
      return out;
    } catch (e) {
      debugPrint('thumb: media_kit skipped $mediaId: $e');
      return null;
    } finally {
      await player.dispose();
    }
  }

  static double? _frameScore(Uint8List bytes) {
    final decoded = img.decodeJpg(bytes);
    if (decoded == null) return null;
    final sample = img.copyResize(decoded, width: 64, height: 36);
    final luminance = List<double>.filled(sample.width * sample.height, 0);
    var sum = 0.0;
    var squaredSum = 0.0;
    var edges = 0.0;
    for (var y = 0; y < sample.height; y++) {
      for (var x = 0; x < sample.width; x++) {
        final value = sample.getPixel(x, y).luminance.toDouble();
        final index = y * sample.width + x;
        luminance[index] = value;
        sum += value;
        squaredSum += value * value;
        if (x > 0) edges += (value - luminance[index - 1]).abs();
        if (y > 0) edges += (value - luminance[index - sample.width]).abs();
      }
    }
    final count = luminance.length;
    final mean = sum / count;
    if (mean < 18 || mean > 238) return -1;
    final variance = (squaredSum / count - mean * mean).clamp(0.0, 65025.0);
    final exposurePenalty = (mean - 128).abs() / 128 * 18;
    return variance + edges / count * 0.35 - exposurePenalty;
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
      if (!await File(localPath).exists()) {
        return null;
      }
      final ms = Platform.isMacOS
          ? await mediaPickerChannel.invokeMethod<int>('probeDuration', {
              'path': localPath,
            })
          : await _probeDurationWithMediaKit(localPath);
      if (ms == null || ms <= 0) return null;
      _cache[mediaId] = ms;
      return ms;
    } catch (e) {
      debugPrint('duration: skipped $mediaId: $e');
      return null;
    }
  }

  static Future<int?> _probeDurationWithMediaKit(String localPath) async {
    return ThumbnailService._throttled(() async {
      final player = mk.Player();
      try {
        await player.open(
          mk.Media(Uri.file(localPath).toString()),
          play: false,
        );
        var duration = player.state.duration;
        if (duration <= Duration.zero) {
          duration = await player.stream.duration
              .firstWhere((value) => value > Duration.zero)
              .timeout(const Duration(seconds: 8));
        }
        return duration.inMilliseconds > 0 ? duration.inMilliseconds : null;
      } finally {
        await player.dispose();
      }
    });
  }
}
