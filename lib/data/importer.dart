import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import '../domain/models.dart';

export '../platform/window_utils.dart' show toggleFullscreen;

/// Native macOS picker channel (see macos/Runner/MainFlutterWindow.swift).
const mediaPickerChannel = MethodChannel('yureru/media_picker');

/// Extensions treated as video when scanning folders (case-insensitive).
const videoExtensions = <String>{
  'mp4',
  'm4v',
  'mov',
  'mkv',
  'webm',
  'avi',
  'ts',
  'm2ts',
  'm2t',
  'mpg',
  'mpeg',
  'mpe',
  'flv',
  'wmv',
  '3gp',
  '3g2',
  'ogv',
  'vob',
  'divx',
  'f4v',
};
const audioExtensions = <String>{
  'mp3',
  'opus',
  'ogg',
  'oga',
  'm4a',
  'aac',
  'wav',
  'flac',
  'aiff',
  'aif',
  'alac',
  'caf',
};

String _baseName(String path) => path.split(RegExp(r'[/\\]')).last;

bool isVideoPath(String path) {
  final name = _baseName(path);
  final dot = name.lastIndexOf('.');
  if (dot <= 0) return false;
  return videoExtensions.contains(name.substring(dot + 1).toLowerCase());
}

bool isSupportedMediaPath(String path) {
  final name = _baseName(path);
  final dot = name.lastIndexOf('.');
  if (dot <= 0) return false;
  final ext = name.substring(dot + 1).toLowerCase();
  return videoExtensions.contains(ext) || audioExtensions.contains(ext);
}

/// Recursively collect video files under [dir]; hidden entries are skipped.
Future<List<String>> collectVideoPaths(Directory dir) async {
  return _collectPaths(dir, isVideoPath);
}

Future<List<String>> collectMediaPaths(Directory dir) async {
  return _collectPaths(dir, isSupportedMediaPath);
}

Future<List<String>> _collectPaths(
  Directory dir,
  bool Function(String) accepts,
) async {
  final out = <String>[];
  Future<void> walk(Directory d) async {
    List<FileSystemEntity> entries;
    try {
      entries = await d.list(followLinks: false).toList();
    } on FileSystemException {
      return;
    }
    for (final e in entries) {
      final name = _baseName(e.path);
      if (name.startsWith('.')) continue;
      if (e is Directory) {
        await walk(e);
      } else if (e is File && accepts(e.path)) {
        out.add(e.path);
      } else if (e is Link && accepts(e.path)) {
        // Symlinked video file: import the link target path.
        out.add(e.path);
      }
    }
  }

  await walk(dir);
  out.sort();
  return out;
}

/// File access layer. Mobile: copy into app-managed dir (imported).
/// PC future: reference folder without copying (origin='referenced').
class VideoImporter {
  /// Selects playable files without copying or registering them in the library.
  Future<List<MediaItem>> pickForPlayback() async {
    final paths = await _pickVideoPaths();
    final seen = <String>{};
    return [
      for (final path in paths)
        if (isSupportedMediaPath(path) && seen.add(path))
          MediaItem(
            title: _splitTitleArtist(_baseName(path)).$1,
            artist: _splitTitleArtist(_baseName(path)).$2,
            localPath: path,
            sourcePath: path,
            origin: 'temporary',
          ),
    ];
  }

  /// Pick video files. Returns [] when cancelled.
  /// [onProgress] fires during the copy phase as (done, total); scan phase
  /// reports (0, 0) = indeterminate.
  Future<List<MediaItem>> pickAndImport({
    bool copyIntoApp = true,
    Set<String> skipSourcePaths = const {},
    Future<String?> Function()? requestArtistOverride,
    void Function(int done, int total)? onProgress,
  }) async {
    final paths = await _pickVideoPaths();
    if (paths.isEmpty) return [];
    final artistOverride = await requestArtistOverride?.call();
    if (requestArtistOverride != null && artistOverride == null) return [];
    return _importPaths(
      paths,
      copyIntoApp: copyIntoApp,
      skipSourcePaths: skipSourcePaths,
      artistOverride: artistOverride,
      onProgress: onProgress,
    );
  }

  /// Pick videos for a playlist, reusing library entries when a selected path
  /// is already present and importing only new files.
  Future<List<MediaItem>> pickForPlaylist({
    required List<MediaItem> existingMedia,
    void Function(int done, int total)? onProgress,
  }) async {
    final paths = await _pickVideoPaths();
    if (paths.isEmpty) return [];

    final existingByPath = <String, MediaItem>{};
    for (final media in existingMedia) {
      if (media.sourcePath != null) existingByPath[media.sourcePath!] = media;
      existingByPath.putIfAbsent(media.localPath, () => media);
    }
    final reused = <MediaItem>[];
    final newPaths = <String>[];
    final seen = <String>{};
    for (final path in paths) {
      if (!seen.add(path)) continue;
      final existing = existingByPath[path];
      if (existing != null) {
        reused.add(existing);
      } else {
        newPaths.add(path);
      }
    }
    final imported = await _importPaths(
      newPaths,
      copyIntoApp: true,
      skipSourcePaths: const {},
      artistOverride: null,
      onProgress: onProgress,
    );
    return [...reused, ...imported];
  }

