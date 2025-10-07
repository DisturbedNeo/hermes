import 'dart:async';

import 'package:flutter/material.dart';
import 'package:hermes/core/helpers/style.dart';
import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/ui/chat/message/bubble_editor.dart';
import 'package:hermes/ui/chat/message/bubble_surface.dart';
import 'package:hermes/ui/chat/message/markdown_view.dart';
import 'package:hermes/ui/chat/message/think_section.dart';
import 'package:hermes/ui/chat/message/think_stream_parser.dart';

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
  State<MessageBubble> createState() => MessageBubbleState();
}

class MessageBubbleState extends State<MessageBubble> {
  bool editing = false;

  final FocusNode focus = FocusNode();

  final ThinkStreamParser parser = ThinkStreamParser();
  String prevText = '';

  Timer? idleTimer;

  late final TextEditingController ctrl = TextEditingController(
    text: widget.b.text,
  );

  @override
  void initState() {
    super.initState();
    ingestUpdate(widget.b.text);
  }

  @override
  void didUpdateWidget(covariant MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (!editing && oldWidget.b.text != widget.b.text) {
      ctrl.text = widget.b.text;
    }

    if (editing && !widget.editable) cancel();

    if (oldWidget.b.text != widget.b.text) {
      ingestUpdate(widget.b.text);
    }
  }

  void ingestUpdate(String newText) {
    if (prevText.isNotEmpty && newText.startsWith(prevText)) {
      final delta = newText.substring(prevText.length);
      if (delta.isNotEmpty) parser.addChunk(delta);
    } else {
      parser.reset();
      if (newText.isNotEmpty) parser.addChunk(newText);
    }

    prevText = newText;

    idleTimer?.cancel();
    idleTimer = Timer(const Duration(milliseconds: 250), parser.flushTail);
  }

  void beginEdit() {
    if (!widget.editable) return;
    setState(() => editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) focus.requestFocus();
    });
  }

  void cancel() {
    setState(() {
      editing = false;
      ctrl.text = widget.b.text;
    });
  }

  void save() {
    widget.onSave?.call(ctrl.text);
    setState(() => editing = false);
  }

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
          enabled: widget.editable && !editing,
          onTap: beginEdit,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 120),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: editing
                ? BubbleEditor(
                    key: const ValueKey('editor'),
                    controller: ctrl,
                    focusNode: focus,
                    foreground: fg,
                    onCancel: cancel,
                    onSave: save,
                  )
                : AnimatedBuilder(
                    key: const ValueKey('markdown-plus-think'),
                    animation: parser,
                    builder: (context, _) => partsColumn(fg, bg),
                  ),
          ),
        ),
      ],
    );
  }

  Widget partsColumn(Color fg, Color bg) {
    final children = <Widget>[];
    for (var i = 0; i < parser.parts.length; i++) {
      final p = parser.parts[i];
      if (i > 0) children.add(const SizedBox(height: 8));

      children.add(
        p.isThink
            ? ThinkSection(
                key: ValueKey(p.id),
                text: p.text,
                fg: fg,
                bg: bg,
                streaming: !p.closed,
                onTap: beginEdit,
              )
            : Padding(
                padding: const EdgeInsets.symmetric(vertical: 0, horizontal: 6),
                child: MarkdownView(
                  key: ValueKey(p.id),
                  data: p.text,
                  onTapNonLink: beginEdit,
                ),
              ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  @override
  void dispose() {
    idleTimer?.cancel();
    parser.dispose();
    super.dispose();
  }
}
