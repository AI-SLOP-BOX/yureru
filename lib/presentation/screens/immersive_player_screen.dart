import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_state.dart';
import '../../domain/creator_names.dart';
import '../../domain/models.dart';
import '../../platform/keyboard_shortcuts.dart';
import '../../playback/playback_controller.dart';
import '../../playback/playback_engine.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets/ambient_backdrop.dart';
import '../widgets/semantics_safe_slider.dart';
import '../widgets/app_svg_icon.dart';
import '../widgets/transport_icon.dart';
import '../widgets/skip_next_icon.dart';
import '../widgets/lyrics_panel.dart';
import 'media_metadata_editor.dart';
import '../widgets/favorite_button.dart';
import '../widgets/sleep_timer_button.dart';
import '../widgets/playback_options.dart';
import '../widgets/thumb_image.dart';
import '../widgets/pip_video_surface.dart';
import '../widgets/picture_in_picture_button.dart';

/// A presentation-only view: switching layouts never loads or pauses a source.
class ImmersivePlayerScreen extends ConsumerStatefulWidget {
  const ImmersivePlayerScreen({super.key});

  @override
  ConsumerState<ImmersivePlayerScreen> createState() =>
      _ImmersivePlayerScreenState();
}

class _ImmersivePlayerScreenState extends ConsumerState<ImmersivePlayerScreen> {
  late final PlaybackEngine _engine;
  final _surfaceKey = GlobalKey();
  final _ambientCaptureKey = GlobalKey();
  Timer? _idleTimer;
  StreamSubscription<bool>? _playbackSubscription;
  bool _controlsVisible = true;
  bool _pointerOverSurface = false;
  bool _overControls = false;
  bool _pressed = false;
  bool _editingControls = false;
  bool _showLyrics = true;
  bool _editingLyrics = false;
  String? _lastMediaId;

