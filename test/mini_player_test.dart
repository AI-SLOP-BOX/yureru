import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yureru/app_state.dart';
import 'package:yureru/data/store.dart';
import 'package:yureru/domain/models.dart';
import 'package:yureru/playback/fake_engine.dart';
import 'package:yureru/playback/playback_engine.dart';
import 'package:yureru/presentation/widgets/mini_player.dart';

class _StreamingEngine extends FakePlaybackEngine {
  final _updates = StreamController<PlaybackSnapshot>.broadcast(sync: true);

  @override
  Stream<PlaybackSnapshot> get snapshots => _updates.stream;

  void emitPlaying(bool isPlaying) {
    snap = PlaybackSnapshot(
      position: snap.position,
      duration: snap.duration,
      isPlaying: isPlaying,
      initialized: snap.initialized,
    );
    _updates.add(snap);
  }

  @override
  Future<void> dispose() async {
    await _updates.close();
    await super.dispose();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('mini player reflects pause and play updates while mounted', (
    tester,
  ) async {
    final engine = _StreamingEngine()..emitPlaying(true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          engineProvider.overrideWithValue(engine),
          repositoryProvider.overrideWithValue(InMemoryLibraryRepository()),
        ],
        child: const MaterialApp(home: Scaffold(body: MiniPlayer())),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MiniPlayer)),
    );
    final media = MediaItem(title: 'Track', localPath: '/track.mp4');
    await container.read(libraryProvider.notifier).addMedia([media]);
    container.read(queueProvider.notifier).start([media.id], shuffle: false);
    await tester.pump();
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);

    engine.emitPlaying(false);
    await tester.pump();
    expect(find.byIcon(Icons.pause_rounded), findsNothing);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
