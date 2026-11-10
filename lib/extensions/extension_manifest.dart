import 'dart:convert';

const extensionApiVersion = 1;

enum YureruExtensionPermission {
  libraryRead('library.read'),
  libraryWrite('library.write'),
  playerControl('player.control'),
  uiContribution('ui.contribute'),
  themeCustomize('theme.customize'),
  extensionStorage('extension.storage');

  const YureruExtensionPermission(this.id);
  final String id;

  static YureruExtensionPermission? fromId(String id) {
    for (final permission in values) {
      if (permission.id == id) return permission;
    }
    return null;
  }
}

class YureruExtensionManifest {
  const YureruExtensionManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.entrypoint,
    required this.hooks,
    required this.permissions,
  });

  final String id;
  final String name;
  final String version;
  final String description;
  final String entrypoint;
  final List<String> hooks;
  final Set<YureruExtensionPermission> permissions;

  factory YureruExtensionManifest.fromJsonText(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Extension manifest must be a JSON object.');
    }
    final apiVersion = decoded['apiVersion'];
    if (apiVersion != extensionApiVersion) {
      throw FormatException('Unsupported extension API version: $apiVersion');
    }

    String requiredText(String key, {int maxLength = 120}) {
      final value = decoded[key];
      if (value is! String ||
          value.trim().isEmpty ||
          value.length > maxLength) {
        throw FormatException('Invalid extension manifest field: $key');
      }
      return value.trim();
    }

    final id = requiredText('id', maxLength: 64);
    if (!RegExp(r'^[a-z0-9][a-z0-9._-]{1,63}$').hasMatch(id)) {
      throw const FormatException(
        'Extension id must use lowercase letters, numbers, dots, underscores, or hyphens.',
      );
    }

    final entrypoint = decoded['entrypoint'] ?? 'main.js';
    if (entrypoint is! String ||
        entrypoint != 'main.js' ||
        entrypoint.contains('..') ||
        entrypoint.startsWith('/')) {
      throw const FormatException('The extension entrypoint must be main.js.');
    }

    final rawHooks = decoded['hooks'] ?? const <dynamic>[];
    if (rawHooks is! List || rawHooks.length > 32) {
      throw const FormatException('Invalid extension hooks.');
    }
    final hooks = <String>{};
    for (final value in rawHooks) {
      if (value is! String ||
          !RegExp(r'^[a-z][a-zA-Z0-9_.-]{1,79}$').hasMatch(value)) {
        throw const FormatException('Invalid extension hook name.');
      }
      hooks.add(value);
    }

    final rawPermissions = decoded['permissions'] ?? const <dynamic>[];
    if (rawPermissions is! List || rawPermissions.length > 24) {
      throw const FormatException('Invalid extension permissions.');
    }
    final permissions = <YureruExtensionPermission>{};
    for (final value in rawPermissions) {
      if (value is! String) {
        throw const FormatException('Invalid extension permission.');
      }
      final permission = YureruExtensionPermission.fromId(value);
      if (permission == null) {
        throw FormatException('Unknown extension permission: $value');
      }
      permissions.add(permission);
    }

    return YureruExtensionManifest(
      id: id,
      name: requiredText('name'),
      version: requiredText('version', maxLength: 40),
      description: requiredText('description', maxLength: 500),
      entrypoint: entrypoint,
      hooks: hooks.toList(growable: false),
      permissions: permissions,
    );
  }
}
