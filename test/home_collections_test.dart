import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yureru/app_state.dart';
import 'package:yureru/data/store.dart';
import 'package:yureru/domain/models.dart';
import 'package:yureru/playback/fake_engine.dart';
import 'package:yureru/presentation/i18n.dart';
import 'package:yureru/presentation/screens/home_screen.dart';
import 'package:yureru/presentation/theme.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ProviderContainer> pumpHome(
    WidgetTester tester,
    Size size,
    List<MediaItem> items, {
    VoidCallback? onOpenVideos,
    double textScale = 1,
  }) async {
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
          theme: yureruTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(body: HomeScreen(onOpenVideos: onOpenVideos)),
        ),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeScreen)),
    );
    await container.read(libraryProvider.notifier).addMedia(items);
    await tester.pumpAndSettle();
    return container;
  }

  List<MediaItem> favorites() => List.generate(
    12,
    (index) => MediaItem(
      id: '$index',
      title: 'Track $index',
      localPath: '/missing/$index.mp3',
      isFavorite: true,
      lastPlayedAt: index < 2 ? DateTime.utc(2026, 10, index + 1) : null,
    ),
  );

  for (final size in [
    const Size(1440, 900),
    const Size(390, 844),
    const Size(1200, 500),
  ]) {
    testWidgets('favorite shelf plays the complete collection at $size', (
      tester,
    ) async {
      final items = favorites();
      final container = await pumpHome(tester, size, items);
      final shelf = find.byKey(const ValueKey('home-favorites'));
      await tester.ensureVisible(shelf);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: shelf, matching: find.text('Track 0')),
      );
      await tester.pumpAndSettle();
      expect(
        container.read(queueProvider).queue,
        items.map((m) => m.id).toList(),
      );
      expect(container.read(queueProvider).currentId, '0');
      expect(container.read(viewingPlayerProvider), isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'recent shelf queues history by recency and excludes unplayed tracks',
    (tester) async {
      final container = await pumpHome(
        tester,
        const Size(1200, 900),
        favorites(),
      );
      final shelf = find.byKey(const ValueKey('home-recently-played'));
      await tester.tap(
        find.descendant(of: shelf, matching: find.text('Track 1')),
      );
      await tester.pumpAndSettle();
      expect(container.read(queueProvider).queue, ['1', '0']);
      expect(container.read(queueProvider).currentId, '1');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('see all sets matching filters and sort before navigating', (
    tester,
  ) async {
    var opened = 0;
    final container = await pumpHome(
      tester,
      const Size(1200, 900),
      favorites(),
      onOpenVideos: () => opened++,
    );
    container.read(videoCreatorFilterProvider.notifier).state =
        'Unrelated artist';
    final favoriteShelf = find.byKey(const ValueKey('home-favorites'));
    await tester.ensureVisible(favoriteShelf);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: favoriteShelf, matching: find.text('すべて見る')),
    );
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(container.read(favoritesOnlyProvider), isTrue);
    expect(container.read(videoCreatorFilterProvider), isNull);
    expect(container.read(videosSortProvider), VideosSort.manual);
    final recentShelf = find.byKey(const ValueKey('home-recently-played'));
    await tester.ensureVisible(recentShelf);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(of: recentShelf, matching: find.text('すべて見る')),
    );
    await tester.pumpAndSettle();
    expect(opened, 2);
    expect(container.read(favoritesOnlyProvider), isFalse);
    expect(container.read(videosSortProvider), VideosSort.recentlyPlayed);
    expect(container.read(queueProvider).hasCurrent, isFalse);
  });

  testWidgets(
    'empty collections stay hidden and home search shows matching results',
    (tester) async {
      final container = await pumpHome(tester, const Size(390, 844), [
        MediaItem(title: 'Only track', localPath: '/missing/track.mp3'),
      ]);
      expect(find.byKey(const ValueKey('home-favorites')), findsNothing);
      expect(find.byKey(const ValueKey('home-recently-played')), findsNothing);
      expect(find.byKey(const ValueKey('home-recently-added')), findsOneWidget);
      container.read(searchQueryProvider.notifier).state = 'Only';
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('home-recently-added')), findsNothing);
      expect(find.text('Only track'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
  for (final scale in [1.4, 2.0]) {
    testWidgets(
      'home shelves fit enlarged text at scale $scale and show artists',
      (tester) async {
        await pumpHome(tester, const Size(390, 844), [
          MediaItem(
            id: 'a',
            title: 'A long title that should fit',
            artist: 'A long artist credit',
            localPath: '/missing/a.mp3',
            isFavorite: true,
            durationMs: 180000,
          ),
        ], textScale: scale);
        expect(find.text('最近追加'), findsOneWidget);
        expect(find.text('A long artist credit'), findsWidgets);
        expect(find.text('プレイリスト'), findsNothing);
        expect(find.text('0個のプレイリスト'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'recently added playback follows the visible newest-first collection',
    (tester) async {
      final container = await pumpHome(tester, const Size(390, 844), [
        MediaItem(
          id: 'old',
          title: 'Old',
          localPath: '/missing/old',
          createdAt: DateTime.utc(2025),
        ),
        MediaItem(
          id: 'new',
          title: 'New',
          localPath: '/missing/new',
          createdAt: DateTime.utc(2026),
        ),
      ]);
      final shelf = find.byKey(const ValueKey('home-recently-added'));
      await tester.tap(find.descendant(of: shelf, matching: find.text('New')));
      await tester.pumpAndSettle();
      expect(container.read(queueProvider).queue, ['new', 'old']);
      expect(container.read(queueProvider).currentId, 'new');
      expect(tester.takeException(), isNull);
    },
  );
}
