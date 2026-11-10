import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'app_state.dart';
import 'presentation/i18n.dart';
import 'presentation/shell.dart';
import 'presentation/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
    await windowManager.ensureInitialized();
  }
  MediaKit.ensureInitialized();
  runApp(const ProviderScope(child: YureruApp()));
}

class YureruApp extends ConsumerWidget {
  const YureruApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeLocale = ref.watch(activeLocaleProvider);
    final isRtl = ref.watch(isRtlProvider);
    final currentThemeMode = ref.watch(themeModeProvider);
    final appearance = ref.watch(appearanceColorsProvider);

    return MaterialApp(
      title: 'Yureru',
      debugShowCheckedModeBanner: false,
      locale: activeLocale,
      theme: yureruLightTheme(
        accentColor: Color(appearance.accent),
        backgroundColor: Color(appearance.lightBackground),
      ),
      darkTheme: yureruDarkTheme(
        accentColor: Color(appearance.accent),
        backgroundColor: Color(appearance.darkBackground),
      ),
      themeMode: currentThemeMode,
      themeAnimationDuration: Duration.zero,
      builder: (context, child) {
        return Directionality(
          textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const AppShell(),
    );
  }
}
