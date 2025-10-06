import 'package:flutter/material.dart';

class KeyHint extends StatelessWidget {
  final String label;
  final String shortcut;
  final Color hintColor;
  
  const KeyHint({
    super.key, 
    required this.label,
    required this.shortcut,
    required this.hintColor,
  });

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(
      context,
    ).textTheme.labelLarge?.copyWith(color: hintColor);
    final muted = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: hintColor);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: style),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            border: Border.all(color: hintColor, width: 0.5),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(shortcut, style: muted),
        ),
      ],
    );
  }
}
