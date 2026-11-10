import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/trash_store.dart';
import '../../domain/models.dart';
import '../../app_state.dart';
import '../i18n.dart';

class TrashScreen extends ConsumerStatefulWidget {
  const TrashScreen({super.key});

  @override
  ConsumerState<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends ConsumerState<TrashScreen> {
  late Future<List<TrashEntry>> _entries;

  @override
  void initState() {
    super.initState();
    _entries = TrashStore().load();
  }

  void _reload() => setState(() => _entries = TrashStore().load());

  Future<void> _restore(TrashEntry entry) async {
    await ref.read(libraryProvider.notifier).restoreTrashEntry(entry);
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(ref.tr('recently_deleted'))),
    body: FutureBuilder<List<TrashEntry>>(
      future: _entries,
      builder: (context, snapshot) {
        final entries = (snapshot.data ?? const <TrashEntry>[])
            .where(
              (entry) =>
                  DateTime.now().difference(entry.deletedAt) <
                  TrashStore.retention,
            )
            .toList();
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (entries.isEmpty) {
          return Center(child: Text(ref.tr('trash_empty')));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final entry = entries[index];
            final title = entry.type == 'media'
                ? MediaItem.fromJson(entry.data).title
                : Playlist.fromJson(entry.data).name;
            final remaining =
                TrashStore.retention.inDays -
                DateTime.now().difference(entry.deletedAt).inDays;
            return Card(
              child: ListTile(
                leading: Icon(
                  entry.type == 'media'
                      ? Icons.movie_outlined
                      : Icons.queue_music_rounded,
                ),
                title: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  ref
                      .tr('trash_days_remaining')
                      .replaceAll(
                        '{count}',
                        '${remaining.clamp(0, TrashStore.retention.inDays)}',
                      ),
                ),
                trailing: FilledButton.tonal(
                  onPressed: () => _restore(entry),
                  child: Text(ref.tr('restore')),
                ),
              ),
            );
          },
        );
      },
    ),
  );
}
