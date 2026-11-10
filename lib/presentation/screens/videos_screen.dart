import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../../app_state.dart';
import '../../domain/models.dart';
import '../../extensions/extension_manifest.dart';
import '../../extensions/extension_registry.dart';
import '../../library/media_order.dart';
import '../../domain/creator_names.dart';
import '../../playback/playback_controller.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets/duration_text.dart';
import '../widgets/app_svg_icon.dart';
import '../widgets/page_header.dart';
import '../widgets/thumb_image.dart';
import '../widgets/track_actions.dart';
import '../widgets/extension_track_actions.dart';
import '../widgets/unsaved_changes_guard.dart';

bool _sharesCreator(String? mediaCredit, String selectedCredit) {
  final selectedNames = splitCreatorNames(
    selectedCredit,
  ).map((name) => name.toLowerCase()).toSet();
  if (selectedNames.isEmpty) return false;
  final mediaNames = splitCreatorNames(
    mediaCredit,
  ).map((name) => name.toLowerCase()).toSet();
  return mediaNames.intersection(selectedNames).isNotEmpty;
}

/// Keep repeated records for the same library file out of the all-tracks list.
/// Use paths/IDs only: distinct files with the same title remain separate.
List<MediaItem> _uniqueLibraryTracks(Iterable<MediaItem> media) {
  final seenIds = <String>{};
  final seenPaths = <String>{};
  final unique = <MediaItem>[];
  for (final item in media) {
    final paths = [item.sourcePath, item.localPath]
        .whereType<String>()
        .map((path) => path.trim())
        .where((path) => path.isNotEmpty)
        .toSet();
    if (seenIds.contains(item.id) || paths.any(seenPaths.contains)) continue;
    seenIds.add(item.id);
    seenPaths.addAll(paths);
    unique.add(item);
  }
  return unique;
}

/// "すべての動画": Clean modern table view with track index, hover play preview,
/// clean alignment, and context actions.
class VideosScreen extends ConsumerStatefulWidget {
  const VideosScreen({super.key});

  @override
  ConsumerState<VideosScreen> createState() => _VideosScreenState();
}

class _VideosScreenState extends ConsumerState<VideosScreen> {
  double _rowExtent(BuildContext context) =>
      72 +
      (MediaQuery.textScalerOf(context).scale(14) - 14).clamp(
            0,
            double.infinity,
          ) *
          2;

  String _sortLabel(VideosSort value) => ref.tr(switch (value) {
    VideosSort.manual => 'manual_order',
    VideosSort.name => 'name_order',
    VideosSort.newestFirst => 'newest_first',
    VideosSort.oldestFirst => 'oldest_first',
    VideosSort.recentlyPlayed => 'recently_played_order',
  });

  void _clearFilters() {
    ref.read(searchQueryProvider.notifier).state = '';
    ref.read(videoCreatorFilterProvider.notifier).state = null;
    ref.read(favoritesOnlyProvider.notifier).state = false;
    ref.read(videosQuickFilterProvider.notifier).state = VideosQuickFilter.all;
  }

  final ScrollController _scrollController = ScrollController();
  Timer? _highlightTimer;
  String? _highlightedId;
  String? _scheduledRequestId;
  bool _selectionMode = false;
  final Set<String> _selectedMediaIds = <String>{};

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _playFromHere(WidgetRef ref, List<String> ids, int i) {
    showPlayerView(ref);
    ref.read(queueProvider.notifier).start(ids, shuffle: false);
    ref.read(queueProvider.notifier).jumpTo(i);
    ref.read(playbackControllerProvider).openCurrent();
  }

  void _toggleSelection(String mediaId) {
    setState(() {
      _selectionMode = true;
      if (!_selectedMediaIds.add(mediaId)) {
        _selectedMediaIds.remove(mediaId);
      }
    });
  }

  void _selectAllVisible(List<MediaItem> items) {
    setState(() {
      _selectionMode = true;
      _selectedMediaIds.addAll(items.map((media) => media.id));
    });
  }

