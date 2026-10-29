import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yureru/domain/models.dart';
import 'package:yureru/platform/system_media_session.dart';
import 'package:yureru/playback/fake_engine.dart';
import 'package:yureru/playback/playback_engine.dart';

const channel = MethodChannel('yureru/system_media');
const codec = StandardMethodCodec();

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return null;
    });
  });
  tearDown(
    () =>
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null),
  );

  Future<dynamic> nativeCommand(String command, [Object? value]) async {
    final result = Completer<ByteData?>();
    await binding.defaultBinaryMessenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(MethodCall(command, value)),
      result.complete,
    );
    return codec.decodeEnvelope((await result.future)!);
  }

  SystemMediaSession create(
    FakePlaybackEngine engine,
    List<String> actions,
    List<Duration> seeks,
  ) {
    final session = SystemMediaSession(
      engine: engine,
      play: () async {
        actions.add('play');
      },
      pause: () async {
        actions.add('pause');
      },
      toggle: () async {
        actions.add('toggle');
      },
      next: () async {
        actions.add('next');
      },
      previous: () async {
        actions.add('previous');
      },
      seek: (value) async {
        seeks.add(value);
      },
      refresh: () {},
    );
    addTearDown(session.dispose);
    return session;
  }

  void update(
    SystemMediaSession session, {
    int position = 9100,
    bool playing = true,
    MediaItem? media,
  }) {
    session.update(
      media:
          media ??
          MediaItem(
            id: 'track',
            title: 'Title',
            artist: 'Artist',
            localPath: '/track.mp3',
            artworkPath: '/cover.jpg',
          ),
      snapshot: PlaybackSnapshot(
        initialized: true,
        isPlaying: playing,
        position: Duration(milliseconds: position),
        duration: const Duration(seconds: 100),
      ),
      rate: 1.25,
      canNext: true,
      canPrevious: false,
    );
  }

  test(
    'metadata, progress and pause updates are deduplicated at one-second intervals',
    () async {
      final session = create(FakePlaybackEngine(), [], []);
      update(session);
      await Future<void>.delayed(Duration.zero);
      expect(calls.single.arguments, containsPair('title', 'Title'));
      expect(calls.single.arguments, containsPair('artist', 'Artist'));
      expect(calls.single.arguments, containsPair('artworkPath', '/cover.jpg'));
      expect(calls.single.arguments, containsPair('rate', 1.25));
      update(session, position: 9400);
      await Future<void>.delayed(Duration.zero);
      expect(calls, hasLength(1));
      update(session, position: 10000);
      await Future<void>.delayed(Duration.zero);
      update(session, position: 10200, playing: false);
      await Future<void>.delayed(Duration.zero);
      expect(calls, hasLength(3));
      expect(calls.last.arguments, containsPair('playing', false));
      expect(calls.last.arguments, containsPair('positionMs', 10200));
      update(
        session,
        position: 10200,
        playing: false,
        media: MediaItem(
          id: 'track',
          title: 'Edited title',
          localPath: '/track.mp3',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(calls.last.arguments, containsPair('title', 'Edited title'));
      expect(calls.last.arguments, containsPair('artworkPath', null));
    },
  );

  test(
    'thumbnail is used as system artwork when jacket art is absent',
    () async {
      final session = create(FakePlaybackEngine(), [], []);
      addTearDown(session.dispose);
      update(
        session,
        media: MediaItem(
          id: 'thumbnail-only',
          title: 'Thumbnail only',
          localPath: '/track.mp4',
          thumbnailPath: '/thumb.jpg',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(calls.single.arguments, containsPair('artworkPath', '/thumb.jpg'));
    },
  );

  test(
    'OS actions use the existing controller callbacks and clamp seek requests',
    () async {
      final engine = FakePlaybackEngine();
      final actions = <String>[];
      final seeks = <Duration>[];
      final session = create(engine, actions, seeks);
      update(session);
      for (final command in ['play', 'pause', 'toggle', 'next', 'previous']) {
        expect(await nativeCommand(command), isTrue);
      }
      expect(actions, ['play', 'pause', 'toggle', 'next', 'previous']);
      expect(await nativeCommand('seek', 12500), isTrue);
      expect(await nativeCommand('seek', 999999), isTrue);
      expect(seeks, [
        const Duration(milliseconds: 12500),
        const Duration(seconds: 100),
      ]);
      expect(await nativeCommand('seek', -1), isFalse);
      expect(await nativeCommand('seek', 'bad'), isFalse);
      expect(await nativeCommand('unknown'), isFalse);
    },
  );

  test(
    'empty queue and disposal clear the OS session and reject stale actions',
    () async {
      final actions = <String>[];
      final session = create(FakePlaybackEngine(), actions, []);
      update(session);
      await Future<void>.delayed(Duration.zero);
      session.update(
        media: null,
        snapshot: const PlaybackSnapshot(),
        rate: 1,
        canNext: false,
        canPrevious: false,
      );
      await Future<void>.delayed(Duration.zero);
      expect(calls.last.arguments, {'active': false});
      expect(await nativeCommand('play'), isFalse);
      expect(actions, isEmpty);
      await session.dispose();
      expect(calls.last.method, 'clear');
      final count = calls.length;
      update(session);
      await Future<void>.delayed(Duration.zero);
      expect(calls, hasLength(count));
    },
  );

  test(
    'slow native updates coalesce rather than publish stale progress later',
    () async {
      final gate = Completer<void>();
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        calls.add(call);
        if (calls.length == 1) await gate.future;
        return null;
      });
      final session = create(FakePlaybackEngine(), [], []);
      update(session, position: 1000);
      await Future<void>.delayed(Duration.zero);
      update(session, position: 2000);
      update(session, position: 3000);
      expect(calls, hasLength(1));
      gate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(calls, hasLength(2));
      expect(calls.last.arguments, containsPair('positionMs', 3000));
    },
  );

  test(
    'unavailable platform integration does not interrupt app playback',
    () async {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) async => throw MissingPluginException(),
      );
      final engine = FakePlaybackEngine();
      final session = create(engine, [], []);
      update(session);
      await Future<void>.delayed(Duration.zero);
      await engine.play();
      expect(engine.snapshot.isPlaying, isTrue);
      await session.dispose();
    },
  );
}
