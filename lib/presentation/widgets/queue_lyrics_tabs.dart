import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../i18n.dart';
import '../theme.dart';

class QueueLyricsTabs extends ConsumerWidget {
  const QueueLyricsTabs({
    super.key,
    required this.showLyrics,
    required this.onQueue,
    required this.onLyrics,
  });

  final bool showLyrics;
  final VoidCallback onQueue;
  final VoidCallback onLyrics;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        _Tab(
          label: ref.tr('next_contents'),
          selected: !showLyrics,
          onTap: onQueue,
        ),
        const SizedBox(width: 22),
        _Tab(label: ref.tr('lyrics'), selected: showLyrics, onTap: onLyrics),
      ],
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? themeTextPrimary(context) : themeTextSub(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 15,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            const SizedBox(height: 5),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: 2,
              width: selected ? 26 : 0,
              decoration: BoxDecoration(
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
