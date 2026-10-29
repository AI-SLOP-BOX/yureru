import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../app_state.dart';
import '../../domain/models.dart';
import '../../library/media_order.dart';
import '../../domain/creator_names.dart';
import '../../playback/playback_controller.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets/duration_text.dart';
import '../widgets/app_svg_icon.dart';
import '../widgets/page_header.dart';
import '../widgets/thumb_image.dart';

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
  }

  final ScrollController _scrollController = ScrollController();
  Timer? _highlightTimer;
  String? _highlightedId;
  String? _scheduledRequestId;

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

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final lib = ref.watch(libraryProvider);
    final query = ref.watch(searchQueryProvider).trim().toLowerCase();
    final creatorFilter = ref.watch(videoCreatorFilterProvider)?.trim();
    final sort = ref.watch(videosSortProvider);
    final favoritesOnly = ref.watch(favoritesOnlyProvider);
    final currentId = ref.watch(queueProvider.select((q) => q.currentId));
    if (!lib.loaded) return const Center(child: CircularProgressIndicator());
    final items = lib.savedMedia
        .where(
          (m) =>
              (!favoritesOnly || m.isFavorite) &&
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
    final filtered = query.isNotEmpty || creatorFilter != null || favoritesOnly;
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
            if (sort == VideosSort.manual && !filtered && items.isNotEmpty)
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
                    const SizedBox(width: 48), // menu space
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
                        creatorFilter == null
                  ? ReorderableListView.builder(
                      scrollController: _scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                      itemCount: items.length,
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
        onPlay: () => _playFromHere(ref, ids, i),
        onAddToPlaylist: () => _addToPlaylist(context, ref, m.id),
        onPlayNext: () {
          final wasEmpty = !ref.read(queueProvider).hasCurrent;
          ref.read(queueProvider.notifier).playNext(m.id);
          if (wasEmpty) ref.read(playbackControllerProvider).openCurrent();
        },
        onEnqueue: () => ref.read(queueProvider.notifier).append(m.id),
        onChangeThumbnail: () => _changeThumbnail(context, ref, m),
        onChangeArtwork: () => _changeArtwork(context, ref, m),
        onDelete: () => _confirmDelete(context, ref, m),
      ),
    );
    if (!reorderable) return row;
    return KeyedSubtree(
      key: ValueKey('video-${m.id}'),
      child: ReorderableDelayedDragStartListener(index: i, child: row),
    );
  }

  Future<void> _changeThumbnail(
    BuildContext context,
    WidgetRef ref,
    MediaItem media,
  ) => _chooseAndSaveImage(context, ref, media, artwork: false);

  Future<void> _changeArtwork(
    BuildContext context,
    WidgetRef ref,
    MediaItem media,
  ) => _chooseAndSaveImage(context, ref, media, artwork: true);

  Future<void> _chooseAndSaveImage(
    BuildContext context,
    WidgetRef ref,
    MediaItem media, {
    required bool artwork,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: false,
    );
    final sourcePath = result?.files.single.path;
    if (sourcePath == null) return;
    try {
      final dir = await getApplicationSupportDirectory();
      final imageDir = Directory(
        '${dir.path}/${artwork ? 'yureru_artwork' : 'yureru_thumbnails'}',
      );
      await imageDir.create(recursive: true);
      final extension = sourcePath.contains('.')
          ? sourcePath.split('.').last.toLowerCase()
          : 'png';
      final destination =
          '${imageDir.path}/${media.id}_${DateTime.now().microsecondsSinceEpoch}.$extension';
      await File(sourcePath).copy(destination);
      if (artwork) {
        await ref
            .read(libraryProvider.notifier)
            .updateMediaArtwork(media.id, destination);
      } else {
        await ref
            .read(libraryProvider.notifier)
            .updateMediaThumbnail(media.id, destination);
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ref.tr('thumbnail_change_failed').replaceAll('{error}', '$error'),
            ),
          ),
        );
      }
    }
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, MediaItem media) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(ref.tr('delete_from_library')),
        content: Text(
          ref.tr('remove_media_confirm').replaceAll('{title}', media.title),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(ref.tr('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kAccent),
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(libraryProvider.notifier).removeMedia(media.id);
            },
            child: Text(ref.tr('delete')),
          ),
        ],
      ),
    );
  }

  void _addToPlaylist(BuildContext context, WidgetRef ref, String mediaId) {
    final lib = ref.read(libraryProvider);
    if (lib.playlists.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(ref.tr('empty_playlist'))));
      return;
    }
    showDialog(
      context: context,
      builder: (_) => SimpleDialog(
        title: Text(ref.tr('add_playlist')),
        children: [
          for (final pl in lib.playlists)
            SimpleDialogOption(
              onPressed: () async {
                await ref
                    .read(libraryProvider.notifier)
                    .addToPlaylist(pl.id, mediaId);
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        ref
                            .tr('added_to_playlist')
                            .replaceAll('{name}', displayTitle(pl.name)),
                      ),
                    ),
                  );
                }
              },
              child: Text(
                displayTitle(pl.name),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }
}

