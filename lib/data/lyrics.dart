class LyricLine {
  const LyricLine({required this.time, required this.text});

  final Duration time;
  final String text;
}

/// Parses synchronized LRC timestamps, including multiple timestamps per line.
List<LyricLine> parseLrc(String source) {
  final lines = <LyricLine>[];
  final timestampPattern = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');
  // An LRC offset is file-wide and may appear after the timed lines.
  final offsets = RegExp(
    r'^\s*\[offset:([+-]?\d+)\]\s*$',
    caseSensitive: false,
    multiLine: true,
  ).allMatches(source);
  final offsetMs = offsets.isEmpty
      ? 0
      : int.tryParse(offsets.last.group(1)!) ?? 0;

  for (final rawLine in source.split(RegExp(r'\r?\n'))) {
    final offsetMatch = RegExp(
      r'^\[offset:([+-]?\d+)\]$',
      caseSensitive: false,
    ).firstMatch(rawLine.trim());
    if (offsetMatch != null) {
      continue;
    }

    final matches = timestampPattern.allMatches(rawLine).toList();
    if (matches.isEmpty) continue;
    final text = rawLine.substring(matches.last.end).trim();
    for (final match in matches) {
      final minutes = int.tryParse(match.group(1)!) ?? 0;
      final seconds = int.tryParse(match.group(2)!) ?? 0;
      final fraction = match.group(3) ?? '';
      final millis = switch (fraction.length) {
        1 => (int.tryParse(fraction) ?? 0) * 100,
        2 => (int.tryParse(fraction) ?? 0) * 10,
        3 => int.tryParse(fraction) ?? 0,
        _ => 0,
      };
      final total = (minutes * 60 + seconds) * 1000 + millis - offsetMs;
      lines.add(
        LyricLine(
          time: Duration(milliseconds: total.clamp(0, 1 << 60)),
          text: text,
        ),
      );
    }
  }
  lines.sort((a, b) => a.time.compareTo(b.time));
  return lines;
}

int activeLyricIndex(
  List<LyricLine> lines,
  Duration position, {
  Duration offset = Duration.zero,
}) {
  final lyricPosition = position - offset;
  var active = -1;
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].time > lyricPosition) break;
    active = i;
  }
  return active;
}
