import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/return_code.dart';
import 'package:path_provider/path_provider.dart';

/// Creates a cached, square video track from jacket art and the active audio
/// file. Native system PiP APIs require a video track even when the picture is
/// intentionally static.
class PipArtworkMovie {
  static Future<String> prepare({
    required String mediaId,
    required String artworkPath,
    required String audioPath,
    int? trimEndMs,
    bool forceAac = false,
  }) async {
    final image = File(artworkPath);
    final audio = File(audioPath);
    if (!await image.exists() || !await audio.exists()) {
      throw StateError(
        'The jacket image or audio file is unavailable for PiP.',
      );
    }
    final imageStat = await image.stat();
    final audioStat = await audio.stat();
    final cacheDir = Directory(
      '${(await getTemporaryDirectory()).path}/yureru_pip_artwork',
    );
    await cacheDir.create(recursive: true);
    final safeId = mediaId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final baseName =
        '${safeId}_${imageStat.size}_'
        '${imageStat.modified.millisecondsSinceEpoch}_'
        '${audioStat.size}_${audioStat.modified.millisecondsSinceEpoch}_'
        '${trimEndMs ?? 0}_${forceAac ? 'aac' : 'copy'}';
    final output = File('${cacheDir.path}/$baseName.mp4');
    if (await output.exists() && await output.length() > 1024) {
      return output.path;
    }
    final partial = File('${output.path}.partial.mp4');
    if (await partial.exists()) await partial.delete();

    Future<bool> encode({required bool copyAudio}) async {
      final args = <String>[
        '-hide_banner',
        '-y',
        '-loop',
        '1',
        '-framerate',
        '1',
        '-i',
        image.path,
        '-i',
        audio.path,
        '-map',
        '0:v:0',
        '-map',
        '1:a:0?',
        '-sn',
        '-dn',
        '-vf',
        'scale=w=1280:h=1280:force_original_aspect_ratio=decrease:force_divisible_by=2',
        '-c:v',
        'h264_videotoolbox',
        '-b:v',
        '400k',
        '-pix_fmt',
        'yuv420p',
        '-r',
        '1',
        '-c:a',
        if (copyAudio) 'copy' else 'aac',
        if (!copyAudio) ...['-b:a', '160k'],
        if (trimEndMs != null && trimEndMs > 0) ...[
          '-t',
          (trimEndMs / 1000).toStringAsFixed(3),
        ],
        '-shortest',
        '-movflags',
        '+faststart',
        partial.path,
      ];
      final session = await FFmpegKit.executeWithArguments(args);
      final code = await session.getReturnCode();
      if (!ReturnCode.isSuccess(code)) return false;
      return await partial.exists() && await partial.length() > 1024;
    }

    try {
      // Stream-copy compatible audio first for a quick PiP launch. Some
      // formats cannot be muxed into MP4, so only then fall back to AAC.
      var success = !forceAac && await encode(copyAudio: true);
      if (!success) {
        if (await partial.exists()) await partial.delete();
        success = await encode(copyAudio: false);
      }
      if (!success) {
        throw StateError('Could not prepare the jacket image for system PiP.');
      }
      if (await output.exists()) await output.delete();
      await partial.rename(output.path);
      return output.path;
    } catch (_) {
      if (await partial.exists()) await partial.delete();
      rethrow;
    }
  }
}
