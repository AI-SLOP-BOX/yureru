import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_state.dart';
import '../../domain/creator_names.dart';
import '../../playback/playback_controller.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets/thumb_image.dart';
import '../widgets/metadata_fields.dart';
import 'media_metadata_editor.dart';

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
    final mediaItems = lib.savedMedia.where((media) {
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
          _selectedIds.isEmpty
              ? ref.tr('edit_media_artwork')
              : ref
                    .tr('selected_count')
                    .replaceAll('{count}', '${_selectedIds.length}'),
        ),
        actions: [
          if (_selecting && mediaItems.isNotEmpty)
            IconButton(
              tooltip: selectedVisibleCount == mediaItems.length
                  ? ref.tr('clear')
                  : ref.tr('select_all'),
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
              tooltip: ref.tr('clear_selection'),
              icon: const Icon(Icons.close_rounded),
              onPressed: () => setState(() {
                _selecting = false;
                _selectedIds.clear();
              }),
            )
          else
            IconButton(
              tooltip: ref.tr('select_multiple'),
              icon: const Icon(Icons.checklist_rounded),
              onPressed: () => setState(() => _selecting = true),
            ),
          if (_selectedIds.isNotEmpty)
            IconButton(
              tooltip: ref.tr('bulk_edit_creator'),
              icon: const Icon(Icons.edit_note_rounded),
              onPressed: _editSelectedArtists,
            ),
        ],
      ),
      body: lib.savedMedia.isEmpty
          ? Center(child: Text(ref.tr('no_media')))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      hintText: ref.tr('search_media'),
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: ref.tr('clear'),
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
                        label: Text(
                          ref
                              .tr('bulk_edit_creator_count')
                              .replaceAll('{count}', '${_selectedIds.length}'),
                        ),
                      ),
                    ),
                  ),
                if (mediaItems.isEmpty)
                  Expanded(child: Center(child: Text(ref.tr('not_found'))))
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
                              imageContext: MediaImageContext.home,
                              size: 40,
                              radius: 8,
                            ),
                            title: Text(displayTitle(m.title)),
                            subtitle: Text(
                              m.artist?.trim().isNotEmpty == true
                                  ? formatCreatorNames(m.artist)
                                  : (m.origin == 'referenced'
                                        ? '${ref.tr('creator_not_set')} • ${ref.tr('referenced_video')}'
                                        : ref.tr('creator_not_set')),
                            ),
                            trailing: _selecting
                                ? Checkbox(
                                    value: _selectedIds.contains(m.id),
                                    onChanged: (_) => _toggleSelected(m.id),
                                  )
                                : IconButton(
                                    tooltip: ref.tr('edit_media_artwork'),
                                    icon: const Icon(Icons.edit_rounded),
                                    onPressed: () => showMediaMetadataEditor(
                                      context,
                                      ref,
                                      m,
                                    ),
                                  ),
                            onTap: _selecting
                                ? () => _toggleSelected(m.id)
                                : () =>
                                      showMediaMetadataEditor(context, ref, m),
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
        title: Text(
          ref
              .tr('bulk_edit_creator_count')
              .replaceAll('{count}', '${selectedIds.length}'),
        ),
        content: SizedBox(
          width: 420,
          child: CreatorNamesField(
            initialValue: null,
            textColor: textColor,
            labelColor: subtle,
            borderColor: border,
            isDark: isDark,
            strings: ref.tr,
            onChanged: (value) => names = value,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'clear'),
            child: Text(ref.tr('clear_creator')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(ref.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'save'),
            child: Text(ref.tr('save')),
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
      SnackBar(
        content: Text(
          ref
              .tr('updated_creator_count')
              .replaceAll('{count}', '${selectedIds.length}'),
        ),
      ),
    );
  }
}
