import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_state.dart';
import '../../platform/window_utils.dart';
import '../../playback/playback_engine.dart';
import '../i18n.dart';

/// Shared PiP action for the top bar and compact/full player controls.
class PictureInPictureButton extends ConsumerStatefulWidget {
  const PictureInPictureButton({
    super.key,
    required this.engine,
    this.color,
    this.iconSize = 21,
    this.enabled = true,
  });

  final PlaybackEngine engine;
  final Color? color;
  final double iconSize;
  final bool enabled;

  @override
  ConsumerState<PictureInPictureButton> createState() =>
      _PictureInPictureButtonState();
}

class _PictureInPictureButtonState
    extends ConsumerState<PictureInPictureButton> {
  bool _starting = false;

  bool get _isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> _start() async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      final platform = defaultTargetPlatform;
      final isMacOS = platform == TargetPlatform.macOS;
      final isDesktop =
          platform == TargetPlatform.macOS ||
          platform == TargetPlatform.windows ||
          platform == TargetPlatform.linux;
      final pipState = ref.read(pictureInPictureProvider.notifier);
      if (isDesktop && !isMacOS) {
        // Switch to the video-only surface before the compact window shrinks.
        pipState.state = true;
        await WidgetsBinding.instance.endOfFrame;
      }
      final aspectRatio =
          ref.read(playerViewModeProvider) == PlayerViewMode.image
          ? 1.0
          : widget.engine.videoAspectRatio ?? 16 / 9;
      final started = isMacOS
          ? await widget.engine.enterPictureInPicture(aspectRatio: aspectRatio)
          : await enterPictureInPictureWindow(
              engine: widget.engine,
              aspectRatio: aspectRatio,
            );
      if (!started && isDesktop && !isMacOS) {
        pipState.state = false;
      } else if (started && platform != TargetPlatform.iOS && !isMacOS) {
        pipState.state = true;
      }
      if (!started && mounted) {
        final failure = widget.engine.pictureInPictureFailure;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              failure == null || failure.isEmpty
                  ? ref.tr('pip_unavailable')
                  : '${ref.tr('pip_unavailable')}\n$failure',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _restore() async {
    if (_starting) return;
    setState(() => _starting = true);
    try {
      final nativeSystemPip = ref.read(nativeSystemPictureInPictureProvider);
      if (!nativeSystemPip) {
        // Custom desktop PiP uses this same window. Restore its normal size
        // before showing the full player layout again.
        ref.read(pictureInPictureProvider.notifier).state = false;
        await WidgetsBinding.instance.endOfFrame;
      }
      await restorePictureInPictureWindow(engine: widget.engine);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isSupported) return const SizedBox.shrink();
    final normalizationEnabled =
        ref.watch(audioSettingsProvider).valueOrNull ?? false;
    final isPipActive =
        ref.watch(pictureInPictureProvider) ||
        ref.watch(nativeSystemPictureInPictureProvider);
    return StreamBuilder<PlaybackSnapshot>(
      stream: widget.engine.snapshots,
      initialData: widget.engine.snapshot,
      builder: (context, _) {
        final isIos = defaultTargetPlatform == TargetPlatform.iOS;
        final canStart =
            !_starting &&
            (isPipActive ||
                (widget.enabled &&
                    (!isIos ||
                        (!normalizationEnabled &&
                            widget.engine.supportsPictureInPicture))));
        return IconButton(
          tooltip: ref.tr(isPipActive ? 'restore_window' : 'pip'),
          icon: Icon(
            _starting
                ? Icons.hourglass_top_rounded
                : isPipActive
                ? Icons.open_in_full_rounded
                : Icons.picture_in_picture_alt_rounded,
            size: widget.iconSize,
            color: widget.color,
          ),
          onPressed: canStart ? (isPipActive ? _restore : _start) : null,
        );
      },
    );
  }
}
