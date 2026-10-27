import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yureru/app_state.dart';
import 'package:yureru/data/session.dart';
import 'package:yureru/data/store.dart';
import 'package:yureru/domain/models.dart';
import 'package:yureru/library/media_order.dart';
import 'package:yureru/playback/fake_engine.dart';
import 'package:yureru/playback/playback_controller.dart';
import 'package:yureru/playback/playback_engine.dart';
import 'package:yureru/playback/sleep_timer_provider.dart';

class _FailingLoad extends FakePlaybackEngine {
  @override
  Future<void> load(PlaybackSource source, {bool autoplay = true}) async =>
      throw StateError('unreadable');
}

class _FailingSave extends InMemoryLibraryRepository {
  bool reject = false;
  @override
  Future<void> saveMedia(List<MediaItem> media) async {
    if (reject) throw StateError('storage unavailable');
    await super.saveMedia(media);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'old and malformed dates load safely; copies can preserve or clear history',
    () {
      final old = MediaItem.fromJson({'id': 'old', 'localPath': '/old.mp3'});
      expect(old.lastPlayedAt, isNull);
      expect(
        MediaItem.fromJson({
          ...old.toJson(),
          'lastPlayedAt': 'invalid',
        }).lastPlayedAt,
        isNull,
      );
      final date = DateTime.utc(2026, 10, 25);
      final played = old.copyWith(lastPlayedAt: date);
      expect(MediaItem.fromJson(played.toJson()).lastPlayedAt, date);
      expect(played.copyWith(title: 'Edited').lastPlayedAt, date);
      expect(played.copyWith(lastPlayedAt: null).lastPlayedAt, isNull);
    },
  );

  test(
    'history clears without deleting favorites, metadata or playlists',
    () async {
      final repo = InMemoryLibraryRepository();
      final library = LibraryNotifier(repo);
      addTearDown(library.dispose);
      final item = MediaItem(
        id: 'saved',
        title: 'Saved',
        localPath: '/saved.mp3',
        isFavorite: true,
      );
      final temporary = MediaItem(
        id: 'temp',
        title: 'Temp',
        localPath: '/temp.mp3',
        origin: 'temporary',
      );
      await library.addMedia([item]);
      library.addTemporaryMedia([temporary]);
      final playlist = await library.createPlaylist('Favorites');
      await library.addToPlaylist(playlist.id, item.id);
      final date = DateTime.utc(2026, 10, 25);
      await library.recordPlayback(item.id, at: date);
      await library.recordPlayback(temporary.id, at: date);
      expect(library.state.byId(temporary.id)!.lastPlayedAt, isNull);
      await library.load();
      expect(library.state.byId(item.id)!.lastPlayedAt, date);
      await library.clearPlaybackHistory();
      await library.load();
      expect(library.state.byId(item.id)!.toJson(), item.toJson());
      expect(library.state.playlistById(playlist.id)!.mediaIds, [item.id]);
    },
  );

  test(
    'recent order puts played tracks first, then unplayed tracks by import date',
    () {
      final items = [
        MediaItem(
          id: 'never-old',
          title: '',
          localPath: '',
          createdAt: DateTime.utc(2025),
        ),
        MediaItem(
          id: 'played-old',
          title: '',
          localPath: '',
          lastPlayedAt: DateTime.utc(2026),
        ),
        MediaItem(
          id: 'never-new',
          title: '',
          localPath: '',
          createdAt: DateTime.utc(2026),
        ),
        MediaItem(
          id: 'played-new',
          title: '',
          localPath: '',
          lastPlayedAt: DateTime.utc(2026, 10),
        ),
      ]..sort(compareRecentlyPlayed);
      expect(items.map((m) => m.id), [
        'played-new',
        'played-old',
        'never-new',
        'never-old',
      ]);
    },
  );

