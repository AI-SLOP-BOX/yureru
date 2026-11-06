import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ambient/video_lyrics_settings.dart';
import '../../data/lyrics.dart';
import '../../domain/models.dart';
import '../../playback/playback_engine.dart';

class VideoLyricsOverlay extends ConsumerStatefulWidget {
  const VideoLyricsOverlay({
    super.key,
    required this.media,
    required this.engine,
    required this.settings,
  });

  final MediaItem media;
  final PlaybackEngine engine;
  final VideoLyricsSettings settings;

  @override
  ConsumerState<VideoLyricsOverlay> createState() => _VideoLyricsOverlayState();
}

class _VideoLyricsOverlayState extends ConsumerState<VideoLyricsOverlay> {
  late Future<List<LyricLine>> _lyricsFuture;

  @override
  void initState() {
    super.initState();
    _lyricsFuture = _loadLyrics();
  }

  @override
  void didUpdateWidget(VideoLyricsOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.media.id != widget.media.id ||
        oldWidget.media.lyricsPath != widget.media.lyricsPath ||
        oldWidget.media.videoLyricsPath != widget.media.videoLyricsPath ||
        oldWidget.media.artworkLyricsPath != widget.media.artworkLyricsPath) {
      _lyricsFuture = _loadLyrics();
    }
  }

  Future<List<LyricLine>> _loadLyrics() async {
    var path = widget.media.lyricsPathForView(artwork: false);
    if (path == null || !await File(path).exists()) {
      path = widget.media.localPath.replaceFirst(
        RegExp(r'\.[^./\\]+$'),
        '.lrc',
      );
    }
    if (await File(path).exists()) {
      final lines = parseLrc(await File(path).readAsString());
      if (lines.isNotEmpty) return lines;
    }
    final embedded = await widget.engine.readEmbeddedLyrics();
    return parseLrc(embedded ?? '');
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    if (!settings.enabled || widget.media.lyricsButtonHidden) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<List<LyricLine>>(
      future: _lyricsFuture,
      builder: (context, lyricsSnapshot) {
        final lines = lyricsSnapshot.data;
        if (lines == null || lines.isEmpty) return const SizedBox.shrink();
        return StreamBuilder<PlaybackSnapshot>(
          stream: widget.engine.snapshots,
          initialData: widget.engine.snapshot,
          builder: (context, playbackSnapshot) {
            final active = activeLyricIndex(
              lines,
              playbackSnapshot.data?.position ?? Duration.zero,
              offset: Duration(
                milliseconds: widget.media.lyricsOffsetForView(artwork: false),
              ),
            );
            if (active < 0 || active >= lines.length) {
              return const SizedBox.shrink();
            }
            final lyric = lines[active].text.trim();
            if (lyric.isEmpty) return const SizedBox.shrink();
            final text = Text(
              lyric,
              textAlign: TextAlign.center,
              softWrap: true,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Color(settings.color),
                fontSize: settings.fontSize,
                fontFamily: switch (settings.fontFamily) {
                  'serif' => 'serif',
                  'monospace' => 'monospace',
                  _ => null,
                },
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            );
            Widget framed = switch (settings.frame) {
              VideoLyricsFrame.none => text,
              VideoLyricsFrame.plate => Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.58),
                  border: Border.all(color: Colors.white38),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: text,
              ),
              VideoLyricsFrame.outline => Stack(
                children: [
                  Text(
                    lyric,
                    textAlign: TextAlign.center,
                    softWrap: true,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      foreground: Paint()
                        ..style = PaintingStyle.stroke
                        ..strokeWidth = 3.5
                        ..color = Colors.black,
                      fontSize: settings.fontSize,
                      fontFamily: settings.fontFamily == 'system'
                          ? null
                          : settings.fontFamily,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  text,
                ],
              ),
            };
            return IgnorePointer(
              child: Align(
                alignment: Alignment(
                  settings.positionX * 2 - 1,
                  settings.positionY * 2 - 1,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 20,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: framed,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
