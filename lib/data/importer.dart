import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
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

String _baseName(String path) => path.split(RegExp(r'[/\\]')).last;

bool isVideoPath(String path) {
  final name = _baseName(path);
  final dot = name.lastIndexOf('.');
  if (dot <= 0) return false;
  return videoExtensions.contains(name.substring(dot + 1).toLowerCase());
}

/// Recursively collect video files under [dir]; hidden entries are skipped.
Future<List<String>> collectVideoPaths(Directory dir) async {
  final out = <String>[];
  Future<void> walk(Directory d) async {
    List<FileSystemEntity> entries;
    try {
      entries = await d.list(followLinks: false).toList();
    } on FileSystemException catch (e) {
      debugPrint('import: unreadable dir skipped ${d.path}: $e');
      return;
    }
    for (final e in entries) {
      final name = _baseName(e.path);
      if (name.startsWith('.')) continue;
      if (e is Directory) {
        await walk(e);
      } else if (e is File && isVideoPath(e.path)) {
        out.add(e.path);
      } else if (e is Link && isVideoPath(e.path)) {
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
  /// Pick video files. Returns [] when cancelled.
  /// [onProgress] fires during the copy phase as (done, total); scan phase
  /// reports (0, 0) = indeterminate.
  Future<List<MediaItem>> pickAndImport({
    bool copyIntoApp = true,
    Set<String> skipSourcePaths = const {},
    void Function(int done, int total)? onProgress,
  }) async {
    debugPrint('import: picker open');
    final paths = await _pickVideoPaths();
    debugPrint('import: picked ${paths.length} path(s)');
    if (paths.isEmpty) return [];
    return _importPaths(
      paths,
      copyIntoApp: copyIntoApp,
      skipSourcePaths: skipSourcePaths,
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
      onProgress: onProgress,
    );
    return [...reused, ...imported];
  }

  /// Pick a folder and import every video inside it.
  /// Returns null when cancelled, [] when there is nothing new to import.
  Future<List<MediaItem>?> pickAndImportFolder({
    bool copyIntoApp = true,
    Set<String> skipSourcePaths = const {},
    void Function(int done, int total)? onProgress,
  }) async {
    debugPrint('import: folder picker open');
    final path = await _pickFolderPath();
    if (path == null) {
      debugPrint('import: folder cancelled');
      return null;
    }
    debugPrint('import: folder picked $path');
    return _importPaths(
      [path],
      copyIntoApp: copyIntoApp,
      skipSourcePaths: skipSourcePaths,
      onProgress: onProgress,
    );
  }

  Future<List<MediaItem>> _importPaths(
    List<String> paths, {
    required bool copyIntoApp,
    required Set<String> skipSourcePaths,
    void Function(int done, int total)? onProgress,
  }) async {
    onProgress?.call(0, 0);
    final files = <String>[];
    for (final p in paths) {
      if (await FileSystemEntity.isDirectory(p)) {
        files.addAll(await collectVideoPaths(Directory(p)));
      } else {
        // Single-file picks bypass folder scan: filter non-video here.
        if (!isVideoPath(p)) {
          debugPrint('import: skipped non-video file $p');
          continue;
        }
        files.add(p);
      }
    }
    final fresh = [
      for (final p in files)
        if (!skipSourcePaths.contains(p)) p,
    ];
    final skipped = files.length - fresh.length;
    if (skipped > 0) {
      debugPrint('import: skipped $skipped already-imported file(s)');
    }
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
          debugPrint('import: copy failed, skipped $src: $e');
          continue;
        }
      }
      out.add(
        MediaItem(
          title: title,
          artist: artist,
          localPath: dest,
          origin: copyIntoApp ? 'imported' : 'referenced',
          sourcePath: src,
        ),
      );
      onProgress?.call(out.length, fresh.length);
    }
    debugPrint('import: ready ${out.length} item(s), skipped $skipped');
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
      type: FileType.video,
      allowMultiple: true,
      withData: false,
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
      return await FilePicker.platform.getDirectoryPath(
        dialogTitle: '動画フォルダを選択',
      );
    } catch (e) {
      debugPrint('import: getDirectoryPath unavailable: $e');
      return null;
    }
  }

  static String _titleOf(String fileName) {
    final i = fileName.lastIndexOf('.');
    return i <= 0 ? fileName : fileName.substring(0, i);
  }

  /// Split "Artist - Title" file names (MV convention). Returns
  /// (title, artist); artist is null when the pattern doesn't apply.
  static (String, String?) _splitTitleArtist(String fileName) {
    final base = _titleOf(fileName);
    final sep = base.indexOf(' - ');
    if (sep <= 0) return (base, null);
    final artist = base.substring(0, sep).trim();
    final title = base.substring(sep + 3).trim();
    if (artist.isEmpty || title.isEmpty) return (base, null);
    return (title, artist);
  }
}
