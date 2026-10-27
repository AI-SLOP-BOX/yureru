import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AmbientLightNotifier extends StateNotifier<bool> {
  static const _key = 'yureru_ambient_light_enabled_v1';

  AmbientLightNotifier() : super(true) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getBool(_key) ?? true;
    } catch (_) {}
  }

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, enabled);
    } catch (_) {}
  }
}

final ambientLightProvider = StateNotifierProvider<AmbientLightNotifier, bool>((
  _,
) {
  return AmbientLightNotifier();
});

class AmbientIntensityNotifier extends StateNotifier<double> {
  static const _key = 'yureru_ambient_intensity_v1';
  AmbientIntensityNotifier() : super(1.0) {
    _load();
  }
  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = (prefs.getDouble(_key) ?? 1.0).clamp(0.5, 1.5);
    } catch (_) {}
  }

  void setIntensity(double value) {
    state = value.clamp(0.5, 1.5);
  }

  Future<void> persistIntensity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_key, state);
    } catch (_) {}
  }
}

final ambientIntensityProvider =
    StateNotifierProvider<AmbientIntensityNotifier, double>(
      (_) => AmbientIntensityNotifier(),
    );

class AmbientGeometrySettings {
  const AmbientGeometrySettings({
    this.spread = 1.0,
    this.depth = 1.0,
    this.softness = 1.0,
  });

  final double spread;
  final double depth;
  final double softness;

  AmbientGeometrySettings copyWith({
    double? spread,
    double? depth,
    double? softness,
  }) => AmbientGeometrySettings(
    spread: spread ?? this.spread,
    depth: depth ?? this.depth,
    softness: softness ?? this.softness,
  );
}

class AmbientGeometryNotifier extends StateNotifier<AmbientGeometrySettings> {
  static const _spreadKey = 'yureru_ambient_spread_v1';
  static const _depthKey = 'yureru_ambient_depth_v1';
  static const _softnessKey = 'yureru_ambient_softness_v1';

  AmbientGeometryNotifier() : super(const AmbientGeometrySettings()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = AmbientGeometrySettings(
        spread: (prefs.getDouble(_spreadKey) ?? 1).clamp(0.5, 1.5),
        depth: (prefs.getDouble(_depthKey) ?? 1).clamp(0, 2),
        softness: (prefs.getDouble(_softnessKey) ?? 1).clamp(0.5, 1.5),
      );
    } catch (_) {}
  }

  void setSpread(double value) =>
      state = state.copyWith(spread: value.clamp(0.5, 1.5));

  void setDepth(double value) =>
      state = state.copyWith(depth: value.clamp(0, 2));

  void setSoftness(double value) =>
      state = state.copyWith(softness: value.clamp(0.5, 1.5));

  Future<void> persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_spreadKey, state.spread);
      await prefs.setDouble(_depthKey, state.depth);
      await prefs.setDouble(_softnessKey, state.softness);
    } catch (_) {}
  }
}

final ambientGeometryProvider =
    StateNotifierProvider<AmbientGeometryNotifier, AmbientGeometrySettings>(
      (_) => AmbientGeometryNotifier(),
    );

class AmbientFrameRateNotifier extends StateNotifier<int> {
  static const _key = 'yureru_ambient_frame_rate_v1';

  AmbientFrameRateNotifier() : super(0) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt(_key) ?? 0;
      state = const [0, 15, 30, 60].contains(saved) ? saved : 0;
    } catch (_) {}
  }

  void setFrameRate(int value) {
    if (const [0, 15, 30, 60].contains(value)) state = value;
  }

  Future<void> persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_key, state);
    } catch (_) {}
  }
}

final ambientFrameRateProvider =
    StateNotifierProvider<AmbientFrameRateNotifier, int>(
      (_) => AmbientFrameRateNotifier(),
    );
