import 'dart:convert';
import '../domain/models.dart';
import '../domain/creator_names.dart';

enum CollectionKind { albums, artists }

class MediaCollection {
  MediaCollection({
    required this.id,
    required this.name,
    required this.artist,
    required List<MediaItem> items,
  }) : items = List.unmodifiable(items);
  final String id;
  final String? name;
  final String? artist;
  final List<MediaItem> items;
}

String _normalize(String? text) => (text ?? '').trim().toLowerCase();
String? _clean(String? text) =>
    (text ?? '').trim().isEmpty ? null : text!.trim();

/// Album artist disambiguates identically named albums and unifies guest credits.
/// Temporary media never participates in the saved-library browser.
List<MediaCollection> buildMediaCollections(
  Iterable<MediaItem> media,
  CollectionKind kind,
) {
  final groups = <String, List<MediaItem>>{};
  final names = <String, (String?, String?)>{};
  for (final item in media.where((item) => !item.isTemporary)) {
    if (kind == CollectionKind.albums) {
      final album = _clean(item.album);
      final artist = _clean(item.albumArtist) ?? _clean(item.artist);
      final id = jsonEncode([_normalize(album), _normalize(artist)]);
      groups.putIfAbsent(id, () => []).add(item);
      names[id] = (album, artist);
    } else {
      final namesForItem = splitCreatorNames(item.artist);
      final artists = namesForItem.isEmpty ? <String?>[null] : namesForItem;
      final seen = <String>{};
      for (final artist in artists) {
        final id = _normalize(artist);
        if (!seen.add(id)) continue;
        groups.putIfAbsent(id, () => []).add(item);
        names[id] = (artist, null);
      }
    }
  }
  final result = groups.entries.map((entry) {
    final items = entry.value;
    items.sort((a, b) {
      if (kind == CollectionKind.albums) {
        final disc = (a.discNumber ?? 1).compareTo(b.discNumber ?? 1);
        if (disc != 0) return disc;
        final number = (a.trackNumber ?? 0x7fffffff).compareTo(
          b.trackNumber ?? 0x7fffffff,
        );
        if (number != 0) return number;
      }
      final title = _normalize(a.title).compareTo(_normalize(b.title));
      return title != 0 ? title : a.id.compareTo(b.id);
    });
    final labels = names[entry.key]!;
    return MediaCollection(
      id: entry.key,
      name: labels.$1,
      artist: labels.$2,
      items: items,
    );
  }).toList();
  result.sort((a, b) {
    if (a.name == null && b.name != null) return 1;
    if (a.name != null && b.name == null) return -1;
    final name = _normalize(a.name).compareTo(_normalize(b.name));
    return name != 0 ? name : a.id.compareTo(b.id);
  });
  return result;
}
