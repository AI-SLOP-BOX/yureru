import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_state.dart';
import '../../domain/models.dart';
import '../../playback/playback_controller.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets/app_svg_icon.dart';
import '../widgets/page_header.dart';
import '../widgets/thumb_image.dart';

/// Playlists page: vertical list with counts + play/shuffle actions.
class _PlaylistsSortMenu extends ConsumerWidget {
  final PlaylistsSort sort;
  const _PlaylistsSortMenu({required this.sort});

  String _label(WidgetRef ref, PlaylistsSort value) => ref.tr(switch (value) {
    PlaylistsSort.recentlyPlayed => 'recently_played_order',
    PlaylistsSort.newestFirst => 'newest_first',
    PlaylistsSort.oldestFirst => 'oldest_first',
    PlaylistsSort.name => 'name_order',
    PlaylistsSort.manual => 'manual_order',
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return PopupMenuButton<PlaylistsSort>(
      tooltip: ref.tr('sort'),
      initialValue: sort,
      onSelected: (value) =>
          ref.read(playlistsSortProvider.notifier).state = value,
      itemBuilder: (_) => [
        for (final value in [
          PlaylistsSort.recentlyPlayed,
          PlaylistsSort.newestFirst,
          PlaylistsSort.oldestFirst,
          PlaylistsSort.name,
          PlaylistsSort.manual,
        ])
          CheckedPopupMenuItem(
            value: value,
            checked: value == sort,
            child: Text(_label(ref, value)),
          ),
      ],
      child: compact
          ? const Padding(
              padding: EdgeInsets.all(10),
              child: Icon(Icons.sort_rounded),
            )
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                border: Border.all(color: themeBorder(context)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppSvgIcon('sort', size: 18),
                  const SizedBox(width: 8),
                  Text(_label(ref, sort)),
                  const SizedBox(width: 8),
                  const AppSvgIcon('chevron_down', size: 14),
                ],
              ),
            ),
    );
  }
}

class PlaylistsScreen extends ConsumerWidget {
  final ValueChanged<String>? onOpenPlaylist;
  const PlaylistsScreen({super.key, this.onOpenPlaylist});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lib = ref.watch(libraryProvider);
    final query = ref.watch(searchQueryProvider).trim().toLowerCase();
    final sort = ref.watch(playlistsSortProvider);
    if (!lib.loaded) return const Center(child: CircularProgressIndicator());
    final playlists = lib.playlists
        .where((p) => query.isEmpty || p.name.toLowerCase().contains(query))
        .toList();
    if (sort != PlaylistsSort.manual) {
      final indexed = playlists.indexed.toList();
      DateTime? lastPlayed(Playlist playlist) {
        DateTime? latest;
        for (final id in playlist.mediaIds) {
          final playedAt = lib.byId(id)?.lastPlayedAt;
          if (playedAt != null &&
              (latest == null || playedAt.isAfter(latest))) {
            latest = playedAt;
          }
        }
        return latest;
      }

      indexed.sort((a, b) {
        final left = a.$2;
        final right = b.$2;
        var order = 0;
        switch (sort) {
          case PlaylistsSort.recentlyPlayed:
            final leftPlayed = lastPlayed(left);
            final rightPlayed = lastPlayed(right);
            if (leftPlayed == null && rightPlayed != null) {
              order = 1;
            } else if (leftPlayed != null && rightPlayed == null) {
              order = -1;
            } else if (leftPlayed != null && rightPlayed != null) {
              order = rightPlayed.compareTo(leftPlayed);
            }
          case PlaylistsSort.newestFirst:
            order = right.createdAt.compareTo(left.createdAt);
          case PlaylistsSort.oldestFirst:
            order = left.createdAt.compareTo(right.createdAt);
          case PlaylistsSort.name:
            order = left.name.toLowerCase().compareTo(right.name.toLowerCase());
          case PlaylistsSort.manual:
            break;
        }
        if (order == 0 && sort == PlaylistsSort.recentlyPlayed) {
          order = right.createdAt.compareTo(left.createdAt);
        }
        return order != 0 ? order : a.$1.compareTo(b.$1);
      });
      playlists
        ..clear()
        ..addAll(indexed.map((entry) => entry.$2));
    }
    if (playlists.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.queue_music_rounded,
              size: 48,
              color: themeTextSub(context),
            ),
            const SizedBox(height: 12),
            Text(
              ref.tr('empty_playlist'),
              textAlign: TextAlign.center,
              style: TextStyle(color: themeTextSub(context)),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _createPlaylist(context, ref),
              icon: const Icon(Icons.add_rounded),
              label: Text(ref.tr('create_playlist')),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PageHeader(
          title: ref.tr('playlists'),
          trailing: ref.playlistsCount(playlists.length),
          actions: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PlaylistsSortMenu(sort: sort),
              if (MediaQuery.sizeOf(context).width < 1000)
                IconButton.filledTonal(
                  tooltip: ref.tr('create_playlist'),
                  onPressed: () => _createPlaylist(context, ref),
                  icon: const Icon(Icons.add_rounded),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            itemCount: playlists.length,
            separatorBuilder: (_, _) => const SizedBox(height: 4),
            itemBuilder: (c, i) {
              final pl = playlists[i];
              return Container(
                decoration: BoxDecoration(
                  color: themeCard(context),
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: Material(
                  color: Colors.transparent,
                  child: ListTile(
                    leading: ThumbImage(
                      seed: pl.id,
                      mediaId: pl.mediaIds.isEmpty
                          ? null
                          : lib.byId(pl.mediaIds.first)?.id,
                      localPath: pl.mediaIds.isEmpty
                          ? null
                          : lib.byId(pl.mediaIds.first)?.localPath,
                      size: 48,
                    ),
                    title: Text(
                      displayTitle(pl.name),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      ref.tracksCount(pl.mediaIds.length),
                      style: TextStyle(
                        fontSize: 12,
                        color: themeTextSub(context),
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: ref.tr('shuffle'),
                          icon: const Icon(Icons.shuffle_rounded, size: 20),
                          onPressed: pl.mediaIds.isEmpty
                              ? null
                              : () {
                                  showPlayerView(ref);
                                  ref
                                      .read(playbackControllerProvider)
                                      .startPlaylist(pl.id, shuffle: true);
                                },
                        ),
                        IconButton(
                          tooltip: ref.tr('play'),
                          icon: const Icon(Icons.play_arrow_rounded),
                          onPressed: pl.mediaIds.isEmpty
                              ? null
                              : () {
                                  showPlayerView(ref);
                                  ref
                                      .read(playbackControllerProvider)
                                      .startPlaylist(pl.id, shuffle: false);
                                },
                        ),
                      ],
                    ),
                    onTap: onOpenPlaylist == null
                        ? null
                        : () => onOpenPlaylist!(pl.id),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

Future<void> _createPlaylist(BuildContext context, WidgetRef ref) async {
  final controller = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(ref.tr('create_playlist')),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: ref.tr('playlist_name')),
        onSubmitted: (value) => Navigator.pop(dialogContext, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(ref.tr('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, controller.text),
          child: Text(ref.tr('create')),
        ),
      ],
    ),
  );
  controller.dispose();
  if (name != null && name.trim().isNotEmpty) {
    await ref.read(libraryProvider.notifier).createPlaylist(name.trim());
  }
}
