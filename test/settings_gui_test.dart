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
        if (size.width < 900) {
          expect(
            find.byKey(const ValueKey('settings-category-scroll-left')),
            findsNothing,
          );
          final scrollRight = find.byKey(
            const ValueKey('settings-category-scroll-right'),
          );
          expect(scrollRight, findsOneWidget);
          final allCategory = find.byKey(
            const ValueKey('settings-category-all'),
          );
          final allCategoryXBefore = tester.getTopLeft(allCategory).dx;
          await tester.tap(scrollRight);
          await tester.pumpAndSettle();
          final allCategoryShift =
              allCategoryXBefore - tester.getTopLeft(allCategory).dx;
          expect(allCategoryShift, greaterThan(0));
          expect(allCategoryShift, lessThan(size.width * 0.6));
          for (
            var tap = 0;
            tap < 8 && scrollRight.evaluate().isNotEmpty;
            tap++
          ) {
            await tester.tap(scrollRight);
            await tester.pump(const Duration(milliseconds: 40));
          }
          await tester.pumpAndSettle();
          expect(
            find.widgetWithText(ChoiceChip, 'アプリ').hitTestable(),
            findsOneWidget,
          );
          final scrollLeft = find.byKey(
            const ValueKey('settings-category-scroll-left'),
          );
          expect(scrollLeft, findsOneWidget);
          for (
            var tap = 0;
            tap < 8 && scrollLeft.evaluate().isNotEmpty;
            tap++
          ) {
            await tester.tap(scrollLeft);
            await tester.pumpAndSettle();
          }
          expect(scrollLeft, findsNothing);
          expect(
            find.widgetWithText(ChoiceChip, 'すべて').hitTestable(),
            findsOneWidget,
          );
        }
        final container = ProviderScope.containerOf(
          tester.element(find.byType(SettingsScreen)),
        );
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

        final imagePriorityCategory = size.width >= 900
            ? find.byKey(
                const ValueKey('settings-category-settings_image_priority'),
              )
            : find.widgetWithText(ChoiceChip, '画像の表示優先度');
        await tester.ensureVisible(imagePriorityCategory);
        await tester.tap(imagePriorityCategory);
        await tester.pumpAndSettle();
        expect(find.text('ホーム'), findsOneWidget);
        expect(find.text('プレイリスト'), findsOneWidget);
        expect(find.text('アルバム'), findsOneWidget);

        await tester.tap(find.text('サムネイル').first);
        await tester.pumpAndSettle();
        expect(
          container.read(mediaImagePriorityProvider)[MediaImageContext.home],
          MediaImagePriority.thumbnailFirst,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
