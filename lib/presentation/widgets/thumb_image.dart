import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_state.dart';
import '../../data/thumbnails.dart';
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
  final MediaImageContext? imageContext;

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
    this.imageContext,
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
      _future = ThumbnailService.forMedia(
        mediaId: id,
        localPath: path,
        highRes: widget.highRes,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = _future;
    final priorities = ref.watch(mediaImagePriorityProvider);
    final priority = widget.imageContext == null
        ? null
        : priorities[widget.imageContext!];
    final preferArtwork = priority == null
        ? widget.useArtwork
        : priority == MediaImagePriority.artworkFirst;
    final imagePath = widget.mediaId == null
        ? null
        : ref.watch(
            libraryProvider.select((lib) {
              final media = lib.byId(widget.mediaId!);
              if (media == null) return null;
              return preferArtwork
                  ? media.artworkPath ?? media.thumbnailPath
                  : media.thumbnailPath;
            }),
          );
    final fallback = ThumbBox(
      seed: widget.seed,
      size: widget.size,
      radius: widget.radius,
      expand: widget.expand,
    );
    if (imagePath != null) {
      final art = Image.file(
        File(imagePath),
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
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
}
