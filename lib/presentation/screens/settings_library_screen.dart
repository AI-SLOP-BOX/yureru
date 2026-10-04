import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_state.dart';
import '../../domain/models.dart';
import '../../playback/playback_controller.dart';
import '../theme.dart';
import '../i18n.dart';
import '../widgets/thumb_image.dart';

Future<String> _storageText(List<MediaItem> media) async {
  int bytes = 0;
  for (final m in media) {
    try {
      bytes += await File(m.localPath).length();
    } catch (_) {}
  }
  return '${media.length}件\n${(bytes / 1048576).toStringAsFixed(1)} MB';
}

class LibraryManagementScreen extends ConsumerWidget {
  const LibraryManagementScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('ライブラリ管理')),
      body: ListView(children: [
        ListTile(leading: const Icon(Icons.file_download), title: const Text('動画をインポート'),
          subtitle: const Text('動画ファイルを選んでアプリ保存領域にコピーします'),
          onTap: () => _import(context, ref)),
        ListTile(leading: const Icon(Icons.folder_open), title: const Text('フォルダからインポート'),
          subtitle: const Text('フォルダの中の動画をまとめて取り込みます'),
          onTap: () => _importFolder(context, ref)),
        ListTile(leading: const Icon(Icons.video_library), title: const Text('インポート済みメディア'),
          subtitle: Text('${lib.media.length}件'),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ImportedMediaScreen()))),
        ListTile(leading: const Icon(Icons.storage), title: const Text('ストレージ'),
          onTap: () => _storage(context, ref)),
        ListTile(leading: const Icon(Icons.folder), title: const Text('フォルダを参照追加'),
          subtitle: const Text('動画をコピーせず、元のフォルダを参照して取り込みます（PC推奨）'),
          onTap: () => _importFolderReferenced(context, ref)),
        const Divider(color: Colors.white12, height: 24),
        ListTile(
          leading: const Icon(Icons.language_rounded),
          title: const Text('言語 (Language)'),
          subtitle: Text(
            ref.watch(languageProvider) == AppLanguage.system
                ? 'システム標準 (${ref.watch(activeLanguageCodeProvider)})'
                : ref.watch(languageProvider).label,
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<AppLanguage>(
                value: ref.watch(languageProvider),
                dropdownColor: const Color(0xFF1E1E28),
                borderRadius: BorderRadius.circular(12),
                style: const TextStyle(fontSize: 13, color: Colors.white),
                icon: const Icon(Icons.keyboard_arrow_down_rounded,
                    size: 18, color: Colors.white70),
                items: AppLanguage.values.map((l) {
                  return DropdownMenuItem(
                    value: l,
                    child: Text(l.label),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    ref.read(languageProvider.notifier).setLanguage(val);
                  }
                },
              ),
            ),
          ),
        ),
      ]),
    );
  }
  Future<void> _import(BuildContext context, WidgetRef ref) async {
    debugPrint('import: onTap fired');
    final importer = ref.read(importerProvider);
    try {
      final items = await _withProgressDialog(
        context,
        (p) => importer.pickAndImport(
            skipSourcePaths: _existingSources(ref), onProgress: p),
      );
      if (!context.mounted) return;
      if (items.isEmpty) { debugPrint('import: cancelled / nothing to add'); return; }
      await ref.read(libraryProvider.notifier).addMedia(items);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${items.length}本をインポートしました')));
    } catch (e, s) {
      debugPrint('import: error $e\n$s');
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('インポートに失敗しました: $e')));
    }
  }
  Future<void> _importFolder(BuildContext context, WidgetRef ref) async {
    debugPrint('import: folder onTap fired');
    try {
      final importer = ref.read(importerProvider);
      final items = await _withProgressDialog(
        context,
        (p) => importer.pickAndImportFolder(
            skipSourcePaths: _existingSources(ref), onProgress: p),
      );
      if (!context.mounted) return;
      if (items == null) { debugPrint('import: folder cancelled'); return; }
      if (items.isEmpty) {
        debugPrint('import: folder has nothing new');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('取り込める新しい動画が見つかりませんでした')));
        }
        return;
      }
      await ref.read(libraryProvider.notifier).addMedia(items);
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${items.length}本をインポートしました')));
    } catch (e, s) {
      debugPrint('import: folder error $e\n$s');
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('インポートに失敗しました: $e')));
    }
  }

  Future<void> _importFolderReferenced(BuildContext context, WidgetRef ref) async {
    debugPrint('import: folder referenced onTap fired');
    try {
      final importer = ref.read(importerProvider);
      final items = await _withProgressDialog(
        context,
        (p) => importer.pickAndImportFolder(
            copyIntoApp: false,
            skipSourcePaths: _existingSources(ref),
            onProgress: p),
      );
      if (!context.mounted) return;
      if (items == null) { debugPrint('import: referenced folder cancelled'); return; }
      if (items.isEmpty) {
        debugPrint('import: referenced folder has nothing new');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('取り込める新しい動画が見つかりませんでした')));
        }
        return;
      }
      await ref.read(libraryProvider.notifier).addMedia(items);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${items.length}本を参照追加しました（コピーなし）')));
      }
    } catch (e, s) {
      debugPrint('import: referenced folder error $e\n$s');
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('参照追加に失敗しました: $e')));
    }
  }
  Set<String> _existingSources(WidgetRef ref) => ref
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
        title: const Text('ストレージ'),
        content: FutureBuilder<String>(
          future: _storageText(media),
          builder: (c, s) => Text(s.data ?? '計算中...'),
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
  Future<T> Function(void Function(int done, int total)) run,
) async {
  final progress = ValueNotifier<(int, int)>((0, 0));
  var dialogOpen = false;
  Timer? timer;
  void arm() {
    timer ??= Timer(const Duration(milliseconds: 400), () {
      if (!dialogOpen && context.mounted) {
        dialogOpen = true;
        unawaited(showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: const Text('インポート中'),
            content: ValueListenableBuilder<(int, int)>(
              valueListenable: progress,
              builder: (_, v, _) {
                final (done, total) = v;
                return Column(mainAxisSize: MainAxisSize.min, children: [
                  if (total <= 0)
                    const LinearProgressIndicator()
                  else
                    LinearProgressIndicator(value: done / total),
                  const SizedBox(height: 12),
                  Text(total <= 0 ? 'スキャン中...' : '$done / $total 本'),
                ]);
              },
            ),
          ),
        ));
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

class ImportedMediaScreen extends ConsumerWidget {
  const ImportedMediaScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('インポート済みメディア')),
      body: lib.media.isEmpty
          ? const Center(child: Text('メディアがありません。「動画をインポート」から追加してください。'))
          : ListView.builder(itemCount: lib.media.length, itemBuilder: (c, i) {
              final m = lib.media[i];
              return Dismissible(key: ValueKey(m.id), direction: DismissDirection.endToStart,
                background: Container(color: Colors.red, alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 16), child: const Icon(Icons.delete, color: Colors.white)),
                onDismissed: (_) async {
                  await ref.read(playbackControllerProvider).handleMediaRemoved(m.id);
                  await ref.read(libraryProvider.notifier).removeMedia(m.id);
                },
                child: ListTile(
                    leading: ThumbImage(
                        seed: m.id,
                        mediaId: m.id,
                        localPath: m.localPath,
                        size: 40,
                        radius: 8),
                    title: Text(displayTitle(m.title)),
                  subtitle: Text(
                      m.origin == 'referenced' ? '参照' : 'インポート済み',
                      style: const TextStyle(fontSize: 12))));
            }),
    );
  }
}