  Future<ProviderContainer> setup(
    PlaybackEngine engine,
    LibraryRepository repo,
  ) async {
    final container = ProviderContainer(
      overrides: [
        engineProvider.overrideWithValue(engine),
        repositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    final item = MediaItem(
      id: 'track',
      title: 'Track',
      localPath: '/track.mp3',
    );
    await container.read(libraryProvider.notifier).addMedia([item]);
    container.read(queueProvider.notifier).start([item.id], shuffle: false);
    return container;
  }

  test(
    'countdown pauses and saves position without changing volume or queue',
    () async {
      final engine = FakePlaybackEngine();
      final container = await setup(engine, InMemoryLibraryRepository());
      final controller = container.read(playbackControllerProvider);
      await controller.openCurrent();
      await controller.setVolume(0.4);
      await engine.seekTo(const Duration(seconds: 42));
      final queue = container.read(queueProvider).toJson();
      container
          .read(sleepTimerProvider.notifier)
          .after(const Duration(milliseconds: 1));
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(engine.snapshot.isPlaying, false);
      expect(engine.pauseCalls, 1);
      expect(engine.volume, 0.4);
      expect(container.read(queueProvider).toJson(), queue);
      expect(await container.read(sessionStoreProvider).loadPositions(), {
        'track': 42000,
      });
    },
  );

  for (final repeatOne in [false, true]) {
    test(
      'end sleep timer overrides repeatOne=$repeatOne and keeps the queue',
      () async {
        final engine = FakePlaybackEngine();
        final container = await setup(engine, InMemoryLibraryRepository());
        final controller = container.read(playbackControllerProvider);
        await controller.openCurrent();
        if (repeatOne) container.read(queueProvider.notifier).cycleRepeat();
        final before = container.read(queueProvider).toJson();
        await engine.seekTo(const Duration(seconds: 100));
        container.read(sleepTimerProvider.notifier).endOfTrack('track');
        engine.emitCompleted();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(engine.pauseCalls, 1);
        expect(engine.playCalls, 0);
        expect(engine.snapshot.isPlaying, false);
        expect(container.read(queueProvider).toJson(), before);
        expect(container.read(sleepTimerProvider).active, false);
        expect(
          await container.read(sessionStoreProvider).loadPositions(),
          isEmpty,
        );
      },
    );
  }

  test(
    'successful playback records once per load, not on view changes',
    () async {
      final container = await setup(
        FakePlaybackEngine(),
        InMemoryLibraryRepository(),
      );
      final controller = container.read(playbackControllerProvider);
      await controller.openCurrent();
      final date = container.read(libraryProvider).byId('track')!.lastPlayedAt;
      expect(date, isNotNull);
      await controller.openCurrent();
      expect(container.read(libraryProvider).byId('track')!.lastPlayedAt, date);
    },
  );

  test('failed loads create no playback history', () async {
    final container = await setup(_FailingLoad(), InMemoryLibraryRepository());
    await container.read(playbackControllerProvider).openCurrent();
    expect(container.read(libraryProvider).byId('track')!.lastPlayedAt, isNull);
  });

  test(
    'history persistence failure cannot remove or stop the current track',
    () async {
      final repo = _FailingSave();
      final engine = FakePlaybackEngine();
      final container = await setup(engine, repo);
      repo.reject = true;
      await container.read(playbackControllerProvider).openCurrent();
      expect(container.read(queueProvider).currentId, 'track');
      expect(engine.loaded?.mediaId, 'track');
      expect(engine.snapshot.isPlaying, isTrue);
    },
  );

  test('session restoration is not a play until the user resumes', () async {
    final engine = FakePlaybackEngine();
    final container = await setup(engine, InMemoryLibraryRepository());
    await container
        .read(sessionStoreProvider)
        .saveQueue(container.read(queueProvider));
    final controller = container.read(playbackControllerProvider);
    await controller.restoreSession();
    expect(engine.snapshot.isPlaying, isFalse);
    expect(container.read(libraryProvider).byId('track')!.lastPlayedAt, isNull);
    await controller.toggle();
    expect(
      container.read(libraryProvider).byId('track')!.lastPlayedAt,
      isNotNull,
    );
  });
}
