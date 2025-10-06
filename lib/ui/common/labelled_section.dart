import 'package:flutter/material.dart';

class LabelledSection extends StatelessWidget {
  const LabelledSection({
    super.key, 
    required this.label,
    required this.child,
    this.helper,
  });

  final String label;
  final Widget child;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: t.textTheme.titleMedium),
        if (helper != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(helper!, style: t.textTheme.bodySmall),
          ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}
