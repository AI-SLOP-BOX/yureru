import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../app_state.dart';
import '../../data/importer.dart' show isVideoPath;
import '../../data/lyrics.dart';
import '../../domain/models.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets/lyrics_editor_dialog.dart';
import '../widgets/thumb_image.dart';
import '../../playback/playback_controller.dart';

class LyricsSettingsScreen extends ConsumerStatefulWidget {
  const LyricsSettingsScreen({super.key});

  @override
  ConsumerState<LyricsSettingsScreen> createState() =>
      _LyricsSettingsScreenState();
}

class _LyricsSettingsScreenState extends ConsumerState<LyricsSettingsScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = ref.watch(libraryProvider).savedMedia;
    final query = _query.trim().toLowerCase();
    final filtered = media.where((item) {
      if (query.isEmpty) return true;
      return item.title.toLowerCase().contains(query) ||
          (item.artist?.toLowerCase().contains(query) ?? false);
    }).toList();

    return Scaffold(
      appBar: AppBar(title: Text(ref.tr('lyrics_settings'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: ref.tr('search_media'),
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: ref.tr('clear'),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(child: Text(ref.tr('no_media')))
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      final hasSeparate = item.separateLyricsByView;
                      return ListTile(
                        leading: ThumbImage(
                          seed: item.id,
                          mediaId: item.id,
                          localPath: item.localPath,
                          imageContext: MediaImageContext.home,
                          size: 44,
                          radius: 8,
                        ),
                        title: Text(displayTitle(item.title)),
                        subtitle: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 5,
                          children: [
                            Icon(
                              isVideoPath(item.localPath)
                                  ? Icons.movie_outlined
                                  : Icons.graphic_eq_rounded,
                              size: 15,
                              color: themeTextSub(context),
                            ),
                            Text(
                              ref.tr(
                                isVideoPath(item.localPath)
                                    ? 'media_kind_mv'
                                    : 'media_kind_audio',
                              ),
                            ),
                            const Text('·'),
                            Text(
                              item.lyricsButtonHidden
                                  ? ref.tr('lyrics_button_hidden')
                                  : hasSeparate
                                  ? ref.tr('lyrics_separate_enabled')
                                  : item.lyricsPath == null
                                  ? ref.tr('lyrics_not_configured')
                                  : ref.tr('lyrics_shared_enabled'),
                            ),
                          ],
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                LyricsMediaSettingsScreen(mediaId: item.id),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class LyricsMediaSettingsScreen extends ConsumerStatefulWidget {
  const LyricsMediaSettingsScreen({super.key, required this.mediaId});

  final String mediaId;

  @override
  ConsumerState<LyricsMediaSettingsScreen> createState() =>
      _LyricsMediaSettingsScreenState();
}

class _LyricsMediaSettingsScreenState
    extends ConsumerState<LyricsMediaSettingsScreen> {
  final _offsetController = TextEditingController();
  final _globalShiftController = TextEditingController(text: '0.00');
  PlayerViewMode _viewMode = PlayerViewMode.media;
  int? _editingOffsetFor;

  @override
  void dispose() {
    _offsetController.dispose();
    _globalShiftController.dispose();
    super.dispose();
  }

  bool get _artwork => _viewMode == PlayerViewMode.image;

  Future<void> _playForLyricsSync(MediaItem media) async {
    final queue = ref.read(queueProvider);
    final remaining = queue.queue.where((id) => id != media.id).toList();
    ref.read(lyricsEditorRequestProvider.notifier).state = media.id;
    ref.read(playerViewModeProvider.notifier).state = _viewMode;
    await ref
        .read(libraryProvider.notifier)
        .setLyricsButtonHidden(media.id, false);
    ref.read(queueProvider.notifier).start([
      media.id,
      ...remaining,
    ], shuffle: false);
    await ref.read(engineProvider).setVideoTrackEnabled(!_artwork);
    await ref.read(playbackControllerProvider).openCurrent();
    if (!mounted) return;
    if (!ref.read(engineProvider).snapshot.isPlaying) {
      await ref.read(engineProvider).play();
    }
    ref.read(lyricsPanelProvider.notifier).state = true;
    ref.read(queueVisibleProvider.notifier).state = true;
    showPlayerView(ref);
  }

  Future<void> _chooseLyrics(MediaItem media) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['lrc', 'txt'],
      allowMultiple: false,
      withData: false,
    );
    final source = result?.files.single.path;
    if (source == null) return;
    try {
      final support = await getApplicationSupportDirectory();
      final directory = Directory('${support.path}/yureru_lyrics');
      await directory.create(recursive: true);
      final extension = source.toLowerCase().endsWith('.lrc') ? 'lrc' : 'txt';
      final path =
          '${directory.path}/${media.id}_${_artwork ? 'art' : 'video'}_${DateTime.now().microsecondsSinceEpoch}.$extension';
      await File(source).copy(path);
      await ref
          .read(libraryProvider.notifier)
          .updateMediaLyricsForView(media.id, artwork: _artwork, path: path);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${ref.tr('lyrics_load_error')}: $error')),
      );
    }
  }

  Future<String> _initialText(MediaItem media, String? path) async {
    if (path != null) {
      try {
        return await File(path).readAsString();
      } catch (_) {}
    }
    if (media.separateLyricsByView) {
      // A new variant starts from the shared text, which can then be adapted.
      if (media.lyricsPath != null) {
        try {
          return await File(media.lyricsPath!).readAsString();
        } catch (_) {}
      }
    }
    if (ref.read(queueProvider).currentId == media.id) {
      return await ref.read(engineProvider).readEmbeddedLyrics() ?? '';
    }
    return '';
  }

  Future<void> _editLyrics(MediaItem media, String? path) async {
    final text = await _initialText(media, path);
    if (!mounted) return;
    // Keep the editor on this settings page, but load the selected MV into the
    // shared playback engine so its video surface is available inside the LRC
    // editor while timing lines.
    if (isVideoPath(media.localPath)) {
      final queue = ref.read(queueProvider);
      final remaining = queue.queue.where((id) => id != media.id).toList();
      ref.read(playerViewModeProvider.notifier).state = _viewMode;
      ref.read(queueProvider.notifier).start([
        media.id,
        ...remaining,
      ], shuffle: false);
      await ref.read(engineProvider).setVideoTrackEnabled(!_artwork);
      await ref.read(playbackControllerProvider).openCurrent();
      if (!mounted) return;
      if (!ref.read(engineProvider).snapshot.isPlaying) {
        await ref.read(engineProvider).play();
      }
      if (!mounted) return;
    }
    await showDialog<void>(
      context: context,
      builder: (_) => LyricsEditorDialog(
        media: media,
        engine: ref.read(engineProvider),
        initialText: text,
        viewMode: _viewMode,
        initialSynchronized:
            path?.toLowerCase().endsWith('.lrc') ?? parseLrc(text).isNotEmpty,
        onSaved: (newPath) => ref
            .read(libraryProvider.notifier)
            .updateMediaLyricsForView(
              media.id,
              artwork: _artwork,
              path: newPath,
            ),
        advancedLrcTools: true,
        onDraftSaved: (newPath) => ref
            .read(libraryProvider.notifier)
            .updateMediaLyricsForView(
              media.id,
              artwork: _artwork,
              path: newPath,
            ),
        onFinalized: () => ref
            .read(libraryProvider.notifier)
            .setLyricsEditingFinalized(media.id, true),
      ),
    );
  }

  Future<void> _chooseTranslationLyrics(MediaItem media) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt'],
      allowMultiple: false,
      withData: false,
    );
    final source = result?.files.single.path;
    if (source == null) return;
    try {
      final support = await getApplicationSupportDirectory();
      final directory = Directory('${support.path}/yureru_lyrics');
      await directory.create(recursive: true);
      final path =
          '${directory.path}/${media.id}_translation_${DateTime.now().microsecondsSinceEpoch}.txt';
      await File(source).copy(path);
      await ref
          .read(libraryProvider.notifier)
          .updateTranslatedLyrics(media.id, path);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${ref.tr('lyrics_load_error')}: $error')),
      );
    }
  }

  Future<void> _editTranslationLyrics(MediaItem media) async {
    final path = media.translatedLyricsPath;
    var initialText = '';
    if (path != null) {
      try {
        initialText = await File(path).readAsString();
      } catch (_) {}
    }
    if (!mounted) return;
    Future<void> saveTranslation(String newPath) => ref
        .read(libraryProvider.notifier)
        .updateTranslatedLyrics(media.id, newPath);
    await showDialog<void>(
      context: context,
      builder: (_) => LyricsEditorDialog(
        media: media,
        engine: ref.read(engineProvider),
        initialText: initialText,
        initialSynchronized: false,
        viewMode: _viewMode,
        onSaved: saveTranslation,
        onDraftSaved: saveTranslation,
      ),
    );
  }

  Future<void> _copyLyricsFromOtherView(
    MediaItem media,
    String? sourcePath,
  ) async {
    if (sourcePath == null) return;
    try {
      final support = await getApplicationSupportDirectory();
      final directory = Directory('${support.path}/yureru_lyrics');
      await directory.create(recursive: true);
      final extension = sourcePath.toLowerCase().endsWith('.lrc')
          ? 'lrc'
          : 'txt';
      final targetPath =
          '${directory.path}/${media.id}_${_artwork ? 'art' : 'video'}_copy_${DateTime.now().microsecondsSinceEpoch}.$extension';
      await File(sourcePath).copy(targetPath);
      await ref
          .read(libraryProvider.notifier)
          .updateMediaLyricsForView(
            media.id,
            artwork: _artwork,
            path: targetPath,
          );
      await ref
          .read(libraryProvider.notifier)
          .updateMediaLyricsOffsetForView(
            media.id,
            artwork: _artwork,
            offsetMs: media.lyricsOffsetForView(artwork: !_artwork),
          );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${ref.tr('lyrics_load_error')}: $error')),
      );
    }
  }

  Future<void> _saveOffset(MediaItem media) async {
    final offset = _parseOffset(_offsetController.text);
    if (offset == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(ref.tr('invalid_lyrics_timing'))));
      return;
    }
    await ref
        .read(libraryProvider.notifier)
        .updateMediaLyricsOffsetForView(
          media.id,
          artwork: _artwork,
          offsetMs: offset,
        );
    if (!mounted) return;
    setState(() => _editingOffsetFor = null);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(ref.tr('save'))));
  }

  Future<void> _applyGlobalShift(MediaItem media, String? path) async {
    final seconds = double.tryParse(_globalShiftController.text.trim());
    if (seconds == null || !seconds.isFinite || path == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ref.tr('lyrics_editor_invalid_shift'))),
      );
      return;
    }
    try {
      final source = await File(path).readAsString();
      final timestampPattern = RegExp(
        r'\[(?:(\d+):)?(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]',
      );
      if (!timestampPattern.hasMatch(source)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ref.tr('lyrics_no_timestamps_to_shift'))),
        );
        return;
      }
      final shifted = shiftLrcTimestamps(source, (seconds * 1000).round());
      final support = await getApplicationSupportDirectory();
      final directory = Directory('${support.path}/yureru_lyrics');
      await directory.create(recursive: true);
      final destination =
          '${directory.path}/${media.id}_${_artwork ? 'art' : 'video'}_shifted_${DateTime.now().microsecondsSinceEpoch}.lrc';
      await File(destination).writeAsString(shifted);
      await ref
          .read(libraryProvider.notifier)
          .updateMediaLyricsForView(
            media.id,
            artwork: _artwork,
            path: destination,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ref.tr('lyrics_global_shift_applied'))),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${ref.tr('lyrics_load_error')}: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = ref.watch(libraryProvider).byId(widget.mediaId);
    if (media == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(ref.tr('not_found'))),
      );
    }
    final path = media.lyricsPathForView(artwork: _artwork);
    final offsetMs = media.lyricsOffsetForView(artwork: _artwork);
    if (_editingOffsetFor != offsetMs) {
      _editingOffsetFor = offsetMs;
      _offsetController.text = (offsetMs / 1000).toStringAsFixed(2);
    }
    final hasSeparate = media.separateLyricsByView;
    final hasOwnLyrics =
        !hasSeparate ||
        (_artwork ? media.artworkLyricsPath : media.videoLyricsPath) != null;
    final otherViewLyricsPath = media.lyricsPathForView(artwork: !_artwork);
    return Scaffold(
      appBar: AppBar(title: Text(displayTitle(media.title))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  ThumbImage(
                    seed: media.id,
                    mediaId: media.id,
                    localPath: media.localPath,
                    imageContext: MediaImageContext.home,
                    size: 64,
                    radius: 10,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayTitle(media.title),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            _MediaKindChip(
                              isVideo: isVideoPath(media.localPath),
                            ),
                            Chip(
                              visualDensity: VisualDensity.compact,
                              avatar: const Icon(
                                Icons.lyrics_outlined,
                                size: 16,
                              ),
                              label: Text(ref.tr('lyrics_edit')),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (media.lyricsButtonHidden)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.lyrics_outlined),
              title: Text(ref.tr('lyrics_button_hidden')),
              trailing: TextButton(
                onPressed: () => ref
                    .read(libraryProvider.notifier)
                    .setLyricsButtonHidden(media.id, false),
                child: Text(ref.tr('show_lyrics_button')),
              ),
            ),
          if (media.lyricsEditingFinalized)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.done_all_rounded),
              title: Text(ref.tr('lyrics_finalized')),
              trailing: TextButton(
                onPressed: () => ref
                    .read(libraryProvider.notifier)
                    .setLyricsEditingFinalized(media.id, false),
                child: Text(ref.tr('restore_lyrics_edit_mark')),
              ),
            ),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(ref.tr('lyrics_separate_by_view')),
            subtitle: Text(ref.tr('lyrics_separate_by_view_hint')),
            value: hasSeparate,
            onChanged: (value) => ref
                .read(libraryProvider.notifier)
                .setSeparateLyricsByView(media.id, value),
          ),
          if (hasSeparate) ...[
            const SizedBox(height: 12),
            SegmentedButton<PlayerViewMode>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: PlayerViewMode.media,
                  label: Text(ref.tr('lyrics_for_video')),
                  icon: const Icon(Icons.smart_display_outlined),
                ),
                ButtonSegment(
                  value: PlayerViewMode.image,
                  label: Text(ref.tr('lyrics_for_artwork')),
                  icon: const Icon(Icons.album_outlined),
                ),
              ],
              selected: {_viewMode},
              onSelectionChanged: (selection) => setState(() {
                _viewMode = selection.single;
                _editingOffsetFor = null;
              }),
            ),
            const SizedBox(height: 12),
            if (!hasOwnLyrics && media.lyricsPath != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(ref.tr('lyrics_uses_shared_fallback')),
              ),
          ],
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ref.tr('translated_lyrics'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    media.translatedLyricsPath == null
                        ? ref.tr('translated_lyrics_optional_hint')
                        : media.translatedLyricsPath!
                              .split(Platform.pathSeparator)
                              .last,
                    style: TextStyle(color: themeTextSub(context)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _chooseTranslationLyrics(media),
                        icon: const Icon(Icons.file_open_rounded),
                        label: Text(ref.tr('choose_translation_lyrics')),
                      ),
                      if (media.translatedLyricsPath != null) ...[
                        OutlinedButton.icon(
                          onPressed: () => _editTranslationLyrics(media),
                          icon: const Icon(Icons.edit_note_rounded),
                          label: Text(ref.tr('edit_translation_lyrics')),
                        ),
                        TextButton.icon(
                          onPressed: () => ref
                              .read(libraryProvider.notifier)
                              .updateTranslatedLyrics(media.id, null),
                          icon: const Icon(Icons.delete_outline_rounded),
                          label: Text(ref.tr('remove_translation_lyrics')),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasSeparate
                        ? ref.tr(
                            _artwork
                                ? 'lyrics_for_artwork'
                                : 'lyrics_for_video',
                          )
                        : ref.tr('lyrics_shared'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    path == null
                        ? ref.tr('lyrics_not_configured')
                        : path.split(Platform.pathSeparator).last,
                    style: TextStyle(color: themeTextSub(context)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (hasSeparate && otherViewLyricsPath != null) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () =>
                          _copyLyricsFromOtherView(media, otherViewLyricsPath),
                      icon: const Icon(Icons.copy_all_rounded),
                      label: Text(
                        ref.tr(
                          _artwork
                              ? 'copy_video_lyrics_to_artwork'
                              : 'copy_artwork_lyrics_to_video',
                        ),
                      ),
                    ),
                  ],
                  if (path?.toLowerCase().endsWith('.lrc') == true) ...[
                    const SizedBox(height: 18),
                    Text(
                      ref.tr('lyrics_global_shift'),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      ref.tr('lyrics_global_shift_hint'),
                      style: TextStyle(
                        color: themeTextSub(context),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _globalShiftController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                              signed: true,
                            ),
                            decoration: InputDecoration(
                              labelText: ref.tr('lyrics_editor_global_shift'),
                              suffixText: ref.tr('seconds_short'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () => _applyGlobalShift(media, path),
                          child: Text(ref.tr('lyrics_editor_apply_shift')),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _offsetController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: InputDecoration(
                            labelText: ref.tr('lyrics_timing'),
                            hintText: '0.00',
                          ),
                          onSubmitted: (_) => _saveOffset(media),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        tooltip: ref.tr('save'),
                        onPressed: () => _saveOffset(media),
                        icon: const Icon(Icons.check_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    ref.tr('lyrics_timing_hint'),
                    style: TextStyle(
                      color: themeTextSub(context),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () => _playForLyricsSync(media),
                        icon: const Icon(Icons.play_circle_outline_rounded),
                        label: Text(ref.tr('lyrics_sync_while_playing')),
                      ),
                      FilledButton.icon(
                        onPressed: () => _editLyrics(media, path),
                        icon: const Icon(Icons.edit_note_rounded),
                        label: Text(ref.tr('lyrics_editor_title')),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _chooseLyrics(media),
                        icon: const Icon(Icons.file_open_rounded),
                        label: Text(ref.tr('choose_lrc')),
                      ),
                      if (path != null)
                        TextButton.icon(
                          onPressed: () => ref
                              .read(libraryProvider.notifier)
                              .updateMediaLyricsForView(
                                media.id,
                                artwork: _artwork,
                                path: null,
                              ),
                          icon: const Icon(Icons.delete_outline_rounded),
                          label: Text(ref.tr('remove_lyrics')),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (hasSeparate) ...[
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.library_music_outlined),
              title: Text(ref.tr('lyrics_shared')),
              subtitle: Text(
                media.lyricsPath == null
                    ? ref.tr('lyrics_not_configured')
                    : media.lyricsPath!.split(Platform.pathSeparator).last,
              ),
              trailing: Text(ref.tr('lyrics_fallback')),
              onTap: () => setState(() {
                ref
                    .read(libraryProvider.notifier)
                    .setSeparateLyricsByView(media.id, false);
                _viewMode = PlayerViewMode.media;
                _editingOffsetFor = null;
              }),
            ),
          ],
        ],
      ),
    );
  }
}

class _MediaKindChip extends ConsumerWidget {
  const _MediaKindChip({required this.isVideo});

  final bool isVideo;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Chip(
    visualDensity: VisualDensity.compact,
    avatar: Icon(
      isVideo ? Icons.movie_outlined : Icons.graphic_eq_rounded,
      size: 16,
    ),
    label: Text(ref.tr(isVideo ? 'media_kind_mv' : 'media_kind_audio')),
  );
}

int? _parseOffset(String input) {
  final value = input.trim();
  if (value.contains(':')) {
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final minutes = int.tryParse(parts[0]);
    final seconds = double.tryParse(parts[1]);
    if (minutes == null || seconds == null || seconds < 0 || seconds >= 60) {
      return null;
    }
    return ((minutes * 60 + seconds) * 1000).round();
  }
  final seconds = double.tryParse(value);
  if (seconds == null || !seconds.isFinite) return null;
  return (seconds * 1000).round();
}
