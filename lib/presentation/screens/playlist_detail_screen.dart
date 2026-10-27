import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../app_state.dart';
import '../../domain/creator_names.dart';
import '../../playback/playback_controller.dart';
import '../i18n.dart';
import '../layout_metrics.dart';
import '../theme.dart';
import '../widgets/duration_text.dart';
import '../widgets/frosted_panel.dart';
import '../widgets/thumb_image.dart';

/// Playlist detail (center-pane body; the shell owns nav/transport chrome).
class PlaylistDetailScreen extends ConsumerStatefulWidget {
  final String playlistId;
  final VoidCallback? onBack;
  const PlaylistDetailScreen({
    super.key,
    required this.playlistId,
    this.onBack,
  });

  @override
  ConsumerState<PlaylistDetailScreen> createState() =>
      _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends ConsumerState<PlaylistDetailScreen> {
  static const double _desktopContentMaxWidth = 1440;
  bool _showSearch = false;
  bool _sortByCreator = false;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Widget _contentFrame({required Widget child}) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: _desktopContentMaxWidth),
      child: child,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final lib = ref.watch(libraryProvider);
    final currentId = ref.watch(queueProvider.select((q) => q.currentId));
    final pl = lib.playlistById(widget.playlistId);
    if (pl == null) {
      return Center(
        child: Text(
          ref.tr('playlist_not_found'),
          style: TextStyle(color: kTextSub),
        ),
      );
    }
    final first = pl.mediaIds.isEmpty ? null : lib.byId(pl.mediaIds.first);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final horizontalInset = LayoutMetrics.horizontalInset(context);
    // Keep short playlist names from making the header feel artwork-heavy on
    // desktop, while preserving a generous cover size on compact screens.
    final artworkSize = (screenWidth * (screenWidth < 600 ? 0.34 : 0.16))
        .clamp(
          screenWidth < 600 ? 108.0 : 184.0,
          screenWidth < 600 ? 152.0 : 220.0,
        )
        .toDouble();
    final artworkGap = screenWidth < 600 ? 14.0 : 20.0;

