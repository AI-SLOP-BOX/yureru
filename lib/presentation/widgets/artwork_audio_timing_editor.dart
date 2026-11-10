import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/return_code.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../playback/playback_engine.dart';
import '../theme.dart';

class ArtworkAudioTimingEditor extends StatefulWidget {
  const ArtworkAudioTimingEditor({
    super.key,
    required this.engine,
    required this.sourcePath,
    required this.startController,
    required this.endController,
    required this.onPreparePreview,
    required this.onRestorePlayback,
    required this.onError,
    required this.tr,
  });

  final PlaybackEngine engine;
  final String sourcePath;
  final TextEditingController startController;
  final TextEditingController endController;
  final Future<void> Function({required bool autoplay}) onPreparePreview;
  final Future<void> Function() onRestorePlayback;
  final ValueChanged<Object> onError;
  final String Function(String key) tr;

  @override
  State<ArtworkAudioTimingEditor> createState() =>
      _ArtworkAudioTimingEditorState();
}

class _ArtworkAudioTimingEditorState extends State<ArtworkAudioTimingEditor> {
  String? _waveformPath;
  bool _waveformLoading = false;
  bool _previewLoading = false;
  bool _previewReady = false;
  bool _closing = false;
  Future<void>? _prepareFuture;
  _TrimDragTarget _dragTarget = _TrimDragTarget.none;
  Duration _draggedPosition = Duration.zero;

  @override
  void initState() {
    super.initState();
    _prepareFuture = _preparePreview();
    _loadWaveform();
  }

  Future<void> _preparePreview() async {
    if (mounted) setState(() => _previewLoading = true);
    try {
      await widget.onPreparePreview(autoplay: false);
      if (mounted) {
        setState(() => _previewReady = true);
        final duration = _durationMs;
        if (duration > 0) {
          await widget.engine.seekTo(
            Duration(milliseconds: _startMs.clamp(0, duration)),
          );
        }
      }
    } catch (error) {
      widget.onError(error);
    } finally {
      if (mounted) setState(() => _previewLoading = false);
    }
  }

