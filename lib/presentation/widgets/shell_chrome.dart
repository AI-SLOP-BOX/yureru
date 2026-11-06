import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../app_state.dart';
import '../../platform/window_utils.dart';
import '../../playback/playback_controller.dart';
import '../i18n.dart';
import '../theme.dart';
import 'frosted_panel.dart';
import 'player_card.dart';
import 'pip_video_surface.dart';
import 'thumb_image.dart';

class ShellCompactDrawerItem extends StatelessWidget {
  const ShellCompactDrawerItem({
    super.key,
    this.icon,
    this.leading,
    required this.label,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });
  final IconData? icon;
  final Widget? leading;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = selected
        ? (isDark ? kAccentLight : Colors.black87)
        : (isDark ? kTextSub : Colors.black54);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: compact ? 1 : 3),
      child: Material(
        color: selected
            ? (isDark
                  ? kAccent.withValues(alpha: 0.13)
                  : Colors.black.withValues(alpha: 0.07))
            : Colors.transparent,
        borderRadius: BorderRadius.circular(13),
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: onTap,
          child: SizedBox(
            height: compact ? 42 : 48,
            child: Row(
              children: [
                const SizedBox(width: 15),
                leading ?? Icon(icon, size: 21, color: color),
                const SizedBox(width: 14),
                Text(
                  label,
                  style: TextStyle(
                    color: selected
                        ? (isDark ? kTextPrimary : Colors.black87)
                        : color,
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ShellCompactNavigationBar extends StatelessWidget {
  const ShellCompactNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.labels,
    required this.onSelected,
  });
  final int selectedIndex;
  final List<String> labels;
  final ValueChanged<int> onSelected;
  static const _icons = [
    Icons.home_rounded,
    Icons.playlist_play_rounded,
    Icons.library_music_rounded,
    Icons.settings_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FrostedPanel(
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            children: [
              for (var i = 0; i < _icons.length; i++)
                Expanded(
                  child: _CompactNavItem(
                    icon: _icons[i],
                    label: labels[i],
                    selected: i == selectedIndex,
                    isDark: isDark,
                    onTap: () => onSelected(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactNavItem extends StatelessWidget {
  const _CompactNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = Theme.of(context).colorScheme.primary;
    final idle = themeTextSub(context);
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 21, color: selected ? active : idle),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? active : idle,
              fontSize: 10,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class ShellCinemaFadeIn extends StatelessWidget {
  const ShellCinemaFadeIn({super.key});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOut,
      builder: (context, opacity, child) => Opacity(
        opacity: opacity,
        child: IgnorePointer(ignoring: opacity < 0.85, child: child),
      ),
      child: const ColoredBox(color: Colors.black, child: PlayerCard()),
    );
  }
}

class ShellPictureInPictureView extends ConsumerStatefulWidget {
  const ShellPictureInPictureView({super.key});

  @override
  ConsumerState<ShellPictureInPictureView> createState() =>
      ShellPictureInPictureViewState();
}

class ShellPictureInPictureViewState
    extends ConsumerState<ShellPictureInPictureView>
    with WindowListener {
  Timer? _aspectCorrectionTimer;
  double? _videoAspectRatio;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    _aspectCorrectionTimer?.cancel();
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowResized() {
    if (ref.read(nativeSystemPictureInPictureProvider)) return;
    if (defaultTargetPlatform != TargetPlatform.macOS &&
        defaultTargetPlatform != TargetPlatform.windows) {
      return;
    }
    _schedulePictureInPictureAspectCorrection();
  }

  @override
  void onWindowResize() {
    if (ref.read(nativeSystemPictureInPictureProvider)) return;
    if (defaultTargetPlatform != TargetPlatform.linux) return;
    _schedulePictureInPictureAspectCorrection();
  }

  void _schedulePictureInPictureAspectCorrection() {
    _aspectCorrectionTimer?.cancel();
    _aspectCorrectionTimer = Timer(
      const Duration(milliseconds: 120),
      _correctPictureInPictureAspectRatio,
    );
  }

  Future<void> _correctPictureInPictureAspectRatio() async {
    if (ref.read(nativeSystemPictureInPictureProvider)) return;
    final aspectRatio = _videoAspectRatio;
    if (!mounted || aspectRatio == null || aspectRatio <= 0) return;
    try {
      final size = await windowManager.getSize();
      final titleBarHeight = await windowManager.getTitleBarHeight();
      final contentHeight = size.height - titleBarHeight;
      if (size.width <= 0 || contentHeight <= 0) return;
      final currentAspectRatio = size.width / contentHeight;
      final relativeDifference =
          (currentAspectRatio - aspectRatio).abs() / aspectRatio;
      if (relativeDifference < 0.08) return;

      final correctedSize = aspectRatio >= 1
          ? Size(size.width, size.width / aspectRatio + titleBarHeight)
          : Size(contentHeight * aspectRatio, size.height);
      await windowManager.setSize(correctedSize, animate: false);
    } catch (_) {
      // Keep PiP usable if the native window size cannot be read.
    }
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final engine = ref.watch(engineProvider);
    final queue = ref.watch(queueProvider);
    final media = ref.watch(libraryProvider).byId(queue.currentId ?? '');
    final reportedAspectRatio = engine.videoAspectRatio;
    final videoAspectRatio =
        reportedAspectRatio != null &&
            reportedAspectRatio.isFinite &&
            reportedAspectRatio > 0
        ? reportedAspectRatio
        : 16 / 9;
    _videoAspectRatio = videoAspectRatio;
    final showArtwork =
        ref.watch(playerViewModeProvider) == PlayerViewMode.image;
    if (ref.watch(nativeSystemPictureInPictureProvider)) {
      return ColoredBox(
        color: Colors.black,
        child: showArtwork && media != null
            ? Center(
                child: AspectRatio(
                  aspectRatio: 1,
                  child: ThumbImage(
                    seed: media.id,
                    mediaId: media.id,
                    localPath: media.localPath,
                    forceArtwork: true,
                    highRes: true,
                    expand: true,
                  ),
                ),
              )
            : Center(
                child: AspectRatio(
                  aspectRatio: videoAspectRatio,
                  child: PipVideoSurface(engine: engine),
                ),
              ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        // The compact macOS window has no title bar, and the Flutter video
        // surface consumes pointer events before AppKit's background-drag
        // handling can move the window. Start a native window drag when the
        // user drags anywhere on the PiP surface; taps still reach controls.
        behavior: HitTestBehavior.opaque,
        onPanStart: defaultTargetPlatform == TargetPlatform.macOS
            ? null
            : (_) => windowManager.startDragging(),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (showArtwork && media != null)
                Center(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: ThumbImage(
                      seed: media.id,
                      mediaId: media.id,
                      localPath: media.localPath,
                      forceArtwork: true,
                      highRes: true,
                      expand: true,
                    ),
                  ),
                )
              else
                Center(
                  child: AspectRatio(
                    aspectRatio: videoAspectRatio,
                    child: PipVideoSurface(engine: engine),
                  ),
                ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  height: 58,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Color(0xCC000000)],
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 200;
                      final buttonWidth = compact ? 32.0 : 44.0;
                      return Row(
                        children: [
                          Expanded(
                            child: Text(
                              media?.title ?? ref.tr('playing'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: compact ? 10 : 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          StreamBuilder<bool>(
                            stream: engine.playingStream,
                            initialData: engine.snapshot.isPlaying,
                            builder: (context, state) {
                              final playing = state.data ?? false;
                              return IconButton(
                                tooltip: ref.tr(playing ? 'pause' : 'play'),
                                color: Colors.white,
                                constraints: BoxConstraints.tightFor(
                                  width: buttonWidth,
                                  height: 44,
                                ),
                                padding: EdgeInsets.zero,
                                // Use the state shown by this StreamBuilder.
                                // PlaybackController.toggle() reads its cached
                                // snapshot, which can lag behind the platform
                                // stream during the PiP surface transition and
                                // issue pause again when the button shows Play.
                                onPressed: () =>
                                    playing ? engine.pause() : engine.play(),
                                icon: Icon(
                                  playing
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                ),
                              );
                            },
                          ),
                          IconButton(
                            tooltip: ref.tr('next_video'),
                            color: Colors.white,
                            constraints: BoxConstraints.tightFor(
                              width: buttonWidth,
                              height: 44,
                            ),
                            padding: EdgeInsets.zero,
                            onPressed: queue.hasCurrent
                                ? () => ref
                                      .read(playbackControllerProvider)
                                      .playNext()
                                : null,
                            icon: const Icon(Icons.skip_next_rounded),
                          ),
                          IconButton(
                            tooltip: ref.tr('restore_window'),
                            color: Colors.white,
                            constraints: BoxConstraints.tightFor(
                              width: buttonWidth,
                              height: 44,
                            ),
                            padding: EdgeInsets.zero,
                            onPressed: () async {
                              if (ref.read(
                                nativeSystemPictureInPictureProvider,
                              )) {
                                await const MethodChannel(
                                  'yureru/native_pip',
                                ).invokeMethod<void>('stop');
                                return;
                              }
                              ref
                                      .read(pictureInPictureProvider.notifier)
                                      .state =
                                  false;
                              await WidgetsBinding.instance.endOfFrame;
                              await restorePictureInPictureWindow(
                                engine: engine,
                              );
                            },
                            icon: const Icon(Icons.open_in_full_rounded),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              Positioned(
                right: 0,
                top: 0,
                child: IgnorePointer(
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: const BoxDecoration(
                      color: Color(0x66000000),
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(8),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.drag_handle_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: defaultTargetPlatform == TargetPlatform.macOS
                    ? const SizedBox.expand()
                    : DragToResizeArea(
                        resizeEdgeSize: 12,
                        enableResizeEdges: const [
                          ResizeEdge.top,
                          ResizeEdge.left,
                          ResizeEdge.right,
                          ResizeEdge.bottom,
                          ResizeEdge.topLeft,
                          ResizeEdge.topRight,
                          ResizeEdge.bottomLeft,
                          ResizeEdge.bottomRight,
                        ],
                        child: const SizedBox.expand(),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontal drag divider between resizable panes. Dragging resizes the
/// neighbor panels; the center video flexes with whatever is left.
class ShellHorizontalSplitter extends StatefulWidget {
  final ValueChanged<double> onDelta;
  final String tooltip;
  final bool ambient;
  const ShellHorizontalSplitter({
    super.key,
    required this.onDelta,
    required this.tooltip,
    this.ambient = false,
  });

  @override
  State<ShellHorizontalSplitter> createState() =>
      ShellHorizontalSplitterState();
}

class ShellHorizontalSplitterState extends State<ShellHorizontalSplitter> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => widget.onDelta(d.delta.dx),
        child: Tooltip(
          message: widget.tooltip,
          child: Container(
            width: 8,
            color: Colors.transparent,
            alignment: Alignment.center,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: _hover ? 2 : (widget.ambient ? 0 : 1),
              decoration: BoxDecoration(
                color: _hover
                    ? kAccentLight
                    : Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(1),
                boxShadow: _hover
                    ? [
                        BoxShadow(
                          color: kAccent.withValues(alpha: 0.5),
                          blurRadius: 6,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
