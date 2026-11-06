import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum VideoLyricsPosition {
  topLeft,
  topCenter,
  topRight,
  centerLeft,
  center,
  centerRight,
  bottomLeft,
  bottomCenter,
  bottomRight,
}

enum VideoLyricsFrame { none, outline, plate }

class VideoLyricsSettings {
  const VideoLyricsSettings({
    this.enabled = false,
    this.position = VideoLyricsPosition.bottomCenter,
    this.positionX = 0.5,
    this.positionY = 0.84,
    this.fontSize = 30,
    this.fontFamily = 'system',
    this.color = 0xFFFFFFFF,
    this.frame = VideoLyricsFrame.outline,
  });

  final bool enabled;
  final VideoLyricsPosition position;

  /// Normalized center point inside the video frame (0..1 on each axis).
  final double positionX;
  final double positionY;
  final double fontSize;
  final String fontFamily;
  final int color;
  final VideoLyricsFrame frame;

  VideoLyricsSettings copyWith({
    bool? enabled,
    VideoLyricsPosition? position,
    double? positionX,
    double? positionY,
    double? fontSize,
    String? fontFamily,
    int? color,
    VideoLyricsFrame? frame,
  }) => VideoLyricsSettings(
    enabled: enabled ?? this.enabled,
    position: position ?? this.position,
    positionX: (positionX ?? this.positionX).clamp(0.0, 1.0).toDouble(),
    positionY: (positionY ?? this.positionY).clamp(0.0, 1.0).toDouble(),
    fontSize: fontSize ?? this.fontSize,
    fontFamily: fontFamily ?? this.fontFamily,
    color: color ?? this.color,
    frame: frame ?? this.frame,
  );

  Map<String, Object> toJson() => {
    'enabled': enabled,
    'position': position.name,
    'positionX': positionX,
    'positionY': positionY,
    'fontSize': fontSize,
    'fontFamily': fontFamily,
    'color': color,
    'frame': frame.name,
  };

  factory VideoLyricsSettings.fromJson(Map<String, dynamic> json) {
    T enumValue<T extends Enum>(List<T> values, Object? raw, T fallback) =>
        values.where((value) => value.name == raw).firstOrNull ?? fallback;

    final position = enumValue(
      VideoLyricsPosition.values,
      json['position'],
      VideoLyricsPosition.bottomCenter,
    );
    return VideoLyricsSettings(
      enabled: json['enabled'] == true,
      position: position,
      positionX:
          ((json['positionX'] as num?)?.toDouble() ?? _defaultXFor(position))
              .clamp(0.0, 1.0)
              .toDouble(),
      positionY:
          ((json['positionY'] as num?)?.toDouble() ?? _defaultYFor(position))
              .clamp(0.0, 1.0)
              .toDouble(),
      fontSize: ((json['fontSize'] as num?)?.toDouble() ?? 30).clamp(16, 56),
      fontFamily: switch (json['fontFamily']) {
        'serif' => 'serif',
        'monospace' => 'monospace',
        _ => 'system',
      },
      color: (json['color'] as int?) ?? 0xFFFFFFFF,
      frame: enumValue(
        VideoLyricsFrame.values,
        json['frame'],
        VideoLyricsFrame.outline,
      ),
    );
  }
}

double _defaultXFor(VideoLyricsPosition position) => switch (position) {
  VideoLyricsPosition.topLeft ||
  VideoLyricsPosition.centerLeft ||
  VideoLyricsPosition.bottomLeft => 0.15,
  VideoLyricsPosition.topRight ||
  VideoLyricsPosition.centerRight ||
  VideoLyricsPosition.bottomRight => 0.85,
  _ => 0.5,
};

double _defaultYFor(VideoLyricsPosition position) => switch (position) {
  VideoLyricsPosition.topLeft ||
  VideoLyricsPosition.topCenter ||
  VideoLyricsPosition.topRight => 0.16,
  VideoLyricsPosition.centerLeft ||
  VideoLyricsPosition.center ||
  VideoLyricsPosition.centerRight => 0.5,
  _ => 0.84,
};

class VideoLyricsSettingsNotifier extends StateNotifier<VideoLyricsSettings> {
  static const _key = 'yureru_video_lyrics_settings_v1';

  VideoLyricsSettingsNotifier() : super(const VideoLyricsSettings()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        state = VideoLyricsSettings.fromJson(decoded);
      }
    } catch (_) {}
  }

  void update(VideoLyricsSettings next) {
    state = next;
  }

  Future<void> persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(state.toJson()));
    } catch (_) {}
  }
}

final videoLyricsSettingsProvider =
    StateNotifierProvider<VideoLyricsSettingsNotifier, VideoLyricsSettings>(
      (_) => VideoLyricsSettingsNotifier(),
    );
