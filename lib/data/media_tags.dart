import 'dart:convert';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/return_code.dart';
import 'package:path_provider/path_provider.dart';

class EmbeddedMediaTags {
  final String? title;
  final String? artist;
  final String? album;
  final String? albumArtist;
  final int? trackNumber;
  final int? discNumber;
  final int? durationMs;
  final int? coverStreamIndex;

  const EmbeddedMediaTags({
    this.title,
    this.artist,
    this.album,
    this.albumArtist,
    this.trackNumber,
    this.discNumber,
    this.durationMs,
    this.coverStreamIndex,
  });
}

/// Reads common ID3, Vorbis, MP4 and Matroska tags without decoding the media.
Future<EmbeddedMediaTags> readEmbeddedMediaTags(String path) async {
  try {
    final session = await FFprobeKit.executeWithArguments([
      '-v',
      'error',
      '-show_entries',
      'format=duration:format_tags:stream=index,codec_type:stream_disposition=attached_pic:stream_tags',
      '-of',
      'json',
      path,
    ]);
    if (!ReturnCode.isSuccess(await session.getReturnCode())) {
      return const EmbeddedMediaTags();
    }
    final decoded = jsonDecode(await session.getOutput() ?? '');
    if (decoded is! Map) return const EmbeddedMediaTags();
    final format = decoded['format'];
    final streams = decoded['streams'];
    int? coverStreamIndex;
    final tagMaps = <Map>[];
    if (format is Map && format['tags'] is Map) {
      tagMaps.add(format['tags'] as Map);
    }
    if (streams is List) {
      for (final stream in streams.whereType<Map>()) {
        if (stream['tags'] is Map) tagMaps.add(stream['tags'] as Map);
        final disposition = stream['disposition'];
        if (coverStreamIndex == null &&
            disposition is Map &&
            disposition['attached_pic'] == 1) {
          coverStreamIndex = (stream['index'] as num?)?.toInt();
        }
      }
    }
    final tags = <String, String>{};
    for (final map in tagMaps.reversed) {
      for (final entry in map.entries) {
        final value = entry.value?.toString().trim();
        if (value == null || value.isEmpty) continue;
        tags[_normalizeTag(entry.key.toString())] = value;
      }
    }
    String? valueFor(Iterable<String> names) {
      for (final name in names) {
        final value = tags[name];
        if (value != null && value.isNotEmpty) return value;
      }
      return null;
    }

    final duration = format is Map
        ? double.tryParse('${format['duration'] ?? ''}')
        : null;
    return EmbeddedMediaTags(
      title: valueFor(const ['title', 'name']),
      artist: valueFor(const ['artist', 'author', 'albumartist']),
      album: valueFor(const ['album', 'collection']),
      albumArtist: valueFor(const ['albumartist', 'album_artist']),
      trackNumber: _tagNumber(valueFor(const ['track', 'tracknumber'])),
      discNumber: _tagNumber(valueFor(const ['disc', 'discnumber'])),
      durationMs: duration == null || duration <= 0
          ? null
          : (duration * 1000).round(),
      coverStreamIndex: coverStreamIndex,
    );
  } catch (_) {
    return const EmbeddedMediaTags();
  }
}

Future<String?> extractEmbeddedCover({
  required String path,
  required String mediaId,
  required int? streamIndex,
}) async {
  if (streamIndex == null) return null;
  try {
    final docs = await getApplicationDocumentsDirectory();
    final directory = Directory('${docs.path}/yureru_artwork');
    await directory.create(recursive: true);
    final output = File('${directory.path}/$mediaId.jpg');
    final session = await FFmpegKit.executeWithArguments([
      '-v',
      'error',
      '-y',
      '-i',
      path,
      '-map',
      '0:$streamIndex',
      '-frames:v',
      '1',
      '-vf',
      'scale=1600:1600:force_original_aspect_ratio=decrease',
      '-q:v',
      '2',
      output.path,
    ]);
    if (!ReturnCode.isSuccess(await session.getReturnCode()) ||
        !await output.exists() ||
        await output.length() == 0) {
      return null;
    }
    return output.path;
  } catch (_) {
    return null;
  }
}

String _normalizeTag(String key) =>
    key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

int? _tagNumber(String? value) {
  if (value == null) return null;
  final parsed = int.tryParse(value.split('/').first.trim());
  return parsed != null && parsed > 0 ? parsed : null;
}
