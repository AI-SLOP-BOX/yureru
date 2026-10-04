import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yureru/app_state.dart';
import 'package:yureru/data/session.dart';
import 'package:yureru/data/store.dart';
import 'package:yureru/domain/models.dart';
import 'package:yureru/presentation/theme.dart';

void main() {
  test('playlist independent of folders; same media in two playlists', () async {
    final repo = InMemoryLibraryRepository();
    final m = MediaItem(title: 'v', localPath: '/tmp/v.mp4');
    await repo.saveMedia([m]);
    await repo.savePlaylists([
      Playlist(name: 'P1', mediaIds: [m.id]),
      Playlist(name: 'P2', mediaIds: [m.id]),
    ]);
    final pls = await repo.loadPlaylists();
    expect(pls.length, 2);
    expect(pls[0].mediaIds, [m.id]);
    expect(pls[1].mediaIds, [m.id]);
  });

  group('displayTitle', () {
    test('invisible-only names fall back', () {
      expect(displayTitle('夜の海'), '夜の海');
      expect(displayTitle('  夜の海  '), '夜の海');
      expect(displayTitle(''), '(無題)');
      expect(displayTitle('   '), '(無題)');
      expect(displayTitle('​'), '(無題)');
      expect(displayTitle('⁠'), '(無題)');
    });
  });

  group('SessionStore', () {
    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
    });

    test('queue round-trips', () async {
      const store = SessionStore();
      expect(await store.loadQueue(), isNull);
      await store.saveQueue(const QueueState(
          queue: ['a', 'b'], index: 1, shuffle: true, speed: 1.5));
      final loaded = await store.loadQueue();
      expect(loaded?.queue, ['a', 'b']);
      expect(loaded?.index, 1);
      expect(loaded?.shuffle, isTrue);
      expect(loaded?.speed, 1.5);
    });

    test('positions keep most-recent, capped', () async {
      const store = SessionStore();
      await store.savePosition('a', 10000);
      await store.savePosition('b', 20000);
      await store.savePosition('a', 30000); // refresh recency
      var all = await store.loadPositions();
      expect(all, {'a': 30000, 'b': 20000});
      await store.savePosition('c', 0); // ignored
      all = await store.loadPositions();
      expect(all.containsKey('c'), isFalse);
    });
  });
}
