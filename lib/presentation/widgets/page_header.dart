import 'package:flutter/material.dart';

import '../layout_metrics.dart';
import '../theme.dart';

/// Shared page header (search sits in the top bar; pages show a small title).
class PageHeader extends StatelessWidget {
  final String title;
  final String? trailing;
  final Widget? actions;
  const PageHeader({
    super.key,
    required this.title,
    this.trailing,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inset = LayoutMetrics.horizontalInset(context);
    final heading = Text(
      title,
      style: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w800,
        color: isDark ? kTextPrimary : const Color(0xFF242424),
        letterSpacing: -0.5,
      ),
    );
    final badge = trailing == null
        ? null
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: themeCard(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: themeBorder(context)),
            ),
            child: Text(
              trailing!,
              style: TextStyle(
                fontSize: 12,
                color: themeTextSub(context),
                fontWeight: FontWeight.w500,
              ),
            ),
          );
    return Padding(
      padding: EdgeInsets.fromLTRB(inset, 10, inset, 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 600) {
            return Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [heading, ?badge, ?actions],
            );
          }
          return Row(
            children: [
              heading,
              if (badge != null) ...[const SizedBox(width: 12), badge],
              if (actions != null) ...[const Spacer(), actions!],
            ],
          );
        },
      ),
    );
  }
}
