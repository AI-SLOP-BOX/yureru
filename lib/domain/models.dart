import 'dart:math' as math;
import 'package:uuid/uuid.dart';

const _uuid = Uuid();
const _unchanged = Object();

enum PlaybackRankingPeriod { threeDays, week, month, olderPopular, allTime }

enum MediaViewAvailability { both, mediaOnly, artworkOnly }

/// A single media item in the library. Identity = [id], never path.
class MediaItem {
  final String id;
  bool get isTemporary => origin == 'temporary';
  final String title;
  final bool isFavorite;
  final DateTime? lastPlayedAt;
  final int playCount;

  /// Calendar-day play counts (YYYY-MM-DD), retained for period rankings.
  final Map<String, int> playCountsByDay;
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

  /// Which visual surfaces this item may use in the player.
  final MediaViewAvailability viewAvailability;

  /// User-selected thumbnail, stored separately from jacket artwork.
  final String? thumbnailPath;

  /// Image for integrations without a screen context, such as the OS media
  /// session. Preserve jacket-first where no screen preference is available.
  String? get preferredImagePath => artworkPath ?? thumbnailPath;

  /// User-selected lyrics file (.lrc or plain text), if available.
  final String? lyricsPath;

  /// Optional translated lyrics. Its lines are displayed against the source
  /// lyric timestamps, so translation does not need duplicate timing data.
  final String? translatedLyricsPath;

  /// Hides the in-player lyric edit control after the user finalizes the text.
  final bool lyricsEditingFinalized;

  /// Signed correction for synchronized lyrics. Positive values delay lines.
  final int lyricsOffsetMs;

  /// When enabled, the player chooses a separate lyric file for video and
  /// jacket display modes, falling back to the shared lyrics when absent.
  final bool separateLyricsByView;
  final String? videoLyricsPath;
  final int videoLyricsOffsetMs;
  final String? artworkLyricsPath;
  final int artworkLyricsOffsetMs;

  /// When true, jacket lyrics follow the video timing correction and account
  /// for the jacket audio's position offset on the shared playback timeline.
  final bool artworkLyricsOffsetFollowsVideo;

  /// Optional library media whose audio is used in jacket mode.
  final String? artworkAudioMediaId;

  /// Optional copied audio file used in jacket mode.
  final String? artworkAudioPath;

  /// Jacket audio trim point relative to the video timeline.
  /// A positive value trims that much from the audio head and makes the
  /// remaining source time zero align with that position in the MV.
  final int artworkAudioOffsetMs;

  /// Absolute source timestamp where jacket audio playback stops; zero means
  /// play through the source end.
  final int artworkAudioEndMs;

