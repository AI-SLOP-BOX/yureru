import 'dart:io';
import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../app_state.dart';
import '../../data/lyrics.dart';
import '../../domain/models.dart';
import '../../playback/playback_engine.dart';
import '../i18n.dart';
import '../theme.dart';
import 'lyrics_editor_dialog.dart';

/// The immersive player follows lyrics as they advance, so an auto-added
/// desktop scrollbar flashes on every programmatic scroll. Keep scrolling
/// available while suppressing that scrollbar for the lyrics surface.
class _ImmersiveLyricsScrollBehavior extends MaterialScrollBehavior {
  const _ImmersiveLyricsScrollBehavior();

  @override
  bool get scrollbars => false;

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}

/// Lyrics content hosted inside QueuePanel, alongside the upcoming queue.
class LyricsPanel extends ConsumerStatefulWidget {
  const LyricsPanel({
    super.key,
    required this.engine,
    required this.media,
    this.immersive = false,
    this.viewMode = PlayerViewMode.media,
    this.onEditingChanged,
  });

  final PlaybackEngine engine;
  final MediaItem media;
  final bool immersive;
  final PlayerViewMode viewMode;
  final ValueChanged<bool>? onEditingChanged;

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
  PlayerViewMode? _editorViewMode;
  List<String> _translationLines = const [];
  bool _showTranslation = false;
  bool _editorRequestScheduled = false;

  @override
  void initState() {
    super.initState();
    _source = _loadSource();
    unawaited(_loadTranslationLines());
  }

