import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_state.dart';
import 'thumb_image.dart';

class AmbientRoomGlowCanvas extends ConsumerWidget {
  const AmbientRoomGlowCanvas({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final frame = ref.watch(ambientFrameProvider);
    if (!ref.watch(ambientLightProvider)) {
      return const SizedBox.expand();
    }
    final intensity = ref.watch(ambientIntensityProvider);
    if (frame == null) {
      final isVideoMode =
          ref.watch(playerViewModeProvider) == PlayerViewMode.media &&
          ref.read(engineProvider).videoAspectRatio != null;
      // Never use the album/video thumbnail as a full-window blurred layer
      // while a video frame is unavailable. That creates a ghost copy of the
      // video below the player, with a very visible rectangular boundary.
      // Wait for a sampled frame instead; the artwork fallback is only for
      // audio and image playback where no moving video frame exists.
      if (isVideoMode) return const SizedBox.expand();

      final queue = ref.watch(queueProvider);
      final library = ref.watch(libraryProvider);
      final media = queue.currentId == null
          ? null
          : library.byId(queue.currentId!);
      if (media == null) return const SizedBox.expand();

      // Audio tracks and artwork mode have no video frame to sample. Use the
      // current cover as a soft light source so Ambient mode still responds.
      return IgnorePointer(
        child: Opacity(
          opacity: (intensity * 0.4).clamp(0.0, 0.4).toDouble(),
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 144, sigmaY: 144),
            child: Transform.scale(
              scale: 1.35,
              child: ThumbImage(
                seed: media.id,
                mediaId: media.id,
                localPath: media.localPath,
                radius: 0,
                expand: true,
                highRes: true,
              ),
            ),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        // Edge profiles are already diffused in renderAmbientGlow. Apply only
        // a small final softening pass here; a window-sized sigma erased the
        // color falloff and turned the whole shell into gray fog.
        // The source glow is only 320×180 and is already spatially softened
        // as it leaves the video. Keep this final pass below one source pixel
        // on typical windows so it blends interpolation without smearing the
        // sky/mountain boundary into a foggy band.
        final sigma = (constraints.maxHeight * 0.005)
            .clamp(2.0, 6.0)
            .toDouble();
        return IgnorePointer(
          child: Opacity(
            opacity: intensity.clamp(0.0, 1.0).toDouble(),
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
              child: RawImage(
                image: frame,
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                fit: BoxFit.fill,
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),
        );
      },
    );
  }
}

class AmbientToolbarGlow extends ConsumerWidget {
  const AmbientToolbarGlow({super.key, this.opacity = 0.28});

  final double opacity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final frame = ref.watch(ambientFrameProvider);
    if (frame == null) return const SizedBox.expand();
    final intensity = ref.watch(ambientIntensityProvider);
    final image = RawImage(
      image: frame,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.medium,
    );
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 120),
      switchInCurve: Curves.linear,
      switchOutCurve: Curves.linear,
      child: IgnorePointer(
        key: ObjectKey(frame),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // A tight, saturated edge keeps the light visibly attached to the
            // video. The broad spill adds the sense that it continues outward.
            Opacity(
              opacity: (opacity * intensity * 0.95).clamp(0.0, 0.7).toDouble(),
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 34, sigmaY: 24),
                child: image,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
