import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../i18n.dart';
import '../../platform/keyboard_shortcuts.dart';

/// A small in-app equivalent of the Edit and Window menus on platforms that
/// don't provide an application menu bar (Windows and Linux).
class DesktopMenuBar extends ConsumerWidget {
  const DesktopMenuBar({super.key, required this.onFind});

  final VoidCallback onFind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.windows &&
            defaultTargetPlatform != TargetPlatform.linux)) {
      return const SizedBox.shrink();
    }

    final searchBinding = ref.watch(
      keyboardShortcutsProvider,
    )[AppShortcutAction.globalSearch];
    final searchKey = searchBinding?.key;

    return MenuBar(
      children: [
        SubmenuButton(
          menuChildren: [
            MenuItemButton(
              onPressed: onFind,
              shortcut: searchKey == null
                  ? null
                  : SingleActivator(
                      searchKey,
                      control: searchBinding!.control,
                      meta: searchBinding.meta,
                      alt: searchBinding.alt,
                      shift: searchBinding.shift,
                    ),
              child: Text(ref.tr('menu_find')),
            ),
          ],
          child: Text(ref.tr('menu_edit')),
        ),
        SubmenuButton(
          menuChildren: [
            MenuItemButton(
              onPressed: () => windowManager.minimize(),
              child: Text(ref.tr('menu_minimize')),
            ),
            MenuItemButton(
              onPressed: () async {
                if (await windowManager.isMaximized()) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
              },
              child: Text(ref.tr('menu_toggle_zoom')),
            ),
            MenuItemButton(
              onPressed: () async {
                await windowManager.setFullScreen(
                  !await windowManager.isFullScreen(),
                );
              },
              child: Text(ref.tr('menu_fullscreen')),
            ),
          ],
          child: Text(ref.tr('menu_window')),
        ),
      ],
    );
  }
}
