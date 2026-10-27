import 'dart:async';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:yureru/presentation/i18n.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yureru/app_state.dart';
import 'package:yureru/data/store.dart';
import 'package:yureru/domain/models.dart';
import 'package:yureru/playback/fake_engine.dart';
import 'package:yureru/playback/playback_controller.dart';
import 'package:yureru/playback/playback_engine.dart';
import 'package:yureru/presentation/screens/home_screen.dart';
import 'package:yureru/presentation/screens/videos_screen.dart';
import 'package:yureru/presentation/shell.dart';
import 'package:yureru/presentation/theme.dart';
import 'package:yureru/presentation/widgets/player_card.dart';
import 'package:yureru/presentation/widgets/app_svg_icon.dart';
import 'package:yureru/presentation/widgets/mini_player.dart';
import 'package:yureru/presentation/widgets/preview_player.dart';
import 'package:yureru/presentation/widgets/queue_panel.dart';
import 'package:yureru/presentation/widgets/search_overlay.dart';
import 'package:yureru/presentation/widgets/sidebar.dart';
import 'package:yureru/presentation/widgets/thumb_image.dart';
import 'package:yureru/presentation/widgets/top_bar.dart';
import 'package:yureru/presentation/widgets/transport_bar.dart';

class _LaggingSeekEngine extends FakePlaybackEngine {
  final StreamController<PlaybackSnapshot> _updates =
      StreamController<PlaybackSnapshot>.broadcast();

  _LaggingSeekEngine() {
    snap = const PlaybackSnapshot(
      position: Duration(seconds: 30),
      duration: Duration(seconds: 100),
      isPlaying: true,
      initialized: true,
    );
  }

  @override
  Stream<PlaybackSnapshot> get snapshots => _updates.stream;

  @override
  Future<void> seekTo(Duration position) async {
    seeks.add(position);
    // Simulate an engine that accepts the command before publishing its new
    // playback position, which is the interval where the thumb used to snap
    // back to the stale snapshot.
    Timer(const Duration(milliseconds: 300), () {
      if (_updates.isClosed) return;
      snap = PlaybackSnapshot(
        position: position,
        duration: snap.duration,
        isPlaying: snap.isPlaying,
        initialized: true,
      );
      _updates.add(snap);
    });
  }

