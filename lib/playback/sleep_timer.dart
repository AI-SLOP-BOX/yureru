import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SleepTimerState {
  const SleepTimerState({this.deadline, this.mediaId, this.failed = false});
  final DateTime? deadline;
  final String? mediaId;
  final bool failed;
  bool get active => deadline != null || mediaId != null;
}

/// One timer shared by every player layout; never persisted across launches.
class SleepTimer extends StateNotifier<SleepTimerState> {
  SleepTimer(this.pause) : super(const SleepTimerState());
  final Future<void> Function() pause;
  Timer? _timer;
  int _generation = 0;

  void cancel() {
    _generation++;
    _timer?.cancel();
    _timer = null;
    state = const SleepTimerState();
  }

  void after(Duration duration) {
    if (duration <= Duration.zero) throw ArgumentError.value(duration);
    cancel();
    state = SleepTimerState(deadline: DateTime.now().add(duration));
    _timer = Timer(duration, () => unawaited(_expire()));
  }

  void endOfTrack(String mediaId) {
    cancel();
    state = SleepTimerState(mediaId: mediaId);
  }

  void currentChanged(String? id) {
    if (id == null || (state.mediaId != null && state.mediaId != id)) cancel();
  }

  Future<bool> trackEnded(String? id) async {
    if (id == null || state.mediaId != id) return false;
    await _expire();
    return true;
  }

  Future<void> _expire() async {
    cancel();
    final generation = _generation;
    try {
      await pause();
    } catch (_) {
      if (mounted && generation == _generation) {
        state = const SleepTimerState(failed: true);
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
