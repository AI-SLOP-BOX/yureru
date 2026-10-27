import 'package:flutter_test/flutter_test.dart';
import 'package:yureru/domain/models.dart';
import 'package:yureru/library/media_collections.dart';

MediaItem item(
  String id, {
  String? album,
  String? artist,
  String? albumArtist,
  int? trackNumber,
  String origin = 'imported',
}) => MediaItem(
  id: id,
  title: id,
  localPath: '/$id.mp3',
  album: album,
  artist: artist,
  albumArtist: albumArtist,
  trackNumber: trackNumber,
  origin: origin,
);

void main() {
  test(
    'old data loads and copies preserve or explicitly clear collection metadata',
    () {
      final old = MediaItem.fromJson({
        'id': 'old',
        'title': 'Old',
        'localPath': '/old',
      });
      expect(old.album, isNull);
      final edited = old.copyWith(
        album: 'Album',
        albumArtist: 'Artist',
        trackNumber: 4,
      );
      final restored = MediaItem.fromJson(
        edited.toJson(),
      ).copyWith(isFavorite: true);
      expect(restored.album, 'Album');
      expect(restored.albumArtist, 'Artist');
      expect(restored.trackNumber, 4);
      expect(restored.id, old.id);
      expect(restored.createdAt, old.createdAt);
      final cleared = restored.copyWith(
        album: null,
        albumArtist: null,
        trackNumber: null,
      );
      expect(cleared.album, isNull);
      expect(cleared.albumArtist, isNull);
      expect(cleared.trackNumber, isNull);
    },
  );

  test(
    'album identity separates artists and album artist unifies guest credits',
    () {
      final groups = buildMediaCollections([
        item('z', album: 'Album', artist: 'Main', trackNumber: 2),
        item(
          'a',
          album: ' Album ',
          artist: 'Main / Guest',
          albumArtist: 'main',
          trackNumber: 1,
        ),
        item('b', album: 'Album', artist: 'Other'),
        item('c', artist: 'Main'),
        item('temp', album: 'Temp', origin: 'temporary'),
      ], CollectionKind.albums);
      expect(groups.length, 3);
      expect(
        groups.firstWhere((g) => g.items.length == 2).items.map((m) => m.id),
        ['a', 'z'],
      );
      expect(groups.last.name, isNull);
    },
  );

  test('artist collections include collaborations once and unknown artist', () {
    final groups = buildMediaCollections([
      item('a', artist: 'Main / Guest / main'),
      item('b', artist: ' Main '),
      item('c'),
    ], CollectionKind.artists);
    expect(groups.length, 3);
    final main = groups.firstWhere((g) => g.id == 'main');
    expect(main.items.map((m) => m.id), ['a', 'b']);
    expect(groups.firstWhere((g) => g.id == 'guest').items.single.id, 'a');
    expect(groups.last.name, isNull);
  });
  test('disc values round-trip, preserve on edits and can be cleared', () {
    final original = item('a').copyWith(discNumber: 2);
    final restored = MediaItem.fromJson(original.toJson());
    expect(restored.copyWith(title: 'Edited').discNumber, 2);
    expect(restored.copyWith(discNumber: null).discNumber, isNull);
    expect(
      MediaItem.fromJson({'id': 'old', 'localPath': '/old'}).discNumber,
      isNull,
    );
  });

  test('album order is disc then track, missing disc is disc one', () {
    final groups = buildMediaCollections([
      item('two', album: 'A', trackNumber: 1).copyWith(discNumber: 2),
      item('unnumbered', album: 'A'),
      item('first', album: 'A', trackNumber: 1),
      item('second', album: 'A', trackNumber: 2).copyWith(discNumber: 1),
    ], CollectionKind.albums);
    expect(groups.single.items.map((m) => m.id), [
      'first',
      'second',
      'unnumbered',
      'two',
    ]);
  });
}
