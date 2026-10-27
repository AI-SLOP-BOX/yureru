import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_state.dart';
import '../../playback/sleep_timer_provider.dart';
import '../i18n.dart';
import 'app_svg_icon.dart';

class SleepTimerButton extends ConsumerWidget {
  const SleepTimerButton({super.key, this.onEditingChanged});
  final ValueChanged<bool>? onEditingChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sleepTimerProvider);
    final currentId = ref.watch(queueProvider.select((q) => q.currentId));
    String minutesLabel(int minutes) =>
        ref.tr('sleep_minutes').replaceAll('{minutes}', '$minutes');
    final status = state.failed
        ? ref.tr('sleep_failed')
        : state.mediaId != null
        ? ref.tr('sleep_track')
        : state.deadline != null
        ? '${ref.tr('sleep_timer')} · ${minutesLabel(((state.deadline!.difference(DateTime.now()).inSeconds / 60).ceil()).clamp(0, 60))}'
        : ref.tr('sleep_timer');
    return PopupMenuButton<int>(
      tooltip: status,
      icon: AppSvgIcon(
        'sleep_timer',
        color: state.active ? Theme.of(context).colorScheme.primary : null,
      ),
      onOpened: () => onEditingChanged?.call(true),
      onCanceled: () => onEditingChanged?.call(false),
      onSelected: (value) {
        onEditingChanged?.call(false);
        final timer = ref.read(sleepTimerProvider.notifier);
        if (value == 0) {
          timer.cancel();
        } else if (value == -1) {
          final id = ref.read(queueProvider).currentId;
          if (id != null) timer.endOfTrack(id);
        } else {
          timer.after(Duration(minutes: value));
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem<int>(enabled: false, child: Text(status)),
        const PopupMenuDivider(),
        for (final minutes in [15, 30, 60])
          PopupMenuItem(value: minutes, child: Text(minutesLabel(minutes))),
        PopupMenuItem(
          value: -1,
          enabled: currentId != null,
          child: Text(ref.tr('sleep_track')),
        ),
        PopupMenuItem(
          value: 0,
          enabled: state.active || state.failed,
          child: Text(ref.tr('sleep_off')),
        ),
      ],
    );
  }
}
