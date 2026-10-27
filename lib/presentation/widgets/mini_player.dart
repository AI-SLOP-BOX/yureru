import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_state.dart';
import '../../domain/creator_names.dart';
import '../../playback/playback_controller.dart';
import '../i18n.dart';
import '../theme.dart';
import 'thumb_image.dart';
import 'frosted_panel.dart';

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
    final showLiveVideo =
        engine.snapshot.initialized &&
        ref.watch(playerViewModeProvider) == PlayerViewMode.media;

    return FrostedPanel(
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
                    child: SizedBox.square(
                      dimension: 48,
                      child: showLiveVideo
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
                              size: 48,
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
                            style: TextStyle(
                              fontSize: 11.5,
                              color: themeTextSub(context),
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
            tooltip: ref.tr('return_to_player'),
            icon: const Icon(Icons.open_in_full_rounded),
            onPressed: onExpand,
          ),
          IconButton(
            tooltip: ref.tr(engine.snapshot.isPlaying ? 'pause' : 'play'),
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
