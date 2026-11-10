import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../app_state.dart';
import '../../data/importer.dart' show isVideoPath;
import '../../domain/models.dart';
import '../../playback/playback_engine.dart';
import '../../playback/playback_controller.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets/artwork_audio_timing_editor.dart';
import '../widgets/lyrics_editor_dialog.dart';
import '../widgets/metadata_fields.dart';

Future<void> showMediaMetadataEditor(
  BuildContext context,
  WidgetRef ref,
  MediaItem media, {
  bool focusCreator = false,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final languageCode = ref.read(activeLanguageCodeProvider);
  String tr(String key) => translate(key, languageCode);
  final titleController = TextEditingController(text: media.title);
  final artistController = TextEditingController(text: media.artist ?? '');
  final albumController = TextEditingController(text: media.album ?? '');
  final albumArtistController = TextEditingController(
    text: media.albumArtist ?? '',
  );
  final discController = TextEditingController(
    text: media.discNumber?.toString() ?? '',
  );
  final trackController = TextEditingController(
    text: media.trackNumber?.toString() ?? '',
  );
  final lyricsOffsetController = TextEditingController(
    text: _formatLyricsOffset(media.lyricsOffsetMs),
  );
  final videoLyricsOffsetController = TextEditingController(
    text: _formatLyricsOffset(media.lyricsOffsetForView(artwork: false)),
  );
  final artworkLyricsOffsetController = TextEditingController(
    text: _formatLyricsOffset(media.lyricsOffsetForView(artwork: true)),
  );
  final artworkAudioOffsetController = TextEditingController(
    text: _formatLyricsOffset(media.artworkAudioOffsetMs),
  );
  final artworkAudioEndController = TextEditingController(
    text: media.artworkAudioEndMs > 0
        ? _formatLyricsOffset(media.artworkAudioEndMs)
        : '',
  );
  final videoLyricsOffsetFromArtworkController = TextEditingController(
    text: _formatLyricsOffset(
      media.lyricsOffsetForView(artwork: false) -
          media.lyricsOffsetForView(artwork: true),
    ),
  );
  var separateLyricsByView = media.separateLyricsByView;
  var viewAvailability = media.viewAvailability;
  var artworkLyricsOffsetFollowsVideo = media.artworkLyricsOffsetFollowsVideo;
  var videoLyricsTimingRelativeToArtwork =
      media.separateLyricsByView && !media.artworkLyricsOffsetFollowsVideo;
  String? artworkAudioMediaId = media.artworkAudioMediaId;
  String? artworkAudioPath = media.artworkAudioPath;
  String? selectedArtworkAudioPath;
  var clearArtworkAudio = false;
  final audioSourceChoices = ref
      .read(libraryProvider)
      .savedMedia
      .where((item) => !isVideoPath(item.localPath))
      .toList();
  if (!audioSourceChoices.any((item) => item.id == artworkAudioMediaId)) {
    artworkAudioMediaId = null;
  }
  String? selectedArtworkPath;
  var clearArtwork = false;
  String? selectedThumbnailPath;
  var clearThumbnail = false;
  String? pendingArtworkPath;
  var pendingClearArtwork = false;
  String? pendingThumbnailPath;
  var pendingClearThumbnail = false;
  var timingPreviewActive = false;
  QueueState? queueBeforeTimingPreview;
  PlayerViewMode? viewBeforeTimingPreview;
  PlaybackSnapshot? playbackBeforeTimingPreview;
  var editLyricsAfterClose = false;
  var creatorWasEdited = false;
  final creatorFieldKey = GlobalKey<CreatorNamesFieldState>();
  var deleteMediaAfterClose = false;
  DialogRoute<bool>? dialogRoute;
  final allowDialogPop = ValueNotifier(false);

  bool hasUnsavedChanges() =>
      titleController.text != media.title ||
      artistController.text != (media.artist ?? '') ||
      creatorFieldKey.currentState?.hasPendingInput == true ||
      albumController.text != (media.album ?? '') ||
      albumArtistController.text != (media.albumArtist ?? '') ||
      discController.text != (media.discNumber?.toString() ?? '') ||
      trackController.text != (media.trackNumber?.toString() ?? '') ||
      lyricsOffsetController.text !=
          _formatLyricsOffset(media.lyricsOffsetMs) ||
      videoLyricsOffsetController.text !=
          _formatLyricsOffset(media.lyricsOffsetForView(artwork: false)) ||
      artworkLyricsOffsetController.text !=
          _formatLyricsOffset(media.lyricsOffsetForView(artwork: true)) ||
      artworkAudioOffsetController.text !=
          _formatLyricsOffset(media.artworkAudioOffsetMs) ||
      artworkAudioEndController.text !=
          (media.artworkAudioEndMs > 0
              ? _formatLyricsOffset(media.artworkAudioEndMs)
              : '') ||
      videoLyricsOffsetFromArtworkController.text !=
          _formatLyricsOffset(
            media.lyricsOffsetForView(artwork: false) -
                media.lyricsOffsetForView(artwork: true),
          ) ||
      separateLyricsByView != media.separateLyricsByView ||
      viewAvailability != media.viewAvailability ||
      artworkLyricsOffsetFollowsVideo !=
          media.artworkLyricsOffsetFollowsVideo ||
      videoLyricsTimingRelativeToArtwork !=
          (media.separateLyricsByView &&
              !media.artworkLyricsOffsetFollowsVideo) ||
      artworkAudioMediaId != media.artworkAudioMediaId ||
      artworkAudioPath != media.artworkAudioPath ||
      selectedArtworkAudioPath != null ||
      clearArtworkAudio ||
      selectedArtworkPath != null ||
      clearArtwork ||
      pendingArtworkPath != null ||
      pendingClearArtwork ||
      selectedThumbnailPath != null ||
      clearThumbnail ||
      pendingThumbnailPath != null ||
      pendingClearThumbnail;

  Future<void> closeDialogRoute(
    BuildContext dialogContext, {
    required bool result,
  }) async {
    allowDialogPop.value = true;
    await WidgetsBinding.instance.endOfFrame;
    if (dialogContext.mounted && dialogRoute?.isActive == true) {
      Navigator.of(dialogContext, rootNavigator: true).pop(result);
    }
  }

  Future<void> requestDialogClose(
    BuildContext dialogContext, {
    bool openLyrics = false,
  }) async {
    if (hasUnsavedChanges()) {
      final discard = await showDialog<bool>(
        context: dialogContext,
        barrierDismissible: false,
        builder: (confirmContext) => AlertDialog(
          title: Text(tr('unsaved_changes_title')),
          content: Text(tr('unsaved_changes_message')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(confirmContext, false),
              child: Text(tr('keep_editing')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(confirmContext, true),
              child: Text(tr('discard_changes')),
            ),
          ],
        ),
      );
      if (discard != true || !dialogContext.mounted) return;
    }
    if (openLyrics) editLyricsAfterClose = true;
    await closeDialogRoute(dialogContext, result: false);
  }

  String timingPreviewSourcePath() {
    if (selectedArtworkAudioPath != null) return selectedArtworkAudioPath!;
    if (clearArtworkAudio) return media.localPath;
    if (artworkAudioPath != null) return artworkAudioPath!;
    if (artworkAudioMediaId != null) {
      return ref.read(libraryProvider).byId(artworkAudioMediaId!)?.localPath ??
          media.localPath;
    }
    return media.localPath;
  }

  Future<void> startTimingPreview({required bool autoplay}) async {
    final engine = ref.read(engineProvider);
    final queueNotifier = ref.read(queueProvider.notifier);
    queueBeforeTimingPreview ??= ref
        .read(queueProvider)
        .copyWith(
          queue: List.of(ref.read(queueProvider).queue),
          original: List.of(ref.read(queueProvider).original),
        );
    viewBeforeTimingPreview ??= ref.read(playerViewModeProvider);
    playbackBeforeTimingPreview ??= engine.snapshot;
    timingPreviewActive = true;
    // The timing preview may use a separate audio file. Isolate it in a
    // one-item, stop-at-end queue so finishing that file cannot start another
    // video while the user is adjusting its timing.
    queueNotifier.start([media.id], shuffle: false);
    queueNotifier.setRepeat('off');
    await engine.setVideoTrackEnabled(false);
    final startMs = (_parseLyricsOffset(artworkAudioOffsetController.text) ?? 0)
        .clamp(0, 1 << 62);
    final endMs = _parseLyricsOffset(artworkAudioEndController.text) ?? 0;
    await engine.load(
      PlaybackSource(
        mediaId: '${media.id}_timing_preview',
        uri: timingPreviewSourcePath(),
        start: Duration(milliseconds: startMs),
        end: endMs > 0 ? Duration(milliseconds: endMs) : null,
      ),
      autoplay: autoplay,
    );
  }

  Future<void> restoreTimingPreview() async {
    if (!timingPreviewActive) return;
    final engine = ref.read(engineProvider);
    final oldQueue = queueBeforeTimingPreview;
    final oldView = viewBeforeTimingPreview;
    final oldPlayback = playbackBeforeTimingPreview;
    try {
      await engine.pause();
      final validIds = ref
          .read(libraryProvider)
          .media
          .map((item) => item.id)
          .toSet();
      if (oldQueue != null) {
        ref.read(queueProvider.notifier).restore(oldQueue, validIds);
      }
      if (oldView != null) {
        ref.read(playerViewModeProvider.notifier).setEffective(oldView);
      }
      final oldMedia = oldQueue?.currentId == null
          ? null
          : ref.read(libraryProvider).byId(oldQueue!.currentId!);
      if (oldMedia != null && oldPlayback != null && oldPlayback.initialized) {
        var sourcePath = oldMedia.localPath;
        var timelineOffsetMs = 0;
        if (oldView == PlayerViewMode.image) {
          timelineOffsetMs = oldMedia.artworkAudioOffsetMs;
          if (oldMedia.artworkAudioMediaId != null) {
            sourcePath =
                ref
                    .read(libraryProvider)
                    .byId(oldMedia.artworkAudioMediaId!)
                    ?.localPath ??
                sourcePath;
          } else {
            sourcePath = oldMedia.artworkAudioPath ?? sourcePath;
          }
        }
        await engine.setPlaybackRate(oldQueue!.speed);
        await engine.setVideoTrackEnabled(oldView == PlayerViewMode.media);
        final timelineOffset = Duration(milliseconds: timelineOffsetMs);
        await engine.load(
          PlaybackSource(
            mediaId: oldMedia.id,
            uri: sourcePath,
            start: oldPlayback.position + timelineOffset,
            timelineOffset: timelineOffset,
            end:
                oldView == PlayerViewMode.image &&
                    oldMedia.artworkAudioEndMs > 0
                ? Duration(milliseconds: oldMedia.artworkAudioEndMs)
                : null,
          ),
          autoplay: oldPlayback.isPlaying,
        );
      } else {
        await engine.setVideoTrackEnabled(oldView == PlayerViewMode.media);
      }
    } catch (_) {
      // Keep the editor usable even if the previous playback source vanished.
    } finally {
      timingPreviewActive = false;
      queueBeforeTimingPreview = null;
      viewBeforeTimingPreview = null;
      playbackBeforeTimingPreview = null;
    }
  }

  try {
    dialogRoute = DialogRoute<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
        final textColor = themeTextPrimary(dialogContext);
        final subtle = themeTextSub(dialogContext);
        final border = themeBorder(dialogContext);
        return ValueListenableBuilder<bool>(
          valueListenable: allowDialogPop,
          builder: (context, canPop, _) => PopScope<bool>(
            canPop: canPop,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) unawaited(requestDialogClose(dialogContext));
            },
            child: Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
                  decoration: BoxDecoration(
                    color: themeCard(dialogContext),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.35 : 0.12,
                        ),
                        blurRadius: 28,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr('metadata_edit_title'),
                          style: TextStyle(
                            color: textColor,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 22),
                        MetadataField(
                          label: tr('metadata_title'),
                          controller: titleController,
                          autofocus: !focusCreator,
                          textColor: textColor,
                          labelColor: subtle,
                          borderColor: border,
                          isDark: isDark,
                        ),
                        const SizedBox(height: 16),
                        CreatorNamesField(
                          key: creatorFieldKey,
                          initialValue: media.artist,
                          textColor: textColor,
                          labelColor: subtle,
                          borderColor: border,
                          isDark: isDark,
                          strings: tr,
                          autofocusEntry: focusCreator,
                          onChanged: (names) {
                            creatorWasEdited = true;
                            artistController.text = names.join('・');
                          },
                        ),
                        const SizedBox(height: 16),
                        for (final field in [
                          (tr('album'), albumController),
                          (tr('album_artist'), albumArtistController),
                          (tr('disc_number'), discController),
                          (tr('track_number'), trackController),
                        ]) ...[
                          MetadataField(
                            label: field.$1,
                            controller: field.$2,
                            textColor: textColor,
                            labelColor: subtle,
                            borderColor: border,
                            isDark: isDark,
                            keyboardType:
                                field.$2 == trackController ||
                                    field.$2 == discController
                                ? TextInputType.number
                                : null,
                          ),
                          const SizedBox(height: 16),
                        ],
                        StatefulBuilder(
                          builder: (context, setViewState) =>
                              DropdownButtonFormField<MediaViewAvailability>(
                                initialValue: viewAvailability,
                                decoration: InputDecoration(
                                  labelText: tr('player_view_availability'),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                items: [
                                  DropdownMenuItem(
                                    value: MediaViewAvailability.both,
                                    child: Text(tr('view_both')),
                                  ),
                                  DropdownMenuItem(
                                    value: MediaViewAvailability.mediaOnly,
                                    child: Text(tr('view_video_only')),
                                  ),
                                  DropdownMenuItem(
                                    value: MediaViewAvailability.artworkOnly,
                                    child: Text(tr('view_artwork_only')),
                                  ),
                                ],
                                onChanged: (value) {
                                  if (value == null) return;
                                  setViewState(() => viewAvailability = value);
                                },
                              ),
                        ),
                        const SizedBox(height: 16),
                        StatefulBuilder(
                          builder: (context, setDialogState) => Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SwitchListTile.adaptive(
                                contentPadding: EdgeInsets.zero,
                                title: Text(tr('lyrics_separate_timing')),
                                value: separateLyricsByView,
                                onChanged: (value) {
                                  setDialogState(() {
                                    if (value) {
                                      final shared = _parseLyricsOffset(
                                        lyricsOffsetController.text,
                                      );
                                      if (shared != null) {
                                        videoLyricsOffsetController.text =
                                            _formatLyricsOffset(shared);
                                        artworkLyricsOffsetController.text =
                                            _formatLyricsOffset(shared);
                                      }
                                    } else {
                                      if (videoLyricsTimingRelativeToArtwork) {
                                        final artworkOffset =
                                            _parseLyricsOffset(
                                              artworkLyricsOffsetController
                                                  .text,
                                            ) ??
                                            0;
                                        final relativeOffset =
                                            _parseLyricsOffset(
                                              videoLyricsOffsetFromArtworkController
                                                  .text,
                                            ) ??
                                            0;
                                        videoLyricsOffsetController.text =
                                            _formatLyricsOffset(
                                              artworkOffset + relativeOffset,
                                            );
                                        videoLyricsTimingRelativeToArtwork =
                                            false;
                                      }
                                      lyricsOffsetController.text =
                                          videoLyricsOffsetController.text;
                                      if (artworkAudioMediaId == null) {
                                        artworkLyricsOffsetFollowsVideo = true;
                                      }
                                    }
                                    separateLyricsByView = value;
                                  });
                                },
                              ),
                              const SizedBox(height: 6),
                              Text(
                                tr('artwork_audio_source'),
                                style: TextStyle(
                                  color: subtle,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              DropdownButtonFormField<String?>(
                                initialValue: artworkAudioMediaId,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                ),
                                items: [
                                  DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text(
                                      tr('audio_source_same_as_video'),
                                    ),
                                  ),
                                  for (final source in audioSourceChoices)
                                    DropdownMenuItem<String?>(
                                      value: source.id,
                                      child: Text(
                                        displayTitle(source.title),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                                onChanged: (value) => setDialogState(() {
                                  final videoOffset = separateLyricsByView
                                      ? videoLyricsOffsetController.text
                                      : lyricsOffsetController.text;
                                  if (artworkLyricsOffsetFollowsVideo) {
                                    artworkLyricsOffsetController
                                        .text = _formatLyricsOffset(
                                      (_parseLyricsOffset(videoOffset) ?? 0) +
                                          (_parseLyricsOffset(
                                                artworkAudioOffsetController
                                                    .text,
                                              ) ??
                                              0),
                                    );
                                  }
                                  artworkAudioMediaId = value;
                                  artworkAudioPath = null;
                                  selectedArtworkAudioPath = null;
                                  clearArtworkAudio = false;
                                }),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () async {
                                        final result = await FilePicker.platform
                                            .pickFiles(
                                              type: FileType.audio,
                                              allowMultiple: false,
                                              withData: false,
                                            );
                                        final path = result?.files.single.path;
                                        if (path == null) return;
                                        setDialogState(() {
                                          final videoOffset =
                                              separateLyricsByView
                                              ? videoLyricsOffsetController.text
                                              : lyricsOffsetController.text;
                                          if (artworkLyricsOffsetFollowsVideo) {
                                            artworkLyricsOffsetController.text =
                                                videoOffset;
                                          }
                                          selectedArtworkAudioPath = path;
                                          artworkAudioPath = path;
                                          artworkAudioMediaId = null;
                                          clearArtworkAudio = false;
                                        });
                                      },
                                      icon: const Icon(
                                        Icons.audio_file_outlined,
                                      ),
                                      label: Text(tr('choose_audio_file')),
                                    ),
                                  ),
                                  if (artworkAudioPath != null ||
                                      selectedArtworkAudioPath != null)
                                    IconButton(
                                      tooltip: tr('clear_audio_source'),
                                      onPressed: () => setDialogState(() {
                                        artworkAudioPath = null;
                                        selectedArtworkAudioPath = null;
                                        artworkAudioMediaId = null;
                                        clearArtworkAudio = true;
                                      }),
                                      icon: const Icon(
                                        Icons.delete_outline_rounded,
                                      ),
                                    ),
                                ],
                              ),
                              if (artworkAudioPath != null ||
                                  selectedArtworkAudioPath != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  (selectedArtworkAudioPath ??
                                          artworkAudioPath)!
                                      .split(Platform.pathSeparator)
                                      .last,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: themeTextSub(context),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 4),
                              Text(
                                tr('artwork_audio_source_hint'),
                                style: TextStyle(color: subtle, fontSize: 11),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    await showDialog<void>(
                                      context: dialogContext,
                                      barrierDismissible: false,
                                      builder: (_) => ArtworkAudioTimingEditor(
                                        engine: ref.read(engineProvider),
                                        sourcePath: timingPreviewSourcePath(),
                                        startController:
                                            artworkAudioOffsetController,
                                        endController:
                                            artworkAudioEndController,
                                        onPreparePreview: startTimingPreview,
                                        onRestorePlayback: restoreTimingPreview,
                                        onError: (error) =>
                                            messenger.showSnackBar(
                                              SnackBar(content: Text('$error')),
                                            ),
                                        tr: tr,
                                      ),
                                    );
                                    setDialogState(() {});
                                  },
                                  icon: const Icon(Icons.tune_rounded),
                                  label: Text(tr('adjust_audio_position')),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${tr('trim_start')}: ${artworkAudioOffsetController.text}  ·  '
                                '${tr('trim_end')}: ${artworkAudioEndController.text.trim().isEmpty ? tr('source_end') : artworkAudioEndController.text}',
                                style: TextStyle(color: subtle, fontSize: 11),
                              ),
                              const SizedBox(height: 4),
                              SwitchListTile.adaptive(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  tr('video_timing_relative_to_artwork'),
                                ),
                                value: videoLyricsTimingRelativeToArtwork,
                                onChanged: (value) => setDialogState(() {
                                  if (value) {
                                    final videoOffset =
                                        _parseLyricsOffset(
                                          videoLyricsOffsetController.text,
                                        ) ??
                                        _parseLyricsOffset(
                                          lyricsOffsetController.text,
                                        ) ??
                                        0;
                                    final artworkOffset =
                                        _parseLyricsOffset(
                                          artworkLyricsOffsetController.text,
                                        ) ??
                                        0;
                                    videoLyricsOffsetFromArtworkController
                                        .text = _formatLyricsOffset(
                                      videoOffset - artworkOffset,
                                    );
                                    separateLyricsByView = true;
                                    artworkLyricsOffsetFollowsVideo = false;
                                  } else {
                                    final artworkOffset =
                                        _parseLyricsOffset(
                                          artworkLyricsOffsetController.text,
                                        ) ??
                                        0;
                                    final relativeOffset =
                                        _parseLyricsOffset(
                                          videoLyricsOffsetFromArtworkController
                                              .text,
                                        ) ??
                                        0;
                                    videoLyricsOffsetController.text =
                                        _formatLyricsOffset(
                                          artworkOffset + relativeOffset,
                                        );
                                  }
                                  videoLyricsTimingRelativeToArtwork = value;
                                }),
                              ),
                              if (!videoLyricsTimingRelativeToArtwork)
                                SwitchListTile.adaptive(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(
                                    tr('artwork_timing_follows_video'),
                                  ),
                                  value: artworkLyricsOffsetFollowsVideo,
                                  onChanged: (value) => setDialogState(() {
                                    if (!artworkLyricsOffsetFollowsVideo) {
                                      final videoOffset = separateLyricsByView
                                          ? videoLyricsOffsetController.text
                                          : lyricsOffsetController.text;
                                      artworkLyricsOffsetController
                                          .text = _formatLyricsOffset(
                                        (_parseLyricsOffset(videoOffset) ?? 0) -
                                            (_parseLyricsOffset(
                                                  artworkAudioOffsetController
                                                      .text,
                                                ) ??
                                                0),
                                      );
                                    }
                                    artworkLyricsOffsetFollowsVideo = value;
                                  }),
                                ),
                              if (videoLyricsTimingRelativeToArtwork) ...[
                                MetadataField(
                                  label: tr('lyrics_timing_for_artwork'),
                                  controller: artworkLyricsOffsetController,
                                  textColor: textColor,
                                  labelColor: subtle,
                                  borderColor: border,
                                  isDark: isDark,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                        signed: true,
                                      ),
                                ),
                                const SizedBox(height: 12),
                                MetadataField(
                                  label: tr('video_timing_from_artwork'),
                                  controller:
                                      videoLyricsOffsetFromArtworkController,
                                  textColor: textColor,
                                  labelColor: subtle,
                                  borderColor: border,
                                  isDark: isDark,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                        signed: true,
                                      ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  tr('video_timing_from_artwork_hint'),
                                  style: TextStyle(color: subtle, fontSize: 11),
                                ),
                              ] else if (separateLyricsByView ||
                                  artworkAudioMediaId != null ||
                                  artworkAudioPath != null ||
                                  !artworkLyricsOffsetFollowsVideo) ...[
                                MetadataField(
                                  label: tr('lyrics_timing_for_video'),
                                  controller: videoLyricsOffsetController,
                                  textColor: textColor,
                                  labelColor: subtle,
                                  borderColor: border,
                                  isDark: isDark,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                        signed: true,
                                      ),
                                  enabled: separateLyricsByView,
                                ),
                                const SizedBox(height: 12),
                                MetadataField(
                                  label: tr('lyrics_timing_for_artwork'),
                                  controller: artworkLyricsOffsetController,
                                  textColor: textColor,
                                  labelColor: subtle,
                                  borderColor: border,
                                  isDark: isDark,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                        signed: true,
                                      ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  tr('lyrics_timing_hint'),
                                  style: TextStyle(color: subtle, fontSize: 11),
                                ),
                              ] else ...[
                                MetadataField(
                                  label: tr('lyrics_timing'),
                                  controller: lyricsOffsetController,
                                  textColor: textColor,
                                  labelColor: subtle,
                                  borderColor: border,
                                  isDark: isDark,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                        signed: true,
                                      ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  tr('lyrics_timing_hint'),
                                  style: TextStyle(color: subtle, fontSize: 11),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (media.lyricsPath != null) ...[
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              onPressed: () => requestDialogClose(
                                dialogContext,
                                openLyrics: true,
                              ),
                              icon: const Icon(Icons.edit_note_rounded),
                              label: Text(tr('lyrics_editor_title')),
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        StatefulBuilder(
                          builder: (context, setDialogState) {
                            Widget imageSelector({
                              required String label,
                              required String? existingPath,
                              required String? selectedPath,
                              required bool cleared,
                              required String? pendingPath,
                              required bool pendingClear,
                              required IconData icon,
                              required ValueChanged<String> onChoose,
                              required VoidCallback onClear,
                              required VoidCallback onConfirm,
                            }) {
                              final currentPath = cleared
                                  ? null
                                  : (selectedPath ?? existingPath);
                              final previewPath = pendingClear
                                  ? null
                                  : (pendingPath ?? currentPath);
                              final hasPendingChoice =
                                  pendingClear || pendingPath != null;
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    label,
                                    style: TextStyle(
                                      color: subtle,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: SizedBox(
                                          width: 56,
                                          height: 56,
                                          child: previewPath == null
                                              ? ColoredBox(
                                                  color: const Color(
                                                    0x22000000,
                                                  ),
                                                  child: Icon(icon),
                                                )
                                              : Image.file(
                                                  File(previewPath),
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, _, _) =>
                                                      const Icon(
                                                        Icons
                                                            .broken_image_outlined,
                                                      ),
                                                ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      OutlinedButton.icon(
                                        icon: Icon(icon),
                                        label: Text(tr('choose_artwork')),
                                        onPressed: () async {
                                          final result = await FilePicker
                                              .platform
                                              .pickFiles(
                                                type: FileType.image,
                                                allowMultiple: false,
                                                withData: false,
                                              );
                                          final path =
                                              result?.files.single.path;
                                          if (path != null) {
                                            setDialogState(
                                              () => onChoose(path),
                                            );
                                          }
                                        },
                                      ),
                                      if (previewPath != null)
                                        IconButton(
                                          tooltip: tr('clear_artwork'),
                                          icon: const Icon(
                                            Icons.delete_outline_rounded,
                                          ),
                                          onPressed: () => setDialogState(() {
                                            onClear();
                                          }),
                                        ),
                                    ],
                                  ),
                                  if (hasPendingChoice) ...[
                                    const SizedBox(height: 8),
                                    FilledButton.icon(
                                      icon: const Icon(Icons.check_rounded),
                                      label: Text(tr('confirm_image_choice')),
                                      onPressed: () => setDialogState(() {
                                        onConfirm();
                                      }),
                                    ),
                                  ],
                                ],
                              );
                            }

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                imageSelector(
                                  label: tr('artwork'),
                                  existingPath: media.artworkPath,
                                  selectedPath: selectedArtworkPath,
                                  cleared: clearArtwork,
                                  pendingPath: pendingArtworkPath,
                                  pendingClear: pendingClearArtwork,
                                  icon: Icons.album_outlined,
                                  onChoose: (path) {
                                    pendingArtworkPath = path;
                                    pendingClearArtwork = false;
                                  },
                                  onClear: () {
                                    pendingArtworkPath = null;
                                    pendingClearArtwork = true;
                                  },
                                  onConfirm: () {
                                    selectedArtworkPath = pendingArtworkPath;
                                    clearArtwork = pendingClearArtwork;
                                    pendingArtworkPath = null;
                                    pendingClearArtwork = false;
                                  },
                                ),
                                const SizedBox(height: 16),
                                imageSelector(
                                  label: tr('thumbnail_label'),
                                  existingPath: media.thumbnailPath,
                                  selectedPath: selectedThumbnailPath,
                                  cleared: clearThumbnail,
                                  pendingPath: pendingThumbnailPath,
                                  pendingClear: pendingClearThumbnail,
                                  icon: Icons.image_outlined,
                                  onChoose: (path) {
                                    pendingThumbnailPath = path;
                                    pendingClearThumbnail = false;
                                  },
                                  onClear: () {
                                    pendingThumbnailPath = null;
                                    pendingClearThumbnail = true;
                                  },
                                  onConfirm: () {
                                    selectedThumbnailPath =
                                        pendingThumbnailPath;
                                    clearThumbnail = pendingClearThumbnail;
                                    pendingThumbnailPath = null;
                                    pendingClearThumbnail = false;
                                  },
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 24),
                        OverflowBar(
                          alignment: MainAxisAlignment.spaceBetween,
                          overflowAlignment: OverflowBarAlignment.end,
                          spacing: 8,
                          overflowSpacing: 4,
                          children: [
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.redAccent,
                              ),
                              icon: const Icon(Icons.delete_outline_rounded),
                              label: Text(tr('delete_from_library_short')),
                              onPressed: () async {
                                final confirmed = await showDialog<bool>(
                                  context: dialogContext,
                                  builder: (confirmContext) => AlertDialog(
                                    title: Text(tr('delete_from_library')),
                                    content: Text(
                                      tr(
                                        'remove_media_confirm',
                                      ).replaceAll('{title}', media.title),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(
                                          confirmContext,
                                          false,
                                        ),
                                        child: Text(tr('cancel')),
                                      ),
                                      FilledButton(
                                        style: FilledButton.styleFrom(
                                          backgroundColor: Colors.redAccent,
                                        ),
                                        onPressed: () =>
                                            Navigator.pop(confirmContext, true),
                                        child: Text(tr('delete')),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed == true) {
                                  deleteMediaAfterClose = true;
                                  if (dialogContext.mounted) {
                                    await closeDialogRoute(
                                      dialogContext,
                                      result: false,
                                    );
                                  }
                                }
                              },
                            ),
                            TextButton(
                              style: TextButton.styleFrom(
                                foregroundColor: subtle,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: () =>
                                  requestDialogClose(dialogContext),
                              child: Text(tr('cancel')),
                            ),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: textColor,
                                foregroundColor: themeCard(dialogContext),
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              onPressed: () async {
                                FocusManager.instance.primaryFocus?.unfocus();
                                final discText = discController.text.trim();
                                final disc = int.tryParse(discText);
                                if (discText.isNotEmpty &&
                                    (disc == null || disc < 1)) {
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(tr('invalid_disc_number')),
                                    ),
                                  );
                                  return;
                                }
                                final text = trackController.text.trim();
                                final number = int.tryParse(text);
                                if (text.isNotEmpty &&
                                    (number == null || number < 1)) {
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(tr('invalid_track_number')),
                                    ),
                                  );
                                  return;
                                }
                                final timingIsValid =
                                    videoLyricsTimingRelativeToArtwork
                                    ? _parseLyricsOffset(
                                                artworkLyricsOffsetController
                                                    .text,
                                              ) !=
                                              null &&
                                          _parseLyricsOffset(
                                                videoLyricsOffsetFromArtworkController
                                                    .text,
                                              ) !=
                                              null
                                    : separateLyricsByView ||
                                          artworkAudioMediaId != null ||
                                          artworkAudioPath != null ||
                                          !artworkLyricsOffsetFollowsVideo
                                    ? _parseLyricsOffset(
                                                videoLyricsOffsetController
                                                    .text,
                                              ) !=
                                              null &&
                                          _parseLyricsOffset(
                                                artworkLyricsOffsetController
                                                    .text,
                                              ) !=
                                              null
                                    : _parseLyricsOffset(
                                            lyricsOffsetController.text,
                                          ) !=
                                          null;
                                if (!timingIsValid) {
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        tr('invalid_lyrics_timing'),
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                final audioStartMs = _parseLyricsOffset(
                                  artworkAudioOffsetController.text,
                                );
                                final audioEndText = artworkAudioEndController
                                    .text
                                    .trim();
                                final audioEndMs = audioEndText.isEmpty
                                    ? null
                                    : _parseLyricsOffset(audioEndText);
                                if (audioStartMs == null ||
                                    (audioEndText.isNotEmpty &&
                                        (audioEndMs == null ||
                                            audioEndMs < 0))) {
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        tr('invalid_lyrics_timing'),
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                if (audioEndMs != null &&
                                    audioEndMs > 0 &&
                                    audioEndMs <=
                                        audioStartMs.clamp(0, 1 << 62)) {
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(tr('trim_end_after_start')),
                                    ),
                                  );
                                  return;
                                }
                                creatorFieldKey.currentState
                                    ?.commitPendingInput();
                                await closeDialogRoute(
                                  dialogContext,
                                  result: true,
                                );
                              },
                              child: Text(tr('save')),
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
        );
      },
    );
    final save = await Navigator.of(
      context,
      rootNavigator: true,
    ).push(dialogRoute);
    if (deleteMediaAfterClose) {
      await dialogRoute.completed;
      if (!context.mounted) return;
      await ref.read(playbackControllerProvider).handleMediaRemoved(media.id);
      await ref.read(libraryProvider.notifier).removeMedia(media.id);
      return;
    }
    if (editLyricsAfterClose) {
      await dialogRoute.completed;
      if (context.mounted) await _showLyricsEditor(context, ref, media);
      return;
    }
    if (save != true || !context.mounted) return;
    final offsetMs = _parseLyricsOffset(lyricsOffsetController.text) ?? 0;
    final needsSeparateTiming =
        separateLyricsByView ||
        videoLyricsTimingRelativeToArtwork ||
        artworkAudioMediaId != null ||
        artworkAudioPath != null ||
        !artworkLyricsOffsetFollowsVideo;
    final artworkOffsetMs = needsSeparateTiming
        ? _parseLyricsOffset(artworkLyricsOffsetController.text)
        : null;
    final videoOffsetMs = videoLyricsTimingRelativeToArtwork
        ? artworkOffsetMs == null
              ? null
              : artworkOffsetMs +
                    (_parseLyricsOffset(
                          videoLyricsOffsetFromArtworkController.text,
                        ) ??
                        0)
        : separateLyricsByView
        ? _parseLyricsOffset(videoLyricsOffsetController.text)
        : null;
    if (needsSeparateTiming &&
        (artworkOffsetMs == null ||
            ((separateLyricsByView || videoLyricsTimingRelativeToArtwork) &&
                videoOffsetMs == null))) {
      messenger.showSnackBar(
        SnackBar(content: Text(tr('invalid_lyrics_timing'))),
      );
      return;
    }
    final artworkAudioOffsetMs = _parseLyricsOffset(
      artworkAudioOffsetController.text,
    );
    if (artworkAudioOffsetMs == null) {
      messenger.showSnackBar(
        SnackBar(content: Text(tr('invalid_lyrics_timing'))),
      );
      return;
    }
    final artworkAudioEndMs = _parseLyricsOffset(
      artworkAudioEndController.text,
    );
    if (artworkAudioEndController.text.trim().isNotEmpty &&
        (artworkAudioEndMs == null || artworkAudioEndMs < 0)) {
      messenger.showSnackBar(
        SnackBar(content: Text(tr('invalid_lyrics_timing'))),
      );
      return;
    }
    if (artworkAudioEndMs != null &&
        artworkAudioEndMs > 0 &&
        artworkAudioEndMs <= artworkAudioOffsetMs.clamp(0, 1 << 62)) {
      messenger.showSnackBar(
        SnackBar(content: Text(tr('trim_end_after_start'))),
      );
      return;
    }

    final numberText = trackController.text.trim();
    final number = int.tryParse(numberText);
    if (numberText.isNotEmpty && (number == null || number < 1)) {
      messenger.showSnackBar(
        SnackBar(content: Text(tr('invalid_track_number'))),
      );
      return;
    }
    String? nullableText(TextEditingController controller) =>
        controller.text.trim().isEmpty ? null : controller.text.trim();
    // Clearing all creator chips and saving intentionally stores a whitespace
    // marker: it hides the creator and disables the blank-area edit shortcut.
    // The media settings editor can still reopen and restore the field.
    final artistValue = creatorWasEdited
        ? (artistController.text.trim().isEmpty
              ? ' '
              : artistController.text.trim())
        : media.artist;

    String? artworkPath = media.artworkPath;
    if (selectedArtworkPath != null) {
      try {
        final dir = await getApplicationSupportDirectory();
        final artworkDir = Directory('${dir.path}/yureru_artwork');
        await artworkDir.create(recursive: true);
        final ext = selectedArtworkPath!.split('.').last.toLowerCase();
        final destination =
            '${artworkDir.path}/${media.id}_${DateTime.now().microsecondsSinceEpoch}.$ext';
        await File(selectedArtworkPath!).copy(destination);
        artworkPath = destination;
      } catch (error) {
        if (context.mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                tr('artwork_save_error').replaceAll('{error}', '$error'),
              ),
            ),
          );
        }
      }
    } else if (clearArtwork) {
      artworkPath = null;
    }
    String? thumbnailPath = media.thumbnailPath;
    if (selectedThumbnailPath != null) {
      try {
        final dir = await getApplicationSupportDirectory();
        final thumbnailDir = Directory('${dir.path}/yureru_thumbnails');
        await thumbnailDir.create(recursive: true);
        final ext = selectedThumbnailPath!.split('.').last.toLowerCase();
        final destination =
            '${thumbnailDir.path}/${media.id}_${DateTime.now().microsecondsSinceEpoch}.$ext';
        await File(selectedThumbnailPath!).copy(destination);
        thumbnailPath = destination;
      } catch (error) {
        if (context.mounted) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                tr('thumbnail_change_failed').replaceAll('{error}', '$error'),
              ),
            ),
          );
        }
      }
    } else if (clearThumbnail) {
      thumbnailPath = null;
    }
    String? artworkAudioPathValue = artworkAudioPath;
    if (selectedArtworkAudioPath != null) {
      try {
        final support = await getApplicationSupportDirectory();
        final audioDir = Directory('${support.path}/yureru_audio_sources');
        await audioDir.create(recursive: true);
        final extension = selectedArtworkAudioPath!
            .split('.')
            .last
            .toLowerCase();
        final destination =
            '${audioDir.path}/${media.id}_${DateTime.now().microsecondsSinceEpoch}.$extension';
        await File(selectedArtworkAudioPath!).copy(destination);
        artworkAudioPathValue = destination;
      } catch (error) {
        if (context.mounted) {
          messenger.showSnackBar(SnackBar(content: Text('$error')));
        }
        return;
      }
    } else if (clearArtworkAudio) {
      artworkAudioPathValue = null;
    }
    try {
      await ref
          .read(libraryProvider.notifier)
          .updateMediaDetails(
            media.id,
            title: titleController.text.trim(),
            artist: artistValue,
            album: nullableText(albumController),
            albumArtist: nullableText(albumArtistController),
            trackNumber: number,
            discNumber: int.tryParse(discController.text.trim()),
            artworkPath: artworkPath,
            viewAvailability: viewAvailability,
            thumbnailPath: thumbnailPath,
            lyricsOffsetMs: offsetMs,
            separateLyricsByView: separateLyricsByView,
            videoLyricsOffsetMs: videoOffsetMs,
            artworkLyricsOffsetMs: artworkOffsetMs,
            artworkLyricsOffsetFollowsVideo: videoLyricsTimingRelativeToArtwork
                ? false
                : artworkLyricsOffsetFollowsVideo,
            artworkAudioMediaId: artworkAudioMediaId,
            artworkAudioPath: artworkAudioPathValue,
            artworkAudioOffsetMs: artworkAudioOffsetMs,
            artworkAudioEndMs: artworkAudioEndMs ?? 0,
          );
    } catch (error) {
      if (context.mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              tr('media_details_save_error').replaceAll('{error}', '$error'),
            ),
          ),
        );
      }
      return;
    }
    final queue = ref.read(queueProvider);
    // Metadata edits should not restart the current video. Only refresh the
    // playback source when editing the currently displayed jacket/audio view.
    if (queue.currentId == media.id &&
        ref.read(playerViewModeProvider) == PlayerViewMode.image) {
      try {
        await ref.read(playbackControllerProvider).syncCurrentViewSource();
      } catch (_) {
        // The metadata has already been persisted; a playback refresh failure
        // must not make the save appear to have failed.
      }
    }
    if (context.mounted) {
      messenger.showSnackBar(
        SnackBar(content: Text(tr('media_details_saved'))),
      );
    }
  } finally {
    // The route remains mounted while its closing animation runs.
    if (dialogRoute != null) await dialogRoute.completed;
    await restoreTimingPreview();
    titleController.dispose();
    artistController.dispose();
    albumController.dispose();
    albumArtistController.dispose();
    trackController.dispose();
    discController.dispose();
    lyricsOffsetController.dispose();
    videoLyricsOffsetController.dispose();
    artworkLyricsOffsetController.dispose();
    artworkAudioOffsetController.dispose();
    artworkAudioEndController.dispose();
    videoLyricsOffsetFromArtworkController.dispose();
    allowDialogPop.dispose();
  }
}

