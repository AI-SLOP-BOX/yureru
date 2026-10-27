import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yureru/app_state.dart';
import 'package:yureru/data/importer.dart';
import 'package:yureru/data/store.dart';
import 'package:yureru/domain/models.dart';

void main() {
  group('isVideoPath', () {
    test('動画拡張子を大文字小文字無視で判定する', () {
      expect(isVideoPath('/x/y.mp4'), isTrue);
      expect(isVideoPath('/x/y.MP4'), isTrue);
      expect(isVideoPath('/x/y.MOV'), isTrue);
      expect(isVideoPath('/x/y.mkv'), isTrue);
      expect(isVideoPath('/x/y.txt'), isFalse);
      expect(isVideoPath('/x/noext'), isFalse);
      expect(isVideoPath('/x/.mp4'), isFalse); // dotfile は除外
    });
  });

  group('isSupportedMediaPath', () {
    test('音声と動画を受け付け、その他は除外する', () {
      expect(isSupportedMediaPath('/music/song.mp3'), isTrue);
      expect(isSupportedMediaPath('/music/song.OPUS'), isTrue);
      expect(isSupportedMediaPath('/music/song.webm'), isTrue);
      expect(isSupportedMediaPath('/music/readme.txt'), isFalse);
    });
  });

  group('collectVideoPaths', () {
    test('再帰走査して動画だけ・隠しファイル除外で収集する', () async {
      final root = await Directory.systemTemp.createTemp('yureru_walk');
      addTearDown(() => root.delete(recursive: true));
      await File('${root.path}/a.mp4').create();
      await Directory('${root.path}/sub').create();
      await File('${root.path}/sub/b.MOV').create();
      await File('${root.path}/sub/c.txt').create();
      await Directory('${root.path}/.hidden').create();
      await File('${root.path}/.hidden/d.mp4').create();

      final got = await collectVideoPaths(root);
      final expected = ['${root.path}/a.mp4', '${root.path}/sub/b.MOV']..sort();
      expect(got, expected);
    });
  });

  test('collectMediaPaths は音声と動画を収集する', () async {
    final root = await Directory.systemTemp.createTemp('yureru_media_');
    try {
      await File('${root.path}/song.mp3').writeAsString('audio');
      await File('${root.path}/song.opus').writeAsString('audio');
      await File('${root.path}/note.txt').writeAsString('ignore');
      expect(await collectMediaPaths(root), hasLength(2));
    } finally {
      await root.delete(recursive: true);
    }
  });

  group('VideoImporter (メソッドチャネルをモック)', () {
    late TestWidgetsFlutterBinding binding;
    late TestDefaultBinaryMessenger messenger;

    setUp(() {
      binding = TestWidgetsFlutterBinding.ensureInitialized();
      messenger = binding.defaultBinaryMessenger;
    });

    test('pickAndImport: skipSourcePaths のファイルは取り込まない', () async {
      messenger.setMockMethodCallHandler(mediaPickerChannel, (call) async {
        expect(call.method, 'pickVideos');
        return ['/in/a.mp4', '/in/b.mp4'];
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(mediaPickerChannel, null),
      );

      final items = await VideoImporter().pickAndImport(
        copyIntoApp: false,
        skipSourcePaths: {'/in/a.mp4'},
      );
      expect(items.map((e) => e.sourcePath).toList(), ['/in/b.mp4']);
      expect(items.single.title, 'b');
      expect(items.single.origin, 'referenced');
    });

    test('「アーティスト - タイトル.mp4」は分割される', () async {
      messenger.setMockMethodCallHandler(mediaPickerChannel, (call) async {
        expect(call.method, 'pickVideos');
        return ['/in/夜の海 - 蒼.mp4', '/in/ただの名前.mp4'];
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(mediaPickerChannel, null),
      );

      final items = await VideoImporter().pickAndImport(copyIntoApp: false);
      expect(items.length, 2);
      expect(items[0].artist, '夜の海');
      expect(items[0].title, '蒼');
      expect(items[1].artist, isNull);
      expect(items[1].title, 'ただの名前');
    });

    test('pickAndImportFolder: フォルダの中身を取り込み、キャンセルは null', () async {
      final root = await Directory.systemTemp.createTemp('yureru_pick');
      addTearDown(() => root.delete(recursive: true));
      await File('${root.path}/v.mp4').create();
      await File('${root.path}/note.txt').create();

      String? answer = root.path;
      messenger.setMockMethodCallHandler(mediaPickerChannel, (call) async {
        expect(call.method, 'pickFolder');
        return answer;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(mediaPickerChannel, null),
      );

      final importer = VideoImporter();
      final items = await importer.pickAndImportFolder(copyIntoApp: false);
      expect(items, isNotNull);
      expect(items!.single.sourcePath, '${root.path}/v.mp4');

      answer = null; // キャンセル
      expect(await importer.pickAndImportFolder(copyIntoApp: false), isNull);
    });

    test('onProgress がコピー進捗を報告する', () async {
      final root = await Directory.systemTemp.createTemp('yureru_prog');
      addTearDown(() => root.delete(recursive: true));
      await File('${root.path}/a.mp4').create();
      await File('${root.path}/b.mp4').create();
      messenger.setMockMethodCallHandler(mediaPickerChannel, (call) async {
        expect(call.method, 'pickFolder');
        return root.path;
      });

      final seen = <List<int>>[];
      final items = await VideoImporter().pickAndImportFolder(
        copyIntoApp: false,
        onProgress: (done, total) => seen.add([done, total]),
      );
      expect(items?.length, 2);
      expect(seen.first, [0, 0]);
      expect(seen.last, [2, 2]);
      for (var i = 1; i < seen.length; i++) {
        expect(seen[i][0] >= seen[i - 1][0], isTrue);
      }
    });
  });

  group('MediaItem.sourcePath', () {
    test('JSON往復で保持され、無いデータは null', () {
      final m = MediaItem(
        title: 'v',
        localPath: '/lib/v.mp4',
        sourcePath: '/in/v.mp4',
        artworkPath: '/app/yureru_artwork/cover.png',
        lyricsPath: '/app/yureru_lyrics/v.lrc',
      );
      expect(MediaItem.fromJson(m.toJson()).sourcePath, '/in/v.mp4');
      expect(
        MediaItem.fromJson(m.toJson()).artworkPath,
        '/app/yureru_artwork/cover.png',
      );
      expect(
        MediaItem.fromJson(m.toJson()).lyricsPath,
        '/app/yureru_lyrics/v.lrc',
      );
      final old = MediaItem.fromJson({
        'id': 'x',
        'title': 'v',
        'localPath': '/lib/v.mp4',
        'createdAt': DateTime(2026, 1, 1).toIso8601String(),
      });
      expect(old.sourcePath, isNull);
    });
  });

  group('LibraryNotifier.addMedia 重複排除', () {
    test('同じ sourcePath は二重登録されない', () async {
      final repo = InMemoryLibraryRepository();
      final notifier = LibraryNotifier(repo);
      await notifier.addMedia([
        MediaItem(title: 'a', localPath: '/lib/1', sourcePath: '/in/a.mp4'),
      ]);
      await notifier.addMedia([
        MediaItem(title: 'a', localPath: '/lib/2', sourcePath: '/in/a.mp4'),
      ]);
      expect(notifier.state.media.length, 1);
      await notifier.addMedia([
        MediaItem(title: 'b', localPath: '/lib/3', sourcePath: '/in/b.mp4'),
      ]);
      expect(notifier.state.media.length, 2);
      expect(repo.media.length, 2); // 永続化にも反映
    });
  });

  test('一時再生メディアは一覧・保存データに追加せず保持する', () async {
    final repo = InMemoryLibraryRepository();
    final notifier = LibraryNotifier(repo);
    final temporary = MediaItem(
      title: '試聴',
      localPath: '/tmp/listen.opus',
      origin: 'temporary',
    );
    notifier.addTemporaryMedia([temporary]);
    expect(notifier.state.byId(temporary.id), isNotNull);
    expect(notifier.state.savedMedia, isEmpty);
    expect(repo.media, isEmpty);
  });

  group('LibraryNotifier.setDurationMs', () {
    test('保持して永続化し、不明・不変は無視する', () async {
      final repo = InMemoryLibraryRepository();
      final notifier = LibraryNotifier(repo);
      final m = MediaItem(title: 'v', localPath: '/tmp/v.mp4');
      await notifier.addMedia([m]);
      await notifier.setDurationMs(m.id, 305000);
      expect(notifier.state.media.single.durationMs, 305000);
      expect(repo.media.single.durationMs, 305000);
      await notifier.setDurationMs(m.id, 305000); // 不変は no-op
      await notifier.setDurationMs('nope', 1000); // 不明は no-op
      await notifier.setDurationMs(m.id, 0); // 非正は no-op
      expect(notifier.state.media.single.durationMs, 305000);
    });
  });
}