  @override
  void initState() {
    super.initState();
    _engine = ref.read(engineProvider);
    final currentId = ref.read(queueProvider).currentId;
    final currentMedia = currentId == null
        ? null
        : ref.read(libraryProvider).byId(currentId);
    _lastMediaId = currentId;
    _showLyrics =
        currentMedia?.lyricsPathForView(
          artwork: ref.read(playerViewModeProvider) == PlayerViewMode.image,
        ) !=
        null;
    _reveal();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref
            .read(engineProvider)
            .setAmbientFrameSource(_captureAmbientVideoFrame);
      }
    });
    _playbackSubscription = ref
        .read(engineProvider)
        .snapshots
        .map((snapshot) => snapshot.isPlaying)
        .distinct()
        .listen((_) {
          if (mounted) _reveal();
        });
  }

  void _reveal() {
    _idleTimer?.cancel();
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _idleTimer = Timer(const Duration(seconds: 3), () {
      if (mounted &&
          !_overControls &&
          !_pressed &&
          !_editingControls &&
          !MediaQuery.accessibleNavigationOf(context)) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  void _exit() => ref.read(immersiveModeProvider.notifier).state = false;

  void _reportAperture() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _surfaceKey.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      final size = MediaQuery.sizeOf(context);
      final bounds = MatrixUtils.transformRect(
        box.getTransformTo(null),
        Offset.zero & box.size,
      );
      final aperture = Rect.fromLTWH(
        bounds.left / size.width,
        bounds.top / size.height,
        bounds.width / size.width,
        bounds.height / size.height,
      );
      if (ref.read(ambientVideoApertureProvider) != aperture) {
        ref.read(ambientVideoApertureProvider.notifier).state = aperture;
      }
    });
  }

  Future<ui.Image?> _captureAmbientVideoFrame() async {
    final renderObject = _ambientCaptureKey.currentContext?.findRenderObject();
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

  Widget _controls(Widget child) => MouseRegion(
    onEnter: (_) {
      _overControls = true;
      _reveal();
    },
    onExit: (_) {
      _overControls = false;
      _reveal();
    },
    child: IgnorePointer(
      ignoring: !_controlsVisible,
      child: ExcludeSemantics(
        excluding: !_controlsVisible,
        child: AnimatedOpacity(
          key: const ValueKey('immersive-controls'),
          opacity: _controlsVisible ? 1 : 0,
          duration: const Duration(milliseconds: 240),
          child: child,
        ),
      ),
    ),
  );

  @override
  void dispose() {
    _idleTimer?.cancel();
    _playbackSubscription?.cancel();
    _engine.setAmbientFrameSource(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(queueProvider.select((queue) => queue.currentId), (
      _,
      nextId,
    ) {
      if (nextId == _lastMediaId) return;
      _lastMediaId = nextId;
      if (nextId == null) {
        setState(() => _showLyrics = false);
        return;
      }
      final nextMedia = ref.read(libraryProvider).byId(nextId);
      final mode = ref.read(playerViewModeProvider);
      setState(() {
        _showLyrics =
            nextMedia?.lyricsPathForView(
              artwork: mode == PlayerViewMode.image,
            ) !=
            null;
      });
    });
    final media = ref
        .watch(libraryProvider)
        .byId(ref.watch(queueProvider).currentId ?? '');
    if (media == null) return const SizedBox.shrink();
    final engine = ref.watch(engineProvider);
    final mode = ref.watch(playerViewModeProvider);
    final showLyricsButton = !media.lyricsButtonHidden;
    final showLyrics = _showLyrics && showLyricsButton;
    final exitShortcut = ref
        .watch(keyboardShortcutsProvider)[AppShortcutAction.exitExpandedView]!
        .label(macOS: defaultTargetPlatform == TargetPlatform.macOS);
    return Theme(
      data: yureruTheme(),
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _exit();
        },
        child: Scaffold(
          backgroundColor: const Color(0xFF0D0D0D),
          body: MouseRegion(
            onHover: (_) {
              _pointerOverSurface = true;
              _reveal();
            },
            onExit: (_) {
              _pointerOverSurface = false;
              _reveal();
            },
            cursor: _controlsVisible
                ? SystemMouseCursors.basic
                : SystemMouseCursors.none,
            child: Listener(
              onPointerDown: (_) {
                _pressed = true;
                _reveal();
              },
              onPointerUp: (_) {
                _pressed = false;
                _reveal();
              },
              onPointerCancel: (_) {
                _pressed = false;
                _reveal();
              },
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (mode == PlayerViewMode.media)
                    const AmbientRoomGlowCanvas(),
                  SafeArea(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final wide =
                            constraints.maxWidth >= 860 ||
                            (constraints.maxWidth >= 600 &&
                                constraints.maxHeight < 500);
                        final content = _visual(media, engine, mode);
                        final lyrics = LyricsPanel(
                          key: ValueKey(media.id),
                          engine: engine,
                          media: media,
                          immersive: true,
                          viewMode: mode,
                          onEditingChanged: (editing) {
                            if (_editingLyrics != editing) {
                              setState(() => _editingLyrics = editing);
                            }
                          },
                        );
                        return Padding(
                          padding: EdgeInsets.fromLTRB(
                            wide ? 56 : 20,
                            constraints.maxWidth < 600 ? 112 : 68,
                            wide ? 56 : 20,
                            138,
                          ),
                          child: wide
                              ? Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 1600,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(child: content),
                                        if (showLyrics) ...[
                                          const SizedBox(width: 48),
                                          Expanded(child: lyrics),
                                        ],
                                      ],
                                    ),
                                  ),
                                )
                              : Column(
                                  children: [
                                    if (_editingLyrics && showLyrics)
                                      Expanded(child: lyrics)
                                    else ...[
                                      Expanded(
                                        flex: showLyrics ? 3 : 1,
                                        child: content,
                                      ),
                                      if (showLyrics) ...[
                                        const SizedBox(height: 20),
                                        Expanded(flex: 2, child: lyrics),
                                      ],
                                    ],
                                  ],
                                ),
                        );
                      },
                    ),
                  ),
                  PositionedDirectional(
                    top: 0,
                    start: 12,
                    end: 12,
                    child: SafeArea(
                      bottom: false,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final compact = constraints.maxWidth < 600;
                          final viewModeWidth = constraints.maxWidth < 400
                              ? 96.0
                              : constraints.maxWidth < 440
                              ? 110.0
                              : 132.0;
                          final exit = Tooltip(
                            message:
                                '${ref.tr('exit_immersive')} ($exitShortcut)',
                            child: TextButton.icon(
                              key: const ValueKey('immersive-exit'),
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.white,
                                backgroundColor: Colors.black54,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                              ),
                              onPressed: _exit,
                              icon: const AppSvgIcon('back', size: 18),
                              label: Text(ref.tr('return_standard_view')),
                            ),
                          );
                          final status = Text(
                            ref.tr('immersive'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          );
                          final options = Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (media.viewAvailability ==
                                  MediaViewAvailability.both)
                                PopupMenuButton<PlayerViewMode>(
                                  tooltip: ref.tr('immersive_view_options'),
                                  onOpened: () {
                                    _editingControls = true;
                                    _reveal();
                                  },
                                  onCanceled: () {
                                    _editingControls = false;
                                    _reveal();
                                  },
                                  onSelected: (next) {
                                    _editingControls = false;
                                    _reveal();
                                    if (next == mode) return;
                                    ref
                                        .read(playerViewModeProvider.notifier)
                                        .select(next);
                                    unawaited(
                                      engine.setVideoTrackEnabled(
                                        next == PlayerViewMode.media,
                                      ),
                                    );
                                  },
                                  itemBuilder: (_) => [
                                    for (final view in PlayerViewMode.values)
                                      CheckedPopupMenuItem(
                                        value: view,
                                        checked: view == mode,
                                        child: Text(
                                          ref.tr(
                                            view == PlayerViewMode.media
                                                ? 'immersive_media_view'
                                                : 'immersive_image_view',
                                          ),
                                        ),
                                      ),
                                  ],
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: viewModeWidth,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 12,
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          AppSvgIcon(
                                            mode == PlayerViewMode.media
                                                ? 'video'
                                                : 'artwork',
                                            size: 18,
                                            color: Colors.white,
                                          ),
                                          const SizedBox(width: 8),
                                          Flexible(
                                            child: Text(
                                              ref.tr(
                                                mode == PlayerViewMode.media
                                                    ? 'immersive_media_view'
                                                    : 'immersive_image_view',
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          const AppSvgIcon(
                                            'chevron_down',
                                            size: 14,
                                            color: Colors.white70,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              SleepTimerButton(
                                onEditingChanged: (editing) {
                                  if (!mounted) return;
                                  _editingControls = editing;
                                  _reveal();
                                },
                              ),
                              FavoriteButton(
                                mediaId: media.id,
                                color: Colors.white,
                              ),
                              PlaybackVolumeButton(
                                onEditingChanged: (editing) {
                                  if (!mounted) return;
                                  _editingControls = editing;
                                  _reveal();
                                },
                              ),
                              PictureInPictureButton(
                                engine: engine,
                                color: Colors.white,
                              ),
                              if (showLyricsButton)
                                IconButton(
                                  tooltip: ref.tr('lyrics'),
                                  isSelected: _showLyrics,
                                  onPressed: () => setState(
                                    () => _showLyrics = !_showLyrics,
                                  ),
                                  icon: AppSvgIcon(
                                    'lyrics',
                                    color: _showLyrics
                                        ? Colors.white
                                        : Colors.white38,
                                  ),
                                ),
                            ],
                          );
                          if (compact) {
                            return _controls(
                              Column(
                                children: [
                                  Row(
                                    children: [
                                      exit,
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Align(
                                          alignment:
                                              AlignmentDirectional.centerEnd,
                                          child: status,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Align(
                                    alignment: AlignmentDirectional.centerEnd,
                                    child: options,
                                  ),
                                ],
                              ),
                            );
                          }
                          return _controls(
                            Row(
                              children: [
                                exit,
                                const SizedBox(width: 16),
                                Expanded(child: status),
                                options,
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  PositionedDirectional(
                    bottom: 12,
                    start: 20,
                    end: 20,
                    child: SafeArea(
                      top: false,
                      child: _controls(
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1200),
                            child: _ImmersiveTransport(engine: engine),
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
      ),
    );
  }

  Widget _visual(MediaItem media, PlaybackEngine engine, PlayerViewMode mode) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: Center(
            child: StreamBuilder<(bool, double?)>(
              stream: engine.snapshots
                  .map((s) => (s.initialized, engine.videoAspectRatio))
                  .distinct(),
              initialData: (
                engine.snapshot.initialized,
                engine.videoAspectRatio,
              ),
              builder: (context, snapshot) {
                final video =
                    mode == PlayerViewMode.media &&
                    snapshot.data!.$1 &&
                    snapshot.data!.$2 != null;
                if (video) _reportAperture();
                return AspectRatio(
                  key: _surfaceKey,
                  aspectRatio: video ? snapshot.data!.$2! : 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: video
                        ? RepaintBoundary(
                            key: _ambientCaptureKey,
                            child: PipVideoSurface(
                              engine: engine,
                              fit: BoxFit.contain,
                            ),
                          )
                        : ThumbImage(
                            seed: media.id,
                            mediaId: media.id,
                            localPath: media.localPath,
                            imageContext: MediaImageContext.home,
                            forceArtwork: mode == PlayerViewMode.image,
                            highRes: true,
                            expand: true,
                            radius: 20,
                          ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 16),
        _controls(
          AnimatedOpacity(
            opacity: _pointerOverSurface ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () =>
                        ref.read(videoOpenRequestProvider.notifier).state =
                            media.id,
                    child: Text(
                      key: const ValueKey('immersive-title'),
                      displayTitle(media.title),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (formatCreatorNames(media.artist).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Tooltip(
                        message: ref.tr('search_by_creator'),
                        child: InkWell(
                          key: const ValueKey('immersive-creator-search'),
                          onTap: () =>
                              ref
                                  .read(creatorVideosRequestProvider.notifier)
                                  .state = formatCreatorNames(
                                media.artist,
                              ),
                          child: Text(
                            key: const ValueKey('immersive-creator'),
                            formatCreatorNames(media.artist),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (media.artist == null || media.artist!.isEmpty)
                    SizedBox(
                      width: 240,
                      height: 30,
                      child: InkWell(
                        key: const ValueKey('immersive-empty-creator-edit'),
                        onTap: () => showMediaMetadataEditor(
                          context,
                          ref,
                          media,
                          focusCreator: true,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ImmersiveTransport extends ConsumerStatefulWidget {
  const _ImmersiveTransport({required this.engine});
  final PlaybackEngine engine;

  @override
  ConsumerState<_ImmersiveTransport> createState() =>
      _ImmersiveTransportState();
}

class _ImmersiveTransportState extends ConsumerState<_ImmersiveTransport> {
  double? _dragPositionMs;

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(playbackControllerProvider);
    return StreamBuilder<PlaybackSnapshot>(
      stream: widget.engine.snapshots,
      initialData: widget.engine.snapshot,
      builder: (context, snapshot) {
        final playback = snapshot.data!;
        final duration = playback.duration.inMilliseconds;
        final positionMs =
            (_dragPositionMs ?? playback.position.inMilliseconds.toDouble())
                .clamp(0.0, duration > 0 ? duration.toDouble() : 1.0);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            semanticsSafeSlider(
              Slider(
                value: positionMs,
                max: (duration > 0 ? duration : 1).toDouble(),
                activeColor: Colors.white,
                inactiveColor: Colors.white24,
                onChangeStart: playback.initialized && duration > 0
                    ? (value) => setState(() => _dragPositionMs = value)
                    : null,
                onChanged: playback.initialized && duration > 0
                    ? (value) => setState(() => _dragPositionMs = value)
                    : null,
                onChangeEnd: playback.initialized && duration > 0
                    ? (value) async {
                        await controller.seekTo(
                          Duration(milliseconds: value.round()),
                        );
                        if (mounted) setState(() => _dragPositionMs = null);
                      }
                    : null,
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  fmtDuration(Duration(milliseconds: positionMs.round())),
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
                Text(
                  fmtDuration(playback.duration),
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const PlaybackShuffleButton(
                  activeColor: Colors.white,
                  inactiveColor: Colors.white38,
                ),
                IconButton(
                  tooltip: ref.tr('prev_video'),
                  onPressed: controller.playPrev,
                  icon: const TransportIcon.previous(
                    color: Colors.white,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: ref.tr(playback.isPlaying ? 'pause' : 'play'),
                  onPressed: controller.toggle,
                  iconSize: 42,
                  color: Colors.white,
                  style: IconButton.styleFrom(
                    foregroundColor: Colors.white,
                    hoverColor: Colors.white10,
                    highlightColor: Colors.white24,
                  ),
                  icon: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 120),
                    child: Icon(
                      playback.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      key: ValueKey(playback.isPlaying),
                      size: 42,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: ref.tr('next_video'),
                  onPressed: controller.playNext,
                  icon: const SkipNextIcon(color: Colors.white, size: 30),
                ),
                const PlaybackRepeatButton(
                  activeColor: Colors.white,
                  inactiveColor: Colors.white38,
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
