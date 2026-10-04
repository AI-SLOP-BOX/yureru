import 'dart:io';
import 'package:flutter/services.dart';

/// Platform window management channels and helpers.
const windowChannel = MethodChannel('yureru/media_picker');

/// Toggle fullscreen display across desktop platforms (macOS / Linux / Windows).
Future<void> toggleFullscreen() async {
  if (!Platform.isMacOS) return;
  try {
    await windowChannel.invokeMethod('toggleFullscreen');
  } catch (_) {
    // Channel not available (e.g. tests or headless): ignore.
  }
}
