import 'package:flutter/material.dart';

/// Returns the effective text scale multiplier from the current theme,
/// clamped to a maximum of 2.0x and minimum of 0.5x to prevent extreme scaling.
double effectiveTextScale(BuildContext context) {
  final mediaQuery = MediaQuery.of(context);
  // Use scale(16.0) / 16.0 to get the text scale factor from TextScaler
  return (mediaQuery.textScaler.scale(16.0) / 16.0).clamp(0.5, 2.0);
}

/// A reusable accessibility-aware wrapper that adds semantic labels
/// to child widgets while respecting text scale and interaction state.
///
/// Use this for custom interactive widgets that don't have built-in
/// semantics (e.g., custom tap targets, icon-only buttons).
class AccessibleWidget extends StatelessWidget {
  final Widget child;
  final String? label;
  final String? value;
  final bool selected;
  final bool enabled;
  final bool isButton;
  final bool isHeader;

  const AccessibleWidget({
    super.key,
    required this.child,
    this.label,
    this.value,
    this.selected = false,
    this.enabled = true,
    this.isButton = false,
    this.isHeader = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      value: value,
      selected: selected,
      enabled: enabled,
      button: isButton,
      header: isHeader,
      child: child,
    );
  }
}

/// Ensures minimum touch target size (48x48 logical pixels) for interactive elements.
///
/// This wraps the [child] in a [ConstrainedBox] to guarantee WCAG-compliant
/// touch target sizes, while using transparent [Material] to avoid visual changes.
Widget withMinimumTouchTarget({required Widget child}) {
  return Material(
    color: Colors.transparent,
    child: ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      child: child,
    ),
  );
}

/// A widget that respects dynamic text scaling for its content.
///
/// Automatically scales the font size based on the user's text scale preference,
/// clamped to a maximum of 2x to prevent layout overflow.
class ScalableText extends StatelessWidget {
  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;

  const ScalableText({
    super.key,
    required this.data,
    this.style,
    this.textAlign,
    this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ?? Theme.of(context).textTheme.bodyMedium!;
    final textScale = effectiveTextScale(context);
    return Text(
      data,
      style: baseStyle,
      textScaler: TextScaler.linear(textScale),
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: maxLines != null ? TextOverflow.ellipsis : null,
    );
  }
}
