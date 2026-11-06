import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_state.dart';
import '../../data/thumbnails.dart';
import '../../domain/models.dart';
import '../theme.dart';

/// Video thumbnail with gradient fallback: shows [ThumbBox] while loading
/// and whenever generation fails (missing file, unsupported platform,
/// corrupt video). The Future is pinned per media id so list rebuilds
/// (e.g. position ticks) don't refire disk checks.
class ThumbImage extends ConsumerStatefulWidget {
  final String seed;
  final String? mediaId;
  final String? localPath;
  final double size;
  final double radius;

  /// When true, fills the parent instead of using [size] (e.g. card hero).
  final bool expand;
  final bool highRes;
  final bool useArtwork;
  final bool forceArtwork;
  final MediaImageContext? imageContext;
  final String? playlistId;

  /// Treat this image as the playlist's cover (custom image or collage).
  /// Playlist members pass [playlistId] only to inherit image priority.
  final bool playlistCover;
  final bool enablePlaylistCollage;

  const ThumbImage({
    super.key,
    required this.seed,
    this.mediaId,
    this.localPath,
    this.size = 44,
    this.radius = 8,
    this.expand = false,
    this.highRes = false,
    this.useArtwork = true,
    this.forceArtwork = false,
    this.imageContext,
    this.playlistId,
    this.playlistCover = false,
    this.enablePlaylistCollage = true,
  });

  @override
  ConsumerState<ThumbImage> createState() => _ThumbImageState();
}

class _ThumbImageState extends ConsumerState<ThumbImage> {
  Future<File?>? _future;
  String? _key;

  @override
  void initState() {
    super.initState();
    _pin();
  }

  @override
  void didUpdateWidget(ThumbImage old) {
    super.didUpdateWidget(old);
    if (old.mediaId != widget.mediaId ||
        old.localPath != widget.localPath ||
        old.highRes != widget.highRes) {
      _pin();
    }
  }

  void _pin() {
    final id = widget.mediaId;
    final path = widget.localPath;
    _key = widget.highRes ? '$id@hi' : id;
    if (id == null || path == null) {
      _future = null;
    } else {
      _future = _loadThumbnail(id, path, highRes: widget.highRes);
    }
  }

