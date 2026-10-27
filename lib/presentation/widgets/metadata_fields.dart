import 'package:flutter/material.dart';

import '../../domain/creator_names.dart';

class MetadataField extends StatelessWidget {
  const MetadataField({
    super.key,
    required this.label,
    required this.controller,
    required this.textColor,
    required this.labelColor,
    required this.borderColor,
    required this.isDark,
    this.autofocus = false,
    this.keyboardType,
  });

  final String label;
  final TextEditingController controller;
  final Color textColor;
  final Color labelColor;
  final Color borderColor;
  final bool isDark;
  final bool autofocus;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 7),
        child: Text(
          label,
          style: TextStyle(
            color: labelColor,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
      TextField(
        controller: controller,
        autofocus: autofocus,
        keyboardType: keyboardType,
        style: TextStyle(color: textColor, fontSize: 15),
        decoration: InputDecoration(
          hintText: label,
          filled: true,
          fillColor: isDark
              ? Colors.white.withValues(alpha: 0.035)
              : const Color(0xFFF7F7F7),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 13,
            vertical: 13,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: borderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: labelColor.withValues(alpha: 0.8)),
          ),
        ),
      ),
    ],
  );
}

class CreatorNamesField extends StatefulWidget {
  const CreatorNamesField({
    super.key,
    required this.initialValue,
    required this.textColor,
    required this.labelColor,
    required this.borderColor,
    required this.isDark,
    required this.onChanged,
    this.strings,
  });

  final String? initialValue;
  final Color textColor;
  final Color labelColor;
  final Color borderColor;
  final bool isDark;
  final ValueChanged<List<String>> onChanged;
  final String Function(String key)? strings;

  String text(String key, String fallback) => strings?.call(key) ?? fallback;

  @override
  State<CreatorNamesField> createState() => CreatorNamesFieldState();
}

class CreatorNamesFieldState extends State<CreatorNamesField> {
  late final List<String> _names = splitCreatorNames(widget.initialValue);
  final _entryController = TextEditingController();

  @override
  void dispose() {
    _entryController.dispose();
    super.dispose();
  }

  void _addName([String? value]) {
    final name = (value ?? _entryController.text).trim();
    if (name.isEmpty) return;
    if (_names.any(
      (existing) => existing.toLowerCase() == name.toLowerCase(),
    )) {
      _entryController.clear();
      return;
    }
    setState(() => _names.add(name));
    widget.onChanged(List.unmodifiable(_names));
    _entryController.clear();
  }

  void _removeName(String name) {
    setState(() => _names.remove(name));
    widget.onChanged(List.unmodifiable(_names));
  }

  Future<void> _editName(String original) async {
    final index = _names.indexOf(original);
    if (index < 0) return;
    final controller = TextEditingController(text: original);
    final updated = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(widget.text('edit_creator_names', '投稿者名を編集')),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
          decoration: InputDecoration(
            labelText: widget.text('enter_creator_names', '投稿者名'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(widget.text('cancel', 'キャンセル')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: Text(widget.text('save', '保存')),
          ),
        ],
      ),
    );
    controller.dispose();
    final name = updated?.trim();
    if (name == null || name.isEmpty || !mounted) return;
    if (_names.asMap().entries.any(
      (entry) =>
          entry.key != index && entry.value.toLowerCase() == name.toLowerCase(),
    )) {
      return;
    }
    setState(() => _names[index] = name);
    widget.onChanged(List.unmodifiable(_names));
  }

  @override
  Widget build(BuildContext context) {
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: widget.borderColor),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 7),
          child: Text(
            widget.text('creator_names', '投稿者（共作可）'),
            style: TextStyle(
              color: widget.labelColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ),
        if (_names.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 2,
            children: [
              for (final name in _names)
                InputChip(
                  label: Text(name),
                  onPressed: () => _editName(name),
                  onDeleted: () => _removeName(name),
                  tooltip: widget.text('tap_to_edit', 'タップして編集'),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  side: BorderSide(color: widget.borderColor),
                  backgroundColor: widget.isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : const Color(0xFFF7F7F7),
                  labelStyle: TextStyle(color: widget.textColor, fontSize: 13),
                ),
            ],
          ),
          const SizedBox(height: 6),
        ],
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _entryController,
                style: TextStyle(color: widget.textColor, fontSize: 15),
                textInputAction: TextInputAction.done,
                onSubmitted: _addName,
                decoration: InputDecoration(
                  hintText: _names.isEmpty
                      ? widget.text('name_input', '名前を入力')
                      : widget.text('add_collaborator', '共作者を追加'),
                  filled: true,
                  fillColor: widget.isDark
                      ? Colors.white.withValues(alpha: 0.035)
                      : const Color(0xFFF7F7F7),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 13,
                  ),
                  enabledBorder: fieldBorder,
                  focusedBorder: fieldBorder.copyWith(
                    borderSide: BorderSide(
                      color: widget.labelColor.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: widget.text('add_name', '名前を追加'),
              onPressed: () => _addName(),
              icon: const Icon(Icons.add_rounded),
              style: IconButton.styleFrom(
                foregroundColor: widget.textColor,
                side: BorderSide(color: widget.borderColor),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
