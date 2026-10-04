import 'package:flutter/material.dart';

/// Shared, bounded sizing rules for layouts that need to adapt across phones,
/// tablets, and desktop windows. Small icon/text sizes remain intentional
/// logical-pixel design tokens; structural widths and gutters use these rules.
abstract final class LayoutMetrics {
  static const double _desktopReferenceWidth = 1440;

  static double horizontalInset(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 600) return (width * 0.045).clamp(12.0, 20.0).toDouble();
    if (width < 1000) return (width * 0.025).clamp(20.0, 28.0).toDouble();
    return (width * 0.022).clamp(28.0, 48.0).toDouble();
  }

  static double desktopPane(
    double designWidth,
    double viewportWidth, {
    required double min,
    required double max,
  }) => (designWidth * viewportWidth / _desktopReferenceWidth)
      .clamp(min, max)
      .toDouble();

  static double recentCardWidth(BuildContext context) =>
      (MediaQuery.sizeOf(context).width * 0.115).clamp(120.0, 184.0).toDouble();
}
