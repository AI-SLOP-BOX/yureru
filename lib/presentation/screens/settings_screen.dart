import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app_state.dart';
import '../../ambient/video_lyrics_settings.dart';
import '../../domain/models.dart';
import '../../platform/keyboard_shortcuts.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets/app_svg_icon.dart';
import '../widgets/page_header.dart';
import '../widgets/semantics_safe_slider.dart';
import 'imported_media_screen.dart';
import 'settings_library_screen.dart';
import 'settings_lyrics_screen.dart';
import 'licenses_screen.dart';

/// Settings page (center-pane body; shell owns chrome).
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // Show all settings when the page first opens; users can narrow the list
  // with the category controls when they want a focused section.
  String? _section;
  bool _ambientExpanded = false;
  final ScrollController _mobileCategoryController = ScrollController();
  final GlobalKey _categoryViewportKey = GlobalKey();
  final Map<String, GlobalKey> _categoryKeys = {};
  List<String> _categoryOrder = const [];
  int _pendingCategorySteps = 0;
  bool _isScrollingCategories = false;
  bool _canScrollCategoriesRight = false;
  bool _canScrollCategoriesLeft = false;

  @override
  void initState() {
    super.initState();
    _mobileCategoryController.addListener(_updateCategoryScrollAffordance);
  }

  @override
  void dispose() {
    _mobileCategoryController
      ..removeListener(_updateCategoryScrollAffordance)
      ..dispose();
    super.dispose();
  }

  void _updateCategoryScrollAffordance() {
    if (!_mobileCategoryController.hasClients) return;
    final position = _mobileCategoryController.position;
    final canScrollRight = position.extentAfter > 2;
    final canScrollLeft = position.extentBefore > 2;
    if ((canScrollRight != _canScrollCategoriesRight ||
            canScrollLeft != _canScrollCategoriesLeft) &&
        mounted) {
      setState(() {
        _canScrollCategoriesRight = canScrollRight;
        _canScrollCategoriesLeft = canScrollLeft;
      });
    }
  }

  Future<void> _scrollCategories(bool forward) async {
    _pendingCategorySteps += forward ? 1 : -1;
    if (_isScrollingCategories) return;
    _isScrollingCategories = true;
    try {
      while (_pendingCategorySteps != 0 && mounted) {
        final step = _pendingCategorySteps.sign;
        _pendingCategorySteps -= step;
        await _scrollOneCategory(step > 0);
      }
    } finally {
      _isScrollingCategories = false;
    }
  }

  Future<void> _scrollOneCategory(bool forward) async {
    if (!_mobileCategoryController.hasClients) return;
    final viewport = _categoryViewportKey.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) return;
    final viewportLeft = viewport.localToGlobal(Offset.zero).dx;
    final items = <({int index, double left, double right})>[];
    for (var index = 0; index < _categoryOrder.length; index++) {
      final renderObject = _categoryKeys[_categoryOrder[index]]?.currentContext
          ?.findRenderObject();
      if (renderObject is! RenderBox || !renderObject.hasSize) continue;
      final left = renderObject.localToGlobal(Offset.zero).dx;
      items.add((
        index: index,
        left: left,
        right: left + renderObject.size.width,
      ));
    }
    final anchor = items.indexWhere((item) => item.right > viewportLeft + 1);
    if (anchor < 0) return;
    final targetIndex = forward ? anchor + 1 : anchor - 1;
    if (targetIndex < 0 || targetIndex >= _categoryOrder.length) return;
    ({int index, double left, double right})? targetItem;
    for (final item in items) {
      if (item.index == targetIndex) {
        targetItem = item;
        break;
      }
    }
    if (targetItem == null) return;
    final position = _mobileCategoryController.position;
    final target = (position.pixels + targetItem.left - viewportLeft).clamp(
      0.0,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() < 1) return;
    await _mobileCategoryController.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _editShortcut(AppShortcutAction action) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(ref.tr('settings_shortcuts')),
        content: SizedBox(
          width: 320,
          height: 72,
          child: Focus(
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is! KeyDownEvent) return KeyEventResult.ignored;
              final key = event.logicalKey;
              final modifierKeys = [
                LogicalKeyboardKey.shiftLeft,
                LogicalKeyboardKey.shiftRight,
                LogicalKeyboardKey.controlLeft,
                LogicalKeyboardKey.controlRight,
                LogicalKeyboardKey.altLeft,
                LogicalKeyboardKey.altRight,
                LogicalKeyboardKey.metaLeft,
                LogicalKeyboardKey.metaRight,
              ];
              if (modifierKeys.contains(key)) return KeyEventResult.handled;
              final keyboard = HardwareKeyboard.instance;
              final binding = AppShortcutBinding(
                keyId: key.keyId,
                meta: keyboard.isMetaPressed,
                control: keyboard.isControlPressed,
                alt: keyboard.isAltPressed,
                shift: keyboard.isShiftPressed,
              );
              final bindings = ref.read(keyboardShortcutsProvider);
              final conflict = bindings.entries.any(
                (entry) =>
                    entry.key != action && sameShortcut(entry.value, binding),
              );
              if (conflict) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(ref.tr('shortcut_conflict'))),
                );
                return KeyEventResult.handled;
              }
              ref
                  .read(keyboardShortcutsProvider.notifier)
                  .setBinding(action, binding);
              Navigator.pop(dialogContext);
              return KeyEventResult.handled;
            },
            child: Center(
              child: Text(
                ref.tr('shortcut_recording'),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(ref.tr('shortcut_cancel')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final ambientLightEnabled = ref.watch(ambientLightProvider);
    final ambientIntensity = ref.watch(ambientIntensityProvider);
    final ambientGeometry = ref.watch(ambientGeometryProvider);
    final ambientFrameRate = ref.watch(ambientFrameRateProvider);
    final videoLyricsSettings = ref.watch(videoLyricsSettingsProvider);
    final themeMode = ref.watch(themeModeProvider);
    final imagePriorities = ref.watch(mediaImagePriorityProvider);
    final library = ref.watch(libraryProvider);
    final language = ref.watch(languageProvider);
    final normalization = ref.watch(audioSettingsProvider);
    final supportsNormalization = ref
        .watch(engineProvider)
        .supportsVolumeNormalization;
    Future<void> choosePlaylistArtwork(Playlist playlist) async {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: false,
      );
      final sourcePath = result?.files.single.path;
      if (sourcePath == null) return;
      try {
        final support = await getApplicationSupportDirectory();
        final directory = Directory('${support.path}/yureru_playlist_artwork');
        await directory.create(recursive: true);
        final extension = File(
          sourcePath,
        ).uri.pathSegments.last.split('.').last.toLowerCase();
        final destination =
            '${directory.path}/${playlist.id}_${DateTime.now().microsecondsSinceEpoch}.$extension';
        await File(sourcePath).copy(destination);
        await ref
            .read(libraryProvider.notifier)
            .setPlaylistArtworkPath(playlist.id, destination);
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                ref.tr('artwork_save_error').replaceAll('{error}', '$error'),
              ),
            ),
          );
        }
      }
    }

    Widget imagePrioritySelector(String title, MediaImageContext screen) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(title, style: Theme.of(context).textTheme.labelLarge),
            ),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<MediaImagePriority>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: MediaImagePriority.artworkFirst,
                    label: Text(ref.tr('image_priority_artwork')),
                  ),
                  ButtonSegment(
                    value: MediaImagePriority.thumbnailFirst,
                    label: Text(ref.tr('image_priority_thumbnail')),
                  ),
                ],
                selected: {
                  imagePriorities[screen] ??
                      defaultMediaImagePriorities[screen]!,
                },
                onSelectionChanged: (selection) => ref
                    .read(mediaImagePriorityProvider.notifier)
                    .setPriority(screen, selection.first),
              ),
            ),
          ],
        ),
      );
    }

    Widget playlistImagePrioritySelector(Playlist playlist) {
      final value = playlist.imagePriority ?? 'default';
      return Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    displayTitle(playlist.name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 176,
                  child: DropdownButtonFormField<String>(
                    initialValue: value,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'default',
                        child: Text(
                          ref.tr('image_priority_default'),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DropdownMenuItem(
                        value: MediaImagePriority.artworkFirst.name,
                        child: Text(ref.tr('image_priority_artwork')),
                      ),
                      DropdownMenuItem(
                        value: MediaImagePriority.thumbnailFirst.name,
                        child: Text(ref.tr('image_priority_thumbnail')),
                      ),
                    ],
                    onChanged: (selection) => ref
                        .read(libraryProvider.notifier)
                        .setPlaylistImagePriority(
                          playlist.id,
                          selection == null || selection == 'default'
                              ? null
                              : selection,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: SizedBox.square(
                    dimension: 38,
                    child: playlist.artworkPath == null
                        ? ColoredBox(
                            color: themeBorder(context),
                            child: const Icon(Icons.queue_music_rounded),
                          )
                        : Image.file(
                            File(playlist.artworkPath!),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => ColoredBox(
                              color: themeBorder(context),
                              child: const Icon(Icons.broken_image_outlined),
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => choosePlaylistArtwork(playlist),
                  icon: const Icon(Icons.image_outlined, size: 18),
                  label: Text(ref.tr('choose_artwork')),
                ),
                if (playlist.artworkPath != null)
                  IconButton(
                    tooltip: ref.tr('clear_artwork'),
                    onPressed: () => ref
                        .read(libraryProvider.notifier)
                        .setPlaylistArtworkPath(playlist.id, null),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
              ],
            ),
          ],
        ),
      );
    }

    final groups = <_SettingsGroup>[
      _SettingsGroup(
        id: 'settings_library',
        icon: 'settings_folder',
        description: ref.tr('settings_library_hint'),
        title: ref.tr('settings_library'),
        children: [
          ListTile(
            leading: const AppSvgIcon('settings_folder'),
            title: Text(ref.tr('import_video')),
            subtitle: Text(ref.tr('library_management_desc')),
            trailing: const AppSvgIcon('chevron_right', size: 20),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            onTap: () => SettingsScreenActions.openLibraryManagement(context),
          ),
          ListTile(
            leading: const AppSvgIcon('collection_edit'),
            title: Text(ref.tr('edit_media_artwork')),
            subtitle: Text(ref.tr('edit_media_artwork_desc')),
            trailing: const AppSvgIcon('chevron_right', size: 20),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            onTap: () => SettingsScreenActions.openMediaEditor(context),
          ),
          ListTile(
            leading: const Icon(Icons.lyrics_outlined),
            title: Text(ref.tr('lyrics_settings')),
            subtitle: Text(ref.tr('lyrics_settings_hint')),
            trailing: const AppSvgIcon('chevron_right', size: 20),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            onTap: () => SettingsScreenActions.openLyricsSettings(context),
          ),
        ],
      ),
      if (Platform.isMacOS)
        _SettingsGroup(
          id: 'settings_default_media_player',
          icon: 'settings_info',
          description: ref.tr('default_media_player_desc'),
          title: ref.tr('default_media_player'),
          children: [
            ListTile(
              leading: const Icon(Icons.open_in_new_rounded),
              title: Text(ref.tr('set_default_media_player')),
              subtitle: Text(ref.tr('default_media_player_desc')),
              onTap: () async {
                try {
                  await SettingsScreenActions.setAsDefaultMediaPlayer();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(ref.tr('default_media_player_set'))),
                  );
                } on PlatformException catch (error) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        ref
                            .tr('default_media_player_failed')
                            .replaceAll('{error}', error.message ?? error.code),
                      ),
                    ),
                  );
                }
              },
            ),
          ],
        ),
      _SettingsGroup(
        id: 'video_lyrics_overlay',
        icon: 'settings_tune',
        description: ref.tr('video_lyrics_customization_desc'),
        title: ref.tr('video_lyrics_customization'),
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.closed_caption_rounded),
            title: Text(ref.tr('video_lyrics_overlay')),
            subtitle: Text(ref.tr('video_lyrics_overlay_desc')),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            value: videoLyricsSettings.enabled,
            onChanged: (enabled) {
              final notifier = ref.read(videoLyricsSettingsProvider.notifier);
              notifier.update(videoLyricsSettings.copyWith(enabled: enabled));
              notifier.persist();
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _VideoLyricsPositionPreview(
                  settings: videoLyricsSettings,
                  hint: ref.tr('video_lyrics_drag_hint'),
                  resetLabel: ref.tr('video_lyrics_position_reset'),
                  onChanged: (next) => ref
                      .read(videoLyricsSettingsProvider.notifier)
                      .update(next),
                  onCommit: () =>
                      ref.read(videoLyricsSettingsProvider.notifier).persist(),
                ),
                const SizedBox(height: 12),
                Text(ref.tr('video_lyrics_font')),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: videoLyricsSettings.fontFamily,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    border: OutlineInputBorder(),
                  ),
                  items:
                      [
                            ('system', 'video_lyrics_font_system'),
                            ('serif', 'video_lyrics_font_serif'),
                            ('monospace', 'video_lyrics_font_monospace'),
                          ]
                          .map(
                            (font) => DropdownMenuItem(
                              value: font.$1,
                              child: Text(ref.tr(font.$2)),
                            ),
                          )
                          .toList(),
                  onChanged: (font) {
                    if (font == null) return;
                    final notifier = ref.read(
                      videoLyricsSettingsProvider.notifier,
                    );
                    notifier.update(
                      videoLyricsSettings.copyWith(fontFamily: font),
                    );
                    notifier.persist();
                  },
                ),
                const SizedBox(height: 8),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(ref.tr('video_lyrics_size')),
                  trailing: Text('${videoLyricsSettings.fontSize.round()}'),
                ),
                Slider(
                  value: videoLyricsSettings.fontSize,
                  min: 16,
                  max: 56,
                  divisions: 40,
                  onChanged: (size) => ref
                      .read(videoLyricsSettingsProvider.notifier)
                      .update(videoLyricsSettings.copyWith(fontSize: size)),
                  onChangeEnd: (_) =>
                      ref.read(videoLyricsSettingsProvider.notifier).persist(),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Text(ref.tr('video_lyrics_color')),
                ),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children:
                      [
                        (0xFFFFFFFF, 'video_lyrics_color_white'),
                        (0xFFFFE4B5, 'video_lyrics_color_warm'),
                        (0xFFFF987D, 'video_lyrics_color_coral'),
                        (0xFF8AE8FF, 'video_lyrics_color_cyan'),
                        (0xFF181818, 'video_lyrics_color_black'),
                      ].map((choice) {
                        final selected = videoLyricsSettings.color == choice.$1;
                        return Tooltip(
                          message: ref.tr(choice.$2),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () {
                              final notifier = ref.read(
                                videoLyricsSettingsProvider.notifier,
                              );
                              notifier.update(
                                videoLyricsSettings.copyWith(color: choice.$1),
                              );
                              notifier.persist();
                            },
                            child: Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: Color(choice.$1),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: selected
                                      ? Theme.of(context).colorScheme.primary
                                      : themeBorder(context),
                                  width: selected ? 3 : 1,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                ),
                const SizedBox(height: 16),
                Text(ref.tr('video_lyrics_frame')),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<VideoLyricsFrame>(
                    showSelectedIcon: false,
                    segments: VideoLyricsFrame.values
                        .map(
                          (frame) => ButtonSegment(
                            value: frame,
                            label: Text(
                              ref.tr('video_lyrics_frame_${frame.name}'),
                            ),
                          ),
                        )
                        .toList(),
                    selected: {videoLyricsSettings.frame},
                    onSelectionChanged: (selection) {
                      final notifier = ref.read(
                        videoLyricsSettingsProvider.notifier,
                      );
                      notifier.update(
                        videoLyricsSettings.copyWith(frame: selection.single),
                      );
                      notifier.persist();
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      _SettingsGroup(
        id: 'settings_display',
        icon: 'settings_palette',
        description: ref.tr('settings_display_hint'),
        title: ref.tr('settings_display'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const AppSvgIcon('settings_palette', size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ref.tr('theme'),
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          Text(
                            ref.tr('theme_desc'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text(ref.tr('system')),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        label: Text(ref.tr('light')),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        label: Text(ref.tr('dark')),
                      ),
                    ],
                    selected: {themeMode},
                    onSelectionChanged: (selection) => ref
                        .read(themeModeProvider.notifier)
                        .setThemeMode(selection.first),
                  ),
                ),
              ],
            ),
          ),
          SwitchListTile(
            secondary: const AppSvgIcon('settings_ambient'),
            title: Text(ref.tr('ambient_light')),
            subtitle: Text(ref.tr('ambient_light_desc')),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            value: ambientLightEnabled,
            onChanged: ref.read(ambientLightProvider.notifier).setEnabled,
          ),
          ExpansionTile(
            key: const PageStorageKey('ambient-details'),
            leading: const AppSvgIcon('settings_tune'),
            title: Text(ref.tr('settings_ambient_details')),
            subtitle: Text(ref.tr('settings_ambient_details_hint')),
            onExpansionChanged: (expanded) =>
                setState(() => _ambientExpanded = expanded),
            trailing: AnimatedRotation(
              turns: _ambientExpanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              child: const AppSvgIcon('chevron_down', size: 18),
            ),
            children: [
              _AmbientSettingSlider(
                icon: 'settings_tune',
                title: ref.tr('ambient_strength'),
                value: ambientIntensity,
                min: 0.5,
                max: 1.5,
                enabled: ambientLightEnabled,
                onChanged: ref
                    .read(ambientIntensityProvider.notifier)
                    .setIntensity,
                onCommit: ref
                    .read(ambientIntensityProvider.notifier)
                    .persistIntensity,
              ),
              _AmbientSettingSlider(
                icon: 'settings_spread',
                title: ref.tr('ambient_spread'),
                value: ambientGeometry.spread,
                min: 0.5,
                max: 1.5,
                enabled: ambientLightEnabled,
                onChanged: ref.read(ambientGeometryProvider.notifier).setSpread,
                onCommit: ref.read(ambientGeometryProvider.notifier).persist,
              ),
              _AmbientSettingSlider(
                icon: 'settings_depth',
                title: ref.tr('ambient_depth'),
                value: ambientGeometry.depth,
                min: 0,
                max: 2,
                enabled: ambientLightEnabled,
                onChanged: ref.read(ambientGeometryProvider.notifier).setDepth,
                onCommit: ref.read(ambientGeometryProvider.notifier).persist,
              ),
              _AmbientSettingSlider(
                icon: 'settings_softness',
                title: ref.tr('ambient_softness'),
                value: ambientGeometry.softness,
                min: 0.5,
                max: 1.5,
                enabled: ambientLightEnabled,
                onChanged: ref
                    .read(ambientGeometryProvider.notifier)
                    .setSoftness,
                onCommit: ref.read(ambientGeometryProvider.notifier).persist,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const AppSvgIcon('settings_speed', size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "${ref.tr('ambient_frame_rate')} (FPS)",
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              Text(
                                ref.tr('ambient_frame_rate_desc'),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: SegmentedButton<int>(
                        showSelectedIcon: false,
                        segments: const [0, 15, 30, 60]
                            .map(
                              (fps) => ButtonSegment<int>(
                                value: fps,
                                label: Text(
                                  fps == 0
                                      ? ref.tr('ambient_fps_auto')
                                      : '$fps',
                                ),
                              ),
                            )
                            .toList(),
                        selected: {ambientFrameRate},
                        onSelectionChanged: ambientLightEnabled
                            ? (selection) {
                                final notifier = ref.read(
                                  ambientFrameRateProvider.notifier,
                                );
                                notifier.setFrameRate(selection.first);
                                notifier.persist();
                              }
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      _SettingsGroup(
        id: 'settings_audio',
        icon: 'settings_tune',
        description: ref.tr('settings_audio_hint'),
        title: ref.tr('settings_audio'),
        children: [
          SwitchListTile.adaptive(
            key: const ValueKey('volume-normalization'),
            secondary: const Icon(Icons.equalizer_rounded),
            title: Text(ref.tr('volume_normalization')),
            subtitle: Text(
              !supportsNormalization
                  ? ref.tr('normalization_unsupported')
                  : normalization.hasError
                  ? '${ref.tr('normalization_failed')}\n${normalization.error}'
                  : ref.tr('normalization_desc'),
            ),
            value: normalization.valueOrNull ?? false,
            onChanged: supportsNormalization && !normalization.isLoading
                ? ref.read(audioSettingsProvider.notifier).setEnabled
                : null,
          ),
        ],
      ),
      _SettingsGroup(
        id: 'settings_image_priority',
        icon: 'settings_tune',
        description: ref.tr('image_display_priority_desc'),
        title: ref.tr('image_display_priority'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                imagePrioritySelector(
                  ref.tr('image_priority_home'),
                  MediaImageContext.home,
                ),
                imagePrioritySelector(
                  ref.tr('image_priority_playlists'),
                  MediaImageContext.playlist,
                ),
                imagePrioritySelector(
                  ref.tr('image_priority_albums'),
                  MediaImageContext.album,
                ),
                if (library.playlists.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(
                    ref.tr('playlist_image_priority_section'),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  for (final playlist in library.playlists)
                    playlistImagePrioritySelector(playlist),
                ],
              ],
            ),
          ),
        ],
      ),
      _SettingsGroup(
        id: 'settings_shortcuts',
        icon: 'settings_tune',
        description: ref.tr('settings_shortcuts_hint'),
        title: ref.tr('settings_shortcuts'),
        children: [
          for (final action in AppShortcutAction.values)
            ListTile(
              title: Text(ref.tr(shortcutActionName(action))),
              subtitle: Text(
                ref
                    .watch(keyboardShortcutsProvider)[action]!
                    .label(macOS: Platform.isMacOS),
              ),
              trailing: TextButton(
                onPressed: () => _editShortcut(action),
                child: Text(ref.tr('shortcut_change')),
              ),
              onTap: () => _editShortcut(action),
            ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(
              onPressed: ref.read(keyboardShortcutsProvider.notifier).reset,
              child: Text(ref.tr('shortcut_reset')),
            ),
          ),
        ],
      ),
      _SettingsGroup(
        id: 'settings_app',
        icon: 'settings_info',
        description: ref.tr('settings_app_hint'),
        title: ref.tr('settings_app'),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const AppSvgIcon('settings_language'),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        ref.tr('language'),
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _SettingsDropdown<AppLanguage>(
                  value: language,
                  items: AppLanguage.values
                      .map(
                        (item) => DropdownMenuItem(
                          value: item,
                          child: Text(item.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      ref.read(languageProvider.notifier).setLanguage(value);
                    }
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: const AppSvgIcon('settings_info'),
            title: Text(ref.tr('about_app')),
            subtitle: FutureBuilder<PackageInfo>(
              future: SettingsScreenActions.packageInfo,
              builder: (context, snapshot) {
                final info = snapshot.data;
                if (info == null) return Text(ref.tr('version_loading'));
                return Text(
                  ref
                      .tr('version_open_source')
                      .replaceAll('{version}', info.version),
                );
              },
            ),
            trailing: const AppSvgIcon('chevron_right', size: 20),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            onTap: () => SettingsScreenActions.openAbout(context),
          ),
          ListTile(
            leading: const Icon(Icons.policy_outlined),
            title: Text(ref.tr('open_source_licenses')),
            subtitle: Text(ref.tr('open_source_licenses_desc')),
            trailing: const AppSvgIcon('chevron_right', size: 20),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            onTap: () => SettingsScreenActions.openLicenses(context),
          ),
        ],
      ),
    ];
    final visible = groups.where(
      (group) => _section == null || group.id == _section,
    );
    _categoryOrder = ['__settings_all__', for (final group in groups) group.id];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _updateCategoryScrollAffordance();
        });
        final content = Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: ListView(
              key: ValueKey('settings-list-${_section ?? 'all'}'),
              padding: EdgeInsets.fromLTRB(
                wide ? 28 : 16,
                0,
                wide ? 28 : 16,
                40,
              ),
              children: [
                for (final group in visible) ...[
                  group,
                  const SizedBox(height: 20),
                ],
              ],
            ),
          ),
        );

        void selectSection(String? id) {
          setState(() => _section = id);
        }

        Widget desktopSection(String? id, String title, String icon) {
          final selected = _section == id;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: ValueKey('settings-category-${id ?? 'all'}'),
                borderRadius: BorderRadius.circular(10),
                onTap: () => selectSection(id),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? themeTextSub(context).withValues(alpha: 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected
                          ? themeBorder(context)
                          : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    children: [
                      AppSvgIcon(icon, size: 19),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: selected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: themeTextPrimary(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        Widget mobileSectionChip(String? id, String title) => KeyedSubtree(
          key: _categoryKeys.putIfAbsent(
            id ?? '__settings_all__',
            GlobalKey.new,
          ),
          child: ChoiceChip(
            key: ValueKey('settings-category-${id ?? 'all'}'),
            labelPadding: const EdgeInsets.symmetric(horizontal: 4),
            label: Text(title),
            selected: _section == id,
            showCheckmark: false,
            onSelected: (_) => selectSection(id),
          ),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHeader(title: ref.tr('settings')),
            Expanded(
              child: wide
                  ? Row(
                      children: [
                        SizedBox(
                          width: 224,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(8, 0, 8, 20),
                            children: [
                              desktopSection(
                                null,
                                ref.tr('settings_all'),
                                'settings_tune',
                              ),
                              for (final group in groups)
                                desktopSection(
                                  group.id,
                                  group.title,
                                  group.icon,
                                ),
                            ],
                          ),
                        ),
                        VerticalDivider(
                          width: 1,
                          thickness: 1,
                          color: themeBorder(context),
                        ),
                        Expanded(child: content),
                      ],
                    )
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
                          child: Row(
                            children: [
                              if (_canScrollCategoriesLeft)
                                IconButton(
                                  key: const ValueKey(
                                    'settings-category-scroll-left',
                                  ),
                                  tooltip: '←',
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.arrow_back_rounded),
                                  onPressed: () => _scrollCategories(false),
                                )
                              else
                                const SizedBox(width: 40),
                              Expanded(
                                child: SingleChildScrollView(
                                  key: _categoryViewportKey,
                                  controller: _mobileCategoryController,
                                  scrollDirection: Axis.horizontal,
                                  physics: const BouncingScrollPhysics(),
                                  child: Row(
                                    children: [
                                      mobileSectionChip(
                                        null,
                                        ref.tr('settings_all'),
                                      ),
                                      for (final group in groups) ...[
                                        const SizedBox(width: 8),
                                        mobileSectionChip(
                                          group.id,
                                          group.title,
                                        ),
                                      ],
                                      const SizedBox(width: 12),
                                    ],
                                  ),
                                ),
                              ),
                              if (_canScrollCategoriesRight)
                                IconButton(
                                  key: const ValueKey(
                                    'settings-category-scroll-right',
                                  ),
                                  tooltip: '→',
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.arrow_forward_rounded),
                                  onPressed: () => _scrollCategories(true),
                                ),
                            ],
                          ),
                        ),
                        Expanded(child: content),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _AmbientSettingSlider extends StatelessWidget {
  const _AmbientSettingSlider({
    required this.icon,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.enabled,
    required this.onChanged,
    required this.onCommit,
  });

  final String icon;
  final String title;
  final double value;
  final double min;
  final double max;
  final bool enabled;
  final ValueChanged<double> onChanged;
  final VoidCallback onCommit;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    child: Column(
      children: [
        Row(
          children: [
            AppSvgIcon(icon, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.bodyMedium),
            ),
            const SizedBox(width: 12),
            Text(
              '${(value * 100).round()}%',
              style: TextStyle(color: themeTextSub(context)),
            ),
          ],
        ),
        semanticsSafeSlider(
          Slider(
            value: value,
            min: min,
            max: max,
            divisions: 10,
            label: '${(value * 100).round()}%',
            onChanged: enabled ? onChanged : null,
            onChangeEnd: enabled ? (_) => onCommit() : null,
          ),
        ),
      ],
    ),
  );
}

class _SettingsDropdown<T> extends StatelessWidget {
  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _SettingsDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        value: value,
        isExpanded: true,
        items: items,
        onChanged: onChanged,
        borderRadius: BorderRadius.circular(12),
        dropdownColor: isDark ? kPanelSolid : Colors.white,
        style: TextStyle(color: isDark ? kTextPrimary : Colors.black87),
        icon: const AppSvgIcon('chevron_down', size: 20),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  final String title;
  final String id;
  final String icon;
  final String description;
  final List<Widget> children;
  const _SettingsGroup({
    required this.id,
    required this.icon,
    required this.description,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: themeCard(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: themeBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppSvgIcon(
                  icon,
                  size: 22,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: isDark ? kTextPrimary : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: TextStyle(
                          fontSize: 12,
                          color: themeTextSub(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _VideoLyricsPositionPreview extends StatelessWidget {
  const _VideoLyricsPositionPreview({
    required this.settings,
    required this.hint,
    required this.resetLabel,
    required this.onChanged,
    required this.onCommit,
  });

  final VideoLyricsSettings settings;
  final String hint;
  final String resetLabel;
  final ValueChanged<VideoLyricsSettings> onChanged;
  final VoidCallback onCommit;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final sample = Text(
      '歌詞のサンプル',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Color(settings.color),
        fontSize: settings.fontSize,
        fontFamily: switch (settings.fontFamily) {
          'serif' => 'serif',
          'monospace' => 'monospace',
          _ => null,
        },
        fontWeight: FontWeight.w700,
        height: 1.2,
        shadows: settings.frame == VideoLyricsFrame.outline
            ? const [
                Shadow(color: Colors.black, blurRadius: 5),
                Shadow(color: Colors.black, blurRadius: 2),
              ]
            : null,
      ),
    );
    final outlineSample = Stack(
      children: [
        Text(
          '歌詞のサンプル',
          textAlign: TextAlign.center,
          style: TextStyle(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3.5
              ..color = Colors.black,
            fontSize: settings.fontSize,
            fontFamily: settings.fontFamily == 'system'
                ? null
                : settings.fontFamily,
            fontWeight: FontWeight.w800,
            height: 1.2,
          ),
        ),
        sample,
      ],
    );
    final framedSample = switch (settings.frame) {
      VideoLyricsFrame.none => sample,
      VideoLyricsFrame.outline => outlineSample,
      VideoLyricsFrame.plate => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.62),
          border: Border.all(color: Colors.white38),
          borderRadius: BorderRadius.circular(8),
        ),
        child: sample,
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final previewHeight = constraints.maxHeight;
                    return Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF263C50),
                            Color(0xFF14262E),
                            Color(0xFF111820),
                          ],
                        ),
                      ),
                      child: Stack(
                        children: [
                          Positioned(
                            right: -38,
                            top: -55,
                            child: Container(
                              width: previewHeight * 0.9,
                              height: previewHeight * 0.9,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.lightBlueAccent.withValues(
                                  alpha: 0.12,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 12,
                            top: 10,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.28),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 3,
                                ),
                                child: Text(
                                  'MV',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Align(
                            alignment: Alignment(
                              settings.positionX * 2 - 1,
                              settings.positionY * 2 - 1,
                            ),
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onPanUpdate: (details) {
                                final width = constraints.maxWidth;
                                if (width <= 0 || previewHeight <= 0) return;
                                onChanged(
                                  settings.copyWith(
                                    positionX:
                                        (settings.positionX +
                                                details.delta.dx / width)
                                            .clamp(0.04, 0.96)
                                            .toDouble(),
                                    positionY:
                                        (settings.positionY +
                                                details.delta.dy /
                                                    previewHeight)
                                            .clamp(0.08, 0.92)
                                            .toDouble(),
                                  ),
                                );
                              },
                              onPanEnd: (_) => onCommit(),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: accent.withValues(alpha: 0.72),
                                    width: 1.5,
                                  ),
                                  borderRadius: BorderRadius.circular(9),
                                  color: Colors.black.withValues(alpha: 0.08),
                                ),
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: constraints.maxWidth * 0.9,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(6),
                                    child: framedSample,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: Text(
                hint,
                style: TextStyle(color: themeTextSub(context), fontSize: 12),
              ),
            ),
            TextButton.icon(
              onPressed: () {
                onChanged(settings.copyWith(positionX: 0.5, positionY: 0.84));
                onCommit();
              },
              icon: const Icon(Icons.restart_alt_rounded, size: 18),
              label: Text(resetLabel),
            ),
          ],
        ),
      ],
    );
  }
}

/// Opens settings sub-screens; kept next to the settings page.
class SettingsScreenActions {
  static const _defaultMediaPlayerChannel = MethodChannel(
    'yureru/default_media_player',
  );
  static final Future<PackageInfo> packageInfo = PackageInfo.fromPlatform();

  static Future<void> setAsDefaultMediaPlayer() =>
      _defaultMediaPlayerChannel.invokeMethod<void>('setAsDefaultMediaPlayer');

  static void openLibraryManagement(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const LibraryManagementScreen()));
  }

  static void openMediaEditor(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ImportedMediaScreen()));
  }

  static void openLyricsSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const LyricsSettingsScreen()),
    );
  }

  static Future<void> openAbout(BuildContext context) async {
    final info = await packageInfo;
    if (!context.mounted) return;
    showAboutDialog(
      context: context,
      applicationName: info.appName,
      applicationVersion: '${info.version} (${info.buildNumber})',
    );
  }

  static void openLicenses(BuildContext context) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const LicensesScreen()));
  }
}
