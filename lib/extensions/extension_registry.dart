import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'extension_manifest.dart';

const _registryKey = 'yureru_extensions_v1';
const _maxPackageBytes = 20 * 1024 * 1024;
const _maxUnpackedBytes = 32 * 1024 * 1024;
const _maxPackageFiles = 80;

class YureruExtensionPackage {
  const YureruExtensionPackage({required this.manifest, required this.files});

  final YureruExtensionManifest manifest;
  final Map<String, List<int>> files;

  static YureruExtensionPackage decode(List<int> bytes) {
    if (bytes.isEmpty || bytes.length > _maxPackageBytes) {
      throw const FormatException('Extension package size is invalid.');
    }
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    if (archive.files.length > _maxPackageFiles) {
      throw const FormatException('Extension package has too many files.');
    }
    final files = <String, List<int>>{};
    var unpackedBytes = 0;
    for (final file in archive.files) {
      if (file.isSymbolicLink) {
        throw const FormatException(
          'Extension packages cannot contain symbolic links.',
        );
      }
      if (!file.isFile) continue;
      final name = file.name.replaceAll('\\', '/');
      final segments = name.split('/');
      if (name.startsWith('/') ||
          name.contains(':') ||
          segments.any((segment) => segment == '..' || segment.isEmpty)) {
        throw const FormatException(
          'Extension package contains an unsafe path.',
        );
      }
      if (name != 'manifest.json' &&
          name != 'main.js' &&
          !name.startsWith('assets/')) {
        throw FormatException('Unsupported file in extension package: $name');
      }
      if (files.containsKey(name)) {
        throw FormatException(
          'Extension package contains duplicate file: $name',
        );
      }
      if (file.size > _maxUnpackedBytes - unpackedBytes) {
        throw const FormatException(
          'Extension package expands beyond the size limit.',
        );
      }
      final content = file.readBytes();
      if (content == null) {
        throw FormatException('Could not read extension package file: $name');
      }
      if (content.length != file.size) {
        throw FormatException('Invalid uncompressed size for: $name');
      }
      unpackedBytes += content.length;
      if (unpackedBytes > _maxUnpackedBytes) {
        throw const FormatException(
          'Extension package expands beyond the size limit.',
        );
      }
      files[name] = content;
    }
    final manifestBytes = files['manifest.json'];
    if (manifestBytes == null) {
      throw const FormatException(
        'Extension package is missing manifest.json.',
      );
    }
    if (manifestBytes.length > 64 * 1024) {
      throw const FormatException('Extension manifest exceeds 64 KB.');
    }
    final entrypointBytes = files['main.js'];
    if (entrypointBytes == null) {
      throw const FormatException('Extension package is missing main.js.');
    }
    if (entrypointBytes.length > 2 * 1024 * 1024) {
      throw const FormatException('Extension JavaScript exceeds 2 MB.');
    }
    final manifest = YureruExtensionManifest.fromJsonText(
      utf8.decode(manifestBytes),
    );
    return YureruExtensionPackage(manifest: manifest, files: files);
  }
}

class YureruExtension {
  const YureruExtension({
    required this.manifest,
    required this.directoryPath,
    required this.enabled,
    required this.grantedPermissions,
  });

  final YureruExtensionManifest manifest;
  final String directoryPath;
  final bool enabled;
  final Set<YureruExtensionPermission> grantedPermissions;

  String get entrypointPath => '$directoryPath/${manifest.entrypoint}';

  Map<String, dynamic> toJson() => {
    'manifest': {
      'id': manifest.id,
      'name': manifest.name,
      'version': manifest.version,
      'description': manifest.description,
      'entrypoint': manifest.entrypoint,
      'hooks': manifest.hooks,
      'permissions': manifest.permissions
          .map((permission) => permission.id)
          .toList(),
      'apiVersion': extensionApiVersion,
    },
    'directoryPath': directoryPath,
    'enabled': enabled,
    'grantedPermissions': grantedPermissions
        .map((permission) => permission.id)
        .toList(),
  };

  factory YureruExtension.fromJson(Map<String, dynamic> json) {
    final rawManifest = json['manifest'];
    if (rawManifest is! Map<String, dynamic>) {
      throw const FormatException('Invalid saved extension record.');
    }
    final manifest = YureruExtensionManifest.fromJsonText(
      jsonEncode(rawManifest),
    );
    final rawGrants = json['grantedPermissions'];
    final grants = <YureruExtensionPermission>{};
    if (rawGrants is List) {
      for (final value in rawGrants.whereType<String>()) {
        final permission = YureruExtensionPermission.fromId(value);
        if (permission != null && manifest.permissions.contains(permission)) {
          grants.add(permission);
        }
      }
    }
    return YureruExtension(
      manifest: manifest,
      directoryPath: json['directoryPath'] as String,
      enabled: json['enabled'] as bool? ?? false,
      grantedPermissions: grants,
    );
  }

