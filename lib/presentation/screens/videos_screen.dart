import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_state.dart';
import '../../domain/models.dart';
import '../../playback/playback_controller.dart';
import '../theme.dart';
import '../widgets/duration_text.dart';
import '../widgets/thumb_image.dart';
import 'home_screen.dart';

/// "すべての動画": Clean modern table view with track index, hover play preview,
/// clean alignment, and context actions.
class VideosScreen extends ConsumerWidget {
  const VideosScreen({super.key});

  void _playFromHere(WidgetRef ref, List<String> ids, int i) {
    showPlayerView(ref);
    ref.read(queueProvider.notifier).start(ids, shuffle: false);
    ref.read(queueProvider.notifier).jumpTo(i);
    ref.read(playbackControllerProvider).openCurrent();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider);
    final query = ref.watch(searchQueryProvider).trim().toLowerCase();
    final sort = ref.watch(videosSortProvider);
    final currentId = ref.watch(queueProvider.select((q) => q.currentId));
    if (!lib.loaded) return const Center(child: CircularProgressIndicator());
    final items = lib.media
        .where(
          (m) =>
              query.isEmpty ||
              m.title.toLowerCase().contains(query) ||
              (m.artist?.toLowerCase().contains(query) ?? false),
        )
        .toList();
    switch (sort) {
      case VideosSort.newestFirst:
        items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case VideosSort.oldestFirst:
        items.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case VideosSort.name:
        items.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
    }
    if (items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.movie_outlined, size: 56, color: kTextSub),
              SizedBox(height: 14),
              Text(
                '動画がありません',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 8),
              Text(
                '設定 → ライブラリ管理から動画・フォルダをインポートできます',
                textAlign: TextAlign.center,
                style: TextStyle(color: kTextSub, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }
    final ids = [for (final m in items) m.id];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: 'すべての動画',
          trailing: '${items.length}本',
          actions: PopupMenuButton<VideosSort>(
            tooltip: '並び替え',
            icon: const Icon(Icons.sort, size: 20),
            initialValue: sort,
            onSelected: (v) => ref.read(videosSortProvider.notifier).state = v,
            itemBuilder: (_) => const [
              PopupMenuItem(value: VideosSort.newestFirst, child: Text('新しい順')),
              PopupMenuItem(value: VideosSort.oldestFirst, child: Text('古い順')),
              PopupMenuItem(value: VideosSort.name, child: Text('名前順')),
            ],
          ),
        ),
        // Table Column Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
          child: Row(
            children: [
              const SizedBox(
                width: 32,
                child: Text(
                  '#',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: kTextMuted,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'タイトル / 動画',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: kTextMuted,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(
                width: 70,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Icon(
                    Icons.schedule_rounded,
                    size: 16,
                    color: kTextMuted,
                  ),
                ),
              ),
              const SizedBox(width: 48), // menu space
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Divider(height: 1, color: Color(0x1FFFFFFF)),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 3),
            itemBuilder: (c, i) {
              final m = items[i];
              final playing = m.id == currentId;
              return _TrackRow(
                index: i + 1,
                media: m,
                playing: playing,
                onPlay: () => _playFromHere(ref, ids, i),
                onAddToPlaylist: () => _addToPlaylist(context, ref, m.id),
                onPlayNext: () {
                  final wasEmpty = !ref.read(queueProvider).hasCurrent;
                  ref.read(queueProvider.notifier).playNext(m.id);
                  if (wasEmpty) {
                    ref.read(playbackControllerProvider).openCurrent();
                  }
                },
                onEnqueue: () => ref.read(queueProvider.notifier).append(m.id),
                onDelete: () => _confirmDelete(context, ref, m),
              );
            },
          ),
        ),
      ],
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, MediaItem media) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('ライブラリから削除'),
        content: Text('「${media.title}」をライブラリから削除しますか？\n（ファイル自体は削除されません）'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: kAccent),
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(libraryProvider.notifier).removeMedia(media.id);
            },
            child: const Text('削除'),
          ),
        ],
      ),
    );
  }

  void _addToPlaylist(BuildContext context, WidgetRef ref, String mediaId) {
    final lib = ref.read(libraryProvider);
    if (lib.playlists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('プレイリストがありません。サイドバーの＋から作成できます')),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('プレイリストに追加'),
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
                      content: Text('「${displayTitle(pl.name)}」に追加しました'),
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

class _TrackRow extends StatefulWidget {
  final int index;
  final MediaItem media;
  final bool playing;
  final VoidCallback onPlay;
  final VoidCallback onAddToPlaylist;
  final VoidCallback onPlayNext;
  final VoidCallback onEnqueue;
  final VoidCallback onDelete;

  const _TrackRow({
    required this.index,
    required this.media,
    required this.playing,
    required this.onPlay,
    required this.onAddToPlaylist,
    required this.onPlayNext,
    required this.onEnqueue,
    required this.onDelete,
  });

  @override
  State<_TrackRow> createState() => _TrackRowState();
}

class _TrackRowState extends State<_TrackRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final rowHoverColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.05);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onPlay,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _hover
                ? rowHoverColor
                : (widget.playing
                      ? (isDark
                            ? kAccent.withValues(alpha: 0.12)
                            : kAccent.withValues(alpha: 0.08))
                      : Colors.transparent),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              // Index or Play/Equalizer button
              SizedBox(
                width: 32,
                child: Center(
                  child: widget.playing
                      ? const Icon(Icons.equalizer, size: 20, color: kAccent)
                      : (_hover
                            ? const Icon(
                                Icons.play_arrow_rounded,
                                size: 24,
                                color: kAccent,
                              )
                            : Text(
                                '${widget.index}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: isDark ? kTextMuted : Colors.black45,
                                ),
                              )),
                ),
              ),
              const SizedBox(width: 12),
              // Thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 54,
                  height: 34,
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
                            child: Icon(
                              Icons.volume_up,
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
                    Text(
                      displayTitle(widget.media.title),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: widget.playing
                            ? FontWeight.bold
                            : FontWeight.w500,
                        color: widget.playing
                            ? kAccent
                            : (isDark ? Colors.white : Colors.black87),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.media.artist != null &&
                              widget.media.artist!.trim().isNotEmpty
                          ? widget.media.artist!
                          : (widget.media.origin == 'referenced'
                                ? '参照動画'
                                : '動画'),
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
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Action menu
              PopupMenuButton<String>(
                tooltip: 'メニュー',
                icon: Icon(
                  Icons.more_vert,
                  size: 20,
                  color: _hover
                      ? (isDark ? Colors.white : Colors.black87)
                      : (isDark ? kTextMuted : Colors.black38),
                ),
                onSelected: (v) {
                  switch (v) {
                    case 'playNext':
                      widget.onPlayNext();
                      break;
                    case 'enqueue':
                      widget.onEnqueue();
                      break;
                    case 'addToPlaylist':
                      widget.onAddToPlaylist();
                      break;
                    case 'delete':
                      widget.onDelete();
                      break;
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'playNext',
                    child: Row(
                      children: [
                        Icon(Icons.playlist_play, size: 20),
                        SizedBox(width: 10),
                        Text('次に再生'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'enqueue',
                    child: Row(
                      children: [
                        Icon(Icons.queue_music, size: 20),
                        SizedBox(width: 10),
                        Text('キューに追加'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'addToPlaylist',
                    child: Row(
                      children: [
                        Icon(Icons.playlist_add, size: 20),
                        SizedBox(width: 10),
                        Text('プレイリストに追加'),
                      ],
                    ),
                  ),
                  PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline,
                          size: 20,
                          color: Colors.redAccent,
                        ),
                        SizedBox(width: 10),
                        Text(
                          'ライブラリから削除',
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
    );
  }
}
