import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../domain/models.dart';

/// Persistence behind an abstract repository so sqlite/drift can replace it.
abstract class LibraryRepository {
  Future<List<MediaItem>> loadMedia();
  Future<void> saveMedia(List<MediaItem> items);
  Future<List<Playlist>> loadPlaylists();
  Future<void> savePlaylists(List<Playlist> items);
}

class PrefsLibraryRepository implements LibraryRepository {
  static const _kMedia = 'yureru.media.v1';
  static const _kPlaylists = 'yureru.playlists.v1';
  @override
  Future<List<MediaItem>> loadMedia() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kMedia);
      if (raw == null) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final result = <MediaItem>[];
      for (final e in decoded) {
        if (e is Map) {
          try {
            final item = MediaItem.fromJson(Map<String, dynamic>.from(e));
            if (item.localPath.isNotEmpty) result.add(item);
          } catch (_) {
            // Skip single corrupt entry rather than discarding the entire library
          }
        }
      }
      return result;
    } catch (_) {
      return [];
    }
  }
  @override
  Future<void> saveMedia(List<MediaItem> items) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kMedia, jsonEncode(items.map((e) => e.toJson()).toList()));
  }
  @override
  Future<List<Playlist>> loadPlaylists() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kPlaylists);
      if (raw == null) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      final result = <Playlist>[];
      for (final e in decoded) {
        if (e is Map) {
          try {
            result.add(Playlist.fromJson(Map<String, dynamic>.from(e)));
          } catch (_) {
            // Skip corrupt playlist entry
          }
        }
      }
      return result;
    } catch (_) {
      return [];
    }
  }
  @override
  Future<void> savePlaylists(List<Playlist> items) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kPlaylists, jsonEncode(items.map((e) => e.toJson()).toList()));
  }
}

/// In-memory fake for tests.
class InMemoryLibraryRepository implements LibraryRepository {
  List<MediaItem> media = [];
  List<Playlist> playlists = [];
  @override
  Future<List<MediaItem>> loadMedia() async => List.of(media);
  @override
  Future<void> saveMedia(List<MediaItem> items) async { media = List.of(items); }
  @override
  Future<List<Playlist>> loadPlaylists() async => List.of(playlists);
  @override
  Future<void> savePlaylists(List<Playlist> items) async { playlists = List.of(items); }
}
