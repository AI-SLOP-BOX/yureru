import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yureru/app_state.dart';
import 'package:yureru/data/store.dart';
import 'package:yureru/domain/models.dart';
import 'package:yureru/playback/fake_engine.dart';
import 'package:yureru/presentation/i18n.dart';
import 'package:yureru/presentation/screens/playlists_screen.dart';
import 'package:yureru/presentation/theme.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('playlist list can switch between name and manual order', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 700);
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
          theme: yureruTheme(isDark: true),
          home: const Scaffold(body: PlaylistsScreen()),
        ),
      ),
    );
    final container = ProviderScope.containerOf(
      tester.element(find.byType(Scaffold)),
    );
    await container.read(libraryProvider.notifier).createPlaylist('Zeta');
    await container.read(libraryProvider.notifier).createPlaylist('Alpha');
    await tester.pumpAndSettle();

    expect(find.text('Zeta'), findsOneWidget);
    expect(find.byTooltip('次に再生'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Zeta')).dy,
      lessThan(tester.getTopLeft(find.text('Alpha')).dy),
    );

    await tester.tap(find.text('手動順'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('名前順').last, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Alpha')).dy,
      lessThan(tester.getTopLeft(find.text('Zeta')).dy),
    );

    await tester.tap(find.text('名前順'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('手動順').last, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Zeta')).dy,
      lessThan(tester.getTopLeft(find.text('Alpha')).dy),
    );

    final library = container.read(libraryProvider.notifier);
    await library.addMedia([
      MediaItem(id: 'played-zeta', title: 'Zeta track', localPath: '/zeta'),
      MediaItem(id: 'played-alpha', title: 'Alpha track', localPath: '/alpha'),
      MediaItem(
        id: 'played-alpha-2',
        title: 'Second Alpha track',
        localPath: '/alpha-2',
      ),
    ]);
    final playlists = container.read(libraryProvider).playlists;
    final zetaId = playlists.firstWhere((p) => p.name == 'Zeta').id;
    final alphaId = playlists.firstWhere((p) => p.name == 'Alpha').id;
    await library.addToPlaylist(zetaId, 'played-zeta');
    await library.addToPlaylist(alphaId, 'played-alpha');
    await library.addToPlaylist(alphaId, 'played-alpha-2');
    await library.recordPlayback('played-zeta', at: DateTime.utc(2026, 1, 1));
    await library.recordPlayback('played-alpha', at: DateTime.utc(2026, 1, 2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('手動順'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('最近再生した順').last, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Alpha')).dy,
      lessThan(tester.getTopLeft(find.text('Zeta')).dy),
    );
    expect(find.byIcon(Icons.arrow_forward_rounded), findsNothing);
    expect(find.byTooltip('次に再生'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
