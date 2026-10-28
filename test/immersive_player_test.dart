import 'package:package_info_plus/package_info_plus.dart';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yureru/app_state.dart';
import 'package:yureru/data/store.dart';
import 'package:yureru/domain/models.dart';
import 'package:yureru/playback/fake_engine.dart';
import 'package:yureru/playback/playback_engine.dart';
import 'package:yureru/playback/sleep_timer_provider.dart';
import 'package:yureru/playback/playback_controller.dart';
import 'package:yureru/presentation/i18n.dart';
import 'package:yureru/presentation/screens/immersive_player_screen.dart';
import 'package:yureru/presentation/screens/videos_screen.dart';
import 'package:yureru/presentation/shell.dart';
import 'package:yureru/presentation/theme.dart';
import 'package:yureru/presentation/widgets/player_card.dart';

class _Engine extends FakePlaybackEngine {
  int loads = 0;
  bool hasVideo = false;
  @override
  double? get videoAspectRatio => hasVideo ? 16 / 9 : null;
  @override
  Widget buildVideoView({Key? key, BoxFit fit = BoxFit.contain}) =>
      const ColoredBox(
        key: ValueKey('test-video-surface'),
        color: Colors.indigo,
      );
  @override
  Future<void> load(PlaybackSource source, {bool autoplay = true}) async {
    loads++;
    await super.load(source, autoplay: autoplay);
  }

  @override
  Future<String?> readEmbeddedLyrics() async => '''
[00:00.00]夜の向こうへ
[00:12.00]光がそっと揺れている
[00:24.00]この瞬間を聴いていたい
[00:36.00]いつまでも
''';
}

