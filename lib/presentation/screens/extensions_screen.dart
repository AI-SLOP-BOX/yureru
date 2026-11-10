import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_state.dart';
import '../../extensions/extension_manifest.dart';
import '../../extensions/extension_registry.dart';
import '../../extensions/extension_runtime.dart';
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
    YureruExtensionPermission.playerControl => ref.tr(
      'extension_permission_player_control',
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
      final result = await ref.read(extensionDispatcherProvider).runAction(
        extension,
        action,
        {'source': 'extensions', ...contextData},
      );
      if (result is Map && result['command'] is Map) {
        await _executeHostCommand(
          context,
          ref,
          extension,
          result['command'] as Map,
        );
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
        type == 'player.next' ||
        type == 'player.previous' ||
        type == 'player.seek') {
      if (!grants.contains(YureruExtensionPermission.playerControl)) return;
      if (type == 'player.toggle') await controller.toggle();
      if (type == 'player.next') await controller.playNext();
      if (type == 'player.previous') {
        queue.previous();
        await controller.openCurrent();
      }
      if (type == 'player.seek') {
        final ms = command['positionMs'];
        if (ms is int && ms >= 0) {
          final duration = controller.engine.snapshot.duration;
          final position = Duration(milliseconds: ms);
          await controller.seekTo(
            duration > Duration.zero && position > duration
                ? duration
                : position,
          );
        }
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
    if (type == 'library.favorite') {
      final id = command['mediaId'];
      if (id is String && library.byId(id) != null) {
        await notifier.toggleFavorite(id);
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
    } else if (type == 'playlist.add' || type == 'playlist.remove') {
      final playlistId = command['playlistId'];
      final mediaId = command['mediaId'];
      if (playlistId is! String ||
          mediaId is! String ||
          library.byId(mediaId) == null ||
          !library.playlists.any((playlist) => playlist.id == playlistId)) {
        return;
      }
      if (type == 'playlist.add') {
        await notifier.addToPlaylist(playlistId, mediaId);
      } else {
        await notifier.removeFromPlaylist(playlistId, mediaId);
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
      if (block['type'] == 'toggle') form[id] = block['value'] == true;
      if (block['type'] == 'slider') form[id] = block['value'] as double;
    }
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(raw['title'] as String? ?? ''),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final block in raw['blocks'] as List? ?? const [])
                    if (block is Map && block['type'] == 'text')
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(block['text'] as String),
                      )
                    else if (block is Map && block['type'] == 'divider')
                      const Divider()
                    else if (block is Map && block['type'] == 'input')
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: TextFormField(
                          initialValue: form[block['id']] as String,
                          decoration: InputDecoration(
                            labelText: block['label'] as String,
                          ),
                          onChanged: (value) =>
                              form[block['id'] as String] = value,
                        ),
                      )
                    else if (block is Map && block['type'] == 'toggle')
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(block['label'] as String),
                        value: form[block['id']] == true,
                        onChanged: (value) => setDialogState(
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
                            onChanged: (value) => setDialogState(
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
                            dialogContext,
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
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(ref.tr('close')),
            ),
          ],
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
