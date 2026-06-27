import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/enums/stream_state.dart';
import 'package:hermes/core/helpers/a11y.dart';
import 'package:hermes/core/helpers/responsive.dart';
import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/services/chat/chat_service.dart';
import 'package:hermes/core/services/service_provider.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/ui/chat/tool_selector.dart';

enum ComposerMode { send, generate, cont, cancel }

class Composer extends StatefulWidget {
  final ChatService chat;
  final bool enabled;
  final FocusNode? focusNode;

  const Composer({
    super.key,
    required this.chat,
    required this.enabled,
    this.focusNode,
  });

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
  final _toolService = serviceProvider.get<ToolService>();

  late final TextEditingController _controller;
  late FocusNode _focusNode;
  late bool _ownsFocusNode;
  FocusOnKeyEventCallback? _previousOnKeyEvent;

  StreamState _previousStreamState = StreamState.idle;
  late int _messageDisplayRevision;

  MessageRole _selectedRole = MessageRole.user;

  final Set<String> _selectedToolIds = {};
  var _usingDefaultTools = true;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _configureFocusNode();
    _previousStreamState = widget.chat.chatStream.state;
    _messageDisplayRevision = widget.chat.messageStore.displayRevision;
    widget.chat.chatStream.addListener(_onStreamChanged);
    widget.chat.messageStore.addListener(_onMessageStoreChanged);
  }

  @override
  void didUpdateWidget(covariant Composer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      _releaseFocusNode();
      _configureFocusNode();
    }
    if (oldWidget.chat != widget.chat) {
      oldWidget.chat.chatStream.removeListener(_onStreamChanged);
      oldWidget.chat.messageStore.removeListener(_onMessageStoreChanged);
      _previousStreamState = widget.chat.chatStream.state;
      _messageDisplayRevision = widget.chat.messageStore.displayRevision;
      widget.chat.chatStream.addListener(_onStreamChanged);
      widget.chat.messageStore.addListener(_onMessageStoreChanged);
      _controller.clear();
      _selectedToolIds.clear();
      _usingDefaultTools = true;
    }
  }

  void _configureFocusNode() {
    final provided = widget.focusNode;
    _ownsFocusNode = provided == null;
    _focusNode = provided ?? FocusNode();
    _previousOnKeyEvent = _focusNode.onKeyEvent;
    _focusNode.onKeyEvent = _handleFocusKeyEvent;
  }

  void _releaseFocusNode() {
    _focusNode.onKeyEvent = _previousOnKeyEvent;
    _previousOnKeyEvent = null;
    if (_ownsFocusNode) _focusNode.dispose();
  }

  KeyEventResult _handleFocusKeyEvent(FocusNode node, KeyEvent event) {
    final result = _onKey(node, event);
    if (result != KeyEventResult.ignored) return result;
    return _previousOnKeyEvent?.call(node, event) ?? KeyEventResult.ignored;
  }

  List<String> _effectiveToolIds() {
    return _usingDefaultTools
        ? widget.chat.defaultToolIds
        : _selectedToolIds.toList();
  }

  @override
  void dispose() {
    widget.chat.chatStream.removeListener(_onStreamChanged);
    widget.chat.messageStore.removeListener(_onMessageStoreChanged);
    _releaseFocusNode();
    _controller.dispose();
    super.dispose();
  }

  void _onMessageStoreChanged() {
    final nextRevision = widget.chat.messageStore.displayRevision;
    if (nextRevision == _messageDisplayRevision) return;
    setState(() => _messageDisplayRevision = nextRevision);
  }

  void _onStreamChanged() {
    final chat = widget.chat;
    if (_previousStreamState == StreamState.streaming &&
        chat.chatStream.state == StreamState.idle) {
      final serverActive = chat.serverManager.current != null;

      if (serverActive && widget.enabled) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _focusNode.requestFocus();
        });
      }
    }

    _previousStreamState = chat.chatStream.state;
  }

  IconData _iconForRole(MessageRole role) => switch (role) {
    MessageRole.user => Icons.person,
    MessageRole.assistant => Icons.smart_toy,
    MessageRole.system => Icons.display_settings,
    MessageRole.tool => Icons.settings_suggest,
  };

  String _labelForRole(MessageRole role) =>
      "${role.wire[0].toUpperCase()}${role.wire.substring(1).toLowerCase()}";

  Widget _roleDropdownItem(MessageRole role, {required double iconSize}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final hasTightLabelSpace =
            constraints.hasBoundedWidth && constraints.maxWidth < 56;

        if (!constraints.hasBoundedWidth) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_iconForRole(role), size: iconSize),
              const SizedBox(width: 6),
              Text(_labelForRole(role)),
            ],
          );
        }

        return Row(
          children: [
            Icon(_iconForRole(role), size: iconSize),
            if (!hasTightLabelSpace) ...[
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _labelForRole(role),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _roleDropdownSelectedItem(
    MessageRole role, {
    required double iconSize,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showLabel =
            !constraints.hasBoundedWidth || constraints.maxWidth >= 56;

        return Row(
          children: [
            Icon(_iconForRole(role), size: iconSize),
            if (showLabel) ...[
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _labelForRole(role),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  /// Builds an accessibility label for the role dropdown.
  String _buildRoleSemanticLabel(MessageRole role) {
    final label = _labelForRole(role);
    return 'Message role: $label';
  }

  /// Builds an accessibility label for the tool selector button.
  String _buildToolButtonSemanticLabel(int toolCount, bool isEnabled) {
    if (!isEnabled) return 'Select tools, disabled';
    if (toolCount == 0) return 'Select tools';
    return 'Tools selected: $toolCount';
  }

  /// Builds the role dropdown widget used in both wide and narrow layouts.
  Widget _buildRoleDropdown(
    ChatService chat,
    bool inputEnabled, {
    required double iconSize,
    required EdgeInsetsGeometry contentPadding,
  }) {
    return AccessibleWidget(
      label: _buildRoleSemanticLabel(_selectedRole),
      isButton: true,
      enabled: inputEnabled,
      child: DropdownButtonFormField<MessageRole>(
        initialValue: _selectedRole,
        isExpanded: true,
        isDense: true,
        selectedItemBuilder: (context) => MessageRole.values
            .map((role) => _roleDropdownSelectedItem(role, iconSize: iconSize))
            .toList(),
        onChanged: inputEnabled
            ? (v) {
                if (v == null) return;
                setState(() => _selectedRole = v);
                _focusNode.requestFocus();
              }
            : null,
        decoration: InputDecoration(
          labelText: 'Role',
          border: const OutlineInputBorder(),
          contentPadding: contentPadding,
        ),
        items: MessageRole.values.map((role) {
          return DropdownMenuItem<MessageRole>(
            value: role,
            child: _roleDropdownItem(role, iconSize: iconSize),
          );
        }).toList(),
      ),
    );
  }

  /// Builds the composer's text input field, shared across wide and narrow layouts.
  Widget _buildTextField(ChatService chat, bool inputEnabled) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      minLines: 1,
      maxLines: 6,
      enabled: inputEnabled,
      keyboardType: TextInputType.multiline,
      textInputAction:
          (_selectedRole == MessageRole.user && !chat.chatStream.isStreaming)
          ? TextInputAction.send
          : TextInputAction.newline,
      decoration: InputDecoration(
        hintText: _hintTextForMode(chat),
        border: const OutlineInputBorder(),
      ),
      onSubmitted: _handleSubmitted,
      onEditingComplete: () => _focusNode.requestFocus(),
    );
  }

  /// Returns the hint text appropriate for the current chat mode.
  String _hintTextForMode(ChatService chat) {
    if (!widget.enabled) return 'Load a model to chat...';
    if (chat.taskBusy) return 'Task is running...';
    if (chat.chatStream.isStreaming) return 'Streaming response...';
    if (chat.executionMode == ExecutionMode.chat) return 'Type a message...';
    if (chat.executionMode == ExecutionMode.project) {
      return 'Describe the project goal...';
    }
    return 'Describe the task...';
  }

  /// Builds the tool selector button with badge showing the selected tool count.
  Widget _toolButtonWidget(
    bool inputEnabled,
    int toolCount,
    VoidCallback? onPressed,
  ) {
    final hasTools = toolCount > 0;
    return AccessibleWidget(
      label: _buildToolButtonSemanticLabel(toolCount, inputEnabled),
      isButton: true,
      enabled: inputEnabled,
      child: IconButton(
        tooltip: hasTools ? 'Tools ($toolCount)' : 'Select tools',
        onPressed: onPressed,
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
                    toolCount.toString(),
                    style: const TextStyle(fontSize: 9, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _insertMessage() {
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty) return;
    _controller.clear();
    _controller.selection = const TextSelection.collapsed(offset: 0);
    _focusNode.requestFocus();
    widget.chat.insertMessage(trimmed, _selectedRole);
  }

  ComposerMode _modeFor(String text) {
    final chat = widget.chat;
    if (chat.chatStream.isStreaming || chat.taskBusy) {
      return ComposerMode.cancel;
    }

    final isEmpty = text.trim().isEmpty;
    if (!isEmpty) return ComposerMode.send;

    return (chat.messageStore.messages.isNotEmpty &&
            chat.messageStore.messages.last.role == MessageRole.assistant)
        ? ComposerMode.cont
        : ComposerMode.generate;
  }

  Future<void> _openToolSelector() async {
    if (!widget.enabled) return;
    final allTools = _toolService.getToolDefinitions(
      includeWorkspaceTools: widget.chat.workspaceToolsEnabled,
    );
    final initial = _effectiveToolIds().toSet();

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
              allTools: allTools,
              initiallySelectedIds: initial,
            );
          },
        );
      },
    );

    if (selected != null && mounted) {
      setState(() {
        _usingDefaultTools = false;
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

    final chat = widget.chat;
    if (!chat.chatStream.isStreaming && !chat.taskBusy) {
      final trimmed = _controller.text.trim();
      _controller.clear();
      if (trimmed.isNotEmpty) {
        chat.send(trimmed, tools: _effectiveToolIds());
      } else {
        chat.generateOrContinue(tools: _effectiveToolIds());
      }
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  Widget _buildActionControls(
    ChatService chat,
    TextEditingValue value,
    bool inputEnabled,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.hasBoundedWidth && constraints.maxWidth < 180;

        if (_selectedRole != MessageRole.user) {
          return Align(
            alignment: Alignment.centerRight,
            child: _actionButton(
              icon: Icons.add,
              label: 'Insert',
              tooltip: 'Insert ${_labelForRole(_selectedRole)} message',
              onPressed: inputEnabled ? _insertMessage : null,
              compact: compact,
            ),
          );
        }

        final mode = _modeFor(value.text);
        return Align(
          alignment: Alignment.centerRight,
          child: switch (mode) {
            ComposerMode.cancel => _actionButton(
              icon: Icons.stop,
              label: 'Cancel',
              onPressed: chat.taskBusy
                  ? chat.taskCancellationRequested
                        ? null
                        : () => unawaited(chat.cancelTaskRun())
                  : chat.cancelGeneration,
              compact: compact,
            ),
            ComposerMode.generate => _actionButton(
              icon: Icons.auto_awesome,
              label: 'Generate',
              onPressed: inputEnabled
                  ? () => chat.generateOrContinue(tools: _effectiveToolIds())
                  : null,
              compact: compact,
            ),
            ComposerMode.cont => _actionButton(
              icon: Icons.more_horiz,
              label: 'Continue',
              onPressed: inputEnabled
                  ? () => chat.generateOrContinue(tools: _effectiveToolIds())
                  : null,
              compact: compact,
            ),
            ComposerMode.send => _actionButton(
              icon: chat.executionMode == ExecutionMode.chat
                  ? Icons.send
                  : chat.executionMode == ExecutionMode.project
                  ? Icons.rocket_launch_outlined
                  : Icons.account_tree_outlined,
              label: chat.executionMode == ExecutionMode.chat
                  ? 'Send'
                  : chat.executionMode.label,
              onPressed: inputEnabled
                  ? () {
                      final trimmed = value.text.trim();
                      _controller.clear();
                      _controller.selection = const TextSelection.collapsed(
                        offset: 0,
                      );
                      _focusNode.requestFocus();
                      chat.send(trimmed, tools: _effectiveToolIds());
                    }
                  : null,
              compact: compact,
            ),
          },
        );
      },
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    required bool compact,
    String? tooltip,
  }) {
    if (compact) {
      return IconButton.filled(
        icon: Icon(icon),
        tooltip: tooltip ?? label,
        onPressed: onPressed,
      );
    }

    final button = FilledButton.icon(
      icon: Icon(icon),
      label: Text(label),
      onPressed: onPressed,
    );

    if (tooltip == null) return button;

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: button,
    );
  }

  /// Builds the wide-screen composer layout with all controls in a single row.
  List<Widget> _buildWideLayout(BuildContext context) {
    final chat = widget.chat;
    final inputEnabled = widget.enabled && !chat.taskBusy;
    final effectiveToolIds = _effectiveToolIds();

    return [
      ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 140, maxWidth: 180),
        child: Tooltip(
          message: 'Message role',
          waitDuration: const Duration(milliseconds: 400),
          child: _buildRoleDropdown(
            chat,
            inputEnabled,
            iconSize: 18,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
          ),
        ),
      ),
      const SizedBox(width: 8),
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toolButtonWidget(
            inputEnabled,
            effectiveToolIds.length,
            inputEnabled ? _openToolSelector : null,
          ),
          if (effectiveToolIds.isNotEmpty)
            Text(
              '${effectiveToolIds.length}',
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(fontSize: 10),
            ),
        ],
      ),
      const SizedBox(width: 8),
      Expanded(child: _buildTextField(chat, inputEnabled)),
      const SizedBox(width: 8),
      AnimatedBuilder(
        animation: chat.chatStream,
        builder: (_, _) {
          return ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (_, value, _) =>
                _buildActionControls(chat, value, inputEnabled),
          );
        },
      ),
    ];
  }

  /// Builds the narrow-screen composer layout with controls stacked vertically.
  List<Widget> _buildNarrowLayout(BuildContext context) {
    final chat = widget.chat;
    final inputEnabled = widget.enabled && !chat.taskBusy;
    final effectiveToolIds = _effectiveToolIds();

    return [
      // Top row: role dropdown + tool button
      Row(
        children: [
          Expanded(
            flex: 2,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 100, maxWidth: 180),
              child: Tooltip(
                message: 'Message role',
                waitDuration: const Duration(milliseconds: 400),
                child: _buildRoleDropdown(
                  chat,
                  inputEnabled,
                  iconSize: 16,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 1,
            child: Center(
              child: _toolButtonWidget(
                inputEnabled,
                effectiveToolIds.length,
                inputEnabled ? _openToolSelector : null,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      // Full-width text field
      _buildTextField(chat, inputEnabled),
      const SizedBox(height: 8),
      // Action buttons
      AnimatedBuilder(
        animation: chat.chatStream,
        builder: (_, _) {
          return ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (_, value, _) =>
                _buildActionControls(chat, value, inputEnabled),
          );
        },
      ),
    ];
  }

  void _handleSubmitted(String text) {
    if (!widget.enabled || widget.chat.taskBusy) return;
    if (_selectedRole != MessageRole.user) {
      _insertMessage();
      return;
    }
    final trimmed = text.trim();
    _controller.clear();
    _controller.selection = const TextSelection.collapsed(offset: 0);
    _focusNode.requestFocus();
    if (trimmed.isNotEmpty) {
      widget.chat.send(trimmed, tools: _effectiveToolIds());
    } else {
      widget.chat.generateOrContinue(tools: _effectiveToolIds());
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = widget.chat;
    final inputEnabled = widget.enabled && !chat.taskBusy;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = Responsive.isNarrow(context);

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ExecutionModeSelector(chat: chat, enabled: inputEnabled),
                const SizedBox(height: 8),
                if (isNarrow)
                  ..._buildNarrowLayout(context)
                else
                  Row(children: _buildWideLayout(context)),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ExecutionModeSelector extends StatelessWidget {
  final ChatService chat;
  final bool enabled;

  const _ExecutionModeSelector({required this.chat, required this.enabled});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SegmentedButton<ExecutionMode>(
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
        segments: const [
          ButtonSegment(
            value: ExecutionMode.chat,
            icon: Icon(Icons.chat_bubble_outline),
            label: Text('Chat'),
            tooltip: 'Chat',
          ),
          ButtonSegment(
            value: ExecutionMode.task,
            icon: Icon(Icons.account_tree_outlined),
            label: Text('Task'),
            tooltip: 'Task',
          ),
          ButtonSegment(
            value: ExecutionMode.project,
            icon: Icon(Icons.rocket_launch_outlined),
            label: Text('Project'),
            tooltip: 'Project',
          ),
        ],
        selected: {chat.executionMode},
        onSelectionChanged: enabled
            ? (selection) => chat.setExecutionMode(selection.single)
            : null,
      ),
    );
  }
}