Future<void> _showLyricsEditor(
  BuildContext context,
  WidgetRef ref,
  MediaItem media,
) async {
  final path = media.lyricsPath;
  if (path == null) return;
  String initialText = '';
  try {
    initialText = await File(path).readAsString();
  } catch (_) {
    // Keep the editor available so the user can replace a missing lyrics file.
  }
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => LyricsEditorDialog(
      media: media,
      engine: ref.read(engineProvider),
      initialText: initialText,
      initialSynchronized: path.toLowerCase().endsWith('.lrc'),
      onSaved: (newPath) => ref
          .read(libraryProvider.notifier)
          .updateMediaLyrics(media.id, newPath),
      onDraftSaved: (newPath) => ref
          .read(libraryProvider.notifier)
          .updateMediaLyrics(media.id, newPath),
      onFinalized: () => ref
          .read(libraryProvider.notifier)
          .setLyricsEditingFinalized(media.id, true),
    ),
  );
}

String _formatLyricsOffset(int milliseconds) =>
    (milliseconds / 1000).toStringAsFixed(2);

int? _parseLyricsOffset(String input) {
  final value = input.trim();
  if (value.contains(':')) {
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final minutes = int.tryParse(parts[0]);
    final seconds = double.tryParse(parts[1]);
    if (minutes == null || seconds == null || seconds < 0 || seconds >= 60) {
      return null;
    }
    return ((minutes * 60 + seconds) * 1000).round().clamp(-600000, 600000);
  }
  final seconds = double.tryParse(value);
  if (seconds == null || !seconds.isFinite) return null;
  return (seconds * 1000).round().clamp(-600000, 600000);
}
