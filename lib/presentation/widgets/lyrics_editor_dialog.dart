import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../data/lyrics.dart';
import '../../domain/models.dart';
import '../../playback/playback_engine.dart';
import '../i18n.dart';
import '../theme.dart';

/// A lightweight LRC editor for timing lyrics while the current media plays.
class LyricsEditorDialog extends ConsumerStatefulWidget {
  const LyricsEditorDialog({
    super.key,
    required this.media,
    required this.engine,
    required this.initialText,
    required this.onSaved,
    this.initialSynchronized = true,
    this.inline = false,
    this.onCancel,
  });

  final MediaItem media;
  final PlaybackEngine engine;
  final String initialText;
  final Future<void> Function(String path) onSaved;
  final bool initialSynchronized;
  final bool inline;
  final VoidCallback? onCancel;

  @override
  ConsumerState<LyricsEditorDialog> createState() => _LyricsEditorDialogState();
}

class _LyricDraft {
  _LyricDraft(Duration time, String text)
    : time = TextEditingController(text: _formatTime(time)),
      lyric = TextEditingController(text: text);

  final TextEditingController time;
  final TextEditingController lyric;

  void dispose() {
    time.dispose();
    lyric.dispose();
  }
}

class _LyricsEditorDialogState extends ConsumerState<LyricsEditorDialog> {
  late final List<_LyricDraft> _rows;
  late final TextEditingController _plainText;
  late bool _synchronized;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _synchronized = widget.initialSynchronized;
    final parsed = parseLrc(widget.initialText);
    _plainText = TextEditingController(
      text: parsed.isEmpty
          ? widget.initialText
          : parsed.map((line) => line.text).join('\n'),
    );
    if (parsed.isNotEmpty) {
      _rows = parsed.map((line) => _LyricDraft(line.time, line.text)).toList();
    } else {
      _rows = widget.initialText
          .split(RegExp(r'\r?\n'))
          .where((line) => line.trim().isNotEmpty)
          .map((line) => _LyricDraft(Duration.zero, line.trim()))
          .toList();
    }
    if (_rows.isEmpty) _rows.add(_LyricDraft(Duration.zero, ''));
  }

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    _plainText.dispose();
    super.dispose();
  }

  Future<void> _seekToRow(_LyricDraft row) async {
    final time = parseLyricsTimestamp(row.time.text);
    if (time != null) await widget.engine.seekTo(time);
  }

  void _stamp(_LyricDraft row) {
    row.time.text = _formatTime(widget.engine.snapshot.position);
    setState(() {});
  }

  void _switchMode(bool synchronized) {
    if (synchronized == _synchronized) return;
    if (synchronized) {
      for (final row in _rows) {
        row.dispose();
      }
      _rows
        ..clear()
        ..addAll(_draftsFromPastedText(_plainText.text));
      if (_rows.isEmpty) _rows.add(_LyricDraft(Duration.zero, ''));
    } else {
      _plainText.text = _rows
          .map((row) => row.lyric.text.trim())
          .where((line) => line.isNotEmpty)
          .join('\n');
    }
    setState(() => _synchronized = synchronized);
  }

  Future<void> _save() async {
    final content = _synchronized ? _makeLrc() : _plainText.text.trim();
    if (content == null || content.isEmpty) return;
    setState(() => _saving = true);
    try {
      final support = await getApplicationSupportDirectory();
      final directory = Directory('${support.path}/yureru_lyrics');
      await directory.create(recursive: true);
      final path =
          '${directory.path}/${widget.media.id}_edited_${DateTime.now().microsecondsSinceEpoch}.${_synchronized ? 'lrc' : 'txt'}';
      await File(path).writeAsString('$content\n');
      await widget.onSaved(path);
      // Inline editors are dismissed by their host after it switches back to
      // the lyrics view. Popping here would close the player route as well.
      if (mounted) {
        if (widget.inline) {
          setState(() => _saving = false);
        } else {
          Navigator.of(context).pop();
        }
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${ref.tr('lyrics_load_error')}: $error')),
      );
    }
  }

  String? _makeLrc() {
    final entries = <({Duration time, String text})>[];
    for (final row in _rows) {
      final text = row.lyric.text.trim();
      if (text.isEmpty) continue;
      final time = parseLyricsTimestamp(row.time.text);
      if (time == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ref.tr('lyrics_editor_invalid_time'))),
        );
        return null;
      }
      entries.add((time: time, text: text));
    }
    if (entries.isEmpty) return null;
    entries.sort((a, b) => a.time.compareTo(b.time));
    return entries
        .map((entry) => '[${_formatTime(entry.time)}]${entry.text}')
        .join('\n');
  }

  Future<void> _export() async {
    final content = _synchronized ? _makeLrc() : _plainText.text.trim();
    if (content == null || content.isEmpty) return;
    final extension = _synchronized ? 'lrc' : 'txt';
    try {
      await FilePicker.platform.saveFile(
        dialogTitle: ref.tr('lyrics_editor_export'),
        fileName:
            '${widget.media.title.replaceAll(RegExp(r'[/\\]'), '_')}.$extension',
        type: FileType.custom,
        allowedExtensions: [extension],
        bytes: Uint8List.fromList(utf8.encode('$content\n')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${ref.tr('lyrics_load_error')}: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textColor = themeTextPrimary(context);
    final subdued = themeTextSub(context);
    final editor = Container(
      width: widget.inline ? double.infinity : 720,
      height: widget.inline
          ? double.infinity
          : MediaQuery.sizeOf(context).height * 0.88,
      decoration: widget.inline
          ? BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: themeBorder(context)),
            )
          : null,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    ref.tr('lyrics_editor_title'),
                    style: TextStyle(
                      color: textColor,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: ref.tr('close'),
                  onPressed: () {
                    if (widget.inline) {
                      widget.onCancel?.call();
                    } else {
                      Navigator.of(context).pop();
                    }
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                ref.tr(
                  _synchronized
                      ? 'lyrics_editor_hint'
                      : 'lyrics_editor_plain_hint',
                ),
                style: TextStyle(color: subdued, fontSize: 13),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: false,
                  label: Text(ref.tr('lyrics_editor_plain')),
                ),
                ButtonSegment(
                  value: true,
                  label: Text(ref.tr('lyrics_editor_synced')),
                ),
              ],
              selected: {_synchronized},
              onSelectionChanged: (selection) => _switchMode(selection.single),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _synchronized
                ? ListView.builder(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
                    itemCount: _rows.length,
                    itemBuilder: (context, index) {
                      final row = _rows[index];
                      return Container(
                        key: ValueKey('lyrics-row-$index'),
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerLow,
                          border: Border.all(color: themeBorder(context)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '#${index + 1}',
                                    style: TextStyle(
                                      color: subdued,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 112,
                                  child: TextField(
                                    controller: row.time,
                                    keyboardType: TextInputType.datetime,
                                    decoration: InputDecoration(
                                      isDense: true,
                                      hintText: '00:11',
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 9,
                                            vertical: 11,
                                          ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(9),
                                      ),
                                    ),
                                    onSubmitted: (_) => _seekToRow(row),
                                  ),
                                ),
                                IconButton(
                                  tooltip: ref.tr('lyrics_editor_seek'),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => _seekToRow(row),
                                  icon: const Icon(Icons.play_arrow_rounded),
                                ),
                                IconButton(
                                  tooltip: ref.tr('lyrics_editor_stamp'),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => _stamp(row),
                                  icon: const Icon(Icons.my_location_rounded),
                                ),
                                IconButton(
                                  tooltip: ref.tr('remove'),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: _rows.length == 1
                                      ? null
                                      : () => setState(() {
                                          _rows.removeAt(index).dispose();
                                        }),
                                  icon: const Icon(Icons.remove_circle_outline),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              key: ValueKey('lyrics-line-input-$index'),
                              controller: row.lyric,
                              minLines: 2,
                              maxLines: 5,
                              textAlignVertical: TextAlignVertical.top,
                              decoration: InputDecoration(
                                isDense: false,
                                hintText: ref.tr('lyrics_editor_line_hint'),
                                alignLabelWithHint: true,
                                contentPadding: const EdgeInsets.all(12),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(9),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  )
                : Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: TextField(
                      controller: _plainText,
                      expands: true,
                      minLines: null,
                      maxLines: null,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: InputDecoration(
                        hintText: ref.tr('lyrics_editor_line_hint'),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 6,
              children: [
                if (_synchronized)
                  OutlinedButton.icon(
                    onPressed: () => setState(
                      () => _rows.add(
                        _LyricDraft(widget.engine.snapshot.position, ''),
                      ),
                    ),
                    icon: const Icon(Icons.add_rounded),
                    label: Text(ref.tr('lyrics_editor_add_line')),
                  ),
                OutlinedButton.icon(
                  onPressed: _saving ? null : _export,
                  icon: const Icon(Icons.file_download_outlined),
                  label: Text(ref.tr('lyrics_editor_export')),
                ),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(ref.tr('save')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return widget.inline
        ? editor
        : Dialog(insetPadding: const EdgeInsets.all(16), child: editor);
  }
}

List<_LyricDraft> _draftsFromPastedText(String source) {
  final drafts = <_LyricDraft>[];
  for (final rawLine in source.split(RegExp(r'\r?\n'))) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    final lrcLines = parseLrc(line);
    if (lrcLines.isNotEmpty) {
      drafts.addAll(
        lrcLines.map((lyric) => _LyricDraft(lyric.time, lyric.text)),
      );
      continue;
    }
    final match = RegExp(
      r'^(\[[^\]]+\]|\S+)\s*(?:[-–—:]\s*)?(.*)$',
    ).firstMatch(line);
    final time = match == null ? null : parseLyricsTimestamp(match.group(1)!);
    if (match != null && time != null) {
      drafts.add(_LyricDraft(time, match.group(2)!.trim()));
    } else {
      drafts.add(_LyricDraft(Duration.zero, line));
    }
  }
  return drafts;
}

String _formatTime(Duration time) {
  final totalMs = time.inMilliseconds.clamp(0, 1 << 60);
  final minutes = totalMs ~/ 60000;
  final seconds = (totalMs ~/ 1000) % 60;
  final centiseconds = (totalMs % 1000) ~/ 10;
  return '$minutes:${seconds.toString().padLeft(2, '0')}.${centiseconds.toString().padLeft(2, '0')}';
}
