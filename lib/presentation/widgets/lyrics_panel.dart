import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../app_state.dart';
import '../../data/lyrics.dart';
import '../../domain/creator_names.dart';
import '../../domain/models.dart';
import '../../playback/playback_engine.dart';
import '../i18n.dart';
import '../theme.dart';
import 'lyrics_editor_dialog.dart';

/// Lyrics content hosted inside QueuePanel, alongside the upcoming queue.
class LyricsPanel extends ConsumerStatefulWidget {
  const LyricsPanel({
    super.key,
    required this.engine,
    required this.media,
    this.immersive = false,
    this.onEditingChanged,
  });

  final PlaybackEngine engine;
  final MediaItem media;
  final bool immersive;
  final ValueChanged<bool>? onEditingChanged;

  double get lineHeight => immersive ? 100 : 76;

  @override
  ConsumerState<LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends ConsumerState<LyricsPanel> {
  final ScrollController _scrollController = ScrollController();
  late Future<_LyricsSource> _source;
  int _lastActive = -2;
  bool _editing = false;
  String _editorText = '';
  bool _editorSynchronized = true;

  @override
  void initState() {
    super.initState();
    _source = _loadSource();
  }

  @override
  void didUpdateWidget(LyricsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.media.id != widget.media.id ||
        oldWidget.media.lyricsPath != widget.media.lyricsPath) {
      _lastActive = -2;
      _editing = false;
      _source = _loadSource();
    }
  }

  Future<_LyricsSource> _loadSource() async {
    var path = widget.media.lyricsPath;
    if (path != null && !await File(path).exists()) path = null;
    if (path == null) {
      final sibling = widget.media.localPath.replaceFirst(
        RegExp(r'\.[^./\\]+$'),
        '.lrc',
      );
      if (await File(sibling).exists()) path = sibling;
    }
    if (path == null) {
      final sibling = widget.media.localPath.replaceFirst(
        RegExp(r'\.[^./\\]+$'),
        '.txt',
      );
      if (await File(sibling).exists()) path = sibling;
    }
    if (path != null) return _LyricsSource(path: path);
    return _LyricsSource(embedded: await widget.engine.readEmbeddedLyrics());
  }

