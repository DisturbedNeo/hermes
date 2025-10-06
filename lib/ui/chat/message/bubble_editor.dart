import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hermes/ui/common/key_hint.dart';

class BubbleEditor extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final Color foreground;
  final VoidCallback onSave;
  final VoidCallback onCancel;

  const BubbleEditor({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.foreground,
    required this.onSave,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = Theme.of(context).textTheme;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, control: true): onSave,
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): onSave, // mac
        const SingleActivator(LogicalKeyboardKey.escape): onCancel,
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            focusNode: focusNode,
            controller: controller,
            maxLines: null,
            minLines: 3,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              hintText: 'Edit message…',
              filled: true,
              fillColor: scheme.surface.withValues(alpha: 0.75),
              contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            ),
            style: base.bodyMedium?.copyWith(fontSize: 16, color: scheme.onSecondaryContainer),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onCancel,
                style: TextButton.styleFrom(
                  side: const BorderSide(width: 0.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: KeyHint(label: 'Cancel', shortcut: 'Esc', hintColor: foreground),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onSave,
                style: TextButton.styleFrom(
                  side: const BorderSide(width: 0.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: KeyHint(label: 'Save', shortcut: 'Ctrl/⌘ + Enter', hintColor: foreground),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
