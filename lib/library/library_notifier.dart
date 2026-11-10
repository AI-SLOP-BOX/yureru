import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../data/store.dart';
import '../data/trash_store.dart';
import '../domain/models.dart';
import 'media_metadata_patch.dart';

class LibraryState {
  final List<MediaItem> media;
  final List<Playlist> playlists;
  final bool loaded;
  const LibraryState({
    this.media = const [],
    this.playlists = const [],
    this.loaded = false,
  });
  List<MediaItem> get savedMedia => media.where((m) => !m.isTemporary).toList();
  MediaItem? byId(String id) {
    for (final m in media) {
      if (m.id == id) return m;
    }
    return null;
  }

  Playlist? playlistById(String id) {
    for (final p in playlists) {
      if (p.id == id) return p;
    }
    return null;
  }
}

class LibraryNotifier extends StateNotifier<LibraryState> {
  final LibraryRepository repo;
  final Future<List<MediaItem>> Function(List<MediaItem>)? transformImports;
  LibraryNotifier(this.repo, {this.transformImports})
    : super(const LibraryState());
  Future<void> load() async {
    final m = await repo.loadMedia();
    final savedPlaylists = await repo.loadPlaylists();
    final p = _refreshSmartPlaylists(savedPlaylists, m);
    state = LibraryState(media: m, playlists: p, loaded: true);
    if (_playlistContentsChanged(savedPlaylists, p)) {
      await repo.savePlaylists(p);
    }
    try {
      await TrashStore().purgeExpired({
        for (final item in m)
          for (final path in [
            item.localPath,
            item.artworkPath,
            item.thumbnailPath,
            item.lyricsPath,
            item.translatedLyricsPath,
            item.videoLyricsPath,
            item.artworkLyricsPath,
            item.artworkAudioPath,
          ])
            ?path,
        for (final playlist in p) ?playlist.artworkPath,
      });
    } catch (_) {
      // Trash cleanup is maintenance only; it must never block library load.
    }
  }

  Future<void> addMedia(List<MediaItem> items) async {
    // Skip files already imported from the same source (folder re-selection).
    final existing = state.media
        .where((m) => !m.isTemporary)
        .map((m) => m.sourcePath)
        .whereType<String>()
        .toSet();
    final existingIds = state.media.map((m) => m.id).toSet();
    final fresh = [
      for (final m in items)
        if (!existingIds.contains(m.id) &&
            (m.sourcePath == null || !existing.contains(m.sourcePath)))
          m,
    ];
    if (fresh.isEmpty) return;
    final transformed = transformImports == null
        ? fresh
        : await transformImports!(fresh);
    final m = [...state.media, ...transformed];
    await _setMedia(m);
  }

  /// Repoints a missing library entry while preserving its metadata and IDs.
  /// Imported files are copied back into Yureru-managed storage; referenced
  /// items keep using the selected path directly.
  Future<void> relinkMediaFile(String id, String replacementPath) async {
    final current = state.byId(id);
    if (current == null || current.isTemporary) return;
    var localPath = replacementPath;
    var origin = current.origin;
    if (current.origin == 'imported') {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/yureru_media');
      await dir.create(recursive: true);
      final name = replacementPath.split(RegExp(r'[/\\]')).last;
      localPath = '${dir.path}/${DateTime.now().microsecondsSinceEpoch}_$name';
      await File(replacementPath).copy(localPath);
      origin = 'imported';
    } else {
      origin = 'referenced';
    }
    await _updateMedia(
      id,
      (item) => item.copyWith(
        localPath: localPath,
        sourcePath: replacementPath,
        origin: origin,
      ),
    );
  }

  /// Merges a restored backup by stable media/playlist IDs, updating matching
  /// entries and retaining items that are already present in the library.
  Future<void> mergeBackup({
    required List<MediaItem> media,
    required List<Playlist> playlists,
  }) async {
    final mediaById = {for (final item in state.media) item.id: item};
    for (final item in media) {
      mediaById[item.id] = item;
    }
    final playlistById = {for (final item in state.playlists) item.id: item};
    for (final item in playlists) {
      playlistById[item.id] = item;
    }
    await _setMedia(mediaById.values.toList());
    final mergedPlaylists = _refreshSmartPlaylists(
      playlistById.values.toList(),
      state.media,
    );
    state = LibraryState(
      media: state.media,
      playlists: mergedPlaylists,
      loaded: true,
    );
    await repo.savePlaylists(state.playlists);
  }

