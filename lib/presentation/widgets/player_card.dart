import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_state.dart';
import '../../domain/creator_names.dart';
import '../../domain/models.dart';
import '../../playback/playback_controller.dart';
import '../../playback/playback_engine.dart';
import '../i18n.dart';
import '../layout_metrics.dart';
import '../theme.dart';
import 'queue_panel.dart';
import 'app_svg_icon.dart';
import 'favorite_button.dart';
import 'sleep_timer_button.dart';
import 'playback_options.dart';
import 'repeat_icon.dart';
import 'skip_next_icon.dart';
import 'transport_icon.dart';
import 'thumb_image.dart';

/// Playing screen:
/// - Video and artwork playback surface
/// - IINA / macOS inspired floating frosted-glass OSC (On Screen Controller)
/// - Auto-hiding controls with mouse motion tracking and cursor blanking
/// - Two-finger / mouse linear horizontal drag scrubbing over video area
/// - Hover / drag floating time bubble preview above the seekbar
/// - Quiet play/pause state change
/// - Smooth volume toggle with expandable slider ("niyoki-to" animation)
/// - mpv video track toggle (`setVideoTrackEnabled`) for low-power audio mode
class PlayerCard extends ConsumerStatefulWidget {
  const PlayerCard({
    super.key,
    this.leadingChromeInset = 0,
    this.trailingChromeInset = 0,
  });

  final double leadingChromeInset;
  final double trailingChromeInset;

  @override
  ConsumerState<PlayerCard> createState() => _PlayerCardState();
}

class _PlayerCardState extends ConsumerState<PlayerCard> {
  final GlobalKey _playerHoverBoundsKey = GlobalKey();
  final GlobalKey _ambientVideoBoundsKey = GlobalKey();
  final GlobalKey _ambientVideoCaptureKey = GlobalKey();
  late StateController<Rect?> _ambientApertureController;
  late PlaybackEngine _engine;
  Rect? _lastAmbientAperture;
  bool _ambientBoundsReportScheduled = false;
  bool _ambientBoundsNeeded = false;
  StreamSubscription? _sub;
  bool _controlsVisible = false;
  bool _isPlaybackPlaying = false;
  bool _pointerOverPlayer = false;
  bool _pointerPressed = false;
  Offset? _lastPointerActivityPosition;
  Timer? _hideTimer;
  Timer? _pendingVideoTapTimer;
  Timer? _compactCinemaHideTimer;
  bool _compactCinemaControlsVisible = false;

  // Linear drag scrub over the video
  bool _isLinearDragging = false;
  double _dragAccumulatedDelta = 0.0;
  Duration _dragStartPos = Duration.zero;
  bool _queueSheetExpanded = false;

