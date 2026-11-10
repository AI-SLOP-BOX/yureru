import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models.dart';
import '../library/library_notifier.dart';

class RestoredLibraryBackup {
  final List<MediaItem> media;
  final List<Playlist> playlists;

  const RestoredLibraryBackup({required this.media, required this.playlists});
}

/// Portable library backup. Media files are optional; metadata, artwork,
/// thumbnails and lyrics are always included when their files are available.
class LibraryBackupService {
  static const _manifestName = 'yureru-backup.json';
  static const _backupVersion = 1;
  static const _maxManifestBytes = 64 * 1024 * 1024;
  static const _maxRecords = 100000;
  static const _secretPreferenceFragments = [
    'server.access_key',
    'server.pairing_code',
    'client.last_code',
    'client.last_address',
  ];

  Future<File> createBackup(
    LibraryState state, {
    required bool includeMedia,
  }) async {
    final temp = await getTemporaryDirectory();
    final zip = File(
      '${temp.path}/yureru_backup_${DateTime.now().microsecondsSinceEpoch}.zip',
    );
    final references = <String, Map<String, String>>{};
    final payloadFiles = <String, File>{};
    var nextFile = 0;

    String? storePath(String? value, String category) {
      if (value == null || value.isEmpty || _isRemote(value)) return value;
      final file = File(value);
      if (!file.existsSync()) return value;
      final key = 'f${nextFile++}';
      references[key] = {
        'category': category,
        'name': value.split(RegExp(r'[/\\]')).last,
      };
      payloadFiles[key] = file;
      return 'backupfile:$key';
    }

    final media = <Map<String, Object?>>[];
    for (final item in state.savedMedia) {
      final json = Map<String, Object?>.from(item.toJson());
      if (includeMedia) {
        json['localPath'] = storePath(item.localPath, 'media');
      }
      for (final field in const [
        'artworkPath',
        'thumbnailPath',
        'lyricsPath',
        'translatedLyricsPath',
        'videoLyricsPath',
        'artworkLyricsPath',
        'artworkAudioPath',
      ]) {
        final value = json[field] as String?;
        final category = switch (field) {
          'artworkPath' => 'artwork',
          'thumbnailPath' => 'thumbnail',
          'artworkAudioPath' => 'audio',
          _ => 'lyrics',
        };
        json[field] = storePath(value, category);
      }
      media.add(json);
    }

    final playlists = <Map<String, Object?>>[];
    for (final playlist in state.playlists) {
      final json = Map<String, Object?>.from(playlist.toJson());
      json['artworkPath'] = storePath(playlist.artworkPath, 'artwork');
      playlists.add(json);
    }

    final preferences = await SharedPreferences.getInstance();
    final settingValues = <String, Object?>{};
    for (final key in preferences.getKeys()) {
      if (!_isRestorablePreferenceKey(key)) continue;
      final value = preferences.get(key);
      if (value is String ||
          value is bool ||
          value is int ||
          value is double ||
          value is List<String>) {
        settingValues[key] = value;
      }
    }

    final manifest = {
      'format': 'yureru-library-backup',
      'version': _backupVersion,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'mediaIncluded': includeMedia,
      'media': media,
      'playlists': playlists,
      'preferences': settingValues,
      'files': references,
    };
    final scratch = File(
      '${temp.path}/yureru_manifest_${DateTime.now().microsecondsSinceEpoch}.json',
    );
    await scratch.writeAsString(jsonEncode(manifest), flush: true);
    final encoder = ZipFileEncoder()..create(zip.path, level: 0);
    try {
      await encoder.addFile(scratch, _manifestName, 0);
      for (final entry in payloadFiles.entries) {
        await encoder.addFile(entry.value, 'files/${entry.key}', 0);
      }
      await encoder.close();
      return zip;
    } catch (_) {
      await encoder.close();
      if (await zip.exists()) await zip.delete();
      rethrow;
    } finally {
      if (await scratch.exists()) await scratch.delete();
    }
  }

  Future<RestoredLibraryBackup> restoreBackup(String zipPath) async {
    final input = InputFileStream(zipPath);
    try {
      final archive = ZipDecoder().decodeStream(input);
      return await _restoreArchive(archive);
    } finally {
      input.closeSync();
    }
  }

