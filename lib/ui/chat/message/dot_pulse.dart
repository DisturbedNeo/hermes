import 'package:flutter/material.dart';

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
