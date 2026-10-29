import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../app_state.dart';
import '../../domain/models.dart';
import '../../playback/playback_controller.dart';
import '../i18n.dart';
import '../theme.dart';
import '../widgets/lyrics_editor_dialog.dart';
import '../widgets/metadata_fields.dart';

Future<void> showMediaMetadataEditor(
  BuildContext context,
  WidgetRef ref,
  MediaItem media,
) async {
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
  String? selectedArtworkPath;
  var clearArtwork = false;
  String? selectedThumbnailPath;
  var clearThumbnail = false;
  var editLyricsAfterClose = false;
  var deleteMediaAfterClose = false;
  DialogRoute<bool>? dialogRoute;
  try {
    dialogRoute = DialogRoute<bool>(
      context: context,
      builder: (dialogContext) {
        final isDark = Theme.of(dialogContext).brightness == Brightness.dark;
        final textColor = themeTextPrimary(dialogContext);
        final subtle = themeTextSub(dialogContext);
        final border = themeBorder(dialogContext);
        return Dialog(
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
                    color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.12),
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
                      autofocus: true,
                      textColor: textColor,
                      labelColor: subtle,
                      borderColor: border,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 16),
                    CreatorNamesField(
                      initialValue: media.artist,
                      textColor: textColor,
                      labelColor: subtle,
                      borderColor: border,
                      isDark: isDark,
                      strings: tr,
                      onChanged: (names) =>
                          artistController.text = names.join('・'),
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
                    MetadataField(
                      label: tr('lyrics_timing'),
                      controller: lyricsOffsetController,
                      textColor: textColor,
                      labelColor: subtle,
                      borderColor: border,
                      isDark: isDark,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      tr('lyrics_timing_hint'),
                      style: TextStyle(color: subtle, fontSize: 11),
                    ),
                    if (media.lyricsPath != null) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            editLyricsAfterClose = true;
                            Navigator.pop(dialogContext, false);
                          },
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
                          required IconData icon,
                          required ValueChanged<String> onChoose,
                          required VoidCallback onClear,
                        }) {
                          final previewPath = cleared
                              ? null
                              : (selectedPath ?? existingPath);
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
                                              color: const Color(0x22000000),
                                              child: Icon(icon),
                                            )
                                          : Image.file(
                                              File(previewPath),
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, _, _) =>
                                                  const Icon(
                                                    Icons.broken_image_outlined,
                                                  ),
                                            ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  OutlinedButton.icon(
                                    icon: Icon(icon),
                                    label: Text(tr('choose_artwork')),
                                    onPressed: () async {
                                      final result = await FilePicker.platform
                                          .pickFiles(
                                            type: FileType.image,
                                            allowMultiple: false,
                                            withData: false,
                                          );
                                      final path = result?.files.single.path;
                                      if (path != null) {
                                        setDialogState(() => onChoose(path));
                                      }
                                    },
                                  ),
                                  if (previewPath != null)
                                    IconButton(
                                      tooltip: tr('clear_artwork'),
                                      icon: const Icon(
                                        Icons.delete_outline_rounded,
                                      ),
                                      onPressed: () => setDialogState(onClear),
                                    ),
                                ],
                              ),
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
                              icon: Icons.album_outlined,
                              onChoose: (path) {
                                selectedArtworkPath = path;
                                clearArtwork = false;
                              },
                              onClear: () {
                                selectedArtworkPath = null;
                                clearArtwork = true;
                              },
                            ),
                            const SizedBox(height: 16),
                            imageSelector(
                              label: tr('thumbnail_label'),
                              existingPath: media.thumbnailPath,
                              selectedPath: selectedThumbnailPath,
                              cleared: clearThumbnail,
                              icon: Icons.image_outlined,
                              onChoose: (path) {
                                selectedThumbnailPath = path;
                                clearThumbnail = false;
                              },
                              onClear: () {
                                selectedThumbnailPath = null;
                                clearThumbnail = true;
                              },
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    Text(
                      tr('image_priority_hint'),
                      style: TextStyle(color: subtle, fontSize: 11),
                    ),
                    const SizedBox(height: 24),
                    Row(
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
                                    onPressed: () =>
                                        Navigator.pop(confirmContext, false),
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
                                Navigator.pop(dialogContext, false);
                              }
                            }
                          },
                        ),
                        const Spacer(),
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: subtle,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: Text(tr('cancel')),
                        ),
                        const SizedBox(width: 8),
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
                          onPressed: () {
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
                            if (_parseLyricsOffset(
                                  lyricsOffsetController.text,
                                ) ==
                                null) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(tr('invalid_lyrics_timing')),
                                ),
                              );
                              return;
                            }
                            Navigator.pop(dialogContext, true);
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
    final offsetMs = _parseLyricsOffset(lyricsOffsetController.text);
    if (offsetMs == null) {
      messenger.showSnackBar(
        SnackBar(content: Text(tr('invalid_lyrics_timing'))),
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
    await ref
        .read(libraryProvider.notifier)
        .updateMediaAlbum(
          media.id,
          album: nullableText(albumController),
          albumArtist: nullableText(albumArtistController),
          trackNumber: number,
          discNumber: int.tryParse(discController.text.trim()),
        );
    final artist = artistController.text.trim();
    await ref
        .read(libraryProvider.notifier)
        .updateMediaMetadata(
          media.id,
          title: titleController.text.trim(),
          artist: artist.isEmpty ? null : artist,
        );

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
    await ref
        .read(libraryProvider.notifier)
        .updateMediaArtwork(media.id, artworkPath);
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
    await ref
        .read(libraryProvider.notifier)
        .updateMediaThumbnail(media.id, thumbnailPath);
    await ref
        .read(libraryProvider.notifier)
        .updateMediaLyricsOffset(media.id, offsetMs);
  } finally {
    // The route remains mounted while its closing animation runs.
    if (dialogRoute != null) await dialogRoute.completed;
    titleController.dispose();
    artistController.dispose();
    albumController.dispose();
    albumArtistController.dispose();
    trackController.dispose();
    discController.dispose();
    lyricsOffsetController.dispose();
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
