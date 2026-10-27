import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_state.dart';
import '../../domain/models.dart';
import '../../playback/playback_controller.dart';
import '../i18n.dart';
import '../theme.dart';
import 'duration_text.dart';
import 'frosted_panel.dart';
import 'thumb_image.dart';

/// Home footer for the current queue item or an idle suggested track.
/// Its primary action starts playback or opens the shared player.
class PreviewBar extends ConsumerWidget {
  const PreviewBar({super.key});

  /// Playing item first, else first video of the first playlist,
  /// else first library item.
  ({MediaItem item, String? playlistId, String? playlistName})? _target(
    LibraryState lib,
    QueueState q,
  ) {
    if (q.hasCurrent) {
      final m = lib.byId(q.currentId!);
      if (m != null) {
        final plName = q.sourcePlaylistId == null
            ? null
            : lib.playlistById(q.sourcePlaylistId!)?.name;
        return (item: m, playlistId: q.sourcePlaylistId, playlistName: plName);
      }
    }
    if (!lib.loaded || lib.savedMedia.isEmpty) return null;
    for (final pl in lib.playlists) {
      for (final id in pl.mediaIds) {
        final m = lib.byId(id);
        if (m != null) {
          return (item: m, playlistId: pl.id, playlistName: pl.name);
        }
      }
    }
    return (item: lib.savedMedia.first, playlistId: null, playlistName: null);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Narrow pages stay mounted inside an IndexedStack while hidden.
    if (MediaQuery.sizeOf(context).width < 1000) {
      return const SizedBox.shrink();
    }
    final lib = ref.watch(libraryProvider);
    final queue = ref.watch(queueProvider);
    final engine = ref.watch(engineProvider);
    final target = _target(lib, queue);
    if (target == null) return const SizedBox.shrink();
    final item = target.item;
    final playing = queue.hasCurrent && queue.currentId == item.id;

    String subtitle;
    if (target.playlistName != null) {
      final plName = displayTitle(target.playlistName!);
      if (playing) {
        final pl = queue.sourcePlaylistId == null
            ? null
            : lib.playlistById(queue.sourcePlaylistId!);
        final pos = pl == null ? null : pl.mediaIds.indexOf(item.id) + 1;
        subtitle = pos == null || pos <= 0
            ? plName
            : '$plName ・ ${ref.tracksCount(pl!.mediaIds.length)} / $pos';
      } else {
        subtitle = plName;
      }
    } else {
      subtitle = item.isTemporary
          ? ref.tr('temporary_playback')
          : (item.origin == 'referenced'
                ? ref.tr('referenced_video')
                : ref.tr('imported_media'));
    }

    // Up next (only while playing and something follows).
    final upNext = <MediaItem>[];
    if (playing) {
      for (
        var i = queue.index + 1;
        i < queue.queue.length && upNext.length < 2;
        i++
      ) {
        final m = lib.byId(queue.queue[i]);
        if (m != null) upNext.add(m);
      }
    }

    return FrostedPanel(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 14),
      padding: const EdgeInsets.all(12),
      borderRadius: BorderRadius.circular(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 156,
            height: 88,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: (playing && ref.watch(engineProvider).snapshot.initialized)
                ? engine.buildVideoView()
                : ThumbImage(
                    seed: item.id,
                    mediaId: item.id,
                    localPath: item.localPath,
                    radius: 10,
                    expand: true,
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: playing
                        ? (Theme.of(context).brightness == Brightness.dark
                              ? kAccent.withValues(alpha: 0.2)
                              : kAccent.withValues(alpha: 0.12))
                        : (Theme.of(context).brightness == Brightness.dark
                              ? Colors.white10
                              : Colors.black.withValues(alpha: 0.06)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    ref.tr(
                      playing ? 'home_current_track' : 'home_start_listening',
                    ),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: playing
                          ? (Theme.of(context).brightness == Brightness.dark
                                ? kAccentLight
                                : kAccent)
                          : themeTextSub(context),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  displayTitle(item.title),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: themeTextPrimary(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: themeTextSub(context),
                  ),
                ),
                const SizedBox(height: 2),
                DurationText(
                  mediaId: item.id,
                  localPath: item.localPath,
                  durationMs: item.durationMs,
                  style: TextStyle(fontSize: 12, color: themeTextSub(context)),
                ),
                if (upNext.isNotEmpty)
                  for (var i = 0; i < upNext.length; i++)
                    InkWell(
                      onTap: () => _jumpTo(ref, queue, upNext[i].id),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(
                          '${ref.tr('next_video')}: ${displayTitle(upNext[i].title)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? kAccentLight
                                : kAccent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            icon: Icon(
              playing ? Icons.open_in_full : Icons.play_arrow,
              size: 20,
            ),
            label: Text(playing ? ref.tr('open_player') : ref.tr('play')),
            onPressed: () => _playFull(ref, item, target.playlistId),
          ),
        ],
      ),
    );
  }

  Future<void> _playFull(
    WidgetRef ref,
    MediaItem item,
    String? playlistId,
  ) async {
    showPlayerView(ref);
    // Already playing this item: just open the player, don't restart.
    if (ref.read(queueProvider).currentId == item.id) return;
    if (playlistId != null) {
      await ref
          .read(playbackControllerProvider)
          .startPlaylist(playlistId, shuffle: false);
    } else {
      ref.read(queueProvider.notifier).start([item.id], shuffle: false);
      await ref.read(playbackControllerProvider).openCurrent();
    }
  }

  Future<void> _jumpTo(WidgetRef ref, QueueState queue, String id) async {
    final i = queue.queue.indexOf(id);
    if (i < 0) return;
    ref.read(queueProvider.notifier).jumpTo(i);
    await ref.read(playbackControllerProvider).openCurrent();
  }
}
