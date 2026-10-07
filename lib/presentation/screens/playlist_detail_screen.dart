import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_state.dart';
import '../../playback/playback_controller.dart';
import '../layout_metrics.dart';
import '../theme.dart';
import '../widgets/duration_text.dart';
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
  bool _showSearch = false;
  bool _sortByCreator = false;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lib = ref.watch(libraryProvider);
    final currentId = ref.watch(queueProvider.select((q) => q.currentId));
    final pl = lib.playlistById(widget.playlistId);
    if (pl == null) {
      return const Center(
        child: Text('プレイリストが見つかりません', style: TextStyle(color: kTextSub)),
      );
    }
    final first = pl.mediaIds.isEmpty ? null : lib.byId(pl.mediaIds.first);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final horizontalInset = LayoutMetrics.horizontalInset(context);
    final artworkSize = (screenWidth * 0.36).clamp(108.0, 180.0).toDouble();
    final artworkGap = screenWidth < 600 ? 14.0 : 24.0;

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
        // Grand Hero Header aesthetic
        Stack(
          children: [
            // Ambient Glow behind the playlist header
            Positioned(
              left: 20,
              top: -20,
              child: IgnorePointer(
                child: Container(
                  width: artworkSize * 1.7,
                  height: artworkSize * 1.7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        kAccent.withValues(alpha: isDark ? 0.22 : 0.12),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Padding(
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
                      tooltip: '戻る',
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
                  Expanded(
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
                            'プレイリスト',
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
                          '${pl.mediaIds.length}本の動画',
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
                              spacing: tight ? 8 : 14,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                // 1. Edit playlist button (dark circular icon button)
                                _actionCircle(
                                  tooltip: 'プレイリストを編集',
                                  icon: Icons.edit_rounded,
                                  iconSize: 20,
                                  isDark: isDark,
                                  onTap: () => _showRenameDialog(context, pl),
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
                                _moreMenuButton(context, pl, isDark),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),

        // Search bar if opened via "プレイリストで検索"
        if (_showSearch)
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF262626)
                    : const Color(0xFFEAEAEA),
                borderRadius: BorderRadius.circular(20),
              ),
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
                        hintText: 'プレイリスト内を検索...',
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
                      icon: const Icon(Icons.close_rounded, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() {
                          _searchQuery = '';
                        });
                      },
                    ),
                  IconButton(
                    tooltip: '閉じる',
                    icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() {
                        _showSearch = false;
                        _searchQuery = '';
                      });
                    },
                  ),
                  const SizedBox(width: 6),
                ],
              ),
            ),
          ),

        Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              PopupMenuButton<bool>(
                tooltip: '並び替え',
                initialValue: _sortByCreator,
                onSelected: (value) => setState(() => _sortByCreator = value),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: false, child: Text('プレイリスト順')),
                  PopupMenuItem(value: true, child: Text('作成者順（未設定は下）')),
                ],
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.sort, size: 18),
                      SizedBox(width: 6),
                      Text(_sortByCreator ? '作成者順' : 'プレイリスト順'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 28),
          child: Divider(height: 1, color: Color(0x1FFFFFFF)),
        ),

        Expanded(
          child: pl.mediaIds.isEmpty
              ? const Center(
                  child: Text(
                    'このプレイリストは空です\nメニューの「動画を追加」からライブラリの動画を選べます',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: kTextSub, height: 1.6),
                  ),
                )
              : filteredMediaIds.isEmpty
              ? Center(
                  child: Text(
                    '「$_searchQuery」に一致する動画がありません',
                    style: const TextStyle(color: kTextSub),
                  ),
                )
              : ListView(
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

                        return Dismissible(
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
                                  ? (isDark ? kCard : const Color(0xFFEEECF8))
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: ListTile(
                              leading: ThumbImage(
                                seed: m.id,
                                mediaId: m.id,
                                localPath: m.localPath,
                                size: 48,
                              ),
                              title: Text(
                                displayTitle(m.title),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: m.artist != null
                                  ? Text(
                                      m.artist!,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: kTextSub,
                                      ),
                                    )
                                  : DurationText(
                                      mediaId: m.id,
                                      localPath: m.localPath,
                                      durationMs: m.durationMs,
                                    ),
                              trailing: m.id == currentId
                                  ? const Icon(
                                      Icons.equalizer,
                                      size: 20,
                                      color: kAccentLight,
                                    )
                                  : IconButton(
                                      tooltip: '再生',
                                      icon: const Icon(Icons.play_arrow),
                                      onPressed: playFromHere,
                                    ),
                              onTap: playFromHere,
                            ),
                          ),
                        );
                      }(),
                    ],
                    // When playlist has few items, offer quick additions from remaining library
                    if (lib.media.length > pl.mediaIds.length) ...[
                      const SizedBox(height: 24),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.add_circle_outline_rounded,
                              size: 18,
                              color: isDark ? kAccentLight : kAccent,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'ライブラリから曲を追加',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                      for (final cand
                          in lib.media
                              .where((item) => !pl.mediaIds.contains(item.id))
                              .take(5))
                        Container(
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
                            subtitle: Text(
                              cand.artist ?? '動画',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: kTextSub,
                              ),
                            ),
                            trailing: IconButton(
                              tooltip: 'プレイリストに追加',
                              icon: const Icon(
                                Icons.add_rounded,
                                size: 20,
                                color: kAccent,
                              ),
                              onPressed: () async {
                                await ref
                                    .read(libraryProvider.notifier)
                                    .addToPlaylist(pl.id, cand.id);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '「${displayTitle(cand.title)}」を追加しました',
                                      ),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                }
                              },
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
            width: 44,
            height: 44,
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

  Widget _moreMenuButton(BuildContext context, dynamic pl, bool isDark) {
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
        tooltip: 'メニュー',
        offset: const Offset(0, 50),
        child: Material(
          color: isDark ? const Color(0xFF242424) : const Color(0xFFE4E4E4),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: Container(
            width: 44,
            height: 44,
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
          _menuItem('shuffle', Icons.shuffle_rounded, 'シャッフル再生', isDark),
          _menuItem('search', Icons.search_rounded, 'プレイリストで検索', isDark),
          _menuItem('play_next', Icons.playlist_play_rounded, '次に再生', isDark),
          _menuItem(
            'add_to_queue',
            Icons.playlist_add_rounded,
            'キューに追加',
            isDark,
          ),
          _menuItem(
            'add_videos',
            Icons.add_circle_outline_rounded,
            '動画を追加',
            isDark,
          ),
          _menuItem(
            'delete',
            Icons.delete_outline_rounded,
            '再生リストを削除',
            isDark,
            isDestructive: true,
          ),
        ],
      ),
    );
  }

  PopupMenuItem<String> _menuItem(
    String value,
    IconData icon,
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
          Icon(icon, size: 22, color: color),
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

      case 'search':
        setState(() {
          _showSearch = true;
        });
        break;

      case 'play_next':
        if (pl.mediaIds.isNotEmpty) {
          for (final id in (pl.mediaIds as List<String>).reversed) {
            ref.read(queueProvider.notifier).playNext(id);
          }
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('プレイリストを次に再生へ追加しました'),
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
              const SnackBar(
                content: Text('プレイリストをキューに追加しました'),
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
            title: const Text('プレイリストを削除'),
            content: Text('「${pl.name}」を削除してもよろしいですか？\n動画ファイル自体はライブラリに残ります。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('キャンセル'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('削除'),
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
        title: const Text('名前を変更'),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, c.text),
            child: const Text('保存'),
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
          .pickForPlaylist(existingMedia: library.media);
      if (items.isEmpty) return;
      final notifier = ref.read(libraryProvider.notifier);
      await notifier.addMedia(items);
      await notifier.addMediaToPlaylist(
        widget.playlistId,
        items.map((item) => item.id).toList(),
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${items.length}本を動画一覧とプレイリストに追加しました')),
        );
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('動画の追加に失敗しました: $error')));
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
                title: const Text('端末から動画を追加'),
                subtitle: const Text('動画一覧にも自動で追加されます'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _importAndAddVideos(context, ref);
                },
              ),
              const Divider(height: 1),
              for (final m in lib.media)
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
