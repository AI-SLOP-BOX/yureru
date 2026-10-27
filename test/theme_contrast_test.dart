import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yureru/presentation/theme.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance();
  final y = b.computeLuminance();
  return x > y ? (x + 0.05) / (y + 0.05) : (y + 0.05) / (x + 0.05);
}

void main() {
  for (final dark in [true, false]) {
    test(
      'body, secondary, selected and primary action text remain readable dark=$dark',
      () {
        final theme = yureruTheme(isDark: dark);
        final scheme = theme.colorScheme;
        for (final color in [
          theme.scaffoldBackgroundColor,
          scheme.surface,
          scheme.surfaceContainerHigh,
          scheme.onSurface,
          scheme.onSurfaceVariant,
        ]) {
          expect(color.r, closeTo(color.g, 0.001));
          expect(color.g, closeTo(color.b, 0.001));
        }
        expect(scheme.primary.r, isNot(closeTo(scheme.primary.g, 0.001)));
        expect(
          scheme.primaryContainer.r,
          isNot(closeTo(scheme.primaryContainer.g, 0.001)),
        );

        for (final surface in [
          theme.scaffoldBackgroundColor,
          scheme.surface,
          scheme.surfaceContainerHigh,
        ]) {
          expect(
            contrast(scheme.onSurface, surface),
            greaterThanOrEqualTo(4.5),
          );
          expect(
            contrast(scheme.onSurfaceVariant, surface),
            greaterThanOrEqualTo(4.5),
          );
        }
        expect(
          contrast(scheme.onPrimaryContainer, scheme.primaryContainer),
          greaterThanOrEqualTo(4.5),
        );
        final style = theme.filledButtonTheme.style!;
        expect(
          contrast(
            style.foregroundColor!.resolve({})!,
            style.backgroundColor!.resolve({})!,
          ),
          greaterThanOrEqualTo(4.5),
        );
      },
    );
  }
}
