import 'dart:math' as math;
import 'package:uuid/uuid.dart';

const _uuid = Uuid();
const _unchanged = Object();

/// A single media item in the library. Identity = [id], never path.
class MediaItem {
  final String id;
  bool get isTemporary => origin == 'temporary';
  final String title;
  final bool isFavorite;
  final DateTime? lastPlayedAt;
  final String? artist;
  final String? album;
  final String? albumArtist;
  final int? trackNumber;
  final int? discNumber;
  final String localPath;
  final int? durationMs;
  final DateTime createdAt;
  final String origin;
  final String? sourceFolderId;

  /// Original path the item was imported from (null for pre-existing library
  /// entries). Used to avoid re-importing the same file when a folder is
  /// re-selected.
  final String? sourcePath;

  /// User-selected artwork, stored in the app's support directory.
  final String? artworkPath;

  /// User-selected thumbnail, stored separately from jacket artwork.
  final String? thumbnailPath;

  /// Jackets take precedence, then custom thumbnails, then extracted frames.
  String? get preferredImagePath => artworkPath ?? thumbnailPath;

  /// User-selected lyrics file (.lrc or plain text), if available.
  final String? lyricsPath;

  /// Signed correction for synchronized lyrics. Positive values delay lines.
  final int lyricsOffsetMs;

  MediaItem({
    String? id,
    required this.title,
    this.artist,
    this.album,
    this.albumArtist,
    this.trackNumber,
    this.discNumber,
    this.isFavorite = false,
    this.lastPlayedAt,
    required this.localPath,
    this.durationMs,
    DateTime? createdAt,
    this.origin = 'imported',
    this.sourceFolderId,
    this.sourcePath,
    this.artworkPath,
    this.thumbnailPath,
    this.lyricsPath,
    this.lyricsOffsetMs = 0,
  }) : id = id ?? _uuid.v4(),
       createdAt = createdAt ?? DateTime.now();

  /// Updates selected fields while preserving identity and creation time.
  /// Omit nullable fields to preserve them; pass null to clear them.
  MediaItem copyWith({
    String? title,
    bool? isFavorite,
    Object? lastPlayedAt = _unchanged,
    Object? artist = _unchanged,
    Object? album = _unchanged,
    Object? albumArtist = _unchanged,
    Object? trackNumber = _unchanged,
    Object? discNumber = _unchanged,
    String? localPath,
    Object? durationMs = _unchanged,
    String? origin,
    Object? sourceFolderId = _unchanged,
    Object? sourcePath = _unchanged,
    Object? artworkPath = _unchanged,
    Object? thumbnailPath = _unchanged,
    Object? lyricsPath = _unchanged,
    int? lyricsOffsetMs,
  }) => MediaItem(
    id: id,
    title: title ?? this.title,
    isFavorite: isFavorite ?? this.isFavorite,
    lastPlayedAt: identical(lastPlayedAt, _unchanged)
        ? this.lastPlayedAt
        : lastPlayedAt as DateTime?,
    artist: identical(artist, _unchanged) ? this.artist : artist as String?,
    album: identical(album, _unchanged) ? this.album : album as String?,
    albumArtist: identical(albumArtist, _unchanged)
        ? this.albumArtist
        : albumArtist as String?,
    trackNumber: identical(trackNumber, _unchanged)
        ? this.trackNumber
        : trackNumber as int?,
    discNumber: identical(discNumber, _unchanged)
        ? this.discNumber
        : discNumber as int?,
    localPath: localPath ?? this.localPath,
    durationMs: identical(durationMs, _unchanged)
        ? this.durationMs
        : durationMs as int?,
    createdAt: createdAt,
    origin: origin ?? this.origin,
    sourceFolderId: identical(sourceFolderId, _unchanged)
        ? this.sourceFolderId
        : sourceFolderId as String?,
    sourcePath: identical(sourcePath, _unchanged)
        ? this.sourcePath
        : sourcePath as String?,
    artworkPath: identical(artworkPath, _unchanged)
        ? this.artworkPath
        : artworkPath as String?,
    thumbnailPath: identical(thumbnailPath, _unchanged)
        ? this.thumbnailPath
        : thumbnailPath as String?,
    lyricsPath: identical(lyricsPath, _unchanged)
        ? this.lyricsPath
        : lyricsPath as String?,
    lyricsOffsetMs: lyricsOffsetMs ?? this.lyricsOffsetMs,
  );

  factory MediaItem.fromJson(Map<String, dynamic> j) => MediaItem(
    id: j['id'] as String?,
    isFavorite: (j['isFavorite'] as bool?) ?? false,
    lastPlayedAt: j['lastPlayedAt'] is String
        ? DateTime.tryParse(j['lastPlayedAt'] as String)
        : null,
    title: (j['title'] as String?) ?? '(不明)',
    artist: j['artist'] as String?,
    album: j['album'] as String?,
    albumArtist: j['albumArtist'] as String?,
    trackNumber: (j['trackNumber'] as num?)?.toInt(),
    discNumber: (j['discNumber'] as num?)?.toInt(),
    localPath: (j['localPath'] as String?) ?? '',
    durationMs: (j['durationMs'] as num?)?.toInt(),
    createdAt: j['createdAt'] is String
        ? (DateTime.tryParse(j['createdAt'] as String) ?? DateTime.now())
        : DateTime.now(),
    origin: (j['origin'] as String?) ?? 'imported',
    sourceFolderId: j['sourceFolderId'] as String?,
    sourcePath: j['sourcePath'] as String?,
    artworkPath: j['artworkPath'] as String?,
    thumbnailPath: j['thumbnailPath'] as String?,
    lyricsPath: j['lyricsPath'] as String?,
    lyricsOffsetMs: (j['lyricsOffsetMs'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'isFavorite': isFavorite,
    'lastPlayedAt': lastPlayedAt?.toIso8601String(),
    'artist': artist,
    'album': album,
    'albumArtist': albumArtist,
    'trackNumber': trackNumber,
    'discNumber': discNumber,
    'localPath': localPath,
    'durationMs': durationMs,
    'createdAt': createdAt.toIso8601String(),
    'origin': origin,
    'sourceFolderId': sourceFolderId,
    'sourcePath': sourcePath,
    'artworkPath': artworkPath,
    'thumbnailPath': thumbnailPath,
    'lyricsPath': lyricsPath,
    'lyricsOffsetMs': lyricsOffsetMs,
  };
}

/// Playlist = ordered list of Media IDs, independent of folders.
class Playlist {
  final String id;
  final String name;
  final List<String> mediaIds;
  final DateTime createdAt;

  Playlist({
    String? id,
    required this.name,
    List<String>? mediaIds,
    DateTime? createdAt,
  }) : id = id ?? _uuid.v4(),
       mediaIds = List.unmodifiable(mediaIds ?? const []),
       createdAt = createdAt ?? DateTime.now();

  Playlist copyWith({String? name, List<String>? mediaIds}) => Playlist(
    id: id,
    name: name ?? this.name,
    mediaIds: mediaIds ?? this.mediaIds,
    createdAt: createdAt,
  );

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
  static List<String> build(
    List<String> mediaIds, {
    required bool shuffle,
    int? seed,
  }) {
    final list = List<String>.of(mediaIds);
    if (shuffle) {
      list.shuffle(seed == null ? null : math.Random(seed));
    }
    return list;
  }
}
