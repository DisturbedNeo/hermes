import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hermes/core/enums/message_role.dart';
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

  MessageRole _selectedRole = MessageRole.user;

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

    if (_previousStreamState == StreamState.streaming &&
        currentStreamState == StreamState.idle) {
      final serverActive = _chat.serverManager.current != null;

      if (serverActive && widget.enabled) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _focusNode.requestFocus();
        });
      }
    }

    _previousStreamState = currentStreamState;
  }

  IconData _iconForRole(MessageRole role) => switch (role) {
    MessageRole.user => Icons.person,
    MessageRole.assistant => Icons.smart_toy,
    MessageRole.system => Icons.display_settings,
  };

  String _labelForRole(MessageRole role) =>
      "${role.wire[0].toUpperCase()}${role.wire.substring(1).toLowerCase()}";

  void _insertMessage() {
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty) return;
    _controller.clear();
    _controller.selection = const TextSelection.collapsed(offset: 0);
    _focusNode.requestFocus();

    _chat.insertMessage(trimmed, _selectedRole);
  }

  ComposerMode _modeFor(String text) {
    if (widget.isStreaming) return ComposerMode.cancel;

    final isEmpty = text.trim().isEmpty;
    if (!isEmpty) return ComposerMode.send;

    return widget.lastWasAssistant ? ComposerMode.cont : ComposerMode.generate;
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
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

    if (_selectedRole != MessageRole.user) {
      _insertMessage();
      return KeyEventResult.handled;
    }

    if (!_chat.isStreaming) {
      final trimmed = _controller.text.trim();
      _controller.clear();
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
    final roleIsUser = _selectedRole == MessageRole.user;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 140, maxWidth: 180),
              child: Tooltip(
                message: 'Message role',
                waitDuration: const Duration(milliseconds: 400),
                child: DropdownButtonFormField<MessageRole>(
                  initialValue: _selectedRole,
                  isDense: true,
                  onChanged: widget.enabled
                      ? (v) {
                          if (v == null) return;
                          setState(() => _selectedRole = v);
                          _focusNode.requestFocus();
                        }
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'Role',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  items: MessageRole.values.map((role) {
                    return DropdownMenuItem<MessageRole>(
                      value: role,
                      child: Row(
                        children: [
                          Icon(_iconForRole(role), size: 18),
                          const SizedBox(width: 8),
                          Text(_labelForRole(role)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _controller,
                focusNode: _focusNode,
                minLines: 1,
                maxLines: 6,
                enabled: widget.enabled,
                keyboardType: TextInputType.multiline,
                textInputAction: (roleIsUser && !widget.isStreaming)
                    ? TextInputAction.send
                    : TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: !widget.enabled
                      ? 'Load a model to chat…'
                      : widget.isStreaming
                      ? 'Streaming response…'
                      : 'Type a message…',
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) {
                  if (!widget.enabled) return;
                  if (_selectedRole != MessageRole.user) {
                    _insertMessage();
                    return;
                  }
                  if (!_chat.isStreaming) {
                    final trimmed = _controller.text.trim();
                    _controller.clear();
                    _controller.selection = const TextSelection.collapsed(
                      offset: 0,
                    );
                    _focusNode.requestFocus();

                    if (trimmed.isNotEmpty) {
                      _chat.send(trimmed);
                    } else {
                      _chat.generateOrContinue();
                    }
                  }
                },
                onEditingComplete: () {
                  _focusNode.requestFocus();
                },
              ),
            ),
            const SizedBox(width: 8),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (_, value, __) {
                final mode = _modeFor(value.text);
                final List<Widget> buttons = [];

                if (_selectedRole == MessageRole.user) {
                  switch (mode) {
                    case ComposerMode.cancel:
                      buttons.add(
                        FilledButton.icon(
                          icon: const Icon(Icons.stop),
                          label: const Text('Cancel'),
                          onPressed: widget.onCancel,
                        ),
                      );
                      break;
                    case ComposerMode.generate:
                      buttons.add(
                        FilledButton.icon(
                          icon: const Icon(Icons.auto_awesome),
                          label: const Text('Generate'),
                          onPressed: widget.enabled ? widget.onGenerate : null,
                        ),
                      );
                      break;
                    case ComposerMode.cont:
                      buttons.add(
                        FilledButton.icon(
                          icon: const Icon(Icons.more_horiz),
                          label: const Text('Continue'),
                          onPressed: widget.enabled ? widget.onContinue : null,
                        ),
                      );
                      break;
                    case ComposerMode.send:
                      buttons.add(
                        FilledButton.icon(
                          icon: const Icon(Icons.send),
                          label: const Text('Send'),
                          onPressed: widget.enabled
                              ? () => widget.onSend(value.text.trim())
                              : null,
                        ),
                      );
                      break;
                  }

                  buttons.add(const SizedBox(width: 8));
                }

                buttons.add(
                  Tooltip(
                    message: 'Insert ${_labelForRole(_selectedRole)} message',
                    waitDuration: const Duration(milliseconds: 400),
                    child: FilledButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Insert'),
                      onPressed: widget.enabled ? _insertMessage : null,
                    ),
                  )
                );

                return Row(mainAxisSize: MainAxisSize.min, children: buttons);
              },
            ),
          ],
        ),
      ),
    );
  }
}
