import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    final remainingMinutes = state.deadline == null
        ? null
        : (state.deadline!.difference(DateTime.now()).inSeconds / 60)
              .ceil()
              .clamp(0, 24 * 60);
    final remainingLabel = remainingMinutes == null
        ? null
        : remainingMinutes >= 60
        ? '${remainingMinutes ~/ 60}:${(remainingMinutes % 60).toString().padLeft(2, '0')}'
        : minutesLabel(remainingMinutes);
    final status = state.failed
        ? ref.tr('sleep_failed')
        : state.mediaId != null
        ? ref.tr('sleep_track')
        : remainingLabel != null
        ? '${ref.tr('sleep_timer')} · $remainingLabel'
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
        } else if (value == -2) {
          _selectDuration(context, ref).then((duration) {
            if (duration != null && context.mounted) timer.after(duration);
          });
        } else {
          timer.after(Duration(minutes: value));
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem<int>(enabled: false, child: Text(status)),
        const PopupMenuDivider(),
        for (final minutes in [15, 30, 60])
          PopupMenuItem(value: minutes, child: Text(minutesLabel(minutes))),
        PopupMenuItem(value: -2, child: Text(ref.tr('sleep_custom_duration'))),
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

  Future<Duration?> _selectDuration(BuildContext context, WidgetRef ref) async {
    return showDialog<Duration>(
      context: context,
      builder: (_) => _SleepDurationDialog(
        title: ref.tr('sleep_custom_duration'),
        hoursLabel: ref.tr('sleep_hours_label'),
        minutesLabel: ref.tr('sleep_minutes_label'),
        cancelLabel: ref.tr('cancel'),
        saveLabel: ref.tr('save'),
      ),
    );
  }
}

class _SleepDurationDialog extends StatefulWidget {
  const _SleepDurationDialog({
    required this.title,
    required this.hoursLabel,
    required this.minutesLabel,
    required this.cancelLabel,
    required this.saveLabel,
  });

  final String title;
  final String hoursLabel;
  final String minutesLabel;
  final String cancelLabel;
  final String saveLabel;

  @override
  State<_SleepDurationDialog> createState() => _SleepDurationDialogState();
}

class _SleepDurationDialogState extends State<_SleepDurationDialog> {
  final _hours = TextEditingController(text: '0');
  final _minutes = TextEditingController(text: '30');

  @override
  void dispose() {
    _hours.dispose();
    _minutes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hours = int.tryParse(_hours.text) ?? -1;
    final minutes = int.tryParse(_minutes.text) ?? -1;
    final valid =
        hours >= 0 &&
        hours <= 23 &&
        minutes >= 0 &&
        minutes <= 59 &&
        hours * 60 + minutes > 0;

    void submit() =>
        Navigator.pop(context, Duration(hours: hours, minutes: minutes));

    return AlertDialog(
      title: Text(widget.title),
      content: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _hours,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: widget.hoursLabel),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: TextField(
              controller: _minutes,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(labelText: widget.minutesLabel),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (valid) submit();
              },
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(
          onPressed: valid ? submit : null,
          child: Text(widget.saveLabel),
        ),
      ],
    );
  }
}
