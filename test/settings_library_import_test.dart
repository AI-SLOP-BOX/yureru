import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yureru/app_state.dart';
import 'package:yureru/data/importer.dart';
import 'package:yureru/data/store.dart';
import 'package:yureru/domain/models.dart';
import 'package:yureru/presentation/screens/settings_library_screen.dart';

class _FakeImporter extends VideoImporter {
  _FakeImporter({this.fileResult, this.folderResult});
  final Future<List<MediaItem>> Function()? fileResult;
  final Future<List<MediaItem>?> Function()? folderResult;
  int calls = 0;
  int folderCalls = 0;
  Set<String> lastSkip = const {};
  @override
  Future<List<MediaItem>> pickAndImport({
    bool copyIntoApp = true,
    Set<String> skipSourcePaths = const {},
    void Function(int done, int total)? onProgress,
  }) {
    calls++;
    lastSkip = skipSourcePaths;
    return fileResult!();
  }
  @override
  Future<List<MediaItem>?> pickAndImportFolder({
    bool copyIntoApp = true,
    Set<String> skipSourcePaths = const {},
    void Function(int done, int total)? onProgress,
  }) {
    folderCalls++;
    lastSkip = skipSourcePaths;
    return folderResult!();
  }
}

Future<void> _pump(WidgetTester tester, VideoImporter importer) async {
  await tester.pumpWidget(ProviderScope(overrides: [
    importerProvider.overrideWithValue(importer),
    repositoryProvider.overrideWithValue(InMemoryLibraryRepository()),
  ], child: const MaterialApp(home: LibraryManagementScreen())));
}

void main() {
  testWidgets('「動画をインポート」タップでピッカーが呼ばれ、メディアが追加される', (tester) async {
    final fake = _FakeImporter(fileResult: () async =>
        [MediaItem(title: 'demo', localPath: '/tmp/demo.mp4')]);
    await _pump(tester, fake);

    await tester.tap(find.text('動画をインポート'));
    await tester.pumpAndSettle();

    expect(fake.calls, 1);
    expect(find.text('1本をインポートしました'), findsOneWidget);
    expect(find.text('1件'), findsOneWidget); // 一覧の件数も更新される
    expect(tester.takeException(), isNull);
  });

  testWidgets('ピッカーがキャンセルを返してもエラーにならない', (tester) async {
    final fake = _FakeImporter(fileResult: () async => const []);
    await _pump(tester, fake);

    await tester.tap(find.text('動画をインポート'));
    await tester.pumpAndSettle();

    expect(fake.calls, 1);
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ピッカーが失敗した場合はエラーをスナックバーで示す', (tester) async {
    final fake = _FakeImporter(fileResult: () async => throw Exception('boom'));
    await _pump(tester, fake);

    await tester.tap(find.text('動画をインポート'));
    await tester.pumpAndSettle();

    expect(fake.calls, 1);
    expect(find.textContaining('インポートに失敗しました'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('「フォルダからインポート」タップでまとめて取り込まれる', (tester) async {
    final fake = _FakeImporter(folderResult: () async => [
      MediaItem(title: 'a', localPath: '/tmp/a.mp4', sourcePath: '/in/a.mp4'),
      MediaItem(title: 'b', localPath: '/tmp/b.mp4', sourcePath: '/in/b.mp4'),
    ]);
    await _pump(tester, fake);

    await tester.tap(find.text('フォルダからインポート'));
    await tester.pumpAndSettle();

    expect(fake.folderCalls, 1);
    expect(find.text('2本をインポートしました'), findsOneWidget);
    expect(find.text('2件'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('フォルダ選択キャンセル(null)は何もしない', (tester) async {
    final fake = _FakeImporter(folderResult: () async => null);
    await _pump(tester, fake);

    await tester.tap(find.text('フォルダからインポート'));
    await tester.pumpAndSettle();

    expect(fake.folderCalls, 1);
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('「フォルダを参照追加」タップでコピーなし(origin=referenced)で取り込まれる', (tester) async {
    final fake = _FakeImporter(folderResult: () async => [
      MediaItem(title: 'ref1', localPath: '/ext/ref1.mp4', origin: 'referenced', sourcePath: '/ext/ref1.mp4'),
    ]);
    await _pump(tester, fake);

    await tester.tap(find.text('フォルダを参照追加'));
    await tester.pumpAndSettle();

    expect(fake.folderCalls, 1);
    expect(find.text('1本を参照追加しました（コピーなし）'), findsOneWidget);
    expect(find.text('1件'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
