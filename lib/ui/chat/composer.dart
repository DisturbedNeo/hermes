import 'package:flutter/material.dart';

class Composer extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onCancel;
  final ValueChanged<String> onSubmitted;
  final bool isStreaming;
  final bool enabled;

  const Composer({
    super.key, 
    required this.controller,
    required this.onCancel,
    required this.onSubmitted,
    required this.isStreaming,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveOnSubmitted = (enabled && !isStreaming) ? onSubmitted : (_){};

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 6,
                enabled: enabled && !isStreaming,
                textInputAction: isStreaming ? TextInputAction.none : TextInputAction.send,
                onSubmitted: effectiveOnSubmitted,
                decoration: InputDecoration(
                  hintText: !enabled
                      ? 'Load a model to chat…'
                      : (isStreaming ? 'Streaming response…' : 'Message the model…'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),

            if (isStreaming)
              FilledButton.icon(
                icon: const Icon(Icons.stop),
                label: const Text('Cancel'),
                onPressed: onCancel,
              )
            else
              FilledButton.icon(
                icon: const Icon(Icons.send),
                label: const Text('Send'),
                onPressed: enabled ? () => onSubmitted(controller.text.trim()) : null,
              ),
          ],
        ),
      ),
    );
  }
}
