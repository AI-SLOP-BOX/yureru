import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yureru/playback/fake_engine.dart';
import 'package:yureru/playback/ios_playback_engine.dart';
import 'package:yureru/playback/playback_engine.dart';

class _StreamingEngine extends FakePlaybackEngine {
  final updates = StreamController<PlaybackSnapshot>.broadcast();

  @override
  Stream<PlaybackSnapshot> get snapshots => updates.stream;

  @override
  Future<void> dispose() async {
    await updates.close();
    await super.dispose();
  }
}

void main() {
  test(
    'existing iOS subscribers receive fallback updates across loads',
    () async {
      final backends = <_StreamingEngine>[];
      final engine = IosPlaybackEngine(
        fallbackFactory: () {
          final backend = _StreamingEngine();
          backends.add(backend);
          return backend;
        },
      );
      final snapshots = <PlaybackSnapshot>[];
      final positions = <Duration>[];
      var completed = 0;
      final subscriptions = [
        engine.snapshots.listen(snapshots.add),
        engine.positionStream.listen(positions.add),
        engine.completedStream.listen((_) => completed++),
      ];
      for (var i = 0; i < 2; i++) {
        await engine.load(PlaybackSource(mediaId: '$i', uri: '/test/$i.webm'));
        final update = PlaybackSnapshot(
          initialized: true,
          isPlaying: true,
          position: Duration(seconds: i + 1),
        );
        backends.last.updates.add(update);
        backends.last.emitCompleted();
        await Future<void>.delayed(Duration.zero);
        expect(snapshots, contains(same(update)));
      }
      expect(completed, 2);
      expect(positions, hasLength(2));
      expect(backends.first.disposed, isTrue);
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
      await engine.dispose();
    },
  );
}
