import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_state.dart';
import '../../domain/creator_names.dart';
import '../../playback/playback_controller.dart';
import '../theme.dart';
import 'duration_text.dart';
import 'thumb_image.dart';

List<int> _queueDisplayIndices(QueueState queue) {
  if (!queue.hasCurrent) {
    return List<int>.generate(queue.queue.length, (index) => index);
  }
  return [
    queue.index,
    for (var i = queue.index - 1; i >= 0; i--) i,
    for (var i = queue.index + 1; i < queue.queue.length; i++) i,
  ];
}

/// Right panel: reorderable play queue (number, thumb, title, duration).
class QueuePanel extends ConsumerWidget {
  final double width;
  final VoidCallback? onClose;
  final VoidCallback? onToggleExpanded;
  final bool showCompactPreview;
  final Widget? compactPreview;
  final EdgeInsetsGeometry? margin;
  const QueuePanel({
    super.key,
    this.width = 336,
    this.onClose,
    this.onToggleExpanded,
    this.showCompactPreview = false,
    this.compactPreview,
    this.margin,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = ref.watch(queueProvider);
    final lib = ref.watch(libraryProvider);
    final engine = ref.watch(engineProvider);
    final displayIndices = _queueDisplayIndices(q);
    return Container(
      width: width,
      margin: margin ?? const EdgeInsets.fromLTRB(0, 12, 12, 12),
      decoration: BoxDecoration(
        color: themePanelSolid(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: themeBorder(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onToggleExpanded != null)
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onToggleExpanded,
                  child: SizedBox(
                    height: 26,
                    width: double.infinity,
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 38,
                            height: 4,
                            decoration: BoxDecoration(
                              color: themeTextSub(
                                context,
                              ).withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            showCompactPreview
                                ? Icons.keyboard_arrow_down_rounded
                                : Icons.keyboard_arrow_up_rounded,
                            size: 18,
                            color: themeTextSub(context),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (showCompactPreview && q.currentId != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child:
                            compactPreview ??
                            ThumbImage(
                              seed: q.currentId!,
                              mediaId: lib.byId(q.currentId!)?.id,
                              localPath: lib.byId(q.currentId!)?.localPath,
                              size: 64,
                              radius: 7,
                            ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          lib.byId(q.currentId!) == null
                              ? '再生中'
                              : displayTitle(lib.byId(q.currentId!)!.title),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: themeTextPrimary(context),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: engine.snapshot.isPlaying ? '一時停止' : '再生',
                        onPressed: () =>
                            ref.read(playbackControllerProvider).toggle(),
                        icon: Icon(
                          engine.snapshot.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                        ),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
                child: Row(
                  children: [
                    Text(
                      '再生キュー',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: themeTextPrimary(context),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: themeCard(context),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${q.queue.length}',
                        style: TextStyle(
                          fontSize: 12,
                          color: themeTextSub(context),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (onClose != null) ...[
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                        tooltip: 'キューを閉じる (→)',
                        splashRadius: 18,
                        onPressed: onClose,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          Expanded(
            child: q.queue.isEmpty
                ? Center(
                    child: Text(
                      'キューは空です\nプレイリストや動画一覧から再生してください',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: themeTextSub(context),
                        fontSize: 13,
                        height: 1.6,
                      ),
                    ),
                  )
                : ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    padding: const EdgeInsets.fromLTRB(10, 4, 10, 12),
                    itemCount: displayIndices.length,
                    onReorder: (oldIndex, newIndex) {
                      final firstUpcomingIndex = q.hasCurrent ? q.index + 1 : 0;
                      // Keep the current and played entries in the history
                      // section; only reorder entries that are still ahead.
                      if (oldIndex < firstUpcomingIndex ||
                          newIndex < firstUpcomingIndex) {
                        return;
                      }
                      if (newIndex > oldIndex) newIndex -= 1;
                      ref.read(queueProvider.notifier).move(oldIndex, newIndex);
                    },
                    itemBuilder: (c, i) {
                      final queueIndex = displayIndices[i];
                      final id = q.queue[queueIndex];
                      final m = lib.byId(id);
                      final cur = queueIndex == q.index && q.hasCurrent;
                      final played = q.hasCurrent && queueIndex < q.index;
                      final knownDur =
                          cur && engine.snapshot.duration > Duration.zero
                          ? engine.snapshot.duration
                          : (m?.durationMs != null
                                ? Duration(milliseconds: m!.durationMs!)
                                : null);
                      final isDark =
                          Theme.of(context).brightness == Brightness.dark;
                      final textPrimary = themeTextPrimary(context);
                      final textSub = themeTextSub(context);
                      return Container(
                        key: ValueKey('queue-${id}_$queueIndex'),
                        margin: const EdgeInsets.only(bottom: 3),
                        decoration: BoxDecoration(
                          color: cur
                              ? (isDark
                                    ? kAccent.withValues(alpha: 0.18)
                                    : kAccent.withValues(alpha: 0.10))
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: cur
                                ? (isDark
                                      ? kAccent.withValues(alpha: 0.4)
                                      : kAccent.withValues(alpha: 0.25))
                                : Colors.transparent,
                          ),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          hoverColor: isDark
                              ? Colors.white.withValues(alpha: 0.05)
                              : Colors.black.withValues(alpha: 0.04),
                          onTap: () {
                            showPlayerView(ref);
                            ref.read(queueProvider.notifier).jumpTo(queueIndex);
                            ref.read(playbackControllerProvider).openCurrent();
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 7,
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 22,
                                  child: cur
                                      ? Icon(
                                          Icons.equalizer_rounded,
                                          size: 16,
                                          color: isDark
                                              ? kAccentLight
                                              : kAccent,
                                        )
                                      : played
                                      ? Icon(
                                          Icons.check_rounded,
                                          size: 16,
                                          color: textSub,
                                        )
                                      : Text(
                                          '${queueIndex + 1}',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w500,
                                            color: textSub,
                                          ),
                                        ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(6),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: 0.3,
                                        ),
                                        blurRadius: 4,
                                        offset: const Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                  clipBehavior: Clip.antiAlias,
                                  child: ThumbImage(
                                    seed: id,
                                    mediaId: m?.id,
                                    localPath: m?.localPath,
                                    size: 40,
                                    radius: 6,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        m == null
                                            ? '不明な動画'
                                            : displayTitle(m.title),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: cur
                                              ? FontWeight.w600
                                              : FontWeight.w400,
                                          color: cur
                                              ? (isDark
                                                    ? Colors.white
                                                    : kAccent)
                                              : textPrimary,
                                        ),
                                      ),
                                      m?.artist?.trim().isNotEmpty == true
                                          ? Text(
                                              formatCreatorNames(m!.artist),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                color: textSub,
                                              ),
                                            )
                                          : knownDur != null
                                          ? Text(
                                              fmtDuration(knownDur),
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                color: textSub,
                                              ),
                                            )
                                          : (m == null
                                                ? Text(
                                                    '—',
                                                    style: TextStyle(
                                                      fontSize: 11.5,
                                                      color: textSub,
                                                    ),
                                                  )
                                                : DurationText(
                                                    mediaId: m.id,
                                                    localPath: m.localPath,
                                                    style: TextStyle(
                                                      fontSize: 11.5,
                                                      color: textSub,
                                                    ),
                                                  )),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 16,
                                  ),
                                  color: textSub,
                                  splashRadius: 14,
                                  visualDensity: VisualDensity.compact,
                                  tooltip: 'キューから削除',
                                  onPressed: () {
                                    ref
                                        .read(queueProvider.notifier)
                                        .removeAt(queueIndex);
                                  },
                                ),
                                const SizedBox(width: 2),
                                if (!q.hasCurrent || i > q.index)
                                  ReorderableDragStartListener(
                                    index: i,
                                    child: MouseRegion(
                                      cursor: SystemMouseCursors.grab,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 4,
                                          vertical: 8,
                                        ),
                                        child: Icon(
                                          Icons.drag_indicator_rounded,
                                          size: 18,
                                          color: textSub.withValues(alpha: 0.6),
                                        ),
                                      ),
                                    ),
                                  )
                                else
                                  const SizedBox(width: 26),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
