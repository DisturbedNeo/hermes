import 'package:flutter/material.dart';
import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/helpers/style.dart';
import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/ui/chat/message/bubble_editor.dart';
import 'package:hermes/ui/chat/message/bubble_surface.dart';
import 'package:hermes/ui/chat/message/bubble_view.dart';

class MessageBubble extends StatefulWidget {
  final Bubble b;
  final bool editable;
  final Function(String reasoning, String text)? onSave;

  const MessageBubble({
    super.key,
    required this.b,
    this.editable = true,
    this.onSave,
  });

  @override
  State<MessageBubble> createState() => MessageBubbleState();
}

class MessageBubbleState extends State<MessageBubble> {
  bool editing = false;
  bool showReasoning = false;

  final FocusNode focus = FocusNode();

  String prevReasoning = '';
  String prevText = '';

  late final TextEditingController reasoningController = TextEditingController(
    text: widget.b.reasoning,
  );

  late final TextEditingController textController = TextEditingController(
    text: widget.b.text,
  );

  @override
  void didUpdateWidget(covariant MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!editing && oldWidget.b.reasoning != widget.b.reasoning) {
      reasoningController.text = widget.b.reasoning;
    }

    if (!editing && oldWidget.b.text != widget.b.text) {
      textController.text = widget.b.text;
    }

    if (editing && !widget.editable) _cancel();
  }

  void _beginEdit() {
    if (!widget.editable) return;
    setState(() => editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) focus.requestFocus();
    });
  }

  void _cancel() {
    setState(() {
      editing = false;
      reasoningController.text = widget.b.reasoning;
      textController.text = widget.b.text;
    });
  }

  void _save() {
    widget.onSave?.call(reasoningController.text, textController.text);
    setState(() => editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = widget.b.role == MessageRole.user;
    final align = isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final (bg, fg) = getColorsForRole(scheme, widget.b.role);
    final borderRadius = BorderRadius.circular(8);

    return Column(
      crossAxisAlignment: align,
      children: [
        BubbleSurface(
          borderRadius: borderRadius,
          background: bg,
          enabled: widget.editable && !editing,
          onTap: _beginEdit,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 120),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: editing
                ? BubbleEditor(
                    key: const ValueKey('editor'),
                    reasoningController: reasoningController,
                    textController: textController,
                    focusNode: focus,
                    fg: fg,
                    onCancel: _cancel,
                    onSave: _save,
                  )
                : BubbleView(
                    key: const ValueKey('view'),
                    reasoning: widget.b.reasoning,
                    text: widget.b.text,
                    showReasoning: showReasoning,
                    fg: fg,
                    bg: bg,
                    onTap: _beginEdit,
                    onToggleReasoning: () => setState(() => showReasoning = !showReasoning),
                  ),
          ),
        ),
      ],
    );
  }
}
