import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yureru/data/importer.dart';
import 'package:yureru/data/thumbnails.dart';

void main() {
  group('ThumbnailService.forMedia', () {    test('network uri -> null without native call', () async {
      expect(
        await ThumbnailService.forMedia(
            mediaId: 'x', localPath: 'http://192.168.0.2:8080/media/x'),
        isNull,
      );
    });
    test('missing file -> null without throwing', () async {
      expect(
        await ThumbnailService.forMedia(
            mediaId: 'missing', localPath: '/tmp/yureru-no-such-file.mp4'),
        isNull,
      );
    });

    test('mocked native bytes are cached; second call hits disk', () async {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      final messenger = binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async {
        if (call.method == 'getTemporaryDirectory') {
          return Directory.systemTemp.path;
        }
        return null;
      });
      var nativeCalls = 0;
      messenger.setMockMethodCallHandler(mediaPickerChannel, (call) async {
        if (call.method == 'makeThumbnail') {
          nativeCalls++;
          expect((call.arguments as Map)['path'], isA<String>());
          expect((call.arguments as Map)['maxWidth'], 320);
          expect((call.arguments as Map).containsKey('timeMs'), isFalse);
          return {
            'jpg': Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]),
            'timeMs': 2000,
          };
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(mediaPickerChannel, null);
        messenger.setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
      });

      final src = File('${Directory.systemTemp.path}/yureru-thumb-src.mp4');
      await src.writeAsBytes([0]);
      addTearDown(() async {
        if (await src.exists()) await src.delete();
        final cached = await ThumbnailService.cacheFileFor('mock1');
        if (await cached.exists()) await cached.delete();
        final sidecar = File('${cached.path}.txt');
        if (await sidecar.exists()) await sidecar.delete();
        for (final legacy
            in await ThumbnailService.legacyCacheFilesFor('mock1')) {
          if (await legacy.exists()) await legacy.delete();
        }
      });

      final first = await ThumbnailService.forMedia(
          mediaId: 'mock1', localPath: src.path);
      expect(first, isNotNull);
      expect(first!.path.endsWith('.v3.jpg'), isTrue);
      expect(await first.readAsBytes(), [0xFF, 0xD8, 0xFF, 0xD9]);
      expect(await ThumbnailService.bestTimeMsFor('mock1'), 2000);
      final second = await ThumbnailService.forMedia(
          mediaId: 'mock1', localPath: src.path);
      expect(second?.path, first.path);
      expect(nativeCalls, 1);
    });
  });

  group('DurationService.forMedia', () {    test('missing file -> null without throwing', () async {
      expect(
        await DurationService.forMedia(
            mediaId: 'dur-missing',
            localPath: '/tmp/yureru-no-such-file.mp4'),
        isNull,
      );
    });

    test('mocked native ms are cached in memory', () async {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      final messenger = binding.defaultBinaryMessenger;
      var nativeCalls = 0;
      messenger.setMockMethodCallHandler(mediaPickerChannel, (call) async {
        if (call.method == 'probeDuration') {
          nativeCalls++;
          expect((call.arguments as Map)['path'], isA<String>());
          return 305000;
        }
        return null;
      });
      addTearDown(() =>
          messenger.setMockMethodCallHandler(mediaPickerChannel, null));

      final src = File('${Directory.systemTemp.path}/yureru-dur-src.mp4');
      await src.writeAsBytes([0]);
      addTearDown(() async {
        if (await src.exists()) await src.delete();
      });

      expect(
        await DurationService.forMedia(mediaId: 'dur1', localPath: src.path),
        305000,
      );
      expect(
        await DurationService.forMedia(mediaId: 'dur1', localPath: src.path),
        305000,
      );
      expect(nativeCalls, 1);
    });
  });

  group('ThumbnailService throttling', () {
    test('concurrent generations complete without deadlock', () async {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      final messenger = binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async {
        if (call.method == 'getTemporaryDirectory') {
          return Directory.systemTemp.path;
        }
        return null;
      });
      var nativeCalls = 0;
      messenger.setMockMethodCallHandler(mediaPickerChannel, (call) async {
        if (call.method == 'makeThumbnail') {
          nativeCalls++;
          await Future.delayed(const Duration(milliseconds: 50));
          return {
            'jpg': Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]),
            'timeMs': 1000,
          };
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(mediaPickerChannel, null);
        messenger.setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
      });

      final srcs = <File>[];
      for (var i = 0; i < 4; i++) {
        final f = File('${Directory.systemTemp.path}/yureru-thr-$i.mp4');
        await f.writeAsBytes([0]);
        srcs.add(f);
      }
      addTearDown(() async {
        for (final f in srcs) {
          if (await f.exists()) await f.delete();
        }
        for (var i = 0; i < 4; i++) {
          final cached =
              await ThumbnailService.cacheFileFor('thr$i');
          if (await cached.exists()) await cached.delete();
          final sidecar = File('${cached.path}.txt');
          if (await sidecar.exists()) await sidecar.delete();
        }
      });

      final results = await Future.wait([
        for (var i = 0; i < 4; i++)
          ThumbnailService.forMedia(
              mediaId: 'thr$i', localPath: srcs[i].path),
      ]);
      expect(results.every((f) => f != null), isTrue);
      expect(nativeCalls, 4);
    });
  });
}
