import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:io';
import '../app_state.dart';
import '../data/session.dart';
import '../platform/window_utils.dart';
import '../platform/system_media_provider.dart';
import 'i18n.dart';
import '../playback/playback_controller.dart';
import 'nav.dart';
import 'layout_metrics.dart';
import 'theme.dart';

import 'screens/home_screen.dart';
import 'screens/immersive_player_screen.dart';
import 'screens/playlist_detail_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/videos_screen.dart';
import 'widgets/mini_player.dart';
import 'widgets/frosted_panel.dart';
import 'widgets/ambient_backdrop.dart';
import 'widgets/player_card.dart';
import 'widgets/queue_panel.dart';
import 'widgets/search_overlay.dart';
import 'widgets/sidebar.dart';
import 'widgets/top_bar.dart';
import 'widgets/transport_bar.dart';
import 'widgets/yureru_logo.dart';

/// 3-pane desktop shell (sidebar / center / queue) + bottom transport bar.
/// Wide (>=1000px): target design layout. Narrow: nav bar + mini player.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});
  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  static const _appExitChannel = MethodChannel('yureru/app_exit');
  static const _pipChannel = MethodChannel('yureru/media_picker');
  static const _nativeMenuChannel = MethodChannel('yureru/native_menu');
  static const _firstLaunchCompleteKey = 'yureru_first_launch_complete_v1';
  Nav nav = Nav.library;
  String? detailPlaylistId;
  Nav _detailFrom = Nav.library;

  /// Resizable side panels (drag the dividers). Center video flexes.
  double _sideW = 248;
  double _queueW = 336;
  bool? _wasWide;
  PlaybackController? _playbackController;

  @override
  void initState() {
    super.initState();
    _playbackController = ref.read(playbackControllerProvider);
    ref.read(systemMediaSessionProvider);
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyboardEvent);
    WidgetsBinding.instance.addObserver(this);
    _appExitChannel.setMethodCallHandler((call) async {
      if (call.method == 'prepareForTermination') {
        await ref.read(playbackControllerProvider).prepareForAppExit();
        return null;
      }
      throw MissingPluginException(
        'Unknown app lifecycle method: ${call.method}',
      );
    });
    _pipChannel.setMethodCallHandler((call) async {
      if (call.method == 'onSystemPictureInPictureChanged') {
        ref.read(pictureInPictureProvider.notifier).state =
            call.arguments == true;
        return null;
      }
      return null;
    });
    _nativeMenuChannel.setMethodCallHandler((call) async {
      if (call.method == 'openSettings') {
        _setNav(Nav.settings);
        return null;
      }
      throw MissingPluginException(
        'Unknown native menu action: ${call.method}',
      );
    });
    Future.microtask(() async {
      if (!mounted) return;
      if (!ref.read(libraryProvider).loaded) {
        await ref.read(libraryProvider.notifier).load();
      }
      if (!mounted) return;
      final preferences = await SharedPreferences.getInstance();
      if (preferences.getBool(_firstLaunchCompleteKey) != true) {
        final hasImportedMedia = ref
            .read(libraryProvider)
            .savedMedia
            .isNotEmpty;
        await preferences.setBool(_firstLaunchCompleteKey, true);
        if (!hasImportedMedia && mounted) {
          setState(() => nav = Nav.settings);
        }
      }
      await ref.read(playbackControllerProvider).restoreSession();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      ref.read(playbackControllerProvider).saveCurrentPosition();
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyboardEvent);
    WidgetsBinding.instance.removeObserver(this);
    _playbackController?.saveCurrentPosition();
    _appExitChannel.setMethodCallHandler(null);
    _pipChannel.setMethodCallHandler(null);
    _nativeMenuChannel.setMethodCallHandler(null);
    super.dispose();
  }

  bool _handleGlobalKeyboardEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (ModalRoute.of(context)?.isCurrent == false) return false;

    final keyboard = HardwareKeyboard.instance;
    final key = event.logicalKey;
    final isMac = Platform.isMacOS;
    final hasSearchModifier = isMac
        ? keyboard.isMetaPressed
        : keyboard.isControlPressed;
    if (key == LogicalKeyboardKey.keyK && hasSearchModifier) {
      _openSearch();
      return true;
    }

    final focusContext = FocusManager.instance.primaryFocus?.context;
    final isTyping =
        focusContext != null &&
        focusContext.mounted &&
        (focusContext.widget is EditableText ||
            focusContext.findAncestorWidgetOfExactType<EditableText>() != null);
    if (isTyping) return false;

    final playback = ref.read(playbackControllerProvider);
    switch (key) {
      case LogicalKeyboardKey.space:
        playback.toggle();
        return true;
      case LogicalKeyboardKey.escape:
        if (ref.read(immersiveModeProvider)) {
          ref.read(immersiveModeProvider.notifier).state = false;
          return true;
        }
        if (ref.read(cinemaModeProvider)) {
          ref.read(cinemaModeProvider.notifier).state = false;
          return true;
        }
    }
    return false;
  }

  void _browse() {
    ref.read(immersiveModeProvider.notifier).state = false;
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

  Future<void> _openMediaFile() async {
    try {
      final items = await ref.read(importerProvider).pickForPlayback();
      if (!mounted || items.isEmpty) return;
      ref.read(libraryProvider.notifier).addTemporaryMedia(items);
      showPlayerView(ref);
      ref.read(queueProvider.notifier).start([
        for (final item in items) item.id,
      ], shuffle: false);
      await ref.read(playbackControllerProvider).openCurrent();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ref.tr('file_open_failed').replaceAll('{error}', '$error'),
          ),
        ),
      );
    }
  }

  Future<void> _saveTemporaryCurrent() async {
    final id = ref.read(queueProvider).currentId;
    if (id == null || ref.read(libraryProvider).byId(id)?.isTemporary != true) {
      return;
    }
    try {
      await ref.read(libraryProvider.notifier).saveTemporaryMedia(id);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(ref.tr('saved_to_library'))));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ref.tr('file_open_failed').replaceAll('{error}', '$error'),
            ),
          ),
        );
      }
    }
  }

  void _submitSearch(String query) {
    if (!mounted) return;
    ref.read(searchQueryProvider.notifier).state = query;
    ref.read(videoCreatorFilterProvider.notifier).state = null;
    _browse();
    setState(() {
      nav = Nav.videos;
      detailPlaylistId = null;
    });
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

  void _toggleQueue() {
    ref.read(lyricsPanelProvider.notifier).state = false;
    ref.read(queueVisibleProvider.notifier).state = !ref.read(
      queueVisibleProvider,
    );
  }

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
    ref.listen<String?>(creatorVideosRequestProvider, (_, creator) {
      if (creator == null || creator.trim().isEmpty || !mounted) return;
      ref.read(creatorVideosRequestProvider.notifier).state = null;
      ref.read(videoCreatorFilterProvider.notifier).state = creator.trim();
      ref.read(searchQueryProvider.notifier).state = '';
      ref.read(favoritesOnlyProvider.notifier).state = false;
      _browse();
      setState(() {
        nav = Nav.videos;
        detailPlaylistId = null;
      });
    });
    ref.listen<String?>(videoOpenRequestProvider, (_, mediaId) {
      if (mediaId == null || !mounted) return;
      ref.read(videoCreatorFilterProvider.notifier).state = null;
      ref.read(searchQueryProvider.notifier).state = '';
      ref.read(favoritesOnlyProvider.notifier).state = false;
      _browse();
      setState(() {
        nav = Nav.videos;
        detailPlaylistId = null;
      });
    });
    final isPictureInPicture = ref.watch(pictureInPictureProvider);
    final immersive = ref.watch(immersiveModeProvider);
    final hasMedia = ref.watch(queueProvider.select((q) => q.hasCurrent));
    return Focus(
      autofocus: true,
      child: isPictureInPicture
          ? const _PictureInPictureView()
          : immersive && hasMedia
          ? const ImmersivePlayerScreen()
          : wide
          ? _wide()
          : _narrow(),
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
    final playerMode = ref.watch(playerViewModeProvider);
    final isCinema = hasCurrent && ref.watch(cinemaModeProvider);
    final ambientEnabled = ref.watch(ambientLightProvider);
    final theme = Theme.of(context);
    final showAmbient = viewing && hasCurrent && ambientEnabled && !isCinema;

    return Scaffold(
      // The room-glow canvas is painted immediately behind this Scaffold.
      // Keep the wide player surface transparent while ambient mode is on;
      // an opaque scaffold background hides every sampled video color.
      backgroundColor: showAmbient
          ? Colors.transparent
          : theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          if (showAmbient)
            const Positioned.fill(child: AmbientRoomGlowCanvas()),
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
                          ambient: showAmbient,
                          onNav: _setNav,
                          onPlaylist: _openDetail,
                          onLogoHome: _goLibrary,
                        ),
                        _HSplitter(
                          tooltip: ref.tr('sidebar_width'),
                          ambient: showAmbient,
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
                                onOpenSearch: _openSearch,
                                onSubmitSearch: _submitSearch,
                                onOpenFile: hasCurrent ? null : _openMediaFile,
                                onSaveTemporary: _saveTemporaryCurrent,
                                ambient: showAmbient,
                              ),
                              Expanded(
                                child: LayoutBuilder(
                                  builder: (context, centerConstraints) {
                                    // Automatically hide queue if available width in center area is too small (< 620px),
                                    // and automatically restore when widened.
                                    final autoHideQueue =
                                        centerConstraints.maxWidth < 620;
                                    // `viewing` only controls the default state
                                    // when entering the player. Once there, the
                                    // queue button must be able to close the pane.
                                    final effectiveShowQueue =
                                        showQueue && !autoHideQueue;

                                    return Row(
                                      children: [
                                        Expanded(
                                          child: Stack(
                                            children: [
                                              Positioned.fill(
                                                child: AnimatedSwitcher(
                                                  duration: const Duration(
                                                    milliseconds: 140,
                                                  ),
                                                  switchInCurve: Curves.easeOut,
                                                  switchOutCurve:
                                                      Curves.easeOut,
                                                  child: KeyedSubtree(
                                                    key: ValueKey(
                                                      'center-${viewing ? 'player' : nav.name}-${detailPlaylistId ?? ''}',
                                                    ),
                                                    child: _center(),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (effectiveShowQueue) ...[
                                          _HSplitter(
                                            tooltip: ref.tr('queue_width'),
                                            ambient: showAmbient,
                                            onDelta: (dx) => setState(
                                              () => _queueW =
                                                  ((queueWidth - dx) /
                                                          sideScale)
                                                      .clamp(280.0, 480.0),
                                            ),
                                          ),
                                          QueuePanel(
                                            width: queueWidth,
                                            ambient: showAmbient,
                                            onClose: _toggleQueue,
                                          ),
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
                  // Keep core playback controls available while browsing and
                  // while the full player is open; the immersive view has its
                  // own integrated transport controls.
                  if (hasCurrent &&
                      !(viewing && playerMode == PlayerViewMode.media))
                    TransportBar(
                      queueVisible: showQueue,
                      onToggleQueue: _toggleQueue,
                      transportOnly: viewing,
                      ambient: showAmbient,
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
    final playerMode = ref.watch(playerViewModeProvider);
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
      width: (MediaQuery.sizeOf(context).width - 56).clamp(260.0, 288.0),
      backgroundColor: themePanelSolid(context),
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(right: Radius.circular(22)),
        side: BorderSide(color: kGlassBorder),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 18, 24),
              child: Row(
                children: [
                  const YureruWaveLogo(size: 38),
                  const SizedBox(width: 12),
                  Text(
                    'Yureru',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 16, 10),
              child: Text(
                ref.tr('library'),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: kTextMuted,
                  letterSpacing: 1.1,
                ),
              ),
            ),
            _CompactDrawerItem(
              icon: Icons.home_rounded,
              label: ref.tr('library'),
              selected: nav == Nav.library && detailId == null && !isPlayerMode,
              onTap: () {
                Navigator.pop(context);
                _setNav(Nav.library);
              },
            ),
            _CompactDrawerItem(
              icon: Icons.playlist_play_rounded,
              label: ref.tr('playlists'),
              selected:
                  nav == Nav.playlists && detailId == null && !isPlayerMode,
              onTap: () {
                Navigator.pop(context);
                _setNav(Nav.playlists);
              },
            ),
            _CompactDrawerItem(
              icon: Icons.library_music_rounded,
              label: ref.tr('all_videos'),
              selected: nav == Nav.videos && !isPlayerMode,
              onTap: () {
                Navigator.pop(context);
                _setNav(Nav.videos);
              },
            ),
            _CompactDrawerItem(
              icon: Icons.settings_rounded,
              label: ref.tr('settings'),
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
    final showAmbient =
        isPlayerMode && ref.watch(ambientLightProvider) && !isCinema;

    return Stack(
      children: [
        if (showAmbient) const Positioned.fill(child: AmbientRoomGlowCanvas()),
        Positioned.fill(
          child: Scaffold(
            backgroundColor: showAmbient
                ? Colors.transparent
                : Theme.of(context).scaffoldBackgroundColor,
            drawer: isCinema || isPlayerMode ? null : drawer,
            body: Column(
              children: [
                if (!isCinema && !isPlayerMode)
                  SafeArea(
                    bottom: false,
                    child: TopBar(
                      onOpenSearch: _openSearch,
                      onSubmitSearch: _submitSearch,
                      onOpenFile: q.hasCurrent ? null : _openMediaFile,
                      onSaveTemporary: _saveTemporaryCurrent,
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
                                constraints: const BoxConstraints(
                                  maxWidth: 420,
                                ),
                                child: QueuePanel(
                                  width: double.infinity,
                                  ambient: showAmbient,
                                  margin: const EdgeInsets.fromLTRB(
                                    16,
                                    8,
                                    8,
                                    8,
                                  ),
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
            bottomNavigationBar:
                isPlayerMode && playerMode == PlayerViewMode.media
                ? null
                : isPlayerMode
                ? TransportBar(
                    queueVisible: showQueue,
                    onToggleQueue: _toggleQueue,
                    transportOnly: true,
                    ambient: showAmbient,
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MiniPlayer(onExpand: () => showPlayerView(ref)),
                      _CompactNavigationBar(
                        selectedIndex: detailId != null ? 1 : index.clamp(0, 3),
                        labels: [
                          ref.tr('library'),
                          ref.tr('playlists'),
                          ref.tr('all_videos'),
                          ref.tr('settings'),
                        ],
                        onSelected: (i) => _setNav(Nav.values[i]),
                      ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _CompactDrawerItem extends StatelessWidget {
  const _CompactDrawerItem({
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

class _CompactNavigationBar extends StatelessWidget {
  const _CompactNavigationBar({
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

class _PictureInPictureView extends ConsumerStatefulWidget {
  const _PictureInPictureView();

  @override
  ConsumerState<_PictureInPictureView> createState() =>
      _PictureInPictureViewState();
}

class _PictureInPictureViewState extends ConsumerState<_PictureInPictureView> {
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
class _HSplitter extends StatefulWidget {
  final ValueChanged<double> onDelta;
  final String tooltip;
  final bool ambient;
  const _HSplitter({
    required this.onDelta,
    required this.tooltip,
    this.ambient = false,
  });

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
