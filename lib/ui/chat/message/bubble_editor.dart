import 'package:flutter/material.dart';

class BubbleEditor extends StatelessWidget {
  final TextEditingController reasoningController;
  final TextEditingController textController;
  final FocusNode focusNode;
  final Color fg;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  const BubbleEditor({
    super.key,
    required this.reasoningController,
    required this.textController,
    required this.focusNode,
    required this.fg,
    required this.onCancel,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (reasoningController.text.isNotEmpty)
          TextField(
            controller: reasoningController,
            focusNode: focusNode,
            maxLines: null,
            style: TextStyle(color: fg, fontStyle: FontStyle.italic),
            decoration: const InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              labelText: 'Reasoning',
            ),
          ),
        TextField(
          controller: textController,
          maxLines: null,
          style: TextStyle(color: fg),
          decoration: InputDecoration(
            isCollapsed: true,
            border: InputBorder.none,
            labelText: reasoningController.text.isNotEmpty
                ? 'Answer'
                : 'Message',
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: onCancel,
              style: TextButton.styleFrom(foregroundColor: fg),
              child: const Text('Cancel')
            ),
            TextButton(
              onPressed: onSave, 
              style: TextButton.styleFrom(foregroundColor: fg),
              child: const Text('Save')
            ),
          ],
        ),
      ],
    );
  }
}
