import 'package:flutter/material.dart';
import 'package:hermes/core/models/bubble.dart';

class ToolCallsView extends StatelessWidget {
  final Map<int, BubbleToolCall> tools;
  final Color fg;
  final Color bg;

  const ToolCallsView({
    super.key, 
    required this.tools,
    required this.fg,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.all(6),
      child: Column(
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
              padding: const EdgeInsets.only(bottom: 4),
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
                    if (t.id != null) TextSpan(
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
      ),
    );
  }
}
