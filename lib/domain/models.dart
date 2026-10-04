import 'dart:math' as math;
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// A single video in the library. Identity = [id] (Media ID), never path.
class MediaItem {
  final String id;
  final String title;
  final String? artist;
  final String localPath;
  final int? durationMs;
  final DateTime createdAt;
  final String origin;
  final String? sourceFolderId;

  /// Original path the item was imported from (null for pre-existing library
  /// entries). Used to avoid re-importing the same file when a folder is
  /// re-selected.
  final String? sourcePath;

  MediaItem({
    String? id,
    required this.title,
    this.artist,
    required this.localPath,
    this.durationMs,
    DateTime? createdAt,
    this.origin = 'imported',
    this.sourceFolderId,
    this.sourcePath,
  })  : id = id ?? _uuid.v4(),
        createdAt = createdAt ?? DateTime.now();

  factory MediaItem.fromJson(Map<String, dynamic> j) => MediaItem(
        id: j['id'] as String?,
        title: (j['title'] as String?) ?? '(不明)',
        artist: j['artist'] as String?,
        localPath: (j['localPath'] as String?) ?? '',
        durationMs: (j['durationMs'] as num?)?.toInt(),
        createdAt: j['createdAt'] is String
            ? (DateTime.tryParse(j['createdAt'] as String) ?? DateTime.now())
            : DateTime.now(),
        origin: (j['origin'] as String?) ?? 'imported',
        sourceFolderId: j['sourceFolderId'] as String?,
        sourcePath: j['sourcePath'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'localPath': localPath,
        'durationMs': durationMs,
        'createdAt': createdAt.toIso8601String(),
        'origin': origin,
        'sourceFolderId': sourceFolderId,
        'sourcePath': sourcePath,
      };
}

/// Playlist = ordered list of Media IDs, independent of folders.
class Playlist {
  final String id;
  final String name;
  final List<String> mediaIds;
  final DateTime createdAt;

  Playlist({String? id, required this.name, List<String>? mediaIds, DateTime? createdAt})
      : id = id ?? _uuid.v4(),
        mediaIds = List.unmodifiable(mediaIds ?? const []),
        createdAt = createdAt ?? DateTime.now();

  factory Playlist.fromJson(Map<String, dynamic> j) {
    final rawIds = j['mediaIds'];
    final ids = rawIds is List
        ? rawIds.whereType<String>().toList()
        : <String>[];
    return Playlist(
      id: j['id'] as String?,
      name: (j['name'] as String?) ?? '(名称未設定)',
      mediaIds: ids,
      createdAt: j['createdAt'] is String
          ? (DateTime.tryParse(j['createdAt'] as String) ?? DateTime.now())
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'mediaIds': mediaIds,
        'createdAt': createdAt.toIso8601String(),
      };
}

/// Queue building: ordered copy, or shuffled permutation (each item once).
class QueueBuilder {
  static List<String> build(List<String> mediaIds, {required bool shuffle, int? seed}) {
    final list = List<String>.of(mediaIds);
    if (shuffle) {
      list.shuffle(seed == null ? null : math.Random(seed));
    }
    return list;
  }
}