  Future<RestoredLibraryBackup> _restoreArchive(Archive archive) async {
    final manifestFile = archive.find(_manifestName);
    if (manifestFile == null || !manifestFile.isFile) {
      throw const FormatException('Not a Yureru backup.');
    }
    if (manifestFile.size > _maxManifestBytes) {
      throw const FormatException('Backup manifest is too large.');
    }
    final decoded = jsonDecode(utf8.decode(manifestFile.readBytes() ?? []));
    if (decoded is! Map ||
        decoded['format'] != 'yureru-library-backup' ||
        decoded['version'] != _backupVersion ||
        decoded['media'] is! List ||
        decoded['playlists'] is! List) {
      throw const FormatException('Unsupported Yureru backup.');
    }
    final mediaEntries = decoded['media'] as List;
    final playlistEntries = decoded['playlists'] as List;
    if (mediaEntries.length > _maxRecords ||
        playlistEntries.length > _maxRecords) {
      throw const FormatException('Backup contains too many records.');
    }

    final docs = await getApplicationDocumentsDirectory();
    final files = decoded['files'] is Map
        ? Map<String, dynamic>.from(decoded['files'] as Map)
        : <String, dynamic>{};
    if (files.length > _maxRecords) {
      throw const FormatException('Backup contains too many files.');
    }
    void validateReference(Object? value) {
      if (value is! String || !value.startsWith('backupfile:')) return;
      final key = value.substring('backupfile:'.length);
      if (!files.containsKey(key)) {
        throw const FormatException('Backup references a missing file.');
      }
    }

    for (final raw in mediaEntries) {
      if (raw is! Map) {
        throw const FormatException('Backup contains invalid media data.');
      }
      for (final key in const [
        'localPath',
        'artworkPath',
        'thumbnailPath',
        'lyricsPath',
        'translatedLyricsPath',
        'videoLyricsPath',
        'artworkLyricsPath',
        'artworkAudioPath',
      ]) {
        validateReference(raw[key]);
      }
    }
    for (final raw in playlistEntries) {
      if (raw is! Map) {
        throw const FormatException('Backup contains invalid playlist data.');
      }
      validateReference(raw['artworkPath']);
    }
    // Validate all referenced archive members before writing any files.
    for (final entry in files.entries) {
      if (!RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(entry.key)) {
        throw const FormatException('Backup contains an invalid file key.');
      }
      final details = entry.value;
      if (details is! Map || details['category'] is! String) {
        throw const FormatException('Backup contains invalid file metadata.');
      }
      if (!const {
        'media',
        'artwork',
        'thumbnail',
        'lyrics',
        'audio',
      }.contains(details['category'])) {
        throw const FormatException('Backup contains an unknown file type.');
      }
      final archiveFile = archive.find('files/${entry.key}');
      if (archiveFile == null || !archiveFile.isFile) {
        throw const FormatException('Backup is missing a media file.');
      }
    }
    final restoredPaths = <String, String>{};
    for (final entry in files.entries) {
      final details = entry.value;
      if (details is! Map) {
        throw const FormatException('Backup contains invalid file metadata.');
      }
      final category = details['category']?.toString() ?? 'media';
      final originalName = details['name']?.toString() ?? entry.key;
      final safeName = originalName
          .split(RegExp(r'[/\\]'))
          .last
          .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final boundedName = safeName.length > 120
          ? safeName.substring(safeName.length - 120)
          : safeName;
      final folder = switch (category) {
        'artwork' => 'yureru_artwork',
        'thumbnail' => 'yureru_thumbnails',
        'lyrics' => 'yureru_lyrics',
        'audio' => 'yureru_audio_sources',
        _ => 'yureru_media',
      };
      final directory = Directory('${docs.path}/$folder');
      await directory.create(recursive: true);
      final target = File(
        '${directory.path}/restore_${DateTime.now().microsecondsSinceEpoch}_${entry.key}_$boundedName',
      );
      final archiveFile = archive.find('files/${entry.key}')!;
      final output = OutputFileStream(target.path);
      try {
        archiveFile.writeContent(output);
      } finally {
        output.closeSync();
      }
      restoredPaths[entry.key] = target.path;
    }

    String? resolve(Object? value) {
      if (value is! String || !value.startsWith('backupfile:')) {
        return value as String?;
      }
      return restoredPaths[value.substring('backupfile:'.length)];
    }

    final media = <MediaItem>[];
    for (final raw in mediaEntries) {
      if (raw is! Map) continue;
      final json = Map<String, dynamic>.from(raw);
      for (final key in const [
        'localPath',
        'artworkPath',
        'thumbnailPath',
        'lyricsPath',
        'translatedLyricsPath',
        'videoLyricsPath',
        'artworkLyricsPath',
        'artworkAudioPath',
      ]) {
        json[key] = resolve(json[key]);
      }
      final path = json['localPath'];
      if (path is String && path.isNotEmpty) {
        media.add(MediaItem.fromJson(json));
      }
    }
    final playlists = <Playlist>[];
    for (final raw in playlistEntries) {
      if (raw is! Map) continue;
      final json = Map<String, dynamic>.from(raw);
      json['artworkPath'] = resolve(json['artworkPath']);
      playlists.add(Playlist.fromJson(json));
    }
    await _restorePreferences(decoded['preferences']);
    return RestoredLibraryBackup(media: media, playlists: playlists);
  }

  Future<void> _restorePreferences(Object? raw) async {
    if (raw is! Map) return;
    final preferences = await SharedPreferences.getInstance();
    for (final entry in raw.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String || !_isRestorablePreferenceKey(key)) continue;
      if (value is String) {
        await preferences.setString(key, value);
      } else if (value is bool) {
        await preferences.setBool(key, value);
      } else if (value is int) {
        await preferences.setInt(key, value);
      } else if (value is double) {
        await preferences.setDouble(key, value);
      } else if (value is List && value.every((item) => item is String)) {
        await preferences.setStringList(key, value.cast<String>());
      }
    }
  }

  bool _isRemote(String path) =>
      path.startsWith('http://') || path.startsWith('https://');

  bool _isRestorablePreferenceKey(String key) =>
      (key.startsWith('yureru_') ||
          key.startsWith('yureru.') ||
          key == 'preferred_player_view_mode') &&
      !_secretPreferenceFragments.any(key.contains);
}
