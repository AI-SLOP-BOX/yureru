import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

/// Platform window management channels and helpers.
const windowChannel = MethodChannel('yureru/media_picker');
Rect? _normalWindowBounds;

/// Toggle fullscreen display across desktop platforms (macOS / Linux / Windows).
Future<void> toggleFullscreen() async {
  if (!Platform.isMacOS) return;
  try {
    await windowChannel.invokeMethod('toggleFullscreen');
  } catch (_) {
    // Channel not available (e.g. tests or headless): ignore.
  }
}

/// Resize the desktop app into a small, floating player window.
Future<void> setPictureInPictureWindow(bool enabled) async {
  if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) return;
  try {
    if (enabled) {
      _normalWindowBounds ??= await windowManager.getBounds();
      await windowManager.setResizable(true);
      await windowManager.setMinimumSize(const Size(280, 180));
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setSize(const Size(480, 300), animate: true);
      await windowManager.setAlignment(Alignment.bottomRight, animate: true);
    } else {
      await windowManager.setAlwaysOnTop(false);
      await windowManager.setMinimumSize(const Size(380, 600));
      final bounds = _normalWindowBounds;
      if (bounds != null) {
        await windowManager.setBounds(bounds, animate: true);
      }
      _normalWindowBounds = null;
    }
  } catch (_) {
    // Ignore when the native window channel is unavailable (for example tests).
  }
}