  void _leaveSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedMediaIds.clear();
    });
  }

  Future<void> _addSelectionToPlaylist(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final library = ref.read(libraryProvider);
    if (_selectedMediaIds.isEmpty) return;
    final manualPlaylists = library.playlists
        .where((playlist) => !playlist.isSmart)
        .toList();
    if (manualPlaylists.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(ref.tr('empty_playlist'))));
      return;
    }
    final playlist = await showModalBottomSheet<Playlist>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
              child: Text(
                ref.tr('add_playlist'),
                style: Theme.of(
                  sheetContext,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            for (final item in manualPlaylists)
              ListTile(
                leading: const Icon(Icons.playlist_play_rounded),
                title: Text(displayTitle(item.name)),
                onTap: () => Navigator.pop(sheetContext, item),
              ),
          ],
        ),
      ),
    );
    if (playlist == null || !context.mounted) return;
    try {
      final currentLibrary = ref.read(libraryProvider);
      final selectedIds = _selectedMediaIds
          .where(
            (id) => currentLibrary.savedMedia.any((media) => media.id == id),
          )
          .toList(growable: false);
      if (selectedIds.isEmpty) {
        _leaveSelectionMode();
        return;
      }
      final count = selectedIds.length;
      await ref
          .read(libraryProvider.notifier)
          .addMediaToPlaylist(playlist.id, selectedIds);
      if (!context.mounted) return;
      _leaveSelectionMode();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${ref.tr('added_to_playlist').replaceAll('{name}', displayTitle(playlist.name))} · ${ref.tracksCount(count)}',
          ),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(ref.tr('add_to_playlist_failed'))));
    }
  }

  Future<void> _addSelectionToAlbum(BuildContext context, WidgetRef ref) async {
    final library = ref.read(libraryProvider);
    final selectedIds = _selectedMediaIds
        .where((id) => library.savedMedia.any((media) => media.id == id))
        .toList(growable: false);
    if (selectedIds.isEmpty) return;
    final selectedMedia = library.savedMedia
        .where((media) => selectedIds.contains(media.id))
        .toList(growable: false);
    final creators = selectedMedia
        .map((media) => (media.albumArtist ?? media.artist ?? '').trim())
        .where((name) => name.isNotEmpty)
        .toSet();
    final albumController = TextEditingController();
    final initialAlbumArtist = creators.length == 1
        ? creators.first
        : ref.tr('various_artists');
    final albumArtistController = TextEditingController(
      text: initialAlbumArtist,
    );
    String? artworkSourcePath;
    final result = await showDialog<(String, String, String?)>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final hasDraft =
              albumController.text.isNotEmpty ||
              albumArtistController.text != initialAlbumArtist ||
              artworkSourcePath != null;
          return PopScope<Object?>(
            canPop: !hasDraft,
            onPopInvokedWithResult: (didPop, _) async {
              if (!didPop &&
                  hasDraft &&
                  await confirmDiscardUnsavedChanges(context, ref.tr) &&
                  dialogContext.mounted) {
                Navigator.pop(dialogContext);
              }
            },
            child: AlertDialog(
              title: Text(ref.tr('add_to_album')),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ref
                            .tr('batch_count')
                            .replaceAll('{count}', '${selectedIds.length}'),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        autofocus: true,
                        controller: albumController,
                        onChanged: (_) => setDialogState(() {}),
                        decoration: InputDecoration(
                          labelText: ref.tr('album'),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: albumArtistController,
                        onChanged: (_) => setDialogState(() {}),
                        decoration: InputDecoration(
                          labelText: ref.tr('album_artist'),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await FilePicker.platform.pickFiles(
                            type: FileType.image,
                            allowMultiple: false,
                          );
                          final path = picked?.files.single.path;
                          if (path == null) return;
                          setDialogState(() => artworkSourcePath = path);
                        },
                        icon: const Icon(Icons.image_outlined),
                        label: Text(
                          artworkSourcePath == null
                              ? ref.tr('choose_album_artwork')
                              : File(artworkSourcePath!).uri.pathSegments.last,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        ref.tr('album_artwork_hint'),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () async {
                    if (hasDraft &&
                        !await confirmDiscardUnsavedChanges(context, ref.tr)) {
                      return;
                    }
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: Text(ref.tr('cancel')),
                ),
                FilledButton(
                  onPressed:
                      albumController.text.trim().isEmpty ||
                          albumArtistController.text.trim().isEmpty
                      ? null
                      : () {
                          final album = albumController.text.trim();
                          final artist = albumArtistController.text.trim();
                          Navigator.pop(dialogContext, (
                            album,
                            artist,
                            artworkSourcePath,
                          ));
                        },
                  child: Text(ref.tr('save')),
                ),
              ],
            ),
          );
        },
      ),
    );
    albumController.dispose();
    albumArtistController.dispose();
    if (result == null || !context.mounted) return;

    String? managedArtworkPath;
    try {
      if (result.$3 != null) {
        final support = await getApplicationSupportDirectory();
        final artworkDirectory = Directory('${support.path}/yureru_artwork');
        await artworkDirectory.create(recursive: true);
        final extension = result.$3!.split('.').last.toLowerCase();
        managedArtworkPath =
            '${artworkDirectory.path}/album_${DateTime.now().microsecondsSinceEpoch}.$extension';
        await File(result.$3!).copy(managedArtworkPath);
      }
      await ref
          .read(libraryProvider.notifier)
          .updateMediaAlbumBatch(
            selectedIds,
            album: result.$1,
            albumArtist: result.$2,
            artworkPath: managedArtworkPath,
          );
      if (!context.mounted) return;
      _leaveSelectionMode();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${ref.tr('album_added')} · ${ref.tracksCount(selectedIds.length)}',
          ),
        ),
      );
    } catch (_) {
      if (managedArtworkPath != null) {
        try {
          await File(managedArtworkPath).delete();
        } catch (_) {}
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(ref.tr('batch_save_failed'))));
    }
  }

  Future<void> _editSelectionArtist(BuildContext context, WidgetRef ref) async {
    if (_selectedMediaIds.isEmpty) return;
    final controller = TextEditingController();
    final artist = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(ref.tr('batch_edit_artist')),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: ref.tr('metadata_artist'),
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(ref.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(ref.tr('save')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (artist == null || !context.mounted) return;
    final ids = _selectedMediaIds.toList(growable: false);
    await ref.read(libraryProvider.notifier).updateMediaArtists(ids, artist);
    _leaveSelectionMode();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ref.tr('batch_count').replaceAll('{count}', '${ids.length}'),
          ),
        ),
      );
    }
  }

  Future<void> _addMediaToPlaylist(
    BuildContext context,
    WidgetRef ref,
    MediaItem media,
  ) async {
    final playlists = ref
        .read(libraryProvider)
        .playlists
        .where((playlist) => !playlist.isSmart)
        .toList();
    if (playlists.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(ref.tr('empty_playlist'))));
      return;
    }
    final playlist = await showModalBottomSheet<Playlist>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                ref.tr('add_playlist'),
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            for (final item in playlists)
              ListTile(
                leading: const Icon(Icons.playlist_play_rounded),
                title: Text(displayTitle(item.name)),
                onTap: () => Navigator.pop(sheetContext, item),
              ),
          ],
        ),
      ),
    );
    if (playlist == null || !context.mounted) return;
    await ref
        .read(libraryProvider.notifier)
        .addToPlaylist(playlist.id, media.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ref
                .tr('added_to_playlist')
                .replaceAll('{name}', displayTitle(playlist.name)),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final lib = ref.watch(libraryProvider);
    final query = ref.watch(searchQueryProvider).trim().toLowerCase();
    final creatorFilter = ref.watch(videoCreatorFilterProvider)?.trim();
    final sort = ref.watch(videosSortProvider);
    final favoritesOnly = ref.watch(favoritesOnlyProvider);
    final quickFilter = ref.watch(videosQuickFilterProvider);
    final currentId = ref.watch(queueProvider.select((q) => q.currentId));
    if (!lib.loaded) return const Center(child: CircularProgressIndicator());
    final items = _uniqueLibraryTracks(lib.savedMedia)
        .where(
          (m) =>
              (!favoritesOnly || m.isFavorite) &&
              switch (quickFilter) {
                VideosQuickFilter.all => true,
                VideosQuickFilter.withLyrics => [
                  m.lyricsPath,
                  m.videoLyricsPath,
                  m.artworkLyricsPath,
                ].any((path) => path != null && path.isNotEmpty),
                VideosQuickFilter.withoutLyrics => [
                  m.lyricsPath,
                  m.videoLyricsPath,
                  m.artworkLyricsPath,
                ].every((path) => path == null || path.isEmpty),
                VideosQuickFilter.notPlayed => m.playCount == 0,
              } &&
              (creatorFilter == null ||
                  _sharesCreator(m.artist, creatorFilter)) &&
              (query.isEmpty ||
                  m.title.toLowerCase().contains(query) ||
                  (m.artist?.toLowerCase().contains(query) ?? false) ||
                  (m.album?.toLowerCase().contains(query) ?? false)),
        )
        .toList();
    switch (sort) {
      case VideosSort.recentlyPlayed:
        items.sort(compareRecentlyPlayed);
      case VideosSort.newestFirst:
        items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case VideosSort.oldestFirst:
        items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case VideosSort.name:
        items.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
      case VideosSort.manual:
        // Preserve the user's saved library order.
        break;
    }
    final requestedMediaId = ref.watch(videoOpenRequestProvider);
    if (requestedMediaId != null && requestedMediaId != _scheduledRequestId) {
      _scheduledRequestId = requestedMediaId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(videoOpenRequestProvider.notifier).state = null;
        _scheduledRequestId = null;
        final targetIndex = items.indexWhere(
          (media) => media.id == requestedMediaId,
        );
        if (targetIndex < 0) return;
        if (_scrollController.hasClients) {
          final position = _scrollController.position;
          final reorderable =
              sort == VideosSort.manual &&
              !favoritesOnly &&
              quickFilter == VideosQuickFilter.all &&
              query.isEmpty &&
              creatorFilter == null;
          final offset =
              (targetIndex * (_rowExtent(context) + (reorderable ? 0 : 3)))
                  .clamp(0.0, position.maxScrollExtent)
                  .toDouble();
          unawaited(
            _scrollController.animateTo(
              offset,
              duration: const Duration(milliseconds: 450),
              curve: Curves.easeOutCubic,
            ),
          );
        }
        _highlightTimer?.cancel();
        setState(() => _highlightedId = requestedMediaId);
        _highlightTimer = Timer(const Duration(milliseconds: 2600), () {
          if (mounted) setState(() => _highlightedId = null);
        });
      });
    }
    final ids = [for (final m in items) m.id];
    final filtered =
        query.isNotEmpty ||
        creatorFilter != null ||
        favoritesOnly ||
        quickFilter != VideosQuickFilter.all;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHeader(
              title: ref.tr('all_videos'),
              trailing: ref.tracksCount(items.length),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Tooltip(
                    message: ref.tr('favorites_only'),
                    child: FilterChip(
                      selected: favoritesOnly,
                      showCheckmark: false,
                      avatar: AppSvgIcon(
                        favoritesOnly ? 'favorite_filled' : 'favorite',
                        size: 18,
                      ),
                      label: Text(ref.tr('videos_favorites')),
                      onSelected: (value) =>
                          ref.read(favoritesOnlyProvider.notifier).state =
                              value,
                    ),
                  ),
                  PopupMenuButton<VideosQuickFilter>(
                    tooltip: ref.tr('filter'),
                    initialValue: quickFilter,
                    onSelected: (value) =>
                        ref.read(videosQuickFilterProvider.notifier).state =
                            value,
                    itemBuilder: (_) => [
                      for (final value in VideosQuickFilter.values)
                        CheckedPopupMenuItem(
                          value: value,
                          checked: value == quickFilter,
                          child: Text(
                            ref.tr(switch (value) {
                              VideosQuickFilter.all => 'filter_all',
                              VideosQuickFilter.withLyrics =>
                                'filter_with_lyrics',
                              VideosQuickFilter.withoutLyrics =>
                                'filter_without_lyrics',
                              VideosQuickFilter.notPlayed =>
                                'filter_not_played',
                            }),
                          ),
                        ),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: themeBorder(context)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.filter_list_rounded, size: 18),
                          const SizedBox(width: 6),
                          Text(
                            ref.tr(switch (quickFilter) {
                              VideosQuickFilter.all => 'filter_all',
                              VideosQuickFilter.withLyrics =>
                                'filter_with_lyrics',
                              VideosQuickFilter.withoutLyrics =>
                                'filter_without_lyrics',
                              VideosQuickFilter.notPlayed =>
                                'filter_not_played',
                            }),
                          ),
                          const SizedBox(width: 4),
                          const AppSvgIcon('chevron_down', size: 14),
                        ],
                      ),
                    ),
                  ),
                  PopupMenuButton<VideosSort>(
                    tooltip: ref.tr('sort'),
                    initialValue: sort,
                    onSelected: (value) =>
                        ref.read(videosSortProvider.notifier).state = value,
                    itemBuilder: (_) => [
                      for (final value in [
                        VideosSort.recentlyPlayed,
                        VideosSort.newestFirst,
                        VideosSort.oldestFirst,
                        VideosSort.name,
                        VideosSort.manual,
                      ])
                        CheckedPopupMenuItem(
                          value: value,
                          checked: value == sort,
                          child: Text(_sortLabel(value)),
                        ),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: themeBorder(context)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const AppSvgIcon('sort', size: 18),
                          const SizedBox(width: 8),
                          Text(_sortLabel(sort)),
                          const SizedBox(width: 8),
                          const AppSvgIcon('chevron_down', size: 14),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: ref.tr('shuffle'),
                    icon: const Icon(Icons.shuffle_rounded, size: 20),
                    onPressed: ids.isEmpty
                        ? null
                        : () {
                            showPlayerView(ref);
                            ref
                                .read(queueProvider.notifier)
                                .start(ids, shuffle: true);
                            ref.read(playbackControllerProvider).openCurrent();
                          },
                  ),
                  IconButton(
                    tooltip: ref.tr('play'),
                    icon: const Icon(Icons.play_arrow_rounded),
                    onPressed: ids.isEmpty
                        ? null
                        : () => _playFromHere(ref, ids, 0),
                  ),
                  IconButton(
                    tooltip: ref.tr(
                      _selectionMode ? 'select_all' : 'select_multiple',
                    ),
                    icon: _selectionMode
                        ? const Icon(Icons.select_all_rounded)
                        : AppSvgIcon(
                            'collection_select',
                            size: 20,
                            color: themeTextSub(context),
                          ),
                    onPressed: _selectionMode
                        ? () => _selectAllVisible(items)
                        : () => setState(() => _selectionMode = true),
                  ),
                  if (_selectionMode) ...[
                    Chip(
                      label: Text(
                        ref
                            .tr('selected_count')
                            .replaceAll(
                              '{count}',
                              '${_selectedMediaIds.length}',
                            ),
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _selectedMediaIds.isEmpty
                          ? null
                          : () => _addSelectionToPlaylist(context, ref),
                      icon: const Icon(Icons.playlist_add_rounded, size: 18),
                      label: Text(ref.tr('add_playlist')),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _selectedMediaIds.isEmpty
                          ? null
                          : () => _addSelectionToAlbum(context, ref),
                      icon: const Icon(Icons.album_outlined, size: 18),
                      label: Text(ref.tr('add_to_album')),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _selectedMediaIds.isEmpty
                          ? null
                          : () => _editSelectionArtist(context, ref),
                      icon: const Icon(Icons.person_outline_rounded, size: 18),
                      label: Text(ref.tr('batch_edit_artist')),
                    ),
                    TextButton(
                      onPressed: _leaveSelectionMode,
                      child: Text(ref.tr('cancel')),
                    ),
                  ],
                  if (creatorFilter != null)
                    InputChip(
                      label: Text(
                        '${ref.tr('metadata_artist')}: $creatorFilter',
                      ),
                      deleteIcon: const AppSvgIcon('close', size: 16),
                      onDeleted: () =>
                          ref.read(videoCreatorFilterProvider.notifier).state =
                              null,
                    ),
                  if (query.isNotEmpty)
                    InputChip(
                      label: Text(
                        ref
                            .tr('videos_search_filter')
                            .replaceAll(
                              '{query}',
                              ref.read(searchQueryProvider).trim(),
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      deleteIcon: const AppSvgIcon('close', size: 16),
                      onDeleted: () =>
                          ref.read(searchQueryProvider.notifier).state = '',
                    ),
                  if (filtered)
                    TextButton(
                      onPressed: _clearFilters,
                      child: Text(ref.tr('videos_reset_filters')),
                    ),
                ],
              ),
            ),
            if (sort == VideosSort.manual &&
                !filtered &&
                items.isNotEmpty &&
                !_selectionMode)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  ref.tr('videos_manual_hint'),
                  style: TextStyle(fontSize: 12, color: themeTextSub(context)),
                ),
              ),
            // Wide lists keep aligned columns; narrow lists prioritize titles.
            if (!compact)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 32,
                      child: Text(
                        '#',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: themeTextSub(context),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        ref.tr('title_video'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: themeTextSub(context),
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 70,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          ref.tr('videos_duration'),
                          style: TextStyle(
                            fontSize: 12,
                            color: themeTextSub(context),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: sort == VideosSort.manual ? 104 : 48,
                    ), // reorder and menu space
                  ],
                ),
              ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Divider(height: 1, color: themeBorder(context)),
            ),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AppSvgIcon(
                              filtered ? 'search' : 'video',
                              size: 36,
                              color: themeTextSub(context),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              ref.tr(
                                query.isNotEmpty || creatorFilter != null
                                    ? 'not_found'
                                    : favoritesOnly
                                    ? 'favorites_empty'
                                    : 'empty_library',
                              ),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (filtered) ...[
                              const SizedBox(height: 8),
                              Text(
                                ref.tr('videos_filter_hint'),
                                textAlign: TextAlign.center,
                                style: TextStyle(color: themeTextSub(context)),
                              ),
                              const SizedBox(height: 16),
                              OutlinedButton(
                                onPressed: _clearFilters,
                                child: Text(ref.tr('videos_reset_filters')),
                              ),
                            ],
                          ],
                        ),
                      ),
                    )
                  : sort == VideosSort.manual &&
                        !favoritesOnly &&
                        query.isEmpty &&
                        creatorFilter == null &&
                        !_selectionMode
                  ? ReorderableListView.builder(
                      scrollController: _scrollController,
                      buildDefaultDragHandles: false,
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                      itemCount: items.length,
                      // ignore: deprecated_member_use
                      onReorder: (oldIndex, newIndex) {
                        if (newIndex > oldIndex) newIndex--;
                        ref
                            .read(libraryProvider.notifier)
                            .reorderMedia(oldIndex, newIndex);
                      },
                      itemBuilder: (context, i) => _buildTrackRow(
                        context,
                        ref,
                        items,
                        ids,
                        currentId,
                        i,
                        reorderable: true,
                      ),
                    )
                  : ListView.separated(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 3),
                      itemBuilder: (context, i) => _buildTrackRow(
                        context,
                        ref,
                        items,
                        ids,
                        currentId,
                        i,
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTrackRow(
    BuildContext context,
    WidgetRef ref,
    List<MediaItem> items,
    List<String> ids,
    String? currentId,
    int i, {
    bool reorderable = false,
  }) {
    final m = items[i];
    final playing = m.id == currentId;
    final row = SizedBox(
      height: _rowExtent(context),
      child: _TrackRow(
        index: i + 1,
        media: m,
        playing: playing,
        highlighted: m.id == _highlightedId,
        reorderable: reorderable,
        selectionMode: _selectionMode,
        selected: _selectedMediaIds.contains(m.id),
        onToggleSelection: () => _toggleSelection(m.id),
        onPlay: () => _playFromHere(ref, ids, i),
        onPlayNext: () {
          final wasEmpty = !ref.read(queueProvider).hasCurrent;
          ref.read(queueProvider.notifier).playNext(m.id);
          if (wasEmpty) ref.read(playbackControllerProvider).openCurrent();
        },
        onAddToPlaylist: () => _addMediaToPlaylist(context, ref, m),
        onOpenArtist: () {
          final artist = m.artist?.trim();
          if (artist == null || artist.isEmpty) return;
          ref.read(creatorVideosRequestProvider.notifier).state = artist;
        },
      ),
    );
    final contextualRow = TrackContextMenuRegion(
      ref: ref,
      media: m,
      child: row,
    );
    if (!reorderable) return contextualRow;
    return KeyedSubtree(key: ValueKey('video-${m.id}'), child: contextualRow);
  }
}

