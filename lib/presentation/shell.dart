import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';
import 'dart:io';
import '../app_state.dart';
import '../data/session.dart';
import '../playback/playback_controller.dart';
import 'nav.dart';
import 'layout_metrics.dart';
import 'theme.dart';

import 'screens/home_screen.dart';
import 'screens/playlist_detail_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/videos_screen.dart';
import 'widgets/mini_player.dart';
import 'widgets/player_card.dart';
import 'widgets/queue_panel.dart';
import 'widgets/search_overlay.dart';
import 'widgets/sidebar.dart';
import 'widgets/top_bar.dart';
import 'widgets/transport_bar.dart';

/// 3-pane desktop shell (sidebar / center / queue) + bottom transport bar.
/// Wide (>=1000px): target design layout. Narrow: nav bar + mini player.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});
  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  Nav nav = Nav.library;
  String? detailPlaylistId;
  Nav _detailFrom = Nav.library;

  /// Resizable side panels (drag the dividers). Center video flexes.
  double _sideW = 248;
  double _queueW = 336;
  bool? _wasWide;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      if (!mounted) return;
      if (!ref.read(libraryProvider).loaded) {
        await ref.read(libraryProvider.notifier).load();
      }
      if (!mounted) return;
      await ref.read(playbackControllerProvider).restoreSession();
    });
  }

  void _browse() {
    ref.read(viewingPlayerProvider.notifier).state = false;
    ref.read(cinemaModeProvider.notifier).state = false;
    // Automatically close queue panel when browsing library, playlists, videos, or settings
    ref.read(queueVisibleProvider.notifier).state = false;
  }

  void _openDetail(String id) {
    _browse();
    setState(() {
      _detailFrom = nav;
      detailPlaylistId = id;
    });
  }

  void _closeDetail() {
    _browse();
    setState(() {
      detailPlaylistId = null;
      nav = _detailFrom;
    });
  }

  void _setNav(Nav n) {
    _browse();
    setState(() {
      nav = n;
      detailPlaylistId = null;
    });
  }

  void _goLibrary() => _setNav(Nav.library);

  void _openSearch() {
    if (!mounted) return;
    unawaited(SearchOverlay.show(context, _openDetail));
  }

  Widget _centerPage() {
    if (detailPlaylistId != null) {
      return PlaylistDetailScreen(
        playlistId: detailPlaylistId!,
        onBack: _closeDetail,
      );
    }
    switch (nav) {
      case Nav.library:
        return HomeScreen(
          onOpenPlaylist: _openDetail,
          onOpenVideos: () => _setNav(Nav.videos),
        );
      case Nav.playlists:
        return PlaylistsScreen(onOpenPlaylist: _openDetail);
      case Nav.videos:
        return const VideosScreen();
      case Nav.settings:
        return const SettingsScreen();
    }
  }

  Widget _center() {
    final q = ref.watch(queueProvider);
    final viewing = ref.watch(viewingPlayerProvider);
    // Player OR browse, never stacked: the list below the player is gone,
    // the video gets the whole center pane.
    if (q.hasCurrent && viewing) {
      final inset = LayoutMetrics.horizontalInset(context);
      return Padding(
        padding: EdgeInsets.fromLTRB(inset, 4, inset, 12),
        child: PlayerCard(),
      );
    }
    return _centerPage();
  }

  void _toggleQueue() => ref.read(queueVisibleProvider.notifier).state = !ref
      .read(queueVisibleProvider);

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    // Auto-close the queue when shrinking to phone layout, auto-restore when widening.
    if (_wasWide != null && _wasWide != wide) {
      final nowWide = wide;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(queueVisibleProvider.notifier).state =
            nowWide && ref.read(viewingPlayerProvider);
      });
    }
    _wasWide = wide;
    final ctl = ref.read(playbackControllerProvider);
    // Fresh playback enters the player; the queue opens by default only on
    // desktop. Auto-advance (playNext) leaves the current view alone.
    ref.listen<String?>(queueProvider.select((q) => q.currentId), (prev, next) {
      if (next != null && prev == null && mounted) {
        ref.read(viewingPlayerProvider.notifier).state = true;
        // Keep the queue open by default on desktop, but let compact layouts
        // enter the player without covering it with the queue sheet.
        ref.read(queueVisibleProvider.notifier).state = wide;
      }
    });
    // Whenever player view is activated, default the queue open only on desktop.
    ref.listen<bool>(viewingPlayerProvider, (prev, next) {
      if (next && mounted) {
        ref.read(queueVisibleProvider.notifier).state = wide;
      }
    });
    // Persist the queue layout on every change for session restore.
    ref.listen<QueueState>(queueProvider, (_, next) {
      unawaited(ref.read(sessionStoreProvider).saveQueue(next));
    });
    // Desktop shortcuts (ignored while typing in TextField).
    final isMac = Platform.isMacOS;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): () {
          final focusedNode = FocusManager.instance.primaryFocus;
          final ctx = focusedNode?.context;
          final isTyping =
              ctx != null &&
              ctx.mounted &&
              (ctx.widget is EditableText ||
                  ctx.findAncestorWidgetOfExactType<EditableText>() != null);
          if (!isTyping) {
            ctl.toggle();
          }
        },
        const SingleActivator(LogicalKeyboardKey.arrowRight): () {
          final focusedNode = FocusManager.instance.primaryFocus;
          final ctx = focusedNode?.context;
          final isTyping =
              ctx != null &&
              ctx.mounted &&
              (ctx.widget is EditableText ||
                  ctx.findAncestorWidgetOfExactType<EditableText>() != null);
          if (!isTyping) {
            ctl.seekBy(const Duration(seconds: 10));
          }
        },
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
          final focusedNode = FocusManager.instance.primaryFocus;
          final ctx = focusedNode?.context;
          final isTyping =
              ctx != null &&
              ctx.mounted &&
              (ctx.widget is EditableText ||
                  ctx.findAncestorWidgetOfExactType<EditableText>() != null);
          if (!isTyping) {
            ctl.seekBy(const Duration(seconds: -10));
          }
        },
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (ref.read(cinemaModeProvider)) {
            ref.read(cinemaModeProvider.notifier).state = false;
          }
        },
        SingleActivator(
          LogicalKeyboardKey.keyK,
          meta: isMac,
          control: !isMac,
        ): () =>
            _openSearch(),
      },
      child: Focus(autofocus: true, child: wide ? _wide() : _narrow()),
    );
  }

  Widget _wide() {
    final viewportWidth = MediaQuery.sizeOf(context).width;
    final sideScale = viewportWidth / 1440;
    final sideWidth = LayoutMetrics.desktopPane(
      _sideW,
      viewportWidth,
      min: 200,
      max: 340,
    );
    final queueWidth = LayoutMetrics.desktopPane(
      _queueW,
      viewportWidth,
      min: 280,
      max: 480,
    );
    final hasCurrent = ref.watch(queueProvider.select((q) => q.hasCurrent));
    final showQueue = ref.watch(queueVisibleProvider);
    final viewing = ref.watch(viewingPlayerProvider);
    final isCinema = hasCurrent && ref.watch(cinemaModeProvider);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          ClipRect(
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 1, end: isCinema ? 0.9 : 1),
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeInOutCubic,
              builder: (context, scale, child) => Transform.scale(
                scale: scale,
                alignment: Alignment.center,
                child: child,
              ),
              child: Column(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Sidebar(
                          width: sideWidth,
                          nav: nav,
                          detailPlaylistId: detailPlaylistId,
                          viewingPlayer: viewing,
                          onNav: _setNav,
                          onPlaylist: _openDetail,
                          onLogoHome: _goLibrary,
                        ),
                        _HSplitter(
                          tooltip: 'サイドバーの幅',
                          onDelta: (dx) => setState(
                            () => _sideW = ((sideWidth + dx) / sideScale).clamp(
                              200.0,
                              340.0,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              TopBar(
                                queueVisible: showQueue,
                                onToggleQueue: _toggleQueue,
                                onLogoHome: _goLibrary,
                                onOpenSearch: _openSearch,
                              ),
                              Expanded(
                                child: LayoutBuilder(
                                  builder: (context, centerConstraints) {
                                    // Automatically hide queue if available width in center area is too small (< 620px),
                                    // and automatically restore when widened.
                                    final autoHideQueue =
                                        centerConstraints.maxWidth < 620;
                                    final effectiveShowQueue =
                                        (viewing || showQueue) &&
                                        !autoHideQueue;

                                    return Row(
                                      children: [
                                        Expanded(
                                          child: AnimatedSwitcher(
                                            duration: const Duration(
                                              milliseconds: 140,
                                            ),
                                            switchInCurve: Curves.easeOut,
                                            switchOutCurve: Curves.easeOut,
                                            child: KeyedSubtree(
                                              key: ValueKey(
                                                'center-${viewing ? 'player' : nav.name}-${detailPlaylistId ?? ''}',
                                              ),
                                              child: _center(),
                                            ),
                                          ),
                                        ),
                                        if (effectiveShowQueue) ...[
                                          _HSplitter(
                                            tooltip: 'キューの幅',
                                            onDelta: (dx) => setState(
                                              () => _queueW =
                                                  ((queueWidth - dx) /
                                                          sideScale)
                                                      .clamp(280.0, 480.0),
                                            ),
                                          ),
                                          QueuePanel(width: queueWidth),
                                        ],
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Bottom transport bar: shown only while browsing library/playlists/videos/settings.
                  // When in full PlayerCard view, the player has its own OSC controls to avoid duplication.
                  if (hasCurrent && !viewing)
                    TransportBar(
                      queueVisible: showQueue,
                      onToggleQueue: _toggleQueue,
                    ),
                ],
              ),
            ),
          ),
          // Complete full screen cinema mode: occupies the entire window,
          // hiding sidebar, top bar, queue and transport bar.
          if (isCinema) const Positioned.fill(child: _CinemaFadeIn()),
        ],
      ),
    );
  }

  /// Narrow fallback: pages + mini player + bottom navigation.
  Widget _narrow() {
    final pages = [
      HomeScreen(
        onOpenPlaylist: _openDetail,
        onOpenVideos: () => _setNav(Nav.videos),
      ),
      PlaylistsScreen(onOpenPlaylist: _openDetail),
      const VideosScreen(),
      const SettingsScreen(),
    ];
    final index = nav.index;
    final detailId = detailPlaylistId;
    final q = ref.watch(queueProvider);
    final viewing = ref.watch(viewingPlayerProvider);
    final showQueue = ref.watch(queueVisibleProvider);
    final isPlayerMode = q.hasCurrent && viewing;
    Widget body;
    if (isPlayerMode) {
      body = const PlayerCard();
    } else if (detailId != null) {
      body = PlaylistDetailScreen(playlistId: detailId, onBack: _closeDetail);
    } else {
      body = IndexedStack(index: index.clamp(0, 3), children: pages);
    }

    // Drawer for navigation (shown via hamburger button in TopBar).
    // Visible at all times including when player is active.
    final drawer = Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'メニュー',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade500,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.home_rounded),
              title: const Text('ライブラリ'),
              selected: nav == Nav.library && detailId == null && !isPlayerMode,
              onTap: () {
                Navigator.pop(context);
                _setNav(Nav.library);
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_play_rounded),
              title: const Text('プレイリスト'),
              selected:
                  nav == Nav.playlists && detailId == null && !isPlayerMode,
              onTap: () {
                Navigator.pop(context);
                _setNav(Nav.playlists);
              },
            ),
            ListTile(
              leading: const Icon(Icons.video_library_rounded),
              title: const Text('すべての動画'),
              selected: nav == Nav.videos && !isPlayerMode,
              onTap: () {
                Navigator.pop(context);
                _setNav(Nav.videos);
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_rounded),
              title: const Text('設定'),
              selected: nav == Nav.settings && !isPlayerMode,
              onTap: () {
                Navigator.pop(context);
                _setNav(Nav.settings);
              },
            ),
          ],
        ),
      ),
    );

    final isCinema = q.hasCurrent && ref.watch(cinemaModeProvider);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      drawer: isCinema || isPlayerMode ? null : drawer,
      body: Column(
        children: [
          if (!isCinema && !isPlayerMode)
            SafeArea(
              bottom: false,
              child: TopBar(
                queueVisible: showQueue,
                onToggleQueue: _toggleQueue,
                onLogoHome: _goLibrary,
                onOpenSearch: _openSearch,
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 140),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeOut,
                    child: KeyedSubtree(
                      key: ValueKey(
                        'narrow-${isPlayerMode ? 'player' : nav.name}-${detailId ?? ''}',
                      ),
                      child: body,
                    ),
                  ),
                ),
                if (showQueue && !isPlayerMode)
                  Positioned.fill(
                    child: ColoredBox(
                      color: Colors.black45,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: QueuePanel(
                            width: double.infinity,
                            margin: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                            onClose: _toggleQueue,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      // When playing in full player view, hide the bottom navigation bar and mini player entirely.
      // User can open drawer (hamburger menu in TopBar) to navigate away.
      bottomNavigationBar: isPlayerMode
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MiniPlayer(onExpand: () => showPlayerView(ref)),
                NavigationBar(
                  selectedIndex: detailId != null ? 1 : index.clamp(0, 3),
                  onDestinationSelected: (i) => _setNav(Nav.values[i]),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.home_rounded),
                      label: 'ライブラリ',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.playlist_play_rounded),
                      label: 'プレイリスト',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.video_library_rounded),
                      label: '動画',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.settings_rounded),
                      label: '設定',
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _CinemaFadeIn extends StatelessWidget {
  const _CinemaFadeIn();

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

/// Horizontal drag divider between resizable panes. Dragging resizes the
/// neighbor panels; the center video flexes with whatever is left.
class _HSplitter extends StatefulWidget {
  final ValueChanged<double> onDelta;
  final String tooltip;
  const _HSplitter({required this.onDelta, required this.tooltip});

  @override
  State<_HSplitter> createState() => _HSplitterState();
}

class _HSplitterState extends State<_HSplitter> {
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
              width: _hover ? 2 : 1,
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
