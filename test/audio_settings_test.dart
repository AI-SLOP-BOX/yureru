import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yureru/app_state.dart';
import 'package:yureru/data/store.dart';
import 'package:yureru/domain/models.dart';
import 'package:yureru/playback/audio_settings.dart';
import 'package:yureru/playback/fake_engine.dart';
import 'package:yureru/playback/playback_controller.dart';
import 'package:yureru/playback/playback_engine.dart';
import 'package:yureru/presentation/i18n.dart';
import 'package:yureru/presentation/screens/settings_screen.dart';
import 'package:yureru/presentation/theme.dart';

class _UnsupportedEngine extends FakePlaybackEngine {
  @override
  bool get supportsVolumeNormalization => false;
}

class _RejectingEngine extends FakePlaybackEngine {
  @override
  Future<void> setVolumeNormalizationEnabled(bool enabled) async {
    if (enabled) throw StateError('Filter unavailable');
    await super.setVolumeNormalizationEnabled(enabled);
  }
}

class _LoadObserver extends FakePlaybackEngine {
  bool? normalizedAtLoad;
  @override
  Future<void> load(PlaybackSource source, {bool autoplay = true}) async {
    normalizedAtLoad = normalizationEnabled;
    await super.load(source, autoplay: autoplay);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
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

  test(
    'normalization persists and restores without touching manual volume',
    () async {
      final engine = FakePlaybackEngine()..vol = 0.37;
      final settings = AudioSettingsNotifier(engine);
      addTearDown(settings.dispose);
      await settings.ready;
      expect(settings.state.valueOrNull, isFalse);
      await settings.setEnabled(true);
      expect(engine.normalizationEnabled, isTrue);
      expect(engine.volume, 0.37);
      final nextEngine = FakePlaybackEngine();
      final restored = AudioSettingsNotifier(nextEngine);
      addTearDown(restored.dispose);
      await restored.ready;
      expect(nextEngine.normalizationEnabled, isTrue);
      await restored.setEnabled(false);
      expect(nextEngine.normalizationEnabled, isFalse);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          AudioSettingsNotifier.preferenceKey,
        ),
        isFalse,
      );
    },
  );

  test('an edit during hydration wins over the saved preference', () async {
    SharedPreferences.setMockInitialValues({
      AudioSettingsNotifier.preferenceKey: true,
    });
    final engine = FakePlaybackEngine();
    final settings = AudioSettingsNotifier(engine);
    addTearDown(settings.dispose);
    await settings.setEnabled(false);
    expect(engine.normalizationEnabled, isFalse);
    expect(settings.state.valueOrNull, isFalse);
  });

  test('failed processing keeps the previous value and preference', () async {
    final engine = _RejectingEngine();
    final settings = AudioSettingsNotifier(engine);
    addTearDown(settings.dispose);
    await settings.ready;
    await settings.setEnabled(true);
    expect(settings.state.hasError, isTrue);
    expect(settings.state.valueOrNull, isFalse);
    expect(engine.normalizationEnabled, isFalse);
    expect(
      (await SharedPreferences.getInstance()).getBool(
        AudioSettingsNotifier.preferenceKey,
      ),
      isNot(true),
    );
  });

  test(
    'unsupported backend preserves saved preferences for supported backends',
    () async {
      SharedPreferences.setMockInitialValues({
        AudioSettingsNotifier.preferenceKey: true,
      });
      final engine = _UnsupportedEngine();
      final settings = AudioSettingsNotifier(engine);
      addTearDown(settings.dispose);
      await settings.ready;
      await settings.setEnabled(true);
      expect(settings.state.valueOrNull, isFalse);
      expect(engine.normalizationEnabled, isFalse);
      expect(
        (await SharedPreferences.getInstance()).getBool(
          AudioSettingsNotifier.preferenceKey,
        ),
        isTrue,
      );
    },
  );

  test(
    'playback restores processing before loading the first source',
    () async {
      SharedPreferences.setMockInitialValues({
        AudioSettingsNotifier.preferenceKey: true,
      });
      final engine = _LoadObserver();
      final container = ProviderContainer(
        overrides: [
          engineProvider.overrideWithValue(engine),
          repositoryProvider.overrideWithValue(InMemoryLibraryRepository()),
        ],
      );
      addTearDown(container.dispose);
      final item = MediaItem(title: 'Track', localPath: '/track.mp3');
      await container.read(libraryProvider.notifier).addMedia([item]);
      container.read(queueProvider.notifier).start([item.id], shuffle: false);
      await container.read(playbackControllerProvider).openCurrent();
      expect(engine.normalizedAtLoad, isTrue);
    },
  );

  for (final supported in [true, false]) {
    testWidgets('normalization setting reflects backend support: $supported', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final engine = supported ? FakePlaybackEngine() : _UnsupportedEngine();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            engineProvider.overrideWithValue(engine),
            repositoryProvider.overrideWithValue(InMemoryLibraryRepository()),
            activeLanguageCodeProvider.overrideWithValue('ja'),
          ],
          child: MaterialApp(
            theme: yureruTheme(),
            home: const Scaffold(body: SettingsScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final setting = find.byKey(const ValueKey('volume-normalization'));
      await tester.scrollUntilVisible(setting, 300);
      await tester.pumpAndSettle();
      final widget = tester.widget<SwitchListTile>(setting);
      expect(widget.onChanged != null, supported);
      if (supported) {
        await tester.tap(setting);
        await tester.pumpAndSettle();
        expect(engine.normalizationEnabled, isTrue);
        expect(tester.widget<SwitchListTile>(setting).value, isTrue);
      } else {
        expect(find.text('この再生方式では利用できません。'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