  void _reportAmbientVideoBounds() {
    _ambientBoundsNeeded = true;
    if (_ambientBoundsReportScheduled) return;
    _ambientBoundsReportScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ambientBoundsReportScheduled = false;
      if (!mounted) return;
      if (!_ambientBoundsNeeded) {
        _clearAmbientVideoBounds();
        return;
      }
      final renderObject = _ambientVideoBoundsKey.currentContext
          ?.findRenderObject();
      final window = MediaQuery.sizeOf(context);
      if (renderObject is! RenderBox ||
          !renderObject.hasSize ||
          window.width <= 0 ||
          window.height <= 0) {
        return;
      }
      // The video frame sits inside FittedBox/RotatedBox in several layouts.
      // RenderBox.size is pre-transform, so use its transformed bounds or the
      // ambient aperture will be the wrong size and shifted from the video.
      final transformed = MatrixUtils.transformRect(
        renderObject.getTransformTo(null),
        Offset.zero & renderObject.size,
      );
      if (transformed.isEmpty) return;
      // Keep the full media bounds even when the window clips part of the
      // player. Clamping here to the visible slice recenters and stretches
      // the edge profile, which makes the ambient continuation lean to one
      // side whenever the video extends beyond the screen edge.
      final aperture = Rect.fromLTWH(
        transformed.left / window.width,
        transformed.top / window.height,
        transformed.width / window.width,
        transformed.height / window.height,
      );
      final previous = _lastAmbientAperture;
      if (previous != null &&
          (previous.left - aperture.left).abs() < 0.001 &&
          (previous.top - aperture.top).abs() < 0.001 &&
          (previous.width - aperture.width).abs() < 0.001 &&
          (previous.height - aperture.height).abs() < 0.001) {
        return;
      }
      _lastAmbientAperture = aperture;
      _ambientApertureController.state = aperture;
    });
  }

  void _clearAmbientVideoBounds() {
    _ambientBoundsNeeded = false;
    final previous = _lastAmbientAperture;
    if (previous == null) return;
    _lastAmbientAperture = null;
    // dispose can run while Flutter is finalizing the widget tree. Defer the
    // provider write until the frame is over, and avoid clearing a newer
    // aperture published by another player surface in the meantime.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_ambientApertureController.mounted) return;
      if (_ambientApertureController.state == previous) {
        _ambientApertureController.state = null;
      }
    });
  }

  void _trackGlobalMousePosition(PointerEvent event) {
    if (event.kind != PointerDeviceKind.mouse || event is! PointerHoverEvent) {
      return;
    }
    final renderObject = _playerHoverBoundsKey.currentContext
        ?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;
    final bounds = renderObject.localToGlobal(Offset.zero) & renderObject.size;
    final isInsidePlayer = bounds.contains(event.position);
    if (isInsidePlayer) {
      _showControlsForPointer(event.position);
    } else if (_pointerOverPlayer) {
      _hideTimer?.cancel();
      _pointerOverPlayer = false;
      _lastPointerActivityPosition = null;
      if ((_isPlaybackPlaying || _autoHideVideoControls) &&
          !_isLinearDragging &&
          mounted) {
        setState(() => _controlsVisible = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _ambientApertureController = ref.read(
      ambientVideoApertureProvider.notifier,
    );
    WidgetsBinding.instance.pointerRouter.addGlobalRoute(
      _trackGlobalMousePosition,
    );
    final engine = _engine = ref.read(engineProvider);
    bool lastInit = engine.snapshot.initialized;
    bool lastPlaying = engine.snapshot.isPlaying;
    _isPlaybackPlaying = lastPlaying;
    double? lastVideoAspectRatio = engine.videoAspectRatio;

    _sub = engine.snapshots.listen((s) {
      if (!mounted) return;
      final videoAspectRatio = engine.videoAspectRatio;
      final previousAspectRatio = lastVideoAspectRatio;
      final aspectRatioChanged =
          (videoAspectRatio == null) != (previousAspectRatio == null) ||
          (videoAspectRatio != null &&
              previousAspectRatio != null &&
              (videoAspectRatio - previousAspectRatio).abs() > 0.001);
      lastVideoAspectRatio = videoAspectRatio;
      if (s.initialized != lastInit) {
        lastInit = s.initialized;
        setState(() {});
      }
      if (s.isPlaying != lastPlaying) {
        lastPlaying = s.isPlaying;
        _isPlaybackPlaying = s.isPlaying;
        if (s.isPlaying) {
          _startHideTimer(reset: true);
        } else if (_autoHideVideoControls) {
          // Video controls follow pointer activity even while paused. Show
          // them briefly on pause, then let the same idle timer hide them.
          _controlsVisible = true;
          _startHideTimer(reset: true);
        } else {
          // Keep the music/image transport available while playback is paused.
          _hideTimer?.cancel();
          _controlsVisible = true;
        }
        setState(() {});
      }
      // media_kit can mark a new source initialized before its video output
      // reports dimensions. Rebuild when the aspect ratio arrives as well;
      // otherwise the new frame can stay hidden behind the artwork until a
      // pause or seek happens to trigger another widget update.
      if (aspectRatioChanged) setState(() {});
    }, onError: (_) {});
    _startHideTimer();
  }

  void _startHideTimer({bool reset = false}) {
    // Rebuilds, stream notifications, and duplicate hover routes must not
    // restart an already-running countdown. Only actual user activity opts in
    // to resetting it.
    if (!reset && _hideTimer?.isActive == true) return;
    _hideTimer?.cancel();
    if (!_isPlaybackPlaying && !_autoHideVideoControls) {
      // Paused playback has no idle timeout: users may need time to choose a
      // seek position or another queued item in the music/image player.
      if (!_controlsVisible && mounted) {
        setState(() => _controlsVisible = true);
      }
      return;
    }
    if (!_controlsVisible || _pointerPressed || _isLinearDragging) {
      return;
    }
    _hideTimer = Timer(const Duration(milliseconds: 2400), () {
      if (mounted &&
          _controlsVisible &&
          !_isLinearDragging &&
          !_pointerPressed) {
        setState(() {
          _controlsVisible = false;
        });
      }
    });
  }

  bool get _autoHideVideoControls =>
      ref.read(playerViewModeProvider) == PlayerViewMode.media &&
      !ref.read(cinemaModeProvider);

  void _showControlsForPointer(Offset position) {
    // The global pointer route and this player's MouseRegion both receive each
    // move. Ignore duplicate events and tiny trackpad jitter so they cannot
    // continually restart the idle timer while the pointer is effectively at
    // rest. Comparing against the last accepted position still lets gradual
    // real movement accumulate until it crosses the threshold.
    final previous = _lastPointerActivityPosition;
    if (previous != null && (position - previous).distance < 3) return;
    _lastPointerActivityPosition = position;
    if (!_pointerOverPlayer || !_controlsVisible) {
      setState(() {
        _pointerOverPlayer = true;
        _controlsVisible = true;
      });
    }
    _startHideTimer(reset: true);
  }

  void _onPointerHover() {
    if (!_controlsVisible) {
      setState(() {
        _controlsVisible = true;
      });
    }
    _startHideTimer(reset: true);
  }

  void _onControlsExit() {
    if (_pointerOverPlayer) {
      _startHideTimer();
    } else if (!_isLinearDragging && !_pointerPressed && mounted) {
      _hideTimer?.cancel();
      setState(() => _controlsVisible = false);
    }
  }

  void _onPointerDown(PointerDownEvent _) {
    _pointerPressed = true;
    _hideTimer?.cancel();
    if (!_controlsVisible) {
      setState(() => _controlsVisible = true);
    }
  }

  void _onPointerUp(PointerEvent _) {
    _pointerPressed = false;
    _startHideTimer(reset: true);
  }

  void _showCompactCinemaControls() {
    _compactCinemaHideTimer?.cancel();
    if (!_compactCinemaControlsVisible && mounted) {
      setState(() => _compactCinemaControlsVisible = true);
    }
    _compactCinemaHideTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _compactCinemaControlsVisible = false);
      }
    });
  }

  Widget _buildCinemaVideoLayer({
    required MediaItem media,
    required PlaybackSnapshot snap,
    required PlaybackEngine engine,
    bool rotateForPhone = false,
  }) {
    if (snap.initialized) {
      if (rotateForPhone) {
        return RotatedBox(
          key: _ambientVideoBoundsKey,
          quarterTurns: 1,
          child: engine.videoAspectRatio == null
              ? const SizedBox.shrink()
              : engine.buildVideoView(fit: BoxFit.cover),
        );
      }
      return Stack(
        fit: StackFit.expand,
        children: [
          // Leave space outside the source frame black instead of stretching
          // a thumbnail into a blurred, unrelated-looking backdrop.
          const Positioned.fill(child: ColoredBox(color: Colors.black)),
          Center(
            child: AspectRatio(
              key: _ambientVideoBoundsKey,
              aspectRatio: engine.videoAspectRatio ?? (16 / 9),
              child: engine.videoAspectRatio == null
                  ? const SizedBox.shrink()
                  : engine.buildVideoView(fit: BoxFit.contain),
            ),
          ),
        ],
      );
    }
    return ThumbImage(
      seed: media.id,
      mediaId: media.id,
      localPath: media.localPath,
      expand: true,
    );
  }

  Widget _cinemaMetadata(MediaItem media, {double bottom = 32}) {
    final creator = formatCreatorNames(media.artist);
    return Positioned(
      left: 28,
      bottom: bottom,
      child: IgnorePointer(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.55,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                key: const ValueKey('cinema-title'),
                displayTitle(media.title),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  shadows: [Shadow(color: Colors.black87, blurRadius: 10)],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                key: const ValueKey('cinema-creator'),
                creator.isEmpty ? ref.tr('creator_not_set') : creator,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _desktopVideoMetadata(MediaItem media) {
    final creator = formatCreatorNames(media.artist);
    return Positioned(
      bottom: 192,
      left: 32,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.55,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.58),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  key: const ValueKey('player-title'),
                  displayTitle(media.title),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    shadows: [Shadow(color: Colors.black87, blurRadius: 8)],
                  ),
                ),
                const SizedBox(height: 2),
                if (creator.isNotEmpty)
                  Tooltip(
                    message: ref.tr('search_by_creator'),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        key: const ValueKey('player-creator-search'),
                        borderRadius: BorderRadius.circular(4),
                        onTap: () =>
                            ref
                                    .read(creatorVideosRequestProvider.notifier)
                                    .state =
                                creator,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            key: const ValueKey('player-creator'),
                            creator,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              shadows: [
                                Shadow(color: Colors.black87, blurRadius: 6),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  Text(
                    key: const ValueKey('player-creator'),
                    ref.tr('creator_not_set'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      shadows: [Shadow(color: Colors.black87, blurRadius: 6)],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _videoSurface(PlaybackEngine engine, {BoxFit fit = BoxFit.contain}) {
    // Video stays as an untouched foreground surface. Ambient colors are
    // rendered only in the surrounding app canvas beneath this aperture.
    return RepaintBoundary(
      key: _ambientVideoCaptureKey,
      child: engine.buildVideoView(fit: fit),
    );
  }

  Future<ui.Image?> _captureAmbientVideoFrame() async {
    final renderObject = _ambientVideoCaptureKey.currentContext
        ?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary || !renderObject.hasSize) {
      return null;
    }
    final size = renderObject.size;
    if (size.width <= 0 || size.height <= 0) return null;
    final pixelRatio = math.min(
      1.0,
      math.min(480 / size.width, 320 / size.height),
    );
    try {
      return await renderObject.toImage(pixelRatio: pixelRatio);
    } catch (_) {
      return null;
    }
  }

  void _onSwitchMode(PlayerViewMode newMode) {
    _onPointerHover();
    ref.read(playerViewModeProvider.notifier).state = newMode;
    // mpv video track toggle: vid=auto for media, vid=no for audio-only
    final engine = ref.read(engineProvider);
    engine.setVideoTrackEnabled(newMode == PlayerViewMode.media);
  }

  Widget _playPauseGlyph(bool isPlaying, double size, Color color) =>
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 90),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, animation) =>
            FadeTransition(opacity: animation, child: child),
        child: Icon(
          isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          key: ValueKey(isPlaying),
          color: color,
          size: size,
        ),
      );

  Future<void> _saveTemporaryToLibrary(
    BuildContext context,
    MediaItem media,
  ) async {
    try {
      await ref.read(libraryProvider.notifier).saveTemporaryMedia(media.id);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(ref.tr('saved_to_library'))));
      }
    } catch (error) {
      if (context.mounted) {
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

  void _showAddToPlaylist(BuildContext context, MediaItem media) {
    final playlists = ref.read(libraryProvider).playlists;
    if (playlists.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(ref.tr('empty_playlist'))));
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Text(
                ref.tr('add_playlist'),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ),
            for (final playlist in playlists)
              ListTile(
                leading: const Icon(Icons.playlist_add_rounded),
                title: Text(displayTitle(playlist.name)),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await ref
                      .read(libraryProvider.notifier)
                      .addToPlaylist(playlist.id, media.id);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          ref
                              .tr('added_to_playlist')
                              .replaceAll(
                                '{name}',
                                displayTitle(playlist.name),
                              ),
                        ),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _pendingVideoTapTimer?.cancel();
    _compactCinemaHideTimer?.cancel();
    _sub?.cancel();
    WidgetsBinding.instance.pointerRouter.removeGlobalRoute(
      _trackGlobalMousePosition,
    );
    _clearAmbientVideoBounds();
    _engine.setAmbientFrameSource(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final availableWidth = constraints.hasBoundedWidth
          ? constraints.maxWidth
          : MediaQuery.sizeOf(context).width;
      return _buildForWidth(context, availableWidth);
    },
  );

  Widget _buildForWidth(BuildContext context, double screenWidth) {
    final q = ref.watch(queueProvider);
    final lib = ref.watch(libraryProvider);
    final engine = ref.watch(engineProvider);
    final ctl = ref.read(playbackControllerProvider);
    final mode = ref.watch(playerViewModeProvider);
    final ambientLightEnabled = ref.watch(ambientLightProvider);
    final fullPlayerView = ref.watch(viewingPlayerProvider);
    final snap = engine.snapshot;
    final media = q.currentId == null ? null : lib.byId(q.currentId!);
    if (media == null) return const SizedBox.shrink();
    final reportedAspectRatio = engine.videoAspectRatio;
    final hasValidVideoAspectRatio =
        reportedAspectRatio != null &&
        reportedAspectRatio.isFinite &&
        reportedAspectRatio > 0;
    final videoAspectRatio = hasValidVideoAspectRatio
        ? reportedAspectRatio
        : (16 / 9);
    final videoLayoutWidth = screenWidth;
    // The player lives inside the center pane, which is already narrower than
    // the window when the sidebar and queue are open. Keep the desktop layout
    // until that actual pane can no longer fit its toolbar and transport row.
    final isCompact = screenWidth < 760;
    final isUltraCompact = screenWidth < 380;
    final previousNextIconSize = isUltraCompact
        ? 24.0
        : (isCompact ? 28.0 : 34.0);
    // Preserve the desktop proportion (60px play glyph to 34px skip glyph)
    // at every responsive size so the primary action remains visually primary.
    final playPauseIconSize = previousNextIconSize * 60 / 34;
    final isCinema = ref.watch(cinemaModeProvider);
    final useVideoOverlay = mode == PlayerViewMode.media && !isCinema;
    engine.setAmbientFrameSource(
      useVideoOverlay ? _captureAmbientVideoFrame : null,
    );
    if (snap.initialized && mode == PlayerViewMode.media && !isCinema) {
      _reportAmbientVideoBounds();
    } else {
      _ambientBoundsNeeded = false;
      if (_lastAmbientAperture != null && !_ambientBoundsReportScheduled) {
        _ambientBoundsReportScheduled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _ambientBoundsReportScheduled = false;
          if (!mounted) return;
          if (_ambientBoundsNeeded) {
            _reportAmbientVideoBounds();
          } else {
            _clearAmbientVideoBounds();
          }
        });
      }
    }

    if (isCompact) {
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          final scale = Tween<double>(begin: 0.9, end: 1).animate(animation);
          return ClipRect(
            child: FadeTransition(
              opacity: animation,
              child: ScaleTransition(scale: scale, child: child),
            ),
          );
        },
        child: isCinema
            ? _buildCompactCinemaPlayer(
                context,
                key: const ValueKey('compact-cinema'),
                media: media,
                snap: snap,
                mode: mode,
                engine: engine,
              )
            : _buildCompactPlayer(
                context,
                key: const ValueKey('compact-player'),
                media: media,
                snap: snap,
                mode: mode,
                ctl: ctl,
                q: q,
                lib: lib,
                engine: engine,
              ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = themeTextPrimary(context);
    final textSub = themeTextSub(context);
    final playerTextPrimary = useVideoOverlay ? Colors.white : textPrimary;
    final playerTextSub = useVideoOverlay ? Colors.white70 : textSub;
    final transportIconColor = useVideoOverlay
        ? Colors.white70
        : (isDark ? const Color(0xFFA9A9A9) : const Color(0xFF5D5D5D));
    final playIconColor = transportIconColor;
    return MouseRegion(
      key: _playerHoverBoundsKey,
      // Hide the cursor only with the same idle state that hides the video
      // controls; movement reveals both together so the cursor cannot linger
      // over an otherwise clean playback frame.
      cursor: _controlsVisible
          ? SystemMouseCursors.basic
          : SystemMouseCursors.none,
      // Do not reveal on enter alone: on macOS this may be synthesized when
      // the window/widget appears beneath a stationary cursor. Actual pointer
      // movement arrives through onHover and the global pointer route.
      onHover: (event) {
        if (mounted) _showControlsForPointer(event.position);
      },
      onExit: (_) {
        if (mounted) {
          _hideTimer?.cancel();
          // A release can be swallowed when the pointer exits through an
          // overlapping pane. Leaving the player ends ordinary press state;
          // active seek drags remain tracked separately.
          _pointerPressed = false;
          setState(() {
            _pointerOverPlayer = false;
            _lastPointerActivityPosition = null;
            if (!_isLinearDragging) {
              _controlsVisible = false;
            }
          });
        }
      },
      child: Listener(
        onPointerDown: _onPointerDown,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerUp,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Main Visual Layer (Video or Artwork with smooth cross-fade animation)
            // Also supports two-finger/mouse linear horizontal drag to scrub through video seamlessly
            Positioned.fill(
              child: Padding(
                padding: isCinema
                    ? EdgeInsets.zero
                    : EdgeInsets.fromLTRB(
                        isCompact ? 16 : 32,
                        isCompact ? 68 : 80,
                        isCompact ? 16 : 32,
                        isCompact ? 120 : 150,
                      ),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (details) {
                    _onPointerHover();
                    _isLinearDragging = true;
                    _dragAccumulatedDelta = 0.0;
                    _dragStartPos = engine.snapshot.position;
                  },
                  onHorizontalDragUpdate: (details) {
                    _onPointerHover();
                    _dragAccumulatedDelta += details.delta.dx;
                    final dur = engine.snapshot.duration;
                    if (dur.inMilliseconds > 0 && videoLayoutWidth > 0) {
                      // Scale the drag to total duration so the same gesture
                      // covers a comparable fraction of short clips and
                      // feature-length videos on any center-pane width.
                      final dragFraction =
                          _dragAccumulatedDelta / videoLayoutWidth;
                      final deltaMs = (dragFraction * dur.inMilliseconds)
                          .round();
                      final targetMs = (_dragStartPos.inMilliseconds + deltaMs)
                          .clamp(0, dur.inMilliseconds);
                      ctl.seekTo(Duration(milliseconds: targetMs));
                    }
                  },
                  onHorizontalDragEnd: (details) {
                    _isLinearDragging = false;
                    _startHideTimer(reset: true);
                  },
                  onTap: () {
                    // Delay the single-tap action just beyond Flutter's
                    // double-tap recognition window so the first tap of a
                    // fullscreen gesture cannot also pause the video.
                    _pendingVideoTapTimer?.cancel();
                    _pendingVideoTapTimer = Timer(
                      const Duration(milliseconds: 330),
                      () {
                        if (!mounted) return;
                        if (isCompact) {
                          // Touch layouts keep the seek and transport controls
                          // visible; tapping the video must not hide them.
                        } else {
                          _onPointerHover();
                          ctl.toggle();
                        }
                      },
                    );
                  },
                  onDoubleTap: () {
                    _pendingVideoTapTimer?.cancel();
                    ref.read(cinemaModeProvider.notifier).state = !ref.read(
                      cinemaModeProvider,
                    );
                  },
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    switchInCurve: Curves.easeInOut,
                    switchOutCurve: Curves.easeInOut,
                    child: mode == PlayerViewMode.media
                        ? SizedBox.expand(
                            key: const ValueKey('player-mode-media'),
                            child: isCinema
                                ? _buildCinemaVideoLayer(
                                    media: media,
                                    snap: snap,
                                    engine: engine,
                                    rotateForPhone:
                                        isCompact &&
                                        MediaQuery.sizeOf(context).height >
                                            screenWidth,
                                  )
                                : FittedBox(
                                    fit: isCinema
                                        ? BoxFit.cover
                                        : BoxFit.contain,
                                    clipBehavior: Clip.none,
                                    child: SizedBox(
                                      width: videoLayoutWidth,
                                      height:
                                          videoLayoutWidth / videoAspectRatio,
                                      child: Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          Container(
                                            key: _ambientVideoBoundsKey,
                                            decoration: BoxDecoration(
                                              color: Colors.black,
                                              borderRadius: isCinema
                                                  ? BorderRadius.zero
                                                  : BorderRadius.circular(20),
                                              boxShadow:
                                                  isCinema ||
                                                      ambientLightEnabled
                                                  ? null
                                                  : [
                                                      BoxShadow(
                                                        color: Colors.black
                                                            .withValues(
                                                              alpha: isDark
                                                                  ? 0.7
                                                                  : 0.2,
                                                            ),
                                                        blurRadius: 40,
                                                        offset: const Offset(
                                                          0,
                                                          14,
                                                        ),
                                                      ),
                                                    ],
                                            ),
                                            // Preserve one fine outline so
                                            // the video remains distinct from
                                            // its blurred ambient spill.
                                            foregroundDecoration:
                                                ambientLightEnabled && !isCinema
                                                ? BoxDecoration(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          20,
                                                        ),
                                                    border: Border.all(
                                                      // The player itself is
                                                      // dark even in light UI;
                                                      // use a light keyline in
                                                      // both themes so the
                                                      // video/glow boundary
                                                      // stays visible.
                                                      color: Colors.white
                                                          .withValues(
                                                            alpha: 0.16,
                                                          ),
                                                      width: 1,
                                                    ),
                                                  )
                                                : null,
                                            clipBehavior: Clip.antiAlias,
                                            child: snap.initialized
                                                ? Stack(
                                                    fit: StackFit.expand,
                                                    children: [
                                                      if (hasValidVideoAspectRatio)
                                                        const ColoredBox(
                                                          color: Colors.black,
                                                        )
                                                      else
                                                        ThumbImage(
                                                          seed: media.id,
                                                          mediaId: media.id,
                                                          localPath:
                                                              media.localPath,
                                                          expand: true,
                                                        ),
                                                      if (hasValidVideoAspectRatio)
                                                        _videoSurface(engine),
                                                    ],
                                                  )
                                                : Stack(
                                                    fit: StackFit.expand,
                                                    children: [
                                                      ThumbImage(
                                                        seed: media.id,
                                                        mediaId: media.id,
                                                        localPath:
                                                            media.localPath,
                                                        expand: true,
                                                      ),
                                                      Container(
                                                        color: Colors.black45,
                                                        child: Column(
                                                          mainAxisAlignment:
                                                              MainAxisAlignment
                                                                  .center,
                                                          children: [
                                                            CircularProgressIndicator(
                                                              strokeWidth: 3,
                                                            ),
                                                            SizedBox(
                                                              height: 14,
                                                            ),
                                                            Text(
                                                              ref.tr('loading'),
                                                              style: TextStyle(
                                                                fontSize: 13,
                                                                color: Colors
                                                                    .white70,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                          )
                        : Center(
                            key: const ValueKey('player-mode-image'),
                            child: AspectRatio(
                              // Artwork is presented as a square sleeve;
                              // video mode keeps the video's own frame ratio.
                              aspectRatio: 1,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: themeCard(context),
                                  borderRadius: BorderRadius.circular(24),
                                  // Ambient light already gives the sleeve a
                                  // soft separation from the room. The usual
                                  // heavy drop shadow reads as a thin second
                                  // outline against that moving background.
                                  boxShadow: ambientLightEnabled
                                      ? const []
                                      : [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: isDark ? 0.6 : 0.15,
                                            ),
                                            blurRadius: 48,
                                            spreadRadius: 4,
                                            offset: const Offset(0, 16),
                                          ),
                                        ],
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Stack(
                                  children: [
                                    Center(
                                      child: Container(
                                        width: 72,
                                        height: 72,
                                        decoration: BoxDecoration(
                                          color: Colors.black,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        child: Image.asset(
                                          'assets/yureru_logo.png',
                                          fit: BoxFit.contain,
                                        ),
                                      ),
                                    ),
                                    ThumbImage(
                                      seed: media.id,
                                      mediaId: media.id,
                                      localPath: media.localPath,
                                      radius: 0,
                                      expand: true,
                                      highRes: true,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ),

            if (isCinema)
              _cinemaMetadata(media)
            else if (useVideoOverlay && !isCompact)
              _desktopVideoMetadata(media),

            // 3. Top Floating Capsule: Collapse Button + Media / Image Mode Switcher (or pure cinema exit button)
            Positioned(
              top: 14,
              left: 16 + widget.leadingChromeInset,
              right: 16 + widget.trailingChromeInset,
              child: MouseRegion(
                onExit: (_) => _onControlsExit(),
                child: IgnorePointer(
                  ignoring: !(isCinema
                      ? _pointerOverPlayer
                      : useVideoOverlay
                      ? _controlsVisible
                      : _controlsVisible),
                  child: ExcludeSemantics(
                    excluding: !(isCinema
                        ? _pointerOverPlayer
                        : useVideoOverlay
                        ? _controlsVisible
                        : _controlsVisible),
                    child: AnimatedOpacity(
                      // In cinema mode, reveal the exit affordance only while
                      // the pointer is over the player. Touch layouts keep
                      // their always-visible exit button below.
                      opacity:
                          (isCinema
                              ? _pointerOverPlayer
                              : useVideoOverlay
                              ? _controlsVisible
                              : _controlsVisible)
                          ? 1.0
                          : 0.0,
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeInOut,
                      child: isCinema
                          ? Align(
                              alignment: Alignment.topRight,
                              child: ClipOval(
                                child: BackdropFilter(
                                  filter: ui.ImageFilter.blur(
                                    sigmaX: 18,
                                    sigmaY: 18,
                                  ),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isDark
                                          ? const Color(0xFFE2E2E2)
                                          : const Color(0xFF232323),
                                      border: Border.all(
                                        color: isDark
                                            ? Colors.white.withValues(
                                                alpha: 0.2,
                                              )
                                            : Colors.black.withValues(
                                                alpha: 0.15,
                                              ),
                                        width: 1,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: 0.5,
                                          ),
                                          blurRadius: 16,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: IconButton(
                                      tooltip:
                                          '${ref.tr('close_fullscreen')} (Esc)',
                                      icon: const Icon(
                                        Icons.fullscreen_exit_rounded,
                                        size: 26,
                                      ),
                                      color: isDark
                                          ? const Color(0xFF353535)
                                          : Colors.white,
                                      onPressed: () {
                                        _onPointerHover();
                                        ref
                                                .read(
                                                  cinemaModeProvider.notifier,
                                                )
                                                .state =
                                            false;
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // Collapse / Back to library button (especially important for mobile/narrow view)
                                ClipOval(
                                  child: BackdropFilter(
                                    filter: ui.ImageFilter.blur(
                                      sigmaX: 18,
                                      sigmaY: 18,
                                    ),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isDark
                                            ? Colors.black.withValues(
                                                alpha: 0.5,
                                              )
                                            : Colors.white.withValues(
                                                alpha: 0.85,
                                              ),
                                        border: Border.all(
                                          color: themeBorder(context),
                                          width: 1,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: isDark ? 0.3 : 0.1,
                                            ),
                                            blurRadius: 16,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: IconButton(
                                        tooltip: ref.tr('library'),
                                        icon: const Icon(
                                          Icons.keyboard_arrow_down_rounded,
                                          size: 26,
                                        ),
                                        color: textPrimary,
                                        onPressed: () {
                                          ref
                                                  .read(
                                                    viewingPlayerProvider
                                                        .notifier,
                                                  )
                                                  .state =
                                              false;
                                          ref
                                                  .read(
                                                    queueVisibleProvider
                                                        .notifier,
                                                  )
                                                  .state =
                                              false;
                                        },
                                      ),
                                    ),
                                  ),
                                ),

                                // Media / Image Mode Switcher capsule
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(24),
                                  child: BackdropFilter(
                                    filter: ui.ImageFilter.blur(
                                      sigmaX: 18,
                                      sigmaY: 18,
                                    ),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? Colors.black.withValues(
                                                alpha: 0.5,
                                              )
                                            : Colors.white.withValues(
                                                alpha: 0.85,
                                              ),
                                        borderRadius: BorderRadius.circular(24),
                                        border: Border.all(
                                          color: themeBorder(context),
                                          width: 1,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: isDark ? 0.3 : 0.1,
                                            ),
                                            blurRadius: 20,
                                            offset: const Offset(0, 6),
                                          ),
                                        ],
                                      ),
                                      padding: const EdgeInsets.all(4),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _ModeButton(
                                            label: ref.tr('media'),
                                            icon: Icons.smart_display_rounded,
                                            selected:
                                                mode == PlayerViewMode.media,
                                            onTap: () => _onSwitchMode(
                                              PlayerViewMode.media,
                                            ),
                                          ),
                                          _ModeButton(
                                            label: ref.tr('image'),
                                            icon: Icons.image_rounded,
                                            selected:
                                                mode == PlayerViewMode.image,
                                            onTap: () => _onSwitchMode(
                                              PlayerViewMode.image,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),

                                const SleepTimerButton(),
                                FavoriteButton(mediaId: media.id),
                                Tooltip(
                                  message: ref.tr('immersive'),
                                  child: TextButton.icon(
                                    label: Text(ref.tr('immersive')),
                                    icon: const AppSvgIcon('immersive'),
                                    onPressed: () =>
                                        ref
                                                .read(
                                                  immersiveModeProvider
                                                      .notifier,
                                                )
                                                .state =
                                            true,
                                  ),
                                ),
                                // Complete big screen / Cinema mode toggle button
                                ClipOval(
                                  child: BackdropFilter(
                                    filter: ui.ImageFilter.blur(
                                      sigmaX: 18,
                                      sigmaY: 18,
                                    ),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: isDark
                                            ? Colors.black.withValues(
                                                alpha: 0.5,
                                              )
                                            : Colors.white.withValues(
                                                alpha: 0.85,
                                              ),
                                        border: Border.all(
                                          color: themeBorder(context),
                                          width: 1,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: isDark ? 0.3 : 0.1,
                                            ),
                                            blurRadius: 16,
                                            offset: const Offset(0, 4),
                                          ),
                                        ],
                                      ),
                                      child: IconButton(
                                        tooltip: ref.tr('fullscreen_video'),
                                        icon: const Icon(
                                          Icons.fullscreen_rounded,
                                          size: 24,
                                        ),
                                        color: textPrimary,
                                        onPressed: () {
                                          _onPointerHover();
                                          ref
                                                  .read(
                                                    cinemaModeProvider.notifier,
                                                  )
                                                  .state =
                                              true;
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ),

            // 4. Bottom Floating IINA-style Frosted Glass OSC (On Screen Controller)
            // Hidden when in pure cinema mode so nothing blocks the video
            if (isCinema)
              Positioned(
                bottom: 30,
                left: 24,
                right: 24,
                child: MouseRegion(
                  onExit: (_) => _onControlsExit(),
                  child: IgnorePointer(
                    ignoring: !_pointerOverPlayer,
                    child: AnimatedOpacity(
                      opacity: _pointerOverPlayer ? 1 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.48),
                            borderRadius: BorderRadius.circular(32),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.12),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              PlaybackShuffleButton(
                                activeColor: Colors.white70,
                                inactiveColor: Colors.white70,
                              ),
                              IconButton(
                                tooltip: ref.tr('prev_video'),
                                icon: TransportIcon.previous(
                                  size: 26,
                                  color: Colors.white,
                                ),
                                onPressed: q.hasCurrent ? ctl.playPrev : null,
                              ),
                              StreamBuilder<bool>(
                                stream: engine.playingStream,
                                initialData: engine.snapshot.isPlaying,
                                builder: (context, state) => IconButton(
                                  tooltip: ref.tr(
                                    state.data == true ? 'pause' : 'play',
                                  ),
                                  iconSize: 42,
                                  color: Colors.white,
                                  onPressed: q.hasCurrent ? ctl.toggle : null,
                                  icon: Icon(
                                    state.data == true
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: ref.tr('next_video'),
                                icon: SkipNextIcon(
                                  size: 26,
                                  color: Colors.white,
                                ),
                                onPressed: q.hasCurrent ? ctl.playNext : null,
                              ),
                              PlaybackRepeatButton(
                                activeColor: Colors.white70,
                                inactiveColor: Colors.white70,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (!isCinema)
              Positioned(
                bottom: isCompact ? 10 : 34,
                left: isCompact ? 10 : 24,
                right: isCompact ? 10 : 24,
                child: MouseRegion(
                  onExit: (_) => _onControlsExit(),
                  child: AnimatedOpacity(
                    key: useVideoOverlay
                        ? const ValueKey('player-hover-transport')
                        : null,
                    opacity: useVideoOverlay
                        ? (_controlsVisible ? 1.0 : 0.0)
                        : (_controlsVisible ? 1.0 : 0.0),
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeInOut,
                    child: IgnorePointer(
                      ignoring: useVideoOverlay
                          ? !_controlsVisible
                          : !_controlsVisible,
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: useVideoOverlay ? double.infinity : 660,
                          ),
                          child: SizedBox(
                            width: useVideoOverlay ? double.infinity : null,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(
                                isCompact ? 18 : 22,
                              ),
                              child: BackdropFilter(
                                filter: ui.ImageFilter.blur(
                                  sigmaX: isCompact ? 22 : (isDark ? 48 : 36),
                                  sigmaY: isCompact ? 22 : (isDark ? 48 : 36),
                                ),
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: isCompact ? 12 : 20,
                                    vertical: isCompact ? 10 : 12,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isCompact
                                        ? (isDark
                                              ? const Color(0x73181822)
                                              : Colors.white.withValues(
                                                  alpha: 0.88,
                                                ))
                                        : (isDark
                                              ? const Color(0x704B4B52)
                                              : Colors.white.withValues(
                                                  alpha: 0.24,
                                                )),
                                    gradient: !isCompact && isDark
                                        ? const LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              Color(0x2AFFFFFF),
                                              Color(0x12FFFFFF),
                                              Color(0x08000000),
                                            ],
                                          )
                                        : null,
                                    borderRadius: BorderRadius.circular(
                                      isCompact ? 18 : 22,
                                    ),
                                    border: Border.all(
                                      color: isDark
                                          ? Colors.white.withValues(alpha: 0.17)
                                          : themeBorder(context),
                                      width: 1,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: isDark ? 0.55 : 0.15,
                                        ),
                                        blurRadius: 32,
                                        offset: const Offset(0, 10),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Prominent Music Track Info & Artwork Pill
                                      if (!useVideoOverlay)
                                        Padding(
                                          padding: EdgeInsets.fromLTRB(
                                            isCompact ? 2 : 6,
                                            2,
                                            isCompact ? 2 : 6,
                                            isCompact ? 4 : 8,
                                          ),
                                          child: Row(
                                            children: [
                                              Container(
                                                decoration: BoxDecoration(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors.black
                                                          .withValues(
                                                            alpha: isDark
                                                                ? 0.35
                                                                : 0.15,
                                                          ),
                                                      blurRadius: 6,
                                                      offset: const Offset(
                                                        0,
                                                        2,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                child: ThumbImage(
                                                  seed: media.id,
                                                  mediaId: media.id,
                                                  localPath: media.localPath,
                                                  size: isCompact ? 36 : 42,
                                                  radius: 8,
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      displayTitle(media.title),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        fontSize: isCompact
                                                            ? 13.5
                                                            : 15,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color:
                                                            playerTextPrimary,
                                                        letterSpacing: -0.2,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    if (media.artist
                                                            ?.trim()
                                                            .isNotEmpty ==
                                                        true)
                                                      InkWell(
                                                        onTap: () =>
                                                            ref
                                                                    .read(
                                                                      creatorVideosRequestProvider
                                                                          .notifier,
                                                                    )
                                                                    .state =
                                                                formatCreatorNames(
                                                                  media.artist,
                                                                ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              4,
                                                            ),
                                                        child: Text(
                                                          formatCreatorNames(
                                                            media.artist,
                                                          ),
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: TextStyle(
                                                            fontSize: isCompact
                                                                ? 11
                                                                : 12,
                                                            fontWeight:
                                                                FontWeight.w500,
                                                            color:
                                                                playerTextSub,
                                                          ),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              // Expandable volume slider
                                              _ExpandableVolume(
                                                onHoverActivity:
                                                    _onPointerHover,
                                              ),
                                              const SizedBox(width: 6),
                                              // Speed Indicator Pill
                                              _PlayerSpeedButton(
                                                speed: q.speed,
                                                tooltip: ref.tr(
                                                  'playback_speed',
                                                ),
                                                onSelected: (s) =>
                                                    ctl.setSpeed(s),
                                              ),
                                            ],
                                          ),
                                        ),
                                      // Floating Timeline Slider with Bubble Preview
                                      if (useVideoOverlay || !fullPlayerView)
                                        _FloatingTimeline(
                                          desktop: !isCompact,
                                          onHoverActivity: _onPointerHover,
                                        ),
                                      // In full-player jacket mode, the shell's
                                      // bottom TransportBar is the single
                                      // transport surface. Keep this in-card
                                      // row for video hover controls and
                                      // non-full-player layouts only.
                                      if (useVideoOverlay || !fullPlayerView)
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            // Shuffle
                                            IconButton(
                                              padding: EdgeInsets.all(
                                                isUltraCompact
                                                    ? 4
                                                    : (isCompact ? 8 : 10),
                                              ),
                                              constraints: isUltraCompact
                                                  ? const BoxConstraints()
                                                  : null,
                                              tooltip: ref.tr('shuffle'),
                                              icon: TransportIcon.shuffle(
                                                size: isUltraCompact
                                                    ? 18
                                                    : (isCompact ? 20 : 22),
                                                color: transportIconColor,
                                              ),
                                              onPressed: () {
                                                _onPointerHover();
                                                ref
                                                    .read(
                                                      queueProvider.notifier,
                                                    )
                                                    .toggleShuffle();
                                              },
                                            ),
                                            SizedBox(
                                              width: isUltraCompact
                                                  ? 6
                                                  : (isCompact ? 10 : 12),
                                            ),

                                            // Prev
                                            IconButton(
                                              padding: EdgeInsets.all(
                                                isUltraCompact
                                                    ? 4
                                                    : (isCompact ? 8 : 10),
                                              ),
                                              constraints: isUltraCompact
                                                  ? const BoxConstraints()
                                                  : null,
                                              tooltip: ref.tr('prev_video'),
                                              icon: TransportIcon.previous(
                                                size: previousNextIconSize,
                                                color: transportIconColor,
                                              ),
                                              onPressed: () {
                                                _onPointerHover();
                                                ctl.playPrev();
                                              },
                                            ),
                                            SizedBox(
                                              width: isUltraCompact
                                                  ? 6
                                                  : (isCompact ? 10 : 12),
                                            ),

                                            // Center Play / Pause button
                                            Material(
                                              color: isCompact
                                                  ? (isDark
                                                        ? Colors.white
                                                        : const Color(
                                                            0xFF2B2B2B,
                                                          ))
                                                  : Colors.transparent,
                                              shape: const CircleBorder(),
                                              elevation: isCompact ? 6 : 0,
                                              child: InkWell(
                                                customBorder:
                                                    const CircleBorder(),
                                                onTap: () {
                                                  _onPointerHover();
                                                  ctl.toggle();
                                                },
                                                child: Padding(
                                                  padding: EdgeInsets.all(
                                                    isUltraCompact
                                                        ? 8
                                                        : (isCompact ? 10 : 18),
                                                  ),
                                                  child: _playPauseGlyph(
                                                    snap.isPlaying,
                                                    playPauseIconSize,
                                                    playIconColor,
                                                  ),
                                                ),
                                              ),
                                            ),
                                            SizedBox(
                                              width: isUltraCompact
                                                  ? 6
                                                  : (isCompact ? 10 : 12),
                                            ),

                                            // Next
                                            IconButton(
                                              padding: EdgeInsets.all(
                                                isUltraCompact
                                                    ? 4
                                                    : (isCompact ? 8 : 10),
                                              ),
                                              constraints: isUltraCompact
                                                  ? const BoxConstraints()
                                                  : null,
                                              tooltip: ref.tr('next_video'),
                                              icon: SkipNextIcon(
                                                size: previousNextIconSize,
                                                color: transportIconColor,
                                              ),
                                              onPressed: () {
                                                _onPointerHover();
                                                ctl.playNext();
                                              },
                                            ),
                                            SizedBox(
                                              width: isUltraCompact
                                                  ? 6
                                                  : (isCompact ? 10 : 12),
                                            ),

                                            // Repeat
                                            IconButton(
                                              padding: EdgeInsets.all(
                                                isUltraCompact
                                                    ? 4
                                                    : (isCompact ? 8 : 10),
                                              ),
                                              constraints: isUltraCompact
                                                  ? const BoxConstraints()
                                                  : null,
                                              tooltip: q.repeat == 'one'
                                                  ? ref.tr('repeat_one')
                                                  : (q.repeat == 'off'
                                                        ? ref.tr('repeat_off')
                                                        : ref.tr('repeat_all')),
                                              icon: RepeatIcon(
                                                size: isUltraCompact
                                                    ? 18
                                                    : (isCompact ? 20 : 22),
                                                color: transportIconColor,
                                                repeatMode: q.repeat,
                                              ),
                                              onPressed: () {
                                                _onPointerHover();
                                                ref
                                                    .read(
                                                      queueProvider.notifier,
                                                    )
                                                    .cycleRepeat();
                                              },
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
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
    );
  }

  Widget _buildCompactCinemaPlayer(
    BuildContext context, {
    Key? key,
    required MediaItem media,
    required PlaybackSnapshot snap,
    required PlayerViewMode mode,
    required PlaybackEngine engine,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final queue = ref.watch(queueProvider);
    final controller = ref.read(playbackControllerProvider);
    return Scaffold(
      key: key,
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _showCompactCinemaControls,
        child: Stack(
          fit: StackFit.expand,
          children: [
            mode == PlayerViewMode.media
                ? Positioned.fill(
                    child: _buildCinemaVideoLayer(
                      media: media,
                      snap: snap,
                      engine: engine,
                      rotateForPhone:
                          MediaQuery.sizeOf(context).height >
                          MediaQuery.sizeOf(context).width,
                    ),
                  )
                : Center(
                    child: AspectRatio(
                      aspectRatio: engine.videoAspectRatio ?? (16 / 9),
                      child: ThumbImage(
                        seed: media.id,
                        mediaId: media.id,
                        localPath: media.localPath,
                        expand: true,
                        highRes: true,
                      ),
                    ),
                  ),
            _cinemaMetadata(media, bottom: 112),
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              right: 12,
              child: IgnorePointer(
                ignoring: !_compactCinemaControlsVisible,
                child: ExcludeSemantics(
                  excluding: !_compactCinemaControlsVisible,
                  child: AnimatedOpacity(
                    opacity: _compactCinemaControlsVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Material(
                      color: isDark ? Colors.white : const Color(0xFF232323),
                      shape: const CircleBorder(),
                      elevation: 4,
                      child: IconButton(
                        tooltip: ref.tr('restore_window'),
                        icon: const Icon(Icons.fullscreen_exit_rounded),
                        color: isDark ? const Color(0xFF181818) : Colors.white,
                        onPressed: () {
                          ref.read(cinemaModeProvider.notifier).state = false;
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: MediaQuery.paddingOf(context).bottom + 24,
              child: IgnorePointer(
                ignoring: !_compactCinemaControlsVisible,
                child: ExcludeSemantics(
                  excluding: !_compactCinemaControlsVisible,
                  child: AnimatedOpacity(
                    opacity: _compactCinemaControlsVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.48),
                          borderRadius: BorderRadius.circular(32),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            PlaybackShuffleButton(
                              activeColor: Colors.white,
                              inactiveColor: Colors.white60,
                            ),
                            IconButton(
                              tooltip: ref.tr('prev_video'),
                              icon: TransportIcon.previous(
                                size: 26,
                                color: Colors.white,
                              ),
                              onPressed: queue.hasCurrent
                                  ? controller.playPrev
                                  : null,
                            ),
                            StreamBuilder<bool>(
                              stream: engine.playingStream,
                              initialData: engine.snapshot.isPlaying,
                              builder: (context, state) => IconButton(
                                tooltip: ref.tr(
                                  state.data == true ? 'pause' : 'play',
                                ),
                                iconSize: 42,
                                color: Colors.white,
                                onPressed: queue.hasCurrent
                                    ? controller.toggle
                                    : null,
                                icon: Icon(
                                  state.data == true
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: ref.tr('next_video'),
                              icon: SkipNextIcon(size: 26, color: Colors.white),
                              onPressed: queue.hasCurrent
                                  ? controller.playNext
                                  : null,
                            ),
                            PlaybackRepeatButton(
                              activeColor: Colors.white,
                              inactiveColor: Colors.white60,
                            ),
                          ],
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
    );
  }

  Widget _buildCompactPlayer(
    BuildContext context, {
    Key? key,
    required MediaItem media,
    required PlaybackSnapshot snap,
    required PlayerViewMode mode,
    required PlaybackController ctl,
    required QueueState q,
    required LibraryState lib,
    required PlaybackEngine engine,
  }) {
    final showQueue = ref.watch(queueVisibleProvider);
    final lockQueueOpen = LayoutMetrics.isLargeDesktop(context);
    final windowWidth = MediaQuery.sizeOf(context).width;
    final isNarrowWindow = windowWidth < 1000;
    final isPhoneSize = windowWidth < 600;
    final showQueueSheet = showQueue && isNarrowWindow;
    final useVideoOverlay = mode == PlayerViewMode.media;
    // Compact layouts are touch-first: keep the transport and seek bar visible
    // instead of relying on hover, which mobile devices do not have.
    final keepVideoControlsVisible = useVideoOverlay;
    final ambientLightEnabled = ref.watch(ambientLightProvider);
    final fullPlayerView = ref.watch(viewingPlayerProvider);
    final title = displayTitle(media.title);
    final artist = formatCreatorNames(media.artist);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = themeTextPrimary(context);
    final textSub = themeTextSub(context);
    final transportArrowColor = isDark
        ? const Color(0xFFA9A9A9)
        : const Color(0xFF5D5D5D);
    final playIconColor = transportArrowColor;
    final compactPlayPauseSize = (MediaQuery.sizeOf(context).width * 0.14)
        .clamp(48.0, 56.0)
        .toDouble();
    final compactSkipSize = compactPlayPauseSize * 34 / 60;

    return MouseRegion(
      key: _playerHoverBoundsKey,
      cursor: useVideoOverlay && !_controlsVisible && !keepVideoControlsVisible
          ? SystemMouseCursors.none
          : SystemMouseCursors.basic,
      onHover: (event) {
        if (useVideoOverlay && mounted) {
          _showControlsForPointer(event.position);
        }
      },
      onExit: (_) {
        if (!useVideoOverlay || !mounted) return;
        _hideTimer?.cancel();
        _pointerOverPlayer = false;
        _lastPointerActivityPosition = null;
        if (!_isLinearDragging) setState(() => _controlsVisible = false);
      },
      child: Scaffold(
        key: key,
        backgroundColor: ambientLightEnabled
            ? Colors.transparent
            : Theme.of(context).scaffoldBackgroundColor,
        body: Stack(
          children: [
            // Keep the tap-away layer behind playback controls. The queue sheet
            // itself remains above them, while controls outside it stay usable.
            if (showQueueSheet)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    ref.read(queueVisibleProvider.notifier).state = false;
                    setState(() => _queueSheetExpanded = false);
                  },
                  child: const SizedBox.expand(),
                ),
              ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: IntrinsicHeight(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // 1. Top Bar: Down arrow (collapse) and Options
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              child: SizedBox(
                                height: 48,
                                child: LayoutBuilder(
                                  builder: (context, toolbarConstraints) {
                                    final narrowToolbar =
                                        toolbarConstraints.maxWidth < 360;
                                    return Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        IconButton(
                                          icon: const Icon(
                                            Icons.keyboard_arrow_down_rounded,
                                            size: 30,
                                          ),
                                          color: textPrimary,
                                          tooltip: ref.tr('library'),
                                          onPressed: () {
                                            ref
                                                    .read(
                                                      viewingPlayerProvider
                                                          .notifier,
                                                    )
                                                    .state =
                                                false;
                                            ref
                                                    .read(
                                                      queueVisibleProvider
                                                          .notifier,
                                                    )
                                                    .state =
                                                false;
                                          },
                                        ),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            // Mode switcher (media / image)
                                            IconButton(
                                              icon: Icon(
                                                mode == PlayerViewMode.media
                                                    ? Icons.image_rounded
                                                    : Icons
                                                          .smart_display_rounded,
                                                size: 22,
                                                color: textPrimary,
                                              ),
                                              tooltip:
                                                  mode == PlayerViewMode.media
                                                  ? ref.tr('image_mode')
                                                  : ref.tr('video_mode'),
                                              onPressed: () {
                                                _onSwitchMode(
                                                  mode == PlayerViewMode.media
                                                      ? PlayerViewMode.image
                                                      : PlayerViewMode.media,
                                                );
                                              },
                                            ),
                                            if (!narrowToolbar)
                                              IconButton(
                                                tooltip: ref.tr('immersive'),
                                                icon: const AppSvgIcon(
                                                  'immersive',
                                                ),
                                                onPressed: () =>
                                                    ref
                                                            .read(
                                                              immersiveModeProvider
                                                                  .notifier,
                                                            )
                                                            .state =
                                                        true,
                                              ),
                                            // Fullscreen / Cinema mode button
                                            if (!narrowToolbar)
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.fullscreen_rounded,
                                                  size: 24,
                                                ),
                                                color: textPrimary,
                                                tooltip:
                                                    '${ref.tr('fullscreen')} (F)',
                                                onPressed: () {
                                                  ref
                                                          .read(
                                                            cinemaModeProvider
                                                                .notifier,
                                                          )
                                                          .state =
                                                      true;
                                                },
                                              ),
                                            // Queue visibility is controlled by the
                                            // responsive content panel, not a separate
                                            // queue button in the player toolbar.
                                            PopupMenuButton<String>(
                                              icon: Icon(
                                                Icons.more_vert_rounded,
                                                size: 24,
                                                color: textPrimary,
                                              ),
                                              color: themePanelSolid(context),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                                side: BorderSide(
                                                  color: themeBorder(context),
                                                ),
                                              ),
                                              onSelected: (val) {
                                                if (val == 'add_to_playlist') {
                                                  _showAddToPlaylist(
                                                    context,
                                                    media,
                                                  );
                                                } else if (val ==
                                                    'save_to_library') {
                                                  unawaited(
                                                    _saveTemporaryToLibrary(
                                                      context,
                                                      media,
                                                    ),
                                                  );
                                                } else if (val == 'immersive') {
                                                  ref
                                                          .read(
                                                            immersiveModeProvider
                                                                .notifier,
                                                          )
                                                          .state =
                                                      true;
                                                } else if (val ==
                                                    'fullscreen') {
                                                  ref
                                                          .read(
                                                            cinemaModeProvider
                                                                .notifier,
                                                          )
                                                          .state =
                                                      true;
                                                }
                                              },
                                              itemBuilder: (ctx) => [
                                                if (narrowToolbar) ...[
                                                  PopupMenuItem(
                                                    value: 'immersive',
                                                    child: Row(
                                                      children: [
                                                        const AppSvgIcon(
                                                          'immersive',
                                                        ),
                                                        const SizedBox(
                                                          width: 10,
                                                        ),
                                                        Text(
                                                          ref.tr('immersive'),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  PopupMenuItem(
                                                    value: 'fullscreen',
                                                    child: Row(
                                                      children: [
                                                        const Icon(
                                                          Icons
                                                              .fullscreen_rounded,
                                                          size: 18,
                                                        ),
                                                        const SizedBox(
                                                          width: 10,
                                                        ),
                                                        Text(
                                                          ref.tr('fullscreen'),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  const PopupMenuDivider(),
                                                ],
                                                if (media.isTemporary)
                                                  PopupMenuItem(
                                                    value: 'save_to_library',
                                                    child: Row(
                                                      children: [
                                                        Icon(
                                                          Icons
                                                              .library_add_rounded,
                                                          size: 18,
                                                        ),
                                                        SizedBox(width: 10),
                                                        Text(
                                                          ref.tr(
                                                            'save_library',
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                PopupMenuItem(
                                                  value: 'add_to_playlist',
                                                  child: Row(
                                                    children: [
                                                      Icon(
                                                        Icons
                                                            .playlist_add_rounded,
                                                        color: textPrimary,
                                                        size: 18,
                                                      ),
                                                      const SizedBox(width: 10),
                                                      Text(
                                                        ref.tr('add_playlist'),
                                                        style: TextStyle(
                                                          color: textPrimary,
                                                          fontSize: 13,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                const PopupMenuDivider(),
                                                PopupMenuItem(
                                                  enabled: false,
                                                  child: Row(
                                                    children: [
                                                      Icon(
                                                        Icons.speed_rounded,
                                                        color: textSub,
                                                        size: 18,
                                                      ),
                                                      const SizedBox(width: 10),
                                                      Text(
                                                        '${ref.tr('playback_speed')}: ${q.speed}x',
                                                        style: TextStyle(
                                                          color: textSub,
                                                          fontSize: 13,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                for (final s in const [
                                                  0.5,
                                                  0.75,
                                                  1.0,
                                                  1.25,
                                                  1.5,
                                                  2.0,
                                                ].reversed)
                                                  PopupMenuItem(
                                                    onTap: () =>
                                                        ctl.setSpeed(s),
                                                    height: 34,
                                                    child: Padding(
                                                      padding:
                                                          const EdgeInsets.only(
                                                            left: 28,
                                                          ),
                                                      child: Text(
                                                        '${s == s.toInt() ? s.toInt() : s}x',
                                                        style: TextStyle(
                                                          color: q.speed == s
                                                              ? kAccentLight
                                                              : textPrimary,
                                                          fontWeight:
                                                              q.speed == s
                                                              ? FontWeight.bold
                                                              : FontWeight
                                                                    .normal,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ),

                            const Spacer(flex: 1),

                            // 2. Main Visual Area (16:9 Video or 1:1 Artwork)
                            if (!_queueSheetExpanded)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                child: Center(
                                  child: Builder(
                                    builder: (context) {
                                      final isArtwork =
                                          mode == PlayerViewMode.image;
                                      final safePadding = MediaQuery.paddingOf(
                                        context,
                                      );
                                      final aspectRatio = isArtwork
                                          ? 1.0
                                          : (engine.videoAspectRatio ??
                                                (16 / 9));
                                      final maxVisualHeight =
                                          MediaQuery.sizeOf(context).height *
                                          (isArtwork ? 0.4 : 0.48);
                                      final maxVisualWidth = isArtwork
                                          ? (MediaQuery.sizeOf(context).width -
                                                    safePadding.horizontal -
                                                    32) *
                                                0.82
                                          : MediaQuery.sizeOf(context).width -
                                                safePadding.horizontal -
                                                32;
                                      // Fit the square sleeve or source video
                                      // frame inside the viewport without overflow.
                                      final visualWidth = math.min(
                                        maxVisualWidth,
                                        maxVisualHeight * aspectRatio,
                                      );
                                      final visualHeight =
                                          visualWidth / aspectRatio;
                                      return SizedBox(
                                        width: visualWidth,
                                        height: visualHeight,
                                        child: Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            Positioned.fill(
                                              child: Container(
                                                key:
                                                    mode == PlayerViewMode.media
                                                    ? _ambientVideoBoundsKey
                                                    : null,
                                                decoration: BoxDecoration(
                                                  color: Colors.black,
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                  boxShadow: ambientLightEnabled
                                                      ? null
                                                      : [
                                                          BoxShadow(
                                                            color: Colors.black
                                                                .withValues(
                                                                  alpha: isDark
                                                                      ? 0.6
                                                                      : 0.15,
                                                                ),
                                                            blurRadius: 24,
                                                            offset:
                                                                const Offset(
                                                                  0,
                                                                  8,
                                                                ),
                                                          ),
                                                        ],
                                                ),
                                                clipBehavior: Clip.antiAlias,
                                                child: GestureDetector(
                                                  behavior:
                                                      HitTestBehavior.opaque,
                                                  onTap: () => ctl.toggle(),
                                                  child:
                                                      mode ==
                                                          PlayerViewMode.media
                                                      ? (snap.initialized
                                                            ? Stack(
                                                                fit: StackFit
                                                                    .expand,
                                                                children: [
                                                                  ThumbImage(
                                                                    seed: media
                                                                        .id,
                                                                    mediaId:
                                                                        media
                                                                            .id,
                                                                    localPath: media
                                                                        .localPath,
                                                                    expand:
                                                                        true,
                                                                  ),
                                                                  if (engine
                                                                          .videoAspectRatio !=
                                                                      null)
                                                                    _videoSurface(
                                                                      engine,
                                                                    ),
                                                                ],
                                                              )
                                                            : ThumbImage(
                                                                seed: media.id,
                                                                mediaId:
                                                                    media.id,
                                                                localPath: media
                                                                    .localPath,
                                                                expand: true,
                                                              ))
                                                      : ThumbImage(
                                                          seed: media.id,
                                                          mediaId: media.id,
                                                          localPath:
                                                              media.localPath,
                                                          expand: true,
                                                          highRes: true,
                                                        ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),

                            const Spacer(flex: 1),

                            // 3. Track Info (Title & Artist)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.w800,
                                            color: textPrimary,
                                            letterSpacing: -0.5,
                                            height: 1.2,
                                          ),
                                        ),
                                      ),
                                      const SleepTimerButton(),
                                      FavoriteButton(mediaId: media.id),
                                    ],
                                  ),
                                  if (artist.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    InkWell(
                                      onTap: () =>
                                          ref
                                                  .read(
                                                    creatorVideosRequestProvider
                                                        .notifier,
                                                  )
                                                  .state =
                                              artist,
                                      borderRadius: BorderRadius.circular(6),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 2,
                                        ),
                                        child: Text(
                                          artist,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
                                            color: textSub,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),

                            const SizedBox(height: 18),

                            // 4. Seekbar + Time indicators underneath
                            if (useVideoOverlay || !fullPlayerView)
                              AnimatedOpacity(
                                key: useVideoOverlay
                                    ? const ValueKey('compact-player-timeline')
                                    : null,
                                opacity:
                                    useVideoOverlay && !keepVideoControlsVisible
                                    ? (_controlsVisible ? 1 : 0)
                                    : 1,
                                duration: const Duration(milliseconds: 240),
                                curve: Curves.easeInOut,
                                child: IgnorePointer(
                                  ignoring:
                                      useVideoOverlay &&
                                      !keepVideoControlsVisible &&
                                      !_controlsVisible,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                    ),
                                    child: _MobileTimeline(
                                      engine: engine,
                                      ctl: ctl,
                                    ),
                                  ),
                                ),
                              ),

                            const SizedBox(height: 12),

                            // 5. Transport Bar (Shuffle, Prev, Play/Pause Circle, Repeat)
                            if (useVideoOverlay || !fullPlayerView)
                              AnimatedOpacity(
                                key: useVideoOverlay
                                    ? const ValueKey('compact-player-transport')
                                    : null,
                                opacity:
                                    useVideoOverlay && !keepVideoControlsVisible
                                    ? (_controlsVisible ? 1 : 0)
                                    : 1,
                                duration: const Duration(milliseconds: 240),
                                curve: Curves.easeInOut,
                                child: IgnorePointer(
                                  ignoring:
                                      useVideoOverlay &&
                                      !keepVideoControlsVisible &&
                                      !_controlsVisible,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceEvenly,
                                      children: [
                                        // Shuffle
                                        IconButton(
                                          tooltip: ref.tr('shuffle'),
                                          icon: TransportIcon.shuffle(
                                            size: 26,
                                            color: transportArrowColor,
                                          ),
                                          onPressed: () {
                                            ref
                                                .read(queueProvider.notifier)
                                                .toggleShuffle();
                                          },
                                        ),

                                        // Skip Previous
                                        IconButton(
                                          tooltip: ref.tr('prev_video'),
                                          icon: TransportIcon.previous(
                                            size: compactSkipSize,
                                            color: transportArrowColor,
                                          ),
                                          onPressed: () => ctl.playPrev(),
                                        ),

                                        // Play / Pause Button
                                        Material(
                                          color: Colors.transparent,
                                          shape: const CircleBorder(),
                                          elevation: 0,
                                          child: InkWell(
                                            customBorder: const CircleBorder(),
                                            onTap: () => ctl.toggle(),
                                            child: Padding(
                                              padding: const EdgeInsets.all(16),
                                              child: _playPauseGlyph(
                                                snap.isPlaying,
                                                compactPlayPauseSize,
                                                playIconColor,
                                              ),
                                            ),
                                          ),
                                        ),

                                        // Skip Next
                                        IconButton(
                                          tooltip: ref.tr('next_video'),
                                          icon: SkipNextIcon(
                                            size: compactSkipSize,
                                            color: transportArrowColor,
                                          ),
                                          onPressed: () => ctl.playNext(),
                                        ),

                                        // Repeat
                                        IconButton(
                                          tooltip: q.repeat == 'one'
                                              ? ref.tr('repeat_one')
                                              : (q.repeat == 'off'
                                                    ? ref.tr('repeat_off')
                                                    : ref.tr('repeat_all')),
                                          icon: RepeatIcon(
                                            size: 26,
                                            color: transportArrowColor,
                                            repeatMode: q.repeat,
                                          ),
                                          onPressed: () {
                                            ref
                                                .read(queueProvider.notifier)
                                                .cycleRepeat();
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),

                            const SizedBox(height: 18),

                            // A touch-friendly entry point to the queue/lyrics
                            // sheet. QueuePanel already provides tabs for
                            // switching between next contents and lyrics.
                            if (!lockQueueOpen)
                              Center(
                                child: TextButton.icon(
                                  key: const ValueKey(
                                    'compact-next-content-button',
                                  ),
                                  onPressed: () {
                                    ref
                                            .read(lyricsPanelProvider.notifier)
                                            .state =
                                        false;
                                    ref
                                            .read(queueVisibleProvider.notifier)
                                            .state =
                                        true;
                                    setState(() => _queueSheetExpanded = false);
                                  },
                                  icon: const Icon(
                                    Icons.keyboard_arrow_up_rounded,
                                    size: 20,
                                  ),
                                  label: Text(ref.tr('next_contents')),
                                  style: TextButton.styleFrom(
                                    foregroundColor: textSub,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ),
                              ),

                            const Spacer(flex: 1),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // Slide-up queue sheet for mobile
            if (showQueueSheet)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                left: 0,
                right: 0,
                bottom: 0,
                height:
                    MediaQuery.sizeOf(context).height *
                    (_queueSheetExpanded ? 0.88 : 0.52),
                child: QueuePanel(
                  width: double.infinity,
                  ambient: ambientLightEnabled,
                  margin: EdgeInsets.zero,
                  showCompactPreview: _queueSheetExpanded,
                  compactPreview: SizedBox(
                    width: 112,
                    height: 63,
                    child: ThumbImage(
                      seed: media.id,
                      mediaId: media.id,
                      localPath: media.localPath,
                      expand: true,
                    ),
                  ),
                  onToggleExpanded: () {
                    setState(() => _queueSheetExpanded = !_queueSheetExpanded);
                  },
                  onClose: isPhoneSize
                      ? () {
                          ref.read(queueVisibleProvider.notifier).state = false;
                          setState(() => _queueSheetExpanded = false);
                        }
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Floating OSC Seekbar with exact time bubble popup hovering over the mouse position
class _FloatingTimeline extends ConsumerStatefulWidget {
  final bool desktop;
  final VoidCallback onHoverActivity;
  const _FloatingTimeline({
    required this.desktop,
    required this.onHoverActivity,
  });

  @override
  ConsumerState<_FloatingTimeline> createState() => _FloatingTimelineState();
}

class _FloatingTimelineState extends ConsumerState<_FloatingTimeline> {
  bool _isDragging = false;
  double _draggedMs = 0.0;
  double? _pendingSeekMs;
  bool _seekCommandReturned = false;
  int _seekGeneration = 0;
  Timer? _seekSettleTimer;
  bool _hover = false;
  double _hoverFraction = 0.0;
  double _hoverPixelX = 0.0;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    final engine = ref.read(engineProvider);
    _sub = engine.snapshots.listen((_) {
      if (!mounted) return;
      final target = _pendingSeekMs;
      if (_seekCommandReturned &&
          target != null &&
          (engine.snapshot.position.inMilliseconds - target).abs() <= 250) {
        _seekSettleTimer?.cancel();
        _pendingSeekMs = null;
        _seekCommandReturned = false;
        _isDragging = false;
      }
      setState(() {});
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    _seekSettleTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final engine = ref.watch(engineProvider);
    final ctl = ref.read(playbackControllerProvider);
    final snap = engine.snapshot;
    final primaryControlColor = themeTextPrimary(context);
    final activeSeekColor = widget.desktop
        ? const Color(0xFFA1A1A1)
        : primaryControlColor;
    final inactiveSeekColor = widget.desktop
        ? const Color(0xFF676767)
        : Colors.white24;
    final seekThumbColor = widget.desktop
        ? const Color(0xFFD0D0D2)
        : primaryControlColor;
    final dur = snap.duration;
    final displayPos = _isDragging
        ? Duration(milliseconds: _draggedMs.toInt())
        : snap.position;

    final isInteracting = _hover || _isDragging;
    final double timeLabelWidth = dur.inHours > 0 ? 54.0 : 42.0;

    final hoverTargetMs = (dur.inMilliseconds * _hoverFraction).toInt();
    final hoverTargetDuration = Duration(milliseconds: hoverTargetMs);

    return LayoutBuilder(
      builder: (context, timelineConstraints) {
        final timelineWidth = timelineConstraints.maxWidth;
        final bubbleWidth = timeLabelWidth + 16;
        final maxBubbleLeft = math.max(
          0.0,
          timelineWidth - timeLabelWidth - bubbleWidth,
        );
        final minBubbleLeft = math.min(timeLabelWidth, maxBubbleLeft);
        final bubbleLeft = (_hoverPixelX - bubbleWidth / 2)
            .clamp(minBubbleLeft, maxBubbleLeft)
            .toDouble();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Hover / Drag Time Bubble preview positioned directly above the cursor
            SizedBox(
              height: 22,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  if (isInteracting && dur.inMilliseconds > 0)
                    Positioned(
                      left: bubbleLeft,
                      bottom: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          fmtDuration(
                            _isDragging ? displayPos : hoverTargetDuration,
                          ),
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            Row(
              children: [
                SizedBox(
                  width: timeLabelWidth,
                  child: Text(
                    fmtDuration(displayPos),
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return MouseRegion(
                        onEnter: (e) {
                          widget.onHoverActivity();
                          setState(() {
                            _hover = true;
                            _hoverPixelX = e.localPosition.dx + timeLabelWidth;
                            _hoverFraction =
                                (e.localPosition.dx / constraints.maxWidth)
                                    .clamp(0.0, 1.0);
                          });
                        },
                        onHover: (e) {
                          widget.onHoverActivity();
                          setState(() {
                            _hover = true;
                            _hoverPixelX = e.localPosition.dx + timeLabelWidth;
                            _hoverFraction =
                                (e.localPosition.dx / constraints.maxWidth)
                                    .clamp(0.0, 1.0);
                          });
                        },
                        onExit: (_) => setState(() => _hover = false),
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: isInteracting ? 5 : 3.5,
                            thumbShape: RoundSliderThumbShape(
                              enabledThumbRadius: isInteracting ? 7 : 4.5,
                              elevation: 2,
                            ),
                            activeTrackColor: activeSeekColor,
                            inactiveTrackColor: inactiveSeekColor,
                            thumbColor: seekThumbColor,
                            overlayColor: activeSeekColor.withValues(
                              alpha: 0.15,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 10,
                            ),
                          ),
                          child: Slider(
                            value: dur.inMilliseconds == 0
                                ? 0
                                : displayPos.inMilliseconds
                                      .clamp(0, dur.inMilliseconds)
                                      .toDouble(),
                            max:
                                (dur.inMilliseconds <= 0
                                        ? 1
                                        : dur.inMilliseconds)
                                    .toDouble(),
                            onChangeStart: (v) {
                              widget.onHoverActivity();
                              _seekSettleTimer?.cancel();
                              _seekGeneration++;
                              _pendingSeekMs = null;
                              _seekCommandReturned = false;
                              setState(() {
                                _isDragging = true;
                                _draggedMs = v;
                              });
                            },
                            onChanged: (v) {
                              widget.onHoverActivity();
                              setState(() {
                                _draggedMs = v;
                                if (dur.inMilliseconds > 0) {
                                  _hoverPixelX =
                                      (v / dur.inMilliseconds) *
                                          constraints.maxWidth +
                                      timeLabelWidth;
                                }
                              });
                            },
                            onChangeEnd: (v) async {
                              widget.onHoverActivity();
                              final generation = ++_seekGeneration;
                              final targetMs = v.toDouble();
                              setState(() {
                                _draggedMs = targetMs;
                                _pendingSeekMs = targetMs;
                                _seekCommandReturned = false;
                                _isDragging = true;
                              });
                              try {
                                await ctl.seekTo(
                                  Duration(milliseconds: targetMs.toInt()),
                                );
                              } catch (_) {
                                // Keep the requested thumb position visible briefly
                                // even when the engine reports a seek failure.
                              }
                              if (!mounted || generation != _seekGeneration) {
                                return;
                              }
                              _seekCommandReturned = true;
                              if ((engine.snapshot.position.inMilliseconds -
                                          targetMs)
                                      .abs() <=
                                  250) {
                                _seekSettleTimer?.cancel();
                                _pendingSeekMs = null;
                                _seekCommandReturned = false;
                                setState(() => _isDragging = false);
                                return;
                              }
                              _seekSettleTimer?.cancel();
                              _seekSettleTimer = Timer(
                                const Duration(milliseconds: 900),
                                () {
                                  if (!mounted ||
                                      generation != _seekGeneration) {
                                    return;
                                  }
                                  setState(() {
                                    _pendingSeekMs = null;
                                    _seekCommandReturned = false;
                                    _isDragging = false;
                                  });
                                },
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(
                  width: timeLabelWidth,
                  child: Text(
                    fmtDuration(dur),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Expandable volume control that expands into a slider when hovered
class _ExpandableVolume extends ConsumerStatefulWidget {
  final VoidCallback onHoverActivity;
  const _ExpandableVolume({required this.onHoverActivity});

  @override
  ConsumerState<_ExpandableVolume> createState() => _ExpandableVolumeState();
}

class _ExpandableVolumeState extends ConsumerState<_ExpandableVolume> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final volume = ref.watch(volumeProvider);
    final playback = ref.read(playbackControllerProvider);
    final primaryControlColor = themeTextPrimary(context);

    return MouseRegion(
      onEnter: (_) {
        widget.onHoverActivity();
        setState(() => _isHovered = true);
      },
      onExit: (_) => setState(() => _isHovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: _isHovered
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              iconSize: 20,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              tooltip: ref.tr(volume == 0 ? 'unmute' : 'mute'),
              icon: Icon(
                volume == 0
                    ? Icons.volume_off_rounded
                    : Icons.volume_up_rounded,
                color: Colors.white,
              ),
              onPressed: () async {
                widget.onHoverActivity();
                await playback.toggleMute();
              },
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: SizedBox(
                width: _isHovered ? 78 : 0,
                child: _isHovered
                    ? SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 3.5,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 5.5,
                            elevation: 2,
                          ),
                          activeTrackColor: primaryControlColor,
                          inactiveTrackColor: themeBorder(context),
                          thumbColor: primaryControlColor,
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 8,
                          ),
                        ),
                        child: Slider(
                          value: volume.clamp(0.0, 1.0),
                          onChanged: (v) {
                            widget.onHoverActivity();
                            unawaited(playback.setVolume(v));
                          },
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _ModeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textSub = themeTextSub(context);

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? (isDark ? Colors.white : const Color(0xFF2B2B2B))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: selected
                  ? (isDark ? Colors.black : Colors.white)
                  : textSub,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected
                    ? (isDark ? Colors.black : Colors.white)
                    : textSub,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact Apple-style Speed Button for PlayerCard OSC
class _PlayerSpeedButton extends StatelessWidget {
  final double speed;
  final String tooltip;
  final ValueChanged<double> onSelected;
  const _PlayerSpeedButton({
    required this.speed,
    required this.tooltip,
    required this.onSelected,
  });

  static const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = themeTextPrimary(context);
    final textSub = themeTextSub(context);

    return PopupMenuButton<double>(
      tooltip: tooltip,
      initialValue: speed,
      onSelected: onSelected,
      color: themePanelSolid(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: themeBorder(context)),
      ),
      elevation: 8,
      itemBuilder: (ctx) {
        final rev = _speeds.reversed.toList();
        return [
          for (final s in rev)
            PopupMenuItem<double>(
              value: s,
              height: 38,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: speed == s
                    ? BoxDecoration(
                        color: kAccent,
                        borderRadius: BorderRadius.circular(8),
                      )
                    : null,
                child: Row(
                  children: [
                    if (speed == s) ...[
                      const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                    ] else ...[
                      const SizedBox(width: 24),
                    ],
                    Text(
                      '${s == s.toInt() ? s.toInt() : s}x',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: speed == s
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: speed == s ? Colors.white : textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ];
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.06),
          border: Border.all(color: themeBorder(context)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.speed_rounded,
              size: 13,
              color: speed == 1.0 ? textSub : kAccentLight,
            ),
            const SizedBox(width: 3),
            Text(
              '${speed}x',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: speed == 1.0 ? textSub : kAccentLight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Mobile style Timeline with full width bar and time stamps below
class _MobileTimeline extends StatefulWidget {
  final PlaybackEngine engine;
  final PlaybackController ctl;

  const _MobileTimeline({required this.engine, required this.ctl});

  @override
  State<_MobileTimeline> createState() => _MobileTimelineState();
}

class _MobileTimelineState extends State<_MobileTimeline> {
  bool _isDragging = false;
  double _draggedMs = 0.0;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.engine.snapshots.listen((_) {
      if (mounted && !_isDragging) setState(() {});
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snap = widget.engine.snapshot;
    final dur = snap.duration;
    final primaryControlColor = themeTextPrimary(context);
    final displayPos = _isDragging
        ? Duration(milliseconds: _draggedMs.toInt())
        : snap.position;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3.5,
            thumbShape: const RoundSliderThumbShape(
              enabledThumbRadius: 6,
              elevation: 2,
            ),
            activeTrackColor: primaryControlColor,
            inactiveTrackColor: themeBorder(context),
            thumbColor: primaryControlColor,
            overlayColor: primaryControlColor.withValues(alpha: 0.15),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
          ),
          child: Slider(
            value: dur.inMilliseconds == 0
                ? 0
                : displayPos.inMilliseconds
                      .clamp(0, dur.inMilliseconds)
                      .toDouble(),
            max: (dur.inMilliseconds <= 0 ? 1 : dur.inMilliseconds).toDouble(),
            onChangeStart: (v) {
              setState(() {
                _isDragging = true;
                _draggedMs = v;
              });
            },
            onChanged: (v) {
              setState(() {
                _draggedMs = v;
              });
            },
            onChangeEnd: (v) async {
              _draggedMs = v;
              await widget.ctl.seekTo(Duration(milliseconds: v.toInt()));
              if (mounted) {
                setState(() {
                  _isDragging = false;
                });
              }
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                fmtDuration(displayPos),
                style: TextStyle(
                  fontSize: 12,
                  color: themeTextSub(context),
                  fontWeight: FontWeight.w500,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                fmtDuration(dur),
                style: TextStyle(
                  fontSize: 12,
                  color: themeTextSub(context),
                  fontWeight: FontWeight.w500,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
