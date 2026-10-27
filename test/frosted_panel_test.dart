import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yureru/presentation/theme.dart';
import 'package:yureru/presentation/widgets/frosted_panel.dart';

void main() {
  for (final dark in [true, false]) {
    testWidgets(
      'glass keeps controls usable and respects high contrast ($dark)',
      (tester) async {
        var presses = 0;
        Future<void> render(bool highContrast) => tester.pumpWidget(
          MaterialApp(
            theme: yureruTheme(isDark: dark),
            home: MediaQuery(
              data: MediaQueryData(highContrast: highContrast),
              child: Scaffold(
                body: FrostedPanel(
                  borderRadius: BorderRadius.circular(16),
                  child: TextButton(
                    onPressed: () => presses++,
                    child: const Text('Play'),
                  ),
                ),
              ),
            ),
          ),
        );
        await render(false);
        final filter = tester.widget<BackdropFilter>(
          find.byType(BackdropFilter),
        );
        expect(filter.enabled, isTrue);
        // Even an extreme backdrop must not wash out secondary text.
        final decoration =
            tester
                    .widgetList<DecoratedBox>(
                      find.descendant(
                        of: find.byType(BackdropFilter),
                        matching: find.byType(DecoratedBox),
                      ),
                    )
                    .first
                    .decoration
                as BoxDecoration;
        final theme = yureruTheme(isDark: dark);
        final text = theme.colorScheme.onSurfaceVariant;
        for (final tint in decoration.gradient!.colors) {
          expect(tint.a, lessThan(1));
          for (final backdrop in [Colors.black, Colors.white]) {
            final surface = Color.alphaBlend(tint, backdrop);
            final foreground = Color.alphaBlend(
              text,
              surface,
            ).computeLuminance();
            final background = surface.computeLuminance();
            final lighter = foreground > background ? foreground : background;
            final darker = foreground < background ? foreground : background;
            expect(
              (lighter + 0.05) / (darker + 0.05),
              greaterThanOrEqualTo(4.5),
            );
          }
        }
        expect(
          find.ancestor(
            of: find.byType(BackdropFilter),
            matching: find.byType(ClipRRect),
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Play'));
        expect(presses, 1);
        await render(true);
        expect(
          tester.widget<BackdropFilter>(find.byType(BackdropFilter)).enabled,
          isFalse,
        );
        final surface =
            tester
                    .widgetList<DecoratedBox>(
                      find.descendant(
                        of: find.byType(BackdropFilter),
                        matching: find.byType(DecoratedBox),
                      ),
                    )
                    .first
                    .decoration
                as BoxDecoration;
        expect(surface.color!.a, 1);
        expect(surface.gradient, isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
