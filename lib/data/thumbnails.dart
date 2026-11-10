import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffprobe_kit.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:media_kit/media_kit.dart' as mk;
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_new_full/return_code.dart';

import 'importer.dart';

/// Best-of-N JPEG thumbnails from local media. macOS uses AVFoundation;
/// Android, iOS, Windows and Linux use the bundled media_kit decoder.
/// Disk-cached per media id under app support; any failure yields null
/// and callers fall back to the gradient placeholder.
class ThumbnailService {
  static final Map<String, Future<File?>> _inflight = {};
  static final Map<String, Future<File?>> _jacketArtwork = {};
  static final Map<String, Future<double?>> _aspectRatios = {};

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
    final suffix = highRes ? '.hi.v5.jpg' : '.v5.jpg';
    return File('${dir.path}/yureru_thumbs/$mediaId$suffix');
  }

  static Future<List<File>> legacyCacheFilesFor(String mediaId) async {
    final dir = await _cacheDirectory();
    return [
      File('${dir.path}/yureru_thumbs/$mediaId.jpg'),
      File('${dir.path}/yureru_thumbs/$mediaId.jpg.txt'),
      File('${dir.path}/yureru_thumbs/$mediaId.v2.jpg'),
      File('${dir.path}/yureru_thumbs/$mediaId.v2.jpg.txt'),
      File('${dir.path}/yureru_thumbs/$mediaId.v3.jpg'),
      File('${dir.path}/yureru_thumbs/$mediaId.v3.jpg.txt'),
      File('${dir.path}/yureru_thumbs/$mediaId.v4.jpg'),
      File('${dir.path}/yureru_thumbs/$mediaId.v4.jpg.txt'),
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

  /// Returns the displayed image's natural aspect ratio. Artwork keeps its
  /// own dimensions; video mode can use the extracted thumbnail dimensions.
  static Future<double?> aspectRatioForMedia({
    required String mediaId,
    required String localPath,
    String? artworkPath,
    String? thumbnailPath,
    required bool preferArtwork,
  }) async {
    if (preferArtwork && artworkPath != null) {
      final ratio = await _aspectRatioForPath(artworkPath);
      if (ratio != null) return ratio;
    }
    if (thumbnailPath != null) {
      final ratio = await _aspectRatioForPath(thumbnailPath);
      if (ratio != null) return ratio;
    }
    final thumbnail = preferArtwork
        ? await jacketArtworkForMedia(mediaId: mediaId, localPath: localPath)
        : await forMedia(mediaId: mediaId, localPath: localPath);
    return thumbnail == null ? null : _aspectRatioForPath(thumbnail.path);
  }

  /// Jacket mode should show the actual image inside a video-generated
  /// thumbnail. Some files store a 16:9 attached image with a portrait cover
  /// centered between flat-colored side mattes; those mattes are part of the
  /// extracted frame, but aren't part of the jacket itself. Trim only clearly
  /// uniform side mattes, leaving ordinary wide artwork untouched.
  static Future<File?> jacketArtworkForMedia({
    required String mediaId,
    required String localPath,
    bool highRes = true,
  }) {
    final key = '$mediaId:${highRes ? 'hi' : 'lo'}';
    return _jacketArtwork
        .putIfAbsent(key, () async {
          File? source;
          try {
            source = await forMedia(
              mediaId: mediaId,
              localPath: localPath,
              highRes: highRes,
            );
            if (source == null) return null;
            final output = File('${source.path}.jacket.v1.jpg');
            if (await output.exists() && await output.length() > 0) {
              return output;
            }
            final decoded = img.decodeImage(await source.readAsBytes());
            if (decoded == null) return source;
            final oriented = img.bakeOrientation(decoded);
            final left = _uniformMatteInset(oriented, fromLeft: true);
            final right = _uniformMatteInset(oriented, fromLeft: false);
            if (left == 0 && right == 0 ||
                left + right >= oriented.width * 0.5) {
              return source;
            }
            final cropped = img.copyCrop(
              oriented,
              x: left,
              y: 0,
              width: oriented.width - left - right,
              height: oriented.height,
            );
            await output.writeAsBytes(
              img.encodeJpg(cropped, quality: 92),
              flush: true,
            );
            return output;
          } catch (error) {
            debugPrint('thumb: jacket matte trim skipped for $mediaId: $error');
            return source;
          }
        })
        .whenComplete(() => _jacketArtwork.remove(key));
  }

  static int _uniformMatteInset(img.Image image, {required bool fromLeft}) {
    // Only consider up to 35% of an edge, and test a spread of vertical
    // samples so text or a narrow stripe cannot be mistaken for letterboxing.
    final maxInset = (image.width * 0.35).floor();
    int xAt(int inset) => fromLeft ? inset : image.width - 1 - inset;
    final ys = List<int>.generate(
      33,
      (i) => (i * (image.height - 1) / 32).round(),
    );
    final edge = image.getPixel(xAt(0), ys[ys.length ~/ 2]);
    var inset = 0;
    for (var x = 0; x < maxInset; x++) {
      var similar = 0;
      for (final y in ys) {
        final pixel = image.getPixel(xAt(x), y);
        final distance =
            (pixel.r - edge.r).abs() +
            (pixel.g - edge.g).abs() +
            (pixel.b - edge.b).abs();
        if (distance <= 24) similar++;
      }
      if (similar / ys.length < 0.94) break;
      inset++;
    }
    // Tiny edge trims are usually compression noise, not actual mattes.
    return inset >= image.width * 0.04 ? inset : 0;
  }

  static Future<double?> _aspectRatioForPath(String path) {
    return _aspectRatios.putIfAbsent(path, () async {
      try {
        final bytes = await File(path).readAsBytes();
        final decoded = img.decodeImage(bytes);
        if (decoded == null || decoded.height == 0) return null;
        return decoded.width / decoded.height;
      } catch (_) {
        return null;
      }
    });
  }

  static Future<File?> forMedia({
    required String mediaId,
    required String localPath,
    int maxWidth = 320,
    bool highRes = false,
  }) {
    if (localPath.startsWith('http://') ||
        localPath.startsWith('https://') ||
        !isVideoPath(localPath)) {
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
      // Some containers carry poster art as an attached picture stream or
      // image attachment. Prefer that authored image over a sampled frame.
      final embedded = await _extractEmbeddedArtwork(
        mediaId,
        localPath,
        maxWidth,
        highRes: highRes,
      );
      if (embedded != null) return embedded;
      // Keep already generated thumbnails for non-WebM media when a new
      // embedded-art probe finds nothing. The cache format change is needed
      // to retry WebM extraction, but must not make working MP4 thumbs vanish
      // just because a codec cannot be regenerated on this machine.
      if (!_isWebm(localPath)) {
        final restored = await _restoreLegacyThumbnail(mediaId, out);
        if (restored != null) return restored;
      }
      if (Platform.isMacOS && _isWebm(localPath)) {
        // Avoid the crash-prone mpv screenshot path for WebM on macOS.
        return _throttled(
          () => _generateWithFfmpeg(
            mediaId,
            localPath,
            maxWidth,
            highRes: highRes,
          ),
        );
      }
      return _throttled(() async {
        final native = await _generate(
          mediaId,
          localPath,
          maxWidth,
          highRes: highRes,
        );
        // AVFoundation does not decode every container/codec in the library
        // (notably some MKV, AVI and MPEG variants). Recover with ffmpeg when
        // the native extractor cannot produce a frame.
        if (native != null || !Platform.isMacOS) return native;
        return _generateWithFfmpeg(
          mediaId,
          localPath,
          maxWidth,
          highRes: highRes,
        );
      });
    } catch (e) {
      debugPrint('thumb: skipped $mediaId: $e');
      return null;
    }
  }

  static Future<File?> _restoreLegacyThumbnail(
    String mediaId,
    File output,
  ) async {
    final candidates = await legacyCacheFilesFor(mediaId);
    for (final candidate in candidates.reversed) {
      if (!candidate.path.endsWith('.jpg') || !await candidate.exists()) {
        continue;
      }
      try {
        final bytes = await candidate.readAsBytes();
        if (img.decodeImage(bytes) == null) continue;
        await output.writeAsBytes(bytes, flush: true);
        final oldSidecar = File('${candidate.path}.txt');
        if (await oldSidecar.exists()) {
          await File(
            '${output.path}.txt',
          ).writeAsBytes(await oldSidecar.readAsBytes(), flush: true);
        }
        return output;
      } catch (_) {
        // Continue to an older usable cache.
      }
    }
    return null;
  }

  static Future<File?> _extractEmbeddedArtwork(
    String mediaId,
    String localPath,
    int maxWidth, {
    required bool highRes,
  }) async {
    final extension = localPath.toLowerCase().split('?').first;
    if (!(extension.endsWith('.mp4') ||
        extension.endsWith('.m4v') ||
        extension.endsWith('.mov') ||
        extension.endsWith('.webm') ||
        extension.endsWith('.mkv'))) {
      return null;
    }
    Directory? scratchDirectory;
    try {
      final probe = await FFprobeKit.executeWithArguments([
        '-v',
        'error',
        '-show_entries',
        'stream=index,codec_type:stream_disposition=attached_pic:stream_tags=filename,mimetype',
        '-of',
        'json',
        localPath,
      ]);
      if (!ReturnCode.isSuccess(await probe.getReturnCode())) return null;
      final parsed = jsonDecode(await probe.getOutput() ?? '') as Map;
      final streams = parsed['streams'];
      if (streams is! List) return null;
      int? coverStream;
      int? attachmentIndex;
      var attachmentOrdinal = 0;
      for (final stream in streams.whereType<Map>()) {
        final disposition = stream['disposition'];
        if (disposition is Map && disposition['attached_pic'] == 1) {
          coverStream = (stream['index'] as num?)?.toInt();
          if (coverStream != null) break;
        }
        if (stream['codec_type'] == 'attachment') {
          final tags = stream['tags'];
          final mime = tags is Map ? '${tags['mimetype'] ?? ''}' : '';
          if (mime.toLowerCase().startsWith('image/')) {
            attachmentIndex = attachmentOrdinal;
            break;
          }
          attachmentOrdinal++;
        }
      }
      if (coverStream == null && attachmentIndex == null) return null;

      final output = await cacheFileFor(mediaId, highRes: highRes);
      await output.parent.create(recursive: true);
      final List<String> arguments;
      File? rawAttachment;
      if (coverStream != null) {
        arguments = [
          '-v',
          'error',
          '-y',
          '-i',
          localPath,
          '-map',
          '0:$coverStream',
          '-frames:v',
          '1',
          '-vf',
          'scale=$maxWidth:-2',
          output.path,
        ];
      } else {
        scratchDirectory = await Directory.systemTemp.createTemp(
          'yureru-embedded-art-',
        );
        rawAttachment = File('${scratchDirectory.path}/cover.bin');
        arguments = [
          '-v',
          'error',
          '-dump_attachment:t:$attachmentIndex',
          rawAttachment.path,
          '-i',
          localPath,
          '-f',
          'null',
          '-',
        ];
      }
      final extraction = await FFmpegKit.executeWithArguments(arguments);
      if (rawAttachment != null &&
          ReturnCode.isSuccess(await extraction.getReturnCode()) &&
          await rawAttachment.exists()) {
        final decoded = img.decodeImage(await rawAttachment.readAsBytes());
        if (decoded != null) {
          final resized = decoded.width > maxWidth
              ? img.copyResize(
                  decoded,
                  width: maxWidth,
                  interpolation: img.Interpolation.average,
                )
              : decoded;
          await output.writeAsBytes(img.encodeJpg(resized, quality: 88));
        }
      }
      if (!ReturnCode.isSuccess(await extraction.getReturnCode()) ||
          !await output.exists() ||
          await output.length() == 0) {
        if (await output.exists()) await output.delete();
        return null;
      }
      // Embedded art is static; remove stale generated-frame seek metadata.
      final sidecar = File('${output.path}.txt');
      if (await sidecar.exists()) await sidecar.delete();
      return output;
    } catch (error) {
      debugPrint('thumb: embedded art unavailable for $mediaId: $error');
      return null;
    } finally {
      try {
        await scratchDirectory?.delete(recursive: true);
      } catch (_) {}
    }
  }

  static bool _isWebm(String path) =>
      path.toLowerCase().split('?').first.endsWith('.webm');

  static Future<File?> _generateWithFfmpeg(
    String mediaId,
    String localPath,
    int maxWidth, {
    required bool highRes,
  }) async {
    final out = await cacheFileFor(mediaId, highRes: highRes);
    await out.parent.create(recursive: true);
    final scratch = await Directory.systemTemp.createTemp('yureru-thumb-');
    try {
      Uint8List? bestFrame;
      var bestScore = double.negativeInfinity;
      var bestTime = 0;
      for (final seconds in const [0, 0.5, 1, 2, 4, 8, 12]) {
        final label = seconds.toString().replaceAll('.', '_');
        final frame = File('${scratch.path}/frame-$label.jpg');
        try {
          final session = await FFmpegKit.executeWithArguments([
            '-v',
            'error',
            '-y',
            '-ss',
            seconds.toString(),
            '-i',
            localPath,
            '-frames:v',
            '1',
            '-vf',
            'scale=$maxWidth:-2',
            '-q:v',
            '3',
            frame.path,
          ]).timeout(const Duration(seconds: 12));
          if (!ReturnCode.isSuccess(await session.getReturnCode()) ||
              !await frame.exists()) {
            continue;
          }
          final bytes = await frame.readAsBytes();
          final score = _frameScore(bytes);
          if (score != null && score > bestScore) {
            bestFrame = bytes;
            bestScore = score;
            bestTime = (seconds * 1000).round();
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
