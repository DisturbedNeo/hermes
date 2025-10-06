import 'dart:math' as math;
import 'package:flutter/material.dart';

class MessageRow extends StatelessWidget {
  final Widget bubble;
  final Widget? actions;
  final bool isUser;

  // Tweak these if you like
  static const double _hGap = 8;
  static const double _maxBubbleWidth = 900;
  static const double _narrowBreakpoint = 560;

  const MessageRow({
    super.key,
    required this.bubble,
    required this.isUser,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final hasActions = actions != null;
        final isNarrow = constraints.maxWidth <= _narrowBreakpoint;

        if (isNarrow) {
          final bubbleCap = math.min(
            _maxBubbleWidth,
            constraints.maxWidth * 0.95,
          );

          return Column(
            crossAxisAlignment:
                isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: bubbleCap),
                child: bubble,
              ),
              if (hasActions) ...[
                const SizedBox(height: 6),
                Align(
                  alignment:
                      isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: actions!,
                ),
              ],
            ],
          );
        }

        final bubbleChild = Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxBubbleWidth),
            child: bubble,
          ),
        );

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: bubbleChild),
            if (hasActions) ...[
              const SizedBox(width: _hGap),
              IntrinsicWidth(child: actions!),
            ],
          ],
        );
      },
    );
  }
}
