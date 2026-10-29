import 'package:flutter_test/flutter_test.dart';
import 'package:yureru/data/store.dart';
import 'package:yureru/domain/models.dart';
import 'package:yureru/library/library_notifier.dart';

MediaItem _media(String id, {String origin = 'referenced'}) => MediaItem(
  id: id,
  title: 'Original title',
  isFavorite: true,
  lastPlayedAt: DateTime.utc(2026, 10, 1),
  artist: 'Original artist',
  localPath: '/media/$id.mp3',
  durationMs: 120000,
  createdAt: DateTime.utc(2026, 1, 1),
  origin: origin,
  sourceFolderId: 'folder',
  sourcePath: '/source/$id.mp3',
  artworkPath: '/art/$id.jpg',
  lyricsPath: '/lyrics/$id.lrc',
  lyricsOffsetMs: 250,
);

void main() {
  test(
    'playlist image preference persists and can inherit settings again',
    () async {
      final repo = InMemoryLibraryRepository();
      final library = LibraryNotifier(repo);
      addTearDown(library.dispose);
      final playlist = await library.createPlaylist('Mix');

      await library.setPlaylistImagePriority(playlist.id, 'artworkFirst');
      expect(
        library.state.playlistById(playlist.id)!.imagePriority,
        'artworkFirst',
      );
      await library.load();
      expect(
        library.state.playlistById(playlist.id)!.imagePriority,
        'artworkFirst',
      );

      await library.setPlaylistImagePriority(playlist.id, null);
      await library.load();
      expect(library.state.playlistById(playlist.id)!.imagePriority, isNull);
    },
  );

  test(
    'favorites persist through metadata edits and cannot include temporary items',
    () async {
      final repo = InMemoryLibraryRepository();
      final library = LibraryNotifier(repo);
      addTearDown(library.dispose);
      final saved = _media('saved').copyWith(isFavorite: false);
      final temporary = _media(
        'temporary',
        origin: 'temporary',
      ).copyWith(isFavorite: false);
      await library.addMedia([saved]);
      library.addTemporaryMedia([temporary]);
      await library.toggleFavorite(saved.id);
      await library.toggleFavorite(temporary.id);
      await library.updateMediaMetadata(
        saved.id,
        title: 'Changed',
        artist: 'Artist',
      );
      expect(library.state.byId(saved.id)!.isFavorite, isTrue);
      expect(library.state.byId(temporary.id)!.isFavorite, isFalse);
      await library.load();
      expect(library.state.byId(saved.id)!.isFavorite, isTrue);
      expect(library.state.byId(temporary.id), isNull);
      await library.toggleFavorite(saved.id);
      await library.load();
      expect(library.state.byId(saved.id)!.isFavorite, isFalse);
    },
  );

  test(
    'metadata edits preserve unrelated fields, playlist and other media',
    () async {
      final repo = InMemoryLibraryRepository();
      final library = LibraryNotifier(repo);
      addTearDown(library.dispose);
      final original = _media('saved');
      final other = _media('other');
      await library.addMedia([original, other]);
      final playlist = await library.createPlaylist('Favorites');
      await library.addToPlaylist(playlist.id, original.id);
      final expected = original.toJson();

      // Exercise successive edits; a newly added field must survive every path.
      final edits = <(Future<void> Function(), Map<String, dynamic>)>[
        (
          () => library.updateMediaMetadata(
            original.id,
            title: 'Edited',
            artist: null,
          ),
          {'title': 'Edited', 'artist': null},
        ),
        (
          () => library.updateMediaArtists([original.id], 'Collaborators'),
          {'artist': 'Collaborators'},
        ),
        (
          () => library.updateMediaArtwork(original.id, '/art/new.jpg'),
          {'artworkPath': '/art/new.jpg'},
        ),
        (
          () => library.updateMediaThumbnail(original.id, '/thumb/new.jpg'),
          {'thumbnailPath': '/thumb/new.jpg'},
        ),
        (
          () => library.updateMediaLyrics(original.id, '/lyrics/new.lrc'),
          {'lyricsPath': '/lyrics/new.lrc'},
        ),
        (
          () => library.updateMediaLyricsOffset(original.id, -500),
          {'lyricsOffsetMs': -500},
        ),
        (
          () => library.setDurationMs(original.id, 180000),
          {'durationMs': 180000},
        ),
        (
          () => library.updateMediaArtwork(original.id, null),
          {'artworkPath': null},
        ),
        (
          () => library.updateMediaThumbnail(original.id, null),
          {'thumbnailPath': null},
        ),
        (
          () => library.updateMediaLyrics(original.id, null),
          {'lyricsPath': null},
        ),
      ];
      for (final (edit, changes) in edits) {
        await edit();
        expected.addAll(changes);
        expect(library.state.byId(original.id)!.toJson(), expected);
        expect((await repo.loadMedia()).first.toJson(), expected);
        expect(library.state.byId(other.id)!.toJson(), other.toJson());
        expect(library.state.playlistById(playlist.id)!.mediaIds, [
          original.id,
        ]);
      }
      await library.load();
      expect(library.state.byId(original.id)!.toJson(), expected);
    },
  );

  test(
    'all metadata and reorder paths keep temporary media out of storage',
    () async {
      final repo = InMemoryLibraryRepository();
      final library = LibraryNotifier(repo);
      addTearDown(library.dispose);
      final saved = _media('saved');
      final temporary = _media('temporary', origin: 'temporary');
      await library.addMedia([saved]);
      library.addTemporaryMedia([temporary]);

      final edits = <Future<void> Function()>[
        () => library.updateMediaMetadata(
          temporary.id,
          title: 'Session',
          artist: null,
        ),
        () => library.updateMediaArtists([saved.id, temporary.id], 'Artist'),
        () => library.updateMediaArtwork(temporary.id, '/art/session.jpg'),
        () => library.updateMediaLyrics(temporary.id, '/lyrics/session.lrc'),
        () => library.updateMediaLyricsOffset(temporary.id, 1000),
        () => library.setDurationMs(temporary.id, 90000),
        () => library.reorderMedia(1, 0),
        () => library.addMedia([_media('added')]),
        () => library.removeMedia('added'),
      ];
      for (final edit in edits) {
        await edit();
        expect(library.state.byId(temporary.id), isNotNull);
        expect(
          (await repo.loadMedia()).any((item) => item.isTemporary),
          isFalse,
        );
      }
      await library.load();
      expect(library.state.byId(temporary.id), isNull);
      expect(library.state.byId(saved.id)!.artist, 'Artist');
    },
  );

  test(
    'media details update title and related fields in one saved item',
    () async {
      final repo = InMemoryLibraryRepository();
      final library = LibraryNotifier(repo);
      addTearDown(library.dispose);
      final media = _media('details');
      await library.addMedia([media]);

      await library.updateMediaDetails(
        media.id,
        title: 'New title',
        artist: 'New artist',
        album: 'New album',
        albumArtist: 'Album artist',
        trackNumber: 3,
        discNumber: 2,
        artworkPath: media.artworkPath,
        thumbnailPath: '/thumb/details.jpg',
        lyricsOffsetMs: 1250,
      );

      final updated = library.state.byId(media.id)!;
      expect(updated.title, 'New title');
      expect(updated.artist, 'New artist');
      expect(updated.album, 'New album');
      expect(updated.trackNumber, 3);
      expect(updated.thumbnailPath, '/thumb/details.jpg');
      await library.load();
      expect(library.state.byId(media.id)!.title, 'New title');
    },
  );
}
