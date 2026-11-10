import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_state.dart';
import '../i18n.dart';
import '../theme.dart';

class AppearanceColorsScreen extends ConsumerWidget {
  const AppearanceColorsScreen({super.key});

  static const _accents = <(int, String)>[
    (0xFF9B533F, 'color_coral'),
    (0xFF4767B1, 'color_blue'),
    (0xFF6652A3, 'color_violet'),
    (0xFF168A86, 'color_teal'),
    (0xFF418358, 'color_green'),
    (0xFFC07A25, 'color_amber'),
    (0xFFC14E78, 'color_pink'),
    (0xFF687680, 'color_slate'),
  ];

  static const _darkBackgrounds = <(int, String)>[
    (0xFF181818, 'background_charcoal'),
    (0xFF101216, 'background_midnight'),
    (0xFF151D25, 'background_blue'),
    (0xFF17211B, 'background_forest'),
    (0xFF24191D, 'background_wine'),
    (0xFF241D16, 'background_warm'),
    (0xFF141414, 'background_black'),
  ];

  static const _lightBackgrounds = <(int, String)>[
    (0xFFF5F5F5, 'background_neutral'),
    (0xFFF0F4F8, 'background_blue'),
    (0xFFF0F5F1, 'background_forest'),
    (0xFFF8F1EB, 'background_warm'),
    (0xFFF7F0F3, 'background_wine'),
    (0xFFFAF8F1, 'background_sand'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = ref.watch(appearanceColorsProvider);
    final notifier = ref.read(appearanceColorsProvider.notifier);
    final paletteLabels = {
      for (final key in [
        'color_coral',
        'color_blue',
        'color_violet',
        'color_teal',
        'color_green',
        'color_amber',
        'color_pink',
        'color_slate',
        'background_charcoal',
        'background_midnight',
        'background_blue',
        'background_forest',
        'background_wine',
        'background_warm',
        'background_black',
        'background_neutral',
        'background_sand',
      ])
        key: ref.tr(key),
    };
    final customColorLabel = ref.tr('appearance_custom_color');
    final pickerLabels = _colorPickerLabels(ref);
    final accentLabel = ref.tr('appearance_accent');
    final darkBackgroundLabel = ref.tr('appearance_dark_background');
    final lightBackgroundLabel = ref.tr('appearance_light_background');
    return Scaffold(
      appBar: AppBar(title: Text(ref.tr('appearance_colors'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ref.tr('appearance_colors_preview'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _ThemePreview(
                          title: ref.tr('dark'),
                          background: Color(colors.darkBackground),
                          accent: Color(colors.accent),
                          foreground: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ThemePreview(
                          title: ref.tr('light'),
                          background: Color(colors.lightBackground),
                          accent: Color(colors.accent),
                          foreground: const Color(0xFF242424),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _ColorGroup(
            title: ref.tr('appearance_accent'),
            hint: ref.tr('appearance_accent_hint'),
            options: _accents,
            selected: colors.accent,
            onSelected: notifier.setAccent,
            labelFor: (key) => paletteLabels[key] ?? key,
            customLabel: customColorLabel,
            onCustom: () async {
              final selected = await _pickColor(
                context,
                accentLabel,
                Color(colors.accent),
                kind: _ColorKind.accent,
                labels: pickerLabels,
              );
              if (selected != null) notifier.setAccent(selected.toARGB32());
            },
          ),
          const SizedBox(height: 12),
          _ColorGroup(
            title: ref.tr('appearance_dark_background'),
            hint: ref.tr('appearance_dark_background_hint'),
            options: _darkBackgrounds,
            selected: colors.darkBackground,
            onSelected: notifier.setDarkBackground,
            labelFor: (key) => paletteLabels[key] ?? key,
            customLabel: customColorLabel,
            onCustom: () async {
              final selected = await _pickColor(
                context,
                darkBackgroundLabel,
                Color(colors.darkBackground),
                kind: _ColorKind.darkBackground,
                labels: pickerLabels,
              );
              if (selected != null) {
                notifier.setDarkBackground(selected.toARGB32());
              }
            },
          ),
          const SizedBox(height: 12),
          _ColorGroup(
            title: ref.tr('appearance_light_background'),
            hint: ref.tr('appearance_light_background_hint'),
            options: _lightBackgrounds,
            selected: colors.lightBackground,
            onSelected: notifier.setLightBackground,
            labelFor: (key) => paletteLabels[key] ?? key,
            customLabel: customColorLabel,
            onCustom: () async {
              final selected = await _pickColor(
                context,
                lightBackgroundLabel,
                Color(colors.lightBackground),
                kind: _ColorKind.lightBackground,
                labels: pickerLabels,
              );
              if (selected != null) {
                notifier.setLightBackground(selected.toARGB32());
              }
            },
          ),
          const SizedBox(height: 16),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton.icon(
              onPressed: notifier.reset,
              icon: const Icon(Icons.restart_alt_rounded),
              label: Text(ref.tr('appearance_reset')),
            ),
          ),
        ],
      ),
    );
  }

  Future<Color?> _pickColor(
    BuildContext context,
    String title,
    Color initial, {
    required _ColorKind kind,
    required Map<String, String> labels,
  }) {
    var hsv = HSVColor.fromColor(initial);
    final darkBackground = kind == _ColorKind.darkBackground;
    final accent = kind == _ColorKind.accent;
    return showDialog<Color>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: hsv.toColor(),
                    shape: BoxShape.circle,
                    border: Border.all(color: themeBorder(context)),
                  ),
                ),
                const SizedBox(height: 16),
                _ColorSlider(
                  label: labels['appearance_hue']!,
                  value: hsv.hue,
                  min: 0,
                  max: 360,
                  color: hsv.toColor(),
                  onChanged: (value) =>
                      setState(() => hsv = hsv.withHue(value)),
                ),
                _ColorSlider(
                  label: labels['appearance_saturation']!,
                  value: hsv.saturation,
                  min: accent ? 0.45 : 0,
                  max: accent ? 1 : 0.4,
                  color: hsv.toColor(),
                  onChanged: (value) =>
                      setState(() => hsv = hsv.withSaturation(value)),
                ),
                _ColorSlider(
                  label: labels['appearance_brightness']!,
                  value: hsv.value,
                  min: accent ? 0.35 : (darkBackground ? 0.04 : 0.88),
                  max: accent ? 1 : (darkBackground ? 0.16 : 1),
                  color: hsv.toColor(),
                  onChanged: (value) =>
                      setState(() => hsv = hsv.withValue(value)),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(labels['cancel']!),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, hsv.toColor()),
              child: Text(labels['done']!),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, String> _colorPickerLabels(WidgetRef ref) => {
    'appearance_hue': ref.tr('appearance_hue'),
    'appearance_saturation': ref.tr('appearance_saturation'),
    'appearance_brightness': ref.tr('appearance_brightness'),
    'cancel': ref.tr('cancel'),
    'done': ref.tr('done'),
  };
}

enum _ColorKind { accent, darkBackground, lightBackground }

class _ColorGroup extends StatelessWidget {
  const _ColorGroup({
    required this.title,
    required this.hint,
    required this.options,
    required this.selected,
    required this.onSelected,
    required this.labelFor,
    required this.customLabel,
    required this.onCustom,
  });

  final String title;
  final String hint;
  final List<(int, String)> options;
  final int selected;
  final ValueChanged<int> onSelected;
  final String Function(String) labelFor;
  final String customLabel;
  final VoidCallback onCustom;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(hint, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final option in [
                ...options,
                if (!options.any((option) => option.$1 == selected))
                  (selected, customLabel),
              ])
                Tooltip(
                  message: labelFor(option.$2),
                  child: Semantics(
                    button: true,
                    selected: selected == option.$1,
                    label: labelFor(option.$2),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => onSelected(option.$1),
                      child: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Color(option.$1),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected == option.$1
                                ? Theme.of(context).colorScheme.primary
                                : themeBorder(context),
                            width: selected == option.$1 ? 3 : 1,
                          ),
                        ),
                        child: selected == option.$1
                            ? Icon(
                                Icons.check_rounded,
                                color: Color(option.$1).computeLuminance() > 0.5
                                    ? Colors.black87
                                    : Colors.white,
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
              Tooltip(
                message: customLabel,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onCustom,
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: themeBorder(context)),
                    ),
                    child: const Icon(Icons.add_rounded),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _ColorSlider extends StatelessWidget {
  const _ColorSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.color,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final Color color;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label),
      Slider(
        value: value.clamp(min, max).toDouble(),
        min: min,
        max: max,
        activeColor: color,
        onChanged: onChanged,
      ),
    ],
  );
}

class _ThemePreview extends StatelessWidget {
  const _ThemePreview({
    required this.title,
    required this.background,
    required this.accent,
    required this.foreground,
  });

  final String title;
  final Color background;
  final Color accent;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
    height: 76,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: themeBorder(context)),
    ),
    child: Row(
      children: [
        Container(
          width: 12,
          height: 36,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: foreground, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}
