import 'dart:convert';
import 'dart:io';

import 'package:quickjs_engine/quickjs/quickjs_runtime2.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models.dart';
import 'extension_manifest.dart';
import 'extension_registry.dart';

/// Runs one extension in an isolated JavaScript runtime for a single hook call.
/// No filesystem, network, or Flutter objects are exposed to extension code.
class YureruExtensionRuntime {
  static const _timeoutMicros = 500000;
  static const _memoryLimitBytes = 16 * 1024 * 1024;
  static const _stackSizeBytes = 256 * 1024;

  Future<Object?> invoke(
    YureruExtension extension,
    String hook,
    Map<String, Object?> payload,
  ) async {
    if (!extension.enabled || !extension.manifest.hooks.contains(hook)) {
      return null;
    }
    final requiredPermission = _permissionForHook(hook);
    if (requiredPermission != null &&
        !extension.grantedPermissions.contains(requiredPermission)) {
      return null;
    }
    final source = await File(extension.entrypointPath).readAsString();
    final runtime = QuickJsRuntime2(
      timeout: _timeoutMicros,
      memoryLimit: _memoryLimitBytes,
      stackSize: _stackSizeBytes,
    );
    try {
      final registration = runtime.evaluate('''
        (() => {
          const hooks = Object.create(null);
          globalThis.Yureru = Object.freeze({
            apiVersion: 1,
            on(name, callback) {
              if (typeof name !== 'string' || typeof callback !== 'function') {
                throw new TypeError('Yureru.on expects a hook name and function');
              }
              (hooks[name] ??= []).push(callback);
            },
            register(value) {
              if (!value || typeof value !== 'object' || Array.isArray(value)) {
                throw new TypeError('Yureru.register expects an object');
              }
            }
          });
          globalThis.__yureruHooks = hooks;
        })();
        $source
        true;
      ''');
      if (registration.isError) {
        throw StateError(
          'Extension failed to load: ${registration.stringResult}',
        );
      }
      final input = jsonEncode(payload);
      final hookLiteral = jsonEncode(hook);
      final result = runtime.evaluate('''
        (() => {
          const callbacks = globalThis.__yureruHooks[$hookLiteral] || [];
          const event = Object.freeze(JSON.parse(${jsonEncode(input)}));
          let value = event;
          for (const callback of callbacks) {
            const next = callback(value);
            if (next !== undefined) value = next;
          }
          return JSON.stringify(value);
        })();
      ''');
      if (result.isError) {
        throw StateError('Extension hook failed: ${result.stringResult}');
      }
      if (result.rawResult is! String) return result.rawResult;
      return jsonDecode(result.rawResult as String);
    } finally {
      runtime.dispose();
    }
  }

  /// Reads the extension's declarative UI contribution. Contributions are data,
  /// not Flutter code, so the host can validate and render them safely.
  Future<Map<String, Object?>> describe(YureruExtension extension) async {
    if (!extension.enabled ||
        (!extension.grantedPermissions.contains(
              YureruExtensionPermission.uiContribution,
            ) &&
            !extension.grantedPermissions.contains(
              YureruExtensionPermission.themeCustomize,
            ))) {
      return const {};
    }
    final source = await File(extension.entrypointPath).readAsString();
    final runtime = QuickJsRuntime2(
      timeout: _timeoutMicros,
      memoryLimit: _memoryLimitBytes,
      stackSize: _stackSizeBytes,
    );
    try {
      final loaded = runtime.evaluate('''
        (() => {
          const hooks = Object.create(null);
          let contribution = {};
          globalThis.Yureru = Object.freeze({
            apiVersion: 1,
            on(name, callback) {
              if (typeof name !== 'string' || typeof callback !== 'function') {
                throw new TypeError('Yureru.on expects a hook name and function');
              }
              (hooks[name] ??= []).push(callback);
            },
            register(value) {
              if (!value || typeof value !== 'object' || Array.isArray(value)) {
                throw new TypeError('Yureru.register expects an object');
              }
              contribution = JSON.parse(JSON.stringify(value));
            }
          });
          globalThis.__yureruHooks = hooks;
          globalThis.__yureruContribution = () => contribution;
        })();
        $source
        JSON.stringify(globalThis.__yureruContribution());
      ''');
      if (loaded.isError) {
        throw StateError('Extension failed to load: ${loaded.stringResult}');
      }
      final rawResult = loaded.rawResult;
      if (rawResult is! String) return const {};
      final decoded = jsonDecode(rawResult);
      if (decoded is! Map) return const {};
      return _sanitizeContribution(decoded, extension);
    } finally {
      runtime.dispose();
    }
  }

