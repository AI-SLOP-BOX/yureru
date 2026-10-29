import 'package:flutter_test/flutter_test.dart';
import 'package:yureru/domain/models.dart';

void main() {
  test(
    'old libraries default to non-favorite and favorite values round-trip',
    () {
      final legacy = MediaItem.fromJson({
        'id': 'old',
        'title': 'Old',
        'localPath': '/old.mp3',
      });
      expect(legacy.isFavorite, isFalse);
      final favorite = legacy.copyWith(isFavorite: true);
      expect(MediaItem.fromJson(favorite.toJson()).isFavorite, isTrue);
      expect(favorite.copyWith(isFavorite: false).isFavorite, isFalse);
    },
  );

  test('media copies preserve every serialized field and identity', () {
    final item = MediaItem(
      id: 'track',
      title: 'Title',
      isFavorite: true,
      lastPlayedAt: DateTime.utc(2026, 10, 1),
      artist: 'Artist',
      localPath: '/track.mp3',
      durationMs: 1000,
      createdAt: DateTime.utc(2026),
      origin: 'referenced',
      sourceFolderId: 'folder',
      sourcePath: '/source.mp3',
      artworkPath: '/art.jpg',
      thumbnailPath: '/thumb.jpg',
      lyricsPath: '/lyrics.lrc',
      lyricsOffsetMs: 50,
    );
    expect(item.copyWith().toJson(), item.toJson());
    expect(item.copyWith(title: 'New').toJson(), {
      ...item.toJson(),
      'title': 'New',
    });

    final cleared = item.copyWith(
      artist: null,
      durationMs: null,
      sourceFolderId: null,
      sourcePath: null,
      artworkPath: null,
      thumbnailPath: null,
      lyricsPath: null,
      lyricsOffsetMs: 0,
    );
    expect(cleared.toJson(), {
      ...item.toJson(),
      'artist': null,
      'durationMs': null,
      'sourceFolderId': null,
      'sourcePath': null,
      'artworkPath': null,
      'thumbnailPath': null,
      'lyricsPath': null,
      'lyricsOffsetMs': 0,
    });
    expect(item.artist, 'Artist');
    expect(item.preferredImagePath, '/art.jpg');
    expect(item.copyWith(artworkPath: null).preferredImagePath, '/thumb.jpg');
  });

  test(
    'playlist copies preserve identity and own their ordered media list',
    () {
      final item = Playlist(name: 'Old', mediaIds: ['a', 'b']);
      final ids = ['b', 'a'];
      final updated = item.copyWith(name: 'New', mediaIds: ids);
      ids.clear();
      expect(updated.toJson(), {
        ...item.toJson(),
        'name': 'New',
        'mediaIds': ['b', 'a'],
      });
      expect(() => updated.mediaIds.add('c'), throwsUnsupportedError);
      expect(item.mediaIds, ['a', 'b']);
    },
  );

  test('playlist image priority round-trips and can return to default', () {
    final playlist = Playlist(
      id: 'mix',
      name: 'Mix',
      imagePriority: 'artworkFirst',
    );
    expect(Playlist.fromJson(playlist.toJson()).imagePriority, 'artworkFirst');
    expect(playlist.copyWith(imagePriority: null).imagePriority, isNull);
  });
}
