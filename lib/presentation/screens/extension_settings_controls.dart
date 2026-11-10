import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../extensions/extension_manifest.dart';
import '../../extensions/extension_registry.dart';
import '../../extensions/extension_runtime.dart';
import '../i18n.dart';

class ExtensionSettingsCatalog extends ConsumerWidget {
  const ExtensionSettingsCatalog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final extensions = ref
        .watch(extensionRegistryProvider)
        .where(
          (extension) =>
              extension.enabled &&
              extension.grantedPermissions.contains(
                YureruExtensionPermission.uiContribution,
              ),
        );
    if (extensions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(ref.tr('extension_settings_empty')),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final extension in extensions)
          _ExtensionSettingsSection(extension: extension),
      ],
    );
  }
}

class _ExtensionSettingsSection extends ConsumerStatefulWidget {
  const _ExtensionSettingsSection({required this.extension});

  final YureruExtension extension;

  @override
  ConsumerState<_ExtensionSettingsSection> createState() =>
      _ExtensionSettingsSectionState();
}

class _ExtensionSettingsSectionState
    extends ConsumerState<_ExtensionSettingsSection> {
  int _revision = 0;

  @override
  Widget build(BuildContext context) => FutureBuilder(
    future: ref.read(extensionDispatcherProvider).describe(widget.extension),
    builder: (context, snapshot) {
      final settings = snapshot.data?['settings'] as List? ?? const [];
      if (settings.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.extension.manifest.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (widget.extension.grantedPermissions.contains(
                  YureruExtensionPermission.extensionStorage,
                ))
                  IconButton(
                    tooltip: ref.tr('extension_settings_reset'),
                    icon: const Icon(Icons.restart_alt_rounded),
                    onPressed: () async {
                      await ref
                          .read(extensionDispatcherProvider)
                          .resetSettings(widget.extension);
                      if (mounted) setState(() => _revision++);
                    },
                  ),
              ],
            ),
          ),
          for (final item in settings)
            if (item is Map<String, Object?> && item['type'] == 'section')
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
                child: Text(
                  item['label'] as String? ?? '',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              )
            else if (item is Map<String, Object?>)
              _PersistentExtensionSetting(
                key: ValueKey(
                  '${widget.extension.manifest.id}-$_revision-${item['id']}',
                ),
                extension: widget.extension,
                definition: item,
              ),
          const Divider(height: 1, indent: 16, endIndent: 16),
        ],
      );
    },
  );
}

class _PersistentExtensionSetting extends ConsumerStatefulWidget {
  const _PersistentExtensionSetting({
    super.key,
    required this.extension,
    required this.definition,
  });

  final YureruExtension extension;
  final Map<String, Object?> definition;

  @override
  ConsumerState<_PersistentExtensionSetting> createState() =>
      _PersistentExtensionSettingState();
}