    // Filter media items when search query is active
    final query = _searchQuery.trim().toLowerCase();
    final filteredMediaIds =
        (query.isEmpty
                ? pl.mediaIds
                : pl.mediaIds.where((id) {
                    final m = lib.byId(id);
                    if (m == null) return false;
                    final titleMatch = m.title.toLowerCase().contains(query);
                    final artistMatch = (m.artist ?? '')
                        .trim()
                        .toLowerCase()
                        .contains(query);
                    return titleMatch || artistMatch;
                  }).toList())
            .toList();
    if (_sortByCreator) {
      filteredMediaIds.sort((a, b) {
        final aMedia = lib.byId(a);
        final bMedia = lib.byId(b);
        final aCreator = aMedia?.artist?.trim() ?? '';
        final bCreator = bMedia?.artist?.trim() ?? '';
        if (aCreator.isEmpty != bCreator.isEmpty) {
          return aCreator.isEmpty ? 1 : -1;
        }
        final creatorOrder = aCreator.toLowerCase().compareTo(
          bCreator.toLowerCase(),
        );
        if (creatorOrder != 0) return creatorOrder;
        return (aMedia?.title ?? '').toLowerCase().compareTo(
          (bMedia?.title ?? '').toLowerCase(),
        );
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          children: [
            if (first?.localPath != null)
              Positioned.fill(
                child: ClipRect(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 36, sigmaY: 36),
                        child: ThumbImage(
                          seed: pl.id,
                          mediaId: first!.id,
                          localPath: first.localPath,
                          size: artworkSize,
                          expand: true,
                        ),
                      ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              theme.scaffoldBackgroundColor.withValues(
                                alpha: isDark ? 0.42 : 0.5,
                              ),
                              theme.scaffoldBackgroundColor.withValues(
                                alpha: isDark ? 0.68 : 0.76,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            _contentFrame(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalInset,
                  16,
                  horizontalInset,
                  16,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Back button if applicable
                    if (widget.onBack != null) ...[
                      IconButton(
                        tooltip: ref.tr('back'),
                        icon: const Icon(Icons.arrow_back),
                        onPressed: widget.onBack,
                      ),
                      const SizedBox(width: 12),
                    ],
                    // Large Playlist Artwork
                    Container(
                      width: artworkSize,
                      height: artworkSize,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.45),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: first?.localPath == null
                          ? Container(
                              decoration: BoxDecoration(
                                gradient: thumbGradient(pl.id),
                              ),
                              child: const Icon(
                                Icons.playlist_play_rounded,
                                size: 64,
                                color: Colors.white70,
                              ),
                            )
                          : ThumbImage(
                              seed: pl.id,
                              mediaId: first?.id,
                              localPath: first?.localPath,
                              size: artworkSize,
                              radius: 16,
                              expand: true,
                            ),
                    ),
                    SizedBox(width: artworkGap),
                    // Title, meta info & action buttons layout
                    Flexible(
                      fit: FlexFit.loose,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 560),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white10 : Colors.black12,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                ref.tr('playlists'),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                  color: isDark ? kTextSub : Colors.black54,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              displayTitle(pl.name),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              ref.tracksCount(pl.mediaIds.length),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: isDark ? kTextSub : Colors.black54,
                              ),
                            ),
                            const SizedBox(height: 14),
                            // Circular action trio: [Edit] [Play] [More]
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final tight = constraints.maxWidth < 210;
                                return Wrap(
                                  spacing: tight ? 4 : 14,
                                  runSpacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    // 1. Edit playlist button (dark circular icon button)
                                    _actionCircle(
                                      tooltip: ref.tr('edit_playlist'),
                                      icon: Icons.edit_rounded,
                                      iconSize: 20,
                                      buttonSize: tight ? 40 : 44,
                                      isDark: isDark,
                                      onTap: () =>
                                          _showRenameDialog(context, pl),
                                    ),
                                    // 2. Center Large White Play Button
                                    Material(
                                      color: pl.mediaIds.isEmpty
                                          ? (isDark
                                                ? Colors.white24
                                                : Colors.black12)
                                          : Colors.white,
                                      shape: const CircleBorder(),
                                      elevation: pl.mediaIds.isEmpty ? 0 : 3,
                                      clipBehavior: Clip.antiAlias,
                                      child: InkWell(
                                        onTap: pl.mediaIds.isEmpty
                                            ? null
                                            : () {
                                                showPlayerView(ref);
                                                ref
                                                    .read(
                                                      playbackControllerProvider,
                                                    )
                                                    .startPlaylist(
                                                      pl.id,
                                                      shuffle: false,
                                                    );
                                              },
                                        child: Container(
                                          width: tight ? 44 : 52,
                                          height: tight ? 44 : 52,
                                          alignment: Alignment.center,
                                          child: Icon(
                                            Icons.play_arrow_rounded,
                                            size: tight ? 30 : 34,
                                            color: pl.mediaIds.isEmpty
                                                ? Colors.white38
                                                : Colors.black,
                                          ),
                                        ),
                                      ),
                                    ),
                                    // 3. More options (PopupMenuButton formatted as dark circular button)
                                    _moreMenuButton(
                                      context,
                                      pl,
                                      isDark,
                                      buttonSize: tight ? 40 : 44,
                                    ),
                                  ],
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (screenWidth >= 1200) ...[
                      const SizedBox(width: 28),
                      SizedBox(
                        width: 270,
                        child: FrostedPanel(
                          borderRadius: BorderRadius.circular(16),
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!_sortByCreator && query.isEmpty) ...[
                                Row(
                                  children: [
                                    Icon(
                                      Icons.drag_indicator_rounded,
                                      size: 17,
                                      color: themeTextSub(context),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        ref.tr('drag_to_reorder'),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: themeTextSub(context),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Divider(height: 1, color: themeBorder(context)),
                                const SizedBox(height: 6),
                              ],
                              Row(
                                children: [
                                  IconButton(
                                    tooltip: ref.tr(
                                      _showSearch ? 'close' : 'search_playlist',
                                    ),
                                    visualDensity: VisualDensity.compact,
                                    icon: Icon(
                                      _showSearch
                                          ? Icons.close_rounded
                                          : Icons.search_rounded,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _showSearch = !_showSearch;
                                        if (!_showSearch) {
                                          _searchCtrl.clear();
                                          _searchQuery = '';
                                        }
                                      });
                                    },
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: PopupMenuButton<bool>(
                                      tooltip: ref.tr('sort'),
                                      initialValue: _sortByCreator,
                                      onSelected: (value) => setState(
                                        () => _sortByCreator = value,
                                      ),
                                      itemBuilder: (_) => [
                                        PopupMenuItem(
                                          value: false,
                                          child: Text(ref.tr('playlist_order')),
                                        ),
                                        PopupMenuItem(
                                          value: true,
                                          child: Text(ref.tr('creator_order')),
                                        ),
                                      ],
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: _sortByCreator
                                              ? themeTextSub(
                                                  context,
                                                ).withValues(alpha: 0.12)
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: _sortByCreator
                                                ? themeTextSub(
                                                    context,
                                                  ).withValues(alpha: 0.3)
                                                : Colors.transparent,
                                          ),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 8,
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                _sortByCreator
                                                    ? Icons
                                                          .sort_by_alpha_rounded
                                                    : Icons.sort_rounded,
                                                size: 18,
                                              ),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  ref.tr(
                                                    _sortByCreator
                                                        ? 'creator_order'
                                                        : 'playlist_order',
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const Icon(
                                                Icons.expand_more_rounded,
                                                size: 18,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),

        // Search bar if opened via "プレイリストで検索"
        if (_showSearch)
          _contentFrame(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalInset,
                0,
                horizontalInset,
                12,
              ),
              child: FrostedPanel(
                borderRadius: BorderRadius.circular(20),
                child: SizedBox(
                  height: 40,
                  child: Row(
                    children: [
                      const SizedBox(width: 14),
                      Icon(
                        Icons.search_rounded,
                        size: 20,
                        color: isDark ? kTextSub : Colors.black54,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          autofocus: true,
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          decoration: InputDecoration(
                            hintText: ref.tr('search_playlist'),
                            hintStyle: TextStyle(
                              fontSize: 13,
                              color: isDark ? kTextSub : Colors.black45,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: (val) {
                            setState(() {
                              _searchQuery = val;
                            });
                          },
                        ),
                      ),
                      if (_searchQuery.isNotEmpty)
                        IconButton(
                          tooltip: ref.tr('browse_clear_search'),
                          icon: const Icon(Icons.close_rounded, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() {
                              _searchQuery = '';
                            });
                          },
                        ),
                      const SizedBox(width: 6),
                    ],
                  ),
                ),
              ),
            ),
          ),

        if (screenWidth < 1200)
          _contentFrame(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalInset,
                2,
                horizontalInset,
                2,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: !_sortByCreator && query.isEmpty
                        ? Text(
                            ref.tr('drag_to_reorder'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: themeTextSub(context),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: ref.tr(
                          _showSearch ? 'close' : 'search_playlist',
                        ),
                        visualDensity: VisualDensity.compact,
                        icon: Icon(
                          _showSearch
                              ? Icons.close_rounded
                              : Icons.search_rounded,
                        ),
                        onPressed: () {
                          setState(() {
                            _showSearch = !_showSearch;
                            if (!_showSearch) {
                              _searchCtrl.clear();
                              _searchQuery = '';
                            }
                          });
                        },
                      ),
                      PopupMenuButton<bool>(
                        tooltip: ref.tr('sort'),
                        initialValue: _sortByCreator,
                        onSelected: (value) =>
                            setState(() => _sortByCreator = value),
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: false,
                            child: Text(ref.tr('playlist_order')),
                          ),
                          PopupMenuItem(
                            value: true,
                            child: Text(ref.tr('creator_order')),
                          ),
                        ],
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: _sortByCreator
                                ? themeTextSub(context).withValues(alpha: 0.12)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _sortByCreator
                                  ? themeTextSub(context).withValues(alpha: 0.3)
                                  : Colors.transparent,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _sortByCreator
                                      ? Icons.sort_by_alpha_rounded
                                      : Icons.sort_rounded,
                                  size: 18,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  ref.tr(
                                    _sortByCreator
                                        ? 'creator_order'
                                        : 'playlist_order',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        _contentFrame(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: horizontalInset),
            child: Divider(
              height: 1,
              color: theme.dividerColor.withValues(alpha: 0.55),
            ),
          ),
        ),

        Expanded(
          child: pl.mediaIds.isEmpty
              ? Center(
                  child: Text(
                    ref.tr('playlist_empty_detail'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: kTextSub, height: 1.6),
                  ),
                )
              : filteredMediaIds.isEmpty
              ? Center(
                  child: Text(
                    ref
                        .tr('no_playlist_matches')
                        .replaceAll('{query}', _searchQuery),
                    style: const TextStyle(color: kTextSub),
                  ),
                )
              : ReorderableListView(
                  buildDefaultDragHandles: false,
                  onReorder: (from, to) {
                    if (_sortByCreator || query.isNotEmpty) return;
                    if (to > from) to--;
                    ref
                        .read(libraryProvider.notifier)
                        .reorderPlaylist(pl.id, from, to);
                  },
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  children: [
                    for (int i = 0; i < filteredMediaIds.length; i++) ...[
                      () {
                        final m = lib.byId(filteredMediaIds[i]);
                        if (m == null) return const SizedBox.shrink();
                        void playFromHere() {
                          showPlayerView(ref);
                          ref
                              .read(queueProvider.notifier)
                              .start(
                                pl.mediaIds,
                                playlistId: pl.id,
                                shuffle: false,
                              );
                          final originalIndex = pl.mediaIds.indexOf(m.id);
                          ref
                              .read(queueProvider.notifier)
                              .jumpTo(originalIndex >= 0 ? originalIndex : 0);
                          ref.read(playbackControllerProvider).openCurrent();
                        }

                        final row = Dismissible(
                          key: ValueKey(m.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            color: Colors.red,
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 16),
                            child: const Icon(
                              Icons.delete,
                              color: Colors.white,
                            ),
                          ),
                          onDismissed: (_) => ref
                              .read(libraryProvider.notifier)
                              .removeFromPlaylist(pl.id, m.id),
                          child: Container(
                            decoration: BoxDecoration(
                              color: m.id == currentId
                                  ? (isDark ? kCard : const Color(0xFFF1F1F1))
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: ListTile(
                              minLeadingWidth: 0,
                              horizontalTitleGap: 10,
                              leading: SizedBox(
                                width: 78,
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 22,
                                      child: Center(
                                        child: m.id == currentId
                                            ? Icon(
                                                Icons.equalizer_rounded,
                                                size: 16,
                                                color: themeTextSub(context),
                                              )
                                            : Text(
                                                '${i + 1}'.padLeft(2, '0'),
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: themeTextSub(context),
                                                ),
                                              ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    ThumbImage(
                                      seed: m.id,
                                      mediaId: m.id,
                                      localPath: m.localPath,
                                      size: 48,
                                    ),
                                  ],
                                ),
                              ),
                              title: Text(
                                displayTitle(m.title),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: m.artist?.trim().isNotEmpty == true
                                  ? Text(
                                      formatCreatorNames(m.artist),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: themeTextSub(context),
                                      ),
                                    )
                                  : DurationText(
                                      mediaId: m.id,
                                      localPath: m.localPath,
                                      durationMs: m.durationMs,
                                    ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  m.id == currentId
                                      ? const SizedBox(width: 48)
                                      : IconButton(
                                          tooltip: ref.tr('play'),
                                          icon: const Icon(Icons.play_arrow),
                                          onPressed: playFromHere,
                                        ),
                                  if (!_sortByCreator && query.isEmpty)
                                    Tooltip(
                                      message: ref.tr('drag_to_reorder'),
                                      child: SizedBox(
                                        width: 52,
                                        height: 52,
                                        child: ReorderableDragStartListener(
                                          index: i,
                                          child: const Icon(
                                            Icons.drag_handle_rounded,
                                            size: 28,
                                            color: kTextSub,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              onTap: playFromHere,
                            ),
                          ),
                        );
                        final centeredRow = Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: _desktopContentMaxWidth,
                            ),
                            child: row,
                          ),
                        );
                        if (!_sortByCreator && query.isEmpty) {
                          return ReorderableDelayedDragStartListener(
                            key: ValueKey('playlist-row-${m.id}'),
                            index: i,
                            child: centeredRow,
                          );
                        }
                        return KeyedSubtree(
                          key: ValueKey('playlist-row-${m.id}'),
                          child: centeredRow,
                        );
                      }(),
                    ],
                    // When playlist has few items, offer quick additions from remaining library
                    if (lib.savedMedia.length > pl.mediaIds.length) ...[
                      const SizedBox(
                        key: ValueKey('playlist-add-gap'),
                        height: 24,
                      ),
                      KeyedSubtree(
                        key: const ValueKey('playlist-add-heading'),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: _desktopContentMaxWidth,
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.add_circle_outline_rounded,
                                    size: 18,
                                    color: themeTextSub(context),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    ref.tr('add_from_library'),
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      for (final cand
                          in lib.savedMedia
                              .where((item) => !pl.mediaIds.contains(item.id))
                              .take(5))
                        KeyedSubtree(
                          key: ValueKey('playlist-add-${cand.id}'),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxWidth: _desktopContentMaxWidth,
                              ),
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 2),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.03)
                                      : Colors.black.withValues(alpha: 0.02),
                                ),
                                child: ListTile(
                                  dense: true,
                                  leading: ThumbImage(
                                    seed: cand.id,
                                    mediaId: cand.id,
                                    localPath: cand.localPath,
                                    size: 40,
                                  ),
                                  title: Text(
                                    displayTitle(cand.title),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  subtitle:
                                      formatCreatorNames(cand.artist).isEmpty
                                      ? DurationText(
                                          mediaId: cand.id,
                                          localPath: cand.localPath,
                                          durationMs: cand.durationMs,
                                        )
                                      : Text(
                                          formatCreatorNames(cand.artist),
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: themeTextSub(context),
                                          ),
                                        ),
                                  trailing: IconButton(
                                    tooltip: ref.tr('add_playlist'),
                                    icon: Icon(
                                      Icons.add_rounded,
                                      size: 20,
                                      color: themeTextSub(context),
                                    ),
                                    onPressed: () async {
                                      await ref
                                          .read(libraryProvider.notifier)
                                          .addToPlaylist(pl.id, cand.id);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              ref
                                                  .tr('added_media_title')
                                                  .replaceAll(
                                                    '{title}',
                                                    displayTitle(cand.title),
                                                  ),
                                            ),
                                            duration: const Duration(
                                              seconds: 2,
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _actionCircle({
    required String tooltip,
    required IconData icon,
    required double iconSize,
    double buttonSize = 44,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: isDark ? const Color(0xFF242424) : const Color(0xFFE4E4E4),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            width: buttonSize,
            height: buttonSize,
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: iconSize,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }

  Widget _moreMenuButton(
    BuildContext context,
    dynamic pl,
    bool isDark, {
    double buttonSize = 44,
  }) {
    return Theme(
      data: Theme.of(context).copyWith(
        popupMenuTheme: PopupMenuThemeData(
          color: isDark ? const Color(0xFF212121) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 8,
        ),
      ),
      child: PopupMenuButton<String>(
        tooltip: ref.tr('menu'),
        offset: const Offset(0, 50),
        child: Material(
          color: isDark ? const Color(0xFF242424) : const Color(0xFFE4E4E4),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: Container(
            width: buttonSize,
            height: buttonSize,
            alignment: Alignment.center,
            child: Icon(
              Icons.more_vert_rounded,
              size: 22,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ),
        onSelected: (val) => _handleMenuAction(context, pl, val),
        itemBuilder: (ctx) => [
          _menuItem(
            'shuffle',
            'assets/icons/shuffle.svg',
            ref.tr('shuffle'),
            isDark,
          ),
          _menuItem(
            'play_next',
            'assets/icons/play_next.svg',
            ref.tr('add_next'),
            isDark,
          ),
          _menuItem(
            'add_to_queue',
            'assets/icons/queue_add.svg',
            ref.tr('add_queue'),
            isDark,
          ),
          _menuItem(
            'add_videos',
            'assets/icons/video_add.svg',
            ref.tr('add_videos'),
            isDark,
          ),
          _menuItem(
            'delete',
            'assets/icons/delete.svg',
            ref.tr('delete_playlist'),
            isDark,
            isDestructive: true,
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _menuItem(
    String value,
    String iconAsset,
    String label,
    bool isDark, {
    bool isDestructive = false,
  }) {
    final color = isDestructive
        ? Colors.redAccent
        : (isDark ? Colors.white : Colors.black87);
    return PopupMenuItem<String>(
      value: value,
      height: 44,
      child: Row(
        children: [
          SvgPicture.asset(
            iconAsset,
            width: 22,
            height: 22,
            colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
            excludeFromSemantics: true,
          ),
          const SizedBox(width: 14),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  void _handleMenuAction(
    BuildContext context,
    dynamic pl,
    String action,
  ) async {
    switch (action) {
      case 'shuffle':
        if (pl.mediaIds.isNotEmpty) {
          showPlayerView(ref);
          ref
              .read(playbackControllerProvider)
              .startPlaylist(pl.id, shuffle: true);
        }
        break;

      case 'play_next':
        if (pl.mediaIds.isNotEmpty) {
          for (final id in (pl.mediaIds as List<String>).reversed) {
            ref.read(queueProvider.notifier).playNext(id);
          }
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(ref.tr('playlist_added_next')),
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
        break;

      case 'add_to_queue':
        if (pl.mediaIds.isNotEmpty) {
          for (final id in pl.mediaIds as List<String>) {
            ref.read(queueProvider.notifier).append(id);
          }
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(ref.tr('playlist_added_queue')),
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
        break;

      case 'add_videos':
        _addSheet(context, ref);
        break;

      case 'delete':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(ref.tr('delete_playlist')),
            content: Text(
              ref.tr('delete_playlist_confirm').replaceAll('{name}', pl.name),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(ref.tr('cancel')),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(ref.tr('delete')),
              ),
            ],
          ),
        );
        if (confirmed == true && mounted) {
          await ref.read(libraryProvider.notifier).deletePlaylist(pl.id);
          if (context.mounted && widget.onBack != null) {
            widget.onBack!();
          }
        }
        break;
    }
  }

  Future<void> _showRenameDialog(BuildContext context, dynamic pl) async {
    final c = TextEditingController(text: pl.name);
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(ref.tr('rename')),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(ref.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, c.text),
            child: Text(ref.tr('save')),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await ref
          .read(libraryProvider.notifier)
          .renamePlaylist(pl.id, name.trim());
    }
  }

  Future<void> _importAndAddVideos(BuildContext context, WidgetRef ref) async {
    final library = ref.read(libraryProvider);
    try {
      final items = await ref
          .read(importerProvider)
          .pickForPlaylist(existingMedia: library.savedMedia);
      if (items.isEmpty) return;
      final notifier = ref.read(libraryProvider.notifier);
      await notifier.addMedia(items);
      await notifier.addMediaToPlaylist(
        widget.playlistId,
        items.map((item) => item.id).toList(),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ref
                  .tr('added_media_count')
                  .replaceAll('{count}', '${items.length}'),
            ),
          ),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ref.tr('add_media_failed').replaceAll('{error}', '$error'),
            ),
          ),
        );
      }
    }
  }

  void _addSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (_) => Consumer(
        builder: (sheetContext, ref, _) {
          final lib = ref.watch(libraryProvider);
          final ids =
              lib.playlistById(widget.playlistId)?.mediaIds.toSet() ??
              <String>{};
          final n = ref.read(libraryProvider.notifier);
          return ListView(
            children: [
              ListTile(
                leading: const Icon(Icons.video_library_outlined),
                title: Text(ref.tr('add_from_device')),
                subtitle: Text(ref.tr('add_from_device_desc')),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _importAndAddVideos(context, ref);
                },
              ),
              const Divider(height: 1),
              for (final m in lib.savedMedia)
                CheckboxListTile(
                  value: ids.contains(m.id),
                  title: Text(
                    displayTitle(m.title),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onChanged: (_) async {
                    if (ids.contains(m.id)) {
                      await n.removeFromPlaylist(widget.playlistId, m.id);
                    } else {
                      await n.addToPlaylist(widget.playlistId, m.id);
                    }
                  },
                ),
            ],
          );
        },
      ),
    );
  }
}
