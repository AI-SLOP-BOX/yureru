import '../domain/models.dart';

/// A missing change preserves a field; a present null explicitly clears it.
class MetadataChange<T> {
  const MetadataChange(this.value);
  final T value;
}

class MediaMetadataPatch {
  const MediaMetadataPatch({
    this.album,
    this.albumArtist,
    this.artist,
    this.discNumber,
    this.trackNumberStart,
  });
  final MetadataChange<String?>? album;
  final MetadataChange<String?>? albumArtist;
  final MetadataChange<String?>? artist;
  final MetadataChange<int?>? discNumber;
  final int? trackNumberStart;
  bool get isEmpty =>
      album == null &&
      albumArtist == null &&
      artist == null &&
      discNumber == null &&
      trackNumberStart == null;

  void validate() {
    if (trackNumberStart != null && trackNumberStart! < 1) {
      throw ArgumentError.value(trackNumberStart);
    }
    if (discNumber?.value != null && discNumber!.value! < 1) {
      throw ArgumentError.value(discNumber!.value);
    }
  }

  MediaItem apply(MediaItem item, {int index = 0}) {
    var result = item;
    if (album != null) result = result.copyWith(album: album!.value);
    if (albumArtist != null) {
      result = result.copyWith(albumArtist: albumArtist!.value);
    }
    if (artist != null) result = result.copyWith(artist: artist!.value);
    if (discNumber != null) {
      result = result.copyWith(discNumber: discNumber!.value);
    }
    if (trackNumberStart != null) {
      result = result.copyWith(trackNumber: trackNumberStart! + index);
    }
    return result;
  }
}
