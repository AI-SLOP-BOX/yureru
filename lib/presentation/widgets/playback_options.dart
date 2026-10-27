import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_state.dart';
import '../../playback/playback_controller.dart';
import '../i18n.dart';
import '../theme.dart';
import 'app_svg_icon.dart';
import 'repeat_icon.dart';
import 'transport_icon.dart';

class PlaybackShuffleButton extends ConsumerWidget {
  const PlaybackShuffleButton({
    super.key,
    this.activeColor,
    this.inactiveColor,
  });
  final Color? activeColor;
  final Color? inactiveColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(queueProvider);
    return IconButton(
      tooltip: ref.tr('shuffle'),
      isSelected: queue.shuffle,
      icon: TransportIcon.shuffle(
        size: 20,
        color: queue.shuffle
            ? activeColor ?? themeTextPrimary(context)
            : inactiveColor ?? themeTextSub(context),
      ),
      onPressed: queue.hasCurrent
          ? ref.read(queueProvider.notifier).toggleShuffle
          : null,
    );
  }
}

class PlaybackRepeatButton extends ConsumerWidget {
  const PlaybackRepeatButton({super.key, this.activeColor, this.inactiveColor});
  final Color? activeColor;
  final Color? inactiveColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(queueProvider);
    return IconButton(
      tooltip: ref.tr('repeat_${queue.repeat}'),
      isSelected: queue.repeat != 'off',
      icon: RepeatIcon(
        size: 20,
        repeatMode: queue.repeat,
        color: queue.repeat == 'off'
            ? inactiveColor ?? themeTextSub(context)
            : activeColor ?? themeTextPrimary(context),
      ),
      onPressed: queue.hasCurrent
          ? ref.read(queueProvider.notifier).cycleRepeat
          : null,
    );
  }
}

/// A compact entry point to the same volume state used by all player layouts.
class PlaybackVolumeButton extends ConsumerWidget {
  const PlaybackVolumeButton({super.key, this.onEditingChanged});
  final ValueChanged<bool>? onEditingChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final volume = ref.watch(volumeProvider);
    return IconButton(
      tooltip: ref.tr('volume'),
      icon: AppSvgIcon(
        volume == 0 ? 'volume_off' : 'volume',
        color: Colors.white,
      ),
      onPressed: () async {
        onEditingChanged?.call(true);
        try {
          await showDialog<void>(
            context: context,
            builder: (context) => const _VolumeDialog(),
          );
        } finally {
          onEditingChanged?.call(false);
        }
      },
    );
  }
}

class _VolumeDialog extends ConsumerWidget {
  const _VolumeDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final volume = ref.watch(volumeProvider);
    final controller = ref.read(playbackControllerProvider);
    return AlertDialog(
      title: Text(ref.tr('volume')),
      content: SizedBox(
        width: 320,
        child: Row(
          children: [
            IconButton(
              tooltip: ref.tr(volume == 0 ? 'unmute' : 'mute'),
              icon: AppSvgIcon(volume == 0 ? 'volume_off' : 'volume'),
              onPressed: controller.toggleMute,
            ),
            Expanded(
              child: Slider(
                value: volume.clamp(0, 1),
                semanticFormatterCallback: (value) =>
                    '${(value * 100).round()}%',
                onChanged: controller.setVolume,
              ),
            ),
            SizedBox(
              width: 42,
              child: Text(
                '${(volume * 100).round()}%',
                textAlign: TextAlign.end,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(ref.tr('close')),
        ),
      ],
    );
  }
}
