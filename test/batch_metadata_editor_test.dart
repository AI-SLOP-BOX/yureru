import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yureru/app_state.dart';
import 'package:yureru/data/store.dart';
import 'package:yureru/domain/models.dart';
import 'package:yureru/presentation/i18n.dart';
import 'package:yureru/presentation/screens/batch_metadata_editor.dart';

class _Repository extends InMemoryLibraryRepository {
  bool reject = false;
  @override
  Future<void> saveMedia(List<MediaItem> items) async {
    if (reject) throw StateError('full');
    await super.saveMedia(items);
  }
}

void main() {
  testWidgets(
    'failed save keeps dialog and edits, retry can explicitly clear one field',
    (tester) async {
      final repo = _Repository();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            repositoryProvider.overrideWithValue(repo),
            activeLanguageCodeProvider.overrideWithValue('ja'),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () =>
                      showBatchMetadataEditor(context, ref, ['a', 'b']),
                  child: const Text('Edit'),
                ),
              ),
            ),
          ),
        ),
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(Scaffold)),
      );
      await container.read(libraryProvider.notifier).addMedia([
        MediaItem(
          id: 'a',
          title: 'A',
          album: 'Album',
          albumArtist: 'Main',
          artist: 'Solo',
          localPath: '/a',
        ),
        MediaItem(
          id: 'b',
          title: 'B',
          album: 'Album',
          albumArtist: 'Main',
          artist: 'Guest',
          localPath: '/b',
        ),
      ]);
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile).at(1));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('batch-field-1')), '');
      repo.reject = true;
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('保存できませんでした。もう一度お試しください。'), findsOneWidget);
      expect(container.read(libraryProvider).byId('a')!.albumArtist, 'Main');
      repo.reject = false;
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(container.read(libraryProvider).byId('a')!.albumArtist, isNull);
      expect(container.read(libraryProvider).byId('b')!.albumArtist, isNull);
      expect(container.read(libraryProvider).byId('a')!.artist, 'Solo');
      expect(container.read(libraryProvider).byId('b')!.artist, 'Guest');
      expect(container.read(libraryProvider).byId('a')!.album, 'Album');
      expect(tester.takeException(), isNull);
    },
  );
}
