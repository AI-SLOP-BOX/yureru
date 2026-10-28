import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yureru/platform/keyboard_shortcuts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'custom shortcut bindings persist and format for the platform',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final binding = AppShortcutBinding(
        keyId: LogicalKeyboardKey.keyP.keyId,
        meta: true,
        shift: true,
      );

      await container
          .read(keyboardShortcutsProvider.notifier)
          .setBinding(AppShortcutAction.globalSearch, binding);

      expect(binding.label(macOS: true), '⇧⌘P');
      expect(binding.label(macOS: false), 'Shift+Meta+P');
      final stored = (await SharedPreferences.getInstance()).getString(
        'yureru_keyboard_shortcuts_v1',
      );
      expect(stored, contains('"keyId":112'));

      final restored = ProviderContainer();
      addTearDown(restored.dispose);
      restored.read(keyboardShortcutsProvider);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final loaded = restored.read(
        keyboardShortcutsProvider,
      )[AppShortcutAction.globalSearch];
      expect(loaded?.keyId, LogicalKeyboardKey.keyP.keyId);
      expect(loaded?.meta, isTrue);
      expect(loaded?.shift, isTrue);
    },
  );
}