  /// Adds a playable session-only item without writing it to the repository.
  void addTemporaryMedia(List<MediaItem> items) {
    if (items.isEmpty) return;
    final ids = state.media.map((m) => m.id).toSet();
    final fresh = items.where((m) => !ids.contains(m.id)).toList();
    if (fresh.isEmpty) return;
    state = LibraryState(
      media: [...state.media, ...fresh],
      playlists: state.playlists,
      loaded: true,
    );
  }

  /// Copies a session-only item into app storage and makes it a normal library item.
  Future<void> saveTemporaryMedia(String id) async {
    final current = state.byId(id);
    if (current == null || !current.isTemporary) return;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/yureru_media');
    await dir.create(recursive: true);
    final name = current.localPath.split(RegExp(r'[/\\]')).last;
    final destination =
        '${dir.path}/${DateTime.now().microsecondsSinceEpoch}_$name';
    await File(current.localPath).copy(destination);
    await _updateMedia(
      id,
      (item) => item.copyWith(
        localPath: destination,
        origin: 'imported',
        sourcePath: current.localPath,
      ),
    );
  }

  /// One update path keeps persistence rules consistent for every media field.
  Future<void> _setMedia(List<MediaItem> media) async {
    final previousPlaylists = state.playlists;
    final playlists = _refreshSmartPlaylists(previousPlaylists, media);
    state = LibraryState(media: media, playlists: playlists, loaded: true);
    await repo.saveMedia(state.savedMedia);
    if (_playlistContentsChanged(previousPlaylists, playlists)) {
      await repo.savePlaylists(playlists);
    }
  }

  List<Playlist> _refreshSmartPlaylists(
    List<Playlist> playlists,
    List<MediaItem> media,
  ) => [
    for (final playlist in playlists)
      if (!playlist.isSmart)
        playlist
      else
        playlist.copyWith(
          mediaIds: _smartPlaylistIds(playlist.smartRule!, media),
        ),
  ];

  List<String> _smartPlaylistIds(String rule, List<MediaItem> media) {
    final items = media.where((item) => !item.isTemporary).toList();
    switch (rule) {
      case 'recently_played':
        items.removeWhere((item) => item.lastPlayedAt == null);
        items.sort((a, b) => b.lastPlayedAt!.compareTo(a.lastPlayedAt!));
        break;
      case 'most_played':
        items.removeWhere((item) => item.playCount <= 0);
        items.sort(
          (a, b) => b.recommendationScore.compareTo(a.recommendationScore),
        );
        break;
      case 'never_played':
        items.removeWhere((item) => item.playCount > 0);
        items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case 'recently_added':
        items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case 'without_lyrics':
        items.removeWhere(
          (item) => [
            item.lyricsPath,
            item.videoLyricsPath,
            item.artworkLyricsPath,
          ].any((path) => path != null && path.isNotEmpty),
        );
        items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      default:
        return const [];
    }
    return items.map((item) => item.id).toList(growable: false);
  }

  bool _playlistContentsChanged(List<Playlist> before, List<Playlist> after) {
    if (before.length != after.length) return true;
    for (var i = 0; i < before.length; i++) {
      if (before[i].id != after[i].id ||
          before[i].smartRule != after[i].smartRule ||
          before[i].mediaIds.length != after[i].mediaIds.length) {
        return true;
      }
      for (var j = 0; j < before[i].mediaIds.length; j++) {
        if (before[i].mediaIds[j] != after[i].mediaIds[j]) return true;
      }
    }
    return false;
  }

  Future<void> _updateMedia(
    String id,
    MediaItem Function(MediaItem) update,
  ) async {
    if (state.byId(id) == null) return;
    await _setMedia([
      for (final item in state.media) item.id == id ? update(item) : item,
    ]);
  }

  Future<void> recordPlayback(
    String id, {
    DateTime? at,
    bool countAsPlay = true,
  }) async {
    final item = state.byId(id);
    if (item == null || item.isTemporary) return;
    final playedAt = at ?? DateTime.now();
    final dayKey =
        '${playedAt.year.toString().padLeft(4, '0')}-'
        '${playedAt.month.toString().padLeft(2, '0')}-'
        '${playedAt.day.toString().padLeft(2, '0')}';
    final daily = Map<String, int>.from(item.playCountsByDay);
    if (countAsPlay) {
      daily.update(dayKey, (count) => count + 1, ifAbsent: () => 1);
    }
    await _updateMedia(
      id,
      (current) => current.copyWith(
        lastPlayedAt: playedAt,
        playCount: current.playCount + (countAsPlay ? 1 : 0),
        playCountsByDay: daily,
      ),
    );
  }