  Map<String, Object?> _sanitizeContribution(
    Map<dynamic, dynamic> raw,
    YureruExtension extension,
  ) {
    List<Map<String, Object?>> entries(String key, int max) {
      final value = raw[key];
      if (value is! List) return const [];
      return [
        for (final item in value.take(max))
          if (item is Map) Map<String, Object?>.from(item),
      ];
    }

    String? text(Object? value, {int max = 100}) {
      if (value is! String || value.trim().isEmpty || value.length > max) {
        return null;
      }
      return value.trim();
    }

    final canContributeUi = extension.grantedPermissions.contains(
      YureruExtensionPermission.uiContribution,
    );
    final canCustomizeTheme = extension.grantedPermissions.contains(
      YureruExtensionPermission.themeCustomize,
    );
    final commands = <Map<String, Object?>>[];
    for (final item in canContributeUi ? entries('commands', 24) : const []) {
      final id = text(item['id'], max: 64);
      final title = text(item['title']);
      final action = text(item['action'], max: 64);
      if (id == null ||
          title == null ||
          action == null ||
          !RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(id) ||
          !RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(action) ||
          !extension.manifest.hooks.contains('extension.action.$action')) {
        continue;
      }
      commands.add({
        'id': id,
        'title': title,
        'action': action,
        'icon': text(item['icon'], max: 40) ?? 'extension',
      });
    }
    final pages = <Map<String, Object?>>[];
    for (final item in canContributeUi ? entries('pages', 12) : const []) {
      final id = text(item['id'], max: 64);
      final title = text(item['title']);
      final blocks = item['blocks'];
      if (id == null ||
          title == null ||
          blocks is! List ||
          !RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(id))
        continue;
      final safeBlocks = <Map<String, Object?>>[];
      for (final block in blocks.take(80)) {
        if (block is! Map) continue;
        final type = text(block['type'], max: 20);
        if (type == 'text') {
          final value = text(block['text'], max: 2000);
          if (value != null) safeBlocks.add({'type': type, 'text': value});
        } else if (type == 'input' || type == 'toggle') {
          final id = text(block['id'], max: 64);
          final label = text(block['label']);
          if (id == null ||
              label == null ||
              !RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(id)) {
            continue;
          }
          if (type == 'input') {
            final value = block['value'];
            safeBlocks.add({
              'type': type,
              'id': id,
              'label': label,
              'value': value is String && value.length <= 500 ? value : '',
            });
          } else {
            safeBlocks.add({
              'type': type,
              'id': id,
              'label': label,
              'value': block['value'] == true,
            });
          }
        } else if (type == 'slider') {
          final id = text(block['id'], max: 64);
          final label = text(block['label']);
          final min = block['min'];
          final max = block['max'];
          final value = block['value'];
          if (id == null ||
              label == null ||
              !RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(id) ||
              min is! num ||
              max is! num ||
              value is! num ||
              !min.isFinite ||
              !max.isFinite ||
              !value.isFinite ||
              max <= min) {
            continue;
          }
          final lower = min.toDouble().clamp(-1000000, 1000000).toDouble();
          final upper = max.toDouble().clamp(lower, 1000000).toDouble();
          if (upper <= lower) continue;
          safeBlocks.add({
            'type': type,
            'id': id,
            'label': label,
            'min': lower,
            'max': upper,
            'value': value.toDouble().clamp(lower, upper).toDouble(),
          });
        } else if (type == 'button') {
          final label = text(block['label']);
          final action = text(block['action'], max: 64);
          if (label != null &&
              action != null &&
              RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(action) &&
              extension.manifest.hooks.contains('extension.action.$action')) {
            safeBlocks.add({'type': type, 'label': label, 'action': action});
          }
        } else if (type == 'divider') {
          safeBlocks.add({'type': type});
        }
      }
      pages.add({'id': id, 'title': title, 'blocks': safeBlocks});
    }
    final themes = <Map<String, Object?>>[];
    for (final item in canCustomizeTheme ? entries('themes', 16) : const []) {
      final id = text(item['id'], max: 64);
      final name = text(item['name']);
      final accent = _parseColor(item['accent']);
      final dark = _parseColor(item['darkBackground']);
      final light = _parseColor(item['lightBackground']);
      if (id == null ||
          name == null ||
          accent == null ||
          dark == null ||
          light == null ||
          !RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(id)) {
        continue;
      }
      themes.add({
        'id': id,
        'name': name,
        'accent': accent,
        'darkBackground': dark,
        'lightBackground': light,
      });
    }
    return {'commands': commands, 'pages': pages, 'themes': themes};
  }

