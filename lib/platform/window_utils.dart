import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import '../playback/playback_engine.dart';

/// Platform window management channels and helpers.
const windowChannel = MethodChannel('yureru/media_picker');
Rect? _normalWindowBounds;

Offset _pictureInPicturePosition(Rect sourceBounds) =>
    Offset(sourceBounds.center.dx - 120, sourceBounds.center.dy - 67.5);

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
Future<bool> enterPictureInPictureWindow({PlaybackEngine? engine}) async {
  if (!(Platform.isMacOS ||
      Platform.isWindows ||
      Platform.isLinux ||
      Platform.isAndroid ||
      Platform.isIOS)) {
    return false;
  }
  try {
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      // The compact desktop window is much smaller than the normal player.
      // media_kit_video otherwise keeps producing a full-resolution texture.
      // A 640x360 output is sharp on HiDPI displays while greatly reducing
      // texture upload and compositing work for 4K sources.
      // Do not wait here: a slow or unsupported renderer must never prevent
      // the native window itself from shrinking into PiP mode.
      _setVideoOutputSizeInBackground(engine, width: 640, height: 360);
    }
    if (Platform.isMacOS) {
      // Keep macOS's borderless/floating styling, then resize through the
      // same window-manager API used on Windows and Linux. NSWindow's own
      // frame conversion was leaving the Flutter window at its old size.
      _normalWindowBounds ??= await windowManager.getBounds();
      final sourceBounds = _normalWindowBounds!;
      await windowChannel.invokeMethod<void>('setCompactPlayerWindow');
      await windowManager.setResizable(true);
      await windowManager.setAspectRatio(16 / 9);
      await windowManager.setMinimumSize(const Size(220, 124));
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setSize(const Size(240, 135), animate: false);
      await windowManager.setPosition(
        _pictureInPicturePosition(sourceBounds),
        animate: false,
      );
      final size = await windowManager.getSize();
      return size.width <= 500 && size.height <= 300;
    }
    if (Platform.isAndroid) {
      return await windowChannel.invokeMethod<bool>(
            'enterSystemPictureInPicture',
          ) ??
          false;
    }
    if (Platform.isIOS) {
      return await engine?.enterPictureInPicture() ?? false;
    }
    _normalWindowBounds ??= await windowManager.getBounds();
    final sourceBounds = _normalWindowBounds!;
    await windowManager.setResizable(true);
    await windowManager.setAspectRatio(16 / 9);
    await windowManager.setMinimumSize(const Size(220, 124));
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSize(const Size(240, 135), animate: false);
    await windowManager.setPosition(
      _pictureInPicturePosition(sourceBounds),
      animate: false,
    );
    return true;
  } catch (_) {
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
      // MainFlutterWindow owns and restores the original NSWindow frame.
      // Applying the Dart-side bounds as well started a second concurrent
      // AppKit resize animation and could crash in NSWindow._reallySetFrame.
      await windowChannel.invokeMethod<void>('restoreCompactPlayerWindow');
      _normalWindowBounds = null;
      _setVideoOutputSizeInBackground(engine);
      return;
    }
    if (Platform.isAndroid) return; // The system owns the PiP window lifecycle.
    if (Platform.isIOS) return; // AVKit owns the PiP window lifecycle.
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setAspectRatio(0);
    await windowManager.setMinimumSize(
      Platform.isMacOS ? const Size(360, 600) : const Size(380, 600),
    );
    final bounds = _normalWindowBounds;
    if (bounds != null) await windowManager.setBounds(bounds, animate: true);
    _normalWindowBounds = null;
    // Return to source-sized output after leaving the compact window.
    _setVideoOutputSizeInBackground(engine);
  } catch (_) {
    // Ignore when the native window channel is unavailable.
  }
}
