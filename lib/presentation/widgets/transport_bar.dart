import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_state.dart';
import '../../domain/creator_names.dart';
import '../../playback/playback_controller.dart';
import '../i18n.dart';
import '../theme.dart';
import 'playback_options.dart';
import 'frosted_panel.dart';
import 'transport_icon.dart';
import 'thumb_image.dart';

const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

/// Bottom transport bar: now-playing info (tap opens player), centered
/// transport cluster, tools, and a full-width timeline below.
/// Single seekbar in the whole app (the player screen has none).
class TransportBar extends ConsumerStatefulWidget {
  final bool queueVisible;
  final VoidCallback onToggleQueue;
  final bool transportOnly;
  final bool ambient;
  const TransportBar({
    super.key,
    required this.queueVisible,
    required this.onToggleQueue,
    this.transportOnly = false,
    this.ambient = false,
  });

  @override
  ConsumerState<TransportBar> createState() => _TransportBarState();
}

class _TransportBarState extends ConsumerState<TransportBar> {
  bool _volumeHover = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 750;
        if (widget.transportOnly) {
          return FrostedPanel(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            fillOpacity: widget.ambient ? 0.68 : null,
            borderOpacity: widget.ambient ? 0.025 : null,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: _controls(ref),
                  ),
                ),
                const SizedBox(height: 4),
                const _TimelineBar(),
              ],
            ),
          );
        }
        return FrostedPanel(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
          fillOpacity: widget.ambient ? 0.68 : null,
          borderOpacity: widget.ambient ? 0.025 : null,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (compact) ...[
                Row(
                  children: [
                    Expanded(child: _nowPlaying(ref, true)),
                    _tools(ref, true),
                  ],
                ),
                const SizedBox(height: 2),
                Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: _controls(ref),
                  ),
                ),
              ] else
                // Volume & song info (left), transport (center), tools (right).
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Row(
                        children: [
                          Expanded(child: _nowPlaying(ref, false)),
                          const SizedBox(width: 8),
                          _volumeControls(false),
                        ],
                      ),
                    ),
                    Expanded(flex: 4, child: Center(child: _controls(ref))),
                    Expanded(
                      flex: 3,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: _tools(ref, false),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 6),
              // Row 2: Full-width scrub timeline with duration labels on both sides
              const _TimelineBar(),
            ],
          ),
        );
      },
    );
  }

  Widget _nowPlaying(WidgetRef ref, bool compact) {
    final q = ref.watch(queueProvider);
    final lib = ref.watch(libraryProvider);
    final media = q.currentId == null ? null : lib.byId(q.currentId!);
    if (media == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: themeCard(context),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: themeBorder(context)),
              ),
              child: Icon(
                Icons.music_note_rounded,
                size: 22,
                color: themeTextSub(context),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ref.tr('playing_no_track'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: kTextSub,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    ref.tr('select_video_to_play'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: kTextMuted,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    // Keep this line about the video's creator; playlist names here looked
    // like creator metadata when the video had no artist set.
    final subtitle = formatCreatorNames(media.artist);
    final engine = ref.watch(engineProvider);
    final isVideoPlaying = engine.snapshot.initialized;
    final mode = ref.watch(playerViewModeProvider);
    final showLiveVideo = isVideoPlaying && mode == PlayerViewMode.media;

    // Tap to open the playing screen.
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => showPlayerView(ref),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(
          children: [
            Tooltip(
              message: ref.tr('fullscreen_video_tip'),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    showLiveVideo
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
                    Positioned(
                      right: 2,
                      bottom: 2,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(
                          Icons.open_in_full_rounded,
                          size: 10,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
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
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: themeTextPrimary(context),
                    ),
                  ),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () =>
                          ref
                                  .read(creatorVideosRequestProvider.notifier)
                                  .state =
                              subtitle,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: themeTextSub(context),
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _controls(WidgetRef ref) {
    final q = ref.watch(queueProvider);
    final engine = ref.watch(engineProvider);
    final ctl = ref.read(playbackControllerProvider);
    final has = q.hasCurrent;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final desktop = MediaQuery.sizeOf(context).width >= 750;
    final primaryIconColor = isDark ? kTextPrimary : const Color(0xFF2B2B2B);
    final arrowIconColor = isDark
        ? const Color(0xFFA9A9A9)
        : const Color(0xFF5D5D5D);
    final playIconColor = isDark
        ? const Color(0xFF9F9F9F)
        : const Color(0xFF535353);
    final disabledIconColor = isDark
        ? kTextMuted.withValues(alpha: 0.55)
        : Colors.black26;
    // Keep the desktop play-to-skip glyph ratio on compact layouts as well.
    final previousNextIconSize = 30.0;
    final playPauseIconSize = desktop ? 42.0 : previousNextIconSize * 42 / 30;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PlaybackShuffleButton(
          activeColor: primaryIconColor,
          inactiveColor: disabledIconColor,
        ),
        const SizedBox(width: 4),
        IconButton(
          tooltip: ref.tr('prev_video'),
          icon: TransportIcon.previous(
            size: previousNextIconSize,
            color: has ? arrowIconColor : disabledIconColor,
          ),
          color: has ? arrowIconColor : disabledIconColor,
          onPressed: q.hasCurrent ? () => ctl.playPrev() : null,
        ),
        const SizedBox(width: 8),
        // Large transport glyph; desktop keeps only the play/pause shape.
        StreamBuilder<bool>(
          stream: engine.playingStream,
          initialData: engine.snapshot.isPlaying,
          builder: (context, playingSnap) {
            final isPlaying = playingSnap.data ?? false;
            return Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              elevation: 0,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: has ? () => ctl.toggle() : null,
                child: Padding(
                  padding: EdgeInsets.all(desktop ? 12 : 9),
                  child: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: has ? playIconColor : disabledIconColor,
                    size: playPauseIconSize,
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: ref.tr('next_video'),
          icon: TransportIcon.next(
            size: previousNextIconSize,
            color: has ? arrowIconColor : disabledIconColor,
          ),
          color: has ? arrowIconColor : disabledIconColor,
          onPressed: has ? () => ctl.playNext() : null,
        ),
        PlaybackRepeatButton(
          activeColor: primaryIconColor,
          inactiveColor: disabledIconColor,
        ),
      ],
    );
  }

  Widget _volumeControls(bool compact) {
    final volume = ref.watch(volumeProvider);
    final playback = ref.read(playbackControllerProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          final delta = -event.scrollDelta.dy / 1000.0;
          final next = (volume + delta).clamp(0.0, 1.0).toDouble();
          unawaited(playback.setVolume(next));
        }
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: ref.tr(volume == 0 ? 'unmute' : 'mute'),
            icon: Icon(
              volume == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              size: 20,
            ),
            color: isDark ? kTextPrimary : const Color(0xFF575757),
            onPressed: () async {
              await playback.toggleMute();
            },
          ),
          if (!compact)
            MouseRegion(
              onEnter: (_) => setState(() => _volumeHover = true),
              onExit: (_) => setState(() => _volumeHover = false),
              child: SizedBox(
                width: 84,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: _volumeHover ? 4.0 : 3.0,
                    thumbShape: RoundSliderThumbShape(
                      enabledThumbRadius: _volumeHover ? 6.5 : 5.0,
                      elevation: 2,
                    ),
                    activeTrackColor: isDark
                        ? kTextPrimary
                        : const Color(0xFF2B2B2B),
                    inactiveTrackColor: isDark
                        ? kTextMuted.withValues(alpha: 0.4)
                        : Colors.black12,
                    thumbColor: isDark ? kTextPrimary : const Color(0xFF2B2B2B),
                  ),
                  child: Slider(
                    value: volume.clamp(0.0, 1.0),
                    onChanged: (v) => unawaited(playback.setVolume(v)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tools(WidgetRef ref, bool compact) {
    final q = ref.watch(queueProvider);
    final ctl = ref.read(playbackControllerProvider);
    final has = q.hasCurrent;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Speed selection popup menu (Apple-style with checkmarks)
        PopupMenuButton<double>(
          tooltip: ref.tr('playback_speed'),
          enabled: has,
          initialValue: q.speed,
          onSelected: (speed) async {
            await ctl.setSpeed(speed);
          },
          color: isDark ? const Color(0xF2262626) : const Color(0xF2FFFFFF),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: isDark
                  ? kGlassBorder.withValues(alpha: 0.8)
                  : Colors.black.withValues(alpha: 0.08),
            ),
          ),
          elevation: 8,
          itemBuilder: (ctx) {
            final reverseSpeeds = speeds.reversed.toList();
            return [
              for (final s in reverseSpeeds)
                PopupMenuItem<double>(
                  value: s,
                  height: 42,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: q.speed == s
                        ? BoxDecoration(
                            color: kAccent,
                            borderRadius: BorderRadius.circular(9),
                          )
                        : null,
                    child: Row(
                      children: [
                        if (q.speed == s) ...[
                          Icon(
                            Icons.check_rounded,
                            color: isDark ? kBg : Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                        ] else ...[
                          const SizedBox(width: 26),
                        ],
                        Text(
                          '${s == s.toInt() ? s.toInt() : s}×',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: q.speed == s
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: q.speed == s
                                ? kTextPrimary
                                : (isDark ? kTextPrimary : Colors.black87),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ];
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: has ? themeCard(context) : Colors.transparent,
              border: Border.all(
                color: has ? themeBorder(context) : Colors.white12,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.speed_rounded,
                  size: 14,
                  color: !has
                      ? kTextMuted
                      : (q.speed == 1.0 ? kTextSub : kAccent),
                ),
                const SizedBox(width: 4),
                Text(
                  '${q.speed}x',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: !has
                        ? kTextMuted
                        : (q.speed == 1.0 ? kTextSub : kAccent),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Isolated timeline seekbar & duration display.
/// Subscribes directly to `engine.snapshots` so that high-frequency playback position
/// updates ONLY re-render this row and never trigger re-renders of thumbnails,
/// now-playing metadata, or controls.
class _TimelineBar extends ConsumerStatefulWidget {
  const _TimelineBar();

  @override
  ConsumerState<_TimelineBar> createState() => _TimelineBarState();
}

class _TimelineBarState extends ConsumerState<_TimelineBar> {
  bool _isDragging = false;
  double _draggedMs = 0.0;
  bool _hover = false;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    final engine = ref.read(engineProvider);
    _sub = engine.snapshots.listen((_) {
      if (mounted) setState(() {});
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final engine = ref.watch(engineProvider);
    final ctl = ref.read(playbackControllerProvider);
    final has = ref.watch(queueProvider.select((q) => q.hasCurrent));
    final snap = engine.snapshot;
    final enginePos = snap.position;
    final dur = snap.duration;
    final displayPos = _isDragging
        ? Duration(milliseconds: _draggedMs.toInt())
        : enginePos;

    final isInteracting = _hover || _isDragging;

    // Dynamically calculate width based on total duration so 1h+ content is stable without runtime jitter
    final double timeLabelWidth = dur.inHours > 0 ? 58.0 : 44.0;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final desktop = MediaQuery.sizeOf(context).width >= 750;
    final timeColor = isDark ? kTextSub : const Color(0xFF434343);
    final primaryIconColor = isDark ? kTextPrimary : const Color(0xFF2B2B2B);
    final activeSeekColor = desktop
        ? const Color(0xFFA1A1A1)
        : primaryIconColor;
    final inactiveSeekColor = desktop
        ? const Color(0xFF676767)
        : (isDark ? kTextMuted.withValues(alpha: 0.4) : Colors.black12);
    final seekThumbColor = desktop ? kAccentLight : primaryIconColor;

    return Row(
      children: [
        SizedBox(
          width: timeLabelWidth,
          child: Text(
            fmtDuration(displayPos),
            style: TextStyle(
              fontSize: 12,
              color: timeColor,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        Expanded(
          child: MouseRegion(
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: isInteracting ? 5 : 3.5,
                thumbShape: RoundSliderThumbShape(
                  enabledThumbRadius: isInteracting ? 7 : 5,
                  elevation: 3,
                ),
                activeTrackColor: activeSeekColor,
                inactiveTrackColor: inactiveSeekColor,
                thumbColor: seekThumbColor,
                overlayColor: activeSeekColor.withValues(alpha: 0.15),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              ),
              child: Focus(
                // This seekbar stays mounted while browsing. If arrow-key
                // focus reaches it at a list's scroll boundary, Slider's
                // built-in actions would unexpectedly seek. Keep seeking
                // pointer-driven so navigation arrows never change time.
                onKeyEvent: (node, event) =>
                    {
                      LogicalKeyboardKey.arrowLeft,
                      LogicalKeyboardKey.arrowRight,
                      LogicalKeyboardKey.arrowUp,
                      LogicalKeyboardKey.arrowDown,
                    }.contains(event.logicalKey)
                    ? KeyEventResult.handled
                    : KeyEventResult.ignored,
                child: Slider(
                  value: dur.inMilliseconds == 0
                      ? 0
                      : displayPos.inMilliseconds
                            .clamp(0, dur.inMilliseconds)
                            .toDouble(),
                  max: (dur.inMilliseconds <= 0 ? 1 : dur.inMilliseconds)
                      .toDouble(),
                  onChangeStart: has
                      ? (v) {
                          setState(() {
                            _isDragging = true;
                            _draggedMs = v;
                          });
                        }
                      : null,
                  onChanged: has
                      ? (v) {
                          setState(() {
                            _draggedMs = v;
                          });
                        }
                      : null,
                  onChangeEnd: has
                      ? (v) async {
                          _draggedMs = v;
                          await ctl.seekTo(Duration(milliseconds: v.toInt()));
                          if (mounted) {
                            setState(() {
                              _isDragging = false;
                            });
                          }
                        }
                      : null,
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          width: timeLabelWidth,
          child: Text(
            fmtDuration(dur),
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 12,
              color: timeColor,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}
