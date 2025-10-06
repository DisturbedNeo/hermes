import 'package:flutter/material.dart';
import 'package:hermes/core/helpers/style.dart';
import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/ui/chat/message/bubble_editor.dart';
import 'package:hermes/ui/chat/message/bubble_markdown_view.dart';
import 'package:hermes/ui/chat/message/bubble_surface.dart';

class MessageBubble extends StatefulWidget {
  final Bubble b;
  final bool editable;
  final ValueChanged<String>? onSave;

  const MessageBubble({
    super.key,
    required this.b,
    this.editable = true,
    this.onSave,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  bool _editing = false;
  late final TextEditingController _ctrl = TextEditingController(text: widget.b.text);
  final FocusNode _focus = FocusNode();

  @override
  void didUpdateWidget(covariant MessageBubble old) {
    super.didUpdateWidget(old);
    if (!_editing && old.b.text != widget.b.text) _ctrl.text = widget.b.text;
    if (_editing && !widget.editable) _cancel();
  }

  void _beginEdit() {
    if (!widget.editable) return;
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _focus.requestFocus(); });
  }

  void _cancel() { setState(() { _editing = false; _ctrl.text = widget.b.text; }); }
  void _save()   { widget.onSave?.call(_ctrl.text); setState(() => _editing = false); }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = widget.b.role == 'user';
    final align = isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final (bg, fg) = getColorsForRole(scheme, widget.b.role);
    final borderRadius = BorderRadius.circular(8);

    return Column(
      crossAxisAlignment: align,
      children: [
        BubbleSurface(
          borderRadius: borderRadius,
          background: bg,
          enabled: widget.editable && !_editing,
          onTap: _beginEdit,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 120),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: _editing
                ? BubbleEditor(
                    key: const ValueKey('editor'),
                    controller: _ctrl,
                    focusNode: _focus,
                    foreground: fg,
                    onCancel: _cancel,
                    onSave: _save,
                  )
                : BubbleMarkdownView(
                    key: const ValueKey('markdown'),
                    text: widget.b.text,
                    foreground: fg,
                    background: bg,
                  ),
          ),
        ),
      ],
    );
  }
}
