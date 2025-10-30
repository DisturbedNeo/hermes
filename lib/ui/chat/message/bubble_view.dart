import 'package:flutter/material.dart';
import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/ui/chat/message/markdown_view.dart';
import 'package:hermes/ui/chat/message/think_section.dart';
import 'package:hermes/ui/chat/message/tool_calls_view.dart';

class BubbleView extends StatefulWidget {
  final String reasoning;
  final String text;
  final bool showReasoning;
  final Map<int, BubbleToolCall> tools;
  final Color fg;
  final Color bg;
  final VoidCallback onTap;
  final VoidCallback onToggleReasoning;

  const BubbleView({
    super.key, 
    required this.reasoning,
    required this.text,
    required this.showReasoning,
    required this.fg,
    required this.bg,
    required this.onTap,
    required this.onToggleReasoning,
    this.tools = const {},
  });

  @override
  State<BubbleView> createState() => _BubbleViewState();
}

class _BubbleViewState extends State<BubbleView> {
  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];

    if (widget.reasoning.isNotEmpty) {
      children.add(
        ThinkSection(
          key: const ValueKey('think'),
          text: widget.reasoning,
          fg: widget.fg,
          bg: widget.bg,
          streaming: false,
          expanded: widget.showReasoning,
          onTapBanner: widget.onToggleReasoning,
          onTapBody: widget.onTap,
        ),
      );
      children.add(const SizedBox(height: 8));
    }

    if (widget.tools.isNotEmpty) {
      children.add(
        ToolCallsView(
          tools: widget.tools,
          fg: widget.fg,
          bg: widget.bg,
        )
      );
    }

    if (widget.text.isNotEmpty) {
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: MarkdownView(
            key: const ValueKey('content'),
            data: widget.text,
            onTapNonLink: widget.onTap,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}
