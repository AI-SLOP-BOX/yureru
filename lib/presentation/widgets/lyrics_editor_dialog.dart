import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/return_code.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../app_state.dart';
import '../../data/lyrics.dart';
import '../../data/importer.dart' show isVideoPath;
import '../../domain/models.dart';
import '../../playback/playback_controller.dart';
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
    this.onDraftSaved,
    this.onFinalized,
    this.viewMode = PlayerViewMode.media,
    this.initialSynchronized = true,
    this.inline = false,
    this.advancedLrcTools = false,
    this.fullScreen = false,
    this.onCancel,
  });

  final MediaItem media;
  final PlaybackEngine engine;
  final String initialText;
  final Future<void> Function(String path) onSaved;
  final Future<void> Function(String path)? onDraftSaved;
  final Future<void> Function()? onFinalized;
  final PlayerViewMode viewMode;
  final bool initialSynchronized;
  final bool inline;
  final bool advancedLrcTools;
  final bool fullScreen;
  final VoidCallback? onCancel;

  @override
  ConsumerState<LyricsEditorDialog> createState() => _LyricsEditorDialogState();
}

class _LyricDraft {
  _LyricDraft(Duration? time, String text)
    : time = TextEditingController(
        text: time == null ? 'x-xx' : _formatTime(time),
      ),
      lyric = TextEditingController(text: text),
      focusNode = FocusNode();

  final TextEditingController time;
  final TextEditingController lyric;
  final FocusNode focusNode;
  final GlobalKey rowKey = GlobalKey();

  void dispose() {
    time.dispose();
    lyric.dispose();
    focusNode.dispose();
  }
}

class _LyricsSnapshot {
  const _LyricsSnapshot(this.rows, this.selectedIndex);
  final List<({String time, String lyric})> rows;
  final int selectedIndex;

  bool sameAs(_LyricsSnapshot other) {
    if (rows.length != other.rows.length) return false;
    for (var index = 0; index < rows.length; index++) {
      if (rows[index] != other.rows[index]) return false;
    }
    return true;
  }
}

class _LyricsEditorDialogState extends ConsumerState<LyricsEditorDialog> {
  late final List<_LyricDraft> _rows;
  late final TextEditingController _plainText;
  late bool _synchronized;
  bool _saving = false;
  bool _allowRoutePop = false;
  double? _seekSliderPositionMs;
  int _selectedRowIndex = 0;
  bool _initialWideScrollPending = true;
  final List<_LyricsSnapshot> _undoHistory = [];
  final List<_LyricsSnapshot> _redoHistory = [];
  Timer? _historyTimer;
  final ScrollController _lyricsScrollController = ScrollController();
  StreamSubscription<PlaybackSnapshot>? _lyricsFollowSubscription;
  late _LyricsSnapshot _lastHistorySnapshot;
  late String _savedDraftFingerprint;
  bool _restoringHistory = false;
  String? _waveformPath;
  bool _waveformLoading = false;
  int _timeNudgeMs = 100;
  double _waveformZoom = 1;
  double? _waveformCenterMs;

  @override
  void initState() {
    super.initState();
    _synchronized = widget.initialSynchronized;
    _rows = _draftRowsFromEditorText(widget.initialText);
    _plainText = TextEditingController(
      text: _rows.map((row) => row.lyric.text).join('\n'),
    );
    if (_rows.isEmpty) _rows.add(_LyricDraft(null, ''));
    _savedDraftFingerprint = _draftFingerprint();
    _lastHistorySnapshot = _takeHistorySnapshot();
    if (widget.advancedLrcTools) _attachHistoryListeners(_rows);
    if (_synchronized && widget.advancedLrcTools) {
      unawaited(_loadWaveform());
    }
    if (widget.fullScreen) {
      _lyricsFollowSubscription = widget.engine.snapshots.listen(
        _followPlaybackTime,
      );
    }
  }

  @override
  void dispose() {
    _historyTimer?.cancel();
    unawaited(_lyricsFollowSubscription?.cancel());
    _lyricsScrollController.dispose();
    for (final row in _rows) {
      row.dispose();
    }
    _plainText.dispose();
    super.dispose();
  }

  _LyricsSnapshot _takeHistorySnapshot() => _LyricsSnapshot(
    List.unmodifiable(
      _rows.map((row) => (time: row.time.text, lyric: row.lyric.text)),
    ),
    _selectedRowIndex,
  );

  String _draftFingerprint() => jsonEncode([
    _synchronized,
    _synchronized
        ? _rows.map((row) => [row.time.text, row.lyric.text]).toList()
        : _plainText.text,
  ]);

  bool get _hasUnsavedChanges => _draftFingerprint() != _savedDraftFingerprint;

