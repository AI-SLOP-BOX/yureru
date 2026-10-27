import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../app_state.dart';
import '../../domain/models.dart';
import '../i18n.dart';
import '../theme.dart';
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
                    const SizedBox(height: 18),
                    Text(
                      tr('artwork'),
                      style: TextStyle(
                        color: subtle,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    StatefulBuilder(
                      builder: (context, setDialogState) {
                        final previewPath = clearArtwork
                            ? null
                            : (selectedArtworkPath ?? media.artworkPath);
                        return Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: SizedBox(
                                width: 56,
                                height: 56,
                                child: previewPath == null
                                    ? const ColoredBox(
                                        color: Color(0x22000000),
                                        child: Icon(Icons.music_note_rounded),
                                      )
                                    : Image.file(
                                        File(previewPath),
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) => const Icon(
                                          Icons.broken_image_outlined,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.image_outlined),
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
                                  setDialogState(() {
                                    selectedArtworkPath = path;
                                    clearArtwork = false;
                                  });
                                }
                              },
                            ),
                            if (previewPath != null)
                              IconButton(
                                tooltip: tr('clear_artwork'),
                                icon: const Icon(Icons.delete_outline_rounded),
                                onPressed: () => setDialogState(() {
                                  selectedArtworkPath = null;
                                  clearArtwork = true;
                                }),
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
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
