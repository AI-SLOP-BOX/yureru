import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_state.dart';
import '../../domain/creator_names.dart';
import '../../playback/playback_controller.dart';
import '../i18n.dart';
import '../theme.dart';
import 'duration_text.dart';
import 'frosted_panel.dart';
import 'thumb_image.dart';
import 'queue_lyrics_tabs.dart';
import 'lyrics_panel.dart';

/// Right panel: reorderable play queue (number, thumb, title, duration).
class QueuePanel extends ConsumerStatefulWidget {
  final double width;
  final VoidCallback? onClose;
  final VoidCallback? onToggleExpanded;
  final bool showCompactPreview;
  final Widget? compactPreview;
  final EdgeInsetsGeometry? margin;
  final bool ambient;
  const QueuePanel({
    super.key,
    this.width = 336,
    this.onClose,
    this.onToggleExpanded,
    this.showCompactPreview = false,
    this.compactPreview,
    this.margin,
    this.ambient = false,
  });

  @override
  ConsumerState<QueuePanel> createState() => _QueuePanelState();
}

class _QueuePanelState extends ConsumerState<QueuePanel> {
  static const double _queueRowExtent = 68;
  final ScrollController _scrollController = ScrollController();
  String? _lastCurrentId;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = ref.watch(queueProvider);
    final lib = ref.watch(libraryProvider);
    final engine = ref.watch(engineProvider);
    final displayIndices = List<int>.generate(q.queue.length, (index) => index);
    if (q.hasCurrent && q.currentId != _lastCurrentId) {
      _lastCurrentId = q.currentId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        final position = _scrollController.position;
        final target = (q.index * _queueRowExtent).clamp(
          0.0,
          position.maxScrollExtent,
        );
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      });
    }
    return SizedBox(
      width: widget.width,
      child: FrostedPanel(
        margin: widget.margin ?? const EdgeInsets.fromLTRB(0, 12, 12, 12),
        borderRadius: BorderRadius.circular(16),
        fillOpacity: widget.ambient ? 0.68 : null,
        borderOpacity: widget.ambient ? 0.025 : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.onToggleExpanded != null)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: widget.onToggleExpanded,
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
                              widget.showCompactPreview
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
                if (widget.showCompactPreview && q.currentId != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(7),
                          child:
                              widget.compactPreview ??
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
                                ? ref.tr('playing')
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
                          tooltip: ref.tr(
                            engine.snapshot.isPlaying ? 'pause' : 'play',
                          ),
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
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  child: Row(
                    children: [
                      QueueLyricsTabs(
                        showLyrics: ref.watch(lyricsPanelProvider),
                        onQueue: () {
                          ref.read(lyricsPanelProvider.notifier).state = false;
                          ref.read(queueVisibleProvider.notifier).state = true;
                        },
                        onLyrics: () {
                          ref.read(queueVisibleProvider.notifier).state = true;
                          ref.read(lyricsPanelProvider.notifier).state = true;
                        },
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
                      if (widget.onClose != null) ...[
                        const Spacer(),
                        IconButton(
                          icon: const Icon(
                            Icons.arrow_forward_rounded,
                            size: 20,
                          ),
                          tooltip: ref.tr('hide_queue'),
                          splashRadius: 18,
                          onPressed: widget.onClose,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            Expanded(
              child: ref.watch(lyricsPanelProvider)
                  ? (q.currentId != null && lib.byId(q.currentId!) != null
                        ? LyricsPanel(
                            key: ValueKey('lyrics-${q.currentId}'),
                            media: lib.byId(q.currentId!)!,
                            engine: engine,
                          )
                        : Center(
                            child: Text(
                              ref.tr('nothing_playing'),
                              style: TextStyle(color: themeTextSub(context)),
                            ),
                          ))
                  : q.queue.isEmpty
                  ? Center(
                      child: Text(
                        ref.tr('queue_empty'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: themeTextSub(context),
                          fontSize: 13,
                          height: 1.6,
                        ),
                      ),
                    )
                  : ReorderableListView.builder(
                      scrollController: _scrollController,
                      itemExtent: _queueRowExtent,
                      buildDefaultDragHandles: false,
                      padding: const EdgeInsets.fromLTRB(10, 4, 10, 12),
                      itemCount: displayIndices.length,
                      onReorder: (oldIndex, newIndex) {
                        if (newIndex > oldIndex) newIndex -= 1;
                        final fromQueueIndex = displayIndices[oldIndex];
                        final toQueueIndex = displayIndices[newIndex];
                        ref
                            .read(queueProvider.notifier)
                            .move(fromQueueIndex, toQueueIndex);
                      },
                      itemBuilder: (c, i) {
                        final queueIndex = displayIndices[i];
                        final id = q.queue[queueIndex];
                        final m = lib.byId(id);
                        final cur = queueIndex == q.index && q.hasCurrent;
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
                          key: ValueKey('queue-$id'),
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
                              ref
                                  .read(queueProvider.notifier)
                                  .jumpTo(queueIndex);
                              ref
                                  .read(playbackControllerProvider)
                                  .openCurrent();
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
                                              ? ref.tr('unknown_video')
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
                                    tooltip: ref.tr('remove_from_queue'),
                                    onPressed: () {
                                      final removesCurrent =
                                          ref.read(queueProvider).currentId ==
                                          id;
                                      ref
                                          .read(queueProvider.notifier)
                                          .removeAt(queueIndex);
                                      if (!removesCurrent) return;

                                      final next = ref.read(queueProvider);
                                      if (next.hasCurrent) {
                                        unawaited(
                                          ref
                                              .read(playbackControllerProvider)
                                              .openCurrent(),
                                        );
                                      } else {
                                        unawaited(
                                          ref.read(engineProvider).pause(),
                                        );
                                      }
                                    },
                                  ),
                                  const SizedBox(width: 2),
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
                                  ),
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
      ),
    );
  }
}
