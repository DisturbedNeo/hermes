import 'package:flutter/material.dart';
import 'package:hermes/ui/chat/message/markdown_view.dart';

class ThinkSection extends StatefulWidget {
  final String text;
  final Color fg;
  final Color bg;
  final bool streaming;
  final VoidCallback? onTap;

  const ThinkSection({
    super.key,
    required this.text,
    required this.fg,
    required this.bg,
    this.onTap,
    this.streaming = false,
  });

  @override
  State<ThinkSection> createState() => _ThinkSectionState();
}

class _ThinkSectionState extends State<ThinkSection> {
  bool expanded = false;

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
            onTap: () => setState(() => expanded = !expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Icon(expanded ? Icons.visibility_off : Icons.visibility, size: 16, color: widget.fg.withValues(alpha: 0.8)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Row(
                      children: [
                        Text(
                          expanded ? 'Hide assistant thoughts' : 'Show assistant thoughts',
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                color: widget.fg.withValues(alpha: 0.8),
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        if (widget.streaming) ...[
                          const SizedBox(width: 8),
                          SizedBox(width: 10, height: 10, child: DotPulse(color: widget.fg.withValues(alpha: 0.7))),
                        ]
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    duration: const Duration(milliseconds: 150),
                    turns: expanded ? 0.5 : 0.0,
                    child: Icon(Icons.expand_more, size: 16, color: widget.fg.withValues(alpha: 0.6)),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 160),
            crossFadeState: expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: MarkdownView(
                data: widget.text, 
                onTapNonLink: widget.onTap
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DotPulse extends StatefulWidget {
  final Color color;
  const DotPulse({super.key, required this.color});
  @override
  State<DotPulse> createState() => _DotPulseState();
}

class _DotPulseState extends State<DotPulse> with SingleTickerProviderStateMixin {
  late final AnimationController c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  @override void dispose() { c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: c,
      builder: (_, __) => Opacity(
        opacity: 0.5 + 0.5 * (1 - (c.value - 0.5).abs() * 2),
        child: DecoratedBox(
          decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
        ),
      ),
    );
  }
}
