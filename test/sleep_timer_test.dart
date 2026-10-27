import 'package:flutter_test/flutter_test.dart';
import 'package:yureru/playback/sleep_timer.dart';

void main() {
  testWidgets('countdown pauses once and clears state', (tester) async {
    var pauses = 0;
    final timer = SleepTimer(() async {
      pauses++;
    });
    timer.after(const Duration(minutes: 15));
    await tester.pump(const Duration(minutes: 14));
    expect(pauses, 0);
    await tester.pump(const Duration(minutes: 1));
    expect(pauses, 1);
    expect(timer.state.active, false);
    await tester.pump(const Duration(hours: 1));
    expect(pauses, 1);
    timer.dispose();
  });

  testWidgets(
    'replacement, cancellation and disposal cancel pending callbacks',
    (tester) async {
      var pauses = 0;
      final timer = SleepTimer(() async {
        pauses++;
      });
      timer.after(const Duration(minutes: 15));
      timer.after(const Duration(minutes: 30));
      await tester.pump(const Duration(minutes: 15));
      expect(pauses, 0);
      timer.cancel();
      await tester.pump(const Duration(minutes: 30));
      expect(pauses, 0);
      timer.after(const Duration(minutes: 15));
      timer.dispose();
      await tester.pump(const Duration(minutes: 30));
      expect(pauses, 0);
    },
  );

  test('end of track consumes only the selected track', () async {
    var pauses = 0;
    final timer = SleepTimer(() async {
      pauses++;
    });
    timer.endOfTrack('a');
    expect(await timer.trackEnded('b'), false);
    expect(await timer.trackEnded('a'), true);
    expect(await timer.trackEnded('a'), false);
    expect(pauses, 1);
    timer.dispose();
  });

  test('manual track change cancels end mode but preserves countdown', () {
    final timer = SleepTimer(() async {});
    timer.endOfTrack('a');
    timer.currentChanged('a');
    expect(timer.state.active, true);
    timer.currentChanged('b');
    expect(timer.state.active, false);
    timer.after(const Duration(minutes: 15));
    timer.currentChanged('c');
    expect(timer.state.active, true);
    timer.currentChanged(null);
    expect(timer.state.active, false);
    timer.dispose();
  });

  test('pause failures are reported without resuming the queue', () async {
    final timer = SleepTimer(() async {
      throw StateError('pause failed');
    });
    timer.endOfTrack('a');
    expect(await timer.trackEnded('a'), true);
    expect(timer.state.failed, true);
    timer.cancel();
    expect(timer.state.failed, false);
    timer.dispose();
  });
}