  Future<void> _requestClose({bool popRouteAfterClose = false}) async {
    if (_saving) return;
    if (_hasUnsavedChanges) {
      final discard = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: Text(ref.tr('unsaved_changes_title')),
          content: Text(ref.tr('unsaved_changes_message')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(ref.tr('keep_editing')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(ref.tr('discard_changes')),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    if (widget.inline) {
      if (popRouteAfterClose) {
        setState(() => _allowRoutePop = true);
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
      }
      final navigator = Navigator.of(context);
      widget.onCancel?.call();
      if (popRouteAfterClose) {
        await WidgetsBinding.instance.endOfFrame;
        await navigator.maybePop();
      }
      return;
    }
    setState(() => _allowRoutePop = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop();
  }

  void _attachHistoryListeners(Iterable<_LyricDraft> rows) {
    if (!widget.advancedLrcTools) return;
    for (final row in rows) {
      row.time.addListener(_scheduleHistoryCapture);
      row.lyric.addListener(_scheduleHistoryCapture);
    }
  }

  void _scheduleHistoryCapture() {
    if (!widget.advancedLrcTools || _restoringHistory) return;
    _historyTimer?.cancel();
    _historyTimer = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final current = _takeHistorySnapshot();
      if (!_lastHistorySnapshot.sameAs(current)) {
        _pushUndo(_lastHistorySnapshot);
        _lastHistorySnapshot = current;
        setState(() {});
      }
    });
  }

  void _pushUndo(_LyricsSnapshot snapshot) {
    _undoHistory.add(snapshot);
    if (_undoHistory.length > 100) _undoHistory.removeAt(0);
    _redoHistory.clear();
  }

  void _flushHistoryCapture() {
    if (!widget.advancedLrcTools) return;
    _historyTimer?.cancel();
    final current = _takeHistorySnapshot();
    if (!_lastHistorySnapshot.sameAs(current)) {
      _pushUndo(_lastHistorySnapshot);
      _lastHistorySnapshot = current;
    }
  }

  void _commitStructuralChange() {
    if (!widget.advancedLrcTools) return;
    final current = _takeHistorySnapshot();
    if (!_lastHistorySnapshot.sameAs(current)) {
      _pushUndo(_lastHistorySnapshot);
      _lastHistorySnapshot = current;
    }
  }

  void _restoreHistory(_LyricsSnapshot snapshot) {
    _historyTimer?.cancel();
    _restoringHistory = true;
    for (final row in _rows) {
      row.time.removeListener(_scheduleHistoryCapture);
      row.lyric.removeListener(_scheduleHistoryCapture);
      row.dispose();
    }
    _rows
      ..clear()
      ..addAll(
        snapshot.rows.map((row) {
          final draft = _LyricDraft(null, row.lyric);
          draft.time.text = row.time;
          return draft;
        }),
      );
    if (_rows.isEmpty) _rows.add(_LyricDraft(null, ''));
    _selectedRowIndex = snapshot.selectedIndex.clamp(0, _rows.length - 1);
    _attachHistoryListeners(_rows);
    _lastHistorySnapshot = _takeHistorySnapshot();
    _restoringHistory = false;
    setState(() {});
  }

  void _undo() {
    _flushHistoryCapture();
    if (_undoHistory.isEmpty) return;
    _redoHistory.add(_takeHistorySnapshot());
    _restoreHistory(_undoHistory.removeLast());
  }

  void _redo() {
    _flushHistoryCapture();
    if (_redoHistory.isEmpty) return;
    _undoHistory.add(_takeHistorySnapshot());
    _restoreHistory(_redoHistory.removeLast());
  }

  Future<void> _loadWaveform() async {
    if (!widget.advancedLrcTools ||
        _waveformLoading ||
        widget.media.localPath.isEmpty) {
      return;
    }
    final parsed = Uri.tryParse(widget.media.localPath);
    final inputPath = parsed?.scheme == 'file'
        ? parsed!.toFilePath()
        : widget.media.localPath;
    if (inputPath.startsWith('http://') || inputPath.startsWith('https://')) {
      return;
    }
    _waveformLoading = true;
    try {
      final input = File(inputPath);
      if (!await input.exists()) return;
      final stat = await input.stat();
      final cache = Directory(
        '${(await getTemporaryDirectory()).path}/yureru_lyrics_waveforms',
      );
      await cache.create(recursive: true);
      final safeId = widget.media.id.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final output = File(
        '${cache.path}/${safeId}_${stat.size}_${stat.modified.millisecondsSinceEpoch}_waveform_v2.png',
      );
      if (!await output.exists()) {
        final session = await FFmpegKit.executeWithArguments([
          '-hide_banner',
          '-y',
          '-i',
          inputPath,
          '-filter_complex',
          '[0:a:0]aformat=channel_layouts=mono,showwavespic=s=2400x160:colors=0xE58165:scale=lin:filter=average,format=rgba,colorkey=0x000000:0.01:0.0[v]',
          '-map',
          '[v]',
          '-frames:v',
          '1',
          output.path,
        ]);
        if (!ReturnCode.isSuccess(await session.getReturnCode()) ||
            !await output.exists() ||
            await output.length() == 0) {
          return;
        }
      }
      if (!mounted) return;
      setState(() => _waveformPath = output.path);
    } catch (_) {
      // Keep the regular seek bar available if waveform extraction is unsupported.
    } finally {
      _waveformLoading = false;
    }
  }

  Future<void> _nudgeRowTime(_LyricDraft row, int milliseconds) async {
    final current = parseLyricsTimestamp(row.time.text);
    if (current == null) return;
    _flushHistoryCapture();
    final next = current + Duration(milliseconds: milliseconds);
    row.time.text = _formatTime(next.isNegative ? Duration.zero : next);
    await _seekToRow(row);
    if (mounted) setState(() {});
  }

  String _formatNudgeDuration(int milliseconds) {
    if (milliseconds < 1000) {
      return milliseconds % 100 == 0
          ? '${(milliseconds / 1000).toStringAsFixed(1)}秒'
          : '${milliseconds}ms';
    }
    final seconds = milliseconds / 1000;
    return '${seconds.toStringAsFixed(seconds == seconds.roundToDouble() ? 0 : 1)}秒';
  }

  Future<void> _seekToRow(_LyricDraft row) async {
    final time = parseLyricsTimestamp(row.time.text);
    if (time == null) return;
    final media =
        ref.read(libraryProvider).byId(widget.media.id) ?? widget.media;
    await widget.engine.seekTo(
      playbackPositionForLyric(
        time,
        offset: Duration(
          milliseconds: media.lyricsOffsetForView(
            artwork: widget.viewMode == PlayerViewMode.image,
          ),
        ),
      ),
    );
  }

  void _stamp(_LyricDraft row) {
    _flushHistoryCapture();
    row.time.text = _currentLyricTimestamp();
    setState(() {});
  }

  String _currentLyricTimestamp() {
    final media =
        ref.read(libraryProvider).byId(widget.media.id) ?? widget.media;
    return _formatTime(
      lyricTimestampAtPlaybackPosition(
        widget.engine.snapshot.position,
        offset: Duration(
          milliseconds: media.lyricsOffsetForView(
            artwork: widget.viewMode == PlayerViewMode.image,
          ),
        ),
      ),
    );
  }

  void _jumpToCurrentLyric() {
    if (_rows.isEmpty) return;
    final media =
        ref.read(libraryProvider).byId(widget.media.id) ?? widget.media;
    final currentTime = lyricTimestampAtPlaybackPosition(
      widget.engine.snapshot.position,
      offset: Duration(
        milliseconds: media.lyricsOffsetForView(
          artwork: widget.viewMode == PlayerViewMode.image,
        ),
      ),
    );
    var targetIndex = 0;
    var latestBeforeCurrent = -1;
    Duration? nextAfterCurrent;
    for (var index = 0; index < _rows.length; index++) {
      final time = parseLyricsTimestamp(_rows[index].time.text);
      if (time == null) continue;
      if (time <= currentTime) {
        if (latestBeforeCurrent == -1 ||
            time >=
                parseLyricsTimestamp(_rows[latestBeforeCurrent].time.text)!) {
          latestBeforeCurrent = index;
        }
      } else if (nextAfterCurrent == null || time < nextAfterCurrent) {
        nextAfterCurrent = time;
        if (latestBeforeCurrent == -1) targetIndex = index;
      }
    }
    if (latestBeforeCurrent != -1) targetIndex = latestBeforeCurrent;
    final row = _rows[targetIndex];
    setState(() => _selectedRowIndex = targetIndex);
    if (_lyricsScrollController.hasClients) {
      _lyricsScrollController.animateTo(
        (targetIndex * 208.0)
            .clamp(0.0, _lyricsScrollController.position.maxScrollExtent)
            .toDouble(),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final rowContext = row.rowKey.currentContext;
      if (rowContext != null) {
        Scrollable.ensureVisible(
          rowContext,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          alignment: 0.25,
        );
      }
    });
  }

  void _followPlaybackTime(PlaybackSnapshot playback) {
    if (!mounted || !_synchronized || _rows.isEmpty) return;
    final media =
        ref.read(libraryProvider).byId(widget.media.id) ?? widget.media;
    final currentTime = lyricTimestampAtPlaybackPosition(
      playback.position,
      offset: Duration(
        milliseconds: media.lyricsOffsetForView(
          artwork: widget.viewMode == PlayerViewMode.image,
        ),
      ),
    );
    var nextIndex = -1;
    Duration? latestTime;
    for (var index = 0; index < _rows.length; index++) {
      final time = parseLyricsTimestamp(_rows[index].time.text);
      if (time == null || time > currentTime) continue;
      if (latestTime == null || time > latestTime) {
        latestTime = time;
        nextIndex = index;
      }
    }
    if (nextIndex == -1 && playback.position <= Duration.zero) {
      nextIndex = _rows.indexWhere(
        (row) => parseLyricsTimestamp(row.time.text) != null,
      );
    }
    if (nextIndex < 0 || nextIndex == _selectedRowIndex) return;
    setState(() => _selectedRowIndex = nextIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_lyricsScrollController.hasClients) return;
      final target = (nextIndex * 208.0)
          .clamp(0.0, _lyricsScrollController.position.maxScrollExtent)
          .toDouble();
      _lyricsScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  void _recordCurrentTime() {
    if (_rows.isEmpty) return;
    final index = _selectedRowIndex.clamp(0, _rows.length - 1);
    _stamp(_rows[index]);
  }

  void _recordAndAdvance() {
    if (_rows.isEmpty) return;
    final currentIndex = _selectedRowIndex.clamp(0, _rows.length - 1);
    _stamp(_rows[currentIndex]);
    if (currentIndex + 1 < _rows.length) {
      _selectRow(currentIndex + 1, focusLyrics: true);
      return;
    }

    final next = _LyricDraft(null, '');
    _attachHistoryListeners([next]);
    setState(() {
      _rows.add(next);
      _selectedRowIndex = _rows.length - 1;
    });
    _commitStructuralChange();
    _focusRow(next);
  }

  void _splitLyricAtCursor(int index) {
    if (index < 0 || index >= _rows.length) return;
    _flushHistoryCapture();

    final current = _rows[index];
    final text = current.lyric.text;
    final selection = current.lyric.selection.isValid
        ? current.lyric.selection
        : TextSelection.collapsed(offset: text.length);
    final start = selection.start.clamp(0, text.length);
    final end = selection.end.clamp(start, text.length);
    final next = _LyricDraft(null, text.substring(end));

    // Keep Enter from becoming another keystroke in the current lyric after
    // splitting it; the next edit target is the newly inserted row.
    current.lyric.removeListener(_scheduleHistoryCapture);
    current.lyric.value = TextEditingValue(
      text: text.substring(0, start),
      selection: TextSelection.collapsed(offset: start),
    );
    current.lyric.addListener(_scheduleHistoryCapture);
    _attachHistoryListeners([next]);
    setState(() {
      _rows.insert(index + 1, next);
      _selectedRowIndex = index + 1;
    });
    _commitStructuralChange();
    _focusRow(next);
  }

  void _splitInsertedNewlines(int index, String value) {
    if (index < 0 || index >= _rows.length || !value.contains('\n')) return;
    final current = _rows[index];
    final editingValue = current.lyric.value;
    if (editingValue.composing.isValid && !editingValue.composing.isCollapsed) {
      return;
    }

    final normalized = value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final parts = normalized.split('\n');
    if (parts.length < 2) return;
    final cursor = editingValue.selection.isValid
        ? editingValue.selection.extentOffset.clamp(0, normalized.length)
        : normalized.length;
    var cursorRow = 0;
    var cursorColumn = cursor;
    var consumed = 0;
    for (var i = 0; i < parts.length; i++) {
      final nextConsumed = consumed + parts[i].length;
      if (cursor <= nextConsumed || i == parts.length - 1) {
        cursorRow = i;
        cursorColumn = (cursor - consumed).clamp(0, parts[i].length);
        break;
      }
      consumed = nextConsumed + 1;
    }

    _historyTimer?.cancel();
    if (widget.advancedLrcTools) _pushUndo(_lastHistorySnapshot);
    current.lyric.removeListener(_scheduleHistoryCapture);
    current.lyric.value = TextEditingValue(
      text: parts.first,
      selection: TextSelection.collapsed(offset: parts.first.length),
    );
    current.lyric.addListener(_scheduleHistoryCapture);

    final inserted = parts
        .skip(1)
        .map((part) => _LyricDraft(null, part))
        .toList();
    _attachHistoryListeners(inserted);
    setState(() {
      _rows.insertAll(index + 1, inserted);
      _selectedRowIndex = index + cursorRow;
    });
    _lastHistorySnapshot = _takeHistorySnapshot();
    final target = _rows[_selectedRowIndex];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      target.lyric.selection = TextSelection.collapsed(
        offset: cursorColumn.clamp(0, target.lyric.text.length),
      );
      target.focusNode.requestFocus();
      _scrollRowIntoView(target);
    });
  }

  void _selectRow(int index, {bool focusLyrics = false}) {
    if (index < 0 || index >= _rows.length) return;
    final row = _rows[index];
    setState(() => _selectedRowIndex = index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (focusLyrics) row.focusNode.requestFocus();
      _scrollRowIntoView(row);
    });
  }

