import 'package:flutter/material.dart';

Future<bool> confirmDiscardUnsavedChanges(
  BuildContext context,
  String Function(String) tr,
) async {
  return await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(tr('unsaved_changes_title')),
          content: Text(tr('unsaved_changes_message')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(tr('keep_editing')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(tr('discard_changes')),
            ),
          ],
        ),
      ) ??
      false;
}

/// Prevents a dialog from silently dropping edits through Escape or Back.
class UnsavedChangesGuard extends StatelessWidget {
  const UnsavedChangesGuard({
    super.key,
    required this.hasUnsavedChanges,
    required this.translate,
    required this.onDiscard,
    required this.child,
  });

  final bool hasUnsavedChanges;
  final String Function(String) translate;
  final VoidCallback onDiscard;
  final Widget child;

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: !hasUnsavedChanges,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop || !hasUnsavedChanges) return;
      if (await confirmDiscardUnsavedChanges(context, translate) &&
          context.mounted) {
        onDiscard();
      }
    },
    child: child,
  );
}
