import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yureru/app_state.dart';
import 'package:yureru/data/store.dart';
import 'package:yureru/domain/models.dart';
import 'package:yureru/playback/fake_engine.dart';
import 'package:yureru/presentation/screens/home_screen.dart';
import 'package:yureru/presentation/screens/videos_screen.dart';
import 'package:yureru/presentation/shell.dart';
import 'package:yureru/presentation/theme.dart';
import 'package:yureru/presentation/widgets/player_card.dart';
import 'package:yureru/presentation/widgets/mini_player.dart';
import 'package:yureru/presentation/widgets/preview_player.dart';
import 'package:yureru/presentation/widgets/queue_panel.dart';
import 'package:yureru/presentation/widgets/search_overlay.dart';
import 'package:yureru/presentation/widgets/sidebar.dart';
import 'package:yureru/presentation/widgets/thumb_image.dart';
import 'package:yureru/presentation/widgets/top_bar.dart';
import 'package:yureru/presentation/widgets/transport_bar.dart';

void main() {
  Future<void> pumpShell(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = FakePlaybackEngine();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(InMemoryLibraryRepository()),
        engineProvider.overrideWithValue(fake),
      ],
      child: MaterialApp(
        theme: yureruTheme(),
        darkTheme: yureruTheme(),
        themeMode: ThemeMode.dark,
        home: const AppShell(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('wide shell renders sidebar, queue panel and transport bar without FABs',
      (tester) async {
    await pumpShell(tester);
    // Sidebar navigation (target design)
    expect(find.text('ライブラリ'), findsWidgets);
    expect(find.text('プレイリスト'), findsWidgets);
    expect(find.text('すべての動画'), findsOneWidget);
    expect(find.text('設定'), findsOneWidget);
    // Idle: no transport bar, no queue panel (defaults per spec).
    expect(find.text('1.0x'), findsNothing);
    expect(find.text('再生キュー'), findsNothing);
    // With playback: player screen auto-shows with queue + transport.
    final c = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    final m = MediaItem(title: 'テスト動画', localPath: '/tmp/t.mp4');
    await (c.read(repositoryProvider) as InMemoryLibraryRepository)
        .saveMedia([m]);
    await c.read(libraryProvider.notifier).load();
    c.read(queueProvider.notifier).start([m.id], shuffle: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('再生キュー'), findsOneWidget);
    // Speed pill appears in TransportBar AND PlayerCard info bar, so findsWidgets.
    expect(find.text('1.0x'), findsWidgets);
    // No floating/overlay + buttons anywhere (import/add stays in settings)
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byTooltip('新規プレイリスト'), findsOneWidget);
  });

  testWidgets('settings page is reachable and shows general settings', (tester) async {
    await pumpShell(tester);
    await tester.tap(find.text('設定'));
    await tester.pumpAndSettle();
    // Library management and network sync removed
    expect(find.text('ライブラリ管理'), findsNothing);
    expect(find.text('再生と操作'), findsOneWidget);
    expect(find.text('yureru について'), findsOneWidget);
  });

  testWidgets('playlist can be created from the sidebar + button', (tester) async {
    await pumpShell(tester);
    await tester.tap(find.byTooltip('新規プレイリスト'));
    await tester.pumpAndSettle();
    final dialogField = find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(dialogField, '作成テスト');
    await tester.tap(find.text('作成'));
    await tester.pumpAndSettle();
    expect(find.text('作成テスト'), findsWidgets);
  });

  testWidgets('no layout overflow while playing at real window content size 1240x559',
      (tester) async {
    tester.view.physicalSize = const Size(1240, 559);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = FakePlaybackEngine();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(InMemoryLibraryRepository()),
        engineProvider.overrideWithValue(fake),
      ],
      child: MaterialApp(
        theme: yureruTheme(),
        darkTheme: yureruTheme(),
        themeMode: ThemeMode.dark,
        home: const AppShell(),
      ),
    ));
    final c = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    final repo = c.read(repositoryProvider) as InMemoryLibraryRepository;
    final m = MediaItem(title: 'テスト動画', localPath: '/tmp/t.mp4');
    await repo.saveMedia([m]);
    await c.read(libraryProvider.notifier).load();
    await c.read(libraryProvider.notifier).createPlaylist('曲');
    final pl = c.read(libraryProvider).playlists.single;
    await c.read(libraryProvider.notifier).addToPlaylist(pl.id, m.id);
    final pl2 = c.read(libraryProvider).playlistById(pl.id)!;
    c.read(queueProvider.notifier).start(pl2.mediaIds, playlistId: pl2.id, shuffle: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // The player card must actually be visible for this overflow check to be valid.
    expect(find.text('テスト動画'), findsWidgets);
    final ex = tester.takeException();
    expect(ex, isNull,
        reason: 'layout overflowed while playing: $ex');
  });

  testWidgets('playback switches center to full-size player; nav returns to browse',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(InMemoryLibraryRepository()),
        engineProvider.overrideWithValue(FakePlaybackEngine()),
      ],
      child: MaterialApp(
        theme: yureruTheme(),
        darkTheme: yureruTheme(),
        themeMode: ThemeMode.dark,
        home: const AppShell(),
      ),
    ));
    await tester.pumpAndSettle();
    final c = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    final m = MediaItem(title: 'テスト動画', localPath: '/tmp/t.mp4');
    await (c.read(repositoryProvider) as InMemoryLibraryRepository)
        .saveMedia([m]);
    await c.read(libraryProvider.notifier).load();
    await tester.pump();
    // Browse first: no player stacked above the list.
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(PlayerCard), findsNothing);
    // Fresh playback auto-enters the full-size player, list gone.
    c.read(queueProvider.notifier).start([m.id], shuffle: false);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(PlayerCard), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    // Sidebar nav goes back to browsing; list content still reachable.
    await tester.tap(find.text('すべての動画'));
    await tester.pumpAndSettle();
    expect(find.byType(VideosScreen), findsOneWidget);
    expect(find.byType(PlayerCard), findsNothing);
    expect(find.text('テスト動画'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  Future<ProviderContainer> pumpHomeWithMedia(
      WidgetTester tester, MediaItem m) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(InMemoryLibraryRepository()),
        engineProvider.overrideWithValue(FakePlaybackEngine()),
      ],
      child: MaterialApp(
        theme: yureruTheme(),
        darkTheme: yureruTheme(),
        themeMode: ThemeMode.dark,
        home: const AppShell(),
      ),
    ));
    await tester.pumpAndSettle();
    final c = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    await (c.read(repositoryProvider) as InMemoryLibraryRepository)
        .saveMedia([m]);
    await c.read(libraryProvider.notifier).load();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return c;
  }

  testWidgets('home shows static preview; its play enters full player',
      (tester) async {
    final c = await pumpHomeWithMedia(
        tester, MediaItem(title: 'テスト動画', localPath: '/tmp/t.mp4'));
    // Missing file in tests -> static preview, no live engine.
    expect(find.text('プレビュー'), findsOneWidget);
    expect(find.byType(HomeScreen), findsOneWidget);
    await tester.tap(find.text('再生'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(PlayerCard), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
    expect(c.read(viewingPlayerProvider), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('transport tap returns to the player', (tester) async {
    final c = await pumpHomeWithMedia(
        tester, MediaItem(title: 'テスト動画', localPath: '/tmp/t.mp4'));
    c.read(queueProvider.notifier).start(
        [c.read(libraryProvider).media.single.id],
        shuffle: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(PlayerCard), findsOneWidget);
    // Browse away, then come back via the transport now-playing info.
    await tester.tap(find.text('すべての動画'));
    await tester.pumpAndSettle();
    expect(find.byType(VideosScreen), findsOneWidget);
    await tester.tap(find.descendant(
      of: find.byType(TransportBar),
      matching: find.text('テスト動画'),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerCard), findsOneWidget);
    expect(find.byType(VideosScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow layout while playing does not overflow', (tester) async {
    tester.view.physicalSize = const Size(800, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(InMemoryLibraryRepository()),
        engineProvider.overrideWithValue(FakePlaybackEngine()),
      ],
      child: MaterialApp(
        theme: yureruTheme(),
        darkTheme: yureruTheme(),
        themeMode: ThemeMode.dark,
        home: const AppShell(),
      ),
    ));
    await tester.pumpAndSettle();
    final c = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    final m = MediaItem(title: 'テスト動画', localPath: '/tmp/t.mp4');
    await (c.read(repositoryProvider) as InMemoryLibraryRepository)
        .saveMedia([m]);
    await c.read(libraryProvider.notifier).load();
    c.read(queueProvider.notifier).start([m.id], shuffle: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(PlayerCard), findsOneWidget);
    // When full player is visible, mini player is hidden (video is full center pane).
    expect(find.byType(MiniPlayer), findsNothing);
    // NavigationBar is hidden while the player is active to give the video full screen space.
    expect(find.byType(NavigationBar), findsNothing);
    final ex = tester.takeException();
    expect(ex, isNull, reason: 'narrow layout overflowed: $ex');
  });

  testWidgets('media/image toggle keeps playback (no reload)', (tester) async {
    final c = await pumpHomeWithMedia(
        tester, MediaItem(title: 'テスト動画', localPath: '/tmp/t.mp4'));
    final container = c;
    expect(container.read(playerViewModeProvider), PlayerViewMode.media);
    // Start playback via the preview play button.
    await tester.tap(find.text('再生'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(PlayerCard), findsOneWidget);
    final fake =
        container.read(engineProvider) as FakePlaybackEngine;
    final loadedUri = fake.loaded?.uri;
    expect(loadedUri, '/tmp/t.mp4');
    // Switch to image mode: engine untouched, mode flipped.
    await tester.tap(find.text('画像'));
    await tester.pump();
    expect(container.read(playerViewModeProvider), PlayerViewMode.image);
    expect(fake.loaded?.uri, loadedUri);
    expect(fake.playCalls, 0);
    expect(find.byType(PlayerCard), findsOneWidget);
    // Back to media.
    await tester.tap(find.text('メディア'));
    await tester.pump();
    expect(container.read(playerViewModeProvider), PlayerViewMode.media);
    expect(fake.loaded?.uri, loadedUri);
    expect(tester.takeException(), isNull);
  });

  testWidgets('browsing away to videos hides queue, player keeps content',
      (tester) async {
    final c = await pumpHomeWithMedia(
        tester, MediaItem(title: 'テスト動画', localPath: '/tmp/t.mp4'));
    c.read(queueProvider.notifier).start(
        [c.read(libraryProvider).media.single.id],
        shuffle: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(PlayerCard), findsOneWidget);
    expect(find.text('再生キュー'), findsOneWidget);
    // Browsing away to videos automatically hides queue
    await tester.tap(find.text('すべての動画'));
    await tester.pumpAndSettle();
    expect(find.text('再生キュー'), findsNothing);
    await tester.tap(find.descendant(
      of: find.byType(TransportBar),
      matching: find.text('テスト動画'),
    ));
    await tester.pumpAndSettle();
    // Returning to player restores player card
    expect(find.byType(PlayerCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('queue divider drag resizes the panel', (tester) async {
    final c = await pumpHomeWithMedia(
        tester, MediaItem(title: 'テスト動画', localPath: '/tmp/t.mp4'));
    c.read(queueProvider.notifier).start(
        [c.read(libraryProvider).media.single.id],
        shuffle: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final before = tester.getSize(find.byType(QueuePanel));
    await tester.drag(find.byTooltip('キューの幅'), const Offset(-100, 0));
    await tester.pump();
    final after = tester.getSize(find.byType(QueuePanel));
    // Drag slop eats part of the gesture; assert direction + clamp.
    expect(after.width, greaterThan(before.width));
    expect(after.width, lessThanOrEqualTo(before.width + 100));
    expect(tester.takeException(), isNull);
  });

  testWidgets('preview sits below the library content', (tester) async {
    await pumpHomeWithMedia(
        tester, MediaItem(title: 'テスト動画', localPath: '/tmp/t.mp4'));
    final previewTop = tester.getTopLeft(find.byType(PreviewBar)).dy;
    final msgTop = tester
        .getTopLeft(find.text('プレイリストはサイドバーの＋から作成できます'))
        .dy;
    expect(previewTop, greaterThan(msgTop));
    expect(tester.takeException(), isNull);
  });

  testWidgets('preview follows the playing item', (tester) async {    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(InMemoryLibraryRepository()),
        engineProvider.overrideWithValue(FakePlaybackEngine()),
      ],
      child: MaterialApp(
        theme: yureruTheme(),
        darkTheme: yureruTheme(),
        themeMode: ThemeMode.dark,
        home: const AppShell(),
      ),
    ));
    await tester.pumpAndSettle();
    final c = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    final a = MediaItem(title: 'A動画', localPath: '/tmp/a.mp4');
    final b = MediaItem(title: 'B動画', localPath: '/tmp/b.mp4');
    await (c.read(repositoryProvider) as InMemoryLibraryRepository)
        .saveMedia([a, b]);
    await c.read(libraryProvider.notifier).load();
    c.read(queueProvider.notifier).start([a.id, b.id], shuffle: false);
    c.read(queueProvider.notifier).jumpTo(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Back to home while playing: preview shows the playing item, not A.
    await tester.tap(find.text('すべての動画'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ライブラリ'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
          of: find.byType(PreviewBar), matching: find.text('B動画')),
      findsOneWidget,
    );
    expect(
      find.descendant(
          of: find.byType(PreviewBar), matching: find.text('A動画')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('videos sort menu orders by name', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(InMemoryLibraryRepository()),
        engineProvider.overrideWithValue(FakePlaybackEngine()),
      ],
      child: MaterialApp(
        theme: yureruTheme(),
        darkTheme: yureruTheme(),
        themeMode: ThemeMode.dark,
        home: const AppShell(),
      ),
    ));
    await tester.pumpAndSettle();
    final c = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    await (c.read(repositoryProvider) as InMemoryLibraryRepository).saveMedia([
      MediaItem(title: 'B動画', localPath: '/tmp/b.mp4'),
      MediaItem(title: 'A動画', localPath: '/tmp/a.mp4'),
    ]);
    await c.read(libraryProvider.notifier).load();
    await tester.tap(find.text('すべての動画'));
    await tester.pumpAndSettle();
    double dy(String t) => tester.getTopLeft(find.text(t)).dy;
    expect(dy('B動画'), lessThan(dy('A動画')));
    await tester.tap(find.byTooltip('並び替え'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('名前順'));
    await tester.pumpAndSettle();
    expect(dy('A動画'), lessThan(dy('B動画')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('playing row shows equalizer in videos list', (tester) async {
    final c = await pumpHomeWithMedia(
        tester, MediaItem(title: 'テスト動画', localPath: '/tmp/t.mp4'));
    await tester.tap(find.text('すべての動画'));
    await tester.pumpAndSettle();
    c.read(queueProvider.notifier).start(
        [c.read(libraryProvider).media.single.id],
        shuffle: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Back to the list while playing: row marked, player reachable.
    await tester.tap(find.text('すべての動画').first);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(VideosScreen),
        matching: find.byIcon(Icons.equalizer),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('logo tap returns to library', (tester) async {    await pumpHomeWithMedia(
        tester, MediaItem(title: 'テスト動画', localPath: '/tmp/t.mp4'));
    await tester.tap(find.text('すべての動画'));
    await tester.pumpAndSettle();
    expect(find.byType(VideosScreen), findsOneWidget);
    // Top-bar logo (always visible) goes home.
    await tester.tap(find.descendant(
      of: find.byType(TopBar),
      matching: find.byTooltip('ライブラリに戻る'),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(VideosScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('preview shows info panel with next-up while playing',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(InMemoryLibraryRepository()),
        engineProvider.overrideWithValue(FakePlaybackEngine()),
      ],
      child: MaterialApp(
        theme: yureruTheme(),
        darkTheme: yureruTheme(),
        themeMode: ThemeMode.dark,
        home: const AppShell(),
      ),
    ));
    await tester.pumpAndSettle();
    final c = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    final a = MediaItem(title: 'A動画', localPath: '/tmp/a.mp4');
    final b = MediaItem(title: 'B動画', localPath: '/tmp/b.mp4');
    await (c.read(repositoryProvider) as InMemoryLibraryRepository)
        .saveMedia([a, b]);
    await c.read(libraryProvider.notifier).load();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Idle: static thumbnail + 再生 button.
    expect(
      find.descendant(
          of: find.byType(PreviewBar), matching: find.byType(ThumbImage)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(PreviewBar), matching: find.text('再生')),
      findsOneWidget,
    );
    // Playing + back home: info for the playing item, next-up, open button.
    // No second player: single ThumbImage, no video output involved.
    c.read(queueProvider.notifier).start([a.id, b.id], shuffle: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('すべての動画'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ライブラリ'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(PreviewBar), matching: find.text('再生中')),
      findsOneWidget,
    );
    expect(
      find.descendant(
          of: find.byType(PreviewBar), matching: find.text('次: B動画')),
      findsOneWidget,
    );
    // Tapping next-up advances the queue without leaving browse.
    await tester.tap(find.descendant(
      of: find.byType(PreviewBar),
      matching: find.text('次: B動画'),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.read(queueProvider).currentId, b.id);
    expect(find.byType(VideosScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sidebar collapses to icon rail and back', (tester) async {    await pumpHomeWithMedia(
        tester, MediaItem(title: 'テスト動画', localPath: '/tmp/t.mp4'));
    expect(tester.getSize(find.byType(Sidebar)).width,
        moreOrLessEquals(248, epsilon: 1.0));
    expect(find.text('プレイリスト'), findsWidgets);
    await tester.tap(find.byTooltip('サイドバーを隠す'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(Sidebar)).width,
        moreOrLessEquals(76, epsilon: 1.0));
    // Labels hidden, navigation still works via tooltips.
    expect(find.text('プレイリスト'), findsNothing);
    await tester.tap(find.byTooltip('すべての動画'));
    await tester.pumpAndSettle();
    expect(find.byType(VideosScreen), findsOneWidget);
    await tester.tap(find.byTooltip('サイドバーを表示'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(Sidebar)).width,
        moreOrLessEquals(248, epsilon: 1.0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('global search finds a video and plays it', (tester) async {
    await pumpHomeWithMedia(
        tester, MediaItem(title: 'テスト動画', localPath: '/tmp/t.mp4'));
    await tester.tap(find.byTooltip('全体検索'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchOverlay), findsOneWidget);
    await tester.enterText(
      find.descendant(
          of: find.byType(SearchOverlay), matching: find.byType(TextField)),
      'テスト',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(SearchOverlay),
      matching: find.text('テスト動画'),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home shows recently added strip', (tester) async {
    final c = await pumpHomeWithMedia(
        tester, MediaItem(title: 'テスト動画', localPath: '/tmp/t.mp4'));
    expect(find.text('最近追加'), findsOneWidget);
    expect(find.text('テスト動画'), findsWidgets);
    expect(c.read(queueProvider).hasCurrent, isFalse);
    expect(tester.takeException(), isNull);
  });

  // Regression: 1px bottom overflow in HomeScreen Column at short heights
  // (CJK line metrics). Middle scrolls now; header + preview stay pinned.
  testWidgets('short window home with next-up does not overflow',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(InMemoryLibraryRepository()),
        engineProvider.overrideWithValue(FakePlaybackEngine()),
      ],
      child: MaterialApp(
        theme: yureruTheme(),
        darkTheme: yureruTheme(),
        themeMode: ThemeMode.dark,
        home: const AppShell(),
      ),
    ));
    await tester.pumpAndSettle();
    final c = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    final a = MediaItem(title: 'A動画', localPath: '/tmp/a.mp4');
    final b = MediaItem(title: 'B動画', localPath: '/tmp/b.mp4');
    final cc = MediaItem(title: 'C動画', localPath: '/tmp/c.mp4');
    await (c.read(repositoryProvider) as InMemoryLibraryRepository)
        .saveMedia([a, b, cc]);
    await c.read(libraryProvider.notifier).load();
    c.read(queueProvider.notifier).start([a.id, b.id, cc.id], shuffle: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('すべての動画'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ライブラリ'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(PreviewBar), findsOneWidget);
    expect(find.text('次: B動画'), findsOneWidget);
    final ex = tester.takeException();
    expect(ex, isNull, reason: 'short home overflowed: $ex');
  });

  // The exact user path: preview 再生 button with an empty queue.
  // Player shows AND the library pill must be off (single highlight).
  testWidgets('preview play shows player with library pill off',
      (tester) async {
    final c = await pumpHomeWithMedia(
        tester, MediaItem(title: 'テスト動画', localPath: '/tmp/t.mp4'));
    expect(c.read(viewingPlayerProvider), isFalse);
    await tester.tap(find.descendant(
      of: find.byType(PreviewBar),
      matching: find.text('再生'),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(PlayerCard), findsOneWidget);
    expect(c.read(viewingPlayerProvider), isTrue);
    Material? pillOf(String label) {
      final el = find
          .descendant(
            of: find.byType(Sidebar),
            matching: find.text(label),
          )
          .evaluate()
          .single;
      Material? found;
      el.visitAncestorElements((a) {
        if (a.widget is Material) {
          found = a.widget as Material;
          return false;
        }
        return true;
      });
      return found;
    }

    expect(pillOf('ライブラリ')?.color, Colors.transparent);
    expect(tester.takeException(), isNull);
  });

  testWidgets('blank titles render as 無題 in queue', (tester) async {
    final c = await pumpHomeWithMedia(
        tester, MediaItem(title: '​', localPath: '/tmp/t.mp4'));
    c.read(queueProvider.notifier).start(
        [c.read(libraryProvider).media.single.id],
        shuffle: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('(無題)'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home scrolls down at short height', (tester) async {
    tester.view.physicalSize = const Size(1200, 520);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(InMemoryLibraryRepository()),
        engineProvider.overrideWithValue(FakePlaybackEngine()),
      ],
      child: MaterialApp(
        theme: yureruTheme(),
        darkTheme: yureruTheme(),
        themeMode: ThemeMode.dark,
        home: const AppShell(),
      ),
    ));
    await tester.pumpAndSettle();
    final c = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    await (c.read(repositoryProvider) as InMemoryLibraryRepository).saveMedia([
      MediaItem(title: 'A動画', localPath: '/tmp/a.mp4'),
      MediaItem(title: 'B動画', localPath: '/tmp/b.mp4'),
    ]);
    await c.read(libraryProvider.notifier).load();
    await c.read(libraryProvider.notifier).createPlaylist('P');
    final pl = c.read(libraryProvider).playlists.single;
    for (final m in c.read(libraryProvider).media) {
      await c.read(libraryProvider.notifier).addToPlaylist(pl.id, m.id);
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Grid card must move up when dragging the scroll area.
    final cardTop = tester.getTopLeft(find.text('A動画').first).dy;
    await tester.drag(find.byType(HomeScreen), const Offset(0, -120));
    await tester.pumpAndSettle();
    final cardTopAfter = tester.getTopLeft(find.text('A動画').first).dy;
    expect(cardTopAfter, lessThan(cardTop));
    expect(tester.takeException(), isNull);
  });
}
