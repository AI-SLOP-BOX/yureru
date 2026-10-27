import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yureru/app_state.dart';
import 'package:yureru/data/store.dart';
import 'package:yureru/domain/models.dart';
import 'package:yureru/playback/fake_engine.dart';
import 'package:yureru/presentation/i18n.dart';
import 'package:yureru/presentation/screens/videos_screen.dart';
import 'package:yureru/presentation/theme.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<ProviderContainer> pump(
    WidgetTester tester,
    Size size, {
    double scale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(InMemoryLibraryRepository()),
          engineProvider.overrideWithValue(FakePlaybackEngine()),
          activeLanguageCodeProvider.overrideWithValue('ja'),
        ],
        child: MaterialApp(
          theme: yureruTheme(isDark: scale == 1),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const Scaffold(body: VideosScreen()),
        ),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(VideosScreen)),
    );
    await container.read(libraryProvider.notifier).addMedia([
      MediaItem(
        id: 'a',
        title: '長い曲名でも読みやすく並ぶテストの曲',
        artist: 'Artist',
        album: 'Night Album',
        isFavorite: true,
        durationMs: 120000,
        localPath: '/missing/a',
      ),
      MediaItem(
        id: 'b',
        title: 'Other',
        artist: 'Other Artist',
        localPath: '/missing/b',
        durationMs: 180000,
      ),
    ]);
    await tester.pumpAndSettle();
    return container;
  }

  for (final entry in [
    (const Size(360, 600), 1.4),
    (const Size(740, 360), 1.0),
  ]) {
    testWidgets(
      'filters remain clear and can be reset at ${entry.$1} scale ${entry.$2}',
      (tester) async {
        final container = await pump(tester, entry.$1, scale: entry.$2);
        container.read(videosSortProvider.notifier).state = VideosSort.name;
        container.read(favoritesOnlyProvider.notifier).state = true;
        container.read(videoCreatorFilterProvider.notifier).state = 'Artist';
        container.read(searchQueryProvider.notifier).state = 'missing';
        await tester.pumpAndSettle();
        expect(find.text('お気に入り'), findsOneWidget);
        expect(find.text('名前順'), findsOneWidget);
        expect(find.text('投稿者: Artist'), findsOneWidget);
        expect(find.text('検索: missing'), findsOneWidget);
        expect(find.byType(ReorderableListView), findsNothing);
        await tester.tap(find.widgetWithText(TextButton, '絞り込みを解除'));
        await tester.pumpAndSettle();
        expect(container.read(searchQueryProvider), '');
        expect(container.read(videoCreatorFilterProvider), isNull);
        expect(container.read(favoritesOnlyProvider), false);
        expect(container.read(videosSortProvider), VideosSort.name);
        expect(find.text('Other'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('album search and removable search chip preserve other filters', (
    tester,
  ) async {
    final container = await pump(tester, const Size(390, 844));
    container.read(searchQueryProvider.notifier).state = 'night album';
    container.read(favoritesOnlyProvider.notifier).state = true;
    await tester.pumpAndSettle();
    expect(find.text('Other'), findsNothing);
    final chip = tester.widget<InputChip>(find.byType(InputChip));
    chip.onDeleted!();
    await tester.pumpAndSettle();
    expect(container.read(searchQueryProvider), '');
    expect(container.read(favoritesOnlyProvider), true);
    expect(find.text('Other'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening a distant search result scrolls its row into view', (
    tester,
  ) async {
    final container = await pump(tester, const Size(390, 844));
    await container
        .read(libraryProvider.notifier)
        .addMedia(
          List.generate(
            80,
            (i) => MediaItem(
              id: 'extra-$i',
              title: 'Track $i',
              localPath: '/missing/$i',
              durationMs: 1000,
            ),
          ),
        );
    container.read(videosSortProvider.notifier).state = VideosSort.oldestFirst;
    await tester.pumpAndSettle();
    container.read(videoOpenRequestProvider.notifier).state = 'extra-60';
    await tester.pumpAndSettle();
    expect(find.text('Track 60').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 3));
  });
}
