import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yureru/ambient/ambient_frame_notifier.dart';
import 'package:yureru/playback/fake_engine.dart';
import 'package:yureru/playback/playback_engine.dart';

class _SnapshotEngine extends FakePlaybackEngine {
  final controller = StreamController<PlaybackSnapshot>.broadcast();
  int captures = 0;
  Duration captureDelay = Duration.zero;

  @override
  Stream<PlaybackSnapshot> get snapshots => controller.stream;

  @override
  Future<ui.Image?> captureAmbientFrame({
    Rect? aperture,
    double spread = 1,
    double depth = 1,
    double softness = 1,
  }) async {
    if (captureDelay > Duration.zero) await Future<void>.delayed(captureDelay);
    captures++;
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      Uint8List.fromList([captures, 0, 0, 255]),
      1,
      1,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }

  void emit(PlaybackSnapshot snapshot) {
    snap = snapshot;
    controller.add(snapshot);
  }
}

void main() {
  test(
    'captures a paused frame initially and refreshes it after a seek',
    () async {
      final engine = _SnapshotEngine()
        ..snap = const PlaybackSnapshot(
          position: Duration(seconds: 5),
          duration: Duration(minutes: 2),
          initialized: true,
          isPlaying: false,
        );
      final notifier = AmbientFrameNotifier(engine);
      addTearDown(() async {
        notifier.dispose();
        await engine.controller.close();
      });

      if (notifier.state == null) {
        await notifier.stream
            .firstWhere((frame) => frame != null)
            .timeout(const Duration(seconds: 5));
      }
      expect(engine.captures, 1);
      expect(notifier.state, isNotNull);

      final nextFrame = notifier.stream
          .firstWhere((frame) => frame != null)
          .timeout(const Duration(seconds: 5));
      engine.emit(
        const PlaybackSnapshot(
          position: Duration(seconds: 42),
          duration: Duration(minutes: 2),
          initialized: true,
          isPlaying: false,
        ),
      );
      await nextFrame;

      expect(engine.captures, 2);
      expect(notifier.state, isNotNull);
    },
  );

  test(
    'automatic capture rate falls under load and rises when it clears',
    () async {
      final engine = _SnapshotEngine()
        ..snap = const PlaybackSnapshot(
          position: Duration.zero,
          duration: Duration(minutes: 2),
          initialized: true,
          isPlaying: true,
        )
        ..captureDelay = const Duration(milliseconds: 45);
      final notifier = AmbientFrameNotifier(engine, framesPerSecond: 0);
      addTearDown(() async {
        notifier.dispose();
        await engine.controller.close();
      });

      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(notifier.effectiveFramesPerSecond, lessThan(60));

      engine.captureDelay = Duration.zero;
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (notifier.effectiveFramesPerSecond < 60 &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      expect(notifier.effectiveFramesPerSecond, 60);
    },
  );

  test('a numeric capture rate stays fixed under load', () async {
    final engine = _SnapshotEngine()
      ..snap = const PlaybackSnapshot(
        position: Duration.zero,
        duration: Duration(minutes: 2),
        initialized: true,
        isPlaying: true,
      )
      ..captureDelay = const Duration(milliseconds: 60);
    final notifier = AmbientFrameNotifier(engine, framesPerSecond: 30);
    addTearDown(() async {
      notifier.dispose();
      await engine.controller.close();
    });

    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(notifier.effectiveFramesPerSecond, 30);
  });
}
