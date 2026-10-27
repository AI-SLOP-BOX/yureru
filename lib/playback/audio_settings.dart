import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'playback_engine.dart';

/// Audio preferences apply to the engine rather than individual player views.
class AudioSettingsNotifier extends StateNotifier<AsyncValue<bool>> {
  AudioSettingsNotifier(this.engine) : super(const AsyncLoading()) {
    ready = _load();
  }

  static const preferenceKey = 'yureru_volume_normalization_v1';
  final PlaybackEngine engine;
  late final Future<void> ready;

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled =
          engine.supportsVolumeNormalization &&
          (prefs.getBool(preferenceKey) ?? false);
      await engine.setVolumeNormalizationEnabled(enabled);
      if (mounted) state = AsyncData(enabled);
    } catch (error, stack) {
      if (mounted) {
        state = AsyncError<bool>(
          error,
          stack,
        ).copyWithPrevious(const AsyncData(false));
      }
    }
  }

  Future<void> setEnabled(bool enabled) async {
    await ready;
    if (!mounted || state.isLoading || !engine.supportsVolumeNormalization) {
      return;
    }
    final previous = state.valueOrNull ?? false;
    if (previous == enabled && !state.hasError) return;
    state = const AsyncLoading<bool>().copyWithPrevious(AsyncData(previous));
    try {
      await engine.setVolumeNormalizationEnabled(enabled);
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setBool(preferenceKey, enabled)) {
        throw StateError('Audio preference could not be saved');
      }
      if (mounted) state = AsyncData(enabled);
    } catch (error, stack) {
      try {
        await engine.setVolumeNormalizationEnabled(previous);
      } catch (_) {}
      if (mounted) {
        state = AsyncError<bool>(
          error,
          stack,
        ).copyWithPrevious(AsyncData(previous));
      }
    }
  }
}
