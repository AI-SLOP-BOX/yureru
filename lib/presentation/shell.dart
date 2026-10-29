import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import '../app_state.dart';
import '../data/thumbnails.dart';
import '../data/session.dart';
import '../domain/models.dart';
import '../platform/system_media_provider.dart';
import '../platform/keyboard_shortcuts.dart';
import 'i18n.dart';
import '../playback/playback_controller.dart';
import 'nav.dart';
import 'layout_metrics.dart';
import 'theme.dart';

import 'screens/home_screen.dart';
import 'screens/immersive_player_screen.dart';
import 'screens/playlist_detail_screen.dart';
import 'screens/playlists_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/videos_screen.dart';
import 'widgets/mini_player.dart';
import 'widgets/ambient_backdrop.dart';
import 'widgets/player_card.dart';
import 'widgets/queue_panel.dart';
import 'widgets/search_overlay.dart';
import 'widgets/sidebar.dart';
import 'widgets/shell_chrome.dart';
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
  bool _desktopSidebarVisible = false;
  bool _desktopSidebarPinned = false;
  bool _desktopSidebarPointerInside = false;
  bool _desktopQueuePinned = false;
  Timer? _desktopSidebarHideTimer;
  Timer? _desktopQueueHideTimer;
  PlaybackController? _playbackController;
  ProviderSubscription<LibraryState>? _thumbnailLibrarySubscription;
  final Set<String> _thumbnailGenerationAttempted = <String>{};

  @override
  void initState() {
    super.initState();
    _thumbnailLibrarySubscription = ref.listenManual<LibraryState>(
      libraryProvider,
      (_, next) {
        if (next.loaded) _scheduleMissingThumbnails(next.media);
      },
      fireImmediately: true,
    );
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
    _thumbnailLibrarySubscription?.close();
    _desktopSidebarHideTimer?.cancel();
    _desktopQueueHideTimer?.cancel();
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyboardEvent);
    WidgetsBinding.instance.removeObserver(this);
    _playbackController?.saveCurrentPosition();
    _appExitChannel.setMethodCallHandler(null);
    _pipChannel.setMethodCallHandler(null);
    _nativeMenuChannel.setMethodCallHandler(null);
    super.dispose();
  }

  void _scheduleMissingThumbnails(List<MediaItem> media) {
    final missing = media
        .where((item) {
          final path = item.localPath;
          return !item.isTemporary &&
              item.thumbnailPath == null &&
              !path.startsWith('http://') &&
              !path.startsWith('https://') &&
              _thumbnailGenerationAttempted.add(item.id);
        })
        .toList(growable: false);
    if (missing.isNotEmpty) unawaited(_generateMissingThumbnails(missing));
  }

  Future<void> _generateMissingThumbnails(List<MediaItem> media) async {
    for (final item in media) {
      if (!mounted) return;
      try {
        await ThumbnailService.forMedia(
          mediaId: item.id,
          localPath: item.localPath,
        );
      } catch (_) {
        // A missing, unsupported, or temporarily unavailable file keeps the
        // normal placeholder; one failure must not stop the rest of the scan.
      }
    }
  }

  bool _handleGlobalKeyboardEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (ModalRoute.of(context)?.isCurrent == false) return false;

    final keyboard = HardwareKeyboard.instance;
    final bindings = ref.read(keyboardShortcutsProvider);
    bool matches(AppShortcutAction action) =>
        bindings[action]?.matches(event, keyboard) ?? false;
    if (matches(AppShortcutAction.globalSearch)) {
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
    if (matches(AppShortcutAction.togglePlayback)) {
      playback.toggle();
      return true;
    }
    if (matches(AppShortcutAction.exitExpandedView)) {
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
    _desktopQueueHideTimer?.cancel();
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
    // Keep playlist searches scoped to the playlist currently on screen.
    if (detailPlaylistId != null) return;
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
      final width = MediaQuery.sizeOf(context).width;
      final desktopOverlays = LayoutMetrics.isLargeDesktop(context);
      final sidebarInset = desktopOverlays && _desktopSidebarVisible
          ? LayoutMetrics.desktopPane(_sideW, width, min: 200, max: 340) + 8
          : 0.0;
      final queueInset = desktopOverlays && ref.watch(queueVisibleProvider)
          ? LayoutMetrics.desktopPane(_queueW, width, min: 280, max: 480) + 8
          : 0.0;
      return Padding(
        padding: EdgeInsets.fromLTRB(inset, 4, inset, 12),
        child: PlayerCard(
          leadingChromeInset: sidebarInset,
          trailingChromeInset: queueInset,
        ),
      );
    }
    return _centerPage();
  }

  void _toggleQueue() {
    if (LayoutMetrics.isLargeDesktop(context) &&
        ref.read(viewingPlayerProvider)) {
      _showDesktopQueue();
      return;
    }
    ref.read(lyricsPanelProvider.notifier).state = false;
    ref.read(queueVisibleProvider.notifier).state = !ref.read(
      queueVisibleProvider,
    );
  }

  void _showDesktopSidebar() {
    _desktopSidebarHideTimer?.cancel();
    if (!_desktopSidebarVisible && mounted) {
      setState(() => _desktopSidebarVisible = true);
    }
  }

  void _toggleDesktopSidebarPin() {
    _desktopSidebarHideTimer?.cancel();
    setState(() {
      _desktopSidebarPinned = !_desktopSidebarPinned;
      _desktopSidebarVisible = true;
    });
    if (!_desktopSidebarPinned && !_desktopSidebarPointerInside) {
      _scheduleDesktopSidebarHide();
    }
  }

  void _scheduleDesktopSidebarHide() {
    if (_desktopSidebarPinned) return;
    _desktopSidebarHideTimer?.cancel();
    _desktopSidebarHideTimer = Timer(const Duration(milliseconds: 420), () {
      if (mounted) setState(() => _desktopSidebarVisible = false);
    });
  }

  void _showDesktopQueue() {
    _desktopQueueHideTimer?.cancel();
    ref.read(queueVisibleProvider.notifier).state = true;
  }

  void _toggleDesktopQueuePin() {
    _desktopQueueHideTimer?.cancel();
    if (_desktopQueuePinned) {
      _desktopQueuePinned = false;
      _scheduleDesktopQueueHide();
    } else {
      _desktopQueuePinned = true;
      ref.read(queueVisibleProvider.notifier).state = true;
    }
    setState(() {});
  }

  void _scheduleDesktopQueueHide() {
    if (_desktopQueuePinned) return;
    _desktopQueueHideTimer?.cancel();
    _desktopQueueHideTimer = Timer(const Duration(milliseconds: 420), () {
      if (mounted) ref.read(queueVisibleProvider.notifier).state = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    // Desktop uses an edge-revealed queue overlay; compact layouts retain
    // their explicit queue-sheet behavior.
    if (_wasWide != null && _wasWide != wide) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _desktopSidebarPinned = false;
          _desktopSidebarVisible = false;
          _desktopSidebarPointerInside = false;
          _desktopQueuePinned = false;
        });
        _desktopQueueHideTimer?.cancel();
        ref.read(queueVisibleProvider.notifier).state = false;
      });
    }
    _wasWide = wide;
    // Fresh playback enters the player without covering it with the desktop
    // queue overlay. Auto-advance leaves the current view alone.
    ref.listen<String?>(queueProvider.select((q) => q.currentId), (prev, next) {
      if (next != null && prev == null && mounted) {
        ref.read(viewingPlayerProvider.notifier).state = true;
        _desktopQueuePinned = false;
        // The desktop queue is revealed from the right edge on demand.
        ref.read(queueVisibleProvider.notifier).state = false;
      }
    });
    // Restore an explicitly pinned queue when returning from a browse screen.
    ref.listen<bool>(viewingPlayerProvider, (prev, next) {
      if (next && mounted) {
        // Keep a deliberate queue pin across browse/player transitions. The
        // panel stays hidden while browsing and returns when the player does.
        ref.read(queueVisibleProvider.notifier).state = _desktopQueuePinned;
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
          ? const ShellPictureInPictureView()
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
    final browseSidebarInset =
        _desktopSidebarVisible && !(viewing && hasCurrent)
        ? sideWidth + 8
        : 0.0;
    final playerMode = ref.watch(playerViewModeProvider);
    final isCinema = hasCurrent && ref.watch(cinemaModeProvider);
    final ambientEnabled = ref.watch(ambientLightProvider);
    final theme = Theme.of(context);
    final showAmbient =
        viewing &&
        hasCurrent &&
        ambientEnabled &&
        !isCinema &&
        playerMode == PlayerViewMode.media;

    return Scaffold(
      key: const ValueKey('wide-app-shell'),
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
                    child: Stack(
                      clipBehavior: Clip.hardEdge,
                      children: [
                        Column(
                          children: [
                            TopBar(
                              onOpenSearch: _openSearch,
                              onSubmitSearch: _submitSearch,
                              onOpenFile: hasCurrent ? null : _openMediaFile,
                              onSaveTemporary: _saveTemporaryCurrent,
                              showMenuButton: true,
                              onToggleSidebar: _toggleDesktopSidebarPin,
                              sidebarPinned: _desktopSidebarPinned,
                              onToggleQueuePin: viewing && hasCurrent
                                  ? _toggleDesktopQueuePin
                                  : null,
                              queuePinned: _desktopQueuePinned,
                              ambient: showAmbient,
                              leadingInset: _desktopSidebarVisible
                                  ? sideWidth + 8
                                  : 0,
                            ),
                            Expanded(
                              child: AnimatedPadding(
                                key: const ValueKey(
                                  'shell-center-sidebar-inset',
                                ),
                                duration: const Duration(milliseconds: 240),
                                curve: Curves.easeOutCubic,
                                padding: EdgeInsets.only(
                                  left: browseSidebarInset,
                                ),
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 140),
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
                            ),
                          ],
                        ),
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          width: 16,
                          child: MouseRegion(
                            onEnter: (_) => _showDesktopSidebar(),
                            child: const SizedBox.expand(),
                          ),
                        ),
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 240),
                          curve: Curves.easeOutCubic,
                          left: _desktopSidebarVisible ? 0 : -sideWidth - 8,
                          top: 0,
                          bottom: 0,
                          width: sideWidth + 8,
                          child: MouseRegion(
                            onEnter: (_) {
                              _desktopSidebarPointerInside = true;
                              _desktopSidebarHideTimer?.cancel();
                            },
                            onExit: (_) {
                              _desktopSidebarPointerInside = false;
                              _scheduleDesktopSidebarHide();
                            },
                            child: Material(
                              color: Colors.transparent,
                              elevation: 18,
                              shadowColor: Colors.black54,
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
                                  ShellHorizontalSplitter(
                                    tooltip: ref.tr('sidebar_width'),
                                    ambient: showAmbient,
                                    onDelta: (dx) => setState(
                                      () => _sideW =
                                          ((sideWidth + dx) / sideScale).clamp(
                                            200.0,
                                            340.0,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (viewing && hasCurrent)
                          Positioned(
                            right: 0,
                            top: 68,
                            bottom: 0,
                            width: 16,
                            child: MouseRegion(
                              onEnter: (_) => _showDesktopQueue(),
                              child: const SizedBox.expand(),
                            ),
                          ),
                        if (viewing && hasCurrent)
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 240),
                            curve: Curves.easeOutCubic,
                            right: showQueue ? 0 : -queueWidth - 8,
                            top: 68,
                            bottom: 0,
                            width: queueWidth + 8,
                            child: MouseRegion(
                              onEnter: (_) => _desktopQueueHideTimer?.cancel(),
                              onExit: (_) => _scheduleDesktopQueueHide(),
                              child: Material(
                                color: Colors.transparent,
                                elevation: 18,
                                shadowColor: Colors.black54,
                                child: Row(
                                  children: [
                                    ShellHorizontalSplitter(
                                      tooltip: ref.tr('queue_width'),
                                      ambient: showAmbient,
                                      onDelta: (dx) => setState(
                                        () => _queueW =
                                            ((queueWidth - dx) / sideScale)
                                                .clamp(280.0, 480.0),
                                      ),
                                    ),
                                    QueuePanel(
                                      width: queueWidth,
                                      ambient: showAmbient,
                                    ),
                                  ],
                                ),
                              ),
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
          if (isCinema) const Positioned.fill(child: ShellCinemaFadeIn()),
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
            ShellCompactDrawerItem(
              icon: Icons.home_rounded,
              label: ref.tr('library'),
              selected: nav == Nav.library && detailId == null && !isPlayerMode,
              onTap: () {
                Navigator.pop(context);
                _setNav(Nav.library);
              },
            ),
            ShellCompactDrawerItem(
              icon: Icons.playlist_play_rounded,
              label: ref.tr('playlists'),
              selected:
                  nav == Nav.playlists && detailId == null && !isPlayerMode,
              onTap: () {
                Navigator.pop(context);
                _setNav(Nav.playlists);
              },
            ),
            ShellCompactDrawerItem(
              icon: Icons.library_music_rounded,
              label: ref.tr('all_videos'),
              selected: nav == Nav.videos && !isPlayerMode,
              onTap: () {
                Navigator.pop(context);
                _setNav(Nav.videos);
              },
            ),
            ShellCompactDrawerItem(
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
    final playerMode = ref.watch(playerViewModeProvider);
    final showAmbient =
        isPlayerMode &&
        ref.watch(ambientLightProvider) &&
        !isCinema &&
        playerMode == PlayerViewMode.media;

    return Stack(
      children: [
        if (showAmbient) const Positioned.fill(child: AmbientRoomGlowCanvas()),
        Positioned.fill(
          child: Scaffold(
            key: const ValueKey('compact-app-shell'),
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
                      ShellCompactNavigationBar(
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
