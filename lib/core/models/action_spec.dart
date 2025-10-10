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