class _TrackRow extends ConsumerStatefulWidget {
  final bool reorderable;
  final int index;
  final MediaItem media;
  final bool playing;
  final bool highlighted;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onPlay;
  final VoidCallback onPlayNext;
  final VoidCallback onAddToPlaylist;
  final VoidCallback onOpenArtist;
  final VoidCallback onToggleSelection;

  const _TrackRow({
    required this.index,
    required this.media,
    required this.playing,
    required this.highlighted,
    required this.selectionMode,
    required this.selected,
    required this.onPlay,
    required this.onPlayNext,
    required this.onAddToPlaylist,
    required this.onOpenArtist,
    required this.onToggleSelection,
    this.reorderable = false,
  });

  @override
  ConsumerState<_TrackRow> createState() => _TrackRowState();
}

class _TrackRowState extends ConsumerState<_TrackRow> {
  bool _hover = false;

  Widget _reorderHandle(BuildContext context) => SizedBox(
    width: 44,
    height: 44,
    child: Center(
      child: AppSvgIcon(
        'playlist_reorder',
        size: 16,
        color: themeTextSub(context).withValues(alpha: 0.72),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final rowHoverColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.05);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        final thumbnail = ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: compact ? 44 : 54,
            height: compact ? 44 : 34,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ThumbImage(
                  seed: widget.media.title,
                  mediaId: widget.media.id,
                  localPath: widget.media.localPath,
                  imageContext: MediaImageContext.home,
                ),
                if (widget.playing)
                  Container(
                    color: Colors.black.withValues(alpha: 0.3),
                    child: const Center(
                      child: AppSvgIcon(
                        'volume',
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
        return MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          cursor: SystemMouseCursors.click,
          child: Semantics(
            button: true,
            selected: widget.selectionMode ? widget.selected : widget.playing,
            label: widget.selectionMode
                ? ref.tr('select_multiple')
                : widget.playing
                ? ref.tr('videos_current_track')
                : null,
            child: GestureDetector(
              onTap: widget.selectionMode
                  ? widget.onToggleSelection
                  : widget.onPlay,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: widget.selected
                      ? themeAccent(
                          context,
                        ).withValues(alpha: isDark ? 0.2 : 0.12)
                      : _hover
                      ? rowHoverColor
                      : (widget.highlighted
                            ? themeAccent(
                                context,
                              ).withValues(alpha: isDark ? 0.24 : 0.18)
                            : (widget.playing
                                  ? (isDark
                                        ? themeAccent(
                                            context,
                                          ).withValues(alpha: 0.12)
                                        : themeAccent(
                                            context,
                                          ).withValues(alpha: 0.08))
                                  : Colors.transparent)),
                  boxShadow: widget.highlighted
                      ? [
                          BoxShadow(
                            color: themeAccent(context).withValues(alpha: 0.28),
                            blurRadius: 16,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    // Index stays on wide rows; artwork identifies compact rows.
                    if (widget.selectionMode)
                      Checkbox(
                        value: widget.selected,
                        onChanged: (_) => widget.onToggleSelection(),
                      )
                    else if (!compact) ...[
                      SizedBox(
                        width: 32,
                        child: Center(
                          child: widget.playing
                              ? AppSvgIcon(
                                  'equalizer',
                                  size: 20,
                                  color: themeAccent(context),
                                )
                              : (_hover
                                    ? AppSvgIcon(
                                        'play',
                                        size: 24,
                                        color: themeAccent(context),
                                      )
                                    : Text(
                                        '${widget.index}',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: isDark
                                              ? kTextMuted
                                              : Colors.black45,
                                        ),
                                      )),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    thumbnail,
                    const SizedBox(width: 14),
                    // Title & details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  displayTitle(widget.media.title),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: widget.playing
                                        ? FontWeight.bold
                                        : FontWeight.w500,
                                    color: widget.playing
                                        ? (isDark
                                              ? themeAccentHighlight(context)
                                              : const Color(0xFF333333))
                                        : (isDark
                                              ? Colors.white
                                              : Colors.black87),
                                  ),
                                ),
                              ),
                              if (widget.media.isFavorite)
                                Padding(
                                  padding: const EdgeInsetsDirectional.only(
                                    start: 8,
                                  ),
                                  child: AppSvgIcon(
                                    'favorite_filled',
                                    size: 14,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.media.artist != null &&
                                    widget.media.artist!.trim().isNotEmpty
                                ? formatCreatorNames(widget.media.artist)
                                : (widget.media.origin == 'referenced'
                                      ? ref.tr('referenced_video')
                                      : ref.tr('video')),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? kTextSub : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!compact) ...[
                      const SizedBox(width: 16),
                      // Duration
                      SizedBox(
                        width: 70,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: DurationText(
                            mediaId: widget.media.id,
                            localPath: widget.media.localPath,
                            durationMs: widget.media.durationMs,
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? kTextSub : Colors.black54,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (widget.reorderable)
                      Tooltip(
                        message: ref.tr('drag_to_reorder'),
                        child: compact
                            ? ReorderableDelayedDragStartListener(
                                index: widget.index - 1,
                                child: _reorderHandle(context),
                              )
                            : ReorderableDragStartListener(
                                index: widget.index - 1,
                                child: _reorderHandle(context),
                              ),
                      ),
                    if (!widget.selectionMode) ...[
                      if (widget.reorderable) const SizedBox(width: 12),
                      // Action menu
                      PopupMenuButton<String>(
                        tooltip: ref.tr('menu'),
                        icon: AppSvgIcon(
                          'more_horizontal',
                          size: 20,
                          color: _hover
                              ? (isDark ? Colors.white : Colors.black87)
                              : themeTextSub(context),
                        ),
                        onSelected: (v) {
                          if (v == 'play_next') {
                            widget.onPlayNext();
                          } else if (v == 'add_playlist') {
                            widget.onAddToPlaylist();
                          } else if (v == 'open_artist') {
                            widget.onOpenArtist();
                          } else if (v == 'favorite') {
                            ref
                                .read(libraryProvider.notifier)
                                .toggleFavorite(widget.media.id);
                          } else if (v == 'extension_actions') {
                            showTrackExtensionActions(
                              context,
                              ref,
                              widget.media,
                            );
                          }
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'play_next',
                            child: Row(
                              children: [
                                const AppSvgIcon('play_next', size: 20),
                                const SizedBox(width: 10),
                                Text(ref.tr('add_next')),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'add_playlist',
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.playlist_add_rounded,
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Text(ref.tr('add_playlist')),
                              ],
                            ),
                          ),
                          const PopupMenuDivider(),
                          PopupMenuItem(
                            value: 'favorite',
                            child: Row(
                              children: [
                                AppSvgIcon(
                                  widget.media.isFavorite
                                      ? 'favorite_filled'
                                      : 'favorite',
                                  size: 20,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  ref.tr(
                                    widget.media.isFavorite
                                        ? 'remove_favorite'
                                        : 'add_favorite',
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (widget.media.artist?.trim().isNotEmpty == true)
                            PopupMenuItem(
                              value: 'open_artist',
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.person_outline_rounded,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(ref.tr('open_artist_videos')),
                                ],
                              ),
                            ),
                          if (ref
                              .read(extensionRegistryProvider)
                              .any(
                                (extension) =>
                                    extension.enabled &&
                                    extension.grantedPermissions.contains(
                                      YureruExtensionPermission.uiContribution,
                                    ),
                              )) ...[
                            const PopupMenuDivider(),
                            PopupMenuItem(
                              value: 'extension_actions',
                              child: Row(
                                children: [
                                  const Icon(Icons.extension_rounded, size: 20),
                                  const SizedBox(width: 10),
                                  Text(ref.tr('extension_track_actions')),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
