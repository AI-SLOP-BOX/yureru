import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models.dart';

class TrashEntry {
  const TrashEntry({
    required this.id,
    required this.type,
    required this.deletedAt,
    required this.data,
    this.playlistPositions = const {},
  });

  final String id;
  final String type;
  final DateTime deletedAt;
  final Map<String, dynamic> data;
  final Map<String, int> playlistPositions;

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type,
    'deletedAt': deletedAt.toIso8601String(),
    'data': data,
    'playlistPositions': playlistPositions,
  };

  factory TrashEntry.fromJson(Map<String, dynamic> json) => TrashEntry(
    id: json['id'] as String,
    type: json['type'] as String,
    deletedAt: DateTime.parse(json['deletedAt'] as String),
    data: Map<String, dynamic>.from(json['data'] as Map),
    playlistPositions: (json['playlistPositions'] as Map? ?? const {}).map(
      (key, value) => MapEntry(key.toString(), (value as num).toInt()),
    ),
  );
}

class TrashStore {
  static const _key = 'yureru.trash.v1';
  static const retention = Duration(days: 30);

  Future<List<TrashEntry>> load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final raw = prefs.getString(_key);
      if (raw == null) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final entries = <TrashEntry>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        try {
          entries.add(TrashEntry.fromJson(Map<String, dynamic>.from(item)));
        } catch (_) {}
      }
      return entries;
    } catch (_) {
      return [];
    }
  }

  Future<void> saveMedia(MediaItem media, Map<String, int> playlistPositions) =>
      _append(
        TrashEntry(
          id: 'media:${media.id}',
          type: 'media',
          deletedAt: DateTime.now(),
          data: media.toJson(),
          playlistPositions: playlistPositions,
        ),
      );

  Future<void> savePlaylist(Playlist playlist) => _append(
    TrashEntry(
      id: 'playlist:${playlist.id}',
      type: 'playlist',
      deletedAt: DateTime.now(),
      data: playlist.toJson(),
    ),
  );

  Future<void> remove(String id) async {
    final entries = await load();
    entries.removeWhere((entry) => entry.id == id);
    await _write(entries);
  }

  Future<void> purgeExpired(Set<String> activePaths) async {
    final entries = await load();
    final cutoff = DateTime.now().subtract(retention);
    final expired = entries.where((entry) => entry.deletedAt.isBefore(cutoff));
    // A path can be shared by multiple deleted records (for example, one
    // artwork file referenced by two tracks). Keep it until every restorable
    // trash entry that points to it has expired.
    final pathsKeptByTrash = <String>{};
    for (final entry in entries.where(
      (entry) => !entry.deletedAt.isBefore(cutoff),
    )) {
      pathsKeptByTrash.addAll(_filePaths(entry));
    }
    for (final entry in expired) {
      for (final path in _filePaths(entry)) {
        if (activePaths.contains(path) ||
            pathsKeptByTrash.contains(path) ||
            !_isManagedPath(path)) {
          continue;
        }
        try {
          final file = File(path);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
    }
    entries.removeWhere((entry) => entry.deletedAt.isBefore(cutoff));
    await _write(entries);
  }

  Set<String> _filePaths(TrashEntry entry) {
    final values = entry.type == 'media'
        ? [
            entry.data['localPath'],
            entry.data['artworkPath'],
            entry.data['thumbnailPath'],
            entry.data['lyricsPath'],
            entry.data['translatedLyricsPath'],
            entry.data['videoLyricsPath'],
            entry.data['artworkLyricsPath'],
            entry.data['artworkAudioPath'],
          ]
        : entry.type == 'playlist'
        ? [entry.data['artworkPath']]
        : const <Object?>[];
    return values.whereType<String>().where((path) => path.isNotEmpty).toSet();
  }

  Future<void> _append(TrashEntry entry) async {
    final entries = await load()
      ..removeWhere((old) => old.id == entry.id);
    entries.insert(0, entry);
    await _write(entries);
  }

  Future<void> _write(List<TrashEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(entries.map((entry) => entry.toJson()).toList()),
    );
  }

  bool _isManagedPath(String path) => RegExp(
    r'[\\/]yureru_(media|artwork|thumbnails|lyrics|audio_sources|playlist_artwork)[\\/]',
  ).hasMatch(path);
}
