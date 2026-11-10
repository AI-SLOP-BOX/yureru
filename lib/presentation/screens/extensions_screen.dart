import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_state.dart';
import '../../extensions/extension_manifest.dart';
import '../../extensions/extension_registry.dart';
import '../../extensions/extension_runtime.dart';
import '../../data/thumbnails.dart';
import '../../platform/window_utils.dart';
import '../../playback/playback_controller.dart';
import '../i18n.dart';

class ExtensionsScreen extends ConsumerWidget {
  const ExtensionsScreen({super.key});

  Future<Set<YureruExtensionPermission>?> _reviewPermissions(
    BuildContext context,
    WidgetRef ref,
    YureruExtensionManifest manifest,
  ) => showDialog<Set<YureruExtensionPermission>>(
    context: context,
    builder: (dialogContext) {
      final selected = <YureruExtensionPermission>{};
      return StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(ref.tr('extension_permissions_title')),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  manifest.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(manifest.description),
                const SizedBox(height: 12),
                for (final permission in manifest.permissions)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: selected.contains(permission),
                    title: Text(_permissionLabel(ref, permission)),
                    controlAffinity: ListTileControlAffinity.leading,
                    onChanged: (enabled) => setState(() {
                      if (enabled == true) {
                        selected.add(permission);
                      } else {
                        selected.remove(permission);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(ref.tr('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, selected),
              child: Text(ref.tr('extension_install')),
            ),
          ],
        ),
      );
    },
  );

  Future<void> _install(BuildContext context, WidgetRef ref) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['yureru'],
      withData: true,
      allowMultiple: false,
    );
    if (!context.mounted || picked == null || picked.files.isEmpty) return;
    try {
      final file = picked.files.single;
      if (file.size > 20 * 1024 * 1024) {
        throw const FormatException('Extension package exceeds 20 MB.');
      }
      final bytes =
          file.bytes ??
          (file.path == null ? null : await File(file.path!).readAsBytes());
      if (bytes == null) throw const FormatException('Could not read package.');
      final package = YureruExtensionPackage.decode(bytes);
      if (!context.mounted) return;
      final grants = await _reviewPermissions(context, ref, package.manifest);
      if (!context.mounted || grants == null) return;
      await ref
          .read(extensionRegistryProvider.notifier)
          .install(package, grantedPermissions: grants);
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(ref.tr('extension_installed'))));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${ref.tr('extension_install_failed')} ${error.toString()}',
          ),
        ),
      );
    }
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    YureruExtension extension,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(ref.tr('extension_remove')),
        content: Text(
          ref
              .tr('extension_remove_confirm')
              .replaceAll('{name}', extension.manifest.name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(ref.tr('cancel')),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(ref.tr('extension_remove')),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref
          .read(extensionRegistryProvider.notifier)
          .remove(extension.manifest.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final extensions = ref.watch(extensionRegistryProvider);
    return Scaffold(
      appBar: AppBar(title: Text(ref.tr('extensions'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _install(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: Text(ref.tr('extension_add')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(ref.tr('extensions_intro')),
            ),
          ),
          if (extensions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(child: Text(ref.tr('extensions_empty'))),
            ),
          for (final extension in extensions)
            Card(
              child: ExpansionTile(
                leading: const Icon(Icons.extension_outlined),
                title: Text(extension.manifest.name),
                subtitle: Text(
                  '${extension.manifest.id} · ${extension.manifest.version}',
                ),
                trailing: Switch(
                  value: extension.enabled,
                  onChanged: (enabled) => ref
                      .read(extensionRegistryProvider.notifier)
                      .setEnabled(extension.manifest.id, enabled),
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: [
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(extension.manifest.description),
                  ),
                  if (extension.enabled &&
                      (extension.grantedPermissions.contains(
                            YureruExtensionPermission.uiContribution,
                          ) ||
                          extension.grantedPermissions.contains(
                            YureruExtensionPermission.themeCustomize,
                          ))) ...[
                    const SizedBox(height: 12),
                    _ExtensionContributions(extension: extension),
                  ],
                  if (extension.manifest.hooks.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        '${ref.tr('extension_hooks')}: ${extension.manifest.hooks.join(' · ')}',
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  for (final permission in extension.manifest.permissions)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: extension.grantedPermissions.contains(permission),
                      title: Text(_permissionLabel(ref, permission)),
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (enabled) {
                        final updated = {...extension.grantedPermissions};
                        if (enabled == true) {
                          updated.add(permission);
                        } else {
                          updated.remove(permission);
                        }
                        ref
                            .read(extensionRegistryProvider.notifier)
                            .setPermissions(extension.manifest.id, updated);
                      },
                    ),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton.icon(
                      onPressed: () => _remove(context, ref, extension),
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: Text(ref.tr('extension_remove')),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _permissionLabel(
    WidgetRef ref,
    YureruExtensionPermission permission,
  ) => switch (permission) {
    YureruExtensionPermission.libraryRead => ref.tr(
      'extension_permission_library_read',
    ),
    YureruExtensionPermission.libraryWrite => ref.tr(
      'extension_permission_library_write',
    ),
    YureruExtensionPermission.libraryDelete => ref.tr(
      'extension_permission_library_delete',
    ),
    YureruExtensionPermission.playlistManage => ref.tr(
      'extension_permission_playlist_manage',
    ),
    YureruExtensionPermission.playerControl => ref.tr(
      'extension_permission_player_control',
    ),
    YureruExtensionPermission.pictureInPicture => ref.tr(
      'extension_permission_pip_control',
    ),
    YureruExtensionPermission.uiContribution => ref.tr(
      'extension_permission_ui_contribution',
    ),
    YureruExtensionPermission.themeCustomize => ref.tr(
      'extension_permission_theme_customize',
    ),
    YureruExtensionPermission.extensionStorage => ref.tr(
      'extension_permission_storage',
    ),
  };
}

class _ExtensionContributions extends ConsumerStatefulWidget {
  const _ExtensionContributions({required this.extension});

  final YureruExtension extension;

  @override
  ConsumerState<_ExtensionContributions> createState() =>
      _ExtensionContributionsState();
}

class _ExtensionContributionsState
    extends ConsumerState<_ExtensionContributions> {
  late Future<Map<String, Object?>> _contributionFuture;

  @override
  void initState() {
    super.initState();
    _contributionFuture = ref
        .read(extensionDispatcherProvider)
        .describe(widget.extension);
  }

  YureruExtension get extension => widget.extension;

  Future<void> _run(
    BuildContext context,
    WidgetRef ref,
    String action, {
    Map<String, Object?> contextData = const {},
  }) async {
    try {
      final contextPayload = <String, Object?>{
        'source': 'extensions',
        ...contextData,
      };
      final permissions = extension.grantedPermissions;
      if (permissions.contains(YureruExtensionPermission.libraryRead)) {
        final library = ref.read(libraryProvider);
        final media = library.savedMedia;
        contextPayload['library'] = {
          'media': [
            for (final item in media.take(1000))
              {
                'id': item.id,
                'title': item.title,
                'artist': item.artist,
                'album': item.album,
                'durationMs': item.durationMs,
                'playCount': item.playCount,
                'isFavorite': item.isFavorite,
              },
          ],
          'mediaCount': media.length,
          'truncated': media.length > 1000,
          'playlists': [
            for (final playlist in library.playlists.take(200))
              {
                'id': playlist.id,
                'name': playlist.name,
                'mediaIds': playlist.mediaIds.take(500).toList(),
                'truncated': playlist.mediaIds.length > 500,
              },
          ],
          'playlistCount': library.playlists.length,
          'playlistsTruncated': library.playlists.length > 200,
        };
      }
      if (permissions.contains(YureruExtensionPermission.playerControl)) {
        final queue = ref.read(queueProvider);
        final snapshot = ref.read(playbackControllerProvider).engine.snapshot;
        contextPayload['player'] = {
          'currentId': queue.currentId,
          'isPlaying': snapshot.isPlaying,
          'positionMs': snapshot.position.inMilliseconds,
          'durationMs': snapshot.duration.inMilliseconds,
          'volume': ref.read(volumeProvider),
          'speed': queue.speed,
          'shuffle': queue.shuffle,
          'repeat': queue.repeat,
          'queueIds': queue.queue.take(500).toList(),
          'queueTruncated': queue.queue.length > 500,
        };
      }
      final result = await ref
          .read(extensionDispatcherProvider)
          .runAction(extension, action, contextPayload);
      if (!context.mounted) return;
      if (result is Map) {
        final single = result['command'];
        final batch = result['commands'];
        if (single is Map) {
          await _executeHostCommand(context, ref, extension, single);
        }
        if (batch is List) {
          for (final command in batch.take(50)) {
            if (!context.mounted) return;
            if (command is Map) {
              await _executeHostCommand(context, ref, extension, command);
            }
          }
        }
      }
      if (!context.mounted) return;
      final message = result is String
          ? result
          : result is Map && result['message'] is String
          ? result['message'] as String
          : null;
      if (message != null && message.trim().isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              message.length > 300 ? message.substring(0, 300) : message,
            ),
          ),
        );
      }
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ref.tr('extension_action_failed'))),
      );
    }
  }

  Future<void> _executeHostCommand(
    BuildContext context,
    WidgetRef ref,
    YureruExtension extension,
    Map command,
  ) async {
    final type = command['type'];
    final grants = extension.grantedPermissions;
    final controller = ref.read(playbackControllerProvider);
    final queue = ref.read(queueProvider.notifier);
    if (type == 'player.toggle' ||
        type == 'player.play' ||
        type == 'player.pause' ||
        type == 'player.next' ||
        type == 'player.previous' ||
        type == 'player.seek' ||
        type == 'player.seekRelative' ||
        type == 'player.volume' ||
        type == 'player.speed' ||
        type == 'player.shuffle' ||
        type == 'player.repeat') {
      if (!grants.contains(YureruExtensionPermission.playerControl)) return;
      if (type == 'player.toggle') await controller.toggle();
      if (type == 'player.play' && !controller.engine.snapshot.isPlaying) {
        await controller.toggle();
      }
      if (type == 'player.pause' && controller.engine.snapshot.isPlaying) {
        await controller.toggle();
      }
      if (type == 'player.next') await controller.playNext();
      if (type == 'player.previous') {
        queue.previous();
        await controller.openCurrent();
      }
      if (type == 'player.seek') {
        final ms = command['positionMs'];
        if (ms is num && ms.isFinite && ms >= 0) {
          final duration = controller.engine.snapshot.duration;
          final position = Duration(milliseconds: ms.round());
          await controller.seekTo(
            duration > Duration.zero && position > duration
                ? duration
                : position,
          );
        }
      }
      if (type == 'player.seekRelative') {
        final ms = command['deltaMs'];
        if (ms is num && ms.isFinite) {
          await controller.seekBy(Duration(milliseconds: ms.round()));
        }
      }
      if (type == 'player.volume') {
        final volume = command['value'];
        if (volume is num && volume.isFinite) {
          await controller.setVolume(volume.toDouble());
        }
      }
      if (type == 'player.speed') {
        final speed = command['value'];
        if (speed is num && speed.isFinite && speed >= 0.25 && speed <= 3.0) {
          await controller.setSpeed(speed.toDouble());
        }
      }
      if (type == 'player.shuffle') {
        final enabled = command['enabled'];
        if (enabled is bool && enabled != ref.read(queueProvider).shuffle) {
          queue.toggleShuffle();
        }
      }
      if (type == 'player.repeat') {
        final repeat = command['mode'];
        if (repeat is String) queue.setRepeat(repeat);
      }
      return;
    }
    if (type == 'queue.clear') {
      if (grants.contains(YureruExtensionPermission.playerControl)) {
        queue.clear();
      }
      return;
    }
    if (type == 'queue.start') {
      if (!grants.contains(YureruExtensionPermission.playerControl)) return;
      final rawIds = command['mediaIds'];
      if (rawIds is! List) return;
      final library = ref.read(libraryProvider);
      final ids = rawIds
          .whereType<String>()
          .where((id) => library.byId(id) != null)
          .take(500)
          .toList(growable: false);
      if (ids.isEmpty) return;
      final shuffle = command['shuffle'] == true;
      queue.start(ids, shuffle: shuffle);
      await controller.openCurrent();
      return;
    }
    if (type == 'pip.start' || type == 'pip.restore') {
      if (!grants.contains(YureruExtensionPermission.pictureInPicture)) return;
      final isStarting = type == 'pip.start';
      final pipState = ref.read(pictureInPictureProvider.notifier);
      final isDesktopPip = Platform.isWindows || Platform.isLinux;
      final changesSurface = isDesktopPip || Platform.isAndroid;
      if (!isStarting) {
        pipState.state = false;
        await WidgetsBinding.instance.endOfFrame;
        await restorePictureInPictureWindow(engine: controller.engine);
        return;
      }
      final mode = ref.read(playerViewModeProvider);
      final mediaId = ref.read(queueProvider).currentId;
      final media = mediaId == null
          ? null
          : ref.read(libraryProvider).byId(mediaId);
      String? artworkPath;
      if (mode == PlayerViewMode.image && media != null) {
        for (final candidate in [media.artworkPath, media.thumbnailPath]) {
          if (candidate != null && await File(candidate).exists()) {
            artworkPath = candidate;
            break;
          }
        }
        artworkPath ??= (await ThumbnailService.forMedia(
          mediaId: media.id,
          localPath: media.localPath,
          highRes: true,
        ))?.path;
      }
      if (changesSurface) {
        pipState.state = true;
        await WidgetsBinding.instance.endOfFrame;
      }
      final aspectRatio =
          command['aspectRatio'] is num &&
              (command['aspectRatio'] as num).isFinite
          ? (command['aspectRatio'] as num).toDouble().clamp(0.5, 2.5)
          : command['width'] is num &&
                command['height'] is num &&
                (command['width'] as num).isFinite &&
                (command['height'] as num).isFinite &&
                (command['height'] as num) > 0
          ? ((command['width'] as num) / (command['height'] as num))
                .toDouble()
                .clamp(0.5, 2.5)
          : mode == PlayerViewMode.image
          ? 1.0
          : controller.engine.videoAspectRatio ?? 16 / 9;
      final started = isDesktopPip
          ? await enterPictureInPictureWindow(
              engine: controller.engine,
              aspectRatio: aspectRatio,
              artworkPath: artworkPath,
              windowWidth: command['width'] is num
                  ? (command['width'] as num).toDouble()
                  : null,
              windowHeight: command['height'] is num
                  ? (command['height'] as num).toDouble()
                  : null,
            )
          : Platform.isAndroid
          ? await enterPictureInPictureWindow(
              engine: controller.engine,
              aspectRatio: aspectRatio,
              artworkPath: artworkPath,
            )
          : await controller.engine.enterPictureInPicture(
              aspectRatio: aspectRatio,
              artworkPath: artworkPath,
              sourceRect: ref.read(pictureInPictureSourceRectProvider),
            );
      if (!started && changesSurface) pipState.state = false;
      if (!started && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(ref.tr('pip_unavailable'))));
      }
      return;
    }
    if (type == 'queue.remove' || type == 'queue.move') {
      if (!grants.contains(YureruExtensionPermission.playerControl)) return;
      final from = command['from'];
      if (type == 'queue.remove' && from is int) queue.removeAt(from);
      if (type == 'queue.move' && from is int && command['to'] is int) {
        queue.move(from, command['to'] as int);
      }
      return;
    }
    if (type == 'queue.playNext' || type == 'queue.append') {
      if (!grants.contains(YureruExtensionPermission.playerControl)) return;
      final id = command['mediaId'];
      if (id is! String || ref.read(libraryProvider).byId(id) == null) return;
      final wasEmpty = !ref.read(queueProvider).hasCurrent;
      if (type == 'queue.playNext') {
        queue.playNext(id);
      } else {
        queue.append(id);
      }
      if (wasEmpty) await controller.openCurrent();
      return;
    }
    if (!grants.contains(YureruExtensionPermission.libraryWrite)) return;
    final library = ref.read(libraryProvider);
    final notifier = ref.read(libraryProvider.notifier);
    if (type == 'library.favorite' || type == 'library.setFavorite') {
      final id = command['mediaId'];
      final item = id is String ? library.byId(id) : null;
      if (item != null &&
          (type == 'library.favorite' || command['value'] is bool) &&
          (type == 'library.favorite' || item.isFavorite != command['value'])) {
        await notifier.toggleFavorite(item.id);
      }
    } else if (type == 'library.remove') {
      if (!grants.contains(YureruExtensionPermission.libraryDelete)) return;
      final id = command['mediaId'];
      if (id is String && library.byId(id) != null) {
        await notifier.removeMedia(id);
      }
    } else if (type == 'library.metadata') {
      final id = command['mediaId'];
      final item = id is String ? library.byId(id) : null;
      if (item == null) return;
      final title = command['title'];
      final artist = command['artist'];
      final cleanTitle = title is String ? title.trim() : item.title;
      final String? cleanArtist = artist is String
          ? artist.trim()
          : item.artist;
      await notifier.updateMediaMetadata(
        item.id,
        title: cleanTitle.isEmpty
            ? item.title
            : cleanTitle.length > 500
            ? cleanTitle.substring(0, 500)
            : cleanTitle,
        artist: cleanArtist == null || cleanArtist.isEmpty
            ? null
            : cleanArtist.length > 500
            ? cleanArtist.substring(0, 500)
            : cleanArtist,
      );
      final album = command['album'];
      final albumArtist = command['albumArtist'];
      if (album is String || albumArtist is String) {
        await notifier.updateMediaAlbum(
          item.id,
          album: album is String ? album : item.album,
          albumArtist: albumArtist is String ? albumArtist : item.albumArtist,
          trackNumber: item.trackNumber,
          discNumber: item.discNumber,
        );
      }
    } else if (type == 'playlist.create') {
      final name = command['name'];
      if (name is String && name.trim().isNotEmpty) {
        final cleanName = name.trim();
        await notifier.createPlaylist(
          cleanName.length > 120 ? cleanName.substring(0, 120) : cleanName,
        );
      }
    } else if (type == 'playlist.createSmart') {
      final name = command['name'];
      final rule = command['rule'];
      if (name is String && rule is String) {
        await notifier.createSmartPlaylist(name.trim(), rule);
      }
    } else if (type == 'playlist.rename') {
      final playlistId = command['playlistId'];
      final name = command['name'];
      if (playlistId is String && name is String) {
        final cleanName = name.trim();
        if (cleanName.isNotEmpty) {
          await notifier.renamePlaylist(
            playlistId,
            cleanName.length > 120 ? cleanName.substring(0, 120) : cleanName,
          );
        }
      }
    } else if (type == 'playlist.delete') {
      if (!grants.contains(YureruExtensionPermission.playlistManage)) return;
      final playlistId = command['playlistId'];
      if (playlistId is String && library.playlistById(playlistId) != null) {
        await notifier.deletePlaylist(playlistId);
      }
    } else if (type == 'playlist.add' ||
        type == 'playlist.remove' ||
        type == 'playlist.addMany' ||
        type == 'playlist.removeMany') {
      final playlistId = command['playlistId'];
      final playlist = playlistId is String
          ? library.playlistById(playlistId)
          : null;
      if (playlist == null || playlist.isSmart) {
        return;
      }
      final rawIds = command['mediaIds'];
      final mediaIds = type.endsWith('Many') && rawIds is List
          ? rawIds.whereType<String>().take(500).toList()
          : [if (command['mediaId'] is String) command['mediaId'] as String];
      final validIds = mediaIds
          .where((id) => library.byId(id) != null)
          .toList(growable: false);
      if (validIds.isEmpty) return;
      if (type == 'playlist.add' || type == 'playlist.addMany') {
        await notifier.addMediaToPlaylist(playlistId as String, validIds);
      } else {
        await notifier.removeMediaFromPlaylist(playlistId as String, validIds);
      }
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: _contributionFuture,
    builder: (context, snapshot) {
      final contribution = snapshot.data;
      if (snapshot.hasError || contribution == null) return const SizedBox();
      final commands = contribution['commands'] as List? ?? const [];
      final pages = contribution['pages'] as List? ?? const [];
      final themes = contribution['themes'] as List? ?? const [];
      if (commands.isEmpty && pages.isEmpty && themes.isEmpty) {
        return const SizedBox();
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            ref.tr('extension_contributions'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          for (final raw in commands)
            if (raw is Map)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(_contributionIcon(raw['icon'] as String?)),
                title: Text(raw['title'] as String? ?? ''),
                trailing: const Icon(Icons.play_arrow_rounded),
                onTap: () => _run(context, ref, raw['action'] as String),
              ),
          for (final raw in pages)
            if (raw is Map)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.web_asset_rounded),
                title: Text(raw['title'] as String? ?? ''),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _openPage(context, ref, raw),
              ),
          for (final raw in themes)
            if (raw is Map)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: Color(raw['accent'] as int),
                  radius: 12,
                ),
                title: Text(raw['name'] as String? ?? ''),
                subtitle: Text(ref.tr('extension_apply_theme')),
                onTap: () async {
                  await ref
                      .read(appearanceColorsProvider.notifier)
                      .setAll(
                        accent: raw['accent'] as int,
                        darkBackground: raw['darkBackground'] as int,
                        lightBackground: raw['lightBackground'] as int,
                        darkSurface: raw['darkSurface'] as int?,
                        lightSurface: raw['lightSurface'] as int?,
                        darkText: raw['darkText'] as int?,
                        lightText: raw['lightText'] as int?,
                        cornerRadius: (raw['cornerRadius'] as num?)?.toDouble(),
                        fontScale: (raw['fontScale'] as num?)?.toDouble(),
                      );
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(ref.tr('extension_theme_applied'))),
                  );
                },
              ),
        ],
      );
    },
  );

  Future<void> _openPage(BuildContext context, WidgetRef ref, Map raw) async {
    final form = <String, Object?>{};
    for (final block in raw['blocks'] as List? ?? const []) {
      if (block is! Map || block['id'] is! String) continue;
      final id = block['id'] as String;
      if (block['type'] == 'input') form[id] = block['value'] as String;
      if (block['type'] == 'multiline') form[id] = block['value'] as String;
      if (block['type'] == 'toggle') form[id] = block['value'] == true;
      if (block['type'] == 'slider') form[id] = block['value'] as double;
      if (block['type'] == 'select') form[id] = block['value'] as String;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (pageContext) => StatefulBuilder(
          builder: (context, setPageState) => Scaffold(
            appBar: AppBar(
              title: Text(raw['title'] as String? ?? ''),
              leading: IconButton(
                tooltip: ref.tr('close'),
                onPressed: () => Navigator.pop(pageContext),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
            ),
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final block in raw['blocks'] as List? ?? const [])
                        if (block is Map && block['type'] == 'text')
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(block['text'] as String),
                          )
                        else if (block is Map && block['type'] == 'heading')
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              block['text'] as String,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          )
                        else if (block is Map && block['type'] == 'divider')
                          const Divider()
                        else if (block is Map &&
                            (block['type'] == 'input' ||
                                block['type'] == 'multiline'))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: TextFormField(
                              initialValue: form[block['id']] as String,
                              minLines: block['type'] == 'multiline' ? 3 : 1,
                              maxLines: block['type'] == 'multiline' ? 8 : 1,
                              decoration: InputDecoration(
                                labelText: block['label'] as String,
                              ),
                              onChanged: (value) =>
                                  form[block['id'] as String] = value,
                            ),
                          )
                        else if (block is Map && block['type'] == 'select')
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: DropdownButtonFormField<String>(
                              initialValue: form[block['id']] as String,
                              decoration: InputDecoration(
                                labelText: block['label'] as String,
                              ),
                              items: [
                                for (final option
                                    in block['options'] as List<String>)
                                  DropdownMenuItem(
                                    value: option,
                                    child: Text(option),
                                  ),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  setPageState(
                                    () => form[block['id'] as String] = value,
                                  );
                                }
                              },
                            ),
                          )
                        else if (block is Map && block['type'] == 'image')
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(
                                File(
                                  '${extension.directoryPath}/${block['src']}',
                                ),
                                semanticLabel: block['alt'] as String?,
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) =>
                                    const SizedBox.shrink(),
                              ),
                            ),
                          )
                        else if (block is Map && block['type'] == 'toggle')
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(block['label'] as String),
                            value: form[block['id']] == true,
                            onChanged: (value) => setPageState(
                              () => form[block['id'] as String] = value,
                            ),
                          )
                        else if (block is Map && block['type'] == 'slider')
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${block['label']} · ${(form[block['id']] as double).toStringAsFixed(2)}',
                              ),
                              Slider(
                                min: block['min'] as double,
                                max: block['max'] as double,
                                value: form[block['id']] as double,
                                onChanged: (value) => setPageState(
                                  () => form[block['id'] as String] = value,
                                ),
                              ),
                            ],
                          )
                        else if (block is Map && block['type'] == 'button')
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: FilledButton.tonal(
                              onPressed: () => _run(
                                pageContext,
                                ref,
                                block['action'] as String,
                                contextData: {
                                  'pageId': raw['id'],
                                  'form': Map<String, Object?>.of(form),
                                },
                              ),
                              child: Text(block['label'] as String),
                            ),
                          ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

IconData _contributionIcon(String? name) => switch (name) {
  'play' => Icons.play_arrow_rounded,
  'settings' => Icons.settings_rounded,
  'palette' => Icons.palette_outlined,
  'library' => Icons.video_library_outlined,
  'search' => Icons.search_rounded,
  'download' => Icons.download_rounded,
  _ => Icons.extension_outlined,
};