  int? _parseColor(Object? value) {
    if (value is! String) return null;
    final hex = value.startsWith('#') ? value.substring(1) : value;
    if (!RegExp(r'^(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').hasMatch(hex)) {
      return null;
    }
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed == null) return null;
    return hex.length == 6 ? 0xFF000000 | parsed : parsed;
  }

  YureruExtensionPermission? _permissionForHook(String hook) {
    if (hook.startsWith('extension.action.')) {
      return YureruExtensionPermission.uiContribution;
    }
    if (hook.startsWith('player.')) {
      return YureruExtensionPermission.playerControl;
    }
    if (hook.startsWith('library.write') || hook.startsWith('media.write')) {
      return YureruExtensionPermission.libraryWrite;
    }
    if (hook.startsWith('library.') || hook.startsWith('media.')) {
      return YureruExtensionPermission.libraryRead;
    }
    return null;
  }
}

final extensionDispatcherProvider = Provider<YureruExtensionDispatcher>(
  (ref) =>
      YureruExtensionDispatcher(ref.read(extensionRegistryProvider.notifier)),
);

/// App-owned event dispatcher. Extensions can transform only the data shape
/// documented for an event; core state and filesystem paths stay host-owned.
class YureruExtensionDispatcher {
  YureruExtensionDispatcher(this.registry);

  final ExtensionRegistryNotifier registry;
  final YureruExtensionRuntime _runtime = YureruExtensionRuntime();

  Future<Map<String, Object?>> describe(YureruExtension extension) =>
      _runtime.describe(extension);

  Future<Object?> runAction(
    YureruExtension extension,
    String action,
    Map<String, Object?> context,
  ) async {
    final payload = Map<String, Object?>.of(context);
    final canStore = extension.grantedPermissions.contains(
      YureruExtensionPermission.extensionStorage,
    );
    if (canStore) payload['storage'] = await _readStorage(extension);
    final result = await _runtime.invoke(
      extension,
      'extension.action.$action',
      payload,
    );
    if (canStore && result is Map && result['storage'] is Map) {
      await _writeStorage(extension, result['storage'] as Map);
      return result['result'];
    }
    return result;
  }

  Future<Map<String, Object?>> _readStorage(YureruExtension extension) async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_storageKey(extension));
    if (raw == null || raw.length > 64 * 1024) return const {};
    try {
      final value = jsonDecode(raw);
      return value is Map ? Map<String, Object?>.from(value) : const {};
    } catch (_) {
      return const {};
    }
  }

  Future<void> _writeStorage(YureruExtension extension, Map value) async {
    final sanitized = <String, Object?>{};
    for (final entry in value.entries.take(128)) {
      if (entry.key is! String ||
          !RegExp(r'^[a-zA-Z0-9._-]{1,80}$').hasMatch(entry.key as String)) {
        continue;
      }
      sanitized[entry.key as String] = entry.value;
    }
    final encoded = jsonEncode(sanitized);
    if (encoded.length > 64 * 1024) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_storageKey(extension), encoded);
  }

  String _storageKey(YureruExtension extension) =>
      'yureru_extension_data_v1_${extension.manifest.id}';

  Future<List<MediaItem>> transformImportedItems(List<MediaItem> items) async {
    await registry.ready;
    List<Map<String, Object?>> metadata = [
      for (final item in items)
        {'title': item.title, 'artist': item.artist, 'album': item.album},
    ];
    for (final extension in registry.state) {
      try {
        final result = await _runtime.invoke(
          extension,
          'library.write.mediaImport',
          {'items': metadata},
        );
        if (result is! List || result.length != metadata.length) continue;
        metadata = [
          for (var index = 0; index < metadata.length; index++)
            _sanitizeMetadata(result[index], metadata[index]),
        ];
      } catch (_) {
        // A broken optional extension must not interrupt importing media.
      }
    }
    return [
      for (var index = 0; index < items.length; index++)
        items[index].copyWith(
          title: metadata[index]['title'] as String,
          artist: metadata[index]['artist'] as String?,
          album: metadata[index]['album'] as String?,
        ),
    ];
  }

  Map<String, Object?> _sanitizeMetadata(
    Object? result,
    Map<String, Object?> original,
  ) {
    if (result is! Map) return original;
    final sanitized = Map<String, Object?>.from(original);
    final title = result['title'];
    final artist = result['artist'];
    final album = result['album'];
    if (title is String && title.trim().isNotEmpty) {
      sanitized['title'] = _limit(title.trim());
    }
    if (artist is String) {
      sanitized['artist'] = artist.trim().isEmpty
          ? null
          : _limit(artist.trim());
    }
    if (album is String) {
      sanitized['album'] = album.trim().isEmpty ? null : _limit(album.trim());
    }
    return sanitized;
  }

  String _limit(String value) =>
      value.length <= 500 ? value : value.substring(0, 500);
}
