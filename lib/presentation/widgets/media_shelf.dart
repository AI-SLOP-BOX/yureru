import 'package:flutter/material.dart';
import '../../domain/models.dart';
import '../layout_metrics.dart';
import '../theme.dart';
import 'app_svg_icon.dart';
import 'duration_text.dart';
import 'thumb_image.dart';

/// A bounded preview of a collection; the caller owns its complete play order.
class MediaShelf extends StatelessWidget {
  const MediaShelf({
    super.key,
    required this.title,
    required this.items,
    required this.onPlay,
    this.onSeeAll,
    required this.seeAllLabel,
  });
  final String title;
  final List<MediaItem> items;
  final ValueChanged<MediaItem> onPlay;
  final VoidCallback? onSeeAll;
  final String seeAllLabel;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final visible = items.take(10).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final inset = LayoutMetrics.horizontalInset(context);
        final contentWidth = (constraints.maxWidth - inset * 2).clamp(
          0.0,
          double.infinity,
        );
        final gaps = 14.0 * (visible.length - 1);
        final cardWidth = ((contentWidth - gaps) / visible.length).clamp(
          152.0,
          264.0,
        );
        final height =
            (cardWidth - 14) * 9 / 16 +
            28 +
            MediaQuery.textScalerOf(context).scale(13.5) * 1.25 +
            MediaQuery.textScalerOf(context).scale(12) * 1.25;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 2, 24, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (onSeeAll != null)
                    TextButton.icon(
                      onPressed: onSeeAll,
                      label: Text(seeAllLabel),
                      icon: const AppSvgIcon('chevron_right', size: 16),
                    ),
                ],
              ),
            ),
            SizedBox(
              height: height,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(
                  horizontal: LayoutMetrics.horizontalInset(context),
                ),
                itemCount: visible.length,
                separatorBuilder: (_, _) => const SizedBox(width: 14),
                itemBuilder: (_, index) => _MediaShelfCard(
                  key: ValueKey(visible[index].id),
                  media: visible[index],
                  width: cardWidth,
                  onTap: () => onPlay(visible[index]),
                ),
              ),
            ),
            const SizedBox(height: 4),
          ],
        );
      },
    );
  }
}

class _MediaShelfCard extends StatefulWidget {
  final MediaItem media;
  final VoidCallback onTap;
  final double width;

  const _MediaShelfCard({
    super.key,
    required this.media,
    required this.onTap,
    required this.width,
  });

  @override
  State<_MediaShelfCard> createState() => _MediaShelfCardState();
}

class _MediaShelfCardState extends State<_MediaShelfCard> {
  bool _hover = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final m = widget.media;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardWidth = widget.width;
    final thumbnailWidth = cardWidth - 14;
    final compact = MediaQuery.sizeOf(context).width < 600;
    final showPlay = compact || _hover || _focused;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: widget.onTap,
        onFocusChange: (focused) => setState(() => _focused = focused),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          width: cardWidth,
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: (_hover || _focused)
                ? (isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.05))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedScale(
                duration: const Duration(milliseconds: 200),
                scale: _hover ? 1.03 : 1.0,
                curve: Curves.easeOutCubic,
                child: Container(
                  width: thumbnailWidth,
                  height: thumbnailWidth * 9 / 16,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: _hover ? 0.5 : 0.25,
                        ),
                        blurRadius: _hover ? 14 : 8,
                        offset: Offset(0, _hover ? 5 : 2),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      ThumbImage(
                        seed: m.id,
                        mediaId: m.id,
                        localPath: m.localPath,
                        radius: 10,
                        expand: true,
                      ),
                      // Hover Play Vignette
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 180),
                        opacity: _hover ? 0.35 : 0.0,
                        child: Container(color: Colors.black),
                      ),
                      // Touch users need a visible cue without hovering.
                      Align(
                        alignment: compact
                            ? Alignment.bottomRight
                            : Alignment.center,
                        child: Padding(
                          padding: compact
                              ? const EdgeInsets.all(6)
                              : EdgeInsets.zero,
                          child: AnimatedScale(
                            duration: const Duration(milliseconds: 200),
                            scale: showPlay ? 1.0 : 0.5,
                            curve: Curves.easeOutBack,
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 180),
                              opacity: showPlay ? 1.0 : 0.0,
                              child: Container(
                                width: compact ? 26 : 34,
                                height: compact ? 26 : 34,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.4,
                                      ),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: AppSvgIcon(
                                    'play',
                                    size: compact ? 18 : 22,
                                    color: Colors.black87,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                displayTitle(m.title),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                  color: isDark ? kTextPrimary : Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              if ((m.artist ?? '').trim().isNotEmpty)
                Text(
                  m.artist!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.25,
                    color: themeTextSub(context),
                  ),
                )
              else
                DurationText(
                  mediaId: m.id,
                  localPath: m.localPath,
                  durationMs: m.durationMs,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.25,
                    color: themeTextSub(context),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
