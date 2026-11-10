import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_state.dart';
import '../../domain/models.dart';
import '../../extensions/extension_manifest.dart';
import '../../extensions/extension_registry.dart';
import '../i18n.dart';
import '../theme.dart';
import 'app_svg_icon.dart';
import 'extension_track_actions.dart';

List<PopupMenuEntry<String>> trackActionItems(
  WidgetRef ref,
  MediaItem media, {
  String? playlistId,
}) => [
  _item(
    ref,
    'play_next',
    ref.tr('add_next'),
    const AppSvgIcon('play_next', size: 20),
  ),
  _item(
    ref,
    'add_playlist',
    ref.tr('add_playlist'),
    const Icon(Icons.playlist_add_rounded, size: 20),
  ),
  _item(
    ref,
    'favorite',
    ref.tr(media.isFavorite ? 'remove_favorite' : 'add_favorite'),
    AppSvgIcon(media.isFavorite ? 'favorite_filled' : 'favorite', size: 20),
  ),
  if (media.artist?.trim().isNotEmpty == true)
    _item(
      ref,
      'open_artist',
      ref.tr('open_artist_videos'),
      const Icon(Icons.person_outline_rounded, size: 20),
    ),
  if (playlistId != null)
    _item(
      ref,
      'remove_from_playlist',
      ref.tr('remove_from_playlist'),
      const Icon(Icons.playlist_remove_rounded, size: 20),
    ),
  if (ref
      .read(extensionRegistryProvider)
      .any(
        (extension) =>
            extension.enabled &&
            extension.grantedPermissions.contains(
              YureruExtensionPermission.uiContribution,
            ),
      ))
    _item(
      ref,
      'extension_actions',
      ref.tr('extension_track_actions'),
      const Icon(Icons.extension_rounded, size: 20),
    ),
];

PopupMenuItem<String> _item(
  WidgetRef ref,
  String value,
  String label,
  Widget icon,
) => PopupMenuItem(
  value: value,
  child: Row(
    children: [
      icon,
      const SizedBox(width: 10),
      Flexible(child: Text(label)),
    ],
  ),
);

class TrackContextMenuRegion extends StatelessWidget {
  const TrackContextMenuRegion({
    super.key,
    required this.ref,
    required this.media,
    required this.child,
    this.playlistId,
  });

  final WidgetRef ref;
  final MediaItem? media;
  final Widget child;
  final String? playlistId;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.translucent,
    onSecondaryTapUp: (details) => _show(context, details.globalPosition),
    onLongPressStart: (details) => _show(context, details.globalPosition),
    child: child,
  );

  Future<void> _show(BuildContext context, Offset globalPosition) async {
    final currentMedia = media;
    if (currentMedia == null) return;
    final size = MediaQuery.sizeOf(context);
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        size.width - globalPosition.dx,
        size.height - globalPosition.dy,
      ),
      items: trackActionItems(ref, currentMedia, playlistId: playlistId),
    );
    if (action != null && context.mounted) {
      await runTrackAction(
        context,
        ref,
        currentMedia,
        action,
        playlistId: playlistId,
      );
    }
  }
}

Future<void> runTrackAction(
  BuildContext context,
  WidgetRef ref,
  MediaItem media,
  String action, {
  String? playlistId,
}) async {
  switch (action) {
    case 'play_next':
      ref.read(queueProvider.notifier).playNext(media.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${displayTitle(media.title)} — ${ref.tr('add_next')}',
            ),
          ),
        );
      }
      break;
    case 'add_playlist':
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
      final target = await showModalBottomSheet<Playlist>(
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
              for (final playlist in playlists)
                ListTile(
                  leading: const Icon(Icons.playlist_play_rounded),
                  title: Text(displayTitle(playlist.name)),
                  onTap: () => Navigator.pop(sheetContext, playlist),
                ),
            ],
          ),
        ),
      );
      if (target == null || !context.mounted) return;
      await ref
          .read(libraryProvider.notifier)
          .addToPlaylist(target.id, media.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ref
                  .tr('added_to_playlist')
                  .replaceAll('{name}', displayTitle(target.name)),
            ),
          ),
        );
      }
      break;
    case 'favorite':
      await ref.read(libraryProvider.notifier).toggleFavorite(media.id);
      break;
    case 'open_artist':
      final artist = media.artist?.trim();
      if (artist != null && artist.isNotEmpty) {
        ref.read(creatorVideosRequestProvider.notifier).state = artist;
      }
      break;
    case 'remove_from_playlist':
      if (playlistId != null) {
        await ref
            .read(libraryProvider.notifier)
            .removeFromPlaylist(playlistId, media.id);
      }
      break;
    case 'extension_actions':
      await showTrackExtensionActions(context, ref, media);
      break;
  }
}
