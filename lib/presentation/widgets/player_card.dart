import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_state.dart';
import '../../data/importer.dart';
import '../../domain/models.dart';
import '../../playback/playback_controller.dart';
import '../../playback/playback_engine.dart';
import '../theme.dart';
import 'queue_panel.dart';
import 'repeat_icon.dart';
import 'skip_next_icon.dart';
import 'transport_icon.dart';
import 'thumb_image.dart';

/// Playing screen:
/// - Smooth video / artwork visualizer with breathing ambient aura
/// - IINA / macOS inspired floating frosted-glass OSC (On Screen Controller)
/// - Auto-hiding controls with mouse motion tracking and cursor blanking
/// - Two-finger / mouse linear horizontal drag scrubbing over video area
/// - Hover / drag floating time bubble preview above the seekbar
/// - Morphing AnimatedIcon play/pause button
/// - Smooth volume toggle with expandable slider ("niyoki-to" animation)
/// - mpv video track toggle (`setVideoTrackEnabled`) for low-power audio mode
class PlayerCard extends ConsumerStatefulWidget {
  const PlayerCard({super.key});

  @override
  ConsumerState<PlayerCard> createState() => _PlayerCardState();
}

class _PlayerCardState extends ConsumerState<PlayerCard>
    with TickerProviderStateMixin {
  StreamSubscription? _sub;
  bool _controlsVisible = true;
  bool _pointerOverPlayer = false;
  bool _pointerOverControls = false;
  bool _pointerPressed = false;
  Timer? _hideTimer;
  Timer? _compactCinemaHideTimer;
  bool _compactCinemaControlsVisible = false;

  // Animation controller for play/pause morphing
  late final AnimationController _playPauseAnim;

  // Breathing Aura pulse controller for audio mode
  late final AnimationController _pulseAnim;

  // Linear drag scrub over the video
  bool _isLinearDragging = false;
  double _dragAccumulatedDelta = 0.0;
  Duration _dragStartPos = Duration.zero;
  bool _queueSheetExpanded = false;

  @override
  void initState() {
    super.initState();
    final engine = ref.read(engineProvider);
    bool lastInit = engine.snapshot.initialized;
    bool lastPlaying = engine.snapshot.isPlaying;

    _playPauseAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      value: lastPlaying ? 1.0 : 0.0,
    );

    _pulseAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
      lowerBound: 0.92,
      upperBound: 1.08,
      value: 1.0,
    );

    // Only start infinite loop in non-test production environment
    final isTest = WidgetsBinding.instance.runtimeType.toString().contains(
      'Test',
    );
    if (lastPlaying && !isTest) {
      _pulseAnim.repeat(reverse: true);
    }

    _sub = engine.snapshots.listen((s) {
      if (!mounted) return;
      if (s.initialized != lastInit) {
        lastInit = s.initialized;
        setState(() {});
      }
      if (s.isPlaying != lastPlaying) {
        lastPlaying = s.isPlaying;
        if (s.isPlaying) {
          _playPauseAnim.forward();
          if (!_pulseAnim.isAnimating && !isTest) {
            _pulseAnim.repeat(reverse: true);
          }
        } else {
          _playPauseAnim.reverse();
          _pulseAnim.stop();
        }
      }
    }, onError: (_) {});
    _startHideTimer();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    if (_pointerOverPlayer ||
        _pointerOverControls ||
        _pointerPressed ||
        _isLinearDragging) {
      return;
    }
    _hideTimer = Timer(const Duration(milliseconds: 1000), () {
      if (mounted &&
          _controlsVisible &&
          !_pointerOverPlayer &&
          !_isLinearDragging &&
          !_pointerOverControls &&
          !_pointerPressed) {
        setState(() {
          _controlsVisible = false;
        });
      }
    });
  }

  void _onPointerHover() {
    if (!_controlsVisible) {
      setState(() {
        _controlsVisible = true;
      });
    }
    _startHideTimer();
  }

  void _onControlsEnter() {
    _pointerOverControls = true;
    _hideTimer?.cancel();
    if (!_controlsVisible) {
      setState(() => _controlsVisible = true);
    }
  }

  void _onControlsExit() {
    _pointerOverControls = false;
    _startHideTimer();
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
    _startHideTimer();
  }

  void _toggleControlsVisibility() {
    setState(() {
      _controlsVisible = !_controlsVisible;
    });
    if (_controlsVisible) {
      _startHideTimer();
    } else {
      _hideTimer?.cancel();
    }
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
          quarterTurns: 1,
          child: engine.buildVideoView(fit: BoxFit.cover),
        );
      }
      return Stack(
        fit: StackFit.expand,
        children: [
          // Fill the unused space with a softened still while keeping only one
          // live video surface mounted. media_kit does not render reliably
          // when the same controller is mounted twice at once.
          Positioned.fill(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
              child: Opacity(
                opacity: 0.42,
                child: ThumbImage(
                  seed: media.id,
                  mediaId: media.id,
                  localPath: media.localPath,
                  expand: true,
                  highRes: true,
                ),
              ),
            ),
          ),
          const Positioned.fill(child: ColoredBox(color: Color(0x66000000))),
          Center(
            child: AspectRatio(
              aspectRatio: engine.videoAspectRatio ?? (16 / 9),
              child: engine.buildVideoView(fit: BoxFit.contain),
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

  void _onSwitchMode(PlayerViewMode newMode) {
    _onPointerHover();
    ref.read(playerViewModeProvider.notifier).state = newMode;
    // mpv video track toggle: vid=auto for media, vid=no for audio-only
    final engine = ref.read(engineProvider);
    engine.setVideoTrackEnabled(newMode == PlayerViewMode.media);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _compactCinemaHideTimer?.cancel();
    _sub?.cancel();
    _playPauseAnim.dispose();
    _pulseAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = ref.watch(queueProvider);
    final lib = ref.watch(libraryProvider);
    final engine = ref.watch(engineProvider);
    final ctl = ref.read(playbackControllerProvider);
    final mode = ref.watch(playerViewModeProvider);
    final snap = engine.snapshot;
    final media = q.currentId == null ? null : lib.byId(q.currentId!);
    if (media == null) return const SizedBox.shrink();

    final screenWidth = MediaQuery.sizeOf(context).width;
    final videoAspectRatio = engine.videoAspectRatio ?? (16 / 9);
    final videoLayoutWidth = screenWidth;
    final isCompact = screenWidth < 1000;
    final isUltraCompact = screenWidth < 380;
    final isCinema = ref.watch(cinemaModeProvider);

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
    final transportIconColor = isDark
        ? const Color(0xFFA8A8AC)
        : const Color(0xFF5C5C60);
    final playIconColor = isDark
        ? const Color(0xFF9E9EA2)
        : const Color(0xFF525256);

    return MouseRegion(
      cursor: _controlsVisible
          ? SystemMouseCursors.basic
          : SystemMouseCursors.none,
      onEnter: (_) {
        _pointerOverPlayer = true;
        if (_controlsVisible) {
          setState(() {});
        } else {
          _onPointerHover();
        }
      },
      onHover: (_) {
        _pointerOverPlayer = true;
        _onPointerHover();
      },
      onExit: (_) {
        _pointerOverPlayer = false;
        if (mounted &&
            _controlsVisible &&
            !_isLinearDragging &&
            !_pointerPressed) {
          // Immediately hide controls when cursor leaves the player area (IINA style)
          _hideTimer?.cancel();
          setState(() {
            _controlsVisible = false;
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
                    if (dur.inMilliseconds > 0) {
                      // 1 pixel = ~120ms of playback scrub
                      final deltaMs = (_dragAccumulatedDelta * 120).toInt();
                      final targetMs = (_dragStartPos.inMilliseconds + deltaMs)
                          .clamp(0, dur.inMilliseconds);
                      ctl.seekTo(Duration(milliseconds: targetMs));
                    }
                  },
                  onHorizontalDragEnd: (details) {
                    _isLinearDragging = false;
                    _startHideTimer();
                  },
                  onTap: () {
                    if (isCompact) {
                      _toggleControlsVisibility();
                    } else {
                      _onPointerHover();
                      ctl.toggle();
                    }
                  },
                  onDoubleTap: toggleFullscreen,
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
                                    clipBehavior: Clip.hardEdge,
                                    child: SizedBox(
                                      width: videoLayoutWidth,
                                      height:
                                          videoLayoutWidth / videoAspectRatio,
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.black,
                                          borderRadius: isCinema
                                              ? BorderRadius.zero
                                              : BorderRadius.circular(20),
                                          border: isCinema
                                              ? null
                                              : Border.all(
                                                  color: themeBorder(context),
                                                  width: 1,
                                                ),
                                          boxShadow: isCinema
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
                                                    offset: const Offset(0, 14),
                                                  ),
                                                ],
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        child: snap.initialized
                                            ? Stack(
                                                fit: StackFit.expand,
                                                children: [
                                                  ThumbImage(
                                                    seed: media.id,
                                                    mediaId: media.id,
                                                    localPath: media.localPath,
                                                    expand: true,
                                                  ),
                                                  engine.buildVideoView(),
                                                ],
                                              )
                                            : Stack(
                                                fit: StackFit.expand,
                                                children: [
                                                  ThumbImage(
                                                    seed: media.id,
                                                    mediaId: media.id,
                                                    localPath: media.localPath,
                                                    expand: true,
                                                  ),
                                                  Container(
                                                    color: Colors.black45,
                                                    child: const Column(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .center,
                                                      children: [
                                                        CircularProgressIndicator(
                                                          strokeWidth: 3,
                                                        ),
                                                        SizedBox(height: 14),
                                                        Text(
                                                          '読み込み中...',
                                                          style: TextStyle(
                                                            fontSize: 13,
                                                            color:
                                                                Colors.white70,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                      ),
                                    ),
                                  ),
                          )
                        : Center(
                            key: const ValueKey('player-mode-image'),
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: themeCard(context),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: themeBorder(context),
                                    width: 1,
                                  ),
                                  boxShadow: [
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

            // 3. Top Floating Capsule: Collapse Button + Media / Image Mode Switcher (or pure cinema exit button)
            Positioned(
              top: 14,
              left: 16,
              right: 16,
              child: MouseRegion(
                onEnter: (_) => _onControlsEnter(),
                onExit: (_) => _onControlsExit(),
                child: AnimatedOpacity(
                  // In cinema mode, reveal the exit affordance only while the
                  // pointer is over the player. Touch layouts keep their own
                  // always-visible exit button below.
                  opacity: (isCinema ? _pointerOverPlayer : _controlsVisible)
                      ? 1.0
                      : 0.0,
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeInOut,
                  child: isCinema
                      ? Align(
                          alignment: Alignment.topRight,
                          child: ClipOval(
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                              child: Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isDark
                                      ? const Color(0xFFE1E1E4)
                                      : const Color(0xFF202127),
                                  border: Border.all(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.2)
                                        : Colors.black.withValues(alpha: 0.15),
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
                                  tooltip: '大画面を閉じる (Esc)',
                                  icon: const Icon(
                                    Icons.fullscreen_exit_rounded,
                                    size: 26,
                                  ),
                                  color: isDark
                                      ? const Color(0xFF343438)
                                      : Colors.white,
                                  onPressed: () {
                                    _onPointerHover();
                                    ref
                                            .read(cinemaModeProvider.notifier)
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
                                filter: ImageFilter.blur(
                                  sigmaX: 18,
                                  sigmaY: 18,
                                ),
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isDark
                                        ? Colors.black.withValues(alpha: 0.5)
                                        : Colors.white.withValues(alpha: 0.85),
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
                                    tooltip: 'ライブラリに戻る',
                                    icon: const Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      size: 26,
                                    ),
                                    color: textPrimary,
                                    onPressed: () {
                                      ref
                                              .read(
                                                viewingPlayerProvider.notifier,
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
                                filter: ImageFilter.blur(
                                  sigmaX: 18,
                                  sigmaY: 18,
                                ),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.black.withValues(alpha: 0.5)
                                        : Colors.white.withValues(alpha: 0.85),
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
                                        label: 'メディア',
                                        icon: Icons.smart_display_rounded,
                                        selected: mode == PlayerViewMode.media,
                                        onTap: () =>
                                            _onSwitchMode(PlayerViewMode.media),
                                      ),
                                      _ModeButton(
                                        label: '画像',
                                        icon: Icons.image_rounded,
                                        selected: mode == PlayerViewMode.image,
                                        onTap: () =>
                                            _onSwitchMode(PlayerViewMode.image),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),

                            // Complete big screen / Cinema mode toggle button
                            ClipOval(
                              child: BackdropFilter(
                                filter: ImageFilter.blur(
                                  sigmaX: 18,
                                  sigmaY: 18,
                                ),
                                child: Container(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isDark
                                        ? Colors.black.withValues(alpha: 0.5)
                                        : Colors.white.withValues(alpha: 0.85),
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
                                    tooltip: '動画だけ完全大画面',
                                    icon: const Icon(
                                      Icons.fullscreen_rounded,
                                      size: 24,
                                    ),
                                    color: textPrimary,
                                    onPressed: () {
                                      _onPointerHover();
                                      ref
                                              .read(cinemaModeProvider.notifier)
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

            // 4. Bottom Floating IINA-style Frosted Glass OSC (On Screen Controller)
            // Hidden when in pure cinema mode so nothing blocks the video
            if (!isCinema)
              Positioned(
                bottom: isCompact ? 10 : 34,
                left: isCompact ? 10 : 24,
                right: isCompact ? 10 : 24,
                child: MouseRegion(
                  onEnter: (_) => _onControlsEnter(),
                  onExit: (_) => _onControlsExit(),
                  child: AnimatedOpacity(
                    opacity: _controlsVisible ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 240),
                    curve: Curves.easeInOut,
                    child: IgnorePointer(
                      ignoring: !_controlsVisible,
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 660),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(
                              isCompact ? 18 : 22,
                            ),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(
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
                                                  offset: const Offset(0, 2),
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
                                              mainAxisSize: MainAxisSize.min,
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
                                                    fontWeight: FontWeight.w700,
                                                    color: textPrimary,
                                                    letterSpacing: -0.2,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  media.artist ??
                                                      (q.sourcePlaylistId !=
                                                              null
                                                          ? (lib
                                                                    .playlistById(
                                                                      q.sourcePlaylistId!,
                                                                    )
                                                                    ?.name ??
                                                                '')
                                                          : ''),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: isCompact
                                                        ? 11
                                                        : 12,
                                                    fontWeight: FontWeight.w500,
                                                    color: textSub,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          // Expandable volume slider
                                          _ExpandableVolume(
                                            onHoverActivity: _onPointerHover,
                                          ),
                                          const SizedBox(width: 6),
                                          // Speed Indicator Pill
                                          _PlayerSpeedButton(
                                            speed: q.speed,
                                            onSelected: (s) => ctl.setSpeed(s),
                                          ),
                                        ],
                                      ),
                                    ),
                                    // Floating Timeline Slider with Bubble Preview
                                    _FloatingTimeline(
                                      desktop: !isCompact,
                                      onHoverActivity: _onPointerHover,
                                    ),
                                    // Floating Transport Control buttons:
                                    // [シャッフル] [前の曲] (再生/一時停止) [リピート]
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
                                          tooltip: 'シャッフル',
                                          icon: TransportIcon.shuffle(
                                            size: isUltraCompact
                                                ? 18
                                                : (isCompact ? 20 : 22),
                                            color: q.shuffle
                                                ? textPrimary
                                                : (isDark
                                                      ? Colors.white54
                                                      : Colors.black45),
                                          ),
                                          onPressed: () {
                                            _onPointerHover();
                                            ref
                                                .read(queueProvider.notifier)
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
                                          tooltip: '前の動画',
                                          icon: TransportIcon.previous(
                                            size: isUltraCompact
                                                ? 24
                                                : (isCompact ? 28 : 34),
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
                                                    : const Color(0xFF1E293B))
                                              : Colors.transparent,
                                          shape: const CircleBorder(),
                                          elevation: isCompact ? 6 : 0,
                                          child: InkWell(
                                            customBorder: const CircleBorder(),
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
                                              child: AnimatedIcon(
                                                icon: AnimatedIcons.play_pause,
                                                progress: _playPauseAnim,
                                                color: playIconColor,
                                                size: isUltraCompact
                                                    ? 24
                                                    : (isCompact ? 28 : 60),
                                              ),
                                            ),
                                          ),
                                        ),
                                        SizedBox(
                                          width: isUltraCompact
                                              ? 6
                                              : (isCompact ? 10 : 12),
                                        ),

                                        // Next (->)
                                        IconButton(
                                          padding: EdgeInsets.all(
                                            isUltraCompact
                                                ? 4
                                                : (isCompact ? 8 : 10),
                                          ),
                                          constraints: isUltraCompact
                                              ? const BoxConstraints()
                                              : null,
                                          tooltip: '次の動画',
                                          icon: SkipNextIcon(
                                            size: isUltraCompact
                                                ? 24
                                                : (isCompact ? 28 : 34),
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
                                              ? '1曲リピート'
                                              : (q.repeat == 'off'
                                                    ? 'リピートなし'
                                                    : '全曲リピート'),
                                          icon: RepeatIcon(
                                            size: isUltraCompact
                                                ? 18
                                                : (isCompact ? 20 : 22),
                                            color: q.repeat == 'off'
                                                ? (isDark
                                                      ? Colors.white54
                                                      : Colors.black45)
                                                : textPrimary,
                                            repeatMode: q.repeat,
                                          ),
                                          onPressed: () {
                                            _onPointerHover();
                                            ref
                                                .read(queueProvider.notifier)
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
            // Bottom slide-up Queue Sheet that never covers the video entirely (on compact / narrow view)
            if (ref.watch(queueVisibleProvider) && isCompact && !isCinema)
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                height: (MediaQuery.sizeOf(context).height * 0.36)
                    .clamp(220.0, 360.0)
                    .toDouble(),
                child: QueuePanel(
                  width: double.infinity,
                  margin: EdgeInsets.zero,
                  onClose: () {
                    ref.read(queueVisibleProvider.notifier).state = false;
                  },
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
                : Positioned.fill(
                    child: ThumbImage(
                      seed: media.id,
                      mediaId: media.id,
                      localPath: media.localPath,
                      expand: true,
                      highRes: true,
                    ),
                  ),
            Positioned(
              top: MediaQuery.paddingOf(context).top + 8,
              right: 12,
              child: AnimatedOpacity(
                opacity: _compactCinemaControlsVisible ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: Material(
                  color: isDark ? Colors.white : const Color(0xFF202127),
                  shape: const CircleBorder(),
                  elevation: 4,
                  child: IconButton(
                    tooltip: '通常表示に戻る',
                    icon: const Icon(Icons.fullscreen_exit_rounded),
                    color: isDark ? const Color(0xFF17171B) : Colors.white,
                    onPressed: () {
                      ref.read(cinemaModeProvider.notifier).state = false;
                    },
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
    final title = displayTitle(media.title);
    final artist =
        media.artist ??
        (q.sourcePlaylistId != null
            ? (lib.playlistById(q.sourcePlaylistId!)?.name ?? '')
            : '');

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = themeTextPrimary(context);
    final textSub = themeTextSub(context);
    final transportArrowColor = isDark
        ? const Color(0xFFA8A8AC)
        : const Color(0xFF5C5C60);
    final playIconColor = isDark
        ? const Color(0xFF9E9EA2)
        : const Color(0xFF525256);

    return Scaffold(
      key: key,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
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
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                IconButton(
                                  icon: const Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    size: 30,
                                  ),
                                  color: textPrimary,
                                  tooltip: 'ライブラリに戻る',
                                  onPressed: () {
                                    ref
                                            .read(
                                              viewingPlayerProvider.notifier,
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
                                            : Icons.smart_display_rounded,
                                        size: 22,
                                        color: textPrimary,
                                      ),
                                      tooltip: mode == PlayerViewMode.media
                                          ? '画像モードに切替'
                                          : '動画モードに切替',
                                      onPressed: () {
                                        _onSwitchMode(
                                          mode == PlayerViewMode.media
                                              ? PlayerViewMode.image
                                              : PlayerViewMode.media,
                                        );
                                      },
                                    ),
                                    // Fullscreen / Cinema mode button
                                    IconButton(
                                      icon: const Icon(
                                        Icons.fullscreen_rounded,
                                        size: 24,
                                      ),
                                      color: textPrimary,
                                      tooltip: '大画面表示 (F / Cinema)',
                                      onPressed: () {
                                        ref
                                                .read(
                                                  cinemaModeProvider.notifier,
                                                )
                                                .state =
                                            true;
                                      },
                                    ),
                                    // Speed / More menu
                                    PopupMenuButton<String>(
                                      icon: Icon(
                                        Icons.more_vert_rounded,
                                        size: 24,
                                        color: textPrimary,
                                      ),
                                      color: themePanelSolid(context),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(14),
                                        side: BorderSide(
                                          color: themeBorder(context),
                                        ),
                                      ),
                                      onSelected: (val) {},
                                      itemBuilder: (ctx) => [
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
                                                '速度: ${q.speed}x',
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
                                            onTap: () => ctl.setSpeed(s),
                                            height: 34,
                                            child: Padding(
                                              padding: const EdgeInsets.only(
                                                left: 28,
                                              ),
                                              child: Text(
                                                '${s == s.toInt() ? s.toInt() : s}x',
                                                style: TextStyle(
                                                  color: q.speed == s
                                                      ? kAccentLight
                                                      : textPrimary,
                                                  fontWeight: q.speed == s
                                                      ? FontWeight.bold
                                                      : FontWeight.normal,
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
                                child: AspectRatio(
                                  aspectRatio: mode == PlayerViewMode.media
                                      ? (16 / 9)
                                      : 1.0,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: Colors.black,
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(
                                            alpha: isDark ? 0.6 : 0.15,
                                          ),
                                          blurRadius: 24,
                                          offset: const Offset(0, 8),
                                        ),
                                      ],
                                    ),
                                    clipBehavior: Clip.antiAlias,
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () => ctl.toggle(),
                                      child: mode == PlayerViewMode.media
                                          ? (snap.initialized
                                                ? Stack(
                                                    fit: StackFit.expand,
                                                    children: [
                                                      ThumbImage(
                                                        seed: media.id,
                                                        mediaId: media.id,
                                                        localPath:
                                                            media.localPath,
                                                        expand: true,
                                                      ),
                                                      engine.buildVideoView(),
                                                    ],
                                                  )
                                                : ThumbImage(
                                                    seed: media.id,
                                                    mediaId: media.id,
                                                    localPath: media.localPath,
                                                    expand: true,
                                                  ))
                                          : ThumbImage(
                                              seed: media.id,
                                              mediaId: media.id,
                                              localPath: media.localPath,
                                              expand: true,
                                              highRes: true,
                                            ),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                          const Spacer(flex: 1),

                          // 3. Track Info (Title & Artist)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
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
                                const SizedBox(height: 6),
                                Text(
                                  artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    color: textSub,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 18),

                          // 4. Seekbar + Time indicators underneath
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: _MobileTimeline(engine: engine, ctl: ctl),
                          ),

                          const SizedBox(height: 12),

                          // 5. Transport Bar (Shuffle, Prev, Play/Pause Circle, Repeat)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                // Shuffle
                                IconButton(
                                  tooltip: 'シャッフル',
                                  icon: TransportIcon.shuffle(
                                    size: 26,
                                    color: q.shuffle ? textPrimary : textSub,
                                  ),
                                  onPressed: () {
                                    ref
                                        .read(queueProvider.notifier)
                                        .toggleShuffle();
                                  },
                                ),

                                // Skip Previous
                                IconButton(
                                  tooltip: '前の動画',
                                  icon: TransportIcon.previous(
                                    size: 40,
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
                                      child: AnimatedIcon(
                                        icon: AnimatedIcons.play_pause,
                                        progress: _playPauseAnim,
                                        color: playIconColor,
                                        size: 38,
                                      ),
                                    ),
                                  ),
                                ),

                                // Skip Next
                                IconButton(
                                  tooltip: '次の動画',
                                  icon: SkipNextIcon(
                                    size: 40,
                                    color: transportArrowColor,
                                  ),
                                  onPressed: () => ctl.playNext(),
                                ),

                                // Repeat
                                IconButton(
                                  tooltip: q.repeat == 'one'
                                      ? '1曲リピート'
                                      : (q.repeat == 'off'
                                            ? 'リピートなし'
                                            : '全曲リピート'),
                                  icon: RepeatIcon(
                                    size: 26,
                                    color: q.repeat == 'off'
                                        ? textSub
                                        : textPrimary,
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

                          const SizedBox(height: 18),

                          // Give the upcoming queue a clear, labeled entry point
                          // on phones instead of relying on the small toolbar icon.
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: OutlinedButton.icon(
                              onPressed: () {
                                ref.read(queueVisibleProvider.notifier).state =
                                    true;
                              },
                              icon: const Icon(Icons.queue_music_rounded),
                              label: const Text('次のコンテンツ'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: textPrimary,
                                side: BorderSide(
                                  color: isDark
                                      ? Colors.white24
                                      : Colors.black26,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 13,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
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
          if (showQueue)
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
          if (showQueue)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
              left: 0,
              right: 0,
              bottom: 0,
              height:
                  MediaQuery.of(context).size.height *
                  (_queueSheetExpanded ? 0.88 : 0.52),
              child: QueuePanel(
                width: double.infinity,
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
                onClose: () {
                  ref.read(queueVisibleProvider.notifier).state = false;
                  setState(() => _queueSheetExpanded = false);
                },
              ),
            ),
        ],
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
  bool _hover = false;
  double _hoverFraction = 0.0;
  double _hoverPixelX = 0.0;
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
    final snap = engine.snapshot;
    final primaryControlColor = themeTextPrimary(context);
    final activeSeekColor = widget.desktop
        ? const Color(0xFFA0A0A3)
        : primaryControlColor;
    final inactiveSeekColor = widget.desktop
        ? const Color(0xFF66666A)
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
                  left: (_hoverPixelX - 28).clamp(
                    timeLabelWidth,
                    MediaQuery.of(context).size.width - timeLabelWidth - 56,
                  ),
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
                            (e.localPosition.dx / constraints.maxWidth).clamp(
                              0.0,
                              1.0,
                            );
                      });
                    },
                    onHover: (e) {
                      widget.onHoverActivity();
                      setState(() {
                        _hover = true;
                        _hoverPixelX = e.localPosition.dx + timeLabelWidth;
                        _hoverFraction =
                            (e.localPosition.dx / constraints.maxWidth).clamp(
                              0.0,
                              1.0,
                            );
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
                        overlayColor: activeSeekColor.withValues(alpha: 0.15),
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
                        max: (dur.inMilliseconds <= 0 ? 1 : dur.inMilliseconds)
                            .toDouble(),
                        onChangeStart: (v) {
                          widget.onHoverActivity();
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
                          _draggedMs = v;
                          await ctl.seekTo(Duration(milliseconds: v.toInt()));
                          if (mounted) {
                            setState(() {
                              _isDragging = false;
                            });
                          }
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
  double _beforeMute = 1.0;

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
              tooltip: volume == 0 ? 'ミュート解除' : 'ミュート',
              icon: Icon(
                volume == 0
                    ? Icons.volume_off_rounded
                    : Icons.volume_up_rounded,
                color: Colors.white,
              ),
              onPressed: () async {
                widget.onHoverActivity();
                if (volume == 0) {
                  final restore = _beforeMute > 0 ? _beforeMute : 1.0;
                  await playback.setVolume(restore);
                } else {
                  _beforeMute = volume;
                  await playback.setVolume(0);
                }
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
              ? (isDark ? Colors.white : const Color(0xFF1E293B))
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
  final ValueChanged<double> onSelected;
  const _PlayerSpeedButton({required this.speed, required this.onSelected});

  static const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = themeTextPrimary(context);
    final textSub = themeTextSub(context);

    return PopupMenuButton<double>(
      tooltip: '再生速度',
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