  Future<File?> _loadThumbnail(
    String mediaId,
    String localPath, {
    required bool highRes,
  }) async {
    final image = await ThumbnailService.forMedia(
      mediaId: mediaId,
      localPath: localPath,
      highRes: highRes,
    );
    if (image != null || !highRes) return image;
    // Large player artwork requests can fail for a codec even though the
    // regular thumbnail is already cached and displayed elsewhere.
    return ThumbnailService.forMedia(
      mediaId: mediaId,
      localPath: localPath,
      highRes: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final f = _future;
    final priorities = ref.watch(mediaImagePriorityProvider);
    final imagePaths = widget.mediaId == null
        ? null
        : ref.watch(
            libraryProvider.select((lib) {
              final playlistChoice = widget.playlistId == null
                  ? null
                  : lib.playlistById(widget.playlistId!)?.imagePriority;
              final media = lib.byId(widget.mediaId!);
              if (media == null) return null;
              // The player's explicit image mode means show the jacket even
              // when Home is configured to prefer video thumbnails.
              if (widget.forceArtwork) {
                return (
                  media.artworkPath ?? media.thumbnailPath,
                  media.artworkPath == null ? null : media.thumbnailPath,
                );
              }
              // Unscoped surfaces (player chrome, search, queue, etc.) follow
              // the Home preference. Historically they bypassed settings and
              // showed jacket art by default.
              final effectivePriority = effectiveMediaImagePriority(
                priorities: priorities,
                imageContext: widget.imageContext,
                playlistPriority: playlistChoice,
                useArtwork: widget.useArtwork,
              );
              final preferArtwork =
                  effectivePriority == MediaImagePriority.artworkFirst;
              return (
                preferArtwork
                    ? media.artworkPath ?? media.thumbnailPath
                    : media.thumbnailPath,
                null,
              );
            }),
          );
    final playlistArtworkPath =
        widget.playlistId == null || !widget.playlistCover
        ? null
        : ref.watch(
            libraryProvider.select(
              (lib) => lib.playlistById(widget.playlistId!)?.artworkPath,
            ),
          );
    final playlistMedia =
        widget.playlistId == null ||
            !widget.playlistCover ||
            !widget.enablePlaylistCollage
        ? const <MediaItem>[]
        : ref.watch(
            libraryProvider.select((lib) {
              final playlist = lib.playlistById(widget.playlistId!);
              if (playlist == null) return const <MediaItem>[];
              final uniqueMedia = <String, MediaItem>{};
              for (final id in playlist.mediaIds) {
                final item = lib.byId(id);
                if (item != null) uniqueMedia.putIfAbsent(id, () => item);
              }
              final topPlayed = uniqueMedia.values.toList()
                ..sort((a, b) {
                  final byScore = b.recommendationScore.compareTo(
                    a.recommendationScore,
                  );
                  return byScore != 0 ? byScore : a.id.compareTo(b.id);
                });
              return topPlayed.take(4).toList(growable: false);
            }),
          );
    final imagePath = playlistArtworkPath ?? imagePaths?.$1;
    final secondaryImagePath = imagePaths?.$2;
    final fallback = ThumbBox(
      seed: widget.seed,
      size: widget.size,
      radius: widget.radius,
      expand: widget.expand,
    );
    if (playlistArtworkPath == null && playlistMedia.isNotEmpty) {
      return _playlistCollage(context, playlistMedia);
    }
    if (imagePath != null) {
      final art = Image.file(
        File(imagePath),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) {
          if (widget.forceArtwork &&
              secondaryImagePath != null &&
              secondaryImagePath != imagePath) {
            return Image.file(
              File(secondaryImagePath),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => fallback,
            );
          }
          return fallback;
        },
      );
      return ClipRRect(
        borderRadius: BorderRadius.circular(widget.radius),
        child: widget.expand
            ? SizedBox.expand(child: art)
            : SizedBox(width: widget.size, height: widget.size, child: art),
      );
    }
    if (f == null) {
      return fallback;
    }
    return FutureBuilder<File?>(
      future: f,
      builder: (c, snap) {
        final file = snap.data;
        if (file == null) {
          return fallback;
        }
        final img = Image.file(
          file,
          key: ValueKey(_key),
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback,
        );
        if (widget.expand) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(widget.radius),
            child: SizedBox.expand(child: img),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(widget.radius),
          child: SizedBox(width: widget.size, height: widget.size, child: img),
        );
      },
    );
  }

  Widget _playlistCollage(BuildContext context, List<MediaItem> media) {
    Widget tile(MediaItem item) => ThumbImage(
      seed: item.id,
      mediaId: item.id,
      localPath: item.localPath,
      size: widget.size / 2,
      radius: 0,
      expand: true,
      imageContext: MediaImageContext.playlist,
      playlistId: widget.playlistId,
      enablePlaylistCollage: false,
    );

    final gap = (widget.size * 0.006).clamp(1.0, 2.0);
    final firstRow = Row(
      children: [
        Expanded(child: tile(media[0])),
        if (media.length > 1) ...[
          SizedBox(width: gap),
          Expanded(child: tile(media[1])),
        ],
      ],
    );
    final Widget collage;
    if (media.length == 1) {
      collage = tile(media.first);
    } else if (media.length == 2) {
      collage = firstRow;
    } else {
      collage = Column(
        children: [
          Expanded(child: firstRow),
          SizedBox(height: gap),
          Expanded(
            child: Row(
              children: [
                Expanded(child: tile(media[2])),
                if (media.length > 3) ...[
                  SizedBox(width: gap),
                  Expanded(child: tile(media[3])),
                ],
              ],
            ),
          ),
        ],
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: widget.expand
          ? SizedBox.expand(child: collage)
          : SizedBox(width: widget.size, height: widget.size, child: collage),
    );
  }
}
