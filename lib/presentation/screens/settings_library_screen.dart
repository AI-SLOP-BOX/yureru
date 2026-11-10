import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_state.dart';
import '../../domain/models.dart';
import '../../data/importer.dart';
import '../../data/library_backup.dart';
import '../i18n.dart';
import 'duplicate_media_screen.dart';
import 'trash_screen.dart';
import '../widgets/app_svg_icon.dart';

Future<String?> _promptImportArtist(BuildContext context, WidgetRef ref) async {
  final controller = TextEditingController();
  try {
    return await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(ref.tr('import_artist_title')),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: ref.tr('metadata_artist'),
            hintText: ref.tr('import_artist_hint'),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(ref.tr('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, ''),
            child: Text(ref.tr('import_without_artist')),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: Text(ref.tr('import_artist_continue')),
          ),
        ],
      ),
    );
  } finally {
    controller.dispose();
  }
}

Future<String> _storageText(List<MediaItem> media, String languageCode) async {
  int bytes = 0;
  for (final m in media) {
    try {
      bytes += await File(m.localPath).length();
    } catch (_) {}
  }
  return '${formatVideoCount(media.length, languageCode)}\n${(bytes / 1048576).toStringAsFixed(1)} MB';
}

class LibraryManagementScreen extends ConsumerWidget {
  const LibraryManagementScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(ref.tr('library'))),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.file_download),
            title: Text(ref.tr('import_video')),
            subtitle: Text(ref.tr('import_video_desc')),
            onTap: () => chooseImportMethod(context, ref),
          ),
          ListTile(
            leading: const AppSvgIcon('history'),
            title: Text(ref.tr('clear_playback_history')),
            onTap: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: Text(ref.tr('clear_playback_history')),
                  content: Text(ref.tr('clear_history_desc')),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: Text(ref.tr('cancel')),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: Text(ref.tr('clear')),
                    ),
                  ],
                ),
              );
              if (confirmed == true && context.mounted) {
                await ref.read(libraryProvider.notifier).clearPlaybackHistory();
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.link_rounded),
            title: Text(ref.tr('relink_missing_media')),
            subtitle: Text(ref.tr('relink_missing_media_desc')),
            onTap: () => _relinkMissing(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.fact_check_outlined),
            title: Text(ref.tr('check_library')),
            subtitle: Text(ref.tr('check_library_desc')),
            onTap: () => _checkLibrary(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.copy_all_rounded),
            title: Text(ref.tr('possible_duplicates')),
            subtitle: Text(ref.tr('possible_duplicates_desc')),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const DuplicateMediaScreen(),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: Text(ref.tr('recently_deleted')),
            subtitle: Text(ref.tr('trash_desc')),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const TrashScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.ios_share_rounded),
            title: Text(ref.tr('export_catalog')),
            subtitle: Text(ref.tr('export_catalog_desc')),
            onTap: () => _exportCatalog(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.storage),
            title: Text(ref.tr('storage')),
            onTap: () => _storage(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.backup_rounded),
            title: Text(ref.tr('backup_restore')),
            subtitle: Text(ref.tr('backup_restore_desc')),
            onTap: () => _backupRestore(context, ref),
          ),
        ],
      ),
    );
  }

  static Future<void> chooseImportMethod(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final method = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.video_file_outlined),
              title: Text(ref.tr('import_files_copy')),
              subtitle: Text(ref.tr('import_files_copy_desc')),
              onTap: () => Navigator.pop(sheetContext, 'files'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_copy_outlined),
              title: Text(ref.tr('import_folder')),
              subtitle: Text(ref.tr('import_folder_desc')),
              onTap: () => Navigator.pop(sheetContext, 'folder-copy'),
            ),
            ListTile(
              leading: const Icon(Icons.drive_folder_upload_outlined),
              title: Text(ref.tr('import_folder_referenced')),
              subtitle: Text(ref.tr('import_folder_referenced_desc')),
              onTap: () => Navigator.pop(sheetContext, 'folder-reference'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!context.mounted || method == null) return;
    switch (method) {
      case 'files':
        await importVideos(context, ref);
      case 'folder-copy':
        await importFolder(context, ref);
      case 'folder-reference':
        await importFolderReferenced(context, ref);
    }
  }

  static Future<void> importVideos(BuildContext context, WidgetRef ref) async {
    final importer = ref.read(importerProvider);
    try {
      final items = await _withProgressDialog(
        context,
        ref,
        (p) => importer.pickAndImport(
          skipSourcePaths: _existingSources(ref),
          requestArtistOverride: () => _promptImportArtist(context, ref),
          onProgress: p,
        ),
      );
      if (!context.mounted) return;
      if (items.isEmpty) {
        return;
      }
      await ref.read(libraryProvider.notifier).addMedia(items);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ref.tr('imported_count').replaceAll('{count}', '${items.length}'),
            ),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(ref.tr('import_failed'))));
      }
    }
  }

  static Future<void> importFolder(BuildContext context, WidgetRef ref) async {
    try {
      final importer = ref.read(importerProvider);
      final items = await _withProgressDialog(
        context,
        ref,
        (p) => importer.pickAndImportFolder(
          skipSourcePaths: _existingSources(ref),
          requestArtistOverride: () => _promptImportArtist(context, ref),
          onProgress: p,
        ),
      );
      if (!context.mounted) return;
      if (items == null) return;
      if (items.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(ref.tr('no_new_videos'))));
        }
        return;
      }
      await ref.read(libraryProvider.notifier).addMedia(items);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ref.tr('imported_count').replaceAll('{count}', '${items.length}'),
            ),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(ref.tr('import_failed'))));
      }
    }
  }

  static Future<void> importFolderReferenced(
    BuildContext context,
    WidgetRef ref,
  ) async {
    try {
      final importer = ref.read(importerProvider);
      final items = await _withProgressDialog(
        context,
        ref,
        (p) => importer.pickAndImportFolder(
          copyIntoApp: false,
          skipSourcePaths: _existingSources(ref),
          requestArtistOverride: () => _promptImportArtist(context, ref),
          onProgress: p,
        ),
      );
      if (!context.mounted) return;
      if (items == null) return;
      if (items.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(ref.tr('no_new_videos'))));
        }
        return;
      }
      await ref.read(libraryProvider.notifier).addMedia(items);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ref
                  .tr('referenced_count')
                  .replaceAll('{count}', '${items.length}'),
            ),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(ref.tr('reference_failed'))));
      }
    }
  }

  static Set<String> _existingSources(WidgetRef ref) => ref
      .read(libraryProvider)
      .media
      .map((m) => m.sourcePath)
      .whereType<String>()
      .toSet();

  static Future<void> _checkLibrary(BuildContext context, WidgetRef ref) async {
    final media = ref.read(libraryProvider).savedMedia;
    final missingMedia = <MediaItem>[];
    final missingImages = <MediaItem>[];
    final missingLyrics = <MediaItem>[];
    for (final item in media) {
      final isRemote =
          item.localPath.startsWith('http://') ||
          item.localPath.startsWith('https://');
      if (!isRemote && !await File(item.localPath).exists()) {
        missingMedia.add(item);
      }
      final imagePaths = [item.artworkPath, item.thumbnailPath]
          .whereType<String>()
          .where((path) => path.isNotEmpty && !_isRemotePath(path));
      if (imagePaths.any((path) => !File(path).existsSync())) {
        missingImages.add(item);
      }
      final lyricPaths = [
        item.lyricsPath,
        item.translatedLyricsPath,
        item.videoLyricsPath,
        item.artworkLyricsPath,
      ].whereType<String>().where((path) => path.isNotEmpty);
      if (lyricPaths.any((path) => !File(path).existsSync())) {
        missingLyrics.add(item);
      }
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(ref.tr('check_library')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              ref
                  .tr('check_library_summary')
                  .replaceAll('{count}', '${media.length}'),
            ),
            const SizedBox(height: 12),
            _healthLine(ref.tr('missing_media_files'), missingMedia.length),
            _healthLine(ref.tr('missing_image_files'), missingImages.length),
            _healthLine(ref.tr('missing_lyrics_files'), missingLyrics.length),
          ],
        ),
        actions: [
          if (missingMedia.isNotEmpty)
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                unawaited(_relinkMissing(context, ref));
              },
              child: Text(ref.tr('relink_missing_media')),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(ref.tr('done')),
          ),
        ],
      ),
    );
  }

  static Widget _healthLine(String label, int count) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text('$count'),
      ],
    ),
  );

  static bool _isRemotePath(String path) =>
      path.startsWith('http://') || path.startsWith('https://');

  static Future<void> _exportCatalog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final format = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.data_object_rounded),
              title: const Text('JSON'),
              onTap: () => Navigator.pop(sheetContext, 'json'),
            ),
            ListTile(
              leading: const Icon(Icons.table_chart_outlined),
              title: const Text('CSV'),
              onTap: () => Navigator.pop(sheetContext, 'csv'),
            ),
          ],
        ),
      ),
    );
    if (format == null || !context.mounted) return;
    final state = ref.read(libraryProvider);
    final content = format == 'json' ? _catalogJson(state) : _catalogCsv(state);
    final bytes = utf8.encode(content);
    final isMobile = Platform.isIOS || Platform.isAndroid;
    final target = await FilePicker.platform.saveFile(
      dialogTitle: ref.tr('export_catalog'),
      fileName: 'Yureru-library.$format',
      type: FileType.custom,
      allowedExtensions: [format],
      bytes: isMobile ? bytes : null,
    );
    if (target == null || !context.mounted) return;
    if (!isMobile) await File(target).writeAsBytes(bytes, flush: true);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(ref.tr('catalog_exported'))));
    }
  }

  static String _catalogJson(LibraryState state) =>
      const JsonEncoder.withIndent('  ').convert({
        'format': 'yureru-library-catalog',
        'version': 1,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
        'media': [
          for (final item in state.savedMedia)
            {
              'id': item.id,
              'title': item.title,
              'artist': item.artist,
              'album': item.album,
              'albumArtist': item.albumArtist,
              'trackNumber': item.trackNumber,
              'discNumber': item.discNumber,
              'durationMs': item.durationMs,
              'playCount': item.playCount,
              'playCountsByDay': item.playCountsByDay,
              'lastPlayedAt': item.lastPlayedAt?.toIso8601String(),
            },
        ],
        'playlists': [
          for (final playlist in state.playlists)
            {
              'id': playlist.id,
              'name': playlist.name,
              'mediaIds': playlist.mediaIds,
              'createdAt': playlist.createdAt.toIso8601String(),
            },
        ],
      });

  static String _catalogCsv(LibraryState state) {
    String cell(Object? value) {
      final text = value?.toString() ?? '';
      return '"${text.replaceAll('"', '""')}"';
    }

    final rows = <List<Object?>>[
      [
        'ID',
        'Title',
        'Artist',
        'Album',
        'Album artist',
        'Disc',
        'Track',
        'Duration (ms)',
        'Play count',
        'Last played',
        'Playlists',
      ],
      for (final item in state.savedMedia)
        [
          item.id,
          item.title,
          item.artist,
          item.album,
          item.albumArtist,
          item.discNumber,
          item.trackNumber,
          item.durationMs,
          item.playCount,
          item.lastPlayedAt?.toIso8601String(),
          state.playlists
              .where((playlist) => playlist.mediaIds.contains(item.id))
              .map((playlist) => playlist.name)
              .join(' | '),
        ],
    ];
    return rows.map((row) => row.map(cell).join(',')).join('\r\n');
  }

  static Future<void> _relinkMissing(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final state = ref.read(libraryProvider);
    var missing = <MediaItem>[];
    for (final item in state.savedMedia) {
      if (item.localPath.startsWith('http://') ||
          item.localPath.startsWith('https://')) {
        continue;
      }
      if (!await File(item.localPath).exists()) missing.add(item);
    }
    if (!context.mounted) return;
    if (missing.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(ref.tr('no_missing_media'))));
      return;
    }

    String baseName(MediaItem item) {
      final path = item.sourcePath ?? item.localPath;
      return path.split(RegExp(r'[/\\]')).last.toLowerCase();
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(ref.tr('relink_missing_media')),
          content: SizedBox(
            width: 560,
            height: MediaQuery.sizeOf(context).height * .62,
            child: Column(
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final folder = await FilePicker.platform.getDirectoryPath(
                        dialogTitle: ref.tr('choose_media_folder'),
                      );
                      if (folder == null) return;
                      final candidates = await collectMediaPaths(
                        Directory(folder),
                      );
                      final byName = <String, List<String>>{};
                      for (final path in candidates) {
                        byName
                            .putIfAbsent(
                              path.split(RegExp(r'[/\\]')).last.toLowerCase(),
                              () => [],
                            )
                            .add(path);
                      }
                      final repaired = <String>{};
                      for (final item in missing) {
                        final matches = byName[baseName(item)];
                        if (matches?.length == 1) {
                          await ref
                              .read(libraryProvider.notifier)
                              .relinkMediaFile(item.id, matches!.single);
                          repaired.add(item.id);
                        }
                      }
                      setDialogState(() {
                        missing.removeWhere(
                          (item) => repaired.contains(item.id),
                        );
                      });
                      if (repaired.isEmpty && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(ref.tr('no_media_auto_matched')),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.folder_open_rounded),
                    label: Text(ref.tr('scan_for_media_folder')),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    itemCount: missing.length,
                    itemBuilder: (context, index) {
                      final item = missing[index];
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          baseName(item),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          tooltip: ref.tr('locate_file'),
                          icon: const Icon(Icons.search_rounded),
                          onPressed: () async {
                            final picked = await FilePicker.platform.pickFiles(
                              type: FileType.custom,
                              allowedExtensions: [
                                ...videoExtensions,
                                ...audioExtensions,
                              ],
                            );
                            final files = picked?.files;
                            final path = files == null || files.isEmpty
                                ? null
                                : files.first.path;
                            if (path == null) return;
                            await ref
                                .read(libraryProvider.notifier)
                                .relinkMediaFile(item.id, path);
                            setDialogState(() => missing.removeAt(index));
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(ref.tr('done')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _storage(BuildContext context, WidgetRef ref) async {
    final media = List.of(ref.read(libraryProvider).media);
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(ref.tr('storage')),
        content: FutureBuilder<String>(
          future: _storageText(media, ref.read(activeLanguageCodeProvider)),
          builder: (c, s) => Text(s.data ?? ref.tr('calculating')),
        ),
      ),
    );
  }

  static Future<void> _backupRestore(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.file_upload_outlined),
              title: Text(ref.tr('create_backup')),
              subtitle: Text(ref.tr('create_backup_desc')),
              onTap: () => Navigator.pop(sheetContext, 'create'),
            ),
            ListTile(
              leading: const Icon(Icons.file_download_outlined),
              title: Text(ref.tr('restore_backup')),
              subtitle: Text(ref.tr('restore_backup_desc')),
              onTap: () => Navigator.pop(sheetContext, 'restore'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || action == null) return;
    if (action == 'create') {
      await _createBackup(context, ref);
    } else {
      await _restoreBackup(context, ref);
    }
  }

  static Future<void> _createBackup(BuildContext context, WidgetRef ref) async {
    var includeMedia = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(ref.tr('create_backup')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(ref.tr('backup_contents_hint')),
              if (!includeMedia) ...[
                const SizedBox(height: 8),
                Text(ref.tr('backup_without_media_note')),
              ],
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(ref.tr('backup_include_media')),
                subtitle: Text(ref.tr('backup_include_media_desc')),
                value: includeMedia,
                onChanged: (value) => setState(() => includeMedia = value),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(ref.tr('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(ref.tr('create_backup')),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return;
    File? temporary;
    try {
      temporary = await LibraryBackupService().createBackup(
        ref.read(libraryProvider),
        includeMedia: includeMedia,
      );
      final isMobile = Platform.isIOS || Platform.isAndroid;
      if (isMobile && await temporary.length() > 256 * 1024 * 1024) {
        throw StateError(ref.tr('backup_mobile_size_limit'));
      }
      final target = await FilePicker.platform.saveFile(
        dialogTitle: ref.tr('create_backup'),
        fileName: 'Yureru-backup.zip',
        type: FileType.custom,
        allowedExtensions: const ['zip'],
        bytes: isMobile ? await temporary.readAsBytes() : null,
      );
      if (target == null) return;
      if (!isMobile) {
        await temporary.openRead().pipe(File(target).openWrite());
      }
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(ref.tr('backup_created'))));
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${ref.tr('backup_failed')}: $error',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }
    } finally {
      if (temporary != null && await temporary.exists()) {
        await temporary.delete();
      }
    }
  }

  static Future<void> _restoreBackup(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    final selectedFiles = picked?.files;
    final path = selectedFiles == null || selectedFiles.isEmpty
        ? null
        : selectedFiles.first.path;
    if (path == null || !context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(ref.tr('restore_backup')),
        content: Text(ref.tr('restore_backup_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(ref.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(ref.tr('restore_backup')),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      final backup = await LibraryBackupService().restoreBackup(path);
      await ref
          .read(libraryProvider.notifier)
          .mergeBackup(media: backup.media, playlists: backup.playlists);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ref
                  .tr('backup_restored')
                  .replaceAll('{count}', '${backup.media.length}'),
            ),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${ref.tr('backup_failed')}: $error',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      }
    }
  }
}

/// Runs [run] while showing a blocking progress dialog, but only if the
/// job actually takes a while: the dialog arms on the first progress event
/// (the picker phase reports nothing) and appears after 400ms. Fast
/// imports never flash a dialog.
Future<T> _withProgressDialog<T>(
  BuildContext context,
  WidgetRef ref,
  Future<T> Function(void Function(int done, int total)) run,
) async {
  final progress = ValueNotifier<(int, int)>((0, 0));
  var dialogOpen = false;
  Timer? timer;
  void arm() {
    timer ??= Timer(const Duration(milliseconds: 400), () {
      if (!dialogOpen && context.mounted) {
        dialogOpen = true;
        unawaited(
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => AlertDialog(
              title: Text(ref.tr('importing')),
              content: ValueListenableBuilder<(int, int)>(
                valueListenable: progress,
                builder: (_, v, _) {
                  final (done, total) = v;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (total <= 0)
                        const LinearProgressIndicator()
                      else
                        LinearProgressIndicator(value: done / total),
                      const SizedBox(height: 12),
                      Text(
                        total <= 0
                            ? ref.tr('scanning')
                            : '${ref.videosCount(done)} / ${ref.videosCount(total)}',
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      }
    });
  }

  try {
    return await run((done, total) {
      arm();
      progress.value = (done, total);
    });
  } finally {
    timer?.cancel();
    progress.dispose();
    try {
      if (dialogOpen && context.mounted) Navigator.of(context).pop();
    } catch (_) {}
  }
}
