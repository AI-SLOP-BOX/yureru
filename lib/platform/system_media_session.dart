import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../domain/models.dart';
import '../playback/playback_engine.dart';

typedef MediaAction = Future<void> Function();

/// A small platform boundary: the OS controls the existing engine/queue.
class SystemMediaSession {
  SystemMediaSession({
    required this.engine,
    required this.play,
    required this.pause,
    required this.toggle,
    required this.next,
    required this.previous,
    required this.seek,
    required this.refresh,
    MethodChannel channel = const MethodChannel('yureru/system_media'),
  }) : _channel = channel {
    _channel.setMethodCallHandler(_handleCommand);
  }

  final PlaybackEngine engine;
  final MediaAction play, pause, toggle, next, previous;
  final Future<void> Function(Duration) seek;
  final VoidCallback refresh;
  final MethodChannel _channel;
  Map<String, Object?>? _signature;
  Map<String, Object?>? _pending;
  bool _active = false;
  bool _sending = false;
  bool _disposed = false;

  void update({
    required MediaItem? media,
    required PlaybackSnapshot snapshot,
    required double rate,
    required bool canNext,
    required bool canPrevious,
  }) {
    if (_disposed) return;
    _active = media != null && snapshot.initialized;
    final position = snapshot.position.inMilliseconds.clamp(0, 1 << 53);
    final payload = <String, Object?>{
      'active': _active,
      if (_active) ...{
        'mediaId': media!.id,
        'title': media.title,
        'artist': media.artist ?? '',
        'artworkPath': media.artworkPath,
        'durationMs': snapshot.duration.inMilliseconds.clamp(0, 1 << 53),
        'positionMs': position,
        'playing': snapshot.isPlaying,
        'rate': rate,
        'canNext': canNext,
        'canPrevious': canPrevious,
      },
    };
    // macOS extrapolates progress using playback rate; publish positions at 1Hz.
    final signature = {...payload, if (_active) 'positionMs': position ~/ 1000};
    if (mapEquals(_signature, signature)) return;
    _signature = signature;
    _pending = payload;
    unawaited(_flush());
  }

  Future<void> _flush() async {
    if (_sending || _disposed) return;
    _sending = true;
    try {
      while (!_disposed && _pending != null) {
        final payload = _pending;
        _pending = null;
        try {
          await _channel.invokeMethod<void>('update', payload);
        } on MissingPluginException {
          /* Platform integration is optional. */
        } on PlatformException {
          /* Playback must remain available. */
        }
      }
    } finally {
      _sending = false;
    }
  }

  Future<bool> _handleCommand(MethodCall call) async {
    if (_disposed || !_active) return false;
    try {
      switch (call.method) {
        case 'play':
          await play();
        case 'pause':
          await pause();
        case 'toggle':
          await toggle();
        case 'next':
          await next();
        case 'previous':
          await previous();
        case 'seek':
          final value = call.arguments;
          if (value is! num || !value.isFinite || value < 0) return false;
          final duration = engine.snapshot.duration.inMilliseconds;
          if (duration <= 0) return false;
          await seek(Duration(milliseconds: value.clamp(0, duration).round()));
        default:
          return false;
      }
      if (!_disposed) refresh();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _pending = null;
    _channel.setMethodCallHandler(null);
    try {
      await _channel.invokeMethod<void>('clear');
    } on MissingPluginException {
      /* No native session to clear. */
    } on PlatformException {
      /* The app may already be terminating. */
    }
  }
}
