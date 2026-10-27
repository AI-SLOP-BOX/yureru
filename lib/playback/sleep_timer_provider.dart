import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app_state.dart';
import 'playback_controller.dart';
import 'sleep_timer.dart';

final sleepTimerProvider = StateNotifierProvider<SleepTimer, SleepTimerState>((
  ref,
) {
  final timer = SleepTimer(
    () => ref.read(playbackControllerProvider).pauseAndRemember(),
  );
  ref.listen(queueProvider.select((queue) => queue.currentId), (_, id) {
    timer.currentChanged(id);
  });
  return timer;
});
