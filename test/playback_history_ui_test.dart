import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yureru/app_state.dart';
import 'package:yureru/data/store.dart';
import 'package:yureru/domain/models.dart';
import 'package:yureru/playback/fake_engine.dart';
import 'package:yureru/presentation/i18n.dart';
import 'package:yureru/presentation/screens/settings_screen.dart';
import 'package:yureru/presentation/theme.dart';

void main() {
  testWidgets(
    'clearing playback history requires confirmation and preserves favorites',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      PackageInfo.setMockInitialValues(
        appName: 'Yureru',
        packageName: 'dev.yureru.yureru',
        version: '1',
        buildNumber: '1',
        buildSignature: '',
      );
      final repository = InMemoryLibraryRepository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(repository),
            engineProvider.overrideWithValue(FakePlaybackEngine()),
            activeLanguageCodeProvider.overrideWithValue('ja'),
          ],
          child: MaterialApp(
            theme: yureruTheme(),
            home: const Scaffold(body: SettingsScreen()),
          ),
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SettingsScreen)),
      );
      final item = MediaItem(
        id: 'track',
        title: 'Track',
        localPath: '/track.mp3',
        isFavorite: true,
        lastPlayedAt: DateTime.utc(2026),
      );
      await container.read(libraryProvider.notifier).addMedia([item]);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, 'ライブラリ'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('再生履歴を消去'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();
      expect(
        container.read(libraryProvider).byId('track')!.lastPlayedAt,
        item.lastPlayedAt,
      );
      await tester.tap(find.text('再生履歴を消去'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(translate('clear', 'ja')));
      await tester.pumpAndSettle();
      expect(
        container.read(libraryProvider).byId('track')!.lastPlayedAt,
        isNull,
      );
      expect(container.read(libraryProvider).byId('track')!.isFavorite, isTrue);
      expect((await repository.loadMedia()).single.lastPlayedAt, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
