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
        final aperture = ref.watch(ambientVideoApertureProvider);
        final isVideoMode =
            ref.watch(playerViewModeProvider) == PlayerViewMode.media &&
            ref.read(engineProvider).videoAspectRatio != null;
        // Do not show an unmasked first frame while the player bounds are
        // still being measured. Once available, the glow remains in the app
        // area around the player and is cut out over the video itself.
        if (isVideoMode && aperture == null) return const SizedBox.expand();
        // A moderate final blur removes the last scanline-like edge streaks
        // while preserving the broad color gradients of the room glow.
        final sigma = (constraints.maxHeight * 0.015)
            .clamp(8.0, 16.0)
            .toDouble();
        return IgnorePointer(
          child: Opacity(
            opacity: intensity.clamp(0.0, 1.0).toDouble(),
            // Blur can spread opaque edge colors into the transparent video
            // aperture in the source image. Cut the actual player rectangle
            // back out after filtering so ambient light never washes over the
            // moving picture itself.
            child: ClipPath(
              clipper: _AmbientApertureClipper(aperture),
              clipBehavior: Clip.antiAlias,
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
          ),
        );
      },
    );
  }
}

class _AmbientApertureClipper extends CustomClipper<Path> {
  const _AmbientApertureClipper(this.aperture);

  final Rect? aperture;

  @override
  Path getClip(Size size) {
    final path = Path()..addRect(Offset.zero & size);
    final normalized = aperture;
    if (normalized == null || size.isEmpty) return path;

    // Match the 20 px rounded video card, with a one-pixel safety inset to
    // prevent anti-aliased filtering from leaving a colored fringe on its edge.
    final videoRect = Rect.fromLTRB(
      normalized.left * size.width,
      normalized.top * size.height,
      normalized.right * size.width,
      normalized.bottom * size.height,
    ).inflate(1);
    final radius = Radius.circular(21);
    return path
      ..fillType = PathFillType.evenOdd
      ..addRRect(RRect.fromRectAndRadius(videoRect, radius));
  }

  @override
  bool shouldReclip(covariant _AmbientApertureClipper oldClipper) =>
      oldClipper.aperture != aperture;
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
