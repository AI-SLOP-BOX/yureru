import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../app_state.dart';
import '../../platform/window_utils.dart';
import '../i18n.dart';
import '../theme.dart';
import 'frosted_panel.dart';
import 'player_card.dart';

class ShellCompactDrawerItem extends StatelessWidget {
  const ShellCompactDrawerItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = selected
        ? (isDark ? kAccentLight : Colors.black87)
        : (isDark ? kTextSub : Colors.black54);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
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
            height: 48,
            child: Row(
              children: [
                const SizedBox(width: 15),
                Icon(icon, size: 21, color: color),
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
    extends ConsumerState<ShellPictureInPictureView> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final engine = ref.watch(engineProvider);
    final media = ref
        .watch(libraryProvider)
        .byId(
          ref.watch(queueProvider.select((queue) => queue.currentId ?? '')),
        );
    return Scaffold(
      backgroundColor: Colors.black,
      body: MouseRegion(
        onEnter: (_) {
          if (!_hovered) setState(() => _hovered = true);
        },
        onExit: (_) {
          if (_hovered) setState(() => _hovered = false);
        },
        child: GestureDetector(
          // The compact macOS window has no title bar, and the Flutter video
          // surface consumes pointer events before AppKit's background-drag
          // handling can move the window. Start a native window drag when the
          // user drags anywhere on the PiP surface; taps still reach controls.
          behavior: HitTestBehavior.opaque,
          onPanStart: (_) => windowManager.startDragging(),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                engine.buildVideoView(),
                IgnorePointer(
                  ignoring: !_hovered,
                  child: AnimatedOpacity(
                    opacity: _hovered ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Align(
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
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                media?.title ?? ref.tr('playing'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
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
                              tooltip: ref.tr('restore_window'),
                              color: Colors.white,
                              onPressed: () async {
                                ref
                                        .read(pictureInPictureProvider.notifier)
                                        .state =
                                    false;
                                await WidgetsBinding.instance.endOfFrame;
                                await restorePictureInPictureWindow(
                                  engine: engine,
                                );
                              },
                              icon: const Icon(
                                Icons.picture_in_picture_alt_rounded,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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
