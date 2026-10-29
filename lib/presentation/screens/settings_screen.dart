import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app_state.dart';
import '../../platform/keyboard_shortcuts.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets/app_svg_icon.dart';
import '../widgets/page_header.dart';
import '../widgets/semantics_safe_slider.dart';
import 'imported_media_screen.dart';
import 'settings_library_screen.dart';

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
    final themeMode = ref.watch(themeModeProvider);
    final imagePriorities = ref.watch(mediaImagePriorityProvider);
    final language = ref.watch(languageProvider);
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

    final groups = <_SettingsGroup>[
      _SettingsGroup(
        id: 'settings_import',
        icon: 'settings_folder',
        description: ref.tr('import_video_desc'),
        title: ref.tr('import_video'),
        children: [
          ListTile(
            leading: const Icon(Icons.video_file_outlined),
            title: Text(ref.tr('import_video')),
            subtitle: Text(ref.tr('import_video_desc')),
            onTap: () => LibraryManagementScreen.importVideos(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.folder_open_rounded),
            title: Text(ref.tr('import_folder')),
            subtitle: Text(ref.tr('import_folder_desc')),
            onTap: () => LibraryManagementScreen.importFolder(context, ref),
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
        id: 'settings_library',
        icon: 'settings_folder',
        description: ref.tr('settings_library_hint'),
        title: ref.tr('settings_library'),
        children: [
          ListTile(
            leading: const AppSvgIcon('history'),
            title: Text(ref.tr('clear_playback_history')),
            onTap: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: Text(ref.tr('clear_playback_history')),
                  content: Text(ref.tr('clear_history_desc')),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: Text(ref.tr('cancel')),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: Text(ref.tr('clear')),
                    ),
                  ],
                ),
              );
              if (confirmed == true && context.mounted) {
                await ref.read(libraryProvider.notifier).clearPlaybackHistory();
              }
            },
          ),

          ListTile(
            leading: const AppSvgIcon('settings_folder'),
            title: Text(ref.tr('library_management')),
            subtitle: Text(ref.tr('library_management_desc')),
            trailing: const AppSvgIcon('chevron_right', size: 20),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            onTap: () => SettingsScreenActions.openLibraryManagement(context),
          ),
          const Divider(height: 1, indent: 16, endIndent: 16),
          ListTile(
            leading: const AppSvgIcon('collection_edit'),
            title: Text(ref.tr('edit_media_artwork')),
            subtitle: Text(ref.tr('edit_media_artwork_desc')),
            trailing: const AppSvgIcon('chevron_right', size: 20),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            onTap: () => SettingsScreenActions.openMediaEditor(context),
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

        void selectSection(String? id) => setState(() => _section = id);

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

  static Future<void> openAbout(BuildContext context) async {
    final info = await packageInfo;
    if (!context.mounted) return;
    showAboutDialog(
      context: context,
      applicationName: info.appName,
      applicationVersion: '${info.version} (${info.buildNumber})',
    );
  }
}
