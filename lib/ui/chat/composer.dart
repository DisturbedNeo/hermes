import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/enums/stream_state.dart';
import 'package:hermes/core/services/chat_service.dart';
import 'package:hermes/core/services/service_provider.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/core/models/tool_definition.dart';
import 'package:hermes/ui/chat/tool_selector.dart';

enum ComposerMode { send, generate, cont, cancel }

class Composer extends StatefulWidget {
  final bool enabled;

  const Composer({
    super.key,
    required this.enabled,
  });

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final _chat = serviceProvider.get<ChatService>();
  final _toolService = serviceProvider.get<ToolService>();

  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  StreamState _previousStreamState = StreamState.idle;

  MessageRole _selectedRole = MessageRole.user;

  final Set<String> _selectedToolIds = {};

  late final List<ToolDefinition> _allTools;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _focusNode = FocusNode()..onKeyEvent = _onKey;
    _previousStreamState = _chat.streamState;
    _chat.addListener(_onChatChanged);

    _allTools = _toolService.getToolDefinitions();
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
    if (_chat.isStreaming) return ComposerMode.cancel;

    final isEmpty = text.trim().isEmpty;
    if (!isEmpty) return ComposerMode.send;

    return (_chat.messages.isNotEmpty &&
            _chat.messages.last.role == MessageRole.assistant)
        ? ComposerMode.cont
        : ComposerMode.generate;
  }

  Future<void> _openToolSelector() async {
    if (!widget.enabled) return;

    final selected = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return ToolSelector(
              allTools: _allTools,
              initiallySelectedIds: _selectedToolIds,
            );
          },
        );
      },
    );

    if (selected != null && mounted) {
      setState(() {
        _selectedToolIds
          ..clear()
          ..addAll(selected);
      });
    }
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
        _chat.send(
          trimmed,
          tools: _selectedToolIds.toList(),
        );
      } else {
        _chat.generateOrContinue(
          tools: _selectedToolIds.toList(),
        );
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final roleIsUser = _selectedRole == MessageRole.user;
    final hasTools = _selectedToolIds.isNotEmpty;

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

            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: hasTools
                      ? 'Tools (${_selectedToolIds.length})'
                      : 'Select tools',
                  onPressed: widget.enabled ? _openToolSelector : null,
                  icon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.build),
                      if (hasTools)
                        Positioned(
                          right: -4,
                          top: -4,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: Colors.redAccent,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              _selectedToolIds.length.toString(),
                              style: const TextStyle(
                                fontSize: 9,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (hasTools)
                  Text(
                    '${_selectedToolIds.length}',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(fontSize: 10),
                  ),
              ],
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
                textInputAction: (roleIsUser && !_chat.isStreaming)
                    ? TextInputAction.send
                    : TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: !widget.enabled
                      ? 'Load a model to chat…'
                      : _chat.isStreaming
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
                      _chat.send(
                        trimmed,
                        tools: _selectedToolIds.toList(),
                      );
                    } else {
                      _chat.generateOrContinue(
                        tools: _selectedToolIds.toList(),
                      );
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
              builder: (_, value, _) {
                final mode = _modeFor(value.text);
                final List<Widget> buttons = [];

                if (_selectedRole == MessageRole.user) {
                  switch (mode) {
                    case ComposerMode.cancel:
                      buttons.add(
                        FilledButton.icon(
                          icon: const Icon(Icons.stop),
                          label: const Text('Cancel'),
                          onPressed: _chat.stopStreaming,
                        ),
                      );
                      break;
                    case ComposerMode.generate:
                      buttons.add(
                        FilledButton.icon(
                          icon: const Icon(Icons.auto_awesome),
                          label: const Text('Generate'),
                          onPressed: widget.enabled
                              ? () => _chat.generateOrContinue(
                                    tools: _selectedToolIds.toList(),
                                  )
                              : null,
                        ),
                      );
                      break;
                    case ComposerMode.cont:
                      buttons.add(
                        FilledButton.icon(
                          icon: const Icon(Icons.more_horiz),
                          label: const Text('Continue'),
                          onPressed: widget.enabled
                              ? () => _chat.generateOrContinue(
                                    tools: _selectedToolIds.toList(),
                                  )
                              : null,
                        ),
                      );
                      break;
                    case ComposerMode.send:
                      buttons.add(
                        FilledButton.icon(
                          icon: const Icon(Icons.send),
                          label: const Text('Send'),
                          onPressed: widget.enabled
                              ? () => _chat.send(
                                    value.text.trim(),
                                    tools: _selectedToolIds.toList(),
                                  )
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
                  ),
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