  void _focusRow(_LyricDraft row) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      row.focusNode.requestFocus();
      _scrollRowIntoView(row);
    });
  }

  void _scrollRowIntoView(_LyricDraft row) {
    final rowContext = row.rowKey.currentContext;
    if (rowContext == null) return;
    Scrollable.ensureVisible(
      rowContext,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: 0.25,
    );
  }

  double _waveformWindowStart(double durationMs, double centerMs) {
    final visibleFraction = 1 / _waveformZoom;
    final centerFraction = (centerMs / durationMs).clamp(0.0, 1.0);
    return (centerFraction - visibleFraction / 2).clamp(
      0.0,
      1 - visibleFraction,
    );
  }

  void _seekFromWaveform(double dx, double width, double durationMs) {
    if (durationMs <= 0 || width <= 0) return;
    final center =
        _waveformCenterMs ??
        widget.engine.snapshot.position.inMilliseconds.toDouble();
    final start = _waveformWindowStart(durationMs, center);
    final fraction = (start + (dx / width).clamp(0.0, 1.0) / _waveformZoom)
        .clamp(0.0, 1.0);
    setState(() => _seekSliderPositionMs = fraction * durationMs);
  }

  void _finishWaveformSeek() {
    final target = _seekSliderPositionMs;
    _waveformCenterMs = null;
    if (target == null) return;
    setState(() => _seekSliderPositionMs = null);
    unawaited(widget.engine.seekTo(Duration(milliseconds: target.round())));
  }

  void _setWaveformZoom(double zoom) {
    setState(() => _waveformZoom = zoom.clamp(1.0, 16.0));
  }

  Future<void> _seekBy(Duration amount) async {
    final snapshot = widget.engine.snapshot;
    var target = snapshot.position + amount;
    if (target < Duration.zero) target = Duration.zero;
    if (snapshot.duration > Duration.zero && target > snapshot.duration) {
      target = snapshot.duration;
    }
    await widget.engine.seekTo(target);
  }

  Future<void> _stopPreview() async {
    await widget.engine.pause();
    await widget.engine.seekTo(Duration.zero);
  }

  void _switchMode(bool synchronized) {
    if (synchronized == _synchronized) return;
    if (synchronized) {
      _flushHistoryCapture();
      for (final row in _rows) {
        row.time.removeListener(_scheduleHistoryCapture);
        row.lyric.removeListener(_scheduleHistoryCapture);
        row.dispose();
      }
      _rows
        ..clear()
        ..addAll(_draftsFromPastedText(_plainText.text));
      if (_rows.isEmpty) _rows.add(_LyricDraft(null, ''));
      _attachHistoryListeners(_rows);
      _selectedRowIndex = 0;
      _undoHistory.clear();
      _redoHistory.clear();
      _lastHistorySnapshot = _takeHistorySnapshot();
      if (widget.advancedLrcTools) unawaited(_loadWaveform());
    } else {
      _plainText.text = _rows
          .map((row) => row.lyric.text.trim())
          .where((line) => line.isNotEmpty)
          .join('\n');
    }
    setState(() => _synchronized = synchronized);
  }

  Future<String?> _writeLyricsFile({bool allowUnstampedLines = true}) async {
    final content = _synchronized
        ? _makeLrc(allowUnstampedLines: allowUnstampedLines)
        : _plainText.text.trim();
    if (content == null || content.isEmpty) return null;
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.path}/yureru_lyrics');
    await directory.create(recursive: true);
    final path =
        '${directory.path}/${widget.media.id}_edited_${DateTime.now().microsecondsSinceEpoch}.${_synchronized ? 'lrc' : 'txt'}';
    await File(path).writeAsString('$content\n');
    return path;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final path = await _writeLyricsFile(allowUnstampedLines: true);
      if (path == null) {
        if (mounted) setState(() => _saving = false);
        return;
      }
      await widget.onSaved(path);
      if (!mounted) return;
      _savedDraftFingerprint = _draftFingerprint();
      if (widget.inline) {
        setState(() => _saving = false);
      } else {
        setState(() => _allowRoutePop = true);
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${ref.tr('lyrics_load_error')}: $error')),
      );
    }
  }

  Future<void> _saveDraft() async {
    final saveDraft = widget.onDraftSaved;
    if (saveDraft == null) return;
    setState(() => _saving = true);
    try {
      final path = await _writeLyricsFile(allowUnstampedLines: true);
      if (path == null) {
        if (mounted) setState(() => _saving = false);
        return;
      }
      await saveDraft(path);
      if (!mounted) return;
      _savedDraftFingerprint = _draftFingerprint();
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ref.tr('lyrics_editor_draft_saved'))),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${ref.tr('lyrics_load_error')}: $error')),
      );
    }
  }

  Future<void> _finalizeLyrics() async {
    final finalize = widget.onFinalized;
    if (finalize == null) return;
    setState(() => _saving = true);
    try {
      final path = await _writeLyricsFile(allowUnstampedLines: true);
      if (path == null) {
        if (mounted) setState(() => _saving = false);
        return;
      }
      await widget.onSaved(path);
      await finalize();
      if (!mounted) return;
      _savedDraftFingerprint = _draftFingerprint();
      if (widget.inline) {
        setState(() => _saving = false);
      } else {
        setState(() => _allowRoutePop = true);
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${ref.tr('lyrics_load_error')}: $error')),
      );
    }
  }

  String? _makeLrc({bool allowUnstampedLines = true}) {
    final entries = <({Duration? time, String text, int order})>[];
    for (var index = 0; index < _rows.length; index++) {
      final row = _rows[index];
      final text = row.lyric.text.trim();
      if (text.isEmpty) continue;
      final time = parseLyricsTimestamp(row.time.text);
      if (time == null) {
        final rawTime = row.time.text.trim().toLowerCase();
        final isExplicitlyUnset =
            rawTime.isEmpty || rawTime == 'x-xx' || rawTime == '-:--';
        if (!allowUnstampedLines || !isExplicitlyUnset) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ref.tr('lyrics_editor_invalid_time'))),
          );
          return null;
        }
      }
      entries.add((time: time, text: text, order: index));
    }
    if (entries.isEmpty) return null;
    if (allowUnstampedLines) {
      entries.sort((a, b) {
        if (a.time == null) {
          return b.time == null ? a.order.compareTo(b.order) : 1;
        }
        if (b.time == null) return -1;
        return a.order.compareTo(b.order);
      });
    } else {
      entries.sort((a, b) {
        final byTime = a.time!.compareTo(b.time!);
        return byTime != 0 ? byTime : a.order.compareTo(b.order);
      });
    }
    return entries
        .map(
          (entry) =>
              '[${entry.time == null ? 'x-xx' : _formatTime(entry.time!)}]${entry.text}',
        )
        .join('\n');
  }

  Future<void> _export() async {
    final content = _synchronized
        ? _makeLrc(allowUnstampedLines: true)
        : _plainText.text.trim();
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

  Widget _wideEditorBody(BuildContext context, Color subdued) {
    final volume = ref.watch(volumeProvider);
    final hasVideo =
        widget.advancedLrcTools &&
        widget.viewMode == PlayerViewMode.media &&
        isVideoPath(widget.media.localPath);
    if (_synchronized && _initialWideScrollPending) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_lyricsScrollController.hasClients) return;
        _initialWideScrollPending = false;
        final target = (_selectedRowIndex * 208.0)
            .clamp(0.0, _lyricsScrollController.position.maxScrollExtent)
            .toDouble();
        if (target > 0) _lyricsScrollController.jumpTo(target);
      });
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            flex: 6,
            child: Column(
              children: [
                SegmentedButton<bool>(
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
                  onSelectionChanged: (selection) =>
                      _switchMode(selection.single),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: _synchronized
                      ? Scrollbar(
                          controller: _lyricsScrollController,
                          thumbVisibility: true,
                          child: ListView.builder(
                            controller: _lyricsScrollController,
                            padding: const EdgeInsets.only(right: 10),
                            itemCount: _rows.length,
                            itemExtent: 208,
                            itemBuilder: (context, index) {
                              final row = _rows[index];
                              final isSelected = index == _selectedRowIndex;
                              row.focusNode.onKeyEvent = (node, event) {
                                if (event is KeyDownEvent &&
                                    (event.logicalKey ==
                                            LogicalKeyboardKey.enter ||
                                        event.logicalKey ==
                                            LogicalKeyboardKey.numpadEnter) &&
                                    !HardwareKeyboard.instance.isShiftPressed) {
                                  final composing = row.lyric.value.composing;
                                  if (composing.isValid &&
                                      !composing.isCollapsed) {
                                    return KeyEventResult.ignored;
                                  }
                                  _selectedRowIndex = index;
                                  _splitLyricAtCursor(index);
                                  return KeyEventResult.handled;
                                }
                                if (event is KeyDownEvent &&
                                    event.logicalKey ==
                                        LogicalKeyboardKey.arrowDown &&
                                    index + 1 < _rows.length) {
                                  final next = _rows[index + 1];
                                  next.focusNode.requestFocus();
                                  setState(() => _selectedRowIndex = index + 1);
                                  return KeyEventResult.handled;
                                }
                                return KeyEventResult.ignored;
                              };
                              return Padding(
                                key: row.rowKey,
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerLow,
                                    border: Border.all(
                                      color: isSelected
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.primary
                                          : themeBorder(context),
                                      width: isSelected ? 1.5 : 1,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    children: [
                                      Row(
                                        children: [
                                          SizedBox(
                                            width: 42,
                                            child: Text(
                                              '#${index + 1}',
                                              style: TextStyle(
                                                color: subdued,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          SizedBox(
                                            width: 118,
                                            child: TextField(
                                              controller: row.time,
                                              keyboardType:
                                                  TextInputType.datetime,
                                              decoration: InputDecoration(
                                                isDense: true,
                                                hintText: '00:11.250',
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 9,
                                                    ),
                                                border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(9),
                                                ),
                                              ),
                                              onSubmitted: (_) =>
                                                  _seekToRow(row),
                                              onTap: () => setState(
                                                () => _selectedRowIndex = index,
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: ref.tr(
                                              'lyrics_editor_seek',
                                            ),
                                            visualDensity:
                                                VisualDensity.compact,
                                            onPressed: () => _seekToRow(row),
                                            icon: const Icon(
                                              Icons.play_arrow_rounded,
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: ref.tr(
                                              'lyrics_editor_stamp',
                                            ),
                                            visualDensity:
                                                VisualDensity.compact,
                                            onPressed: () => _stamp(row),
                                            icon: const Icon(
                                              Icons.my_location_rounded,
                                            ),
                                          ),
                                          const Spacer(),
                                          IconButton(
                                            tooltip: ref.tr('remove'),
                                            visualDensity:
                                                VisualDensity.compact,
                                            onPressed: _rows.length == 1
                                                ? null
                                                : () {
                                                    _flushHistoryCapture();
                                                    final removed = _rows
                                                        .removeAt(index);
                                                    removed.time.removeListener(
                                                      _scheduleHistoryCapture,
                                                    );
                                                    removed.lyric.removeListener(
                                                      _scheduleHistoryCapture,
                                                    );
                                                    removed.dispose();
                                                    _selectedRowIndex =
                                                        _selectedRowIndex.clamp(
                                                          0,
                                                          _rows.length - 1,
                                                        );
                                                    setState(() {});
                                                    _commitStructuralChange();
                                                  },
                                            icon: const Icon(
                                              Icons.remove_circle_outline,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (isSelected && widget.advancedLrcTools)
                                        Wrap(
                                          alignment: WrapAlignment.end,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            TextButton(
                                              onPressed: () =>
                                                  _nudgeRowTime(row, -1000),
                                              child: const Text('−1s'),
                                            ),
                                            TextButton(
                                              onPressed: () => _nudgeRowTime(
                                                row,
                                                -_timeNudgeMs,
                                              ),
                                              child: Text(
                                                '-${_formatNudgeDuration(_timeNudgeMs)}',
                                              ),
                                            ),
                                            PopupMenuButton<int>(
                                              tooltip: ref.tr(
                                                'lyrics_editor_adjust_time',
                                              ),
                                              initialValue: _timeNudgeMs,
                                              onSelected: (value) => setState(
                                                () => _timeNudgeMs = value,
                                              ),
                                              itemBuilder: (_) =>
                                                  [1, 10, 50, 100, 500, 1000]
                                                      .map(
                                                        (
                                                          value,
                                                        ) => PopupMenuItem(
                                                          value: value,
                                                          child: Text(
                                                            _formatNudgeDuration(
                                                              value,
                                                            ),
                                                          ),
                                                        ),
                                                      )
                                                      .toList(),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
                                                child: Text(
                                                  '±${_formatNudgeDuration(_timeNudgeMs)}',
                                                  style: TextStyle(
                                                    color: subdued,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            TextButton(
                                              onPressed: () => _nudgeRowTime(
                                                row,
                                                _timeNudgeMs,
                                              ),
                                              child: Text(
                                                '+${_formatNudgeDuration(_timeNudgeMs)}',
                                              ),
                                            ),
                                            TextButton(
                                              onPressed: () =>
                                                  _nudgeRowTime(row, 1000),
                                              child: const Text('+1s'),
                                            ),
                                          ],
                                        ),
                                      TextField(
                                        key: ValueKey(
                                          'wide-lyrics-line-input-$index',
                                        ),
                                        controller: row.lyric,
                                        focusNode: row.focusNode,
                                        textInputAction: TextInputAction.next,
                                        onChanged: (value) =>
                                            _splitInsertedNewlines(
                                              index,
                                              value,
                                            ),
                                        onSubmitted: (_) {
                                          _splitLyricAtCursor(index);
                                        },
                                        onTap: () => setState(
                                          () => _selectedRowIndex = index,
                                        ),
                                        minLines: 2,
                                        maxLines: 3,
                                        textAlignVertical:
                                            TextAlignVertical.top,
                                        decoration: InputDecoration(
                                          isDense: false,
                                          hintText: ref.tr(
                                            'lyrics_editor_line_hint',
                                          ),
                                          contentPadding: const EdgeInsets.all(
                                            10,
                                          ),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              9,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: TextField(
                            controller: _plainText,
                            expands: true,
                            minLines: null,
                            maxLines: null,
                            textAlignVertical: TextAlignVertical.top,
                            style: const TextStyle(fontSize: 20, height: 1.5),
                            decoration: InputDecoration(
                              hintText: ref.tr('lyrics_editor_line_hint'),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              contentPadding: const EdgeInsets.all(14),
                            ),
                          ),
                        ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  children: [
                    if (_synchronized)
                      OutlinedButton.icon(
                        onPressed: () {
                          _flushHistoryCapture();
                          final added = _LyricDraft(null, '');
                          _rows.add(added);
                          _attachHistoryListeners([added]);
                          setState(() => _selectedRowIndex = _rows.length - 1);
                          _commitStructuralChange();
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (_lyricsScrollController.hasClients) {
                              _lyricsScrollController.animateTo(
                                _lyricsScrollController
                                    .position
                                    .maxScrollExtent,
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOut,
                              );
                            }
                          });
                        },
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
              ],
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            flex: 5,
            child: Padding(
              padding: const EdgeInsets.only(right: 4, bottom: 12),
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (hasVideo)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: ColoredBox(
                          color: Colors.black,
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                widget.engine.buildVideoView(
                                  fit: BoxFit.contain,
                                ),
                                Positioned(
                                  right: 8,
                                  bottom: 8,
                                  child: IconButton.filledTonal(
                                    tooltip: ref.tr(
                                      volume == 0 ? 'unmute' : 'volume',
                                    ),
                                    onPressed: () => unawaited(
                                      ref
                                          .read(playbackControllerProvider)
                                          .toggleMute(),
                                    ),
                                    icon: Icon(
                                      volume == 0
                                          ? Icons.volume_off_rounded
                                          : Icons.volume_up_rounded,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    else
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Row(
                            children: [
                              const Icon(Icons.graphic_eq_rounded),
                              const SizedBox(width: 10),
                              Expanded(child: Text(ref.tr('volume'))),
                              IconButton(
                                tooltip: ref.tr(
                                  volume == 0 ? 'unmute' : 'volume',
                                ),
                                onPressed: () => unawaited(
                                  ref
                                      .read(playbackControllerProvider)
                                      .toggleMute(),
                                ),
                                icon: Icon(
                                  volume == 0
                                      ? Icons.volume_off_rounded
                                      : Icons.volume_up_rounded,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (_synchronized)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: _widePlaybackControls(context),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _widePlaybackControls(
    BuildContext context,
  ) => StreamBuilder<PlaybackSnapshot>(
    stream: widget.engine.snapshots,
    initialData: widget.engine.snapshot,
    builder: (context, snapshot) {
      final playback = snapshot.data ?? widget.engine.snapshot;
      final durationMs = playback.duration.inMilliseconds;
      final positionMs =
          _seekSliderPositionMs ?? playback.position.inMilliseconds.toDouble();
      final max = durationMs > 0 ? durationMs.toDouble() : 1.0;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                _formatPlaybackTime(Duration(milliseconds: positionMs.round())),
              ),
              const Spacer(),
              Text(_formatPlaybackTime(playback.duration)),
            ],
          ),
          if (widget.advancedLrcTools &&
              _waveformPath != null &&
              durationMs > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: LayoutBuilder(
                builder: (context, constraints) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (_) {
                    _waveformCenterMs = positionMs;
                  },
                  onHorizontalDragUpdate: (details) => _seekFromWaveform(
                    details.localPosition.dx,
                    constraints.maxWidth,
                    durationMs.toDouble(),
                  ),
                  onHorizontalDragEnd: (_) => _finishWaveformSeek(),
                  onTapUp: (details) {
                    _waveformCenterMs = positionMs;
                    _seekFromWaveform(
                      details.localPosition.dx,
                      constraints.maxWidth,
                      durationMs.toDouble(),
                    );
                    _finishWaveformSeek();
                  },
                  child: SizedBox(
                    height: 100,
                    width: double.infinity,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.file(
                          File(_waveformPath!),
                          fit: BoxFit.fill,
                          errorBuilder: (_, _, _) => const SizedBox.shrink(),
                        ),
                        Center(
                          child: Container(
                            height: 1,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.24),
                          ),
                        ),
                        Positioned(
                          left:
                              ((positionMs / durationMs) * constraints.maxWidth)
                                  .clamp(0.0, constraints.maxWidth),
                          top: 0,
                          bottom: 0,
                          child: Container(
                            width: 2,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          Slider.adaptive(
            value: positionMs.clamp(0.0, max),
            max: max,
            onChanged: durationMs <= 0
                ? null
                : (value) => setState(() => _seekSliderPositionMs = value),
            onChangeEnd: durationMs <= 0
                ? null
                : (value) {
                    setState(() => _seekSliderPositionMs = null);
                    unawaited(
                      widget.engine.seekTo(
                        Duration(milliseconds: value.round()),
                      ),
                    );
                  },
          ),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            children: [
              IconButton(
                tooltip: '-10s',
                onPressed: durationMs <= 0
                    ? null
                    : () => unawaited(_seekBy(const Duration(seconds: -10))),
                icon: const Icon(Icons.replay_10_rounded),
              ),
              IconButton(
                tooltip: ref.tr('stop'),
                onPressed: durationMs <= 0
                    ? null
                    : () => unawaited(_stopPreview()),
                icon: const Icon(Icons.stop_rounded),
              ),
              IconButton.filledTonal(
                tooltip: playback.isPlaying ? ref.tr('pause') : ref.tr('play'),
                onPressed: () => unawaited(
                  playback.isPlaying
                      ? widget.engine.pause()
                      : widget.engine.play(),
                ),
                icon: Icon(
                  playback.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
              ),
              IconButton(
                tooltip: '+10s',
                onPressed: durationMs <= 0
                    ? null
                    : () => unawaited(_seekBy(const Duration(seconds: 10))),
                icon: const Icon(Icons.forward_10_rounded),
              ),
            ],
          ),
          if (widget.advancedLrcTools)
            Center(
              child: FilledButton.icon(
                onPressed: _rows.isEmpty ? null : _recordAndAdvance,
                icon: const Icon(Icons.keyboard_double_arrow_down_rounded),
                label: Text(ref.tr('lyrics_editor_record_next')),
              ),
            ),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) {
    final textColor = themeTextPrimary(context);
    final subdued = themeTextSub(context);
    final screenHeight = MediaQuery.sizeOf(context).height;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompact = screenWidth < 600;
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final availableEditorHeight = (screenHeight - keyboardInset - 32)
        .clamp(0.0, screenHeight * 0.88)
        .toDouble();
    final editor = Container(
      width: widget.inline || widget.fullScreen ? double.infinity : 720,
      height: widget.inline || widget.fullScreen
          ? double.infinity
          : availableEditorHeight,
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ref.tr('lyrics_editor_title'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: textColor,
                          fontSize: widget.inline ? 16 : 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (!widget.inline) ...[
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(
                              isVideoPath(widget.media.localPath)
                                  ? Icons.movie_outlined
                                  : Icons.graphic_eq_rounded,
                              size: 14,
                              color: subdued,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              ref.tr(
                                isVideoPath(widget.media.localPath)
                                    ? 'media_kind_mv'
                                    : 'media_kind_audio',
                              ),
                              style: TextStyle(color: subdued, fontSize: 12),
                            ),
                            const Text(' · '),
                            Icon(
                              widget.viewMode == PlayerViewMode.image
                                  ? Icons.album_outlined
                                  : Icons.smart_display_outlined,
                              size: 14,
                              color: subdued,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              ref.tr(
                                widget.viewMode == PlayerViewMode.image
                                    ? 'lyrics_for_artwork'
                                    : 'lyrics_for_video',
                              ),
                              style: TextStyle(color: subdued, fontSize: 12),
                            ),
                            const Text(' · '),
                            Flexible(
                              child: Text(
                                widget.media.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: subdued, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (widget.onDraftSaved != null)
                  IconButton(
                    key: const ValueKey('lyrics-editor-save-draft'),
                    tooltip: ref.tr('lyrics_editor_save_draft'),
                    onPressed: _saving ? null : _saveDraft,
                    icon: const Icon(Icons.bookmark_add_outlined),
                  ),
                if (!isCompact && widget.advancedLrcTools && _synchronized)
                  IconButton(
                    tooltip: ref.tr('undo'),
                    onPressed: _undoHistory.isEmpty ? null : _undo,
                    icon: const Icon(Icons.undo_rounded),
                  ),
                if (!isCompact && widget.advancedLrcTools && _synchronized)
                  IconButton(
                    tooltip: ref.tr('redo'),
                    onPressed: _redoHistory.isEmpty ? null : _redo,
                    icon: const Icon(Icons.redo_rounded),
                  ),
                if (!isCompact && _synchronized)
                  IconButton(
                    key: const ValueKey('lyrics-editor-jump-to-current'),
                    tooltip: ref.tr('lyrics_editor_jump_to_current'),
                    onPressed: _jumpToCurrentLyric,
                    icon: const Icon(Icons.my_location_rounded),
                  ),
                if (!isCompact && widget.onFinalized != null)
                  IconButton(
                    key: const ValueKey('lyrics-editor-finalize'),
                    tooltip: ref.tr('lyrics_finalize'),
                    onPressed: _saving ? null : _finalizeLyrics,
                    icon: const Icon(Icons.done_all_rounded),
                  ),
                if (isCompact &&
                    ((widget.advancedLrcTools && _synchronized) ||
                        _synchronized ||
                        widget.onFinalized != null))
                  PopupMenuButton<String>(
                    tooltip: ref.tr('lyrics_editor_more_tools'),
                    icon: const Icon(Icons.more_vert_rounded),
                    onSelected: (action) {
                      switch (action) {
                        case 'undo':
                          _undo();
                          break;
                        case 'redo':
                          _redo();
                          break;
                        case 'jump':
                          _jumpToCurrentLyric();
                          break;
                        case 'finalize':
                          unawaited(_finalizeLyrics());
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      if (widget.advancedLrcTools && _synchronized)
                        PopupMenuItem(
                          value: 'undo',
                          enabled: _undoHistory.isNotEmpty,
                          child: Text(ref.tr('undo')),
                        ),
                      if (widget.advancedLrcTools && _synchronized)
                        PopupMenuItem(
                          value: 'redo',
                          enabled: _redoHistory.isNotEmpty,
                          child: Text(ref.tr('redo')),
                        ),
                      if (_synchronized)
                        PopupMenuItem(
                          value: 'jump',
                          child: Text(ref.tr('lyrics_editor_jump_to_current')),
                        ),
                      if (widget.onFinalized != null)
                        PopupMenuItem(
                          value: 'finalize',
                          child: Text(ref.tr('lyrics_finalize')),
                        ),
                    ],
                  ),
                IconButton(
                  tooltip: ref.tr('close'),
                  onPressed: _requestClose,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Expanded(
            child: widget.fullScreen && screenWidth >= 900
                ? _wideEditorBody(context, subdued)
                : SingleChildScrollView(
                    primary: true,
                    physics: const ClampingScrollPhysics(),
                    padding: EdgeInsets.only(bottom: keyboardInset + 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
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
                            onSelectionChanged: (selection) =>
                                _switchMode(selection.single),
                          ),
                        ),
                        if (widget.advancedLrcTools &&
                            widget.viewMode == PlayerViewMode.media &&
                            isVideoPath(widget.media.localPath))
                          Align(
                            alignment: widget.fullScreen
                                ? Alignment.centerRight
                                : Alignment.center,
                            child: SizedBox(
                              width: widget.fullScreen && screenWidth >= 900
                                  ? (screenWidth * 0.43)
                                        .clamp(440.0, 680.0)
                                        .toDouble()
                                  : null,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  16,
                                  4,
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: ColoredBox(
                                    color: Colors.black,
                                    child: SizedBox(
                                      width: double.infinity,
                                      height: widget.fullScreen && !isCompact
                                          ? 300
                                          : isCompact
                                          ? 164
                                          : 220,
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          widget.engine.buildVideoView(
                                            fit: BoxFit.contain,
                                          ),
                                          Positioned(
                                            right: 8,
                                            bottom: 8,
                                            child: IconButton.filledTonal(
                                              tooltip: ref.tr(
                                                ref.watch(volumeProvider) == 0
                                                    ? 'unmute'
                                                    : 'volume',
                                              ),
                                              onPressed: () => unawaited(
                                                ref
                                                    .read(
                                                      playbackControllerProvider,
                                                    )
                                                    .toggleMute(),
                                              ),
                                              icon: Icon(
                                                ref.watch(volumeProvider) == 0
                                                    ? Icons.volume_off_rounded
                                                    : Icons.volume_up_rounded,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: 8),
                        if (_synchronized)
                          Align(
                            alignment: widget.fullScreen
                                ? Alignment.centerRight
                                : Alignment.center,
                            child: SizedBox(
                              width: widget.fullScreen && screenWidth >= 900
                                  ? (screenWidth * 0.43)
                                        .clamp(440.0, 680.0)
                                        .toDouble()
                                  : null,
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  18,
                                  0,
                                  18,
                                  8,
                                ),
                                child: StreamBuilder<PlaybackSnapshot>(
                                  stream: widget.engine.snapshots,
                                  initialData: widget.engine.snapshot,
                                  builder: (context, snapshot) {
                                    final playback =
                                        snapshot.data ?? widget.engine.snapshot;
                                    final durationMs =
                                        playback.duration.inMilliseconds;
                                    final currentPositionMs =
                                        _seekSliderPositionMs ??
                                        playback.position.inMilliseconds
                                            .toDouble();
                                    final sliderMax = durationMs > 0
                                        ? durationMs.toDouble()
                                        : 1.0;
                                    return Column(
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              _formatPlaybackTime(
                                                Duration(
                                                  milliseconds:
                                                      currentPositionMs.round(),
                                                ),
                                              ),
                                            ),
                                            const Spacer(),
                                            Text(
                                              _formatPlaybackTime(
                                                playback.duration,
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (widget.advancedLrcTools &&
                                            _waveformPath != null &&
                                            durationMs > 0)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 4,
                                            ),
                                            child: LayoutBuilder(
                                              builder: (context, constraints) {
                                                final width =
                                                    constraints.maxWidth;
                                                final start =
                                                    _waveformWindowStart(
                                                      durationMs.toDouble(),
                                                      _waveformCenterMs ??
                                                          currentPositionMs,
                                                    );
                                                final visiblePosition =
                                                    ((currentPositionMs /
                                                                    durationMs -
                                                                start) *
                                                            _waveformZoom)
                                                        .clamp(0.0, 1.0);
                                                final windowEnd =
                                                    (start + 1 / _waveformZoom)
                                                        .clamp(0.0, 1.0);
                                                return Column(
                                                  children: [
                                                    Row(
                                                      children: [
                                                        Text(
                                                          _formatPlaybackTime(
                                                            Duration(
                                                              milliseconds:
                                                                  (start *
                                                                          durationMs)
                                                                      .round(),
                                                            ),
                                                          ),
                                                          style: TextStyle(
                                                            color: subdued,
                                                            fontSize: 11,
                                                          ),
                                                        ),
                                                        const Spacer(),
                                                        Text(
                                                          '${_waveformZoom.toStringAsFixed(1)}×',
                                                          style: TextStyle(
                                                            color: subdued,
                                                            fontSize: 11,
                                                            fontFeatures: const [
                                                              FontFeature.tabularFigures(),
                                                            ],
                                                          ),
                                                        ),
                                                        IconButton(
                                                          tooltip: ref.tr(
                                                            'lyrics_editor_waveform_zoom_out',
                                                          ),
                                                          visualDensity:
                                                              VisualDensity
                                                                  .compact,
                                                          onPressed:
                                                              _waveformZoom <= 1
                                                              ? null
                                                              : () => _setWaveformZoom(
                                                                  _waveformZoom /
                                                                      2,
                                                                ),
                                                          icon: const Icon(
                                                            Icons
                                                                .remove_rounded,
                                                          ),
                                                        ),
                                                        IconButton(
                                                          tooltip: ref.tr(
                                                            'lyrics_editor_waveform_zoom_in',
                                                          ),
                                                          visualDensity:
                                                              VisualDensity
                                                                  .compact,
                                                          onPressed:
                                                              _waveformZoom >=
                                                                  16
                                                              ? null
                                                              : () => _setWaveformZoom(
                                                                  _waveformZoom *
                                                                      2,
                                                                ),
                                                          icon: const Icon(
                                                            Icons.add_rounded,
                                                          ),
                                                        ),
                                                        Text(
                                                          _formatPlaybackTime(
                                                            Duration(
                                                              milliseconds:
                                                                  (windowEnd *
                                                                          durationMs)
                                                                      .round(),
                                                            ),
                                                          ),
                                                          style: TextStyle(
                                                            color: subdued,
                                                            fontSize: 11,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                    ClipRRect(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                      child: GestureDetector(
                                                        behavior:
                                                            HitTestBehavior
                                                                .opaque,
                                                        onHorizontalDragStart: (_) {
                                                          _waveformCenterMs =
                                                              currentPositionMs;
                                                        },
                                                        onHorizontalDragUpdate:
                                                            (
                                                              details,
                                                            ) => _seekFromWaveform(
                                                              details
                                                                  .localPosition
                                                                  .dx,
                                                              width,
                                                              durationMs
                                                                  .toDouble(),
                                                            ),
                                                        onHorizontalDragEnd: (_) =>
                                                            _finishWaveformSeek(),
                                                        onTapUp: (details) {
                                                          _waveformCenterMs =
                                                              currentPositionMs;
                                                          _seekFromWaveform(
                                                            details
                                                                .localPosition
                                                                .dx,
                                                            width,
                                                            durationMs
                                                                .toDouble(),
                                                          );
                                                          _finishWaveformSeek();
                                                        },
                                                        child: SizedBox(
                                                          height: 100,
                                                          width:
                                                              double.infinity,
                                                          child: Stack(
                                                            clipBehavior:
                                                                Clip.hardEdge,
                                                            children: [
                                                              Positioned(
                                                                left:
                                                                    -start *
                                                                    _waveformZoom *
                                                                    width,
                                                                top: 0,
                                                                bottom: 0,
                                                                width:
                                                                    width *
                                                                    _waveformZoom,
                                                                child: Opacity(
                                                                  opacity: 0.9,
                                                                  child: Image.file(
                                                                    File(
                                                                      _waveformPath!,
                                                                    ),
                                                                    fit: BoxFit
                                                                        .fill,
                                                                    errorBuilder:
                                                                        (
                                                                          _,
                                                                          _,
                                                                          _,
                                                                        ) =>
                                                                            const SizedBox.shrink(),
                                                                  ),
                                                                ),
                                                              ),
                                                              Positioned.fill(
                                                                child: Center(
                                                                  child: Container(
                                                                    height: 1,
                                                                    color:
                                                                        Theme.of(
                                                                          context,
                                                                        ).colorScheme.onSurface.withValues(
                                                                          alpha:
                                                                              0.24,
                                                                        ),
                                                                  ),
                                                                ),
                                                              ),
                                                              for (final row
                                                                  in _rows)
                                                                if (parseLyricsTimestamp(
                                                                      row
                                                                          .time
                                                                          .text,
                                                                    )
                                                                    case final time?)
                                                                  if (time.inMilliseconds /
                                                                              durationMs >=
                                                                          start &&
                                                                      time.inMilliseconds /
                                                                              durationMs <=
                                                                          windowEnd)
                                                                    Positioned(
                                                                      left:
                                                                          ((time.inMilliseconds /
                                                                                  durationMs -
                                                                              start) *
                                                                          _waveformZoom *
                                                                          width),
                                                                      top: 0,
                                                                      bottom: 0,
                                                                      child: Container(
                                                                        width:
                                                                            1,
                                                                        color:
                                                                            Theme.of(
                                                                              context,
                                                                            ).colorScheme.primary.withValues(
                                                                              alpha: 0.7,
                                                                            ),
                                                                      ),
                                                                    ),
                                                              Positioned(
                                                                left:
                                                                    visiblePosition *
                                                                    width,
                                                                top: 0,
                                                                bottom: 0,
                                                                child: Container(
                                                                  width: 2,
                                                                  color: Theme.of(
                                                                    context,
                                                                  ).colorScheme.primary,
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                );
                                              },
                                            ),
                                          ),
                                        SizedBox(
                                          height: 36,
                                          child: Stack(
                                            alignment: Alignment.center,
                                            children: [
                                              SliderTheme(
                                                data: SliderTheme.of(
                                                  context,
                                                ).copyWith(trackHeight: 3),
                                                child: Slider.adaptive(
                                                  value: currentPositionMs
                                                      .clamp(0, sliderMax)
                                                      .toDouble(),
                                                  max: sliderMax,
                                                  onChanged: durationMs <= 0
                                                      ? null
                                                      : (value) => setState(
                                                          () =>
                                                              _seekSliderPositionMs =
                                                                  value,
                                                        ),
                                                  onChangeEnd: durationMs <= 0
                                                      ? null
                                                      : (value) {
                                                          setState(
                                                            () =>
                                                                _seekSliderPositionMs =
                                                                    null,
                                                          );
                                                          unawaited(
                                                            widget.engine.seekTo(
                                                              Duration(
                                                                milliseconds:
                                                                    value
                                                                        .round(),
                                                              ),
                                                            ),
                                                          );
                                                        },
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Wrap(
                                          alignment: WrapAlignment.center,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          spacing: 6,
                                          runSpacing: 2,
                                          children: [
                                            IconButton(
                                              tooltip: '-10s',
                                              visualDensity:
                                                  VisualDensity.compact,
                                              onPressed: durationMs <= 0
                                                  ? null
                                                  : () => unawaited(
                                                      _seekBy(
                                                        const Duration(
                                                          seconds: -10,
                                                        ),
                                                      ),
                                                    ),
                                              icon: const Icon(
                                                Icons.replay_10_rounded,
                                              ),
                                            ),
                                            IconButton(
                                              tooltip: ref.tr('stop'),
                                              visualDensity:
                                                  VisualDensity.compact,
                                              onPressed: durationMs <= 0
                                                  ? null
                                                  : () => unawaited(
                                                      _stopPreview(),
                                                    ),
                                              icon: const Icon(
                                                Icons.stop_rounded,
                                              ),
                                            ),
                                            IconButton.filledTonal(
                                              tooltip: playback.isPlaying
                                                  ? ref.tr('pause')
                                                  : ref.tr('play'),
                                              visualDensity:
                                                  VisualDensity.compact,
                                              onPressed: () => unawaited(
                                                playback.isPlaying
                                                    ? widget.engine.pause()
                                                    : widget.engine.play(),
                                              ),
                                              icon: Icon(
                                                playback.isPlaying
                                                    ? Icons.pause_rounded
                                                    : Icons.play_arrow_rounded,
                                              ),
                                            ),
                                            IconButton(
                                              tooltip: '+10s',
                                              visualDensity:
                                                  VisualDensity.compact,
                                              onPressed: durationMs <= 0
                                                  ? null
                                                  : () => unawaited(
                                                      _seekBy(
                                                        const Duration(
                                                          seconds: 10,
                                                        ),
                                                      ),
                                                    ),
                                              icon: const Icon(
                                                Icons.forward_10_rounded,
                                              ),
                                            ),
                                            if (widget.advancedLrcTools)
                                              FilledButton.icon(
                                                key: const ValueKey(
                                                  'lyrics-editor-record-next',
                                                ),
                                                onPressed: _rows.isEmpty
                                                    ? null
                                                    : _recordAndAdvance,
                                                icon: const Icon(
                                                  Icons
                                                      .keyboard_double_arrow_down_rounded,
                                                ),
                                                label: Text(
                                                  ref.tr(
                                                    'lyrics_editor_record_next',
                                                  ),
                                                ),
                                              )
                                            else
                                              FilledButton.tonalIcon(
                                                key: const ValueKey(
                                                  'lyrics-editor-record-now',
                                                ),
                                                onPressed: _rows.isEmpty
                                                    ? null
                                                    : _recordCurrentTime,
                                                icon: const Icon(
                                                  Icons.my_location_rounded,
                                                ),
                                                label: Text(
                                                  ref.tr(
                                                    'lyrics_editor_record_now',
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        if (_synchronized)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
                            child: Column(
                              children: List.generate(_rows.length, (index) {
                                final row = _rows[index];
                                final isSelected = index == _selectedRowIndex;
                                row.focusNode.onKeyEvent = (node, event) {
                                  if (widget.advancedLrcTools &&
                                      _synchronized &&
                                      event is KeyDownEvent &&
                                      (event.logicalKey ==
                                              LogicalKeyboardKey.enter ||
                                          event.logicalKey ==
                                              LogicalKeyboardKey.numpadEnter) &&
                                      !HardwareKeyboard
                                          .instance
                                          .isShiftPressed) {
                                    _selectedRowIndex = index;
                                    _recordAndAdvance();
                                    return KeyEventResult.handled;
                                  }
                                  if (event is KeyDownEvent &&
                                      event.logicalKey ==
                                          LogicalKeyboardKey.arrowDown &&
                                      index + 1 < _rows.length) {
                                    final selection = row.lyric.selection;
                                    if (!selection.isValid ||
                                        selection.extentOffset >=
                                            row.lyric.text.length) {
                                      final nextIndex = index + 1;
                                      final nextRow = _rows[nextIndex];
                                      nextRow.focusNode.requestFocus();
                                      setState(
                                        () => _selectedRowIndex = nextIndex,
                                      );
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                            final nextContext =
                                                nextRow.rowKey.currentContext;
                                            if (nextContext != null) {
                                              Scrollable.ensureVisible(
                                                nextContext,
                                                duration: const Duration(
                                                  milliseconds: 180,
                                                ),
                                                alignment: 0.25,
                                              );
                                            }
                                          });
                                      return KeyEventResult.handled;
                                    }
                                  }
                                  return KeyEventResult.ignored;
                                };
                                return Container(
                                  key: row.rowKey,
                                  margin: const EdgeInsets.only(bottom: 10),
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    8,
                                    12,
                                    12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.surfaceContainerLow,
                                    border: Border.all(
                                      color: isSelected
                                          ? Theme.of(
                                              context,
                                            ).colorScheme.primary
                                          : themeBorder(context),
                                      width: isSelected ? 1.5 : 1,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
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
                                            width: 104,
                                            child: TextField(
                                              controller: row.time,
                                              keyboardType:
                                                  TextInputType.datetime,
                                              decoration: InputDecoration(
                                                isDense: true,
                                                hintText: '00:11.250',
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 9,
                                                      vertical: 11,
                                                    ),
                                                border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(9),
                                                ),
                                              ),
                                              onSubmitted: (_) =>
                                                  _seekToRow(row),
                                              onTap: () => setState(
                                                () => _selectedRowIndex = index,
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: ref.tr(
                                              'lyrics_editor_seek',
                                            ),
                                            visualDensity:
                                                VisualDensity.compact,
                                            constraints:
                                                const BoxConstraints.tightFor(
                                                  width: 36,
                                                  height: 36,
                                                ),
                                            padding: EdgeInsets.zero,
                                            onPressed: () => _seekToRow(row),
                                            icon: const Icon(
                                              Icons.play_arrow_rounded,
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: ref.tr(
                                              'lyrics_editor_stamp',
                                            ),
                                            visualDensity:
                                                VisualDensity.compact,
                                            constraints:
                                                const BoxConstraints.tightFor(
                                                  width: 36,
                                                  height: 36,
                                                ),
                                            padding: EdgeInsets.zero,
                                            onPressed: () => _stamp(row),
                                            icon: const Icon(
                                              Icons.my_location_rounded,
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: ref.tr('remove'),
                                            visualDensity:
                                                VisualDensity.compact,
                                            constraints:
                                                const BoxConstraints.tightFor(
                                                  width: 36,
                                                  height: 36,
                                                ),
                                            padding: EdgeInsets.zero,
                                            onPressed: _rows.length == 1
                                                ? null
                                                : () {
                                                    _flushHistoryCapture();
                                                    final removed = _rows
                                                        .removeAt(index);
                                                    removed.time.removeListener(
                                                      _scheduleHistoryCapture,
                                                    );
                                                    removed.lyric.removeListener(
                                                      _scheduleHistoryCapture,
                                                    );
                                                    removed.dispose();
                                                    if (_selectedRowIndex >=
                                                        _rows.length) {
                                                      _selectedRowIndex =
                                                          _rows.length - 1;
                                                    }
                                                    setState(() {});
                                                    _commitStructuralChange();
                                                  },
                                            icon: const Icon(
                                              Icons.remove_circle_outline,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (isSelected && widget.advancedLrcTools)
                                        Wrap(
                                          alignment: WrapAlignment.end,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            TextButton(
                                              onPressed: () =>
                                                  _nudgeRowTime(row, -1000),
                                              child: const Text('−1s'),
                                            ),
                                            TextButton(
                                              onPressed: () => _nudgeRowTime(
                                                row,
                                                -_timeNudgeMs,
                                              ),
                                              child: Text(
                                                '−${_formatNudgeDuration(_timeNudgeMs)}',
                                              ),
                                            ),
                                            PopupMenuButton<int>(
                                              tooltip: ref.tr(
                                                'lyrics_editor_adjust_time',
                                              ),
                                              initialValue: _timeNudgeMs,
                                              onSelected: (value) => setState(
                                                () => _timeNudgeMs = value,
                                              ),
                                              itemBuilder: (_) =>
                                                  [1, 10, 50, 100, 500, 1000]
                                                      .map(
                                                        (
                                                          value,
                                                        ) => PopupMenuItem(
                                                          value: value,
                                                          child: Text(
                                                            _formatNudgeDuration(
                                                              value,
                                                            ),
                                                          ),
                                                        ),
                                                      )
                                                      .toList(),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
                                                child: Text(
                                                  '±${_formatNudgeDuration(_timeNudgeMs)}',
                                                  style: TextStyle(
                                                    color: subdued,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            TextButton(
                                              onPressed: () => _nudgeRowTime(
                                                row,
                                                _timeNudgeMs,
                                              ),
                                              child: Text(
                                                '+${_formatNudgeDuration(_timeNudgeMs)}',
                                              ),
                                            ),
                                            TextButton(
                                              onPressed: () =>
                                                  _nudgeRowTime(row, 1000),
                                              child: const Text('+1s'),
                                            ),
                                          ],
                                        ),
                                      const SizedBox(height: 6),
                                      TextField(
                                        key: ValueKey(
                                          'lyrics-line-input-$index',
                                        ),
                                        controller: row.lyric,
                                        focusNode: row.focusNode,
                                        textInputAction: TextInputAction.next,
                                        onChanged: (value) =>
                                            _splitInsertedNewlines(
                                              index,
                                              value,
                                            ),
                                        onSubmitted: (_) =>
                                            _splitLyricAtCursor(index),
                                        onTap: () => setState(
                                          () => _selectedRowIndex = index,
                                        ),
                                        minLines: 2,
                                        maxLines: 5,
                                        textAlignVertical:
                                            TextAlignVertical.top,
                                        decoration: InputDecoration(
                                          isDense: false,
                                          hintText: ref.tr(
                                            'lyrics_editor_line_hint',
                                          ),
                                          alignLabelWithHint: true,
                                          contentPadding: const EdgeInsets.all(
                                            12,
                                          ),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              9,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ),
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                            child: TextField(
                              controller: _plainText,
                              minLines: 6,
                              maxLines: 8,
                              scrollPhysics: const ClampingScrollPhysics(),
                              textAlignVertical: TextAlignVertical.top,
                              style: const TextStyle(
                                fontSize: 19,
                                height: 1.45,
                              ),
                              decoration: InputDecoration(
                                hintText: ref.tr('lyrics_editor_line_hint'),
                                hintStyle: TextStyle(
                                  fontSize: 16,
                                  color: themeTextSub(context),
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                contentPadding: const EdgeInsets.all(12),
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
                                  onPressed: () {
                                    _flushHistoryCapture();
                                    final added = _LyricDraft(null, '');
                                    _rows.add(added);
                                    _attachHistoryListeners([added]);
                                    setState(() {
                                      _selectedRowIndex = _rows.length - 1;
                                    });
                                    _commitStructuralChange();
                                  },
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
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.save_outlined),
                                label: Text(ref.tr('save')),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
    final undoShortcuts = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): _undo,
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
            _redo,
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: true,
          shift: true,
        ): _redo,
        if (widget.advancedLrcTools && _synchronized)
          const SingleActivator(LogicalKeyboardKey.enter, meta: true):
              _recordAndAdvance,
        if (widget.advancedLrcTools && _synchronized)
          const SingleActivator(LogicalKeyboardKey.enter, control: true):
              _recordAndAdvance,
      },
      child: editor,
    );
    final guardedEditor = PopScope<Object?>(
      canPop: _allowRoutePop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_requestClose(popRouteAfterClose: true));
      },
      child: undoShortcuts,
    );
    return widget.inline || widget.fullScreen
        ? guardedEditor
        : Dialog(insetPadding: const EdgeInsets.all(16), child: guardedEditor);
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
      drafts.add(_LyricDraft(null, line));
    }
  }
  return _moveUnstampedRowsToEnd(drafts);
}

List<_LyricDraft> _draftRowsFromEditorText(String source) {
  final rows = <_LyricDraft>[];
  final offsetMatches = RegExp(
    r'^\s*\[offset:([+-]?\d+)\]\s*$',
    caseSensitive: false,
    multiLine: true,
  ).allMatches(source).toList();
  final offsetMatch = offsetMatches.isEmpty ? null : offsetMatches.last;
  final offsetMs = offsetMatch == null
      ? 0
      : int.tryParse(offsetMatch.group(1)!) ?? 0;
  final unstamped = RegExp(
    r'^\s*\[(?:x-xx|-:--)\]\s*(.*)$',
    caseSensitive: false,
  );

  for (final rawLine in source.split(RegExp(r'\r?\n'))) {
    final line = rawLine.trim();
    if (line.isEmpty ||
        RegExp(r'^\[offset:[+-]?\d+\]$', caseSensitive: false).hasMatch(line)) {
      continue;
    }
    final pendingMatch = unstamped.firstMatch(line);
    if (pendingMatch != null) {
      rows.add(_LyricDraft(null, pendingMatch.group(1)!.trim()));
      continue;
    }
    final timedLines = parseLrc(line);
    if (timedLines.isNotEmpty) {
      rows.addAll(
        timedLines.map(
          (entry) => _LyricDraft(
            Duration(
              milliseconds: (entry.time.inMilliseconds - offsetMs)
                  .clamp(0, 1 << 60)
                  .toInt(),
            ),
            entry.text,
          ),
        ),
      );
    } else {
      rows.add(_LyricDraft(null, line));
    }
  }
  return _moveUnstampedRowsToEnd(rows);
}

List<_LyricDraft> _moveUnstampedRowsToEnd(List<_LyricDraft> rows) {
  final timed = <_LyricDraft>[];
  final unstamped = <_LyricDraft>[];
  for (final row in rows) {
    (parseLyricsTimestamp(row.time.text) == null ? unstamped : timed).add(row);
  }
  timed.sort((a, b) {
    final aTime = parseLyricsTimestamp(a.time.text)!;
    final bTime = parseLyricsTimestamp(b.time.text)!;
    return aTime.compareTo(bTime);
  });
  return [...timed, ...unstamped];
}

String _formatTime(Duration time) {
  final totalMs = time.inMilliseconds.clamp(0, 1 << 60);
  final minutes = totalMs ~/ 60000;
  final seconds = (totalMs ~/ 1000) % 60;
  final milliseconds = totalMs % 1000;
  return '$minutes:${seconds.toString().padLeft(2, '0')}.${milliseconds.toString().padLeft(3, '0')}';
}

String _formatPlaybackTime(Duration time) {
  final totalSeconds = time.inSeconds.clamp(0, 1 << 31);
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}
