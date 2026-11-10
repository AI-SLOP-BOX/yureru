import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_state.dart';
import '../../domain/models.dart';
import '../i18n.dart';

/// Candidate groups use matching title, artist and (when both are known)
/// duration. They are suggestions only; every removal is explicit.
List<List<MediaItem>> findPossibleDuplicates(Iterable<MediaItem> source) {
  final groups = <String, List<MediaItem>>{};
  for (final item in source.where((item) => !item.isTemporary)) {
    final title = item.title.trim().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    if (title.isEmpty) continue;
    final artist = (item.artist ?? '').trim().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    groups.putIfAbsent('$title\u0000$artist', () => []).add(item);
  }
  final result = <List<MediaItem>>[];
  for (final candidates in groups.values.where((group) => group.length > 1)) {
    final remaining = [...candidates];
    while (remaining.isNotEmpty) {
      final first = remaining.removeAt(0);
      final group = <MediaItem>[first];
      for (final candidate in [...remaining]) {
        final a = first.durationMs;
        final b = candidate.durationMs;
        if (a == null || b == null || (a - b).abs() <= 3000) {
          group.add(candidate);
          remaining.remove(candidate);
        }
      }
      if (group.length > 1) result.add(group);
    }
  }
  return result;
}

class DuplicateMediaScreen extends ConsumerWidget {
  const DuplicateMediaScreen({super.key});

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    MediaItem item,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(ref.tr('remove_duplicate')),
        content: Text(
          ref.tr('remove_duplicate_confirm').replaceAll('{title}', item.title),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(ref.tr('cancel')),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(ref.tr('remove_from_library')),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await ref.read(libraryProvider.notifier).removeMedia(item.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = findPossibleDuplicates(
      ref.watch(libraryProvider).savedMedia,
    );
    return Scaffold(
      appBar: AppBar(title: Text(ref.tr('possible_duplicates'))),
      body: groups.isEmpty
          ? Center(child: Text(ref.tr('no_possible_duplicates')))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: groups.length,
              itemBuilder: (context, index) {
                final group = groups[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.copy_all_rounded),
                        title: Text(group.first.title),
                        subtitle: Text(
                          '${group.first.artist?.trim().isNotEmpty == true ? group.first.artist : ref.tr('unknown_artist')} · ${ref.tracksCount(group.length)}',
                        ),
                      ),
                      for (final item in group)
                        ListTile(
                          dense: true,
                          title: Text(
                            item.localPath.split(RegExp(r'[/\\]')).last,
                          ),
                          subtitle: Text(
                            item.localPath,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: IconButton(
                            tooltip: ref.tr('remove_duplicate'),
                            onPressed: () => _remove(context, ref, item),
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