  /// User explicitly marked the current item as having no lyrics, hiding the
  /// player lyrics entry until lyrics are added again.
  final bool lyricsButtonHidden;

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
    this.playCount = 0,
    this.playCountsByDay = const {},
    required this.localPath,
    this.durationMs,
    DateTime? createdAt,
    this.origin = 'imported',
    this.sourceFolderId,
    this.sourcePath,
    this.artworkPath,
    this.viewAvailability = MediaViewAvailability.both,
    this.thumbnailPath,
    this.lyricsPath,
    this.translatedLyricsPath,
    this.lyricsEditingFinalized = false,
    this.lyricsOffsetMs = 0,
    this.separateLyricsByView = false,
    this.videoLyricsPath,
    this.videoLyricsOffsetMs = 0,
    this.artworkLyricsPath,
    this.artworkLyricsOffsetMs = 0,
    this.artworkLyricsOffsetFollowsVideo = true,
    this.artworkAudioMediaId,
    this.artworkAudioPath,
    this.artworkAudioOffsetMs = 0,
    this.artworkAudioEndMs = 0,
    this.lyricsButtonHidden = false,
  }) : id = id ?? _uuid.v4(),
       createdAt = createdAt ?? DateTime.now();

  String? lyricsPathForView({required bool artwork}) {
    if (!separateLyricsByView) return lyricsPath;
    return (artwork ? artworkLyricsPath : videoLyricsPath) ?? lyricsPath;
  }

  int playCountFor(PlaybackRankingPeriod period, {DateTime? now}) {
    if (period == PlaybackRankingPeriod.allTime) return playCount;
    final today = now ?? DateTime.now();
    final end = DateTime(today.year, today.month, today.day);
    final range = switch (period) {
      PlaybackRankingPeriod.threeDays => (2, -1),
      PlaybackRankingPeriod.week => (6, -1),
      PlaybackRankingPeriod.month => (29, -1),
      // Older popularity: the 90-day window before the most recent 90 days.
      PlaybackRankingPeriod.olderPopular => (180, 90),
      PlaybackRankingPeriod.allTime => (0, 0),
    };
    final from = end.subtract(Duration(days: range.$1));
    final until = end.subtract(Duration(days: range.$2));
    return playCountBetween(from, until);
  }

  int playCountBetween(DateTime start, DateTime end) {
    var day = DateTime(start.year, start.month, start.day);
    final until = DateTime(end.year, end.month, end.day);
    var total = 0;
    while (day.isBefore(until)) {
      final key =
          '${day.year.toString().padLeft(4, '0')}-'
          '${day.month.toString().padLeft(2, '0')}-'
          '${day.day.toString().padLeft(2, '0')}';
      total += playCountsByDay[key] ?? 0;
      day = day.add(const Duration(days: 1));
    }
    return total;
  }

  /// Internal recommendation signal: emphasize recent listening while keeping
  /// a smaller contribution from evergreen and previously popular media.
  double get recommendationScore =>
      playCountFor(PlaybackRankingPeriod.threeDays) * 4.0 +
      playCountFor(PlaybackRankingPeriod.week) * 2.0 +
      playCountFor(PlaybackRankingPeriod.month) +
      playCountFor(PlaybackRankingPeriod.olderPopular) * 0.35 +
      playCount * 0.05;

  int lyricsOffsetForView({required bool artwork}) {
    final videoOffset = separateLyricsByView
        ? videoLyricsOffsetMs
        : lyricsOffsetMs;
    if (!artwork) return videoOffset;
    if (artworkLyricsOffsetFollowsVideo) {
      // Artwork audio is trimmed at its head, so timeline 0 in artwork mode
      // corresponds to this many milliseconds into the shared video/LRC time.
      return videoOffset - artworkAudioOffsetMs;
    }
    return artworkLyricsOffsetMs;
  }

  /// Updates selected fields while preserving identity and creation time.
  /// Omit nullable fields to preserve them; pass null to clear them.
  MediaItem copyWith({
    String? title,
    bool? isFavorite,
    Object? lastPlayedAt = _unchanged,
    int? playCount,
    Map<String, int>? playCountsByDay,
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
    MediaViewAvailability? viewAvailability,
    Object? thumbnailPath = _unchanged,
    Object? lyricsPath = _unchanged,
    Object? translatedLyricsPath = _unchanged,
    bool? lyricsEditingFinalized,
    int? lyricsOffsetMs,
    bool? separateLyricsByView,
    Object? videoLyricsPath = _unchanged,
    int? videoLyricsOffsetMs,
    Object? artworkLyricsPath = _unchanged,
    int? artworkLyricsOffsetMs,
    bool? artworkLyricsOffsetFollowsVideo,
    Object? artworkAudioMediaId = _unchanged,
    Object? artworkAudioPath = _unchanged,
    int? artworkAudioOffsetMs,
    int? artworkAudioEndMs,
    bool? lyricsButtonHidden,
  }) => MediaItem(
    id: id,
    title: title ?? this.title,
    isFavorite: isFavorite ?? this.isFavorite,
    lastPlayedAt: identical(lastPlayedAt, _unchanged)
        ? this.lastPlayedAt
        : lastPlayedAt as DateTime?,
    playCount: playCount ?? this.playCount,
    playCountsByDay: playCountsByDay ?? this.playCountsByDay,
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
    viewAvailability: viewAvailability ?? this.viewAvailability,
    thumbnailPath: identical(thumbnailPath, _unchanged)
        ? this.thumbnailPath
        : thumbnailPath as String?,
    lyricsPath: identical(lyricsPath, _unchanged)
        ? this.lyricsPath
        : lyricsPath as String?,
    translatedLyricsPath: identical(translatedLyricsPath, _unchanged)
        ? this.translatedLyricsPath
        : translatedLyricsPath as String?,
    lyricsEditingFinalized:
        lyricsEditingFinalized ?? this.lyricsEditingFinalized,
    lyricsOffsetMs: lyricsOffsetMs ?? this.lyricsOffsetMs,
    separateLyricsByView: separateLyricsByView ?? this.separateLyricsByView,
    videoLyricsPath: identical(videoLyricsPath, _unchanged)
        ? this.videoLyricsPath
        : videoLyricsPath as String?,
    videoLyricsOffsetMs: videoLyricsOffsetMs ?? this.videoLyricsOffsetMs,
    artworkLyricsPath: identical(artworkLyricsPath, _unchanged)
        ? this.artworkLyricsPath
        : artworkLyricsPath as String?,
    artworkLyricsOffsetMs: artworkLyricsOffsetMs ?? this.artworkLyricsOffsetMs,
    artworkLyricsOffsetFollowsVideo:
        artworkLyricsOffsetFollowsVideo ?? this.artworkLyricsOffsetFollowsVideo,
    artworkAudioMediaId: identical(artworkAudioMediaId, _unchanged)
        ? this.artworkAudioMediaId
        : artworkAudioMediaId as String?,
    artworkAudioPath: identical(artworkAudioPath, _unchanged)
        ? this.artworkAudioPath
        : artworkAudioPath as String?,
    artworkAudioOffsetMs: artworkAudioOffsetMs ?? this.artworkAudioOffsetMs,
    artworkAudioEndMs: artworkAudioEndMs ?? this.artworkAudioEndMs,
    lyricsButtonHidden: lyricsButtonHidden ?? this.lyricsButtonHidden,
  );

  factory MediaItem.fromJson(Map<String, dynamic> j) => MediaItem(
    id: j['id'] as String?,
    isFavorite: (j['isFavorite'] as bool?) ?? false,
    lastPlayedAt: j['lastPlayedAt'] is String
        ? DateTime.tryParse(j['lastPlayedAt'] as String)
        : null,
    playCount: (j['playCount'] as num?)?.toInt() ?? 0,
    playCountsByDay:
        (j['playCountsByDay'] as Map?)?.map(
          (key, value) => MapEntry(key.toString(), (value as num).toInt()),
        ) ??
        const {},
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
    viewAvailability: MediaViewAvailability.values.firstWhere(
      (value) => value.name == j['viewAvailability'],
      orElse: () => MediaViewAvailability.both,
    ),
    thumbnailPath: j['thumbnailPath'] as String?,
    lyricsPath: j['lyricsPath'] as String?,
    translatedLyricsPath: j['translatedLyricsPath'] as String?,
    lyricsEditingFinalized: j['lyricsEditingFinalized'] as bool? ?? false,
    lyricsOffsetMs: (j['lyricsOffsetMs'] as num?)?.toInt() ?? 0,
    separateLyricsByView: j['separateLyricsByView'] as bool? ?? false,
    videoLyricsPath: j['videoLyricsPath'] as String?,
    videoLyricsOffsetMs:
        (j['videoLyricsOffsetMs'] as num?)?.toInt() ??
        ((j['separateLyricsByView'] as bool? ?? false)
            ? (j['lyricsOffsetMs'] as num?)?.toInt() ?? 0
            : 0),
    artworkLyricsPath: j['artworkLyricsPath'] as String?,
    artworkLyricsOffsetMs:
        (j['artworkLyricsOffsetMs'] as num?)?.toInt() ??
        ((j['separateLyricsByView'] as bool? ?? false)
            ? (j['lyricsOffsetMs'] as num?)?.toInt() ?? 0
            : 0),
    artworkLyricsOffsetFollowsVideo:
        j['artworkLyricsOffsetFollowsVideo'] as bool? ?? true,
    artworkAudioMediaId: j['artworkAudioMediaId'] as String?,
    artworkAudioPath: j['artworkAudioPath'] as String?,
    artworkAudioOffsetMs: (j['artworkAudioOffsetMs'] as num?)?.toInt() ?? 0,
    artworkAudioEndMs: (j['artworkAudioEndMs'] as num?)?.toInt() ?? 0,
    lyricsButtonHidden: j['lyricsButtonHidden'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'isFavorite': isFavorite,
    'lastPlayedAt': lastPlayedAt?.toIso8601String(),
    'playCount': playCount,
    'playCountsByDay': playCountsByDay,
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
    'viewAvailability': viewAvailability.name,
    'thumbnailPath': thumbnailPath,
    'lyricsPath': lyricsPath,
    'translatedLyricsPath': translatedLyricsPath,
    'lyricsEditingFinalized': lyricsEditingFinalized,
    'lyricsOffsetMs': lyricsOffsetMs,
    'separateLyricsByView': separateLyricsByView,
    'videoLyricsPath': videoLyricsPath,
    'videoLyricsOffsetMs': videoLyricsOffsetMs,
    'artworkLyricsPath': artworkLyricsPath,
    'artworkLyricsOffsetMs': artworkLyricsOffsetMs,
    'artworkLyricsOffsetFollowsVideo': artworkLyricsOffsetFollowsVideo,
    'artworkAudioMediaId': artworkAudioMediaId,
    'artworkAudioPath': artworkAudioPath,
    'artworkAudioOffsetMs': artworkAudioOffsetMs,
    'artworkAudioEndMs': artworkAudioEndMs,
    'lyricsButtonHidden': lyricsButtonHidden,
  };
}

