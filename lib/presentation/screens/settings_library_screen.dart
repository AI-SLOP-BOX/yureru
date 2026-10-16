import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_state.dart';
import '../../domain/creator_names.dart';
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
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.file_download),
            title: const Text('動画をインポート'),
            subtitle: const Text('動画ファイルを選んでアプリ保存領域にコピーします'),
            onTap: () => _import(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.folder_open),
            title: const Text('フォルダからインポート'),
            subtitle: const Text('フォルダの中の動画をまとめて取り込みます'),
            onTap: () => _importFolder(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.video_library),
            title: const Text('インポート済みメディア'),
            subtitle: Text('${lib.media.length}件'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ImportedMediaScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.storage),
            title: const Text('ストレージ'),
            onTap: () => _storage(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.folder),
            title: const Text('フォルダを参照追加'),
            subtitle: const Text('動画をコピーせず、元のフォルダを参照して取り込みます（PC推奨）'),
            onTap: () => _importFolderReferenced(context, ref),
          ),
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
                  icon: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: Colors.white70,
                  ),
                  items: AppLanguage.values.map((l) {
                    return DropdownMenuItem(value: l, child: Text(l.label));
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
        ],
      ),
    );
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    debugPrint('import: onTap fired');
    final importer = ref.read(importerProvider);
    try {
      final items = await _withProgressDialog(
        context,
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
      if (context.mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${items.length}本をインポートしました')));
    } catch (e, s) {
      debugPrint('import: error $e\n$s');
      if (context.mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('インポートに失敗しました: $e')));
    }
  }

  Future<void> _importFolder(BuildContext context, WidgetRef ref) async {
    debugPrint('import: folder onTap fired');
    try {
      final importer = ref.read(importerProvider);
      final items = await _withProgressDialog(
        context,
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('取り込める新しい動画が見つかりませんでした')),
          );
        }
        return;
      }
      await ref.read(libraryProvider.notifier).addMedia(items);
      if (context.mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${items.length}本をインポートしました')));
    } catch (e, s) {
      debugPrint('import: folder error $e\n$s');
      if (context.mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('インポートに失敗しました: $e')));
    }
  }

  Future<void> _importFolderReferenced(
    BuildContext context,
    WidgetRef ref,
  ) async {
    debugPrint('import: folder referenced onTap fired');
    try {
      final importer = ref.read(importerProvider);
      final items = await _withProgressDialog(
        context,
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('取り込める新しい動画が見つかりませんでした')),
          );
        }
        return;
      }
      await ref.read(libraryProvider.notifier).addMedia(items);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${items.length}本を参照追加しました（コピーなし）')),
        );
      }
    } catch (e, s) {
      debugPrint('import: referenced folder error $e\n$s');
      if (context.mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('参照追加に失敗しました: $e')));
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
        unawaited(
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => AlertDialog(
              title: const Text('インポート中'),
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
                      Text(total <= 0 ? 'スキャン中...' : '$done / $total 本'),
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

class ImportedMediaScreen extends ConsumerStatefulWidget {
  const ImportedMediaScreen({super.key});

  @override
  ConsumerState<ImportedMediaScreen> createState() =>
      _ImportedMediaScreenState();
}

class _ImportedMediaScreenState extends ConsumerState<ImportedMediaScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  bool _selecting = false;
  final Set<String> _selectedIds = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lib = ref.watch(libraryProvider);
    final query = _query.trim().toLowerCase();
    final mediaItems = lib.media.where((media) {
      if (query.isEmpty) return true;
      return media.title.toLowerCase().contains(query) ||
          (media.artist?.toLowerCase().contains(query) ?? false);
    }).toList();
    final selectedVisibleCount = mediaItems
        .where((media) => _selectedIds.contains(media.id))
        .length;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selectedIds.isEmpty ? '動画タイトル・投稿者を編集' : '${_selectedIds.length}本選択中',
        ),
        actions: [
          if (_selecting && mediaItems.isNotEmpty)
            IconButton(
              tooltip: selectedVisibleCount == mediaItems.length
                  ? '表示中の選択を解除'
                  : '表示中をすべて選択',
              icon: Icon(
                selectedVisibleCount == mediaItems.length
                    ? Icons.deselect_rounded
                    : Icons.select_all_rounded,
              ),
              onPressed: () => setState(() {
                if (selectedVisibleCount == mediaItems.length) {
                  _selectedIds.removeAll(mediaItems.map((m) => m.id));
                } else {
                  _selectedIds.addAll(mediaItems.map((m) => m.id));
                }
              }),
            ),
          if (_selecting)
            IconButton(
              tooltip: '選択を解除',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => setState(() {
                _selecting = false;
                _selectedIds.clear();
              }),
            )
          else
            IconButton(
              tooltip: '複数選択',
              icon: const Icon(Icons.checklist_rounded),
              onPressed: () => setState(() => _selecting = true),
            ),
          if (_selectedIds.isNotEmpty)
            IconButton(
              tooltip: '選択した動画の投稿者を一括変更',
              icon: const Icon(Icons.edit_note_rounded),
              onPressed: _editSelectedArtists,
            ),
        ],
      ),
      body: lib.media.isEmpty
          ? const Center(child: Text('動画がありません。'))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      hintText: '動画名・投稿者を検索',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: '検索をクリア',
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                            ),
                    ),
                  ),
                ),
                if (_selectedIds.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _editSelectedArtists,
                        icon: const Icon(Icons.edit_note_rounded),
                        label: Text('選択した${_selectedIds.length}本の投稿者を一括変更'),
                      ),
                    ),
                  ),
                if (mediaItems.isEmpty)
                  const Expanded(child: Center(child: Text('該当する動画がありません')))
                else
                  Expanded(
                    child: ListView.builder(
                      itemCount: mediaItems.length,
                      itemBuilder: (c, i) {
                        final m = mediaItems[i];
                        return Dismissible(
                          key: ValueKey(m.id),
                          direction: _selecting
                              ? DismissDirection.none
                              : DismissDirection.endToStart,
                          background: Container(
                            color: Colors.red,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 16),
                            child: const Icon(
                              Icons.delete,
                              color: Colors.white,
                            ),
                          ),
                          onDismissed: (_) async {
                            await ref
                                .read(playbackControllerProvider)
                                .handleMediaRemoved(m.id);
                            await ref
                                .read(libraryProvider.notifier)
                                .removeMedia(m.id);
                          },
                          child: ListTile(
                            selected: _selectedIds.contains(m.id),
                            selectedTileColor: kAccent.withValues(alpha: 0.12),
                            leading: ThumbImage(
                              seed: m.id,
                              mediaId: m.id,
                              localPath: m.localPath,
                              size: 40,
                              radius: 8,
                            ),
                            title: Text(displayTitle(m.title)),
                            subtitle: Text(
                              m.artist?.trim().isNotEmpty == true
                                  ? formatCreatorNames(m.artist)
                                  : (m.origin == 'referenced'
                                        ? '投稿者未設定 • 参照'
                                        : '投稿者未設定'),
                            ),
                            trailing: _selecting
                                ? Checkbox(
                                    value: _selectedIds.contains(m.id),
                                    onChanged: (_) => _toggleSelected(m.id),
                                  )
                                : IconButton(
                                    tooltip: '編集',
                                    icon: const Icon(Icons.edit_rounded),
                                    onPressed: () =>
                                        _editMedia(context, ref, m),
                                  ),
                            onTap: _selecting
                                ? () => _toggleSelected(m.id)
                                : () => _editMedia(context, ref, m),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
    );
  }

  void _toggleSelected(String id) => setState(() {
    if (!_selectedIds.add(id)) _selectedIds.remove(id);
  });

  Future<void> _editSelectedArtists() async {
    final selectedIds = List<String>.of(_selectedIds);
    if (selectedIds.isEmpty) return;
    var names = <String>[];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = themeTextPrimary(context);
    final subtle = themeTextSub(context);
    final border = themeBorder(context);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${selectedIds.length}本の投稿者を一括変更'),
        content: SizedBox(
          width: 420,
          child: _CreatorNamesField(
            initialValue: null,
            textColor: textColor,
            labelColor: subtle,
            borderColor: border,
            isDark: isDark,
            onChanged: (value) => names = value,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'clear'),
            child: const Text('投稿者を消去'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'save'),
            child: const Text('一括変更'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    final artist = result == 'clear' || names.isEmpty ? null : names.join('・');
    await ref
        .read(libraryProvider.notifier)
        .updateMediaArtists(selectedIds, artist);
    if (!mounted) return;
    setState(() {
      _selectedIds.clear();
      _selecting = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${selectedIds.length}本の投稿者名を変更しました')),
    );
  }

  Future<void> _editMedia(
    BuildContext context,
    WidgetRef ref,
    MediaItem media,
  ) async {
    final titleController = TextEditingController(text: media.title);
    final artistController = TextEditingController(text: media.artist ?? '');
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
        final textColor = themeTextPrimary(dialogContext);
        final subtle = themeTextSub(dialogContext);
        final border = themeBorder(dialogContext);
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Container(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
              decoration: BoxDecoration(
                color: themeCard(dialogContext),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '動画情報を編集',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 22),
                  _MetadataField(
                    label: 'タイトル',
                    controller: titleController,
                    autofocus: true,
                    textColor: textColor,
                    labelColor: subtle,
                    borderColor: border,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 16),
                  _CreatorNamesField(
                    initialValue: media.artist,
                    textColor: textColor,
                    labelColor: subtle,
                    borderColor: border,
                    isDark: isDark,
                    onChanged: (names) {
                      artistController.text = names.join('・');
                    },
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: subtle,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('キャンセル'),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: textColor,
                          foregroundColor: themeCard(dialogContext),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (save == true) {
      final artist = artistController.text.trim();
      await ref
          .read(libraryProvider.notifier)
          .updateMediaMetadata(
            media.id,
            title: titleController.text.trim(),
            artist: artist.isEmpty ? null : artist,
          );
    }
    titleController.dispose();
    artistController.dispose();
  }
}

class _MetadataField extends StatelessWidget {
  const _MetadataField({
    required this.label,
    required this.controller,
    required this.textColor,
    required this.labelColor,
    required this.borderColor,
    required this.isDark,
    this.autofocus = false,
  });

  final String label;
  final TextEditingController controller;
  final Color textColor;
  final Color labelColor;
  final Color borderColor;
  final bool isDark;
  final bool autofocus;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 7),
        child: Text(
          label,
          style: TextStyle(
            color: labelColor,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
      TextField(
        controller: controller,
        autofocus: autofocus,
        style: TextStyle(color: textColor, fontSize: 15),
        decoration: InputDecoration(
          hintText: label,
          filled: true,
          fillColor: isDark
              ? Colors.white.withValues(alpha: 0.035)
              : const Color(0xFFF5F6FA),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 13,
            vertical: 13,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: borderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: labelColor.withValues(alpha: 0.8)),
          ),
        ),
      ),
    ],
  );
}

class _CreatorNamesField extends StatefulWidget {
  const _CreatorNamesField({
    required this.initialValue,
    required this.textColor,
    required this.labelColor,
    required this.borderColor,
    required this.isDark,
    required this.onChanged,
  });

  final String? initialValue;
  final Color textColor;
  final Color labelColor;
  final Color borderColor;
  final bool isDark;
  final ValueChanged<List<String>> onChanged;

  @override
  State<_CreatorNamesField> createState() => _CreatorNamesFieldState();
}

class _CreatorNamesFieldState extends State<_CreatorNamesField> {
  late final List<String> _names = splitCreatorNames(widget.initialValue);
  final _entryController = TextEditingController();

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  void _addName([String? value]) {
    final name = (value ?? _entryController.text).trim();
    if (name.isEmpty) return;
    if (_names.any(
      (existing) => existing.toLowerCase() == name.toLowerCase(),
    )) {
      _entryController.clear();
      return;
    }
    setState(() => _names.add(name));
    widget.onChanged(List.unmodifiable(_names));
    _entryController.clear();
  }

  void _removeName(String name) {
    setState(() => _names.remove(name));
    widget.onChanged(List.unmodifiable(_names));
  }

  Future<void> _editName(String original) async {
    final index = _names.indexOf(original);
    if (index < 0) return;
    final controller = TextEditingController(text: original);
    final updated = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('投稿者名を編集'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
          decoration: const InputDecoration(labelText: '投稿者名'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    final name = updated?.trim();
    if (name == null || name.isEmpty || !mounted) return;
    if (_names.asMap().entries.any(
      (entry) =>
          entry.key != index && entry.value.toLowerCase() == name.toLowerCase(),
    )) {
      return;
    }
    setState(() => _names[index] = name);
    widget.onChanged(List.unmodifiable(_names));
  }

  @override
  Widget build(BuildContext context) {
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: widget.borderColor),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 7),
          child: Text(
            '投稿者（共作可）',
            style: TextStyle(
              color: widget.labelColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ),
        if (_names.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 2,
            children: [
              for (final name in _names)
                InputChip(
                  label: Text(name),
                  onPressed: () => _editName(name),
                  onDeleted: () => _removeName(name),
                  tooltip: 'タップして編集',
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  side: BorderSide(color: widget.borderColor),
                  backgroundColor: widget.isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : const Color(0xFFF5F6FA),
                  labelStyle: TextStyle(color: widget.textColor, fontSize: 13),
                ),
            ],
          ),
          const SizedBox(height: 6),
        ],
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _entryController,
                style: TextStyle(color: widget.textColor, fontSize: 15),
                textInputAction: TextInputAction.done,
                onSubmitted: _addName,
                decoration: InputDecoration(
                  hintText: _names.isEmpty ? '名前を入力' : '共作者を追加',
                  filled: true,
                  fillColor: widget.isDark
                      ? Colors.white.withValues(alpha: 0.035)
                      : const Color(0xFFF5F6FA),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 13,
                  ),
                  enabledBorder: fieldBorder,
                  focusedBorder: fieldBorder.copyWith(
                    borderSide: BorderSide(
                      color: widget.labelColor.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: '名前を追加',
              onPressed: () => _addName(),
              icon: const Icon(Icons.add_rounded),
              style: IconButton.styleFrom(
                foregroundColor: widget.textColor,
                side: BorderSide(color: widget.borderColor),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
