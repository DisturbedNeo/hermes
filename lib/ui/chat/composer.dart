import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hermes/core/enums/stream_state.dart';
import 'package:hermes/core/services/chat_service.dart';
import 'package:hermes/core/services/service_provider.dart';

enum ComposerMode { send, generate, cont, cancel }

class Composer extends StatefulWidget {
  final VoidCallback onCancel;
  final Function(String) onSend;
  final VoidCallback onGenerate;
  final VoidCallback onContinue;

  final bool isStreaming;
  final bool enabled;
  final bool lastWasAssistant;

  const Composer({
    super.key,
    required this.onCancel,
    required this.onSend,
    required this.onGenerate,
    required this.onContinue,
    required this.isStreaming,
    required this.enabled,
    required this.lastWasAssistant,
  });

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final _chat = serviceProvider.get<ChatService>();

  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  StreamState _previousStreamState = StreamState.idle;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode()..onKeyEvent = _onKey;

    _previousStreamState = _chat.streamState;
    _chat.addListener(_onChatChanged);
  }

  @override
  void dispose() {
    _chat.removeListener(_onChatChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onChatChanged() {
    final currentStreamState = _chat.streamState;

    if (_previousStreamState == StreamState.streaming 
    && currentStreamState == StreamState.idle) {

      final serverActive = _chat.serverManager.current != null;

      if (serverActive && widget.enabled) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _focusNode.requestFocus();
        });
      }
    }

    _previousStreamState = currentStreamState;
  }

  ComposerMode _modeFor(String text) {
    if (widget.isStreaming) return ComposerMode.cancel;

    final isEmpty = text.trim().isEmpty;
    if (!isEmpty) return ComposerMode.send;

    return widget.lastWasAssistant ? ComposerMode.cont : ComposerMode.generate;
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.enter) {
      return KeyEventResult.ignored;
    }

    if (HardwareKeyboard.instance.isShiftPressed) {
      final text = _controller.text;
      final sel = _controller.selection;
      final updated = text.replaceRange(sel.start, sel.end, '\n');
      _controller.text = updated;
      _controller.selection = TextSelection.collapsed(offset: sel.start + 1);
      return KeyEventResult.handled;
    }

    if (!_chat.isStreaming) {
      final trimmed = _controller.text.trim();
      _controller.clear();
      node.unfocus();
      if (trimmed.isNotEmpty) {
        _chat.send(trimmed);
      } else {
        _chat.generateOrContinue();
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
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
                controller: _controller,
                focusNode: _focusNode,
                minLines: 1,
                maxLines: 6,
                enabled: widget.enabled && !widget.isStreaming,
                keyboardType: TextInputType.multiline,
                decoration: InputDecoration(
                  hintText: !widget.enabled
                      ? 'Load a model to chat…'
                      : (widget.isStreaming
                          ? 'Streaming response…'
                          : 'Message the model…'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (_, value, __) {
                final mode = _modeFor(value.text);

                switch (mode) {
                  case ComposerMode.cancel:
                    return FilledButton.icon(
                      icon: const Icon(Icons.stop),
                      label: const Text('Cancel'),
                      onPressed: widget.onCancel,
                    );
                  case ComposerMode.generate:
                    return FilledButton.icon(
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('Generate'),
                      onPressed: widget.enabled ? widget.onGenerate : null,
                    );
                  case ComposerMode.cont:
                    return FilledButton.icon(
                      icon: const Icon(Icons.more_horiz),
                      label: const Text('Continue'),
                      onPressed: widget.enabled ? widget.onContinue : null,
                    );
                  case ComposerMode.send:
                    return FilledButton.icon(
                      icon: const Icon(Icons.send),
                      label: const Text('Send'),
                      onPressed: widget.enabled
                          ? () => widget.onSend(value.text.trim())
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