class _PersistentExtensionSettingState
    extends ConsumerState<_PersistentExtensionSetting> {
  late Future<Map<String, Object?>> _storedSettings;
  Timer? _saveDebounce;
  Object? _draftValue;

  @override
  void initState() {
    super.initState();
    _storedSettings = ref
        .read(extensionDispatcherProvider)
        .readSettings(widget.extension);
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    super.dispose();
  }

  Object? _value(Map<String, Object?> stored) =>
      _draftValue ??
      stored[widget.definition['id']] ??
      widget.definition['default'];

  Future<void> _save(Object? value) async {
    final id = widget.definition['id'];
    if (id is! String ||
        !widget.extension.grantedPermissions.contains(
          YureruExtensionPermission.extensionStorage,
        )) {
      return;
    }
    if (mounted) setState(() => _draftValue = value);
    await ref
        .read(extensionDispatcherProvider)
        .writeSetting(widget.extension, id, value);
    if (!mounted) return;
    setState(() {
      _storedSettings = ref
          .read(extensionDispatcherProvider)
          .readSettings(widget.extension);
    });
  }

  void _saveText(String value) {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(_save(value));
    });
  }

  void _saveNumber(double value) {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(_save(value));
    });
    setState(() => _draftValue = value);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, Object?>>(
    future: _storedSettings,
    builder: (context, snapshot) {
      final definition = widget.definition;
      final id = definition['id'] as String;
      final label = definition['label'] as String;
      final description = definition['description'] as String?;
      final type = definition['type'] as String;
      final canPersist = widget.extension.grantedPermissions.contains(
        YureruExtensionPermission.extensionStorage,
      );
      final values = snapshot.data ?? const <String, Object?>{};
      final value = _value(values);
      if (!canPersist) {
        return ListTile(
          leading: const Icon(Icons.lock_outline_rounded),
          title: Text(label),
          subtitle: Text(ref.tr('extension_settings_storage_required')),
        );
      }
      if (type == 'toggle') {
        return SwitchListTile(
          title: Text(label),
          subtitle: description == null ? null : Text(description),
          value: value == true,
          onChanged: snapshot.connectionState == ConnectionState.done
              ? (next) => unawaited(_save(next))
              : null,
        );
      }
      if (type == 'select') {
        final options = definition['options'] as List<String>;
        final selected = options.contains(value)
            ? value as String
            : options.first;
        return ListTile(
          title: Text(label),
          subtitle: description == null ? null : Text(description),
          trailing: DropdownButton<String>(
            value: selected,
            items: [
              for (final option in options)
                DropdownMenuItem(value: option, child: Text(option)),
            ],
            onChanged: snapshot.connectionState == ConnectionState.done
                ? (next) {
                    if (next != null) unawaited(_save(next));
                  }
                : null,
          ),
        );
      }
      if (type == 'slider') {
        final min = definition['min'] as double;
        final max = definition['max'] as double;
        final current = value is num
            ? value.toDouble().clamp(min, max).toDouble()
            : (definition['default'] as double);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$label · ${current.toStringAsFixed(2)}'),
              if (description != null) Text(description),
              Slider(
                min: min,
                max: max,
                value: current,
                onChanged: snapshot.connectionState == ConnectionState.done
                    ? (next) => _saveDebounceValue(next)
                    : null,
                onChangeEnd: (next) => unawaited(_save(next)),
              ),
            ],
          ),
        );
      }
      if (type == 'number') {
        final min = definition['min'] as double;
        final max = definition['max'] as double;
        final current = value is num
            ? value.toDouble().clamp(min, max).toDouble()
            : (definition['default'] as double);
        final text = current == current.roundToDouble()
            ? current.toInt().toString()
            : current.toString();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: TextFormField(
            key: ValueKey(
              '${widget.extension.manifest.id}-$id-${snapshot.connectionState}',
            ),
            initialValue: text,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
              signed: true,
            ),
            decoration: InputDecoration(
              labelText: label,
              helperText: description == null
                  ? '${definition['min']} – ${definition['max']}'
                  : '$description · ${definition['min']} – ${definition['max']}',
            ),
            onChanged: (input) {
              final parsed = double.tryParse(input);
              if (parsed != null && parsed >= min && parsed <= max) {
                _saveNumber(parsed);
              }
            },
            onFieldSubmitted: (input) {
              final parsed = double.tryParse(input);
              if (parsed != null && parsed >= min && parsed <= max) {
                unawaited(_save(parsed));
              }
            },
            enabled: snapshot.connectionState == ConnectionState.done,
          ),
        );
      }
      final currentText = value is String ? value : '';
      final colorValid =
          type != 'color' ||
          RegExp(r'^#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').hasMatch(currentText);
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: TextFormField(
          key: ValueKey(
            '${widget.extension.manifest.id}-$id-${snapshot.connectionState}',
          ),
          initialValue: currentText,
          minLines: type == 'multiline' ? 3 : 1,
          maxLines: type == 'multiline' ? 8 : 1,
          decoration: InputDecoration(
            labelText: label,
            helperText: description,
            errorText: type == 'color' && !colorValid
                ? ref.tr('extension_settings_invalid_color')
                : null,
            prefixIcon: type == 'color'
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: CircleAvatar(
                      radius: 10,
                      backgroundColor: colorValid
                          ? Color(
                              int.parse(currentText.substring(1), radix: 16) |
                                  (currentText.length == 7 ? 0xFF000000 : 0),
                            )
                          : Theme.of(context).colorScheme.surfaceContainerHigh,
                    ),
                  )
                : null,
          ),
          onChanged: (next) {
            if (type != 'color' ||
                RegExp(
                  r'^#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$',
                ).hasMatch(next)) {
              _saveText(next);
            }
            setState(() {});
          },
          onFieldSubmitted: (next) {
            if (type != 'color' ||
                RegExp(
                  r'^#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$',
                ).hasMatch(next)) {
              unawaited(_save(next));
            }
          },
          enabled: snapshot.connectionState == ConnectionState.done,
        ),
      );
    },
  );

  void _saveDebounceValue(double value) {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 180), () {
      unawaited(_save(value));
    });
    setState(() => _draftValue = value);
  }
}
