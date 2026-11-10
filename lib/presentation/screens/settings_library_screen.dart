import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_state.dart';
import '../../domain/models.dart';
import '../i18n.dart';
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
            leading: const Icon(Icons.storage),
            title: Text(ref.tr('storage')),
            onTap: () => _storage(context, ref),
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
