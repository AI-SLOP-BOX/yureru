import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_state.dart';
import '../../playback/playback_engine.dart';
import '../i18n.dart';

/// Shows a clear in-app placeholder while macOS owns playback in system PiP.
class PipVideoSurface extends ConsumerWidget {
  const PipVideoSurface({
    super.key,
    required this.engine,
    this.fit = BoxFit.contain,
  });

  final PlaybackEngine engine;
  final BoxFit fit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSystemPipActive =
        defaultTargetPlatform == TargetPlatform.macOS &&
        ref.watch(nativeSystemPictureInPictureProvider);
    if (!isSystemPipActive) return engine.buildVideoView(fit: fit);

    return LayoutBuilder(
      builder: (context, constraints) {
        final shortestSide = constraints.biggest.shortestSide;
        final iconSize = (shortestSide * 0.19).clamp(56.0, 136.0);
        final fontSize = (constraints.maxWidth * 0.05).clamp(26.0, 34.0);
        return ColoredBox(
          color: const Color(0xFF101010),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.picture_in_picture_alt_rounded,
                    color: Colors.white,
                    size: iconSize,
                  ),
                  const SizedBox(height: 28),
                  Text(
                    ref.tr('pip_playing_message'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: fontSize,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