  Future<void> _loadWaveform() async {
    final input = File(widget.sourcePath);
    if (!await input.exists()) return;
    if (mounted) setState(() => _waveformLoading = true);
    try {
      final stat = await input.stat();
      final cache = Directory(
        '${(await getTemporaryDirectory()).path}/yureru_audio_trim_waveforms',
      );
      await cache.create(recursive: true);
      final safeName = input.uri.pathSegments.isEmpty
          ? 'audio'
          : input.uri.pathSegments.last.replaceAll(
              RegExp(r'[^a-zA-Z0-9_-]'),
              '_',
            );
      final output = File(
        '${cache.path}/${safeName}_${stat.size}_'
        '${stat.modified.millisecondsSinceEpoch}_trim.png',
      );
      if (!await output.exists()) {
        final session = await FFmpegKit.executeWithArguments([
          '-hide_banner',
          '-y',
          '-i',
          input.path,
          '-filter_complex',
          '[0:a:0]aformat=channel_layouts=mono,showwavespic=s=2400x180:colors=0xE58165:scale=lin:filter=average,format=rgba,colorkey=0x000000:0.01:0.0[v]',
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
      if (mounted) setState(() => _waveformPath = output.path);
    } catch (_) {
      // The trim controls remain usable if this file cannot be decoded.
    } finally {
      if (mounted) setState(() => _waveformLoading = false);
    }
  }

  int get _durationMs => widget.engine.snapshot.duration.inMilliseconds;

  int get _startMs =>
      (_parseSeconds(widget.startController.text) ?? 0).clamp(0, _durationMs);

  int get _endMs {
    final entered = _parseSeconds(widget.endController.text);
    if (entered == null || entered <= 0) return _durationMs;
    return entered.clamp(_startMs, _durationMs);
  }

  int get _positionMs => _dragTarget == _TrimDragTarget.playhead
      ? _draggedPosition.inMilliseconds
      : widget.engine.snapshot.position.inMilliseconds;

  Future<void> _togglePlayback() async {
    try {
      if (!_previewReady) {
        if (_previewLoading) return;
        _prepareFuture = _preparePreview();
        await _prepareFuture;
      }
      if (widget.engine.snapshot.isPlaying) {
        await widget.engine.pause();
      } else {
        await widget.engine.play();
      }
    } catch (error) {
      widget.onError(error);
    }
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    try {
      if (_prepareFuture != null) await _prepareFuture;
      await widget.onRestorePlayback();
    } catch (error) {
      widget.onError(error);
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _seek(int milliseconds) async {
    if (!_previewReady || _durationMs <= 0) return;
    final target = milliseconds.clamp(0, _durationMs);
    setState(() => _draggedPosition = Duration(milliseconds: target));
    try {
      await widget.engine.seekTo(Duration(milliseconds: target));
    } catch (_) {
      // Seeking is best effort while a decoder is still opening.
    }
  }

  void _updateTrimStart(int milliseconds) {
    final value = milliseconds.clamp(0, (_endMs - 1).clamp(0, _durationMs));
    widget.startController.text = _formatSeconds(value);
    setState(() {});
  }

  void _updateTrimEnd(int milliseconds) {
    final value = milliseconds.clamp(
      (_startMs + 1).clamp(0, _durationMs),
      _durationMs,
    );
    widget.endController.text = value >= _durationMs - 1
        ? ''
        : _formatSeconds(value);
    setState(() {});
  }

  void _beginTimelineDrag(Offset position, double width) {
    final duration = _durationMs;
    if (duration <= 0 || width <= 0) return;
    final startX = _startMs / duration * width;
    final endX = _endMs / duration * width;
    final startDistance = (position.dx - startX).abs();
    final endDistance = (position.dx - endX).abs();
    if (startDistance < 26 && startDistance <= endDistance) {
      _dragTarget = _TrimDragTarget.start;
    } else if (endDistance < 26) {
      _dragTarget = _TrimDragTarget.end;
    } else {
      _dragTarget = _TrimDragTarget.playhead;
      _draggedPosition = Duration(
        milliseconds: (position.dx.clamp(0, width) / width * duration).round(),
      );
      _seek(_draggedPosition.inMilliseconds);
    }
  }

  void _updateTimelineDrag(Offset position, double width) {
    final duration = _durationMs;
    if (duration <= 0 || width <= 0) return;
    final milliseconds = (position.dx.clamp(0, width) / width * duration)
        .round();
    switch (_dragTarget) {
      case _TrimDragTarget.start:
        _updateTrimStart(milliseconds);
      case _TrimDragTarget.end:
        _updateTrimEnd(milliseconds);
      case _TrimDragTarget.playhead:
        _seek(milliseconds);
      case _TrimDragTarget.none:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = themeTextPrimary(context);
    final subtle = themeTextSub(context);
    final accent = Theme.of(context).colorScheme.primary;
    return Dialog.fullscreen(
      child: PopScope(
        canPop: _closing,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _close();
        },
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              tooltip: widget.tr('cancel'),
              onPressed: _close,
              icon: const Icon(Icons.close_rounded),
            ),
            title: Text(widget.tr('adjust_audio_position')),
            actions: [
              TextButton(onPressed: _close, child: Text(widget.tr('done'))),
              const SizedBox(width: 10),
            ],
          ),
          body: SafeArea(
            top: false,
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 920),
                    child: StreamBuilder<PlaybackSnapshot>(
                      stream: widget.engine.snapshots,
                      initialData: widget.engine.snapshot,
                      builder: (context, snapshot) {
                        final playback =
                            snapshot.data ?? widget.engine.snapshot;
                        final duration = playback.duration.inMilliseconds;
                        final start = duration > 0
                            ? _startMs.clamp(0, duration)
                            : 0;
                        final end = duration > 0
                            ? _endMs.clamp(start, duration)
                            : 0;
                        final position = _positionMs.clamp(
                          0,
                          duration > 0 ? duration : 0,
                        );
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              widget.sourcePath
                                  .split(Platform.pathSeparator)
                                  .last,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: subtle, fontSize: 14),
                            ),
                            const SizedBox(height: 24),
                            Row(
                              children: [
                                IconButton.filled(
                                  onPressed: _previewLoading
                                      ? null
                                      : _togglePlayback,
                                  iconSize: 34,
                                  constraints: const BoxConstraints.tightFor(
                                    width: 68,
                                    height: 68,
                                  ),
                                  icon: _previewLoading
                                      ? const SizedBox(
                                          width: 24,
                                          height: 24,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Icon(
                                          playback.isPlaying
                                              ? Icons.pause_rounded
                                              : Icons.play_arrow_rounded,
                                        ),
                                ),
                                const SizedBox(width: 18),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SliderTheme(
                                        data: SliderTheme.of(context).copyWith(
                                          trackHeight: 4,
                                          activeTrackColor: accent,
                                          inactiveTrackColor: themeBorder(
                                            context,
                                          ),
                                          thumbColor: accent,
                                          overlayShape:
                                              const RoundSliderOverlayShape(
                                                overlayRadius: 14,
                                              ),
                                        ),
                                        child: Slider(
                                          min: 0,
                                          max: duration > 0
                                              ? duration.toDouble()
                                              : 1,
                                          value: duration <= 0
                                              ? 0
                                              : position.toDouble(),
                                          onChanged:
                                              !_previewReady || duration <= 0
                                              ? null
                                              : (value) => _seek(value.round()),
                                        ),
                                      ),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            _formatMilliseconds(position),
                                            style: TextStyle(color: subtle),
                                          ),
                                          Text(
                                            _formatMilliseconds(duration),
                                            style: TextStyle(color: subtle),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 22),
                            Text(
                              widget.tr('artwork_audio_trim'),
                              style: TextStyle(
                                color: primary,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 12),
                            LayoutBuilder(
                              builder: (context, timelineConstraints) {
                                final width = timelineConstraints.maxWidth;
                                final startFraction = duration <= 0
                                    ? 0.0
                                    : start / duration;
                                final endFraction = duration <= 0
                                    ? 1.0
                                    : end / duration;
                                final playheadFraction = duration <= 0
                                    ? 0.0
                                    : position / duration;
                                return GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTapUp: (details) {
                                    _dragTarget = _TrimDragTarget.playhead;
                                    _updateTimelineDrag(
                                      details.localPosition,
                                      width,
                                    );
                                  },
                                  onHorizontalDragStart: (details) =>
                                      _beginTimelineDrag(
                                        details.localPosition,
                                        width,
                                      ),
                                  onHorizontalDragUpdate: (details) =>
                                      _updateTimelineDrag(
                                        details.localPosition,
                                        width,
                                      ),
                                  onHorizontalDragEnd: (_) => setState(
                                    () => _dragTarget = _TrimDragTarget.none,
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: SizedBox(
                                      height: 142,
                                      width: double.infinity,
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          ColoredBox(
                                            color: isDark
                                                ? const Color(0xFF171717)
                                                : const Color(0xFFE8E8E8),
                                            child: _waveformPath == null
                                                ? Center(
                                                    child: _waveformLoading
                                                        ? const CircularProgressIndicator()
                                                        : Icon(
                                                            Icons
                                                                .graphic_eq_rounded,
                                                            color: subtle,
                                                            size: 42,
                                                          ),
                                                  )
                                                : Image.file(
                                                    File(_waveformPath!),
                                                    fit: BoxFit.fill,
                                                    errorBuilder: (_, _, _) =>
                                                        const SizedBox.shrink(),
                                                  ),
                                          ),
                                          CustomPaint(
                                            painter: _AudioTrimOverlayPainter(
                                              start: startFraction,
                                              end: endFraction,
                                              playhead: playheadFraction,
                                              selection: accent,
                                              dim: Colors.black.withValues(
                                                alpha: isDark ? 0.62 : 0.42,
                                              ),
                                            ),
                                          ),
                                          if (!_previewReady)
                                            Center(
                                              child: Text(
                                                widget.tr('timing_preview'),
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600,
                                                  shadows: const [
                                                    Shadow(
                                                      color: Colors.black87,
                                                      blurRadius: 8,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${widget.tr('trim_start')}: ${_formatMilliseconds(start)}',
                                  style: TextStyle(color: subtle),
                                ),
                                Text(
                                  '${widget.tr('trim_end')}: ${end >= duration && duration > 0 ? widget.tr('source_end') : _formatMilliseconds(end)}',
                                  style: TextStyle(color: subtle),
                                ),
                              ],
                            ),
                            if (duration > 0) ...[
                              const SizedBox(height: 18),
                              RangeSlider(
                                values: RangeValues(
                                  start.toDouble(),
                                  mathMax(start + 1, end).toDouble().clamp(
                                    start.toDouble(),
                                    duration.toDouble(),
                                  ),
                                ),
                                min: 0,
                                max: duration.toDouble(),
                                onChanged: (range) {
                                  _updateTrimStart(range.start.round());
                                  _updateTrimEnd(range.end.round());
                                },
                              ),
                            ],
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                Expanded(
                                  child: _secondsField(
                                    context,
                                    controller: widget.startController,
                                    label: widget.tr('artwork_audio_offset'),
                                    signed: true,
                                    onChanged: () => setState(() {}),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: _secondsField(
                                    context,
                                    controller: widget.endController,
                                    label: widget.tr('artwork_audio_end'),
                                    signed: false,
                                    onChanged: () => setState(() {}),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                onPressed: !_previewReady || duration <= 0
                                    ? null
                                    : () => _updateTrimStart(position),
                                icon: const Icon(Icons.flag_rounded),
                                label: Text(widget.tr('use_preview_position')),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _secondsField(
    BuildContext context, {
    required TextEditingController controller,
    required String label,
    required bool signed,
    required VoidCallback onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return TextField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(
        decimal: true,
        signed: signed,
      ),
      onChanged: (_) => onChanged(),
      style: TextStyle(color: themeTextPrimary(context), fontSize: 16),
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: isDark
            ? Colors.white.withValues(alpha: 0.035)
            : const Color(0xFFF7F7F7),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

enum _TrimDragTarget { none, start, end, playhead }

class _AudioTrimOverlayPainter extends CustomPainter {
  const _AudioTrimOverlayPainter({
    required this.start,
    required this.end,
    required this.playhead,
    required this.selection,
    required this.dim,
  });

  final double start;
  final double end;
  final double playhead;
  final Color selection;
  final Color dim;

  @override
  void paint(Canvas canvas, Size size) {
    final left = (start * size.width).clamp(0.0, size.width);
    final right = (end * size.width).clamp(left, size.width);
    final dimPaint = Paint()..color = dim;
    canvas.drawRect(Rect.fromLTRB(0, 0, left, size.height), dimPaint);
    canvas.drawRect(Rect.fromLTRB(right, 0, size.width, size.height), dimPaint);
    final border = Paint()
      ..color = selection
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    canvas.drawRect(Rect.fromLTRB(left, 1.5, right, size.height - 1.5), border);
    final handlePaint = Paint()..color = selection;
    for (final x in [left, right]) {
      final handle = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x, size.height / 2),
          width: 10,
          height: 48,
        ),
        const Radius.circular(5),
      );
      canvas.drawRRect(handle, handlePaint);
      final grip = Paint()
        ..color = Colors.white.withValues(alpha: 0.88)
        ..strokeWidth = 1.6;
      for (final offset in [-5.0, 0.0, 5.0]) {
        canvas.drawLine(
          Offset(x - 2, size.height / 2 + offset),
          Offset(x + 2, size.height / 2 + offset),
          grip,
        );
      }
    }
    final cursorX = (playhead * size.width).clamp(0.0, size.width);
    final playheadPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2;
    canvas.drawLine(
      Offset(cursorX, 0),
      Offset(cursorX, size.height),
      playheadPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _AudioTrimOverlayPainter oldDelegate) =>
      oldDelegate.start != start ||
      oldDelegate.end != end ||
      oldDelegate.playhead != playhead ||
      oldDelegate.selection != selection ||
      oldDelegate.dim != dim;
}

int? _parseSeconds(String input) {
  final value = input.trim();
  if (value.isEmpty) return null;
  if (value.contains(':')) {
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final minutes = int.tryParse(parts[0]);
    final seconds = double.tryParse(parts[1]);
    if (minutes == null || seconds == null || seconds < 0 || seconds >= 60) {
      return null;
    }
    return ((minutes * 60 + seconds) * 1000).round();
  }
  final seconds = double.tryParse(value);
  if (seconds == null || !seconds.isFinite) return null;
  return (seconds * 1000).round();
}

String _formatSeconds(int milliseconds) =>
    (milliseconds / 1000).toStringAsFixed(2);

String _formatMilliseconds(int milliseconds) {
  final duration = Duration(milliseconds: milliseconds);
  final minutes = duration.inMinutes;
  final seconds = (duration.inMilliseconds / 1000 - minutes * 60);
  return '$minutes:${seconds.toStringAsFixed(2).padLeft(5, '0')}';
}

int mathMax(int a, int b) => a > b ? a : b;
