import 'package:flutter_test/flutter_test.dart';
import 'package:yureru/app_state.dart';
import 'package:yureru/domain/models.dart';

void main() {
  test('ordered queue preserves order', () {
    expect(QueueBuilder.build(['A', 'B', 'C', 'D', 'E'], shuffle: false), [
      'A',
      'B',
      'C',
      'D',
      'E',
    ]);
  });
  test(
    'shuffle queue is a permutation with no duplicates until full cycle',
    () {
      final q = QueueBuilder.build(
        ['A', 'B', 'C', 'D', 'E'],
        shuffle: true,
        seed: 42,
      );
      expect(q.length, 5);
      expect(q.toSet(), {'A', 'B', 'C', 'D', 'E'});
    },
  );
  test('media identity is id, not path', () {
    final a = MediaItem(title: 'x', localPath: '/a/x.mp4');
    final b = MediaItem(title: 'x', localPath: '/b/x.mp4');
    expect(a.id == b.id, false);
  });

  group('QueueNotifier', () {
    test('jumpTo / move keep the current track and playlist source', () {
      final n = QueueNotifier();
      n.start(['A', 'B', 'C', 'D'], playlistId: 'p', shuffle: false);
      n.jumpTo(2);
      expect(n.state.currentId, 'C');
      n.move(0, 3);
      expect(n.state.queue, ['B', 'C', 'D', 'A']);
      expect(n.state.currentId, 'C');
      expect(n.state.sourcePlaylistId, 'p');
    });

    test('toggleShuffle keeps current first, off restores original order', () {
      final n = QueueNotifier();
      n.start(['A', 'B', 'C', 'D'], playlistId: null, shuffle: false);
      n.jumpTo(1); // B
      n.toggleShuffle();
      expect(n.state.shuffle, true);
      expect(n.state.queue.first, 'B');
      expect(n.state.queue.toSet(), {'A', 'B', 'C', 'D'});
      n.toggleShuffle();
      expect(n.state.shuffle, false);
      expect(n.state.queue, ['A', 'B', 'C', 'D']);
      expect(n.state.currentId, 'B');
    });

    test('cycleRepeat: all -> one -> off -> all', () {
      final n = QueueNotifier();
      expect(n.state.repeat, 'all');
      n.cycleRepeat();
      expect(n.state.repeat, 'one');
      n.cycleRepeat();
      expect(n.state.repeat, 'off');
      n.cycleRepeat();
      expect(n.state.repeat, 'all');
    });

    test('playNext inserts after current without duplicating', () {
      final n = QueueNotifier();
      n.start(['A', 'B', 'C'], shuffle: false);
      n.jumpTo(1); // B playing
      n.playNext('D');
      expect(n.state.queue, ['A', 'B', 'D', 'C']);
      expect(n.state.currentId, 'B');
      // Existing item moves instead of duplicating.
      n.playNext('A');
      expect(n.state.queue, ['B', 'A', 'D', 'C']);
      expect(n.state.currentId, 'B');
    });

    test('append adds to end, ignores duplicates', () {
      final n = QueueNotifier();
      n.start(['A', 'B'], shuffle: false);
      n.append('C');
      expect(n.state.queue, ['A', 'B', 'C']);
      expect(n.state.currentId, 'A');
      n.append('B');
      expect(n.state.queue, ['A', 'B', 'C']);
    });

    test('toJson/fromJson round-trips', () {
      final n = QueueNotifier();
      n.start(['A', 'B'], playlistId: 'p', shuffle: false);
      n.jumpTo(1);
      n.setSpeed(1.5);
      final rt = QueueState.fromJson(n.state.toJson());
      expect(rt.queue, ['A', 'B']);
      expect(rt.index, 1);
      expect(rt.sourcePlaylistId, 'p');
      expect(rt.speed, 1.5);
      expect(rt.repeat, 'all');
    });

    test('restore prunes unknown ids', () {
      final n = QueueNotifier();
      n.restore(
        const QueueState(
          queue: ['A', 'X', 'B'],
          index: 2,
          sourcePlaylistId: 'p',
          shuffle: true,
          original: ['A', 'X', 'B'],
        ),
        {'A', 'B'},
      );
      expect(n.state.queue, ['A', 'B']);
      expect(n.state.index, 1);
      expect(n.state.sourcePlaylistId, 'p');
      n.restore(const QueueState(queue: ['Z'], index: 0), {'A'});
      expect(n.state.hasCurrent, isFalse);
    });
  });
}