  /// Pick a folder and import supported audio and video files inside it.
  /// Returns null when cancelled, [] when there is nothing new to import.
  Future<List<MediaItem>?> pickAndImportFolder({
    bool copyIntoApp = true,
    Set<String> skipSourcePaths = const {},
    Future<String?> Function()? requestArtistOverride,
    void Function(int done, int total)? onProgress,
  }) async {
    final path = await _pickFolderPath();
    if (path == null) return null;
    final artistOverride = await requestArtistOverride?.call();
    if (requestArtistOverride != null && artistOverride == null) return null;
    return _importPaths(
      [path],
      copyIntoApp: copyIntoApp,
      skipSourcePaths: skipSourcePaths,
      artistOverride: artistOverride,
      onProgress: onProgress,
    );
  }

  Future<List<MediaItem>> _importPaths(
    List<String> paths, {
    required bool copyIntoApp,
    required Set<String> skipSourcePaths,
    String? artistOverride,
    void Function(int done, int total)? onProgress,
  }) async {
    onProgress?.call(0, 0);
    final files = <String>[];
    for (final p in paths) {
      if (await FileSystemEntity.isDirectory(p)) {
        files.addAll(await collectMediaPaths(Directory(p)));
      } else {
        // Single-file picks bypass folder scan: filter non-video here.
        if (!isSupportedMediaPath(p)) {
          continue;
        }
        files.add(p);
      }
    }
    final fresh = [
      for (final p in files)
        if (!skipSourcePaths.contains(p)) p,
    ];
    final out = <MediaItem>[];
    for (var i = 0; i < fresh.length; i++) {
      final src = fresh[i];
      final name = _baseName(src);
      final (title, artist) = _splitTitleArtist(name);
      String dest = src;
      if (copyIntoApp) {
        try {
          final dir = await getApplicationDocumentsDirectory();
          final lib = Directory('${dir.path}/yureru_media');
          if (!await lib.exists()) await lib.create(recursive: true);
          dest =
              '${lib.path}/${DateTime.now().microsecondsSinceEpoch}_${i}_$name';
          await File(src).copy(dest);
        } catch (e) {
          // One bad file must not abort the whole batch or orphan copies.
          continue;
        }
      }
      out.add(
        MediaItem(
          title: title,
          artist: artistOverride?.trim().isNotEmpty == true
              ? artistOverride!.trim()
              : artist,
          localPath: dest,
          origin: copyIntoApp ? 'imported' : 'referenced',
          sourcePath: src,
        ),
      );
      onProgress?.call(out.length, fresh.length);
    }
    return out;
  }

  /// macOS: NSOpenPanel sheet implemented natively (file_picker's runModal
  /// blocks the merged UI/platform thread and its panel can stay invisible).
  /// Other platforms: file_picker.
  Future<List<String>> _pickVideoPaths() async {
    if (Platform.isMacOS) {
      final paths = await mediaPickerChannel.invokeListMethod<String>(
        'pickVideos',
      );
      return paths?.whereType<String>().toList() ?? const [];
    }
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowMultiple: true,
      withData: false,
      allowedExtensions: [...videoExtensions, ...audioExtensions],
    );
    return res?.files.map((f) => f.path).whereType<String>().toList() ??
        const [];
  }

  /// Folder flow: native NSOpenPanel (macOS) / file_picker elsewhere.
  Future<String?> _pickFolderPath() async {
    if (Platform.isMacOS) {
      return mediaPickerChannel.invokeMethod<String>('pickFolder');
    }
    try {
      // Let the native picker supply its own localized folder-picker title.
      return await FilePicker.platform.getDirectoryPath();
    } catch (_) {
      return null;
    }
  }

  static String _titleOf(String fileName) {
    final i = fileName.lastIndexOf('.');
    return i <= 0 ? fileName : fileName.substring(0, i);
  }

  /// Split common title/artist filename patterns. A slash is treated as the
  /// strongest marker: "Title / Artist" or "Title／Artist". Keep supporting
  /// the existing "Artist - Title" MV convention as well.
  static (String, String?) _splitTitleArtist(String fileName) {
    final base = _titleOf(fileName);

    final asciiSlash = base.lastIndexOf('/');
    final fullWidthSlash = base.lastIndexOf('／');
    final slash = asciiSlash > fullWidthSlash ? asciiSlash : fullWidthSlash;
    if (slash > 0 && slash < base.length - 1) {
      final title = base.substring(0, slash).trim();
      final artist = base.substring(slash + 1).trim();
      if (title.isNotEmpty && artist.isNotEmpty) return (title, artist);
    }

    final sep = base.indexOf(' - ');
    if (sep <= 0) return (base, null);
    final artist = base.substring(0, sep).trim();
    final title = base.substring(sep + 3).trim();
    if (artist.isEmpty || title.isEmpty) return (base, null);
    return (title, artist);
  }
}
