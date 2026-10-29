import 'package:flutter_test/flutter_test.dart';
import 'package:yureru/data/lyrics.dart';
import 'package:yureru/domain/models.dart';

void main() {
  test('parses synchronized LRC timestamps and highlights current line', () {
    final lines = parseLrc('''
[00:01.20]first line
[00:02.05][00:03.50]shared line
''');

    expect(lines, hasLength(3));
    expect(lines[0].time, const Duration(milliseconds: 1200));
    expect(lines[1].time, const Duration(milliseconds: 2050));
    expect(lines[2].time, const Duration(milliseconds: 3500));
    expect(lines[1].text, 'shared line');
    expect(activeLyricIndex(lines, const Duration(milliseconds: 3000)), 1);
    expect(
      activeLyricIndex(
        lines,
        const Duration(milliseconds: 3000),
        offset: const Duration(milliseconds: 1000),
      ),
      0,
    );
  });

  test('applies LRC offset without producing negative timestamps', () {
    final lines = parseLrc('[offset:3000]\n[00:02.00]line');

    expect(lines.single.time, Duration.zero);
  });

  test('LRC offset applies to all lines regardless of tag position', () {
    for (final source in [
      '[offset:500]\n[00:02.00]line',
      '[00:02.00]line\n[offset:500]',
    ]) {
      expect(parseLrc(source).single.time, const Duration(milliseconds: 1500));
    }
    expect(
      parseLrc('[00:02.00]line\n[offset:-500]').single.time,
      const Duration(milliseconds: 2500),
    );
  });

  test('accepts copied comment timestamps and YouTube time URLs', () {
    expect(parseLyricsTimestamp('00:11'), const Duration(seconds: 11));
    expect(
      parseLyricsTimestamp('00:11 lyric text'),
      const Duration(seconds: 11),
    );
    expect(
      parseLyricsTimestamp('1:02:03'),
      const Duration(hours: 1, minutes: 2, seconds: 3),
    );
    expect(
      parseLyricsTimestamp('https://youtu.be/example?t=11s'),
      const Duration(seconds: 11),
    );
    expect(
      parseLyricsTimestamp('https://www.youtube.com/watch?v=x&t=1m2s'),
      const Duration(minutes: 1, seconds: 2),
    );
  });

  test('parses hour timestamps in LRC files', () {
    expect(
      parseLrc('[1:02:03.50]line').single.time,
      const Duration(hours: 1, minutes: 2, seconds: 3, milliseconds: 500),
    );
  });

  test('persists a per-track lyric timing adjustment', () {
    final media = MediaItem(
      id: 'track-1',
      title: 'Track',
      localPath: '/music/track.mp3',
      lyricsOffsetMs: -1250,
    );

    final restored = MediaItem.fromJson(media.toJson());
    expect(restored.lyricsOffsetMs, -1250);
  });
}
