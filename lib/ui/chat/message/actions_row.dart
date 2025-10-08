import 'package:flutter/material.dart';
import 'package:hermes/core/models/bubble.dart';

class ActionSpec {
  final IconData icon;
  final String tooltip;
  final Function(Bubble) onTap;
  final Color iconColor;
  final bool isEnabled;

  const ActionSpec({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.iconColor = Colors.black,
    this.isEnabled = true,
  });
}

class ActionsRow extends StatelessWidget {
  final List<ActionSpec> actions;
  final int maxInline;
  final double iconSize;
  final EdgeInsetsGeometry padding;
  final Bubble message;

  const ActionsRow({
    super.key,
    required this.actions,
    required this.message,
    this.maxInline = 3,
    this.iconSize = 18,
    this.padding = const EdgeInsets.symmetric(horizontal: 4),
  });

  @override
  Widget build(BuildContext context) {
    final inline = actions.take(maxInline).toList();
    final overflow = actions.skip(maxInline).toList();

    List<Widget> children = [
      for (final action in inline) iconButton(context, action),
      if (overflow.isNotEmpty) overflowButton(context, overflow),
    ];

    return Padding(
      padding: padding,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: children,
      ),
    );
  }

  Widget iconButton(BuildContext context, ActionSpec action) {
    return Tooltip(
      message: action.tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: IconButton(
        icon: Icon(action.icon, color: action.iconColor),
        iconSize: iconSize,
        padding: EdgeInsets.symmetric(horizontal: 2),
        constraints: const BoxConstraints(),
        onPressed: action.isEnabled ? () => action.onTap(message) : null,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
    );
  }

  Widget overflowButton(BuildContext context, List<ActionSpec> overflow) {
    return PopupMenuButton<int>(
      tooltip: 'More',
      itemBuilder: (ctx) => [
        for (int i = 0; i < overflow.length; i++)
          PopupMenuItem<int>(
            value: i,
            enabled: overflow[i].isEnabled,
            child: Row(
              children: [
                Icon(overflow[i].icon, size: 18, color: overflow[i].iconColor),
                const SizedBox(width: 8),
                Text(overflow[i].tooltip),
              ],
            ),
          ),
      ],
      onSelected: (i) => overflow[i].onTap(message),
      icon: Icon(
        Icons.more_horiz,
        size: iconSize,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      padding: EdgeInsets.zero,
    );
  }
}
