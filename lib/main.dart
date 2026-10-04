import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'app_state.dart';
import 'presentation/i18n.dart';
import 'presentation/shell.dart';
import 'presentation/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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

    return MaterialApp(
      title: 'yureru',
      debugShowCheckedModeBanner: false,
      locale: activeLocale,
      theme: yureruLightTheme(),
      darkTheme: yureruDarkTheme(),
      themeMode: currentThemeMode,
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