  @override
  Future<void> dispose() async {
    await _updates.close();
    await super.dispose();
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Yureru',
      packageName: 'dev.yureru.yureru',
      version: '1.0.6',
      buildNumber: '7',
      buildSignature: '',
    );
    binding.platformDispatcher.localeTestValue = const Locale('ja', 'JP');
  });
  tearDown(() => binding.platformDispatcher.clearLocaleTestValue());
  Future<void> pumpShell(
    WidgetTester tester, {
    Size size = const Size(1440, 900),
    bool firstLaunch = false,
  }) async {
    SharedPreferences.setMockInitialValues({
      'yureru_first_launch_complete_v1': !firstLaunch,
    });
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final fake = FakePlaybackEngine();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeLanguageCodeProvider.overrideWithValue('ja'),
          repositoryProvider.overrideWithValue(InMemoryLibraryRepository()),
          engineProvider.overrideWithValue(fake),
        ],
        child: MaterialApp(
          theme: yureruTheme(),
          darkTheme: yureruTheme(),
          themeMode: ThemeMode.dark,
          home: const AppShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('first empty launch opens settings on the import section', (
    tester,
  ) async {
    await pumpShell(tester, firstLaunch: true);

    expect(find.text('フォルダからインポート'), findsOneWidget);
    expect(find.text('動画をインポート'), findsWidgets);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('yureru_first_launch_complete_v1'), isTrue);
  });

  testWidgets('wide ambient player leaves the glow canvas visible', (
    tester,
  ) async {
    await pumpShell(tester);
    final c = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    final media = MediaItem(title: '青い動画', localPath: '/tmp/blue.mp4');
    await (c.read(repositoryProvider) as InMemoryLibraryRepository).saveMedia([
      media,
    ]);
    await c.read(libraryProvider.notifier).load();
    c.read(queueProvider.notifier).start([media.id], shuffle: false);
    c.read(viewingPlayerProvider.notifier).state = true;
    await tester.pump();

    final shellScaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(shellScaffold.backgroundColor, Colors.transparent);
    expect(find.byType(PlayerCard), findsOneWidget);
  });

  testWidgets('large desktop reveals the queue from the right edge', (
    tester,
  ) async {
    await pumpShell(tester, size: const Size(1440, 900));
    final c = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    final media = MediaItem(title: 'デスクトップ動画', localPath: '/tmp/desktop.mp4');
    final nextMedia = MediaItem(
      title: '次のデスクトップ動画',
      localPath: '/tmp/desktop-next.mp4',
    );
    await (c.read(repositoryProvider) as InMemoryLibraryRepository).saveMedia([
      media,
      nextMedia,
    ]);
    await c.read(libraryProvider.notifier).load();
    c.read(queueProvider.notifier).start([
      media.id,
      nextMedia.id,
    ], shuffle: false);
    c.read(viewingPlayerProvider.notifier).state = true;
    await tester.pumpAndSettle();

    final queuePanel = find.byType(QueuePanel);
    expect(tester.getRect(queuePanel).left, greaterThanOrEqualTo(1440));
    expect(find.byIcon(Icons.arrow_forward_rounded), findsNothing);
    expect(find.byTooltip('再生キューを固定'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('compact-next-content-button')),
      findsNothing,
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1439, 200));
    await mouse.moveTo(const Offset(1439, 200));
    await tester.pumpAndSettle();
    expect(tester.getRect(queuePanel).left, lessThan(1440));

    // The explicit queue button is only available while watching a video.
    final pinButton = find.byTooltip('再生キューを固定');
    expect(pinButton, findsOneWidget);
    await tester.tap(pinButton);
    await tester.pumpAndSettle();
    expect(c.read(queueVisibleProvider), isTrue);
    final topbarInsets = find.byKey(
      const ValueKey('shell-topbar-chrome-insets'),
    );
    expect(
      (tester.widget<AnimatedPadding>(topbarInsets).padding as EdgeInsets)
          .right,
      greaterThan(16),
    );
    await mouse.moveTo(const Offset(500, 400));
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.getRect(queuePanel).left, lessThan(1440));

    // The pinned panel remains interactive, including selecting a queue row.
    await tester.tap(find.byKey(ValueKey('queue-${nextMedia.id}')));
    await tester.pumpAndSettle();
    expect(c.read(queueProvider).currentId, nextMedia.id);

    // Returning to browsing closes and unpins the desktop queue.
    await mouse.moveTo(const Offset(1, 200));
    await tester.pumpAndSettle();
    final openPanelInsets =
        tester.widget<AnimatedPadding>(topbarInsets).padding as EdgeInsets;
    expect(openPanelInsets.left, greaterThan(16));
    expect(openPanelInsets.right, greaterThan(16));
    await tester.tap(find.byIcon(Icons.video_library_rounded));
    await tester.pumpAndSettle();
    expect(c.read(queueVisibleProvider), isFalse);
    expect(find.byTooltip('再生キューを固定'), findsNothing);
    expect(find.byType(PlayerCard), findsNothing);
    await mouse.removePointer();
  });

  testWidgets(
    'wide video player hides the bottom bar and shows it in image mode',
    (tester) async {
      await pumpShell(tester);
      // Idle: no transport bar, no queue panel (defaults per spec).
      expect(find.text('1.0x'), findsNothing);
      expect(find.text('次のコンテンツ'), findsNothing);
      // Video mode owns its hover transport inside the player surface.
      final c = ProviderScope.containerOf(
        tester.element(find.byType(AppShell)),
      );
      final m = MediaItem(
        title: 'テスト動画',
        artist: 'テスト作者',
        localPath: '/tmp/t.mp4',
      );
      await (c.read(repositoryProvider) as InMemoryLibraryRepository).saveMedia(
        [m],
      );
      await c.read(libraryProvider.notifier).load();
      c.read(queueProvider.notifier).start([m.id], shuffle: false);
      await (c.read(engineProvider) as FakePlaybackEngine).play();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('次のコンテンツ'), findsOneWidget);
      expect(find.byType(TransportBar), findsNothing);
      expect(find.byKey(const ValueKey('player-title')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('player-title'))).data,
        'テスト動画',
      );
      expect(find.byKey(const ValueKey('player-creator')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('player-creator'))).data,
        'テスト作者',
      );
      final hoverTransport = find.byKey(
        const ValueKey('player-hover-transport'),
      );
      expect(hoverTransport, findsOneWidget);
      expect(tester.widget<AnimatedOpacity>(hoverTransport).opacity, 0);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      final cardRect = tester.getRect(find.byType(PlayerCard));
      final playerMargin = cardRect.topLeft + const Offset(8, 8);
      await mouse.moveTo(cardRect.center);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.widget<AnimatedOpacity>(hoverTransport).opacity, 1);
      await mouse.moveTo(tester.getRect(hoverTransport).center);
      await tester.pump(const Duration(milliseconds: 100));
      await mouse.moveTo(const Offset(2, 2));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.widget<AnimatedOpacity>(hoverTransport).opacity, 0);

      await mouse.moveTo(cardRect.center);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.widget<AnimatedOpacity>(hoverTransport).opacity, 1);
      await mouse.moveTo(playerMargin);
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.widget<AnimatedOpacity>(hoverTransport).opacity, 1);
      await tester.pump(const Duration(milliseconds: 2400));
      expect(tester.widget<AnimatedOpacity>(hoverTransport).opacity, 0);

      // Repeated tiny pointer deltas (as from trackpad jitter) are not real
      // activity and must not keep pushing the idle timeout back forever.
      await mouse.moveTo(cardRect.center);
      await tester.pump(const Duration(milliseconds: 100));
      for (var i = 0; i < 27; i++) {
        await mouse.moveTo(cardRect.center + Offset(i.isEven ? 1 : -1, 0));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.widget<AnimatedOpacity>(hoverTransport).opacity, 0);

      final fake = c.read(engineProvider) as FakePlaybackEngine;
      final playCallsBeforeDoubleTap = fake.playCalls;
      final pauseCallsBeforeDoubleTap = fake.pauseCalls;
      await tester.tapAt(cardRect.center);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(cardRect.center);
      await tester.pump(const Duration(milliseconds: 400));
      expect(fake.playCalls, playCallsBeforeDoubleTap);
      expect(fake.pauseCalls, pauseCallsBeforeDoubleTap);
      expect(c.read(cinemaModeProvider), isTrue);
      c.read(cinemaModeProvider.notifier).state = false;
      await tester.pump();

      await mouse.moveTo(cardRect.center);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.widget<AnimatedOpacity>(hoverTransport).opacity, 1);
      await mouse.moveTo(playerMargin);
      await mouse.moveTo(const Offset(2, 2));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.widget<AnimatedOpacity>(hoverTransport).opacity, 0);
      await mouse.removePointer();
      c.read(playerViewModeProvider.notifier).state = PlayerViewMode.image;
      await tester.pump();
      expect(find.byType(TransportBar), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(TransportBar),
          matching: find.byTooltip('次の動画'),
        ),
        findsOneWidget,
      );
      expect(find.text('1.0x'), findsWidgets);
      // No floating/overlay + buttons anywhere (import/add stays in settings)
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.byTooltip('新規プレイリスト'), findsOneWidget);
    },
  );

  testWidgets('arrow keys never seek from the browse transport timeline', (
    tester,
  ) async {
    await pumpShell(tester);
    final c = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    final media = MediaItem(title: '矢印キー確認', localPath: '/tmp/arrows.mp4');
    await (c.read(repositoryProvider) as InMemoryLibraryRepository).saveMedia([
      media,
    ]);
    await c.read(libraryProvider.notifier).load();
    c.read(queueProvider.notifier).start([media.id], shuffle: false);
    c.read(viewingPlayerProvider.notifier).state = false;
    final engine = c.read(engineProvider) as FakePlaybackEngine;
    await engine.play();
    await tester.pumpAndSettle();

    final timeline = find
        .descendant(
          of: find.byType(TransportBar),
          matching: find.byType(Slider),
        )
        .first;
    Focus.of(tester.element(timeline)).requestFocus();
    await tester.pump();

    for (final key in [
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowRight,
    ]) {
      await tester.sendKeyEvent(key);
    }
    expect(engine.seeks, isEmpty);
  });

  testWidgets('paused video controls appear on hover and auto-hide', (
    tester,
  ) async {
    await pumpShell(tester);
    final c = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    final media = MediaItem(title: '一時停止中', localPath: '/tmp/paused.mp4');
    await (c.read(repositoryProvider) as InMemoryLibraryRepository).saveMedia([
      media,
    ]);
    await c.read(libraryProvider.notifier).load();
    c.read(queueProvider.notifier).start([media.id], shuffle: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final hoverTransport = find.byKey(const ValueKey('player-hover-transport'));
    expect(hoverTransport, findsOneWidget);
    expect(tester.widget<AnimatedOpacity>(hoverTransport).opacity, 0);
    final transport = tester.getRect(hoverTransport);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: transport.center);
    await tester.pump();
    // Merely having the window/widget appear beneath a stationary cursor must
    // not reveal the controls; actual pointer movement does.
    expect(tester.widget<AnimatedOpacity>(hoverTransport).opacity, 0);
    await mouse.moveTo(transport.center + const Offset(4, 0));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.widget<AnimatedOpacity>(hoverTransport).opacity, 1);
    await tester.pump(const Duration(seconds: 3));
    expect(tester.widget<AnimatedOpacity>(hoverTransport).opacity, 0);
    await mouse.removePointer();
  });

  testWidgets('compact video transport is hidden until the pointer moves', (
    tester,
  ) async {
    await pumpShell(tester, size: const Size(700, 900));
    final c = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    final media = MediaItem(title: '狭い画面の動画', localPath: '/tmp/compact.mp4');
    await (c.read(repositoryProvider) as InMemoryLibraryRepository).saveMedia([
      media,
    ]);
    await c.read(libraryProvider.notifier).load();
    c.read(queueProvider.notifier).start([media.id], shuffle: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final transport = find.byKey(const ValueKey('compact-player-transport'));
    expect(transport, findsOneWidget);
    expect(tester.widget<AnimatedOpacity>(transport).opacity, 0);

    final bounds = tester.getRect(transport);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: bounds.center);
    await tester.pump();
    expect(tester.widget<AnimatedOpacity>(transport).opacity, 0);
    await mouse.moveTo(bounds.center + const Offset(4, 0));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<AnimatedOpacity>(transport).opacity, 1);
    await tester.pump(const Duration(milliseconds: 2400));
    expect(tester.widget<AnimatedOpacity>(transport).opacity, 0);
    await mouse.removePointer();
  });

  testWidgets('compact player opens next contents and switches to lyrics', (
    tester,
  ) async {
    await pumpShell(tester, size: const Size(390, 844));
    final c = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    final media = MediaItem(title: 'スマホの動画', localPath: '/tmp/mobile.mp4');
    await (c.read(repositoryProvider) as InMemoryLibraryRepository).saveMedia([
      media,
    ]);
    await c.read(libraryProvider.notifier).load();
    c.read(queueProvider.notifier).start([media.id], shuffle: false);
    c.read(viewingPlayerProvider.notifier).state = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final nextContents = find.byKey(
      const ValueKey('compact-next-content-button'),
    );
    expect(find.byIcon(Icons.queue_music_rounded), findsNothing);
    expect(nextContents, findsOneWidget);
    await tester.tap(nextContents);
    await tester.pumpAndSettle();

    expect(c.read(queueVisibleProvider), isTrue);
    expect(find.byIcon(Icons.arrow_forward_rounded), findsNothing);
    expect(find.text('次のコンテンツ'), findsNWidgets(2));
    await tester.tap(find.text('歌詞'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(c.read(lyricsPanelProvider), isTrue);
  });

  testWidgets('compact full-player video keeps the seek timeline on hover', (
    tester,
  ) async {
    await pumpShell(tester, size: const Size(700, 900));
    final c = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    final media = MediaItem(title: '動画シーク', localPath: '/tmp/seek-compact.mp4');
    await (c.read(repositoryProvider) as InMemoryLibraryRepository).saveMedia([
      media,
    ]);
    await c.read(libraryProvider.notifier).load();
    c.read(queueProvider.notifier).start([media.id], shuffle: false);
    c.read(viewingPlayerProvider.notifier).state = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final timeline = find.byKey(const ValueKey('compact-player-timeline'));
    expect(timeline, findsOneWidget);
    expect(tester.widget<AnimatedOpacity>(timeline).opacity, 0);

    final bounds = tester.getRect(timeline);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: bounds.center);
    await mouse.moveTo(bounds.center + const Offset(4, 0));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.widget<AnimatedOpacity>(timeline).opacity, 1);
    expect(
      find.descendant(of: timeline, matching: find.byType(Slider)),
      findsOneWidget,
    );
    await mouse.removePointer();
  });

  testWidgets('seek thumb waits for the engine position after release', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final delayedEngine = _LaggingSeekEngine();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeLanguageCodeProvider.overrideWithValue('ja'),
          repositoryProvider.overrideWithValue(InMemoryLibraryRepository()),
          engineProvider.overrideWithValue(delayedEngine),
        ],
        child: MaterialApp(
          theme: yureruTheme(),
          darkTheme: yureruTheme(),
          themeMode: ThemeMode.dark,
          home: const AppShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    final media = MediaItem(title: 'シーク確認', localPath: '/tmp/seek.mp4');
    await (container.read(repositoryProvider) as InMemoryLibraryRepository)
        .saveMedia([media]);
    await container.read(libraryProvider.notifier).load();
    container.read(queueProvider.notifier).start([media.id], shuffle: false);
    delayedEngine.snap = const PlaybackSnapshot(
      position: Duration(seconds: 30),
      duration: Duration(seconds: 100),
      isPlaying: true,
      initialized: true,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final sliderFinder = find.byType(Slider).first;
    final slider = tester.widget<Slider>(sliderFinder);
    slider.onChangeStart!(30000);
    slider.onChanged!(75000);
    slider.onChangeEnd!(75000);
    await tester.pump();
    expect(tester.widget<Slider>(sliderFinder).value, 75000);
    await tester.pump(const Duration(milliseconds: 150));
    expect(tester.widget<Slider>(sliderFinder).value, 75000);
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.widget<Slider>(sliderFinder).value, 75000);
  });

  testWidgets('seek preview stays inside a narrow player timeline', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fake = FakePlaybackEngine();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeLanguageCodeProvider.overrideWithValue('ja'),
          repositoryProvider.overrideWithValue(InMemoryLibraryRepository()),
          engineProvider.overrideWithValue(fake),
        ],
        child: MaterialApp(
          theme: yureruTheme(),
          darkTheme: yureruTheme(),
          themeMode: ThemeMode.dark,
          home: const AppShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    final media = MediaItem(title: 'プレビュー位置', localPath: '/tmp/preview.mp4');
    await (container.read(repositoryProvider) as InMemoryLibraryRepository)
        .saveMedia([media]);
    await container.read(libraryProvider.notifier).load();
    container.read(queueProvider.notifier).start([media.id], shuffle: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final slider = find.byType(Slider).first;
    final sliderRect = tester.getRect(slider);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: sliderRect.center);
    await mouse.moveTo(sliderRect.topRight - const Offset(2, 0));
    await tester.pump();

    final preview = find.text('1:40').first;
    expect(preview, findsOneWidget);
    final previewBubble = find
        .ancestor(of: preview, matching: find.byType(Container))
        .first;
    final previewStack = find
        .ancestor(of: preview, matching: find.byType(Stack))
        .first;
    final bubbleRect = tester.getRect(previewBubble);
    final stackRect = tester.getRect(previewStack);
    expect(bubbleRect.left, greaterThanOrEqualTo(stackRect.left));
    expect(bubbleRect.right, lessThanOrEqualTo(stackRect.right));
    await mouse.removePointer();
  });

  testWidgets('settings page is reachable and shows general settings', (
    tester,
  ) async {
    await pumpShell(tester);
    await tester.tap(find.text('設定'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'ライブラリ'));
    await tester.pumpAndSettle();
    expect(find.text('ライブラリ管理'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, '表示'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ChoiceChip, '表示'), findsOneWidget);
    expect(find.text('テーマ'), findsOneWidget);
    expect(find.text('アンビエントライト'), findsOneWidget);
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, 'アンビエントライト'),
          )
          .value,
      isTrue,
    );
    await tester.tap(find.widgetWithText(SwitchListTile, 'アンビエントライト'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, 'アンビエントライト'),
          )
          .value,
      isFalse,
    );
    await tester.tap(find.widgetWithText(ChoiceChip, 'アプリ'));
    await tester.pumpAndSettle();
    expect(find.text('言語'), findsOneWidget);
    expect(find.text('Yureru について'), findsOneWidget);
  });

  testWidgets('playlist can be created from the sidebar + button', (
    tester,
  ) async {
    await pumpShell(tester);
    await tester.tap(find.byTooltip('新規プレイリスト'));
    await tester.pumpAndSettle();
    final dialogField = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(dialogField, '作成テスト');
    await tester.tap(find.text('作成'));
    await tester.pumpAndSettle();
    expect(find.text('作成テスト'), findsWidgets);
  });

  testWidgets(
    'no layout overflow while playing at real window content size 1240x559',
    (tester) async {
      tester.view.physicalSize = const Size(1240, 559);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final fake = FakePlaybackEngine();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeLanguageCodeProvider.overrideWithValue('ja'),
            repositoryProvider.overrideWithValue(InMemoryLibraryRepository()),
            engineProvider.overrideWithValue(fake),
          ],
          child: MaterialApp(
            theme: yureruTheme(),
            darkTheme: yureruTheme(),
            themeMode: ThemeMode.dark,
            home: const AppShell(),
          ),
        ),
      );
      final c = ProviderScope.containerOf(
        tester.element(find.byType(AppShell)),
      );
      final repo = c.read(repositoryProvider) as InMemoryLibraryRepository;
      final m = MediaItem(title: 'テスト動画', localPath: '/tmp/t.mp4');
      await repo.saveMedia([m]);
      await c.read(libraryProvider.notifier).load();
      await c.read(libraryProvider.notifier).createPlaylist('曲');
      final pl = c.read(libraryProvider).playlists.single;
      await c.read(libraryProvider.notifier).addToPlaylist(pl.id, m.id);
      final pl2 = c.read(libraryProvider).playlistById(pl.id)!;
      c
          .read(queueProvider.notifier)
          .start(pl2.mediaIds, playlistId: pl2.id, shuffle: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // The player card must actually be visible for this overflow check to be valid.
      expect(find.text('テスト動画'), findsWidgets);
      final ex = tester.takeException();
      expect(ex, isNull, reason: 'layout overflowed while playing: $ex');
    },
  );

  testWidgets(
    'playback switches center to full-size player; nav returns to browse',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'yureru_first_launch_complete_v1': true,
      });
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeLanguageCodeProvider.overrideWithValue('ja'),
            repositoryProvider.overrideWithValue(InMemoryLibraryRepository()),
            engineProvider.overrideWithValue(FakePlaybackEngine()),
          ],
          child: MaterialApp(
            theme: yureruTheme(),
            darkTheme: yureruTheme(),
            themeMode: ThemeMode.dark,
            home: const AppShell(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final c = ProviderScope.containerOf(
        tester.element(find.byType(AppShell)),
      );
      final m = MediaItem(title: 'テスト動画', localPath: '/tmp/t.mp4');
      await (c.read(repositoryProvider) as InMemoryLibraryRepository).saveMedia(
        [m],
      );
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
      // Reveal the edge sidebar to navigate back to browsing.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1, 200));
      await mouse.moveTo(const Offset(1, 200));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.video_library_rounded));
      await tester.pumpAndSettle();
      expect(find.byType(VideosScreen), findsOneWidget);
      expect(find.byType(PlayerCard), findsNothing);
      expect(find.text('テスト動画'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'global video search opens the video list without starting playback',
    (tester) async {
      await pumpShell(tester);
      final c = ProviderScope.containerOf(
        tester.element(find.byType(AppShell)),
      );
      final repo = c.read(repositoryProvider) as InMemoryLibraryRepository;
      final media = MediaItem(title: '検索対象', localPath: '/tmp/search.mp4');
      await repo.saveMedia([media]);
      await c.read(libraryProvider.notifier).load();
      await tester.pump();

      c.read(videoOpenRequestProvider.notifier).state = media.id;
      await tester.pumpAndSettle();

      expect(find.byType(VideosScreen), findsOneWidget);
      expect(find.text('検索対象'), findsOneWidget);
      expect(find.byType(PlayerCard), findsNothing);
      expect((c.read(engineProvider) as FakePlaybackEngine).loaded, isNull);
    },
  );

  testWidgets(
    'Cmd-K search result opens the matching video row instead of playing it',
    (tester) async {
      await pumpShell(tester);
      final c = ProviderScope.containerOf(
        tester.element(find.byType(AppShell)),
      );
      final repo = c.read(repositoryProvider) as InMemoryLibraryRepository;
      final media = MediaItem(
        title: 'ショートカット検索対象',
        localPath: '/tmp/search.mp4',
      );
      await repo.saveMedia([media]);
      await c.read(libraryProvider.notifier).load();
      await tester.pump();

      final shortcut = find.text(
        defaultTargetPlatform == TargetPlatform.macOS ? '⌘ K' : 'Ctrl+K',
      );
      expect(shortcut, findsOneWidget);
      final modifier = Platform.isMacOS
          ? LogicalKeyboardKey.metaLeft
          : LogicalKeyboardKey.controlLeft;
      await tester.sendKeyDownEvent(modifier);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyK);
      await tester.sendKeyUpEvent(modifier);
      await tester.pumpAndSettle();
      expect(find.byType(SearchOverlay), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, media.title);
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .descendant(
              of: find.byType(SearchOverlay),
              matching: find.text(media.title),
            )
            .last,
      );
      await tester.pumpAndSettle();

      expect(find.byType(VideosScreen), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(VideosScreen),
          matching: find.text(media.title),
        ),
        findsOneWidget,
      );
      expect(find.byType(PlayerCard), findsNothing);
      expect((c.read(engineProvider) as FakePlaybackEngine).loaded, isNull);
    },
  );

  testWidgets('Enter in the top search field shows filtered videos', (
    tester,
  ) async {
    await pumpShell(tester);
    final c = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    final repo = c.read(repositoryProvider) as InMemoryLibraryRepository;
    final media = MediaItem(title: 'Enter検索対象', localPath: '/tmp/search.mp4');
    await repo.saveMedia([media]);
    await c.read(libraryProvider.notifier).load();
    await tester.pump();

    final topSearch = find
        .descendant(of: find.byType(TopBar), matching: find.byType(TextField))
        .first;
    await tester.enterText(topSearch, media.title);
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.byType(SearchOverlay), findsNothing);
    expect(find.byType(VideosScreen), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(VideosScreen),
        matching: find.text(media.title),
      ),
      findsOneWidget,
    );
    expect(c.read(searchQueryProvider), media.title);
    expect((c.read(engineProvider) as FakePlaybackEngine).loaded, isNull);
  });

  Future<ProviderContainer> pumpHomeWithMedia(
    WidgetTester tester,
    MediaItem m,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeLanguageCodeProvider.overrideWithValue('ja'),
          repositoryProvider.overrideWithValue(InMemoryLibraryRepository()),
          engineProvider.overrideWithValue(FakePlaybackEngine()),
        ],
        child: MaterialApp(
          theme: yureruTheme(),
          darkTheme: yureruTheme(),
          themeMode: ThemeMode.dark,
          home: const AppShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final c = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    await (c.read(repositoryProvider) as InMemoryLibraryRepository).saveMedia([
      m,
    ]);
    await c.read(libraryProvider.notifier).load();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return c;
  }

  testWidgets('played queue items can be reordered and removed', (
    tester,
  ) async {
    final first = MediaItem(title: '最初', localPath: '/tmp/first.mp4');
    final second = MediaItem(title: '二番目', localPath: '/tmp/second.mp4');
    final current = MediaItem(title: '再生中', localPath: '/tmp/current.mp4');
    final c = await pumpHomeWithMedia(tester, first);
    final repository = c.read(repositoryProvider) as InMemoryLibraryRepository;
    await repository.saveMedia([first, second, current]);
    await c.read(libraryProvider.notifier).load();
    c.read(queueProvider.notifier).start([
      first.id,
      second.id,
      current.id,
    ], shuffle: false);
    c.read(queueProvider.notifier).jumpTo(2);
    await tester.pumpAndSettle();

    final firstHandle = find.byType(ReorderableDragStartListener).first;
    await tester.dragFrom(tester.getCenter(firstHandle), const Offset(0, 110));
    await tester.pumpAndSettle();
    expect(
      c.read(queueProvider).queue,
      isNot([first.id, second.id, current.id]),
    );
    expect(c.read(queueProvider).queue.toSet(), {
      first.id,
      second.id,
      current.id,
    });
    expect(c.read(queueProvider).currentId, current.id);

    await tester.tap(
      find.descendant(
        of: find.byKey(ValueKey('queue-${first.id}')),
        matching: find.byTooltip('キューから削除'),
      ),
    );
    await tester.pumpAndSettle();
    expect(c.read(queueProvider).queue, isNot(contains(first.id)));
    expect(c.read(queueProvider).currentId, current.id);

    await c.read(playbackControllerProvider).openCurrent();
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(ValueKey('queue-${current.id}')),
        matching: find.byTooltip('キューから削除'),
      ),
    );
    await tester.pumpAndSettle();
    expect(c.read(queueProvider).currentId, second.id);
    expect(
      (c.read(engineProvider) as FakePlaybackEngine).loaded?.mediaId,
      second.id,
    );
  });

  testWidgets('creator name in the play queue is not interactive', (
    tester,
  ) async {
    final media = MediaItem(
      title: '作者テスト',
      artist: '作者A',
      localPath: '/tmp/creator.mp4',
    );
    final c = await pumpHomeWithMedia(tester, media);
    c.read(queueProvider.notifier).start([media.id], shuffle: false);
    await tester.pumpAndSettle();

    final creator = find.descendant(
      of: find.byType(QueuePanel),
      matching: find.text('作者A'),
    );
    await tester.tap(creator);
    await tester.pumpAndSettle();

    expect(c.read(videoCreatorFilterProvider), isNull);
    expect(find.text('投稿者: 作者A'), findsNothing);
  });

  testWidgets('desktop player creator name opens the filtered video list', (
    tester,
  ) async {
    final media = MediaItem(
      title: '作者テスト',
      artist: '作者A',
      localPath: '/tmp/creator.mp4',
    );
    final c = await pumpHomeWithMedia(tester, media);
    c.read(queueProvider.notifier).start([media.id], shuffle: false);
    await tester.pumpAndSettle();

    final title = find.byKey(const ValueKey('player-title'));
    final creator = find.byKey(const ValueKey('player-creator-search'));
    final controls = find.byKey(const ValueKey('player-hover-transport'));
    expect(title, findsOneWidget);
    expect(creator, findsOneWidget);
    expect(tester.widget<AnimatedOpacity>(controls).opacity, 0);
    expect(
      tester.getRect(title).bottom,
      lessThan(tester.getRect(controls).top),
    );
    await tester.tap(creator);
    await tester.pumpAndSettle();

    expect(c.read(videoCreatorFilterProvider), '作者A');
    expect(find.text('投稿者: 作者A'), findsOneWidget);
    expect(find.byType(VideosScreen), findsOneWidget);
  });

  testWidgets('home shows static preview; its play enters full player', (
    tester,
  ) async {
    final c = await pumpHomeWithMedia(
      tester,
      MediaItem(title: 'テスト動画', localPath: '/tmp/t.mp4'),
    );
    // Missing file in tests -> static preview, no live engine.
    expect(find.text('ここから再生'), findsOneWidget);
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
      tester,
      MediaItem(title: 'テスト動画', localPath: '/tmp/t.mp4'),
    );
    c.read(queueProvider.notifier).start([
      c.read(libraryProvider).media.single.id,
    ], shuffle: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(PlayerCard), findsOneWidget);
    // Browse away, then come back via the transport now-playing info.
    await tester.tap(find.text('すべての動画'));
    await tester.pumpAndSettle();
    expect(find.byType(VideosScreen), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(TransportBar),
        matching: find.text('テスト動画'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PlayerCard), findsOneWidget);
    expect(find.byType(VideosScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow layout while playing does not overflow', (tester) async {
    tester.view.physicalSize = const Size(800, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeLanguageCodeProvider.overrideWithValue('ja'),
          repositoryProvider.overrideWithValue(InMemoryLibraryRepository()),
          engineProvider.overrideWithValue(FakePlaybackEngine()),
        ],
        child: MaterialApp(
          theme: yureruTheme(),
          darkTheme: yureruTheme(),
          themeMode: ThemeMode.dark,
          home: const AppShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final c = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    final m = MediaItem(title: 'テスト動画', localPath: '/tmp/t.mp4');
    await (c.read(repositoryProvider) as InMemoryLibraryRepository).saveMedia([
      m,
    ]);
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
      tester,
      MediaItem(title: 'テスト動画', localPath: '/tmp/t.mp4'),
    );
    final container = c;
    expect(container.read(playerViewModeProvider), PlayerViewMode.media);
    // Start playback via the preview play button.
    await tester.tap(find.text('再生'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(PlayerCard), findsOneWidget);
    final fake = container.read(engineProvider) as FakePlaybackEngine;
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

  testWidgets('browsing away to videos hides queue, player keeps content', (
    tester,
  ) async {
    final c = await pumpHomeWithMedia(
      tester,
      MediaItem(title: 'テスト動画', localPath: '/tmp/t.mp4'),
    );
    c.read(queueProvider.notifier).start([
      c.read(libraryProvider).media.single.id,
    ], shuffle: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(PlayerCard), findsOneWidget);
    expect(find.text('次のコンテンツ'), findsOneWidget);
    // Browsing away to videos automatically hides queue
    await tester.tap(find.text('すべての動画'));
    await tester.pumpAndSettle();
    expect(find.text('次のコンテンツ'), findsNothing);
    await tester.tap(
      find.descendant(
        of: find.byType(TransportBar),
        matching: find.text('テスト動画'),
      ),
    );
    await tester.pumpAndSettle();
    // Returning to player restores player card
    expect(find.byType(PlayerCard), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('queue divider drag resizes the panel', (tester) async {
    final c = await pumpHomeWithMedia(
      tester,
      MediaItem(title: 'テスト動画', localPath: '/tmp/t.mp4'),
    );
    c.read(queueProvider.notifier).start([
      c.read(libraryProvider).media.single.id,
    ], shuffle: false);
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
      tester,
      MediaItem(title: 'テスト動画', localPath: '/tmp/t.mp4'),
    );
    final previewTop = tester.getTopLeft(find.byType(PreviewBar)).dy;
    final msgTop = tester
        .getTopLeft(find.text('プレイリストはサイドバーの＋から作成できます').first)
        .dy;
    expect(previewTop, greaterThan(msgTop));
    expect(tester.takeException(), isNull);
  });

  testWidgets('preview follows the playing item', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeLanguageCodeProvider.overrideWithValue('ja'),
          repositoryProvider.overrideWithValue(InMemoryLibraryRepository()),
          engineProvider.overrideWithValue(FakePlaybackEngine()),
        ],
        child: MaterialApp(
          theme: yureruTheme(),
          darkTheme: yureruTheme(),
          themeMode: ThemeMode.dark,
          home: const AppShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final c = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    final a = MediaItem(title: 'A動画', localPath: '/tmp/a.mp4');
    final b = MediaItem(title: 'B動画', localPath: '/tmp/b.mp4');
    await (c.read(repositoryProvider) as InMemoryLibraryRepository).saveMedia([
      a,
      b,
    ]);
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
      find.descendant(of: find.byType(PreviewBar), matching: find.text('B動画')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(PreviewBar), matching: find.text('A動画')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('videos sort menu orders by name', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeLanguageCodeProvider.overrideWithValue('ja'),
          repositoryProvider.overrideWithValue(InMemoryLibraryRepository()),
          engineProvider.overrideWithValue(FakePlaybackEngine()),
        ],
        child: MaterialApp(
          theme: yureruTheme(),
          darkTheme: yureruTheme(),
          themeMode: ThemeMode.dark,
          home: const AppShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final c = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    final now = DateTime.now();
    await (c.read(repositoryProvider) as InMemoryLibraryRepository).saveMedia([
      MediaItem(
        title: 'B動画',
        localPath: '/tmp/b.mp4',
        createdAt: now.add(const Duration(seconds: 1)),
      ),
      MediaItem(title: 'A動画', localPath: '/tmp/a.mp4', createdAt: now),
    ]);
    await c.read(libraryProvider.notifier).load();
    await tester.tap(find.text('すべての動画'));
    await tester.pumpAndSettle();
    double dy(String t) => tester.getTopLeft(find.text(t)).dy;
    expect(dy('B動画'), lessThan(dy('A動画')));
    await tester.tap(find.byTooltip('並び替え'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(CheckedPopupMenuItem<VideosSort>, '名前順'),
    );
    await tester.pumpAndSettle();
    expect(dy('A動画'), lessThan(dy('B動画')));
    expect(tester.takeException(), isNull);
  });

  testWidgets('playing row shows equalizer in videos list', (tester) async {
    final c = await pumpHomeWithMedia(
      tester,
      MediaItem(title: 'テスト動画', localPath: '/tmp/t.mp4'),
    );
    await tester.tap(find.text('すべての動画'));
    await tester.pumpAndSettle();
    c.read(queueProvider.notifier).start([
      c.read(libraryProvider).media.single.id,
    ], shuffle: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Back to the list while playing: row marked, player reachable.
    await tester.tap(find.text('すべての動画').first);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(VideosScreen),
        matching: find.byWidgetPredicate(
          (w) => w is AppSvgIcon && w.name == 'equalizer',
        ),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('top bar does not show a duplicate home logo', (tester) async {
    await pumpHomeWithMedia(
      tester,
      MediaItem(title: 'テスト動画', localPath: '/tmp/t.mp4'),
    );
    await tester.tap(find.text('すべての動画'));
    await tester.pumpAndSettle();
    expect(find.byType(VideosScreen), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(TopBar),
        matching: find.byTooltip('ライブラリに戻る'),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'desktop PiP action stays visible at phone-sized widths',
    (tester) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [activeLanguageCodeProvider.overrideWithValue('ja')],
          child: MaterialApp(
            theme: yureruTheme(),
            home: Scaffold(
              body: TopBar(onOpenSearch: () {}, onSubmitSearch: (_) {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(TopBar),
          matching: find.byTooltip('ピクチャ・イン・ピクチャ'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.macOS}),
  );

  testWidgets(
    'compact player keeps a desktop PiP action',
    (tester) async {
      final media = MediaItem(title: '小画面テスト', localPath: '/tmp/compact.mp4');
      final c = await pumpHomeWithMedia(tester, media);
      tester.view.physicalSize = const Size(600, 900);
      c.read(queueProvider.notifier).start([media.id], shuffle: false);
      await tester.pumpAndSettle();

      expect(find.byTooltip('ピクチャ・イン・ピクチャ'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: const TargetPlatformVariant({TargetPlatform.macOS}),
  );

  testWidgets('preview shows info panel with next-up while playing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeLanguageCodeProvider.overrideWithValue('ja'),
          repositoryProvider.overrideWithValue(InMemoryLibraryRepository()),
          engineProvider.overrideWithValue(FakePlaybackEngine()),
        ],
        child: MaterialApp(
          theme: yureruTheme(),
          darkTheme: yureruTheme(),
          themeMode: ThemeMode.dark,
          home: const AppShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final c = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    final a = MediaItem(title: 'A動画', localPath: '/tmp/a.mp4');
    final b = MediaItem(title: 'B動画', localPath: '/tmp/b.mp4');
    await (c.read(repositoryProvider) as InMemoryLibraryRepository).saveMedia([
      a,
      b,
    ]);
    await c.read(libraryProvider.notifier).load();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // Idle: static thumbnail + 再生 button.
    expect(
      find.descendant(
        of: find.byType(PreviewBar),
        matching: find.byType(ThumbImage),
      ),
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
      find.descendant(of: find.byType(PreviewBar), matching: find.text('現在の曲')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(PreviewBar),
        matching: find.text('次の動画: B動画'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(PreviewBar),
        matching: find.text('プレイヤーを開く'),
      ),
      findsOneWidget,
    );
    // Tapping next-up advances the queue without leaving browse.
    await tester.tap(
      find.descendant(
        of: find.byType(PreviewBar),
        matching: find.text('次の動画: B動画'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.read(queueProvider).currentId, b.id);
    expect(find.byType(VideosScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop sidebar can be pinned and follows its panel', (
    tester,
  ) async {
    await pumpHomeWithMedia(
      tester,
      MediaItem(title: 'テスト動画', localPath: '/tmp/t.mp4'),
    );
    final sidebar = find.byType(Sidebar);
    expect(tester.getRect(sidebar).right, lessThanOrEqualTo(0));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1, 200));
    await mouse.moveTo(const Offset(1, 200));
    await tester.pumpAndSettle();
    expect(tester.getRect(sidebar).right, greaterThan(0));
    await tester.tap(find.byTooltip('サイドバーを固定'));
    await mouse.moveTo(const Offset(500, 200));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(tester.getRect(sidebar).right, greaterThan(0));
    await tester.tap(find.byTooltip('サイドバーの固定を解除'));
    await mouse.moveTo(const Offset(700, 200));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(tester.getRect(sidebar).right, lessThanOrEqualTo(0));
    await mouse.removePointer();
    expect(tester.takeException(), isNull);
  });

  testWidgets('global search opens a matching video in the videos list', (
    tester,
  ) async {
    await pumpHomeWithMedia(
      tester,
      MediaItem(title: 'テスト動画', localPath: '/tmp/t.mp4'),
    );
    await tester.tap(find.byTooltip('全体検索'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchOverlay), findsOneWidget);
    await tester.enterText(
      find.descendant(
        of: find.byType(SearchOverlay),
        matching: find.byType(TextField),
      ),
      'テスト',
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(SearchOverlay),
        matching: find.text('テスト動画'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(VideosScreen), findsOneWidget);
    expect(find.byType(PlayerCard), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home shows recently added strip', (tester) async {
    final c = await pumpHomeWithMedia(
      tester,
      MediaItem(title: 'テスト動画', localPath: '/tmp/t.mp4'),
    );
    expect(find.text('最近追加'), findsOneWidget);
    expect(find.text('テスト動画'), findsWidgets);
    expect(c.read(queueProvider).hasCurrent, isFalse);
    expect(tester.takeException(), isNull);
  });

  // Regression: 1px bottom overflow in HomeScreen Column at short heights
  // (CJK line metrics). Middle scrolls now; header + preview stay pinned.
  testWidgets('short window home with next-up does not overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 500);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeLanguageCodeProvider.overrideWithValue('ja'),
          repositoryProvider.overrideWithValue(InMemoryLibraryRepository()),
          engineProvider.overrideWithValue(FakePlaybackEngine()),
        ],
        child: MaterialApp(
          theme: yureruTheme(),
          darkTheme: yureruTheme(),
          themeMode: ThemeMode.dark,
          home: const AppShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final c = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    final a = MediaItem(title: 'A動画', localPath: '/tmp/a.mp4');
    final b = MediaItem(title: 'B動画', localPath: '/tmp/b.mp4');
    final cc = MediaItem(title: 'C動画', localPath: '/tmp/c.mp4');
    await (c.read(repositoryProvider) as InMemoryLibraryRepository).saveMedia([
      a,
      b,
      cc,
    ]);
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
    expect(find.text('次の動画: B動画'), findsOneWidget);
    final ex = tester.takeException();
    expect(ex, isNull, reason: 'short home overflowed: $ex');
  });

  // The exact user path: preview 再生 button with an empty queue.
  // Player shows AND the library pill must be off (single highlight).
  testWidgets('preview play shows player with library pill off', (
    tester,
  ) async {
    final c = await pumpHomeWithMedia(
      tester,
      MediaItem(title: 'テスト動画', localPath: '/tmp/t.mp4'),
    );
    expect(c.read(viewingPlayerProvider), isFalse);
    await tester.tap(
      find.descendant(of: find.byType(PreviewBar), matching: find.text('再生')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(PlayerCard), findsOneWidget);
    expect(c.read(viewingPlayerProvider), isTrue);
    Material? pillOf(String label) {
      final el = find
          .descendant(of: find.byType(Sidebar), matching: find.text(label))
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

  testWidgets('blank titles do not render as 無題 in queue', (tester) async {
    final c = await pumpHomeWithMedia(
      tester,
      MediaItem(title: '​', localPath: '/tmp/t.mp4'),
    );
    c.read(queueProvider.notifier).start([
      c.read(libraryProvider).media.single.id,
    ], shuffle: false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('(無題)'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home scrolls down at short height', (tester) async {
    tester.view.physicalSize = const Size(1200, 520);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeLanguageCodeProvider.overrideWithValue('ja'),
          repositoryProvider.overrideWithValue(InMemoryLibraryRepository()),
          engineProvider.overrideWithValue(FakePlaybackEngine()),
        ],
        child: MaterialApp(
          theme: yureruTheme(),
          darkTheme: yureruTheme(),
          themeMode: ThemeMode.dark,
          home: const AppShell(),
        ),
      ),
    );
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