  Future<void> clearPlaybackHistory() async {
    if (!state.media.any(
      (item) =>
          item.lastPlayedAt != null ||
          item.playCount > 0 ||
          item.playCountsByDay.isNotEmpty,
    )) {
      return;
    }
    await _setMedia([
      for (final item in state.media)
        item.lastPlayedAt == null &&
                item.playCount == 0 &&
                item.playCountsByDay.isEmpty
            ? item
            : item.copyWith(
                lastPlayedAt: null,
                playCount: 0,
                playCountsByDay: const {},
              ),
    ]);
  }

  Future<void> toggleFavorite(String id) async {
    final current = state.byId(id);
    if (current == null || current.isTemporary) return;
    await _updateMedia(
      id,
      (item) => item.copyWith(isFavorite: !item.isFavorite),
    );
  }

  Future<void> updateMediaMetadata(
    String id, {
    required String title,
    required String? artist,
  }) => _updateMedia(id, (item) => item.copyWith(title: title, artist: artist));

  /// Saves the full media details form in one state/persistence update so
  /// playback progress or another metadata change cannot interleave between
  /// separate title, album and artwork writes.
  Future<void> updateMediaDetails(
    String id, {
    required String title,
    required String? artist,
    required String? album,
    required String? albumArtist,
    required int? trackNumber,
    required int? discNumber,
    required String? artworkPath,
    MediaViewAvailability? viewAvailability,
    required String? thumbnailPath,
    required int lyricsOffsetMs,
    bool? separateLyricsByView,
    int? videoLyricsOffsetMs,
    int? artworkLyricsOffsetMs,
    bool artworkLyricsOffsetFollowsVideo = true,
    String? artworkAudioMediaId,
    String? artworkAudioPath,
    int artworkAudioOffsetMs = 0,
    int artworkAudioEndMs = 0,
  }) async {
    final current = state.byId(id);
    if (current == null) return;
    await _updateMedia(
      id,
      (item) => item.copyWith(
        title: title,
        artist: artist,
        album: album,
        albumArtist: albumArtist,
        trackNumber: trackNumber,
        discNumber: discNumber,
        artworkPath: artworkPath,
        viewAvailability: viewAvailability,
        thumbnailPath: thumbnailPath,
        lyricsOffsetMs: lyricsOffsetMs,
        separateLyricsByView: separateLyricsByView,
        videoLyricsOffsetMs: videoLyricsOffsetMs,
        artworkLyricsOffsetMs: artworkLyricsOffsetMs,
        artworkLyricsOffsetFollowsVideo: artworkLyricsOffsetFollowsVideo,
        artworkAudioMediaId: artworkAudioMediaId,
        artworkAudioPath: artworkAudioPath,
        artworkAudioOffsetMs: artworkAudioOffsetMs,
        artworkAudioEndMs: artworkAudioEndMs,
      ),
    );
    await _deleteManagedImageIfReplaced(current.artworkPath, artworkPath);
    await _deleteManagedImageIfReplaced(current.thumbnailPath, thumbnailPath);
    await _deleteManagedAudioIfReplaced(
      current.artworkAudioPath,
      artworkAudioPath,
    );
  }

