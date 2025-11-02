import 'package:flutter/material.dart';
import 'package:hermes/core/models/bubble.dart';

class ToolCallsView extends StatefulWidget {
  final Map<int, BubbleToolCall> tools;
  final Color fg;
  final Color bg;

  final bool initiallyExpanded;

  const ToolCallsView({
    super.key,
    required this.tools,
    required this.fg,
    required this.bg,
    this.initiallyExpanded = false,
  });

  @override
  State<ToolCallsView> createState() => _ToolCallsViewState();
}

class _ToolCallsViewState extends State<ToolCallsView> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final subtleBg = Color.alphaBlend(widget.fg.withValues(alpha: 0.06), widget.bg);
    final border = widget.fg.withValues(alpha: 0.12);

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: subtleBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    _expanded ? Icons.visibility_off : Icons.visibility,
                    size: 16,
                    color: widget.fg.withValues(alpha: 0.8),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _expanded ? 'Hide tool calls' : 'Show tool calls',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: widget.fg.withValues(alpha: 0.8),
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  AnimatedRotation(
                    duration: const Duration(milliseconds: 150),
                    turns: _expanded ? 0.5 : 0.0,
                    child: Icon(Icons.expand_more, size: 16, color: widget.fg.withValues(alpha: 0.6)),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 160),
            crossFadeState: _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: _ToolCallsBody(
                tools: widget.tools,
                fg: widget.fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolCallsBody extends StatelessWidget {
  final Map<int, BubbleToolCall> tools;
  final Color fg;

  const _ToolCallsBody({
    required this.tools,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) {
    if (tools.isEmpty) {
      return Text(
        'No tool calls',
        style: TextStyle(
          color: fg.withValues(alpha: 0.6),
          fontSize: 12,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Tool Calls',
          style: TextStyle(
            color: fg.withValues(alpha: 0.7),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        ...tools.entries.map((e) {
          final t = e.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: t.name ?? 'tool ${e.key}',
                    style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (t.id != null)
                    TextSpan(
                      text: ' (${t.id})',
                      style: TextStyle(
                        color: fg.withValues(alpha: 0.5),
                        fontSize: 11,
                      ),
                    ),
                  const TextSpan(text: '\n'),
                  TextSpan(
                    text: t.arguments,
                    style: TextStyle(
                      color: fg.withValues(alpha: 0.9),
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}