const _previewKey = ValueKey('immersive-preview');

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  // Lyric discovery uses real filesystem I/O, outside the fake test clock.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 40)),
  );
  // Ambient glow and media controls can keep an animation ticker alive, so
  // pump the transition window explicitly instead of waiting for global idle.
  for (var frame = 0; frame < 5; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Yureru',
      packageName: 'dev.yureru.yureru',
      version: '1.0.6',
      buildNumber: '7',
      buildSignature: '',
    );
  });

  Future<(ProviderContainer, _Engine)> pumpPlayer(
    WidgetTester tester,
    Size size,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final engine = _Engine();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(InMemoryLibraryRepository()),
          engineProvider.overrideWithValue(engine),
          activeLanguageCodeProvider.overrideWithValue('ja'),
        ],
        child: MaterialApp(
          theme: yureruTheme(),
          home: const RepaintBoundary(key: _previewKey, child: AppShell()),
        ),
      ),
    );
    await _settle(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    final media = MediaItem(
      id: 'test',
      title: '夜の向こうへ',
      artist: 'Yureru Sessions',
      localPath: '/missing/track.mp3',
    );
    await container.read(libraryProvider.notifier).addMedia([media]);
    container.read(queueProvider.notifier).start([media.id], shuffle: false);
    await container.read(playbackControllerProvider).openCurrent();
    await _settle(tester);
    return (container, engine);
  }

  testWidgets('sleep timer stays shared across normal and immersive views', (
    tester,
  ) async {
    final (container, _) = await pumpPlayer(tester, const Size(390, 844));
    await tester.tap(find.byTooltip('スリープタイマー'));
    await _settle(tester);
    await tester.tap(find.text('30分'));
    await _settle(tester);
    expect(container.read(sleepTimerProvider).deadline, isNotNull);
    await tester.tap(find.byTooltip('没入モード'));
    await _settle(tester);
    await tester.tap(find.byTooltip('スリープタイマー · 30分'));
    await _settle(tester);
    await tester.tap(find.text('タイマーを解除'));
    await _settle(tester);
    expect(container.read(sleepTimerProvider).active, false);
    expect(tester.takeException(), isNull);
  });

  testWidgets('normal video player keeps a visible seek timeline', (
    tester,
  ) async {
    final (container, _) = await pumpPlayer(tester, const Size(1440, 900));
    container.read(viewingPlayerProvider.notifier).state = true;
    await _settle(tester);

    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.onChangeStart, isNotNull);
    expect(slider.onChanged, isNotNull);
    expect(slider.onChangeEnd, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('cinema fullscreen keeps title and creator on screen', (
    tester,
  ) async {
    final (container, _) = await pumpPlayer(tester, const Size(1440, 900));
    container.read(viewingPlayerProvider.notifier).state = true;
    container.read(cinemaModeProvider.notifier).state = true;
    await _settle(tester);

    expect(find.byKey(const ValueKey('cinema-title')), findsNWidgets(2));
    expect(find.byKey(const ValueKey('cinema-creator')), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('immersive seeking commits only when the slider is released', (
    tester,
  ) async {
    final (container, engine) = await pumpPlayer(tester, const Size(1440, 900));
    container.read(immersiveModeProvider.notifier).state = true;
    await _settle(tester);

    final slider = tester.widget<Slider>(
      find.descendant(
        of: find.byType(ImmersivePlayerScreen),
        matching: find.byType(Slider),
      ),
    );
    slider.onChangeStart!(25000);
    slider.onChanged!(26000);
    await tester.pump();
    expect(engine.seeks, isEmpty);

    slider.onChangeEnd!(26000);
    await _settle(tester);
    expect(engine.seeks, [const Duration(milliseconds: 26000)]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'immersive player shows searchable title and creator above controls',
    (tester) async {
      final (container, _) = await pumpPlayer(tester, const Size(1440, 900));
      container.read(immersiveModeProvider.notifier).state = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final title = find.byKey(const ValueKey('immersive-title'));
      final creator = find.byKey(const ValueKey('immersive-creator-search'));
      final controls = find.byKey(const ValueKey('immersive-controls')).last;
      expect(title, findsOneWidget);
      expect(find.byKey(const ValueKey('immersive-creator')), findsOneWidget);
      expect(tester.getRect(title).top, lessThan(tester.getRect(controls).top));
      await tester.tap(creator);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(container.read(videoCreatorFilterProvider), 'Yureru Sessions');
      expect(find.byType(ImmersivePlayerScreen), findsNothing);
      expect(find.byType(VideosScreen), findsOneWidget);
    },
  );

  for (final size in [
    const Size(1440, 900),
    const Size(390, 844),
    const Size(1240, 559),
    const Size(360, 600),
    const Size(740, 360),
  ]) {
    testWidgets('immersive layout fits $size and preserves playback on exit', (
      tester,
    ) async {
      final (container, engine) = await pumpPlayer(tester, size);
      if (size.width < 376) {
        await tester.tap(find.byIcon(Icons.more_vert_rounded));
        await _settle(tester);
        await tester.tap(find.text('没入モード').last);
      } else {
        await tester.tap(find.byTooltip('没入モード'));
      }
      await _settle(tester);
      expect(find.byType(ImmersivePlayerScreen), findsOneWidget);
      expect(find.byType(PlayerCard), findsNothing);
      expect(find.text('光がそっと揺れている'), findsOneWidget);
      if (const bool.fromEnvironment('IMMERSIVE_PREVIEW') &&
          size.width == 1440) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(_previewKey),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '/tmp/yureru-immersive-preview.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      expect(find.text('通常表示に戻る'), findsOneWidget);
      expect(find.text('動画表示'), findsOneWidget);
      final loads = engine.loads;
      final pauses = engine.pauseCalls;
      await tester.tap(find.byTooltip('お気に入りに追加'));
      await _settle(tester);
      expect(container.read(libraryProvider).byId('test')!.isFavorite, isTrue);

      await tester.tap(find.byTooltip('動画・ジャケットの切り替え'));
      await _settle(tester);
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<PlayerViewMode>, 'ジャケット表示'),
      );
      await _settle(tester);
      expect(container.read(playerViewModeProvider), PlayerViewMode.image);
      expect(engine.videoTrackEnabled, isFalse);
      expect(find.text('ジャケット表示'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('没入モードを閉じる'));
      await _settle(tester);
      expect(find.byType(PlayerCard), findsOneWidget);
      expect(find.byTooltip('お気に入りから外す'), findsOneWidget);
      expect(engine.loads, loads);
      expect(engine.pauseCalls, pauses);
      expect(container.read(queueProvider).currentId, 'test');
    });
  }

  testWidgets(
    'immersive controls stay visible while hovered and Escape exits',
    (tester) async {
      final (container, engine) = await pumpPlayer(
        tester,
        const Size(1440, 900),
      );
      container.read(immersiveModeProvider.notifier).state = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      engine.snap = const PlaybackSnapshot(initialized: true, isPlaying: true);
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester
            .widgetList<AnimatedOpacity>(
              find.byKey(const ValueKey('immersive-controls')),
            )
            .every((widget) => widget.opacity == 0),
        isTrue,
      );
      final pointer = await tester.createGesture(
        kind: ui.PointerDeviceKind.mouse,
      );
      await pointer.addPointer(location: const Offset(700, 450));
      await pointer.moveTo(const Offset(710, 450));
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester
            .widgetList<AnimatedOpacity>(
              find.byKey(const ValueKey('immersive-controls')),
            )
            .every((widget) => widget.opacity == 1),
        isTrue,
      );
      await tester.pump(const Duration(seconds: 4));
      expect(
        tester
            .widgetList<AnimatedOpacity>(
              find.byKey(const ValueKey('immersive-controls')),
            )
            .every((widget) => widget.opacity == 1),
        isTrue,
      );
      await pointer.moveTo(const Offset(-10, -10));
      await tester.pump(const Duration(seconds: 4));
      expect(
        tester
            .widgetList<AnimatedOpacity>(
              find.byKey(const ValueKey('immersive-controls')),
            )
            .every((widget) => widget.opacity == 0),
        isTrue,
      );
      await pointer.removePointer();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(container.read(immersiveModeProvider), isFalse);
    },
  );

  testWidgets(
    'video uses a single surface and advancing keeps immersive mode',
    (tester) async {
      final (container, engine) = await pumpPlayer(
        tester,
        const Size(1440, 900),
      );
      engine.hasVideo = true;
      final second = MediaItem(
        id: 'second',
        title: 'Second track',
        localPath: '/missing/second.mp4',
      );
      await container.read(libraryProvider.notifier).addMedia([second]);
      container.read(queueProvider.notifier).append(second.id);
      container.read(immersiveModeProvider.notifier).state = true;
      await _settle(tester);
      expect(find.byKey(const ValueKey('test-video-surface')), findsOneWidget);
      final loads = engine.loads;
      await tester.tap(find.byTooltip('歌詞'));
      await _settle(tester);
      expect(find.text('光がそっと揺れている'), findsNothing);
      expect(engine.loads, loads);
      await tester.tap(find.byTooltip('次の動画'));
      await _settle(tester);
      expect(container.read(queueProvider).currentId, second.id);
      expect(container.read(immersiveModeProvider), isTrue);
      expect(find.text('Second track'), findsOneWidget);
      expect(engine.loads, loads + 1);
      expect(find.byKey(const ValueKey('test-video-surface')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('mute restores the same volume after leaving immersive mode', (
    tester,
  ) async {
    final (container, engine) = await pumpPlayer(tester, const Size(1440, 900));
    await container.read(playbackControllerProvider).setVolume(0.37);
    container.read(immersiveModeProvider.notifier).state = true;
    await _settle(tester);
    await tester.tap(find.byTooltip('音量'));
    await _settle(tester);
    expect(find.text('37%'), findsOneWidget);
    await tester.tap(find.byTooltip('ミュート'));
    await _settle(tester);
    expect(engine.volume, 0);
    await tester.tap(find.text('閉じる'));
    await _settle(tester);
    await tester.tap(find.byTooltip('没入モードを閉じる'));
    await _settle(tester);
    await tester.tap(find.byTooltip('ミュート解除'));
    await _settle(tester);
    expect(engine.volume, 0.37);
    expect(container.read(volumeProvider), 0.37);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'compact volume dialog and playback order share state and Escape scope',
    (tester) async {
      final (container, engine) = await pumpPlayer(
        tester,
        const Size(360, 600),
      );
      container.read(immersiveModeProvider.notifier).state = true;
      await _settle(tester);
      final loads = engine.loads;
      await tester.tap(find.byTooltip('シャッフル'));
      await _settle(tester);
      expect(container.read(queueProvider).shuffle, isTrue);
      for (final (label, expected) in [
        ('全曲リピート', 'one'),
        ('1曲リピート', 'off'),
        ('リピートなし', 'all'),
      ]) {
        await tester.tap(find.byTooltip(label));
        await _settle(tester);
        expect(container.read(queueProvider).repeat, expected);
      }
      await tester.tap(find.byTooltip('音量'));
      await _settle(tester);
      final slider = tester.widget<Slider>(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(Slider),
        ),
      );
      slider.onChanged!(0.62);
      await _settle(tester);
      expect(engine.volume, 0.62);
      expect(find.text('62%'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      expect(
        tester
            .widgetList<AnimatedOpacity>(
              find.byKey(const ValueKey('immersive-controls')),
            )
            .every((widget) => widget.opacity == 1),
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(container.read(immersiveModeProvider), isTrue);
      expect(engine.loads, loads);
      expect(container.read(queueProvider).currentId, 'test');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'global search reveals non-favorites even with favorites filter active',
    (tester) async {
      final (container, _) = await pumpPlayer(tester, const Size(1440, 900));
      container.read(favoritesOnlyProvider.notifier).state = true;
      container.read(videoOpenRequestProvider.notifier).state = 'test';
      await _settle(tester);
      expect(container.read(favoritesOnlyProvider), isFalse);
      expect(find.text('夜の向こうへ'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
  for (final size in [const Size(360, 600), const Size(1440, 900)]) {
    testWidgets(
      'labeled return remains tappable when immersive controls hide at $size',
      (tester) async {
        final (container, engine) = await pumpPlayer(tester, size);
        container.read(immersiveModeProvider.notifier).state = true;
        await _settle(tester);
        final loads = engine.loads;
        final pauses = engine.pauseCalls;
        final position = engine.snapshot.position;
        await tester.pump(const Duration(seconds: 4));
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          tester
              .widgetList<AnimatedOpacity>(
                find.byKey(const ValueKey('immersive-controls')),
              )
              .every((widget) => widget.opacity == 0),
          true,
        );
        expect(find.text('通常表示に戻る').hitTestable(), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('immersive-exit')));
        await _settle(tester);
        expect(container.read(immersiveModeProvider), false);
        expect(find.byType(PlayerCard), findsOneWidget);
        expect(engine.loads, loads);
        expect(engine.pauseCalls, pauses);
        expect(engine.snapshot.position, position);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
