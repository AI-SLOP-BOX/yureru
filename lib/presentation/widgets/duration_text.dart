import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_state.dart';
import '../../data/thumbnails.dart';
import '../theme.dart';

/// Duration label: stored value first, else metadata probe, else '—'.
/// Resolved probes are written back to the library so they persist.
class DurationText extends ConsumerWidget {
  final String mediaId;
  final String localPath;
  final int? durationMs;
  final TextStyle style;
  const DurationText({
    super.key,
    required this.mediaId,
    required this.localPath,
    this.durationMs,
    this.style = const TextStyle(fontSize: 12, color: kTextSub),
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (durationMs != null) {
      return Text(fmtDuration(Duration(milliseconds: durationMs!)),
          style: style);
    }
    return FutureBuilder<int?>(
      future: DurationService.forMedia(mediaId: mediaId, localPath: localPath),
      builder: (c, s) {
        final ms = s.data;
        if (ms == null) {
          return Text(s.connectionState == ConnectionState.done ? '—' : '…',
              style: style);
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(libraryProvider.notifier).setDurationMs(mediaId, ms);
        });
        return Text(fmtDuration(Duration(milliseconds: ms)), style: style);
      },
    );
  }
}