  @override
  void didUpdateWidget(LyricsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.media.translatedLyricsPath !=
        widget.media.translatedLyricsPath) {
      _showTranslation = false;
      _translationLines = const [];
      unawaited(_loadTranslationLines());
    }
    if (oldWidget.media.id != widget.media.id) {
      _lastActive = -2;
      _editing = false;
      _editorRequestScheduled = false;
      _editorViewMode = null;
      _source = _loadSource();
    } else if (oldWidget.viewMode != widget.viewMode) {
      _lastActive = -2;
      // Keep an active editor bound to the view it started editing. Switching
      // the player view must not discard the in-progress lyrics draft.
      if (!_editing) _source = _loadSource();
    } else if (!_editing &&
        oldWidget.media.lyricsPathForView(
              artwork: oldWidget.viewMode == PlayerViewMode.image,
            ) !=
            widget.media.lyricsPathForView(
              artwork: widget.viewMode == PlayerViewMode.image,
            )) {
      _lastActive = -2;
      _source = _loadSource();
    }
  }

  Future<void> _loadTranslationLines() async {
    final path = widget.media.translatedLyricsPath;
    if (path == null) return;
    try {
      final text = await File(path).readAsString();
      final lines = path.toLowerCase().endsWith('.lrc')
          ? parseLrc(text).map((line) => line.text).toList()
          : text
                .split(RegExp(r'\r?\n'))
                .where((line) => line.isNotEmpty)
                .toList();
      if (!mounted || widget.media.translatedLyricsPath != path) return;
      setState(() => _translationLines = lines);
    } catch (_) {
      if (mounted && widget.media.translatedLyricsPath == path) {
        setState(() => _translationLines = const []);
      }
    }
  }

  void _toggleTranslation() {
    if (_translationLines.isEmpty) return;
    setState(() => _showTranslation = !_showTranslation);
  }

  Widget _lyricsScrollView(Widget child) => widget.immersive
      ? ScrollConfiguration(
          behavior: const _ImmersiveLyricsScrollBehavior(),
          child: child,
        )
      : child;

  Future<_LyricsSource> _loadSource() async {
    var path = widget.media.lyricsPathForView(
      artwork: widget.viewMode == PlayerViewMode.image,
    );
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
          .updateMediaLyricsForView(
            widget.media.id,
            artwork: widget.viewMode == PlayerViewMode.image,
            path: destination,
          );
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

  Future<void> _editLyrics({bool forceSynchronized = false}) async {
    final source = await _source;
    final initialText = await source.text;
    if (!mounted) return;
    setState(() {
      _editorText = initialText;
      _editorSynchronized =
          forceSynchronized ||
          (source.path?.toLowerCase().endsWith('.lrc') ??
              parseLrc(initialText).isNotEmpty);
      _editorViewMode = widget.viewMode;
      _editing = true;
    });
    widget.onEditingChanged?.call(true);
  }

  Future<void> _saveEditedLyrics(String path) async {
    await ref
        .read(libraryProvider.notifier)
        .updateMediaLyricsForView(
          widget.media.id,
          artwork: _editorViewMode == PlayerViewMode.image,
          path: path,
        );
    if (!mounted) return;
    setState(() {
      _source = _loadSource();
      _lastActive = -2;
      _editing = false;
      _editorViewMode = null;
    });
    widget.onEditingChanged?.call(false);
  }

  Future<void> _markNoLyrics() async {
    await ref
        .read(libraryProvider.notifier)
        .setLyricsButtonHidden(widget.media.id, true);
    ref.read(lyricsPanelProvider.notifier).state = false;
  }

  Widget _editor() => LyricsEditorDialog(
    media: widget.media,
    engine: widget.engine,
    initialText: _editorText,
    initialSynchronized: _editorSynchronized,
    viewMode: _editorViewMode ?? widget.viewMode,
    inline: true,
    onCancel: () {
      setState(() {
        _editing = false;
        _editorViewMode = null;
        _source = _loadSource();
      });
      widget.onEditingChanged?.call(false);
    },
    onSaved: _saveEditedLyrics,
    onDraftSaved: (path) => ref
        .read(libraryProvider.notifier)
        .updateMediaLyricsForView(
          widget.media.id,
          artwork: _editorViewMode == PlayerViewMode.image,
          path: path,
        ),
    onFinalized: () => ref
        .read(libraryProvider.notifier)
        .setLyricsEditingFinalized(widget.media.id, true),
  );

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  double get _lineHeight {
    if (widget.immersive) return 100;
    return MediaQuery.sizeOf(context).width < 600 ? 88 : 76;
  }

  void _scrollTo(int active) {
    if (active < 0 || active == _lastActive || !_scrollController.hasClients) {
      return;
    }
    _lastActive = active;
    final target =
        (active * _lineHeight -
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
    final requestedEditorId = ref.watch(lyricsEditorRequestProvider);
    if (requestedEditorId == widget.media.id &&
        !_editing &&
        !_editorRequestScheduled) {
      _editorRequestScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _editorRequestScheduled = false;
        if (!mounted ||
            ref.read(lyricsEditorRequestProvider) != widget.media.id) {
          return;
        }
        ref.read(lyricsEditorRequestProvider.notifier).state = null;
        unawaited(_editLyrics(forceSynchronized: true));
      });
    }
    final currentMedia =
        ref.watch(libraryProvider).byId(widget.media.id) ?? widget.media;
    final textPrimary = themeTextPrimary(context);
    final textSub = themeTextSub(context);
    final phoneLayout = MediaQuery.sizeOf(context).width < 600;
    final hasLyricsActions =
        (currentMedia.translatedLyricsPath != null &&
            _translationLines.isNotEmpty) ||
        !currentMedia.lyricsEditingFinalized;
    return Column(
      children: [
        if (!widget.immersive && hasLyricsActions)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
            child: Row(
              children: [
                const Spacer(),
                if (currentMedia.translatedLyricsPath != null &&
                    _translationLines.isNotEmpty)
                  IconButton(
                    tooltip: ref.tr(
                      _showTranslation
                          ? 'show_original_lyrics'
                          : 'show_translation_lyrics',
                    ),
                    onPressed: _toggleTranslation,
                    visualDensity: VisualDensity.compact,
                    color: _showTranslation
                        ? Theme.of(context).colorScheme.primary
                        : null,
                    icon: const Icon(Icons.translate_rounded),
                  ),
                if (!currentMedia.lyricsEditingFinalized)
                  IconButton(
                    tooltip: ref.tr('lyrics_editor_title'),
                    onPressed: _editLyrics,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.edit_note_rounded),
                  ),
              ],
            ),
          ),
        if (!widget.immersive && hasLyricsActions)
          Divider(height: 1, color: themeBorder(context)),
        if (widget.immersive && hasLyricsActions)
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (currentMedia.translatedLyricsPath != null &&
                    _translationLines.isNotEmpty)
                  IconButton(
                    tooltip: ref.tr(
                      _showTranslation
                          ? 'show_original_lyrics'
                          : 'show_translation_lyrics',
                    ),
                    onPressed: _toggleTranslation,
                    visualDensity: VisualDensity.compact,
                    color: _showTranslation
                        ? Theme.of(context).colorScheme.primary
                        : null,
                    icon: const Icon(Icons.translate_rounded),
                  ),
                if (!currentMedia.lyricsEditingFinalized)
                  IconButton(
                    tooltip: ref.tr('lyrics_editor_title'),
                    onPressed: _editLyrics,
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.edit_note_rounded),
                  ),
              ],
            ),
          ),
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
                      return _emptyLyrics(
                        context,
                        ref.tr('lyrics_not_found'),
                        allowHide: true,
                      );
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
                        final lines = parseLrc(
                          text,
                        ).where((line) => line.text.trim().isNotEmpty).toList();
                        final untimedLines =
                            RegExp(
                                  r'^\s*\[(?:x-xx|-:--)\]\s*(.*)$',
                                  caseSensitive: false,
                                  multiLine: true,
                                )
                                .allMatches(text)
                                .map((match) => match.group(1)!.trim())
                                .where((line) => line.isNotEmpty)
                                .toList();
                        if (lyricsSnapshot.hasError || lines.isEmpty) {
                          final plainText = text
                              .replaceAll(
                                RegExp(
                                  r'^\s*\[(?:x-xx|-:--)\]\s*',
                                  caseSensitive: false,
                                  multiLine: true,
                                ),
                                '',
                              )
                              .trim();
                          if (!lyricsSnapshot.hasError &&
                              plainText.isNotEmpty) {
                            return _lyricsScrollView(
                              SingleChildScrollView(
                                padding: const EdgeInsets.all(20),
                                child: Text(
                                  _showTranslation &&
                                          _translationLines.isNotEmpty
                                      ? _translationLines.join('\n')
                                      : plainText,
                                  style: TextStyle(
                                    color: textPrimary,
                                    fontSize: widget.immersive
                                        ? 30
                                        : (phoneLayout ? 20 : 16),
                                    height: 1.6,
                                  ),
                                ),
                              ),
                            );
                          }
                          return _emptyLyrics(
                            context,
                            lyricsSnapshot.hasError
                                ? ref.tr('lyrics_load_error')
                                : ref.tr('synced_lyrics_not_found'),
                            allowHide: !lyricsSnapshot.hasError,
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
                                milliseconds: currentMedia.lyricsOffsetForView(
                                  artwork:
                                      widget.viewMode == PlayerViewMode.image,
                                ),
                              ),
                            );
                            WidgetsBinding.instance.addPostFrameCallback(
                              (_) => _scrollTo(active),
                            );
                            return _lyricsScrollView(
                              ListView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 12,
                                ),
                                itemCount: lines.length + untimedLines.length,
                                itemBuilder: (context, index) {
                                  if (index >= lines.length) {
                                    return SizedBox(
                                      height: _lineHeight,
                                      child: Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          untimedLines[index - lines.length],
                                          style: TextStyle(
                                            color: textSub.withValues(
                                              alpha: 0.7,
                                            ),
                                            fontSize: widget.immersive
                                                ? 26
                                                : (phoneLayout ? 20 : 16),
                                            height: 1.6,
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                  final isActive = index == active;
                                  return SizedBox(
                                    height: _lineHeight,
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: InkWell(
                                        onTap: () => widget.engine.seekTo(
                                          playbackPositionForLyric(
                                            lines[index].time,
                                            offset: Duration(
                                              milliseconds: currentMedia
                                                  .lyricsOffsetForView(
                                                    artwork:
                                                        widget.viewMode ==
                                                        PlayerViewMode.image,
                                                  ),
                                            ),
                                          ),
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                        child: AnimatedDefaultTextStyle(
                                          duration: const Duration(
                                            milliseconds: 180,
                                          ),
                                          style: TextStyle(
                                            color: isActive
                                                ? textPrimary
                                                : textSub.withValues(
                                                    alpha:
                                                        (index - active).abs() <
                                                            3
                                                        ? 0.7
                                                        : 0.42,
                                                  ),
                                            fontSize: widget.immersive
                                                ? (isActive ? 30 : 26)
                                                : phoneLayout
                                                ? (isActive ? 22 : 18)
                                                : (isActive ? 18 : 15),
                                            fontWeight: isActive
                                                ? FontWeight.w700
                                                : FontWeight.w500,
                                          ),
                                          child: Text(
                                            _showTranslation &&
                                                    index <
                                                        _translationLines.length
                                                ? _translationLines[index]
                                                : lines[index].text,
                                            maxLines: widget.immersive ? 2 : 3,
                                            softWrap: true,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
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

  Widget _emptyLyrics(
    BuildContext context,
    String message, {
    bool allowHide = false,
  }) => Center(
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
              if (allowHide)
                TextButton.icon(
                  onPressed: _markNoLyrics,
                  icon: const Icon(Icons.hide_source_outlined, size: 18),
                  label: Text(ref.tr('lyrics_mark_missing')),
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