  Future<void> _deleteManagedAudioIfReplaced(
    String? oldPath,
    String? newPath,
  ) async {
    if (oldPath == null ||
        oldPath == newPath ||
        !_isManagedPath(oldPath, const {'yureru_audio_sources'})) {
      return;
    }
    if (state.savedMedia.any((item) => item.artworkAudioPath == oldPath)) {
      return;
    }
    try {
      final file = File(oldPath);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  Future<void> _deleteManagedImageIfReplaced(
    String? oldPath,
    String? newPath,
  ) async {
    if (oldPath == null || oldPath == newPath) return;
    if (!_isManagedPath(oldPath, const {
      'yureru_artwork',
      'yureru_thumbnails',
    })) {
      return;
    }
    if (state.savedMedia.any(
      (item) => item.artworkPath == oldPath || item.thumbnailPath == oldPath,
    )) {
      return;
    }
    try {
      await File(oldPath).delete();
    } catch (_) {}
  }

  bool _isManagedPath(String path, Set<String> folders) =>
      RegExp('[\\\\/](${folders.join('|')})[\\\\/]').hasMatch(path);

  /// One save for the complete selection. Session-only media is never edited.
  Future<void> updateMediaMetadataBatch(
    Iterable<String> ids,
    MediaMetadataPatch patch,
  ) async {
    patch.validate();
    if (patch.isEmpty) return;
    final available = state.savedMedia.map((m) => m.id).toSet();
    final ordered = ids.toSet().where(available.contains).toList();
    final indices = {for (var i = 0; i < ordered.length; i++) ordered[i]: i};
    final selected = ordered.toSet();
    if (!state.media.any(
      (item) => !item.isTemporary && selected.contains(item.id),
    )) {
      return;
    }
    final before = state;
    final updated = [
      for (final item in state.media)
        if (!item.isTemporary && selected.contains(item.id))
          patch.apply(item, index: indices[item.id]!)
        else
          item,
    ];
    try {
      await _setMedia(updated);
    } catch (_) {
      // Do not undo another edit that completed while this save was pending.
      if (identical(state.media, updated)) {
        state = LibraryState(
          media: before.media,
          playlists: state.playlists,
          loaded: state.loaded,
        );
      }
      rethrow;
    }
  }

  Future<void> updateMediaAlbum(
    String id, {
    required String? album,
    required String? albumArtist,
    required int? trackNumber,
    required int? discNumber,
  }) => _updateMedia(
    id,
    (item) => item.copyWith(
      album: album,
      albumArtist: albumArtist,
      trackNumber: trackNumber,
      discNumber: discNumber,
    ),
  );

  /// Applies one album identity and optional shared cover to selected media.
  Future<void> updateMediaAlbumBatch(
    Iterable<String> ids, {
    required String album,
    required String albumArtist,
    String? artworkPath,
  }) async {
    final selected = ids.toSet();
    if (selected.isEmpty) return;
    final oldArtworkPaths = state.media
        .where((item) => selected.contains(item.id))
        .map((item) => item.artworkPath)
        .whereType<String>()
        .toSet();
    await _setMedia([
      for (final item in state.media)
        if (!item.isTemporary && selected.contains(item.id))
          artworkPath == null
              ? item.copyWith(album: album, albumArtist: albumArtist)
              : item.copyWith(
                  album: album,
                  albumArtist: albumArtist,
                  artworkPath: artworkPath,
                )
        else
          item,
    ]);
    if (artworkPath != null) {
      for (final oldPath in oldArtworkPaths) {
        await _deleteManagedImageIfReplaced(oldPath, artworkPath);
      }
    }
  }

  Future<void> updateMediaArtists(List<String> ids, String? artist) async {
    final selectedIds = ids.toSet();
    if (selectedIds.isEmpty) return;
    await _setMedia([
      for (final item in state.media)
        selectedIds.contains(item.id) ? item.copyWith(artist: artist) : item,
    ]);
  }

  Future<void> updateMediaArtwork(String id, String? path) async {
    final current = state.byId(id);
    if (current == null || current.artworkPath == path) return;
    await _updateMedia(id, (item) => item.copyWith(artworkPath: path));
    await _deleteManagedImageIfReplaced(current.artworkPath, path);
  }

  Future<void> updateMediaThumbnail(String id, String? path) async {
    final current = state.byId(id);
    if (current == null || current.thumbnailPath == path) return;
    await _updateMedia(id, (item) => item.copyWith(thumbnailPath: path));
    await _deleteManagedImageIfReplaced(current.thumbnailPath, path);
  }

  Future<void> updateMediaLyrics(String id, String? path) async {
    final current = state.byId(id);
    if (current == null ||
        (current.lyricsPath == path &&
            (path == null || !current.lyricsButtonHidden))) {
      return;
    }
    await _updateMedia(
      id,
      (item) => item.copyWith(
        lyricsPath: path,
        lyricsButtonHidden: path == null ? item.lyricsButtonHidden : false,
      ),
    );
    await _deleteManagedLyricsIfReplaced(current.lyricsPath, path);
  }

  Future<void> _deleteManagedLyricsIfReplaced(
    String? oldPath,
    String? newPath,
  ) async {
    if (oldPath == null ||
        oldPath == newPath ||
        !_isManagedPath(oldPath, const {'yureru_lyrics'})) {
      return;
    }
    bool referencesPath(Iterable<Object?> paths) =>
        paths.any((path) => path == oldPath);
    const lyricFields = [
      'lyricsPath',
      'translatedLyricsPath',
      'videoLyricsPath',
      'artworkLyricsPath',
    ];
    if (state.savedMedia.any(
      (item) => referencesPath([
        item.lyricsPath,
        item.translatedLyricsPath,
        item.videoLyricsPath,
        item.artworkLyricsPath,
      ]),
    )) {
      return;
    }
    // Deleted media remains recoverable from Trash for 30 days, so keep any
    // lyrics file still referenced by a trash entry as well.
    final trash = await TrashStore().load();
    if (trash.any(
      (entry) => lyricFields.any((field) => entry.data[field] == oldPath),
    )) {
      return;
    }
    try {
      final file = File(oldPath);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  Future<void> updateTranslatedLyrics(String id, String? path) async {
    final current = state.byId(id);
    if (current == null || current.translatedLyricsPath == path) return;
    await _updateMedia(id, (item) => item.copyWith(translatedLyricsPath: path));
  }

  Future<void> setLyricsEditingFinalized(String id, bool finalized) async {
    final current = state.byId(id);
    if (current == null || current.lyricsEditingFinalized == finalized) return;
    await _updateMedia(
      id,
      (item) => item.copyWith(lyricsEditingFinalized: finalized),
    );
  }

  Future<void> setLyricsButtonHidden(String id, bool hidden) async {
    final current = state.byId(id);
    if (current == null || current.lyricsButtonHidden == hidden) return;
    await _updateMedia(id, (item) => item.copyWith(lyricsButtonHidden: hidden));
  }

  Future<void> updateMediaLyricsOffset(String id, int offsetMs) async {
    final current = state.byId(id);
    if (current == null || current.lyricsOffsetMs == offsetMs) return;
    await _updateMedia(id, (item) => item.copyWith(lyricsOffsetMs: offsetMs));
  }

  Future<void> setSeparateLyricsByView(String id, bool separate) async {
    final current = state.byId(id);
    if (current == null || current.separateLyricsByView == separate) return;
    await _updateMedia(
      id,
      (item) => item.copyWith(
        separateLyricsByView: separate,
        // Start both views at the existing shared timing. The user can then
        // adjust artwork and video independently without separate LRC files.
        videoLyricsOffsetMs: separate
            ? item.lyricsOffsetMs
            : item.videoLyricsOffsetMs,
        artworkLyricsOffsetMs: separate
            ? item.lyricsOffsetMs
            : item.artworkLyricsOffsetMs,
        artworkLyricsOffsetFollowsVideo: true,
      ),
    );
  }

  Future<void> updateMediaLyricsForView(
    String id, {
    required bool artwork,
    required String? path,
  }) async {
    final current = state.byId(id);
    if (current == null) return;
    if (!current.separateLyricsByView) {
      await updateMediaLyrics(id, path);
      return;
    }
    await _updateMedia(
      id,
      (item) => artwork
          ? item.copyWith(
              artworkLyricsPath: path,
              lyricsButtonHidden: path == null
                  ? item.lyricsButtonHidden
                  : false,
            )
          : item.copyWith(
              videoLyricsPath: path,
              lyricsButtonHidden: path == null
                  ? item.lyricsButtonHidden
                  : false,
            ),
    );
    await _deleteManagedLyricsIfReplaced(
      artwork ? current.artworkLyricsPath : current.videoLyricsPath,
      path,
    );
  }

  Future<void> updateMediaLyricsOffsetForView(
    String id, {
    required bool artwork,
    required int offsetMs,
  }) async {
    final current = state.byId(id);
    if (current == null) return;
    if (!current.separateLyricsByView &&
        current.artworkAudioMediaId == null &&
        current.artworkAudioPath == null &&
        current.artworkLyricsOffsetFollowsVideo) {
      await updateMediaLyricsOffset(id, offsetMs);
      return;
    }
    await _updateMedia(
      id,
      (item) => artwork
          ? item.copyWith(
              artworkLyricsOffsetMs: offsetMs,
              artworkLyricsOffsetFollowsVideo: false,
            )
          : item.copyWith(videoLyricsOffsetMs: offsetMs),
    );
  }

  Future<void> setArtworkLyricsOffsetFollowsVideo(
    String id,
    bool followsVideo,
  ) async {
    final current = state.byId(id);
    if (current == null ||
        current.artworkLyricsOffsetFollowsVideo == followsVideo) {
      return;
    }
    await _updateMedia(
      id,
      (item) => item.copyWith(
        artworkLyricsOffsetFollowsVideo: followsVideo,
        artworkLyricsOffsetMs: followsVideo
            ? item.lyricsOffsetForView(artwork: false)
            : item.artworkLyricsOffsetMs,
      ),
    );
  }

  Future<void> removeMedia(String id) async {
    final removed = state.media.where((e) => e.id == id).toList();
    if (removed.isEmpty || removed.first.isTemporary) return;
    final playlistPositions = <String, int>{};
    for (final playlist in state.playlists) {
      final index = playlist.mediaIds.indexOf(id);
      if (index >= 0 && !playlist.isSmart) {
        playlistPositions[playlist.id] = index;
      }
    }
    await TrashStore().saveMedia(removed.first, playlistPositions);
    final m = state.media.where((e) => e.id != id).toList();
    final p = state.playlists
        .map(
          (pl) =>
              pl.copyWith(mediaIds: pl.mediaIds.where((x) => x != id).toList()),
        )
        .toList();
    final updatedPlaylists = _refreshSmartPlaylists(p, m);
    state = LibraryState(media: m, playlists: updatedPlaylists, loaded: true);
    await repo.saveMedia(state.savedMedia);
    await repo.savePlaylists(updatedPlaylists);
  }

  Future<Playlist> createPlaylist(String name) async {
    final pl = Playlist(
      name: name.trim().isEmpty ? 'New Playlist' : name.trim(),
    );
    final p = [...state.playlists, pl];
    state = LibraryState(media: state.media, playlists: p, loaded: true);
    await repo.savePlaylists(p);
    return pl;
  }

  Future<Playlist> createSmartPlaylist(String name, String rule) async {
    const supportedRules = {
      'recently_played',
      'most_played',
      'never_played',
      'recently_added',
      'without_lyrics',
    };
    if (!supportedRules.contains(rule)) {
      throw ArgumentError.value(rule, 'rule', 'Unknown smart playlist rule');
    }
    final playlist = Playlist(
      name: name.trim().isEmpty ? 'Smart Playlist' : name.trim(),
      smartRule: rule,
      mediaIds: _smartPlaylistIds(rule, state.savedMedia),
    );
    final playlists = [...state.playlists, playlist];
    state = LibraryState(
      media: state.media,
      playlists: playlists,
      loaded: true,
    );
    await repo.savePlaylists(playlists);
    return playlist;
  }

  Future<void> renamePlaylist(String id, String name) async {
    final clean = name.trim().isEmpty ? 'New Playlist' : name.trim();
    final p = state.playlists
        .map((pl) => pl.id == id ? pl.copyWith(name: clean) : pl)
        .toList();
    state = LibraryState(media: state.media, playlists: p, loaded: true);
    await repo.savePlaylists(p);
  }

  Future<void> setPlaylistImagePriority(String id, String? priority) async {
    final current = state.playlistById(id);
    if (current == null || current.imagePriority == priority) return;
    final playlists = state.playlists
        .map(
          (playlist) => playlist.id == id
              ? playlist.copyWith(imagePriority: priority)
              : playlist,
        )
        .toList();
    state = LibraryState(
      media: state.media,
      playlists: playlists,
      loaded: true,
    );
    await repo.savePlaylists(playlists);
  }

  Future<void> setPlaylistArtworkPath(String id, String? path) async {
    final current = state.playlistById(id);
    if (current == null || current.artworkPath == path) return;
    final playlists = state.playlists
        .map(
          (playlist) => playlist.id == id
              ? playlist.copyWith(artworkPath: path)
              : playlist,
        )
        .toList();
    state = LibraryState(
      media: state.media,
      playlists: playlists,
      loaded: true,
    );
    await repo.savePlaylists(playlists);
    final oldPath = current.artworkPath;
    if (oldPath == null ||
        oldPath == path ||
        !oldPath.contains('yureru_playlist_artwork')) {
      return;
    }
    try {
      final file = File(oldPath);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// Persist a probed duration so lists show it instantly next launch.
  /// No-op when unknown or unchanged (avoids prefs churn).
  Future<void> setDurationMs(String id, int ms) async {
    if (ms <= 0) return;
    final cur = state.byId(id);
    if (cur == null || cur.durationMs == ms) return;
    await _updateMedia(id, (item) => item.copyWith(durationMs: ms));
  }

  Future<void> deletePlaylist(String id) async {
    final removed = state.playlistById(id);
    if (removed != null) await TrashStore().savePlaylist(removed);
    final p = state.playlists.where((e) => e.id != id).toList();
    state = LibraryState(media: state.media, playlists: p, loaded: true);
    await repo.savePlaylists(p);
  }

  Future<void> restoreTrashEntry(TrashEntry entry) async {
    if (entry.type == 'media') {
      final media = MediaItem.fromJson(entry.data);
      if (state.byId(media.id) != null) {
        await TrashStore().remove(entry.id);
        return;
      }
      await _setMedia([...state.media, media]);
      final playlists = [
        for (final playlist in state.playlists)
          if (entry.playlistPositions.containsKey(playlist.id) &&
              !playlist.isSmart)
            playlist.copyWith(
              mediaIds: _insertAt(
                playlist.mediaIds,
                media.id,
                entry.playlistPositions[playlist.id]!,
              ),
            )
          else
            playlist,
      ];
      state = LibraryState(
        media: state.media,
        playlists: playlists,
        loaded: true,
      );
      await repo.savePlaylists(playlists);
    } else if (entry.type == 'playlist') {
      final playlist = Playlist.fromJson(entry.data);
      if (state.playlistById(playlist.id) == null) {
        final playlists = _refreshSmartPlaylists([
          ...state.playlists,
          playlist,
        ], state.media);
        state = LibraryState(
          media: state.media,
          playlists: playlists,
          loaded: true,
        );
        await repo.savePlaylists(playlists);
      }
    }
    await TrashStore().remove(entry.id);
  }

  List<String> _insertAt(List<String> source, String value, int index) {
    if (source.contains(value)) return source;
    final result = [...source];
    result.insert(index.clamp(0, result.length), value);
    return result;
  }

  Future<void> addToPlaylist(String playlistId, String mediaId) async {
    await addMediaToPlaylist(playlistId, [mediaId]);
  }

  Future<void> addMediaToPlaylist(
    String playlistId,
    List<String> mediaIds,
  ) async {
    if (state.playlistById(playlistId)?.isSmart ?? true) return;
    final toAdd = mediaIds.toSet();
    final p = state.playlists.map((pl) {
      if (pl.id != playlistId) return pl;
      final additions = toAdd.where((id) => !pl.mediaIds.contains(id));
      return pl.copyWith(mediaIds: [...pl.mediaIds, ...additions]);
    }).toList();
    state = LibraryState(media: state.media, playlists: p, loaded: true);
    await repo.savePlaylists(p);
  }

  Future<void> removeFromPlaylist(String playlistId, String mediaId) async {
    await removeMediaFromPlaylist(playlistId, [mediaId]);
  }

  Future<void> removeMediaFromPlaylist(
    String playlistId,
    Iterable<String> mediaIds,
  ) async {
    if (state.playlistById(playlistId)?.isSmart ?? true) return;
    final toRemove = mediaIds.toSet();
    final p = state.playlists
        .map(
          (pl) => pl.id != playlistId
              ? pl
              : pl.copyWith(
                  mediaIds: pl.mediaIds
                      .where((x) => !toRemove.contains(x))
                      .toList(),
                ),
        )
        .toList();
    state = LibraryState(media: state.media, playlists: p, loaded: true);
    await repo.savePlaylists(p);
  }

  Future<void> reorderPlaylist(String playlistId, int from, int to) async {
    final playlist = state.playlistById(playlistId);
    if (playlist == null ||
        playlist.isSmart ||
        from < 0 ||
        from >= playlist.mediaIds.length) {
      return;
    }
    final ids = [...playlist.mediaIds];
    if (to < 0 || to >= ids.length || from == to) return;
    ids.insert(to, ids.removeAt(from));
    final playlists = state.playlists
        .map(
          (item) => item.id == playlistId ? item.copyWith(mediaIds: ids) : item,
        )
        .toList();
    state = LibraryState(
      media: state.media,
      playlists: playlists,
      loaded: true,
    );
    await repo.savePlaylists(playlists);
  }

  Future<void> reorderMedia(int from, int to) async {
    if (from < 0 || from >= state.media.length) return;
    final media = [...state.media];
    if (to < 0 || to >= media.length || from == to) return;
    media.insert(to, media.removeAt(from));
    await _setMedia(media);
  }
}
