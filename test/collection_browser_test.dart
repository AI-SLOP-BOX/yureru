import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yureru/app_state.dart';
import 'package:yureru/data/store.dart';
import 'package:yureru/domain/models.dart';
import 'package:yureru/playback/fake_engine.dart';
import 'package:yureru/presentation/i18n.dart';
import 'package:yureru/presentation/screens/home_screen.dart';
import 'package:yureru/presentation/screens/media_metadata_editor.dart';
import 'package:yureru/presentation/widgets/metadata_fields.dart';
import 'package:yureru/presentation/theme.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  final items = [
    MediaItem(
      id: '2',
      title: 'Second',
      artist: 'Main / Guest',
      album: 'Album',
      albumArtist: 'Main',
      trackNumber: 2,
      localPath: '/missing/2.mp3',
    ),
    MediaItem(
      id: '1',
      title: 'First',
      artist: 'Main',
      album: 'Album',
      albumArtist: 'Main',
      trackNumber: 1,
      localPath: '/missing/1.mp3',
    ),
    MediaItem(
      id: '3',
      title: 'Other',
      artist: 'Other',
      album: 'Other album',
      localPath: '/missing/3.mp3',
    ),
  ];
  Future<ProviderContainer> pump(
    WidgetTester tester,
    Size size, {
    bool editor = false,
    bool dark = true,
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          engineProvider.overrideWithValue(FakePlaybackEngine()),
          repositoryProvider.overrideWithValue(InMemoryLibraryRepository()),
          activeLanguageCodeProvider.overrideWithValue('ja'),
        ],
        child: MaterialApp(
          theme: yureruTheme(isDark: dark),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            body: editor
                ? Consumer(
                    builder: (context, ref, _) => TextButton(
                      onPressed: () => showMediaMetadataEditor(
                        context,
                        ref,
                        ref.read(libraryProvider).byId('1')!,
                      ),
                      child: const Text('Edit'),
                    ),
                  )
                : const HomeScreen(),
          ),
        ),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold)),
    );
    await container.read(libraryProvider.notifier).addMedia(items);
    await tester.pumpAndSettle();
    return container;
  }

  for (final size in [const Size(360, 600), const Size(1240, 559)]) {
    testWidgets('album browser queues the full album in track order at $size', (
      tester,
    ) async {
      final container = await pump(tester, size);
      await tester.tap(find.text('アルバム'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Album'));
      await tester.pumpAndSettle();
      expect(find.text('1. First'), findsOneWidget);
      container.read(searchQueryProvider.notifier).state = 'Second';
      await tester.pumpAndSettle();
      expect(find.text('1. First'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('collection-track-2')));
      await tester.pumpAndSettle();
      expect(container.read(queueProvider).queue, ['1', '2']);
      expect(container.read(queueProvider).currentId, '2');
      expect(container.read(viewingPlayerProvider), true);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'artist drilldown includes guest tracks and responds to metadata edits',
    (tester) async {
      final container = await pump(tester, const Size(390, 844));
      await tester.tap(find.text('アーティスト'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Guest'));
      await tester.pumpAndSettle();
      expect(find.text('Second'), findsOneWidget);
      expect(find.text('First'), findsNothing);
      await container
          .read(libraryProvider.notifier)
          .updateMediaMetadata('2', title: 'Changed', artist: 'Main');
      await tester.pumpAndSettle();
      expect(find.text('Guest'), findsNothing);
      expect(find.text('Main'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('metadata editor scrolls on phone and persists album fields', (
    tester,
  ) async {
    final container = await pump(tester, const Size(360, 600), editor: true);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    Future<void> enter(String label, String text) async {
      final field = find.byWidgetPredicate(
        (widget) => widget is MetadataField && widget.label == label,
      );
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(of: field, matching: find.byType(TextField)),
        text,
      );
    }

    await enter('アルバム名', 'Edited Album');
    await enter('アルバムアーティスト', 'Various Artists');
    await enter('ディスク番号', '3');
    await enter('曲番号', '12');
    await tester.ensureVisible(find.text('保存'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    final media = container.read(libraryProvider).byId('1')!;
    expect(media.album, 'Edited Album');
    expect(media.albumArtist, 'Various Artists');
    expect(media.trackNumber, 12);
    expect(media.discNumber, 3);
    expect(media.title, 'First');
    expect(tester.takeException(), isNull);
    await container.read(libraryProvider.notifier).load();
    expect(container.read(libraryProvider).byId('1')!.album, 'Edited Album');
  });
  testWidgets(
    'phone selection edits visible chosen tracks without starting playback',
    (tester) async {
      final container = await pump(tester, const Size(360, 600));
      await tester.tap(find.text('アルバム'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Album'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('曲を選択'));
      await tester.pumpAndSettle();
      container.read(searchQueryProvider.notifier).state = 'Second';
      await tester.pumpAndSettle();
      await tester.tap(find.text('表示中を全選択'));
      await tester.pumpAndSettle();
      expect(find.text('1曲を選択'), findsOneWidget);
      await tester.tap(find.text('情報をまとめて編集'));
      await tester.pumpAndSettle();
      final dialog = find.byType(AlertDialog);
      expect(dialog, findsOneWidget);
      final field = find
          .descendant(of: dialog, matching: find.byType(CheckboxListTile))
          .first;
      await tester.tap(field);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('batch-field-0')),
        'New Album',
      );
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      expect(container.read(libraryProvider).byId('2')!.album, 'New Album');
      expect(container.read(libraryProvider).byId('2')!.artist, 'Main / Guest');
      expect(container.read(libraryProvider).byId('1')!.album, 'Album');
      expect(container.read(queueProvider).queue, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'batch numbering previews display order and rejects zero on phone',
    (tester) async {
      final container = await pump(tester, const Size(360, 600));
      await tester.tap(find.text('アルバム'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Album'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('曲を選択'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('表示中を全選択'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('情報をまとめて編集'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('曲番号を連番で設定'));
      await tester.tap(find.text('曲番号を連番で設定'));
      await tester.pumpAndSettle();
      final start = find.byKey(const ValueKey('batch-track-start'));
      await tester.ensureVisible(start);
      await tester.enterText(start, '0');
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(container.read(libraryProvider).byId('1')!.trackNumber, 1);
      await tester.ensureVisible(start);
      await tester.enterText(start, '7');
      await tester.pumpAndSettle();
      expect(find.text('7. First'), findsOneWidget);
      expect(find.text('8. Second'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.pumpAndSettle();
      expect(container.read(libraryProvider).byId('1')!.trackNumber, 7);
      expect(container.read(libraryProvider).byId('2')!.trackNumber, 8);
      expect(container.read(libraryProvider).byId('3')!.trackNumber, isNull);
      expect(container.read(queueProvider).queue, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('multi-disc album shows disc labels and queues discs in order', (
    tester,
  ) async {
    final container = await pump(tester, const Size(390, 844));
    await container
        .read(libraryProvider.notifier)
        .updateMediaAlbum(
          '1',
          album: 'Album',
          albumArtist: 'Main',
          trackNumber: 1,
          discNumber: 2,
        );
    await container
        .read(libraryProvider.notifier)
        .updateMediaAlbum(
          '2',
          album: 'Album',
          albumArtist: 'Main',
          trackNumber: 1,
          discNumber: 1,
        );
    await tester.tap(find.text('アルバム'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Album'));
    await tester.pumpAndSettle();
    expect(find.text('ディスク1 · Main / Guest'), findsOneWidget);
    expect(find.text('ディスク2 · Main'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '再生'));
    await tester.pumpAndSettle();
    expect(container.read(queueProvider).queue, ['2', '1']);
    expect(container.read(queueProvider).currentId, '2');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'selection controls stay visible after scrolling and explain hidden selections',
    (tester) async {
      final container = await pump(tester, const Size(360, 600));
      await container
          .read(libraryProvider.notifier)
          .addMedia(
            List.generate(
              40,
              (i) => MediaItem(
                id: 'extra-$i',
                title: 'Extra $i',
                artist: 'Main',
                album: 'Album',
                albumArtist: 'Main',
                localPath: '/extra-$i',
              ),
            ),
          );
      await tester.tap(find.text('アルバム'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Album'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('曲を選択'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('表示中を全選択'));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -1200));
      await tester.pumpAndSettle();
      expect(
        find.widgetWithText(FilledButton, '情報をまとめて編集').hitTestable(),
        findsOneWidget,
      );
      expect(find.text('選択を終了').hitTestable(), findsOneWidget);
      container.read(searchQueryProvider.notifier).state = 'First';
      await tester.pumpAndSettle();
      expect(find.text('検索で非表示の41曲も選択中です'), findsOneWidget);
      await tester.tap(find.text('表示中を選択解除'));
      await tester.pumpAndSettle();
      expect(find.text('41曲を選択'), findsOneWidget);
      await tester.tap(find.text('選択を終了'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, '情報をまとめて編集'), findsNothing);
      expect(container.read(queueProvider).queue, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'empty search offers clear search and row menu preserves playback',
    (tester) async {
      final container = await pump(tester, const Size(390, 844));
      await tester.tap(find.text('アルバム'));
      await tester.pumpAndSettle();
      container.read(searchQueryProvider.notifier).state = 'missing-match';
      await tester.pumpAndSettle();
      expect(find.text('見つかりませんでした'), findsOneWidget);
      await tester.tap(find.text('検索をクリア'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Album'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('曲の操作').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(translate('add_favorite', 'ja')));
      await tester.pumpAndSettle();
      expect(container.read(libraryProvider).byId('1')!.isFavorite, true);
      expect(container.read(queueProvider).queue, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'light theme with larger text keeps browsing and selection usable on phone',
    (tester) async {
      await pump(tester, const Size(360, 600), dark: false, textScale: 1.4);
      expect(find.text('アーティスト').hitTestable(), findsOneWidget);
      await tester.tap(find.text('アルバム'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Album'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('曲を選択'));
      await tester.tap(find.text('曲を選択'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('表示中を全選択'));
      await tester.pumpAndSettle();
      expect(find.text('情報をまとめて編集').hitTestable(), findsOneWidget);
      await tester.tap(find.text('選択を終了'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
