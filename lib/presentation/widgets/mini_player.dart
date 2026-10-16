import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_state.dart';
import '../../domain/creator_names.dart';
import '../../playback/playback_controller.dart';
import '../theme.dart';
import 'thumb_image.dart';

/// Compact now-playing strip (used by the narrow fallback layout).
/// Tap (except the buttons) expands to the full-size player.
class MiniPlayer extends ConsumerWidget {
  final VoidCallback? onExpand;
  const MiniPlayer({super.key, this.onExpand});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = ref.watch(queueProvider);
    final lib = ref.watch(libraryProvider);
    if (!q.hasCurrent) return const SizedBox.shrink();
    final media = lib.byId(q.currentId!);
    if (media == null) return const SizedBox.shrink();
    final engine = ref.watch(engineProvider);
    final ctl = ref.read(playbackControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isVideoPlaying = engine.snapshot.initialized;

    return Container(
      decoration: BoxDecoration(
        color: themePanelSolid(context),
        border: Border(
          top: BorderSide(
            color: isDark
                ? const Color(0x1FFFFFFF)
                : Colors.black.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: onExpand,
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 58,
                      height: 34,
                      child: isVideoPlaying
                          ? FittedBox(
                              fit: BoxFit.cover,
                              clipBehavior: Clip.antiAlias,
                              child: SizedBox(
                                width: 160,
                                height: 90,
                                child: engine.buildVideoView(),
                              ),
                            )
                          : ThumbImage(
                              seed: media.id,
                              mediaId: media.id,
                              localPath: media.localPath,
                              size: 34,
                              radius: 0,
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayTitle(media.title),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: themeTextPrimary(context),
                          ),
                        ),
                        if (media.artist != null &&
                            media.artist!.trim().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            formatCreatorNames(media.artist),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: kTextSub,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: '再生画面に戻る',
            icon: const Icon(Icons.open_in_full_rounded),
            onPressed: onExpand,
          ),
          IconButton(
            tooltip: engine.snapshot.isPlaying ? '一時停止' : '再生',
            icon: Icon(
              engine.snapshot.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
            ),
            onPressed: () async {
              await ctl.toggle();
            },
          ),
        ],
      ),
    );
  }
}
