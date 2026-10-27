import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app_state.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets/app_svg_icon.dart';
import 'home_screen.dart';
import 'imported_media_screen.dart';
import 'settings_library_screen.dart';

/// Settings page (center-pane body; shell owns chrome).
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String? _section = 'settings_import';
  bool _ambientExpanded = false;

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final ambientLightEnabled = ref.watch(ambientLightProvider);
    final ambientIntensity = ref.watch(ambientIntensityProvider);
    final ambientGeometry = ref.watch(ambientGeometryProvider);
    final ambientFrameRate = ref.watch(ambientFrameRateProvider);
    final themeMode = ref.watch(themeModeProvider);
    final language = ref.watch(languageProvider);
    final normalization = ref.watch(audioSettingsProvider);
    final supportsNormalization = ref
        .watch(engineProvider)
        .supportsVolumeNormalization;
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
          const Divider(height: 1, indent: 16, endIndent: 16),
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
        icon: 'volume_normalization',
        description: ref.tr('settings_audio_hint'),
        title: ref.tr('settings_audio'),
        children: [
          SwitchListTile(
            key: const ValueKey('volume-normalization'),
            secondary: const AppSvgIcon('volume_normalization'),
            title: Text(ref.tr('volume_normalization')),
            subtitle: Text(
              ref.tr(
                !supportsNormalization
                    ? 'normalization_unsupported'
                    : normalization.hasError
                    ? 'normalization_failed'
                    : 'normalization_desc',
              ),
            ),
            value: normalization.valueOrNull ?? false,
            onChanged: supportsNormalization && !normalization.isLoading
                ? ref.read(audioSettingsProvider.notifier).setEnabled
                : null,
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
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

        Widget mobileSectionChip(String? id, String title) => ChoiceChip(
          key: ValueKey('settings-category-${id ?? 'all'}'),
          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
          label: Text(title),
          selected: _section == id,
          showCheckmark: false,
          onSelected: (_) => selectSection(id),
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
                        SizedBox(
                          height: 48,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                mobileSectionChip(null, ref.tr('settings_all')),
                                for (final group in groups) ...[
                                  const SizedBox(width: 8),
                                  mobileSectionChip(group.id, group.title),
                                ],
                              ],
                            ),
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
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: 10,
          label: '${(value * 100).round()}%',
          onChanged: enabled ? onChanged : null,
          onChangeEnd: enabled ? (_) => onCommit() : null,
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
