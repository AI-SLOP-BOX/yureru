import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import '../playback/playback_engine.dart';

/// Platform window management channels and helpers.
const windowChannel = MethodChannel('yureru/media_picker');
Rect? _normalWindowBounds;
bool? _normalWindowResizable;
bool? _normalWindowSkipTaskbar;
bool? _normalWindowAlwaysOnTop;

Offset _pictureInPicturePosition(Rect sourceBounds, Size pipSize) => Offset(
  sourceBounds.center.dx - pipSize.width / 2,
  sourceBounds.center.dy - pipSize.height / 2,
);

double _validAspectRatio(double? value) =>
    value != null && value.isFinite && value > 0 ? value : 16 / 9;

Size _pictureInPictureSize(double aspectRatio) => aspectRatio >= 1
    ? Size(320, 320 / aspectRatio)
    : Size(320 * aspectRatio, 320);

Size _pictureInPictureMinSize(double aspectRatio) => aspectRatio >= 1
    ? Size(140, 140 / aspectRatio)
    : Size(140 * aspectRatio, 140);

void _setVideoOutputSizeInBackground(
  PlaybackEngine? engine, {
  int? width,
  int? height,
}) {
  if (engine == null) return;
  unawaited(() async {
    try {
      await engine.setVideoOutputSize(width: width, height: height);
    } catch (_) {
      // Rendering-size changes are best-effort and must not block window mode.
    }
  }());
}

/// Toggle fullscreen display across desktop platforms (macOS / Linux / Windows).
Future<void> toggleFullscreen() async {
  try {
    if (Platform.isMacOS) {
      await windowChannel.invokeMethod('toggleFullscreen');
    } else if (Platform.isWindows || Platform.isLinux) {
      await windowManager.setFullScreen(!await windowManager.isFullScreen());
    }
  } catch (_) {
    // Window-management APIs may be unavailable in tests or headless runs.
  }
}

/// Enter the compact always-on-top player window on desktop platforms.
Future<bool> enterPictureInPictureWindow({
  PlaybackEngine? engine,
  double? aspectRatio,
  String? artworkPath,
}) async {
  if (!(Platform.isMacOS ||
      Platform.isWindows ||
      Platform.isLinux ||
      Platform.isAndroid ||
      Platform.isIOS)) {
    return false;
  }
  try {
    final ratio = _validAspectRatio(aspectRatio);
    final pipSize = _pictureInPictureSize(ratio);
    final minSize = _pictureInPictureMinSize(ratio);
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      // The compact desktop window is much smaller than the normal player.
      // media_kit_video otherwise keeps producing a full-resolution texture.
      // Keep the compact texture at a fixed long edge while preserving the
      // video's aspect ratio. A fixed 640x360 texture adds black letterbox
      // space for portrait and ultrawide videos inside the PiP window.
      // Do not wait here: a slow or unsupported renderer must never prevent
      // the native window itself from shrinking into PiP mode.
      final outputSize = ratio >= 1
          ? Size(640, 640 / ratio)
          : Size(480 * ratio, 480);
      _setVideoOutputSizeInBackground(
        engine,
        width: outputSize.width.round().clamp(1, 640),
        height: outputSize.height.round().clamp(1, 640),
      );
    }
    if (Platform.isMacOS) {
      return await engine?.enterPictureInPicture(
            aspectRatio: ratio,
            artworkPath: artworkPath,
          ) ??
          false;
    }
    if (Platform.isAndroid) {
      return await windowChannel.invokeMethod<bool>(
            'enterSystemPictureInPicture',
            {'aspectRatio': ratio},
          ) ??
          false;
    }
    if (Platform.isIOS) {
      return await engine?.enterPictureInPicture(artworkPath: artworkPath) ??
          false;
    }
    _normalWindowBounds ??= await windowManager.getBounds();
    final sourceBounds = _normalWindowBounds!;
    _normalWindowResizable ??= await windowManager.isResizable();
    _normalWindowSkipTaskbar ??= await windowManager.isSkipTaskbar();
    _normalWindowAlwaysOnTop ??= await windowManager.isAlwaysOnTop();
    await windowManager.setResizable(true);
    await windowManager.setTitleBarStyle(
      TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    await windowManager.setSkipTaskbar(true);
    await windowManager.setAspectRatio(ratio);
    await windowManager.setMinimumSize(minSize);
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSize(pipSize, animate: false);
    await windowManager.setPosition(
      _pictureInPicturePosition(sourceBounds, pipSize),
      animate: false,
    );
    return true;
  } catch (_) {
    if (_normalWindowBounds != null &&
        (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      await restorePictureInPictureWindow(engine: engine);
    }
    return false;
  }
}

/// Restore the app window after leaving the compact desktop player mode.
Future<void> restorePictureInPictureWindow({PlaybackEngine? engine}) async {
  if (!(Platform.isMacOS ||
      Platform.isWindows ||
      Platform.isLinux ||
      Platform.isAndroid ||
      Platform.isIOS)) {
    return;
  }
  try {
    if (Platform.isMacOS) {
      await const MethodChannel('yureru/native_pip').invokeMethod<void>('stop');
      return;
    }
    if (Platform.isAndroid) return; // The system owns the PiP window lifecycle.
    if (Platform.isIOS) return; // AVKit owns the PiP window lifecycle.
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setAspectRatio(0);
    await windowManager.setTitleBarStyle(TitleBarStyle.normal);
    await windowManager.setSkipTaskbar(_normalWindowSkipTaskbar ?? false);
    await windowManager.setResizable(_normalWindowResizable ?? true);
    await windowManager.setAlwaysOnTop(_normalWindowAlwaysOnTop ?? false);
    await windowManager.setMinimumSize(
      Platform.isMacOS ? const Size(360, 600) : const Size(380, 600),
    );
    final bounds = _normalWindowBounds;
    if (bounds != null) await windowManager.setBounds(bounds, animate: true);
    await windowManager.show();
    await windowManager.focus();
    _normalWindowBounds = null;
    _normalWindowResizable = null;
    _normalWindowSkipTaskbar = null;
    _normalWindowAlwaysOnTop = null;
    // Return to source-sized output after leaving the compact window.
    _setVideoOutputSizeInBackground(engine);
  } catch (_) {
    // Ignore when the native window channel is unavailable.
  }
}
