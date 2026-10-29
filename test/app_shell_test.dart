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
import 'package:yureru/presentation/screens/settings_screen.dart';
import 'package:yureru/presentation/screens/videos_screen.dart';
import 'package:yureru/presentation/shell.dart';
import 'package:yureru/presentation/theme.dart';
import 'package:yureru/presentation/widgets/player_card.dart';
import 'package:yureru/presentation/widgets/app_svg_icon.dart';
import 'package:yureru/presentation/widgets/mini_player.dart';
import 'package:yureru/presentation/widgets/queue_panel.dart';
import 'package:yureru/presentation/widgets/search_overlay.dart';
import 'package:yureru/presentation/widgets/sidebar.dart';
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
    bool lightMode = false,
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
          theme: yureruLightTheme(),
          darkTheme: yureruTheme(),
          themeMode: lightMode ? ThemeMode.light : ThemeMode.dark,
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
      16,
    );
    await mouse.moveTo(const Offset(500, 400));
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.getRect(queuePanel).left, lessThan(1440));

    // The pinned panel remains interactive, including selecting a queue row.
    await tester.tap(find.byKey(ValueKey('queue-${nextMedia.id}')));
    await tester.pumpAndSettle();
    expect(c.read(queueProvider).currentId, nextMedia.id);

    // Browsing hides the queue, but its explicit pin survives the transition.
    await mouse.moveTo(const Offset(1, 200));
    await tester.pumpAndSettle();
    final openPanelInsets =
        tester.widget<AnimatedPadding>(topbarInsets).padding as EdgeInsets;
    expect(openPanelInsets.left, greaterThan(16));
    expect(openPanelInsets.right, 16);
    await tester.tap(find.byIcon(Icons.video_library_rounded));
    await tester.pumpAndSettle();
    expect(c.read(queueVisibleProvider), isFalse);
    expect(find.byTooltip('再生キューを固定'), findsNothing);
    expect(find.byType(PlayerCard), findsNothing);

    // Returning to the player restores the pinned queue.
    c.read(viewingPlayerProvider.notifier).state = true;
    await tester.pumpAndSettle();
    expect(c.read(queueVisibleProvider), isTrue);
    expect(find.byTooltip('再生キューの固定を解除'), findsOneWidget);
    expect(tester.getRect(queuePanel).left, lessThan(1440));
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
      expect(tester.widget<AnimatedOpacity>(hoverTransport).opacity, 1);
      await mouse.moveTo(const Offset(2, 2));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.widget<AnimatedOpacity>(hoverTransport).opacity, 0);

      // Tiny pointer jitter still counts as hovering, so the controls remain
      // available until the pointer leaves the player.
      await mouse.moveTo(cardRect.center);
      await tester.pump(const Duration(milliseconds: 100));
      for (var i = 0; i < 27; i++) {
        await mouse.moveTo(cardRect.center + Offset(i.isEven ? 1 : -1, 0));
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.widget<AnimatedOpacity>(hoverTransport).opacity, 1);
      await mouse.moveTo(const Offset(2, 2));
      await tester.pump(const Duration(milliseconds: 300));
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
      expect(c.read(cinemaModeProvider), isFalse);
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
    final engine = c.read(engineProvider) as FakePlaybackEngine;
    await engine.play();
    await tester.pumpAndSettle();
    // Starting the first queue item opens the player; force the browse state
    // only after that listener has run to exercise the persistent browse bar.
    c.read(viewingPlayerProvider.notifier).state = false;
    await tester.pumpAndSettle();
    expect(
      tester.widget<TransportBar>(find.byType(TransportBar)).transportOnly,
      isFalse,
    );

    final timeline = find
        .descendant(
          of: find.byType(TransportBar),
          matching: find.byType(Slider),
        )
        .last;
    expect(
      tester
          .widget<Focus>(
            find.byKey(const ValueKey('browse-seekbar-keyboard-focus')),
          )
          .descendantsAreFocusable,
      isFalse,
    );
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

  testWidgets('paused video controls remain visible while hovered', (
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
    expect(tester.widget<AnimatedOpacity>(hoverTransport).opacity, 1);
    await mouse.moveTo(const Offset(2, 2));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<AnimatedOpacity>(hoverTransport).opacity, 0);
    await mouse.removePointer();
  });

  testWidgets('compact video transport stays visible while hovered', (
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
    expect(tester.widget<AnimatedOpacity>(transport).opacity, 1);

    final bounds = tester.getRect(transport);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: bounds.center);
    await tester.pump();
    expect(tester.widget<AnimatedOpacity>(transport).opacity, 1);
    await mouse.moveTo(bounds.center + const Offset(4, 0));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.widget<AnimatedOpacity>(transport).opacity, 1);
    await tester.pump(const Duration(milliseconds: 2400));
    expect(tester.widget<AnimatedOpacity>(transport).opacity, 1);
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
    final visual = find.byKey(const ValueKey('compact-player-visual'));
    final visualSizeBeforeQueue = tester.getSize(visual);
    final visualTopBeforeQueue = tester.getTopLeft(visual).dy;
    expect(find.byIcon(Icons.queue_music_rounded), findsNothing);
    expect(nextContents, findsOneWidget);
    await tester.tap(nextContents);
    await tester.pumpAndSettle();

    expect(c.read(queueVisibleProvider), isTrue);
    expect(find.byIcon(Icons.arrow_forward_rounded), findsNothing);
    expect(find.text('次のコンテンツ').hitTestable(), findsOneWidget);
    expect(
      find.byKey(const ValueKey('transport-next-content-button')),
      findsNothing,
    );
    final playerBounds = tester.getRect(find.byType(PlayerCard));
    final queuePanel = find.byType(QueuePanel);
    expect(
      tester.getRect(queuePanel).top,
      greaterThanOrEqualTo(playerBounds.top),
    );
    expect(tester.getSize(visual), visualSizeBeforeQueue);
    expect(tester.getTopLeft(visual).dy, visualTopBeforeQueue);
    await tester.tap(
      find
          .descendant(of: queuePanel, matching: find.byType(GestureDetector))
          .first,
    );
    await tester.pumpAndSettle();
    final expandedQueueBounds = tester.getRect(queuePanel);
    expect(expandedQueueBounds.top, greaterThanOrEqualTo(playerBounds.top));
    expect(expandedQueueBounds.top - playerBounds.top, lessThan(100));
    expect(expandedQueueBounds.bottom, lessThanOrEqualTo(playerBounds.bottom));
    await tester.tap(find.text('歌詞'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(c.read(lyricsPanelProvider), isTrue);
  });

  testWidgets('compact player keeps the same frame when switching to artwork', (
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
    expect(
      find.byKey(const ValueKey('transport-next-content-button')),
      findsNothing,
    );

    final timeline = find.byKey(const ValueKey('compact-player-timeline'));
    expect(timeline, findsOneWidget);
    expect(tester.widget<AnimatedOpacity>(timeline).opacity, 1);
    expect(
      find.descendant(of: timeline, matching: find.byType(Slider)),
      findsOneWidget,
    );

    // Artwork fills and crops inside exactly the same frame as the video.
    final visual = find.byKey(const ValueKey('compact-player-visual'));
    final videoSize = tester.getSize(visual);
    c.read(playerViewModeProvider.notifier).state = PlayerViewMode.image;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    expect(tester.getSize(visual), videoSize);
    expect(
      find.byKey(const ValueKey('compact-player-timeline')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('compact-player-transport')),
      findsOneWidget,
    );
  });

  testWidgets('artwork mode keeps the light theme surface bright', (
    tester,
  ) async {
    await pumpShell(tester, size: const Size(390, 844), lightMode: true);
    final c = ProviderScope.containerOf(tester.element(find.byType(AppShell)));
    final media = MediaItem(title: 'ライトの確認', localPath: '/tmp/light.mp4');
    await (c.read(repositoryProvider) as InMemoryLibraryRepository).saveMedia([
      media,
    ]);
    await c.read(libraryProvider.notifier).load();
    c.read(queueProvider.notifier).start([media.id], shuffle: false);
    c.read(viewingPlayerProvider.notifier).state = true;
    c.read(playerViewModeProvider.notifier).state = PlayerViewMode.image;
    await tester.pumpAndSettle();

    final surface = tester.widget<Container>(
      find.byKey(const ValueKey('compact-player-visual-surface')),
    );
    expect(
      (surface.decoration! as BoxDecoration).color,
      yureruLightTheme().scaffoldBackgroundColor,
    );
  });

  testWidgets(
    'light artwork mode does not leave the ambient shell transparent',
    (tester) async {
      await pumpShell(tester, lightMode: true);
      final c = ProviderScope.containerOf(
        tester.element(find.byType(AppShell)),
      );
      final media = MediaItem(
        title: 'ライト背景',
        localPath: '/tmp/light-shell.mp4',
      );
      await (c.read(repositoryProvider) as InMemoryLibraryRepository).saveMedia(
        [media],
      );
      await c.read(libraryProvider.notifier).load();
      c.read(queueProvider.notifier).start([media.id], shuffle: false);
      c.read(viewingPlayerProvider.notifier).state = true;
      c.read(playerViewModeProvider.notifier).state = PlayerViewMode.image;
      await tester.pumpAndSettle();

      final shell = tester.widget<Scaffold>(
        find.byKey(const ValueKey('wide-app-shell')),
      );
      expect(shell.backgroundColor, yureruLightTheme().scaffoldBackgroundColor);
    },
  );

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
    await tester.tap(find.byKey(const ValueKey('desktop-sidebar-toggle')));
    await tester.pumpAndSettle();
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

  testWidgets('settings opens with all categories selected', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeLanguageCodeProvider.overrideWithValue('ja'),
          repositoryProvider.overrideWithValue(InMemoryLibraryRepository()),
          engineProvider.overrideWithValue(FakePlaybackEngine()),
        ],
        child: MaterialApp(
          theme: yureruLightTheme(),
          darkTheme: yureruTheme(),
          themeMode: ThemeMode.dark,
          home: const Scaffold(body: SettingsScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('settings-list-all')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-category-all')), findsOneWidget);
  });

  testWidgets('playlist can be created from the sidebar + button', (
    tester,
  ) async {
    await pumpShell(tester);
    await tester.tap(find.byKey(const ValueKey('desktop-sidebar-toggle')));
    await tester.pumpAndSettle();
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
    final timeline = find.byKey(const ValueKey('player-hover-timeline'));
    final controls = find.byKey(const ValueKey('player-hover-transport'));
    expect(title, findsOneWidget);
    expect(creator, findsOneWidget);
    expect(timeline, findsOneWidget);
    expect(tester.widget<AnimatedOpacity>(controls).opacity, 0);
    expect(
      tester.getRect(title).bottom,
      lessThan(tester.getRect(timeline).top),
    );
    expect(
      tester.getRect(creator).bottom,
      lessThan(tester.getRect(timeline).top),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getRect(controls).center);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(creator);
    await tester.pumpAndSettle();

    expect(c.read(videoCreatorFilterProvider), '作者A');
    expect(find.text('投稿者: 作者A'), findsOneWidget);
    expect(find.byType(VideosScreen), findsOneWidget);
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
    // Start playback through the queue now that the redundant home preview is gone.
    final media = container.read(libraryProvider).media.single;
    container.read(queueProvider.notifier).start([media.id], shuffle: false);
    await container.read(playbackControllerProvider).openCurrent();
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

  testWidgets('video row adds itself after the current queue item', (
    tester,
  ) async {
    final current = MediaItem(title: '再生中', localPath: '/tmp/current.mp4');
    final next = MediaItem(title: '次に加える', localPath: '/tmp/next.mp4');
    final c = await pumpHomeWithMedia(tester, current);
    final repository = c.read(repositoryProvider) as InMemoryLibraryRepository;
    await repository.saveMedia([next]);
    await c.read(libraryProvider.notifier).load();
    await tester.pumpAndSettle();

    c.read(videoOpenRequestProvider.notifier).state = next.id;
    await tester.pumpAndSettle();
    c.read(queueProvider.notifier).start([current.id], shuffle: false);
    await tester.pump();

    await tester.tap(find.byKey(ValueKey('video-play-next-${next.id}')));
    await tester.pumpAndSettle();
    expect(c.read(queueProvider).currentId, current.id);
    expect(c.read(queueProvider).queue, [current.id, next.id]);
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

  testWidgets('desktop sidebar can be pinned and follows its panel', (
    tester,
  ) async {
    await pumpHomeWithMedia(
      tester,
      MediaItem(title: 'テスト動画', localPath: '/tmp/t.mp4'),
    );
    final sidebarToggle = find.byKey(const ValueKey('desktop-sidebar-toggle'));
    expect(sidebarToggle, findsOneWidget);
    expect(tester.getRect(sidebarToggle).top, lessThan(80));
    final sidebar = find.byType(Sidebar);
    final center = find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith('center-'),
    );
    final centerBeforeSidebar = tester.getRect(center);
    expect(
      find.descendant(of: sidebar, matching: find.byTooltip('サイドバーを固定')),
      findsNothing,
    );
    expect(tester.getRect(sidebar).right, lessThanOrEqualTo(0));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1, 200));
    await mouse.moveTo(const Offset(1, 200));
    await tester.pumpAndSettle();
    expect(tester.getRect(sidebar).right, greaterThan(0));
    final centerWithSidebar = tester.getRect(center);
    expect(centerWithSidebar.left, greaterThan(centerBeforeSidebar.left));
    expect(centerWithSidebar.width, lessThan(centerBeforeSidebar.width));
    await tester.tap(sidebarToggle);
    await mouse.moveTo(const Offset(500, 200));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(tester.getRect(sidebar).right, greaterThan(0));
    await tester.tap(sidebarToggle);
    await mouse.moveTo(const Offset(700, 200));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(tester.getRect(sidebar).right, lessThanOrEqualTo(0));
    final centerAfterSidebar = tester.getRect(center);
    expect(centerAfterSidebar.left, centerBeforeSidebar.left);
    expect(centerAfterSidebar.width, centerBeforeSidebar.width);
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

  testWidgets('phone-width search icon opens global search', (tester) async {
    await pumpShell(tester, size: const Size(390, 844));
    await tester.tap(find.byTooltip('全体検索'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchOverlay), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compact search field keeps a global search action', (
    tester,
  ) async {
    await pumpShell(tester, size: const Size(650, 844));
    await tester.tap(find.byTooltip('全体検索'));
    await tester.pumpAndSettle();
    expect(find.byType(SearchOverlay), findsOneWidget);
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
  // (CJK line metrics). The home content scrolls without a fixed preview panel.
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
    final ex = tester.takeException();
    expect(ex, isNull, reason: 'short home overflowed: $ex');
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
