import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'domain/models.dart';
import 'data/store.dart';
import 'data/importer.dart';
import 'playback/playback_engine.dart';
import 'playback/media_kit_engine.dart';

final repositoryProvider = Provider<LibraryRepository>(
  (_) => PrefsLibraryRepository(),
);
final importerProvider = Provider((_) => VideoImporter());
final engineProvider = Provider<PlaybackEngine>(
  (_) => MediaKitPlaybackEngine(),
);
final volumeProvider = StateProvider<double>(
  (ref) => ref.read(engineProvider).volume,
);

class LibraryState {
  final List<MediaItem> media;
  final List<Playlist> playlists;
  final bool loaded;
  const LibraryState({
    this.media = const [],
    this.playlists = const [],
    this.loaded = false,
  });
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
    state = LibraryState(media: m, playlists: state.playlists, loaded: true);
    await repo.saveMedia(m);
  }

  Future<void> updateMediaMetadata(
    String id, {
    required String title,
    required String? artist,
  }) async {
    final current = state.byId(id);
    if (current == null) return;
    final m = state.media
        .map(
          (e) => e.id != id
              ? e
              : MediaItem(
                  id: e.id,
                  title: title,
                  artist: artist,
                  localPath: e.localPath,
                  durationMs: e.durationMs,
                  createdAt: e.createdAt,
                  origin: e.origin,
                  sourceFolderId: e.sourceFolderId,
                  sourcePath: e.sourcePath,
                ),
        )
        .toList();
    state = LibraryState(media: m, playlists: state.playlists, loaded: true);
    await repo.saveMedia(m);
  }

  Future<void> updateMediaArtists(List<String> ids, String? artist) async {
    final selectedIds = ids.toSet();
    if (selectedIds.isEmpty) return;
    final m = state.media
        .map(
          (item) => !selectedIds.contains(item.id)
              ? item
              : MediaItem(
                  id: item.id,
                  title: item.title,
                  artist: artist,
                  localPath: item.localPath,
                  durationMs: item.durationMs,
                  createdAt: item.createdAt,
                  origin: item.origin,
                  sourceFolderId: item.sourceFolderId,
                  sourcePath: item.sourcePath,
                ),
        )
        .toList();
    state = LibraryState(media: m, playlists: state.playlists, loaded: true);
    await repo.saveMedia(m);
  }

  Future<void> removeMedia(String id) async {
    final removed = state.media.where((e) => e.id == id).toList();
    final m = state.media.where((e) => e.id != id).toList();
    final p = state.playlists
        .map(
          (pl) => Playlist(
            id: pl.id,
            name: pl.name,
            mediaIds: pl.mediaIds.where((x) => x != id).toList(),
            createdAt: pl.createdAt,
          ),
        )
        .toList();
    state = LibraryState(media: m, playlists: p, loaded: true);
    await repo.saveMedia(m);
    await repo.savePlaylists(p);
    // Best-effort: delete app-managed copies so disk doesn't leak.
    // Referenced (non-copied) files are never touched.
    for (final r in removed) {
      if (r.origin != 'imported') continue;
      if (!r.localPath.contains('yureru_media')) continue;
      try {
        await File(r.localPath).delete();
      } catch (_) {}
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
        .map(
          (pl) => pl.id == id
              ? Playlist(
                  id: pl.id,
                  name: clean,
                  mediaIds: pl.mediaIds,
                  createdAt: pl.createdAt,
                )
              : pl,
        )
        .toList();
    state = LibraryState(media: state.media, playlists: p, loaded: true);
    await repo.savePlaylists(p);
  }

  /// Persist a probed duration so lists show it instantly next launch.
  /// No-op when unknown or unchanged (avoids prefs churn).
  Future<void> setDurationMs(String id, int ms) async {
    if (ms <= 0) return;
    final cur = state.byId(id);
    if (cur == null || cur.durationMs == ms) return;
    final m = state.media
        .map(
          (e) => e.id != id
              ? e
              : MediaItem(
                  id: e.id,
                  title: e.title,
                  artist: e.artist,
                  localPath: e.localPath,
                  durationMs: ms,
                  createdAt: e.createdAt,
                  origin: e.origin,
                  sourceFolderId: e.sourceFolderId,
                  sourcePath: e.sourcePath,
                ),
        )
        .toList();
    state = LibraryState(media: m, playlists: state.playlists, loaded: true);
    await repo.saveMedia(m);
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
      return Playlist(
        id: pl.id,
        name: pl.name,
        mediaIds: [...pl.mediaIds, ...additions],
        createdAt: pl.createdAt,
      );
    }).toList();
    state = LibraryState(media: state.media, playlists: p, loaded: true);
    await repo.savePlaylists(p);
  }

  Future<void> removeFromPlaylist(String playlistId, String mediaId) async {
    final p = state.playlists
        .map(
          (pl) => pl.id != playlistId
              ? pl
              : Playlist(
                  id: pl.id,
                  name: pl.name,
                  mediaIds: pl.mediaIds.where((x) => x != mediaId).toList(),
                  createdAt: pl.createdAt,
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
          (item) => item.id == playlistId
              ? Playlist(
                  id: item.id,
                  name: item.name,
                  mediaIds: ids,
                  createdAt: item.createdAt,
                )
              : item,
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
    state = LibraryState(
      media: media,
      playlists: state.playlists,
      loaded: true,
    );
    await repo.saveMedia(media);
  }
}

final libraryProvider = StateNotifierProvider<LibraryNotifier, LibraryState>((
  ref,
) {
  return LibraryNotifier(ref.watch(repositoryProvider));
});

// ---- Playback queue state (separate from playlist) ----
class QueueState {
  final List<String> queue;
  final int index;
  final String? sourcePlaylistId;
  final bool shuffle;
  final double speed;

  /// Source (unshuffled) order; used to restore order when shuffle toggles off.
  final List<String> original;

  /// 'all' (default, wraps) | 'one' (restart current) | 'off' (stop at end).
  final String repeat;
  const QueueState({
    this.queue = const [],
    this.index = 0,
    this.sourcePlaylistId,
    this.shuffle = false,
    this.speed = 1.0,
    this.original = const [],
    this.repeat = 'all',
  });
  String? get currentId =>
      queue.isEmpty ? null : queue[index.clamp(0, queue.length - 1)];
  bool get hasCurrent => currentId != null;

  QueueState copyWith({
    List<String>? queue,
    int? index,
    String? sourcePlaylistId,
    bool clearSourcePlaylistId = false,
    bool? shuffle,
    double? speed,
    List<String>? original,
    String? repeat,
  }) => QueueState(
    queue: queue ?? this.queue,
    index: index ?? this.index,
    sourcePlaylistId: clearSourcePlaylistId
        ? null
        : (sourcePlaylistId ?? this.sourcePlaylistId),
    shuffle: shuffle ?? this.shuffle,
    speed: speed ?? this.speed,
    original: original ?? this.original,
    repeat: repeat ?? this.repeat,
  );

  Map<String, dynamic> toJson() => {
    'queue': queue,
    'index': index,
    'sourcePlaylistId': sourcePlaylistId,
    'shuffle': shuffle,
    'speed': speed,
    'original': original,
    'repeat': repeat,
  };

  factory QueueState.fromJson(Map<String, dynamic> j) {
    List<String> ids(dynamic v) =>
        v is List ? v.whereType<String>().toList() : <String>[];
    final repeat = j['repeat'] as String?;
    return QueueState(
      queue: ids(j['queue']),
      index: (j['index'] as num?)?.toInt() ?? 0,
      sourcePlaylistId: j['sourcePlaylistId'] as String?,
      shuffle: j['shuffle'] as bool? ?? false,
      speed: (j['speed'] as num?)?.toDouble() ?? 1.0,
      original: ids(j['original']),
      repeat: (repeat == 'one' || repeat == 'off') ? repeat! : 'all',
    );
  }
}

class QueueNotifier extends StateNotifier<QueueState> {
  QueueNotifier() : super(const QueueState());

  void start(
    List<String> mediaIds, {
    String? playlistId,
    required bool shuffle,
  }) {
    if (mediaIds.isEmpty) return;
    final q = QueueBuilder.build(mediaIds, shuffle: shuffle);
    state = QueueState(
      queue: q,
      index: 0,
      sourcePlaylistId: playlistId,
      shuffle: shuffle,
      speed: state.speed,
      original: List.of(mediaIds),
      repeat: state.repeat,
    );
  }

  void next() {
    if (state.queue.isEmpty) return;
    state = state.copyWith(index: (state.index + 1) % state.queue.length);
  }

  void previous() {
    if (state.queue.isEmpty) return;
    state = state.copyWith(
      index: (state.index - 1 + state.queue.length) % state.queue.length,
    );
  }

  /// Jump to a queue position (UI then calls PlaybackController.openCurrent).
  void jumpTo(int i) {
    if (i < 0 || i >= state.queue.length) return;
    state = state.copyWith(index: i);
  }

  /// Drag-reorder inside the queue panel; keeps the playing item current.
  void move(int from, int to) {
    if (state.queue.isEmpty) return;
    if (from < 0 || from >= state.queue.length) return;
    if (to < 0 || to >= state.queue.length || from == to) return;
    final cur = state.currentId;
    final q = List<String>.of(state.queue);
    q.insert(to, q.removeAt(from));
    final newIdx = cur == null ? 0 : q.indexOf(cur);
    // Keep source order in sync while unshuffled so toggling shuffle
    // off later restores the manual order instead of discarding it.
    final newOriginal = state.shuffle ? state.original : List<String>.of(q);
    state = state.copyWith(
      queue: q,
      index: newIdx < 0 ? 0 : newIdx,
      original: newOriginal,
    );
  }

  /// Remove an item at specific index in the queue.
  void removeAt(int i) {
    if (i < 0 || i >= state.queue.length) return;
    final q = List<String>.of(state.queue);
    final removed = q.removeAt(i);
    final orig = List<String>.of(state.original)..remove(removed);
    int idx = state.index;
    if (i < idx) {
      idx--;
    } else if (i == idx) {
      idx = idx.clamp(0, q.isEmpty ? 0 : q.length - 1);
    }
    final cleared = q.isEmpty;
    state = state.copyWith(
      queue: q,
      index: q.isEmpty ? 0 : idx,
      original: orig,
      clearSourcePlaylistId: cleared,
    );
  }

  /// Drop a media id from the queue (e.g. after library deletion).
  /// Keeps the playing item stable when possible.
  void removeId(String id) {
    if (!state.queue.contains(id)) return;
    final cur = state.currentId;
    final q = state.queue.where((e) => e != id).toList();
    final orig = state.original.where((e) => e != id).toList();
    int idx = state.index;
    if (cur == null) {
      idx = 0;
    } else if (cur == id) {
      // Removed the playing item: stay at the same position (now next item).
      idx = idx.clamp(0, q.isEmpty ? 0 : q.length - 1);
    } else {
      final newCur = q.indexOf(cur);
      idx = newCur < 0 ? 0 : newCur;
    }
    final cleared = q.isEmpty;
    state = state.copyWith(
      queue: q,
      index: q.isEmpty ? 0 : idx,
      original: orig,
      clearSourcePlaylistId: cleared,
    );
  }

  void setSpeed(double s) => state = state.copyWith(speed: s);

  /// Insert [id] right after the playing item ("次に再生").
  /// Already queued: moved there instead of duplicating.
  void playNext(String id) {
    if (state.queue.isEmpty) {
      state = state.copyWith(
        queue: [id],
        index: 0,
        original: [id],
        clearSourcePlaylistId: true,
      );
      return;
    }
    final q = state.queue.where((e) => e != id).toList();
    var at = q.indexOf(state.currentId ?? '');
    final insertAt = at < 0 ? q.length : at + 1;
    q.insert(insertAt.clamp(0, q.length), id);
    final orig = state.original.where((e) => e != id).toList();
    if (!state.shuffle) {
      orig
        ..clear()
        ..addAll(q);
    }
    final newIdx = q.indexOf(state.currentId ?? '');
    state = state.copyWith(
      queue: q,
      index: newIdx < 0 ? 0 : newIdx,
      original: orig,
    );
  }

  /// Append [id] to the end ("キューの最後に追加"). No duplicates.
  void append(String id) {
    if (state.queue.contains(id)) return;
    final q = [...state.queue, id];
    final orig = state.shuffle ? state.original : [...state.original, id];
    state = state.copyWith(queue: q, original: orig);
  }

  void cycleRepeat() {
    const order = ['all', 'one', 'off'];
    state = state.copyWith(
      repeat: order[(order.indexOf(state.repeat) + 1) % order.length],
    );
  }

  /// Toggle shuffle: ON keeps the current item first and shuffles the rest;
  /// OFF restores the original (playlist/library) order at the same item.
  void toggleShuffle() {
    if (state.queue.isEmpty) return;
    if (!state.shuffle) {
      final cur = state.currentId;
      final base = List<String>.of(
        state.original.isEmpty ? state.queue : state.original,
      );
      base.remove(cur);
      base.shuffle();
      state = state.copyWith(queue: [?cur, ...base], index: 0, shuffle: true);
    } else {
      final cur = state.currentId;
      final base = List<String>.of(
        state.original.isEmpty ? state.queue : state.original,
      );
      final idx = cur == null ? -1 : base.indexOf(cur);
      state = state.copyWith(
        queue: base,
        index: idx < 0 ? 0 : idx,
        shuffle: false,
      );
    }
  }

  void clear() => state = QueueState(speed: state.speed, repeat: state.repeat);

  /// Restore a persisted session, dropping ids no longer in the library.
  void restore(QueueState s, Set<String> validIds) {
    final q = s.queue.where(validIds.contains).toList();
    if (q.isEmpty) {
      state = QueueState(speed: s.speed, repeat: s.repeat);
      return;
    }
    final orig = s.original.where(validIds.contains).toList();
    state = QueueState(
      queue: q,
      index: s.index.clamp(0, q.length - 1),
      sourcePlaylistId: s.sourcePlaylistId,
      shuffle: s.shuffle,
      speed: s.speed,
      original: orig.isEmpty ? List.of(q) : orig,
      repeat: s.repeat,
    );
  }
}

final queueProvider = StateNotifierProvider<QueueNotifier, QueueState>(
  (_) => QueueNotifier(),
);

/// Global search text typed in the top bar (filters playlists/videos lists).
final searchQueryProvider = StateProvider<String>((_) => '');

/// Playing-screen display mode. Switching never touches the engine:
/// position, play state, speed, volume, queue, shuffle and repeat are kept.
enum PlayerViewMode { media, image }

final playerViewModeProvider = StateProvider<PlayerViewMode>(
  (_) => PlayerViewMode.media,
);

/// Videos list order.
enum VideosSort { newestFirst, oldestFirst, name, manual }

final videosSortProvider = StateProvider<VideosSort>(
  (_) => VideosSort.newestFirst,
);

/// Optional exact creator filter for the all-videos view.
final videoCreatorFilterProvider = StateProvider<String?>((_) => null);

/// One-shot navigation request emitted by tappable creator labels.
final creatorVideosRequestProvider = StateProvider<String?>((_) => null);

/// One-shot request from global search to reveal a video in the videos list.
final videoOpenRequestProvider = StateProvider<String?>((_) => null);

/// Center pane mode: true = full-size player, false = browse pages.
/// Only explicit user actions (tap play, "再生中") set it to true;
/// auto-advance never yanks the user out of browsing.
final viewingPlayerProvider = StateProvider<bool>((_) => false);

/// Immersive cinema mode (video occupies whole window, hiding sidebars and bars)
final cinemaModeProvider = StateProvider<bool>((_) => false);

/// macOS floating picture-in-picture window state.
final pictureInPictureProvider = StateProvider<bool>((_) => false);

/// Queue panel visibility. Hidden by default; auto-shown on the player
/// screen, auto-hidden when browsing. Manual toggle respected in between.
final queueVisibleProvider = StateProvider<bool>((_) => false);

/// Sidebar collapsed to an icon rail.
final sidebarCollapsedProvider = StateProvider<bool>((_) => false);

/// Theme Mode (Dark by default, Light / White mode supported)
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  static const _kThemeKey = 'yureru_app_theme_mode_v1';
  ThemeModeNotifier() : super(ThemeMode.dark) {
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final saved = p.getString(_kThemeKey);
      if (saved == 'light') {
        state = ThemeMode.light;
      } else if (saved == 'system') {
        state = ThemeMode.system;
      } else {
        state = ThemeMode.dark;
      }
    } catch (_) {}
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kThemeKey, mode.name);
    } catch (_) {}
  }

  void toggle() {
    setThemeMode(state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
  }
}

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((
  _,
) {
  return ThemeModeNotifier();
});

/// Switch the center pane to the full-size player (explicit user action).
/// Queue visibility is controlled by the shell for the current layout.
void showPlayerView(WidgetRef ref) {
  ref.read(viewingPlayerProvider.notifier).state = true;
}
