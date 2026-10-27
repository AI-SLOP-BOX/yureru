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
  for (final width in [390.0, 1200.0]) {
    testWidgets('favorites filter stays usable when empty at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
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
            home: const Scaffold(body: VideosScreen()),
          ),
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(VideosScreen)),
      );
      final a = MediaItem(
        id: 'a',
        title: 'Alpha',
        artist: 'Shared',
        localPath: '/missing/a.mp3',
        isFavorite: true,
      );
      final b = MediaItem(
        id: 'b',
        title: 'Beta',
        artist: 'Shared',
        localPath: '/missing/b.mp3',
      );
      await container.read(libraryProvider.notifier).addMedia([a, b]);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('お気に入りのみ表示'));
      await tester.pumpAndSettle();
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsNothing);
      // Filtering must not reorder the underlying library by subset indices.
      expect(find.byType(ReorderableListView), findsNothing);
      container.read(searchQueryProvider.notifier).state = 'beta';
      await tester.pumpAndSettle();
      expect(find.text('見つかりませんでした'), findsOneWidget);
      container.read(searchQueryProvider.notifier).state = '';
      await container.read(libraryProvider.notifier).toggleFavorite(a.id);
      await tester.pumpAndSettle();
      expect(find.text(translate('favorites_empty', 'ja')), findsOneWidget);
      await tester.tap(find.byTooltip('お気に入りのみ表示'));
      await tester.pumpAndSettle();
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
      // The first row's menu can favorite a track without starting playback.
      final menu = find.byType(PopupMenuButton<String>).first;
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('お気に入りに追加'));
      await tester.pumpAndSettle();
      expect(
        container.read(libraryProvider).savedMedia.where((m) => m.isFavorite),
        hasLength(1),
      );
      expect(container.read(queueProvider).hasCurrent, isFalse);
      final favorite = container
          .read(libraryProvider)
          .savedMedia
          .singleWhere((item) => item.isFavorite);
      await tester.tap(find.byTooltip('お気に入りのみ表示'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(favorite.title));
      await tester.pumpAndSettle();
      expect(container.read(queueProvider).queue, [favorite.id]);
      await tester.tap(find.byTooltip('お気に入りのみ表示'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(PopupMenuButton<VideosSort>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('最近再生した順'));
      await tester.pumpAndSettle();
      final other = favorite.id == a.id ? b : a;
      expect(
        tester.getTopLeft(find.text(favorite.title)).dy,
        lessThan(tester.getTopLeft(find.text(other.title)).dy),
      );
      expect(container.read(queueProvider).queue, [favorite.id]);

      expect(tester.takeException(), isNull);
    });
  }
}