  Future<void> _chooseLyrics() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['lrc', 'txt'],
      allowMultiple: false,
      withData: false,
    );
    final sourcePath = result?.files.single.path;
    if (sourcePath == null) return;
    try {
      final support = await getApplicationSupportDirectory();
      final directory = Directory('${support.path}/yureru_lyrics');
      await directory.create(recursive: true);
      final extension = sourcePath.toLowerCase().endsWith('.lrc')
          ? 'lrc'
          : 'txt';
      final destination =
          '${directory.path}/${widget.media.id}_${DateTime.now().microsecondsSinceEpoch}.$extension';
      await File(sourcePath).copy(destination);
      await ref
          .read(libraryProvider.notifier)
          .updateMediaLyrics(widget.media.id, destination);
      if (!mounted) return;
      setState(() {
        _source = Future.value(_LyricsSource(path: destination));
        _lastActive = -2;
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${ref.tr('lyrics_load_error')}: $error')),
      );
    }
  }

  Future<void> _editLyrics() async {
    final source = await _source;
    final initialText = await source.text;
    if (!mounted) return;
    setState(() {
      _editorText = initialText;
      _editorSynchronized =
          source.path?.toLowerCase().endsWith('.lrc') ??
          parseLrc(initialText).isNotEmpty;
      _editing = true;
    });
    widget.onEditingChanged?.call(true);
  }

  Future<void> _saveEditedLyrics(String path) async {
    await ref
        .read(libraryProvider.notifier)
        .updateMediaLyrics(widget.media.id, path);
    if (!mounted) return;
    setState(() {
      _source = Future.value(_LyricsSource(path: path));
      _lastActive = -2;
      _editing = false;
    });
    widget.onEditingChanged?.call(false);
  }

  Widget _editor() => LyricsEditorDialog(
    media: widget.media,
    engine: widget.engine,
    initialText: _editorText,
    initialSynchronized: _editorSynchronized,
    inline: true,
    onCancel: () {
      setState(() => _editing = false);
      widget.onEditingChanged?.call(false);
    },
    onSaved: _saveEditedLyrics,
  );

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollTo(int active) {
    if (active < 0 || active == _lastActive || !_scrollController.hasClients) {
      return;
    }
    _lastActive = active;
    final target =
        (active * widget.lineHeight -
                (widget.immersive
                    ? _scrollController.position.viewportDimension * 0.3
                    : 0))
            .clamp(0.0, _scrollController.position.maxScrollExtent);
    if (!mounted) return;
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentMedia =
        ref.watch(libraryProvider).byId(widget.media.id) ?? widget.media;
    final title = displayTitle(widget.media.title);
    final textPrimary = themeTextPrimary(context);
    final textSub = themeTextSub(context);
    return Column(
      children: [
        if (!widget.immersive)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (title.isNotEmpty)
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      if (widget.media.artist?.trim().isNotEmpty == true)
                        Text(
                          formatCreatorNames(widget.media.artist),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: textSub, fontSize: 12),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (!widget.immersive) Divider(height: 1, color: themeBorder(context)),
        Expanded(
          child: _editing
              ? _editor()
              : FutureBuilder<_LyricsSource>(
                  future: _source,
                  builder: (context, sourceSnapshot) {
                    if (sourceSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(
                        child: SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }
                    final source = sourceSnapshot.data;
                    if (source == null) {
                      return _emptyLyrics(context, ref.tr('lyrics_load_error'));
                    }
                    if (source.path == null &&
                        source.embedded?.trim().isNotEmpty != true) {
                      return _emptyLyrics(context, ref.tr('lyrics_not_found'));
                    }
                    return FutureBuilder<String>(
                      future: source.text,
                      builder: (context, lyricsSnapshot) {
                        if (lyricsSnapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: SizedBox.square(
                              dimension: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        }
                        final text = lyricsSnapshot.data ?? '';
                        final lines = parseLrc(text);
                        if (lyricsSnapshot.hasError || lines.isEmpty) {
                          if (!lyricsSnapshot.hasError &&
                              text.trim().isNotEmpty) {
                            return SingleChildScrollView(
                              padding: const EdgeInsets.all(20),
                              child: Text(
                                text,
                                style: TextStyle(
                                  color: textPrimary,
                                  fontSize: 14,
                                  height: 1.6,
                                ),
                              ),
                            );
                          }
                          return _emptyLyrics(
                            context,
                            lyricsSnapshot.hasError
                                ? ref.tr('lyrics_load_error')
                                : ref.tr('synced_lyrics_not_found'),
                          );
                        }
                        return StreamBuilder<PlaybackSnapshot>(
                          stream: widget.engine.snapshots,
                          initialData: widget.engine.snapshot,
                          builder: (context, playback) {
                            final active = activeLyricIndex(
                              lines,
                              playback.data?.position ?? Duration.zero,
                              offset: Duration(
                                milliseconds: currentMedia.lyricsOffsetMs,
                              ),
                            );
                            WidgetsBinding.instance.addPostFrameCallback(
                              (_) => _scrollTo(active),
                            );
                            return ListView.builder(
                              controller: _scrollController,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 12,
                              ),
                              itemCount: lines.length,
                              itemBuilder: (context, index) {
                                final isActive = index == active;
                                return SizedBox(
                                  height: widget.lineHeight,
                                  child: InkWell(
                                    onTap: () =>
                                        widget.engine.seekTo(lines[index].time),
                                    borderRadius: BorderRadius.circular(8),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: AnimatedDefaultTextStyle(
                                        duration: const Duration(
                                          milliseconds: 180,
                                        ),
                                        style: TextStyle(
                                          color: isActive
                                              ? textPrimary
                                              : textSub.withValues(
                                                  alpha:
                                                      (index - active).abs() < 3
                                                      ? 0.7
                                                      : 0.42,
                                                ),
                                          fontSize: widget.immersive
                                              ? (isActive ? 30 : 26)
                                              : (isActive ? 18 : 15),
                                          fontWeight: isActive
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                        ),
                                        child: Text(
                                          lines[index].text,
                                          maxLines: widget.immersive ? 2 : 3,
                                          softWrap: true,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _emptyLyrics(BuildContext context, String message) => Center(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lyrics_outlined, size: 34, color: themeTextSub(context)),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: themeTextSub(context), fontSize: 13),
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: [
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: widget.immersive
                      ? Colors.white70
                      : themeTextPrimary(context),
                  backgroundColor: widget.immersive
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.transparent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                      color: widget.immersive
                          ? Colors.white.withValues(alpha: 0.12)
                          : themeBorder(context),
                    ),
                  ),
                ),
                onPressed: _chooseLyrics,
                icon: const Icon(Icons.file_open_rounded, size: 18),
                label: Text(ref.tr('add_lrc')),
              ),
              TextButton.icon(
                onPressed: _editLyrics,
                icon: const Icon(Icons.edit_note_rounded, size: 18),
                label: Text(ref.tr('lyrics_editor_create')),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _LyricsSource {
  _LyricsSource({this.path, this.embedded});
  final String? path;
  final String? embedded;
  late final Future<String> text = path == null
      ? Future.value(embedded ?? '')
      : File(path!).readAsString();
}
