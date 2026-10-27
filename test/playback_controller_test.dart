import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yureru/app_state.dart';
import 'package:yureru/data/store.dart';
import 'package:yureru/domain/models.dart';
import 'package:yureru/playback/fake_engine.dart';
import 'package:yureru/playback/playback_controller.dart';
import 'package:yureru/playback/playback_engine.dart';
import 'dart:convert';

ProviderContainer makeContainer(FakePlaybackEngine fake) {
  return ProviderContainer(
    overrides: [
      repositoryProvider.overrideWithValue(InMemoryLibraryRepository()),
      engineProvider.overrideWithValue(fake),
    ],
  );
}

void main() {
  test(
    'mute restores the last audible volume after slider zero and clamping',
    () async {
      final fake = FakePlaybackEngine()..vol = 0.4;
      final container = makeContainer(fake);
      addTearDown(container.dispose);
      final controller = container.read(playbackControllerProvider);
      await controller.toggleMute();
      expect(fake.volume, 0);
      await controller.toggleMute();
      expect(fake.volume, 0.4);
      await controller.setVolume(0.65);
      await controller.setVolume(0);
      await controller.toggleMute();
      expect(fake.volume, 0.65);
      expect(container.read(volumeProvider), 0.65);
      await controller.setVolume(2);
      expect(fake.volume, 1);
      await controller.setVolume(-1);
      await controller.toggleMute();
      expect(fake.volume, 1);
    },
  );

  test('play/pause/seek delegate to engine', () async {
    final fake = FakePlaybackEngine();
    final c = makeContainer(fake);
    final ctl = c.read(playbackControllerProvider);
    await ctl.toggle(); // was paused -> play
    expect(fake.playCalls, 1);
    await ctl.toggle(); // playing -> pause
    expect(fake.pauseCalls, 1);
    await ctl.seekTo(const Duration(seconds: 10));
    expect(fake.seeks, [const Duration(seconds: 10)]);
  });

  test('ended -> next advances queue and loads next item', () async {
    final fake = FakePlaybackEngine();
    final c = makeContainer(fake);
    final repo = c.read(repositoryProvider) as InMemoryLibraryRepository;
    final a = MediaItem(title: 'A', localPath: '/tmp/a.mp4');
    final b = MediaItem(title: 'B', localPath: '/tmp/b.mp4');
    await repo.saveMedia([a, b]);
    await c.read(libraryProvider.notifier).load();
    await c.read(libraryProvider.notifier).createPlaylist('P');
    final pl = c.read(libraryProvider).playlists.single;
    await c.read(libraryProvider.notifier).addToPlaylist(pl.id, a.id);
    await c.read(libraryProvider.notifier).addToPlaylist(pl.id, b.id);
    final ctl = c.read(playbackControllerProvider);
    await ctl.startPlaylist(pl.id, shuffle: false);
    expect(c.read(queueProvider).currentId, a.id);
    expect(fake.loaded?.uri, '/tmp/a.mp4');
    fake.emitCompleted();
    await Future.delayed(const Duration(milliseconds: 50));
    expect(c.read(queueProvider).currentId, b.id);
    expect(fake.loaded?.uri, '/tmp/b.mp4');
  });

  test('engine accepts http URL source (future LAN streaming)', () async {
    final fake = FakePlaybackEngine();
    final c = makeContainer(fake);
    final ctl = c.read(playbackControllerProvider);
    const src = PlaybackSource(
      mediaId: 'mid',
      uri: 'http://192.168.0.2:8080/media/mid',
    );
    expect(src.isNetwork, true);
    await fake.load(src);
    expect(fake.loaded?.uri, src.uri);
    expect(ctl, isNotNull);
  });

  Future<(ProviderContainer, FakePlaybackEngine, String, String)>
  setupTwoItemQueue() async {
    final fake = FakePlaybackEngine();
    final c = makeContainer(fake);
    final repo = c.read(repositoryProvider) as InMemoryLibraryRepository;
    final a = MediaItem(title: 'A', localPath: '/tmp/a.mp4');
    final b = MediaItem(title: 'B', localPath: '/tmp/b.mp4');
    await repo.saveMedia([a, b]);
    await c.read(libraryProvider.notifier).load();
    await c.read(libraryProvider.notifier).createPlaylist('P');
    final pl = c.read(libraryProvider).playlists.single;
    await c.read(libraryProvider.notifier).addToPlaylist(pl.id, a.id);
    await c.read(libraryProvider.notifier).addToPlaylist(pl.id, b.id);
    await c
        .read(playbackControllerProvider)
        .startPlaylist(pl.id, shuffle: false);
    return (c, fake, a.id, b.id);
  }

  test('repeat one restarts the same track from the beginning', () async {
    final (c, fake, aId, _) = await setupTwoItemQueue();
    c.read(queueProvider.notifier).cycleRepeat(); // all -> one
    fake.emitCompleted();
    await Future.delayed(const Duration(milliseconds: 50));
    expect(c.read(queueProvider).currentId, aId);
    expect(fake.loaded?.uri, '/tmp/a.mp4');
    expect(fake.seeks, contains(Duration.zero));
  });

  test('repeat off stops after the last track instead of wrapping', () async {
    final (c, fake, _, bId) = await setupTwoItemQueue();
    c.read(queueProvider.notifier).cycleRepeat(); // all -> one
    c.read(queueProvider.notifier).cycleRepeat(); // one -> off
    c.read(queueProvider.notifier).jumpTo(1);
    await c.read(playbackControllerProvider).openCurrent();
    expect(c.read(queueProvider).currentId, bId);
    fake.emitCompleted();
    await Future.delayed(const Duration(milliseconds: 50));
    expect(c.read(queueProvider).currentId, bId);
    expect(fake.loaded?.uri, '/tmp/b.mp4');
  });

  test('volume is delegated to the engine (0..1)', () async {
    final fake = FakePlaybackEngine();
    final c = makeContainer(fake);
    expect(fake.volume, 1.0);
    await fake.setVolume(0.3);
    expect(fake.volume, closeTo(0.3, 1e-9));
    expect(c.read(engineProvider).volume, closeTo(0.3, 1e-9));
  });

  test('restoreSession preloads paused engine at saved position', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({
      'yureru.session.queue.v1': jsonEncode({
        'queue': ['mid'],
        'index': 0,
        'shuffle': false,
        'speed': 1.0,
        'original': ['mid'],
        'repeat': 'all',
      }),
      'yureru.session.positions.v1': jsonEncode({'mid': 65000}),
    });
    final fake = FakePlaybackEngine();
    final c = makeContainer(fake);
    final repo = c.read(repositoryProvider) as InMemoryLibraryRepository;
    await repo.saveMedia([
      MediaItem(id: 'mid', title: 'M', localPath: '/tmp/m.mp4'),
    ]);
    await c.read(libraryProvider.notifier).load();
    await c.read(playbackControllerProvider).restoreSession();
    expect(c.read(queueProvider).currentId, 'mid');
    expect(fake.loaded?.uri, '/tmp/m.mp4');
    expect(fake.loaded?.start, const Duration(milliseconds: 65000));
    expect(fake.snapshot.isPlaying, isFalse);
  });

  test('restoreSession ignores stale ids', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({
      'yureru.session.queue.v1': jsonEncode({
        'queue': ['gone'],
        'index': 0,
        'original': ['gone'],
      }),
    });
    final fake = FakePlaybackEngine();
    final c = makeContainer(fake);
    await c.read(libraryProvider.notifier).load();
    await c.read(playbackControllerProvider).restoreSession();
    expect(c.read(queueProvider).hasCurrent, isFalse);
    expect(fake.loaded, isNull);
  });

  test(
    'handleMediaRemoved removes deleted item from queue and advances if playing',
    () async {
      final fake = FakePlaybackEngine();
      final c = makeContainer(fake);
      final repo = c.read(repositoryProvider) as InMemoryLibraryRepository;
      final a = MediaItem(id: 'a', title: 'A', localPath: '/tmp/a.mp4');
      final b = MediaItem(id: 'b', title: 'B', localPath: '/tmp/b.mp4');
      await repo.saveMedia([a, b]);
      await c.read(libraryProvider.notifier).load();
      c.read(queueProvider.notifier).start(['a', 'b'], shuffle: false);
      final ctl = c.read(playbackControllerProvider);
      await ctl.openCurrent();
      expect(c.read(queueProvider).currentId, 'a');

      await ctl.handleMediaRemoved('a');
      expect(c.read(queueProvider).currentId, 'b');
      expect(fake.loaded?.uri, '/tmp/b.mp4');
    },
  );
}
