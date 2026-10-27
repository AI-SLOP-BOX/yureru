import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_state.dart';
import '../../domain/models.dart';
import '../i18n.dart';
import 'imported_media_screen.dart';

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
    final lib = ref.watch(libraryProvider);
    return Scaffold(
      appBar: AppBar(title: Text(ref.tr('library_management'))),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.file_download),
            title: Text(ref.tr('import_video')),
            subtitle: Text(ref.tr('import_video_desc')),
            onTap: () => importVideos(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.folder_open),
            title: Text(ref.tr('import_folder')),
            subtitle: Text(ref.tr('import_folder_desc')),
            onTap: () => importFolder(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.video_library),
            title: Text(ref.tr('imported_media')),
            subtitle: Text(ref.videosCount(lib.savedMedia.length)),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ImportedMediaScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.storage),
            title: Text(ref.tr('storage')),
            onTap: () => _storage(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.folder),
            title: Text(ref.tr('import_folder_referenced')),
            subtitle: Text(ref.tr('import_folder_referenced_desc')),
            onTap: () => importFolderReferenced(context, ref),
          ),
        ],
      ),
    );
  }

  static Future<void> importVideos(BuildContext context, WidgetRef ref) async {
    debugPrint('import: onTap fired');
    final importer = ref.read(importerProvider);
    try {
      final items = await _withProgressDialog(
        context,
        ref,
        (p) => importer.pickAndImport(
          skipSourcePaths: _existingSources(ref),
          onProgress: p,
        ),
      );
      if (!context.mounted) return;
      if (items.isEmpty) {
        debugPrint('import: cancelled / nothing to add');
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
    } catch (e, s) {
      debugPrint('import: error $e\n$s');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${ref.tr('import_failed')}: $e')),
        );
      }
    }
  }

  static Future<void> importFolder(BuildContext context, WidgetRef ref) async {
    debugPrint('import: folder onTap fired');
    try {
      final importer = ref.read(importerProvider);
      final items = await _withProgressDialog(
        context,
        ref,
        (p) => importer.pickAndImportFolder(
          skipSourcePaths: _existingSources(ref),
          onProgress: p,
        ),
      );
      if (!context.mounted) return;
      if (items == null) {
        debugPrint('import: folder cancelled');
        return;
      }
      if (items.isEmpty) {
        debugPrint('import: folder has nothing new');
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
    } catch (e, s) {
      debugPrint('import: folder error $e\n$s');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${ref.tr('import_failed')}: $e')),
        );
      }
    }
  }

  static Future<void> importFolderReferenced(
    BuildContext context,
    WidgetRef ref,
  ) async {
    debugPrint('import: folder referenced onTap fired');
    try {
      final importer = ref.read(importerProvider);
      final items = await _withProgressDialog(
        context,
        ref,
        (p) => importer.pickAndImportFolder(
          copyIntoApp: false,
          skipSourcePaths: _existingSources(ref),
          onProgress: p,
        ),
      );
      if (!context.mounted) return;
      if (items == null) {
        debugPrint('import: referenced folder cancelled');
        return;
      }
      if (items.isEmpty) {
        debugPrint('import: referenced folder has nothing new');
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
    } catch (e, s) {
      debugPrint('import: referenced folder error $e\n$s');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${ref.tr('reference_failed')}: $e')),
        );
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
