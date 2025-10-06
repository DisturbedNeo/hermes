import 'package:flutter/material.dart';

class BubbleSurface extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final Color background;
  final VoidCallback? onTap;
  final bool enabled;

  const BubbleSurface({
    super.key, 
    required this.child,
    required this.borderRadius,
    required this.background,
    this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: borderRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: borderRadius,
        mouseCursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered)) return Colors.black.withValues(alpha: 0.05);
          if (states.contains(WidgetState.focused))  return Colors.black.withValues(alpha: 0.08);
          return null;
        }),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 900),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: background, borderRadius: borderRadius),
            child: child,
          ),
        ),
      ),
    );
  }
}
