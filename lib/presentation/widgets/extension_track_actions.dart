import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_state.dart';
import '../../domain/models.dart';
import '../../extensions/extension_manifest.dart';
import '../../extensions/extension_registry.dart';
import '../../extensions/extension_runtime.dart';
import '../../playback/playback_controller.dart';
import '../i18n.dart';

Future<void> showTrackExtensionActions(
  BuildContext context,
  WidgetRef ref,
  MediaItem media,
) async {
  final extensions = ref
      .read(extensionRegistryProvider)
      .where(
        (extension) =>
            extension.enabled &&
            extension.grantedPermissions.contains(
              YureruExtensionPermission.uiContribution,
            ),
      );
  final actions =
      <({YureruExtension extension, Map<String, Object?> command})>[];
  for (final extension in extensions) {
    try {
      final contribution = await ref
          .read(extensionDispatcherProvider)
          .describe(extension);
      for (final item in contribution['commands'] as List? ?? const []) {
        if (item is Map<String, Object?>) {
          actions.add((extension: extension, command: item));
        }
      }
    } catch (_) {
      // A broken extension should not hide actions from other extensions.
    }
  }
  if (!context.mounted) return;
  if (actions.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ref.tr('extension_track_actions_empty'))),
    );
    return;
  }
  final selected =
      await showModalBottomSheet<
        ({YureruExtension extension, Map<String, Object?> command})
      >(
        context: context,
        showDragHandle: true,
        builder: (sheetContext) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Text(
                  ref.tr('extension_track_actions'),
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
              ),
              for (final action in actions)
                ListTile(
                  leading: Icon(_icon(action.command['icon'] as String?)),
                  title: Text(action.command['title'] as String? ?? ''),
                  subtitle: Text(action.extension.manifest.name),
                  onTap: () => Navigator.pop(sheetContext, action),
                ),
            ],
          ),
        ),
      );
  if (selected == null || !context.mounted) return;
  await _runTrackExtensionAction(context, ref, media, selected);
}

Future<void> _runTrackExtensionAction(
  BuildContext context,
  WidgetRef ref,
  MediaItem media,
  ({YureruExtension extension, Map<String, Object?> command}) selected,
) async {
  try {
    final extension = selected.extension;
    final permissions = extension.grantedPermissions;
    final payload = <String, Object?>{
      'source': 'track.menu',
      'media': {
        'id': media.id,
        'title': media.title,
        'artist': media.artist,
        'album': media.album,
        'durationMs': media.durationMs,
        'isFavorite': media.isFavorite,
      },
    };
    if (permissions.contains(YureruExtensionPermission.playerControl)) {
      final queue = ref.read(queueProvider);
      final snapshot = ref.read(playbackControllerProvider).engine.snapshot;
      payload['player'] = {
        'currentId': queue.currentId,
        'isPlaying': snapshot.isPlaying,
        'positionMs': snapshot.position.inMilliseconds,
        'durationMs': snapshot.duration.inMilliseconds,
        'queueIds': queue.queue.take(500).toList(),
      };
    }
    final result = await ref
        .read(extensionDispatcherProvider)
        .runAction(extension, selected.command['action'] as String, payload);
    if (!context.mounted) return;
    final commands = <Map>[];
    if (result is Map && result['command'] is Map) {
      commands.add(result['command'] as Map);
    }
    if (result is Map && result['commands'] is List) {
      commands.addAll((result['commands'] as List).whereType<Map>().take(50));
    }
    for (final command in commands) {
      await executeExtensionTrackCommand(ref, extension, media, command);
    }
    final message = result is String
        ? result
        : result is Map && result['message'] is String
        ? result['message'] as String
        : null;
    if (message != null && message.trim().isNotEmpty && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message.length > 300 ? message.substring(0, 300) : message,
          ),
        ),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ref.tr('extension_action_failed'))),
      );
    }
  }
}