class _TrackRow extends ConsumerStatefulWidget {
  final bool reorderable;
  final int index;
  final MediaItem media;
  final bool playing;
  final bool highlighted;
  final VoidCallback onPlay;
  final VoidCallback onAddToPlaylist;
  final VoidCallback onPlayNext;
  final VoidCallback onEnqueue;
  final VoidCallback onChangeThumbnail;
  final VoidCallback onChangeArtwork;
  final VoidCallback onDelete;

  const _TrackRow({
    required this.index,
    required this.media,
    required this.playing,
    required this.highlighted,
    required this.onPlay,
    required this.onAddToPlaylist,
    required this.onPlayNext,
    required this.onEnqueue,
    required this.onChangeThumbnail,
    required this.onChangeArtwork,
    required this.onDelete,
    this.reorderable = false,
  });

  @override
  ConsumerState<_TrackRow> createState() => _TrackRowState();
}

class _TrackRowState extends ConsumerState<_TrackRow> {
  bool _hover = false;

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
        return MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          cursor: SystemMouseCursors.click,
          child: Semantics(
            button: true,
            selected: widget.playing,
            label: widget.playing ? ref.tr('videos_current_track') : null,
            child: GestureDetector(
              onTap: widget.onPlay,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _hover
                      ? rowHoverColor
                      : (widget.highlighted
                            ? kAccent.withValues(alpha: isDark ? 0.24 : 0.18)
                            : (widget.playing
                                  ? (isDark
                                        ? kAccent.withValues(alpha: 0.12)
                                        : kAccent.withValues(alpha: 0.08))
                                  : Colors.transparent)),
                  boxShadow: widget.highlighted
                      ? [
                          BoxShadow(
                            color: kAccent.withValues(alpha: 0.28),
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
                    if (!compact) ...[
                      SizedBox(
                        width: 32,
                        child: Center(
                          child: widget.playing
                              ? const AppSvgIcon(
                                  'equalizer',
                                  size: 20,
                                  color: kAccent,
                                )
                              : (_hover
                                    ? const AppSvgIcon(
                                        'play',
                                        size: 24,
                                        color: kAccent,
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
                    // Thumbnail
                    ClipRRect(
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
                    ),
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
                                              ? kAccentLight
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
                    if (widget.reorderable && !compact)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: AppSvgIcon(
                          'drag',
                          size: 20,
                          color: isDark ? kTextMuted : Colors.black38,
                        ),
                      ),
                    IconButton(
                      key: ValueKey('video-play-next-${widget.media.id}'),
                      tooltip: ref.tr('add_next'),
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                      padding: EdgeInsets.zero,
                      icon: Icon(
                        Icons.arrow_forward_rounded,
                        size: 20,
                        color: _hover
                            ? (isDark ? Colors.white : Colors.black87)
                            : themeTextSub(context),
                      ),
                      onPressed: widget.onPlayNext,
                    ),
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
                        switch (v) {
                          case 'favorite':
                            ref
                                .read(libraryProvider.notifier)
                                .toggleFavorite(widget.media.id);
                            break;
                          case 'enqueue':
                            widget.onEnqueue();
                            break;
                          case 'addToPlaylist':
                            widget.onAddToPlaylist();
                            break;
                          case 'changeThumbnail':
                            widget.onChangeThumbnail();
                            break;
                          case 'changeArtwork':
                            widget.onChangeArtwork();
                            break;
                          case 'delete':
                            widget.onDelete();
                            break;
                        }
                      },
                      itemBuilder: (_) => [
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
                        PopupMenuItem(
                          value: 'enqueue',
                          child: Row(
                            children: [
                              AppSvgIcon('queue_add', size: 20),
                              SizedBox(width: 10),
                              Text(ref.tr('add_queue')),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'addToPlaylist',
                          child: Row(
                            children: [
                              AppSvgIcon('playlist_add', size: 20),
                              SizedBox(width: 10),
                              Text(ref.tr('add_playlist')),
                            ],
                          ),
                        ),
                        PopupMenuDivider(),
                        PopupMenuItem(
                          value: 'changeThumbnail',
                          child: Row(
                            children: [
                              const Icon(Icons.image_outlined, size: 20),
                              SizedBox(width: 10),
                              Text(ref.tr('change_thumbnail')),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'changeArtwork',
                          child: Row(
                            children: [
                              AppSvgIcon('artwork', size: 20),
                              SizedBox(width: 10),
                              Text(ref.tr('artwork')),
                            ],
                          ),
                        ),
                        PopupMenuDivider(),
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              AppSvgIcon(
                                'delete',
                                size: 20,
                                color: Colors.redAccent,
                              ),
                              SizedBox(width: 10),
                              Text(
                                ref.tr('delete_from_library_short'),
                                style: TextStyle(color: Colors.redAccent),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
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
