import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yureru/app_state.dart';
import 'package:yureru/data/store.dart';
import 'package:yureru/playback/fake_engine.dart';
import 'package:yureru/presentation/i18n.dart';
import 'package:yureru/presentation/screens/settings_screen.dart';
import 'package:yureru/presentation/theme.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Yureru',
      packageName: 'dev.yureru.yureru',
      version: '1',
      buildNumber: '1',
      buildSignature: '',
    );
  });
  for (final size in [
    const Size(360, 600),
    const Size(740, 360),
    const Size(1280, 900),
  ]) {
    testWidgets(
      'categories make settings reachable at $size with enlarged text',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              engineProvider.overrideWithValue(FakePlaybackEngine()),
              repositoryProvider.overrideWithValue(InMemoryLibraryRepository()),
              activeLanguageCodeProvider.overrideWithValue('ja'),
            ],
            child: MaterialApp(
              theme: yureruTheme(isDark: false),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(1.4)),
                child: child!,
              ),
              home: const Scaffold(body: SettingsScreen()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final container = ProviderScope.containerOf(
          tester.element(find.byType(SettingsScreen)),
        );
        final audioCategory = size.width >= 900
            ? find.byKey(const ValueKey('settings-category-settings_audio'))
            : find.widgetWithText(
                ChoiceChip,
                translate('settings_audio', 'ja'),
              );
        await tester.ensureVisible(audioCategory);
        await tester.tap(audioCategory);
        await tester.pumpAndSettle();
        final normalization = find.byKey(
          const ValueKey('volume-normalization'),
        );
        await tester.ensureVisible(normalization);
        await tester.tap(normalization);
        await tester.pumpAndSettle();
        expect(container.read(audioSettingsProvider).value, true);
        expect(find.text('テーマ'), findsNothing);
        final appCategory = size.width >= 900
            ? find.byKey(const ValueKey('settings-category-settings_app'))
            : find.widgetWithText(ChoiceChip, 'アプリ');
        await tester.ensureVisible(appCategory);
        await tester.tap(appCategory);
        await tester.pumpAndSettle();
        final dropdown = find.byType(DropdownButton<AppLanguage>);
        await tester.ensureVisible(dropdown);
        await tester.tap(dropdown);
        await tester.pumpAndSettle();
        expect(find.text('日本語').hitTestable(), findsWidgets);
        await tester.tap(find.text('日本語').last);
        await tester.pumpAndSettle();
        expect(container.read(languageProvider), AppLanguage.ja);
        final displayCategory = size.width >= 900
            ? find.byKey(const ValueKey('settings-category-settings_display'))
            : find.widgetWithText(ChoiceChip, '表示');
        await tester.ensureVisible(displayCategory);
        await tester.tap(displayCategory);
        await tester.pumpAndSettle();
        expect(find.text('テーマ'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
