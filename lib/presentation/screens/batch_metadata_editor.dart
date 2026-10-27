import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app_state.dart';
import '../../domain/models.dart';
import '../../library/media_metadata_patch.dart';
import '../i18n.dart';

Future<bool> showBatchMetadataEditor(
  BuildContext context,
  WidgetRef ref,
  List<String> ids,
) async {
  final available = {
    for (final m in ref.read(libraryProvider).savedMedia) m.id: m,
  };
  final selected = ids.toSet().where(available.containsKey).toList();
  final media = [for (final id in selected) available[id]!];
  if (media.isEmpty) return false;
  final code = ref.read(activeLanguageCodeProvider);
  return await showDialog<bool>(
        context: context,
        builder: (_) => _BatchMetadataDialog(
          media: media,
          languageCode: code,
          save: (patch) => ref
              .read(libraryProvider.notifier)
              .updateMediaMetadataBatch(selected, patch),
        ),
      ) ??
      false;
}

class _BatchMetadataDialog extends StatefulWidget {
  const _BatchMetadataDialog({
    required this.media,
    required this.languageCode,
    required this.save,
  });
  final List<MediaItem> media;
  final String languageCode;
  final Future<void> Function(MediaMetadataPatch) save;
  @override
  State<_BatchMetadataDialog> createState() => _BatchMetadataDialogState();
}

class _BatchMetadataDialogState extends State<_BatchMetadataDialog> {
  late final List<TextEditingController> _controllers;
  late final List<bool> _mixed;
  final _enabled = [false, false, false, false];
  final _startController = TextEditingController(text: '1');
  bool _numberTracks = false;
  bool _saving = false;
  String? _error;
  String tr(String key) => translate(key, widget.languageCode);

  @override
  void initState() {
    super.initState();
    final readers = <String? Function(MediaItem)>[
      (m) => m.album,
      (m) => m.albumArtist,
      (m) => m.artist,
      (m) => m.discNumber?.toString(),
    ];
    _mixed = [
      for (final read in readers) widget.media.map(read).toSet().length > 1,
    ];
    _controllers = [
      for (final read in <String? Function(MediaItem)>[
        (m) => m.album,
        (m) => m.albumArtist,
        (m) => m.artist,
        (m) => m.discNumber?.toString(),
      ])
        TextEditingController(
          text: widget.media.map(read).toSet().length == 1
              ? read(widget.media.first) ?? ''
              : '',
        ),
    ];
  }

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    _startController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final discText = _controllers[3].text.trim();
    final disc = int.tryParse(discText);
    final start = int.tryParse(_startController.text.trim());
    if (_enabled[3] && discText.isNotEmpty && (disc == null || disc < 1)) {
      setState(() => _error = tr('invalid_disc_number'));
      return;
    }
    if (_numberTracks && (start == null || start < 1)) {
      setState(() => _error = tr('invalid_track_number'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    MetadataChange<String?>? change(int index) {
      if (!_enabled[index]) return null;
      final text = _controllers[index].text.trim();
      return MetadataChange(text.isEmpty ? null : text);
    }

    try {
      await widget.save(
        MediaMetadataPatch(
          album: change(0),
          albumArtist: change(1),
          artist: change(2),
          discNumber: _enabled[3] ? MetadataChange(disc) : null,
          trackNumberStart: _numberTracks ? start : null,
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = tr('batch_save_failed');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: Text(tr('batch_metadata')),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(
                    'batch_count',
                  ).replaceAll('{count}', '${widget.media.length}'),
                ),
                const SizedBox(height: 8),
                Text(tr('batch_hint')),
                const SizedBox(height: 12),
                for (final entry in [
                  (0, 'album'),
                  (1, 'album_artist'),
                  (2, 'metadata_artist'),
                  (3, 'disc_number'),
                ]) ...[
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _enabled[entry.$1],
                    title: Text(
                      tr(entry.$2),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      tr(
                        _enabled[entry.$1]
                            ? 'batch_apply_all'
                            : _mixed[entry.$1]
                            ? 'batch_mixed_values'
                            : 'batch_unchanged',
                      ),
                    ),
                    onChanged: _saving
                        ? null
                        : (value) => setState(
                            () => _enabled[entry.$1] = value ?? false,
                          ),
                  ),
                  if (_enabled[entry.$1])
                    TextField(
                      key: ValueKey('batch-field-${entry.$1}'),
                      controller: _controllers[entry.$1],
                      enabled: !_saving,
                      keyboardType: entry.$1 == 3
                          ? TextInputType.number
                          : TextInputType.text,
                      decoration: InputDecoration(
                        labelText: tr(entry.$2),
                        hintText: tr('batch_clear_hint'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(tr('number_tracks')),
                  value: _numberTracks,
                  onChanged: _saving
                      ? null
                      : (value) =>
                            setState(() => _numberTracks = value ?? false),
                ),
                if (_numberTracks) ...[
                  TextField(
                    key: const ValueKey('batch-track-start'),
                    controller: _startController,
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: tr('track_start'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(tr('number_tracks_hint')),
                  const SizedBox(height: 8),
                  for (var i = 0; i < widget.media.length && i < 5; i++)
                    Text(
                      '${i + (int.tryParse(_startController.text) ?? 1)}. ${widget.media[i].title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            child: Text(tr('cancel')),
          ),
          FilledButton(
            onPressed:
                _saving || (!_enabled.any((value) => value) && !_numberTracks)
                ? null
                : _save,
            child: Text(tr(_saving ? 'loading' : 'save')),
          ),
        ],
      ),
    );
  }
}
