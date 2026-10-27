import 'package:flutter_test/flutter_test.dart';
import 'package:yureru/data/store.dart';
import 'package:yureru/domain/models.dart';
import 'package:yureru/library/library_notifier.dart';
import 'package:yureru/library/media_metadata_patch.dart';

class _Repository extends InMemoryLibraryRepository {
  int saves = 0;
  bool reject = false;
  @override
  Future<void> saveMedia(List<MediaItem> items) async {
    saves++;
    if (reject) throw StateError('disk unavailable');
    await super.saveMedia(items);
  }
}

void main() {
  test(
    'batch changes only selected fields and saves once, preserving identity and session media',
    () async {
      final repo = _Repository();
      final library = LibraryNotifier(repo);
      addTearDown(library.dispose);
      final a = MediaItem(
        id: 'a',
        title: 'A',
        artist: 'Solo',
        album: 'Old',
        trackNumber: 3,
        isFavorite: true,
        lyricsPath: '/a.lrc',
        localPath: '/a',
      );
      final b = MediaItem(
        id: 'b',
        title: 'B',
        artist: 'Guest',
        album: 'Other',
        localPath: '/b',
      );
      final c = MediaItem(id: 'c', title: 'C', localPath: '/c');
      final temp = MediaItem(
        id: 'temp',
        title: 'Temporary',
        origin: 'temporary',
        localPath: '/temp',
      );
      await library.addMedia([a, b, c]);
      library.addTemporaryMedia([temp]);
      repo.saves = 0;
      await library.updateMediaMetadataBatch(
        ['a', 'b', 'a', 'missing', 'temp'],
        const MediaMetadataPatch(
          album: MetadataChange('New'),
          albumArtist: MetadataChange('Various'),
        ),
      );
      expect(repo.saves, 1);
      expect(library.state.byId('a')!.toJson(), {
        ...a.toJson(),
        'album': 'New',
        'albumArtist': 'Various',
      });
      expect(library.state.byId('b')!.toJson(), {
        ...b.toJson(),
        'album': 'New',
        'albumArtist': 'Various',
      });
      expect(library.state.byId('c')!.toJson(), c.toJson());
      expect(library.state.byId('temp')!.toJson(), temp.toJson());
      expect((await repo.loadMedia()).map((m) => m.id), ['a', 'b', 'c']);
      await library.updateMediaMetadataBatch([
        'a',
      ], const MediaMetadataPatch(album: MetadataChange(null)));
      expect(library.state.byId('a')!.album, isNull);
      expect(library.state.byId('a')!.albumArtist, 'Various');
    },
  );

  test('empty patches and unavailable selections do not write', () async {
    final repo = _Repository();
    final library = LibraryNotifier(repo);
    addTearDown(library.dispose);
    await library.updateMediaMetadataBatch([
      'missing',
    ], const MediaMetadataPatch(album: MetadataChange('Album')));
    await library.updateMediaMetadataBatch([], const MediaMetadataPatch());
    expect(repo.saves, 0);
  });

  test(
    'failed batch save restores visible metadata and can be retried',
    () async {
      final repo = _Repository();
      final library = LibraryNotifier(repo);
      addTearDown(library.dispose);
      await library.addMedia([
        MediaItem(id: 'a', title: 'A', album: 'Old', localPath: '/a'),
      ]);
      repo.reject = true;
      const patch = MediaMetadataPatch(album: MetadataChange('New'));
      await expectLater(
        library.updateMediaMetadataBatch(['a'], patch),
        throwsStateError,
      );
      expect(library.state.byId('a')!.album, 'Old');
      repo.reject = false;
      await library.updateMediaMetadataBatch(['a'], patch);
      expect((await repo.loadMedia()).single.album, 'New');
    },
  );
  test(
    'numbering uses requested order with no gaps for duplicate or unavailable IDs',
    () async {
      final repo = _Repository();
      final library = LibraryNotifier(repo);
      addTearDown(library.dispose);
      await library.addMedia([
        MediaItem(id: 'a', title: 'A', localPath: '/a', trackNumber: 10),
        MediaItem(id: 'b', title: 'B', localPath: '/b', trackNumber: 20),
        MediaItem(id: 'c', title: 'C', localPath: '/c', trackNumber: 30),
      ]);
      library.addTemporaryMedia([
        MediaItem(
          id: 'temp',
          title: 'Temp',
          localPath: '/temp',
          origin: 'temporary',
        ),
      ]);
      repo.saves = 0;
      await library.updateMediaMetadataBatch(
        ['b', 'missing', 'temp', 'a', 'b'],
        const MediaMetadataPatch(
          discNumber: MetadataChange(2),
          trackNumberStart: 5,
        ),
      );
      expect(repo.saves, 1);
      expect(library.state.byId('b')!.trackNumber, 5);
      expect(library.state.byId('a')!.trackNumber, 6);
      expect(library.state.byId('a')!.discNumber, 2);
      expect(library.state.byId('c')!.trackNumber, 30);
      expect(library.state.byId('c')!.discNumber, isNull);
      expect(library.state.byId('temp')!.trackNumber, isNull);
      await library.updateMediaMetadataBatch([
        'a',
      ], const MediaMetadataPatch(discNumber: MetadataChange(null)));
      expect(library.state.byId('a')!.discNumber, isNull);
      expect(library.state.byId('a')!.trackNumber, 6);
    },
  );

  test(
    'invalid numbering is rejected before any state change or save',
    () async {
      final repo = _Repository();
      final library = LibraryNotifier(repo);
      addTearDown(library.dispose);
      await library.addMedia([MediaItem(id: 'a', title: 'A', localPath: '/a')]);
      repo.saves = 0;
      await expectLater(
        library.updateMediaMetadataBatch([
          'a',
        ], const MediaMetadataPatch(trackNumberStart: 0)),
        throwsArgumentError,
      );
      await expectLater(
        library.updateMediaMetadataBatch([
          'a',
        ], const MediaMetadataPatch(discNumber: MetadataChange(-1))),
        throwsArgumentError,
      );
      expect(repo.saves, 0);
      expect(library.state.byId('a')!.discNumber, isNull);
      expect(library.state.byId('a')!.trackNumber, isNull);
    },
  );
}
