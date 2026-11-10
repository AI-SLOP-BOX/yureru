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
        final size = constraints.biggest;
        final shortestSide = size.shortestSide;
        final iconSize = (shortestSide * 0.17).clamp(40.0, 112.0);
        // PiP windows can be short even when they are fairly wide. Scale the
        // notice from both dimensions so translated text stays inside the
        // visible video surface instead of being clipped at the bottom.
        final fontSize = (shortestSide * 0.055).clamp(14.0, 25.0);
        return ColoredBox(
          color: const Color(0xFF101010),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: size.width,
                maxHeight: size.height,
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(
                  width: (size.width - 32).clamp(1.0, double.infinity),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 12,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.picture_in_picture_alt_rounded,
                          color: Colors.white,
                          size: iconSize,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          ref.tr('pip_playing_message'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: fontSize,
                            height: 1.25,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