Future<void> executeExtensionTrackCommand(
  WidgetRef ref,
  YureruExtension extension,
  MediaItem? media,
  Map command,
) async {
  final grants = extension.grantedPermissions;
  final type = command['type'];
  final playback = ref.read(playbackControllerProvider);
  final queue = ref.read(queueProvider.notifier);
  if (type is String && type.startsWith('player.')) {
    if (!grants.contains(YureruExtensionPermission.playerControl)) return;
    switch (type) {
      case 'player.toggle':
        await playback.toggle();
        break;
      case 'player.play':
        if (!playback.engine.snapshot.isPlaying) await playback.toggle();
        break;
      case 'player.pause':
        if (playback.engine.snapshot.isPlaying) await playback.toggle();
        break;
      case 'player.next':
        await playback.playNext();
        break;
      case 'player.previous':
        queue.previous();
        await playback.openCurrent();
        break;
      case 'player.seek':
        final ms = command['positionMs'];
        if (ms is num && ms.isFinite && ms >= 0) {
          await playback.seekTo(Duration(milliseconds: ms.round()));
        }
        break;
      case 'player.seekRelative':
        final ms = command['deltaMs'];
        if (ms is num && ms.isFinite) {
          await playback.seekBy(Duration(milliseconds: ms.round()));
        }
        break;
      case 'player.volume':
        final value = command['value'];
        if (value is num && value.isFinite) {
          await playback.setVolume(value.toDouble().clamp(0, 1));
        }
        break;
      case 'player.speed':
        final value = command['value'];
        if (value is num && value.isFinite && value >= 0.25 && value <= 3) {
          await playback.setSpeed(value.toDouble());
        }
        break;
      case 'player.shuffle':
        final enabled = command['enabled'];
        if (enabled is bool && enabled != ref.read(queueProvider).shuffle) {
          queue.toggleShuffle();
        }
        break;
      case 'player.repeat':
        final mode = command['mode'];
        if (mode is String) queue.setRepeat(mode);
        break;
      default:
        return;
    }
    return;
  }
  if (type == 'queue.playNext' || type == 'queue.append') {
    if (!grants.contains(YureruExtensionPermission.playerControl)) return;
    final id = command['mediaId'];
    if (id is String && ref.read(libraryProvider).byId(id) != null) {
      if (type == 'queue.playNext') {
        queue.playNext(id);
      } else {
        queue.append(id);
      }
    }
    return;
  }
  if (type == 'queue.start') {
    if (!grants.contains(YureruExtensionPermission.playerControl)) return;
    final ids = command['mediaIds'];
    if (ids is List) {
      final valid = ids
          .whereType<String>()
          .where((id) => ref.read(libraryProvider).byId(id) != null)
          .take(500)
          .toList();
      if (valid.isNotEmpty) {
        queue.start(valid, shuffle: command['shuffle'] == true);
        await playback.openCurrent();
      }
    }
    return;
  }
  if (type == 'queue.clear') {
    if (grants.contains(YureruExtensionPermission.playerControl)) queue.clear();
    return;
  }
  if (type == 'queue.remove') {
    if (!grants.contains(YureruExtensionPermission.playerControl)) return;
    final from = command['from'];
    if (from is int) queue.removeAt(from);
    return;
  }
  if (type == 'queue.move') {
    if (!grants.contains(YureruExtensionPermission.playerControl)) return;
    final from = command['from'];
    final to = command['to'];
    if (from is int && to is int) queue.move(from, to);
    return;
  }
  if (type == 'library.favorite' || type == 'library.setFavorite') {
    if (!grants.contains(YureruExtensionPermission.libraryWrite)) return;
    final id = command['mediaId'] is String
        ? command['mediaId'] as String
        : media?.id;
    if (id == null || ref.read(libraryProvider).byId(id) == null) return;
    if (type == 'library.favorite') {
      await ref.read(libraryProvider.notifier).toggleFavorite(id);
    } else if (command['value'] is bool) {
      final current = ref.read(libraryProvider).byId(id)?.isFavorite;
      if (current != command['value']) {
        await ref.read(libraryProvider.notifier).toggleFavorite(id);
      }
    }
    return;
  }
  if (type == 'library.metadata') {
    if (!grants.contains(YureruExtensionPermission.libraryWrite)) return;
    final id = command['mediaId'] is String
        ? command['mediaId'] as String
        : media?.id;
    if (id == null) return;
    if (ref.read(libraryProvider).byId(id) == null) return;
    final current = ref.read(libraryProvider).byId(id)!;
    await ref
        .read(libraryProvider.notifier)
        .updateMediaMetadata(
          id,
          title: command['title'] is String
              ? (command['title'] as String).substring(
                  0,
                  (command['title'] as String).length.clamp(0, 500),
                )
              : current.title,
          artist: command['artist'] is String
              ? (command['artist'] as String).substring(
                  0,
                  (command['artist'] as String).length.clamp(0, 500),
                )
              : current.artist,
        );
    return;
  }
  if (type == 'playlist.add' || type == 'playlist.remove') {
    if (!grants.contains(YureruExtensionPermission.libraryWrite)) return;
    final playlistId = command['playlistId'];
    final targetId = command['mediaId'] is String
        ? command['mediaId'] as String
        : media?.id;
    if (targetId == null) return;
    final library = ref.read(libraryProvider);
    if (playlistId is! String ||
        library.playlistById(playlistId) == null ||
        library.byId(targetId) == null) {
      return;
    }
    if (type == 'playlist.add') {
      await ref
          .read(libraryProvider.notifier)
          .addToPlaylist(playlistId, targetId);
    } else {
      await ref
          .read(libraryProvider.notifier)
          .removeFromPlaylist(playlistId, targetId);
    }
  }
}

IconData _icon(String? value) => switch (value) {
  'play' => Icons.play_arrow_rounded,
  'next' => Icons.skip_next_rounded,
  'library' => Icons.library_music_rounded,
  'settings' => Icons.settings_rounded,
  'search' => Icons.search_rounded,
  _ => Icons.extension_rounded,
};
