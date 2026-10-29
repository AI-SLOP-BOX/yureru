import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_state.dart';
import '../../domain/models.dart';
import '../../library/media_collections.dart';
import '../../playback/playback_controller.dart';
import '../i18n.dart';
import '../theme.dart';
import 'media_metadata_editor.dart';
import 'batch_metadata_editor.dart';
import '../widgets/app_svg_icon.dart';
import '../widgets/thumb_image.dart';
import '../widgets/duration_text.dart';

final mediaCollectionsProvider =
    Provider.family<List<MediaCollection>, CollectionKind>((ref, kind) {
      return buildMediaCollections(ref.watch(libraryProvider).savedMedia, kind);
    });

class CollectionBrowser extends ConsumerStatefulWidget {
  const CollectionBrowser({super.key, required this.kind});
  final CollectionKind kind;
  @override
  ConsumerState<CollectionBrowser> createState() => _CollectionBrowserState();
}

class _CollectionBrowserState extends ConsumerState<CollectionBrowser> {
  String? _selectedId;
  bool _selecting = false;
  final Set<String> _selection = {};

  void _leaveSelection() {
    _selecting = false;
    _selection.clear();
  }

  @override
  void didUpdateWidget(CollectionBrowser oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != widget.kind) {
      _selectedId = null;
      _leaveSelection();
    }
  }

  void _toggle(String id) => setState(() {
    if (!_selection.add(id)) _selection.remove(id);
  });

  void _play(
    List<MediaItem> items, {
    MediaItem? selected,
    bool shuffle = false,
  }) {
    if (items.isEmpty) return;
    ref
        .read(queueProvider.notifier)
        .start(items.map((m) => m.id).toList(), shuffle: shuffle);
    if (selected != null) {
      final index = ref.read(queueProvider).queue.indexOf(selected.id);
      if (index >= 0) ref.read(queueProvider.notifier).jumpTo(index);
    }
    showPlayerView(ref);
    ref.read(playbackControllerProvider).openCurrent();
  }

  String _label(MediaCollection group) =>
      group.name ??
      ref.tr(
        widget.kind == CollectionKind.albums
            ? 'unknown_album'
            : 'unknown_artist',
      );
  String _count(int count) =>
      ref.tr('collection_tracks').replaceAll('{count}', '$count');

  Widget _empty({required bool searching}) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppSvgIcon(
            widget.kind == CollectionKind.albums
                ? 'collection_album'
                : 'collection_artist',
            size: 36,
            color: themeTextSub(context),
          ),
          const SizedBox(height: 16),
          Text(
            ref.tr(searching ? 'browse_no_matches' : 'collection_empty'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            ref.tr(searching ? 'browse_search_hint' : 'browse_empty_hint'),
            textAlign: TextAlign.center,
            style: TextStyle(color: themeTextSub(context)),
          ),
          if (searching) ...[
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () =>
                  ref.read(searchQueryProvider.notifier).state = '',
              child: Text(ref.tr('browse_clear_search')),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _selectionBar(MediaCollection collection, List<MediaItem> visible) {
    final ids = collection.items
        .where((m) => _selection.contains(m.id))
        .map((m) => m.id)
        .toList();
    final visibleIds = visible.map((m) => m.id).toSet();
    final allVisible =
        visibleIds.isNotEmpty && visibleIds.every(_selection.contains);
    final hidden = ids.where((id) => !visibleIds.contains(id)).length;
    return Material(
      elevation: 8,
      color: themeCard(context),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      ref
                          .tr('batch_count')
                          .replaceAll('{count}', '${ids.length}'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton(
                    onPressed: visibleIds.isEmpty
                        ? null
                        : () => setState(() {
                            if (allVisible) {
                              _selection.removeAll(visibleIds);
                            } else {
                              _selection.addAll(visibleIds);
                            }
                          }),
                    child: Text(
                      ref.tr(
                        allVisible
                            ? 'browse_deselect_visible'
                            : 'browse_select_visible',
                      ),
                    ),
                  ),
                ],
              ),
              if (hidden > 0)
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      ref
                          .tr('browse_hidden_selection')
                          .replaceAll('{count}', '$hidden'),
                      style: TextStyle(
                        color: themeTextSub(context),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: ids.isEmpty
                          ? null
                          : () async {
                              final saved = await showBatchMetadataEditor(
                                context,
                                ref,
                                ids,
                              );
                              if (!mounted || !saved) return;
                              setState(() {
                                _leaveSelection();
                                _selectedId = null;
                              });
                            },
                      icon: const AppSvgIcon('collection_edit', size: 18),
                      label: Text(ref.tr('batch_metadata')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  TextButton(
                    onPressed: () => setState(_leaveSelection),
                    child: Text(ref.tr('browse_finish_selection')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hero(MediaCollection collection) {
    final cover = collection.items.first;
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: themeCard(context),
        border: Border.all(color: themeBorder(context)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ThumbImage(
                seed: _label(collection),
                mediaId: cover.id,
                localPath: cover.localPath,
                imageContext: widget.kind == CollectionKind.albums
                    ? MediaImageContext.album
                    : null,
                size: 72,
                radius: 12,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _label(collection),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    if (collection.artist != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        collection.artist!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: themeTextSub(context)),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      _count(collection.items.length),
                      style: TextStyle(
                        color: themeTextSub(context),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_selecting)
            Text(
              ref.tr('browse_selection_hint'),
              style: TextStyle(color: themeTextSub(context)),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: () => _play(collection.items),
                  icon: const AppSvgIcon('play', size: 18),
                  label: Text(ref.tr('play')),
                ),
                OutlinedButton.icon(
                  onPressed: () => _play(collection.items, shuffle: true),
                  icon: const AppSvgIcon('collection_shuffle', size: 18),
                  label: Text(ref.tr('shuffle')),
                ),
                TextButton.icon(
                  onPressed: () => setState(() {
                    _selection.clear();
                    _selecting = true;
                  }),
                  icon: const AppSvgIcon('collection_select', size: 18),
                  label: Text(ref.tr('select_tracks')),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _track(
    MediaItem media,
    MediaCollection collection,
    bool showDiscs,
    String? currentId,
    bool wide,
  ) {
    return ListTile(
      key: ValueKey('collection-track-${media.id}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      selectedTileColor: Theme.of(
        context,
      ).colorScheme.primary.withValues(alpha: 0.12),
      selected: _selecting
          ? _selection.contains(media.id)
          : currentId == media.id,
      leading: _selecting
          ? Checkbox(
              value: _selection.contains(media.id),
              onChanged: (_) => _toggle(media.id),
            )
          : ThumbImage(
              seed: media.title,
              mediaId: media.id,
              localPath: media.localPath,
              imageContext: widget.kind == CollectionKind.albums
                  ? MediaImageContext.album
                  : null,
            ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              '${media.trackNumber == null || widget.kind == CollectionKind.artists ? '' : '${media.trackNumber}. '}${media.title}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (media.isFavorite)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 8),
              child: AppSvgIcon(
                'favorite_filled',
                size: 14,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
        ],
      ),
      subtitle: Text(
        '${showDiscs ? '${ref.tr('disc_label').replaceAll('{disc}', '${media.discNumber ?? 1}')} · ' : ''}${media.artist ?? ref.tr('unknown_artist')}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: _selecting
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (wide && media.durationMs != null)
                  DurationText(
                    mediaId: media.id,
                    localPath: media.localPath,
                    durationMs: media.durationMs,
                  ),
                PopupMenuButton<String>(
                  tooltip: ref.tr('browse_track_actions'),
                  icon: const AppSvgIcon('more_horizontal'),
                  onSelected: (action) {
                    if (action == 'edit') {
                      showMediaMetadataEditor(context, ref, media);
                    } else {
                      ref
                          .read(libraryProvider.notifier)
                          .toggleFavorite(media.id);
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'favorite',
                      child: Row(
                        children: [
                          AppSvgIcon(
                            media.isFavorite ? 'favorite_filled' : 'favorite',
                            size: 18,
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            child: Text(
                              ref.tr(
                                media.isFavorite
                                    ? 'remove_favorite'
                                    : 'add_favorite',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          const AppSvgIcon('collection_edit', size: 18),
                          const SizedBox(width: 12),
                          Flexible(child: Text(ref.tr('metadata_edit_title'))),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
      onTap: () => _selecting
          ? _toggle(media.id)
          : _play(collection.items, selected: media),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(libraryProvider).loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final groups = ref.watch(mediaCollectionsProvider(widget.kind));
    final query = ref.watch(searchQueryProvider).trim().toLowerCase();
    final currentId = ref.watch(queueProvider.select((q) => q.currentId));
    final collection = groups.where((g) => g.id == _selectedId).firstOrNull;
    bool matches(MediaItem item) =>
        item.title.toLowerCase().contains(query) ||
        (item.artist ?? '').toLowerCase().contains(query);
    if (collection != null) {
      final showDiscs =
          widget.kind == CollectionKind.albums &&
          collection.items.any((m) => (m.discNumber ?? 1) > 1);
      final visible = collection.items
          .where(
            (m) =>
                query.isEmpty ||
                _label(collection).toLowerCase().contains(query) ||
                matches(m),
          )
          .toList();
      return LayoutBuilder(
        builder: (context, constraints) => Column(
          children: [
            Expanded(
              child: CustomScrollView(
                key: ValueKey('collection-detail-${collection.id}'),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextButton.icon(
                            onPressed: () => setState(() {
                              _selectedId = null;
                              _leaveSelection();
                            }),
                            icon: const AppSvgIcon('back', size: 18),
                            label: Text(ref.tr('back')),
                          ),
                          _hero(collection),
                        ],
                      ),
                    ),
                  ),
                  if (visible.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _empty(searching: query.isNotEmpty),
                    ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    sliver: SliverList.builder(
                      itemCount: visible.length,
                      itemBuilder: (_, index) => _track(
                        visible[index],
                        collection,
                        showDiscs,
                        currentId,
                        constraints.maxWidth >= 520,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_selecting) _selectionBar(collection, visible),
          ],
        ),
      );
    }
    final visible = groups
        .where(
          (g) =>
              query.isEmpty ||
              _label(g).toLowerCase().contains(query) ||
              (g.artist ?? '').toLowerCase().contains(query) ||
              g.items.any(matches),
        )
        .toList();
    if (visible.isEmpty) return _empty(searching: query.isNotEmpty);
    return GridView.builder(
      key: ValueKey('collection-grid-${widget.kind.name}'),
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisExtent: 246,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: visible.length,
      itemBuilder: (_, index) {
        final group = visible[index];
        final cover = group.items.first;
        return Card(
          clipBehavior: Clip.antiAlias,
          elevation: 0,
          color: themeCard(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: themeBorder(context)),
          ),
          child: InkWell(
            onTap: () => setState(() => _selectedId = group.id),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SizedBox(
                      width: double.infinity,
                      child: ThumbImage(
                        seed: _label(group),
                        mediaId: cover.id,
                        localPath: cover.localPath,
                        imageContext: widget.kind == CollectionKind.albums
                            ? MediaImageContext.album
                            : null,
                        expand: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _label(group),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (group.artist != null)
                    Text(
                      group.artist!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: themeTextSub(context),
                        fontSize: 12,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    _count(group.items.length),
                    style: TextStyle(
                      color: themeTextSub(context),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