/// Playlist = ordered list of Media IDs, independent of folders.
class Playlist {
  final String id;
  final String name;
  final List<String> mediaIds;
  final DateTime createdAt;

  /// Optional per-playlist image choice; null follows the playlist default.
  final String? imagePriority;
  final String? artworkPath;

  /// Optional automatic rule. When set, [mediaIds] is maintained from the
  /// current library instead of manual edits.
  final String? smartRule;
  bool get isSmart => smartRule != null;

  Playlist({
    String? id,
    required this.name,
    List<String>? mediaIds,
    DateTime? createdAt,
    this.imagePriority,
    this.artworkPath,
    this.smartRule,
  }) : id = id ?? _uuid.v4(),
       mediaIds = List.unmodifiable(mediaIds ?? const []),
       createdAt = createdAt ?? DateTime.now();

  Playlist copyWith({
    String? name,
    List<String>? mediaIds,
    Object? imagePriority = _unchanged,
    Object? artworkPath = _unchanged,
    Object? smartRule = _unchanged,
  }) => Playlist(
    id: id,
    name: name ?? this.name,
    mediaIds: mediaIds ?? this.mediaIds,
    createdAt: createdAt,
    imagePriority: identical(imagePriority, _unchanged)
        ? this.imagePriority
        : imagePriority as String?,
    artworkPath: identical(artworkPath, _unchanged)
        ? this.artworkPath
        : artworkPath as String?,
    smartRule: identical(smartRule, _unchanged)
        ? this.smartRule
        : smartRule as String?,
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
      imagePriority: j['imagePriority'] as String?,
      artworkPath: j['artworkPath'] as String?,
      smartRule: j['smartRule'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'mediaIds': mediaIds,
    'createdAt': createdAt.toIso8601String(),
    'imagePriority': imagePriority,
    'artworkPath': artworkPath,
    'smartRule': smartRule,
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
