import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yureru/app_state.dart';
import 'package:yureru/data/store.dart';
import 'package:yureru/domain/models.dart';
import 'package:yureru/playback/fake_engine.dart';
import 'package:yureru/presentation/i18n.dart';
import 'package:yureru/presentation/screens/playlist_detail_screen.dart';
import 'package:yureru/presentation/theme.dart';

class _SeededLibraryNotifier extends LibraryNotifier {
  _SeededLibraryNotifier(super.repo, LibraryState seed) {
    state = seed;
  }
}

class _SeededQueueNotifier extends QueueNotifier {
  _SeededQueueNotifier() {
    start(['current', 'existing'], shuffle: false);
  }
}

void main() {
  testWidgets('playlist contents can switch to name order', (tester) async {
    final zulu = MediaItem(
      id: 'zulu',
      title: 'Zulu',
      localPath: '/zulu.mp4',
      createdAt: DateTime.utc(2025),
    );
    final alpha = MediaItem(
      id: 'alpha',
      title: 'Alpha',
      localPath: '/alpha.mp4',
      createdAt: DateTime.utc(2026),
    );
    final queue = _SeededQueueNotifier();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeLanguageCodeProvider.overrideWithValue('ja'),
          repositoryProvider.overrideWithValue(InMemoryLibraryRepository()),
          libraryProvider.overrideWith(
            (ref) => _SeededLibraryNotifier(
              ref.read(repositoryProvider),
              LibraryState(
                media: [zulu, alpha],
                playlists: [
                  Playlist(
                    id: 'playlist',
                    name: 'Test playlist',
                    mediaIds: ['zulu', 'alpha'],
                  ),
                ],
                loaded: true,
              ),
            ),
          ),
          queueProvider.overrideWith((ref) => queue),
          engineProvider.overrideWithValue(FakePlaybackEngine()),
        ],
        child: MaterialApp(
          theme: yureruTheme(isDark: false),
          home: const Scaffold(
            body: PlaylistDetailScreen(playlistId: 'playlist'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('playlist-sort-selector')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('名前順').last);
    await tester.tap(find.text('名前順').last, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.text('Alpha')).dy,
      lessThan(tester.getTopLeft(find.text('Zulu')).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('playlist next action queues item without starting it', (
    tester,
  ) async {
    final current = MediaItem(
      id: 'current',
      title: 'Current',
      localPath: '/current.mp4',
    );
    final later = MediaItem(
      id: 'later',
      title: 'Later',
      localPath: '/later.mp4',
    );
    final playlist = Playlist(
      id: 'playlist',
      name: 'Test playlist',
      mediaIds: ['current', 'later'],
    );
    final queue = _SeededQueueNotifier();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeLanguageCodeProvider.overrideWithValue('ja'),
          repositoryProvider.overrideWithValue(InMemoryLibraryRepository()),
          libraryProvider.overrideWith(
            (ref) => _SeededLibraryNotifier(
              ref.read(repositoryProvider),
              LibraryState(
                media: [current, later],
                playlists: [playlist],
                loaded: true,
              ),
            ),
          ),
          queueProvider.overrideWith((ref) => queue),
          engineProvider.overrideWithValue(FakePlaybackEngine()),
        ],
        child: MaterialApp(
          theme: yureruTheme(isDark: false),
          home: const Scaffold(
            body: PlaylistDetailScreen(playlistId: 'playlist'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final nextButton = find.byKey(const ValueKey('playlist-play-next-later'));
    await tester.ensureVisible(nextButton);
    await tester.tap(nextButton);
    await tester.pumpAndSettle();

    expect(queue.state.currentId, 'current');
    expect(queue.state.queue, ['current', 'later', 'existing']);
    expect(find.text('Later — 次に再生'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
