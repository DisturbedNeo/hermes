import 'package:flutter/material.dart';

enum ComposerMode { send, generate, cont, cancel }

class Composer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;

  final VoidCallback onCancel;
  final Function(String) onSend;
  final VoidCallback onGenerate;
  final VoidCallback onContinue;

  final bool isStreaming;
  final bool enabled;
  final bool lastWasAssistant;

  const Composer({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onCancel,
    required this.onSend,
    required this.onGenerate,
    required this.onContinue,
    required this.isStreaming,
    required this.enabled,
    required this.lastWasAssistant,
  });

  ComposerMode modeFor(String text) {
    if (isStreaming) return ComposerMode.cancel;

    final isEmpty = text.trim().isEmpty;

    if (!isEmpty) return ComposerMode.send;

    return lastWasAssistant ? ComposerMode.cont : ComposerMode.generate;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                minLines: 1,
                maxLines: 6,
                enabled: enabled && !isStreaming,
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(
                  hintText: !enabled
                      ? 'Load a model to chat…'
                      : (isStreaming
                          ? 'Streaming response…'
                          : 'Message the model…'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Rebuild the button reactively as the user types.
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (_, value, __) {
                final mode = modeFor(value.text);

                switch (mode) {
                  case ComposerMode.cancel:
                    return FilledButton.icon(
                      icon: const Icon(Icons.stop),
                      label: const Text('Cancel'),
                      onPressed: onCancel,
                    );
                  case ComposerMode.generate:
                    return FilledButton.icon(
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('Generate'),
                      onPressed: enabled ? onGenerate : null,
                    );
                  case ComposerMode.cont:
                    return FilledButton.icon(
                      icon: const Icon(Icons.more_horiz),
                      label: const Text('Continue'),
                      onPressed: enabled ? onContinue : null,
                    );
                  case ComposerMode.send:
                    return FilledButton.icon(
                      icon: const Icon(Icons.send),
                      label: const Text('Send'),
                      onPressed: enabled
                          ? () => onSend(value.text.trim())
                          : null,
                    );
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
