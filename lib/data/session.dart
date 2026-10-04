import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_state.dart';

/// Last session: queue layout + per-video positions. Restored on launch
/// (paused, no autoplay) so playback resumes where it stopped.
class SessionStore {
  const SessionStore();
  static const _kQueue = 'yureru.session.queue.v1';
  static const _kPositions = 'yureru.session.positions.v1';
  static const _kMaxPositions = 200;

  Future<void> saveQueue(QueueState s) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kQueue, jsonEncode(s.toJson()));
    } catch (_) {}
  }

  Future<QueueState?> loadQueue() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kQueue);
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final s = QueueState.fromJson(Map<String, dynamic>.from(decoded));
      return s.queue.isEmpty ? null : s;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, int>> loadPositions() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kPositions);
      if (raw == null) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final out = <String, int>{};
      decoded.forEach((k, v) {
        if (k is String && v is num && v > 0) out[k] = v.toInt();
      });
      return out;
    } catch (_) {
      return {};
    }
  }

  /// Remember [ms] for [id]; most-recently-touched ids are kept.
  Future<void> savePosition(String id, int ms) async {
    if (ms <= 0) return;
    try {
      final all = await loadPositions();
      all.remove(id);
      all[id] = ms;
      while (all.length > _kMaxPositions) {
        all.remove(all.keys.first);
      }
      final p = await SharedPreferences.getInstance();
      await p.setString(_kPositions, jsonEncode(all));
    } catch (_) {}
  }
}

final sessionStoreProvider = Provider<SessionStore>((_) => SessionStore());
