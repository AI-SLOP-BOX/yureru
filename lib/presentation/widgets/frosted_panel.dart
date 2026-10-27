import 'dart:ui';

import 'package:flutter/material.dart';

/// A clipped, neutral glass surface for the app's persistent controls.
/// Keep blur at panel level rather than applying it to every library row.
class FrostedPanel extends StatelessWidget {
  const FrostedPanel({
    super.key,
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.padding = EdgeInsets.zero,
    this.margin = EdgeInsets.zero,
    this.fillOpacity,
    this.borderOpacity,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double? fillOpacity;
  final double? borderOpacity;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final highContrast = MediaQuery.highContrastOf(context);
    final opacity = fillOpacity ?? (dark ? 0.86 : 0.90);
    final tint = dark ? const Color(0xFF202020) : const Color(0xFFF7F7F7);
    return Padding(
      padding: margin,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.18 : 0.06),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: BackdropFilter(
            enabled: !highContrast,
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: highContrast ? tint : null,
                gradient: highContrast
                    ? null
                    : LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color.alphaBlend(
                            Colors.white.withValues(alpha: dark ? 0.045 : 0.2),
                            tint.withValues(alpha: opacity),
                          ),
                          tint.withValues(alpha: opacity),
                        ],
                      ),
                borderRadius: borderRadius,
                border: Border.all(
                  color: dark
                      ? Colors.white.withValues(alpha: borderOpacity ?? 0.13)
                      : Colors.black.withValues(alpha: borderOpacity ?? 0.09),
                ),
              ),
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ),
    );
  }
}