  YureruExtension copyWith({
    bool? enabled,
    Set<YureruExtensionPermission>? grantedPermissions,
  }) => YureruExtension(
    manifest: manifest,
    directoryPath: directoryPath,
    enabled: enabled ?? this.enabled,
    grantedPermissions: grantedPermissions ?? this.grantedPermissions,
  );

  YureruExtension copyWithDirectory(String path) => YureruExtension(
    manifest: manifest,
    directoryPath: path,
    enabled: enabled,
    grantedPermissions: grantedPermissions,
  );
}

final extensionRegistryProvider =
    StateNotifierProvider<ExtensionRegistryNotifier, List<YureruExtension>>(
      (ref) => ExtensionRegistryNotifier(),
    );

class ExtensionRegistryNotifier extends StateNotifier<List<YureruExtension>> {
  ExtensionRegistryNotifier() : super(const []) {
    _ready = _load();
  }

  late final Future<void> _ready;
  Future<void> get ready => _ready;

  Future<void> _load() async {
    final preferences = await SharedPreferences.getInstance();
    final support = await getApplicationSupportDirectory();
    final extensionsRoot = Directory('${support.path}/yureru_extensions');
    final raw = preferences.getStringList(_registryKey) ?? const [];
    final loaded = <YureruExtension>[];
    for (final entry in raw) {
      try {
        final extension = YureruExtension.fromJson(
          jsonDecode(entry) as Map<String, dynamic>,
        );
        final expectedPath = '${extensionsRoot.path}/${extension.manifest.id}';
        // Reconstruct this path from our own support directory. Never trust a
        // persisted path when a later remove operation recursively deletes it.
        final safeExtension = extension.copyWithDirectory(expectedPath);
        if (await FileSystemEntity.isDirectory(expectedPath) &&
            await File(safeExtension.entrypointPath).exists()) {
          loaded.add(safeExtension);
        }
      } catch (_) {}
    }
    state = loaded;
  }

  Future<void> install(
    YureruExtensionPackage package, {
    required Set<YureruExtensionPermission> grantedPermissions,
  }) async {
    await _ready;
    if (state.any(
      (extension) => extension.manifest.id == package.manifest.id,
    )) {
      throw StateError('An extension with this id is already installed.');
    }
    if (!package.manifest.permissions.containsAll(grantedPermissions)) {
      throw ArgumentError(
        'Granted permissions must be requested by the extension.',
      );
    }
    final support = await getApplicationSupportDirectory();
    final extensionsRoot = Directory('${support.path}/yureru_extensions');
    await extensionsRoot.create(recursive: true);
    final target = Directory('${extensionsRoot.path}/${package.manifest.id}');
    if (await target.exists()) {
      throw StateError('An extension directory with this id already exists.');
    }
    final staging = Directory(
      '${extensionsRoot.path}/.${package.manifest.id}_${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await staging.create(recursive: true);
      for (final entry in package.files.entries) {
        final destination = File('${staging.path}/${entry.key}');
        await destination.parent.create(recursive: true);
        await destination.writeAsBytes(entry.value, flush: true);
      }
      await staging.rename(target.path);
      final extension = YureruExtension(
        manifest: package.manifest,
        directoryPath: target.path,
        enabled: true,
        grantedPermissions: grantedPermissions,
      );
      state = [...state, extension];
      await _save();
    } catch (_) {
      if (await staging.exists()) await staging.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> setEnabled(String id, bool enabled) async {
    await _ready;
    state = [
      for (final extension in state)
        if (extension.manifest.id == id)
          extension.copyWith(enabled: enabled)
        else
          extension,
    ];
    await _save();
  }

  Future<void> setPermissions(
    String id,
    Set<YureruExtensionPermission> granted,
  ) async {
    await _ready;
    state = [
      for (final extension in state)
        if (extension.manifest.id == id)
          extension.copyWith(grantedPermissions: granted)
        else
          extension,
    ];
    await _save();
  }

  Future<void> remove(String id) async {
    await _ready;
    final target = state.where((extension) => extension.manifest.id == id);
    for (final extension in target) {
      final directory = Directory(extension.directoryPath);
      if (await directory.exists()) await directory.delete(recursive: true);
    }
    state = state.where((extension) => extension.manifest.id != id).toList();
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove('yureru_extension_data_v1_$id');
    await _save();
  }

  Future<void> _save() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      _registryKey,
      state.map((extension) => jsonEncode(extension.toJson())).toList(),
    );
  }
}
