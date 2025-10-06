import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

MarkdownStyleSheet bubbleMarkdownStyles(BuildContext context, {
  required Color textColor,
  required Color background,
}) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final base = theme.textTheme;
  final codeBg = scheme.surfaceContainerHighest.withValues(alpha: 0.7);
  final blockStripe = theme.dividerColor;

  return MarkdownStyleSheet.fromTheme(theme).copyWith(
    p: base.bodyMedium?.copyWith(fontSize: 16, color: textColor),
    h1: base.headlineSmall?.copyWith(color: textColor, fontWeight: FontWeight.w700),
    h2: base.titleLarge?.copyWith(color: textColor, fontWeight: FontWeight.w700),
    h3: base.titleMedium?.copyWith(color: textColor, fontWeight: FontWeight.w700),
    a: base.bodyMedium?.copyWith(decoration: TextDecoration.underline, color: scheme.primary),
    code: base.bodyMedium?.copyWith(fontFamily: 'monospace', fontSize: 14, color: textColor, backgroundColor: codeBg),
    codeblockDecoration: BoxDecoration(color: codeBg, borderRadius: BorderRadius.circular(8)),
    codeblockPadding: const EdgeInsets.all(10),
    blockquote: base.bodyMedium?.copyWith(color: textColor.withValues(alpha: 0.9), fontStyle: FontStyle.italic),
    blockquoteDecoration: BoxDecoration(
      color: background,
      border: Border(left: BorderSide(color: blockStripe, width: 4)),
      borderRadius: BorderRadius.circular(6),
    ),
    listBullet: base.bodyMedium?.copyWith(color: textColor, fontSize: 16),
    listIndent: 24,
    blockSpacing: 10,
    tableHead: base.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: textColor),
    tableBody: base.bodyMedium?.copyWith(color: textColor),
    tableBorder: TableBorder.symmetric(
      inside: BorderSide(color: theme.dividerColor),
      outside: BorderSide(color: theme.dividerColor),
    ),
  );
}
