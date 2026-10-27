import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:yureru/playback/media_kit_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ambient sampling captures the rendered frame source', () async {
    final bytes = Uint8List(8 * 8 * 4);
    for (var i = 0; i < bytes.length; i += 4) {
      bytes[i] = 32;
      bytes[i + 1] = 160;
      bytes[i + 2] = 224;
      bytes[i + 3] = 255;
    }
    final sourceCompleter = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      bytes,
      8,
      8,
      ui.PixelFormat.rgba8888,
      sourceCompleter.complete,
    );
    final source = await sourceCompleter.future;
    final engine = MediaKitPlaybackEngine()
      ..setAmbientFrameSource(() async => source);

    final frame = await engine.captureAmbientFrame(
      aperture: const ui.Rect.fromLTWH(0.25, 0.25, 0.5, 0.5),
    );

    expect(frame, isNotNull);
    frame?.dispose();
  });
}
