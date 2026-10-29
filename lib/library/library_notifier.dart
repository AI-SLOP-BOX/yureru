import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../data/store.dart';
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
  LibraryNotifier(this.repo) : super(const LibraryState());
  Future<void> load() async {
    final m = await repo.loadMedia();
    final p = await repo.loadPlaylists();
    state = LibraryState(media: m, playlists: p, loaded: true);
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
    final m = [...state.media, ...fresh];
    await _setMedia(m);
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
    state = LibraryState(
      media: media,
      playlists: state.playlists,
      loaded: true,
    );
    await repo.saveMedia(state.savedMedia);
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

  Future<void> recordPlayback(String id, {DateTime? at}) async {
    final item = state.byId(id);
    if (item == null || item.isTemporary) return;
    await _updateMedia(
      id,
      (current) => current.copyWith(lastPlayedAt: at ?? DateTime.now()),
    );
  }

  Future<void> clearPlaybackHistory() async {
    if (!state.media.any((item) => item.lastPlayedAt != null)) return;
    await _setMedia([
      for (final item in state.media)
        item.lastPlayedAt == null ? item : item.copyWith(lastPlayedAt: null),
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
    required String? thumbnailPath,
    required String? imagePriority,
    required int lyricsOffsetMs,
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
        thumbnailPath: thumbnailPath,
        imagePriority: imagePriority,
        lyricsOffsetMs: lyricsOffsetMs,
      ),
    );
    await _deleteManagedImageIfReplaced(current.artworkPath, artworkPath);
    await _deleteManagedImageIfReplaced(current.thumbnailPath, thumbnailPath);
  }

  Future<void> _deleteManagedImageIfReplaced(
    String? oldPath,
    String? newPath,
  ) async {
    if (oldPath == null || oldPath == newPath) return;
    if (!oldPath.contains('yureru_artwork') &&
        !oldPath.contains('yureru_thumbnails')) {
      return;
    }
    try {
      await File(oldPath).delete();
    } catch (_) {}
  }

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
    final oldPath = current.artworkPath;
    if (oldPath != null && oldPath.contains('yureru_artwork')) {
      try {
        await File(oldPath).delete();
      } catch (_) {}
    }
  }

  Future<void> updateMediaThumbnail(String id, String? path) async {
    final current = state.byId(id);
    if (current == null || current.thumbnailPath == path) return;
    await _updateMedia(id, (item) => item.copyWith(thumbnailPath: path));
    final oldPath = current.thumbnailPath;
    if (oldPath != null && oldPath.contains('yureru_thumbnails')) {
      try {
        await File(oldPath).delete();
      } catch (_) {}
    }
  }

  Future<void> updateMediaLyrics(String id, String? path) async {
    final current = state.byId(id);
    if (current == null || current.lyricsPath == path) return;
    await _updateMedia(id, (item) => item.copyWith(lyricsPath: path));
  }

  Future<void> updateMediaLyricsOffset(String id, int offsetMs) async {
    final current = state.byId(id);
    if (current == null || current.lyricsOffsetMs == offsetMs) return;
    await _updateMedia(id, (item) => item.copyWith(lyricsOffsetMs: offsetMs));
  }

  Future<void> removeMedia(String id) async {
    final removed = state.media.where((e) => e.id == id).toList();
    final m = state.media.where((e) => e.id != id).toList();
    final p = state.playlists
        .map(
          (pl) =>
              pl.copyWith(mediaIds: pl.mediaIds.where((x) => x != id).toList()),
        )
        .toList();
    state = LibraryState(media: m, playlists: p, loaded: true);
    await repo.saveMedia(state.savedMedia);
    await repo.savePlaylists(p);
    // Best-effort: delete app-managed copies so disk doesn't leak.
    // Referenced (non-copied) files are never touched.
    for (final r in removed) {
      if (r.origin == 'imported' && r.localPath.contains('yureru_media')) {
        try {
          await File(r.localPath).delete();
        } catch (_) {}
      }
      final art = r.artworkPath;
      if (art != null && art.contains('yureru_artwork')) {
        try {
          await File(art).delete();
        } catch (_) {}
      }
      final thumbnail = r.thumbnailPath;
      if (thumbnail != null && thumbnail.contains('yureru_thumbnails')) {
        try {
          await File(thumbnail).delete();
        } catch (_) {}
      }
    }
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

  /// Persist a probed duration so lists show it instantly next launch.
  /// No-op when unknown or unchanged (avoids prefs churn).
  Future<void> setDurationMs(String id, int ms) async {
    if (ms <= 0) return;
    final cur = state.byId(id);
    if (cur == null || cur.durationMs == ms) return;
    await _updateMedia(id, (item) => item.copyWith(durationMs: ms));
  }

  Future<void> deletePlaylist(String id) async {
    final p = state.playlists.where((e) => e.id != id).toList();
    state = LibraryState(media: state.media, playlists: p, loaded: true);
    await repo.savePlaylists(p);
  }

  Future<void> addToPlaylist(String playlistId, String mediaId) async {
    await addMediaToPlaylist(playlistId, [mediaId]);
  }

  Future<void> addMediaToPlaylist(
    String playlistId,
    List<String> mediaIds,
  ) async {
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
    final p = state.playlists
        .map(
          (pl) => pl.id != playlistId
              ? pl
              : pl.copyWith(
                  mediaIds: pl.mediaIds.where((x) => x != mediaId).toList(),
                ),
        )
        .toList();
    state = LibraryState(media: state.media, playlists: p, loaded: true);
    await repo.savePlaylists(p);
  }

  Future<void> reorderPlaylist(String playlistId, int from, int to) async {
    final playlist = state.playlistById(playlistId);
    if (playlist == null || from < 0 || from >= playlist.mediaIds.length) {
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
