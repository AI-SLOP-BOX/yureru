import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yureru/domain/models.dart';
import 'package:yureru/playback/fake_engine.dart';
import 'package:yureru/presentation/theme.dart';
import 'package:yureru/presentation/widgets/lyrics_editor_dialog.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('LRC editor exposes editable timestamps and seeking', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final engine = FakePlaybackEngine();
    final media = MediaItem(
      id: 'track',
      title: 'Track',
      localPath: '/music/track.mp4',
    );

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: yureruLightTheme(),
          home: Scaffold(
            body: LyricsEditorDialog(
              media: media,
              engine: engine,
              initialText: '[00:12.34]First line\n[00:14.00]Second line',
              inline: true,
              onCancel: () {},
              onSaved: (_) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Edit lyrics'), findsOneWidget);
    expect(find.text('First line'), findsOneWidget);
    expect(find.text('Second line'), findsOneWidget);

    await tester.tap(find.text('Plain text'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byTooltip('Seek to this time'), findsNothing);
    await tester.enterText(
      find.byType(TextField),
      '00:11 copied from a comment\n00:15 another line',
    );

    await tester.tap(find.text('Timed (LRC)'));
    await tester.pumpAndSettle();

    expect(find.text('copied from a comment'), findsOneWidget);
    expect(find.text('another line'), findsOneWidget);
    final lyricInput = tester.widget<TextField>(
      find.byKey(const ValueKey('lyrics-line-input-0')),
    );
    expect(lyricInput.minLines, 2);
    expect(
      tester.getSize(find.byKey(const ValueKey('lyrics-line-input-0'))).width,
      greaterThan(300),
    );
    expect(
      tester
          .widgetList<TextField>(find.byType(TextField))
          .first
          .controller!
          .text,
      '0:11.00',
    );
    await tester.tap(find.byTooltip('Seek to this time').first);
    expect(engine.seeks.single, const Duration(seconds: 11));
  });
}
