import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppShortcutAction {
  globalSearch,
  focusSearch,
  openFile,
  togglePlayback,
  exitExpandedView,
}

class AppShortcutBinding {
  const AppShortcutBinding({
    required this.keyId,
    this.meta = false,
    this.control = false,
    this.alt = false,
    this.shift = false,
  });

  final int keyId;
  final bool meta;
  final bool control;
  final bool alt;
  final bool shift;

  LogicalKeyboardKey? get key => LogicalKeyboardKey.findKeyByKeyId(keyId);

  bool matches(KeyEvent event, HardwareKeyboard keyboard) =>
      event.logicalKey.keyId == keyId &&
      keyboard.isMetaPressed == meta &&
      keyboard.isControlPressed == control &&
      keyboard.isAltPressed == alt &&
      keyboard.isShiftPressed == shift;

  String label({required bool macOS}) {
    final parts = <String>[];
    if (macOS) {
      if (control) parts.add('⌃');
      if (alt) parts.add('⌥');
      if (shift) parts.add('⇧');
      if (meta) parts.add('⌘');
    } else {
      if (control) parts.add('Ctrl');
      if (alt) parts.add('Alt');
      if (shift) parts.add('Shift');
      if (meta) parts.add('Meta');
    }
    final logicalKey = key;
    final keyLabel = switch (logicalKey) {
      LogicalKeyboardKey k when k == LogicalKeyboardKey.space => 'Space',
      LogicalKeyboardKey k when k == LogicalKeyboardKey.escape => 'Esc',
      _ => logicalKey?.keyLabel.toUpperCase() ?? '?',
    };
    if (macOS) return '${parts.join()}$keyLabel';
    return [...parts, keyLabel].join('+');
  }

  Map<String, Object> toJson() => {
    'keyId': keyId,
    'meta': meta,
    'control': control,
    'alt': alt,
    'shift': shift,
  };

  static AppShortcutBinding? fromJson(Object? value) {
    if (value is! Map) return null;
    final keyId = value['keyId'];
    if (keyId is! int || LogicalKeyboardKey.findKeyByKeyId(keyId) == null) {
      return null;
    }
    return AppShortcutBinding(
      keyId: keyId,
      meta: value['meta'] == true,
      control: value['control'] == true,
      alt: value['alt'] == true,
      shift: value['shift'] == true,
    );
  }
}

bool get _isMacOS => Platform.isMacOS;

Map<AppShortcutAction, AppShortcutBinding> _defaultBindings() {
  final primaryIsMeta = _isMacOS;
  AppShortcutBinding letter(LogicalKeyboardKey key) => AppShortcutBinding(
    keyId: key.keyId,
    meta: primaryIsMeta,
    control: !primaryIsMeta,
  );
  return {
    AppShortcutAction.globalSearch: letter(LogicalKeyboardKey.keyK),
    AppShortcutAction.focusSearch: letter(LogicalKeyboardKey.keyF),
    AppShortcutAction.openFile: letter(LogicalKeyboardKey.keyO),
    AppShortcutAction.togglePlayback: AppShortcutBinding(
      keyId: LogicalKeyboardKey.space.keyId,
    ),
    AppShortcutAction.exitExpandedView: AppShortcutBinding(
      keyId: LogicalKeyboardKey.escape.keyId,
    ),
  };
}

final keyboardShortcutsProvider =
    StateNotifierProvider<
      KeyboardShortcutsNotifier,
      Map<AppShortcutAction, AppShortcutBinding>
    >((ref) => KeyboardShortcutsNotifier());

class KeyboardShortcutsNotifier
    extends StateNotifier<Map<AppShortcutAction, AppShortcutBinding>> {
  static const _storageKey = 'yureru_keyboard_shortcuts_v1';

  KeyboardShortcutsNotifier() : super(_defaultBindings()) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final next = Map<AppShortcutAction, AppShortcutBinding>.of(state);
      for (final action in AppShortcutAction.values) {
        final binding = AppShortcutBinding.fromJson(decoded[action.name]);
        if (binding != null) next[action] = binding;
      }
      state = next;
    } catch (_) {}
  }

  Future<void> setBinding(
    AppShortcutAction action,
    AppShortcutBinding binding,
  ) async {
    state = {...state, action: binding};
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storageKey,
        jsonEncode({
          for (final entry in state.entries)
            entry.key.name: entry.value.toJson(),
        }),
      );
    } catch (_) {}
  }

  Future<void> reset() async {
    state = _defaultBindings();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (_) {}
  }
}

String shortcutActionName(AppShortcutAction action) => switch (action) {
  AppShortcutAction.globalSearch => 'shortcut_global_search',
  AppShortcutAction.focusSearch => 'shortcut_focus_search',
  AppShortcutAction.openFile => 'shortcut_open_file',
  AppShortcutAction.togglePlayback => 'shortcut_toggle_playback',
  AppShortcutAction.exitExpandedView => 'shortcut_exit_expanded_view',
};

bool sameShortcut(AppShortcutBinding a, AppShortcutBinding b) =>
    a.keyId == b.keyId &&
    a.meta == b.meta &&
    a.control == b.control &&
    a.alt == b.alt &&
    a.shift == b.shift;
