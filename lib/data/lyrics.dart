class LyricLine {
  const LyricLine({required this.time, required this.text});

  final Duration time;
  final String text;
}

/// Parses synchronized LRC timestamps, including multiple timestamps per line.
List<LyricLine> parseLrc(String source) {
  final lines = <LyricLine>[];
  final timestampPattern = RegExp(
    r'\[(?:(\d+):)?(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]',
  );
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
      final hours = int.tryParse(match.group(1) ?? '0') ?? 0;
      final minutes = int.tryParse(match.group(2)!) ?? 0;
      final seconds = int.tryParse(match.group(3)!) ?? 0;
      final fraction = match.group(4) ?? '';
      final millis = switch (fraction.length) {
        1 => (int.tryParse(fraction) ?? 0) * 100,
        2 => (int.tryParse(fraction) ?? 0) * 10,
        3 => int.tryParse(fraction) ?? 0,
        _ => 0,
      };
      final total =
          (hours * 3600 + minutes * 60 + seconds) * 1000 + millis - offsetMs;
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

/// Parses timestamps copied from video comments or a URL into a duration.
/// Supports `00:11`, `1:02:03`, fractional seconds, and YouTube `t=` URLs.
Duration? parseLyricsTimestamp(String input) {
  var value = input.trim();
  if (value.isEmpty) return null;

  final urlTime = RegExp(r'[?&](?:t|start)=([^&#\s]+)').firstMatch(value);
  if (urlTime != null) {
    value = urlTime.group(1)!;
    final plainSeconds = double.tryParse(value);
    if (plainSeconds != null) {
      return Duration(milliseconds: (plainSeconds * 1000).round());
    }
    final units = RegExp(
      r'^(?:(\d+)h)?(?:(\d+)m)?(?:(\d+(?:\.\d+)?)s)?$',
    ).firstMatch(value);
    if (units != null && units.group(0)!.isNotEmpty) {
      if (value.contains(RegExp(r'[hms]'))) {
        final totalSeconds =
            (int.tryParse(units.group(1) ?? '0') ?? 0) * 3600 +
            (int.tryParse(units.group(2) ?? '0') ?? 0) * 60 +
            (double.tryParse(units.group(3) ?? '0') ?? 0);
        return Duration(milliseconds: (totalSeconds * 1000).round());
      }
      final seconds = double.tryParse(value);
      if (seconds != null) {
        return Duration(milliseconds: (seconds * 1000).round());
      }
    }
  }

  value = value
      .replaceFirst(RegExp(r'^[\s\[\(>*_`]+'), '')
      .replaceFirst(RegExp(r'[\s\]\),*_`]+$'), '');
  final match = RegExp(
    r'^(\d+(?::\d+){0,2})(?:[.,](\d{1,3}))?',
  ).firstMatch(value);
  if (match == null) return null;
  final parts = match.group(1)!.split(':').map(int.tryParse).toList();
  if (parts.any((part) => part == null)) return null;
  final fraction = match.group(2) ?? '';
  final millis = switch (fraction.length) {
    1 => (int.parse(fraction) * 100),
    2 => (int.parse(fraction) * 10),
    3 => int.parse(fraction),
    _ => 0,
  };
  late final int totalSeconds;
  if (parts.length == 3) {
    if (parts[1]! > 59 || parts[2]! > 59) return null;
    totalSeconds = parts[0]! * 3600 + parts[1]! * 60 + parts[2]!;
  } else if (parts.length == 2) {
    if (parts[1]! > 59) return null;
    totalSeconds = parts[0]! * 60 + parts[1]!;
  } else {
    totalSeconds = parts.single!;
  }
  return Duration(milliseconds: totalSeconds * 1000 + millis);
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
