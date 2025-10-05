import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

class Bubble {
  final String role;
  final String text;

  const Bubble({required this.role, required this.text});
}

class MessageBubble extends StatefulWidget {
  final Bubble b;
  final bool editable;
  final ValueChanged<String>? onSave;

  const MessageBubble({
    super.key,
    required this.b,
    this.editable = true,
    this.onSave,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  bool _editing = false;
  late final TextEditingController _editController = TextEditingController(
    text: widget.b.text,
  );
  final FocusNode _focusNode = FocusNode();

  @override
  void didUpdateWidget(covariant MessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing && oldWidget.b.text != widget.b.text) {
      _editController.text = widget.b.text;
    }
    if (_editing && !widget.editable) {
      _cancel();
    }
  }

  @override
  void dispose() {
    _editController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _beginEdit() {
    if (!widget.editable) return;
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  void _cancel() {
    setState(() {
      _editing = false;
      _editController.text = widget.b.text;
    });
  }

  void _save() {
    widget.onSave?.call(_editController.text);
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = widget.b.role == 'user';
    final align = isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    final bgColor = switch (widget.b.role) {
      'user' => scheme.primaryContainer,
      'assistant' => scheme.secondaryContainer,
      'system' => scheme.tertiaryContainer,
      'tool' => scheme.errorContainer,
      _ => scheme.surface,
    };

    final textColor = switch (widget.b.role) {
      'user' => scheme.onPrimaryContainer,
      'assistant' => scheme.onSecondaryContainer,
      'system' => scheme.onTertiaryContainer,
      'tool' => scheme.onErrorContainer,
      _ => scheme.onSurface,
    };

    final codeBg = scheme.surfaceContainerHighest.withValues(alpha: 0.7);
    final blockquoteStripe = Theme.of(context).dividerColor;
    final baseTheme = Theme.of(context).textTheme;

    final borderRadius = BorderRadius.circular(8);

    return Column(
      crossAxisAlignment: align,
      children: [
        Material(
          type: MaterialType.transparency,
          borderRadius: borderRadius,
          child: InkWell(
            onTap: _editing ? null : _beginEdit,
            borderRadius: borderRadius,
            mouseCursor: widget.editable && !_editing
                ? SystemMouseCursors.click
                : SystemMouseCursors.basic,
            overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
              if (states.contains(WidgetState.hovered)) {
                return Colors.black.withValues(alpha: 0.5);
              }
              if (states.contains(WidgetState.focused)) {
                return Colors.black.withValues(alpha: 0.6);
              }
              return null;
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              child: Container(
                padding: const EdgeInsets.all(12),
                constraints: const BoxConstraints(maxWidth: 900),
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: borderRadius,
                ),
                child: _editing
                    ? CallbackShortcuts(
                        bindings: <ShortcutActivator, VoidCallback>{
                          const SingleActivator(
                            LogicalKeyboardKey.enter,
                            control: true,
                          ): _save,
                          const SingleActivator(LogicalKeyboardKey.escape):
                              _cancel,
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              focusNode: _focusNode,
                              controller: _editController,
                              maxLines: null,
                              minLines: 3,
                              textInputAction: TextInputAction.newline,
                              decoration: InputDecoration(
                                hintText: 'Edit message…',
                                filled: true,
                                fillColor: scheme.surface.withValues(
                                  alpha: 0.75,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                  horizontal: 12,
                                ),
                              ),
                              style: baseTheme.bodyMedium?.copyWith(
                                fontSize: 16,
                                color: scheme.onSecondaryContainer,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton(
                                  onPressed: _cancel,
                                  style: TextButton.styleFrom(
                                    side: BorderSide(width: 0.5),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: _KeyHint(
                                    label: 'Cancel',
                                    shortcut: 'Esc',
                                    hintColor: textColor,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                TextButton(
                                  onPressed: _save,
                                  style: TextButton.styleFrom(
                                    side: BorderSide(width: 0.5),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: _KeyHint(
                                    label: 'Save',
                                    shortcut: 'Ctrl + Enter',
                                    hintColor: textColor,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      )
                    : MarkdownBody(
                        data: widget.b.text,
                        selectable: false,
                        softLineBreak: true,
                        onTapLink: (text, href, title) {
                          if (href != null) _launch(href);
                        },
                        styleSheet:
                            MarkdownStyleSheet.fromTheme(
                              Theme.of(context),
                            ).copyWith(
                              p: baseTheme.bodyMedium?.copyWith(
                                fontSize: 16,
                                color: textColor,
                              ),
                              h1: baseTheme.headlineSmall?.copyWith(
                                color: textColor,
                                fontWeight: FontWeight.w700,
                              ),
                              h2: baseTheme.titleLarge?.copyWith(
                                color: textColor,
                                fontWeight: FontWeight.w700,
                              ),
                              h3: baseTheme.titleMedium?.copyWith(
                                color: textColor,
                                fontWeight: FontWeight.w700,
                              ),
                              a: baseTheme.bodyMedium?.copyWith(
                                decoration: TextDecoration.underline,
                                color: scheme.primary,
                              ),
                              code: baseTheme.bodyMedium?.copyWith(
                                fontFamily: 'monospace',
                                fontSize: 14,
                                color: textColor,
                                backgroundColor: codeBg,
                              ),
                              codeblockDecoration: BoxDecoration(
                                color: codeBg,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              codeblockPadding: const EdgeInsets.all(10),
                              blockquote: baseTheme.bodyMedium?.copyWith(
                                color: textColor.withValues(alpha: 0.9),
                                fontStyle: FontStyle.italic,
                              ),
                              blockquoteDecoration: BoxDecoration(
                                color: bgColor,
                                border: Border(
                                  left: BorderSide(
                                    color: blockquoteStripe,
                                    width: 4,
                                  ),
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              listBullet: baseTheme.bodyMedium?.copyWith(
                                color: textColor,
                                fontSize: 16,
                              ),
                              listIndent: 24,
                              blockSpacing: 10,
                              tableHead: baseTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: textColor,
                              ),
                              tableBody: baseTheme.bodyMedium?.copyWith(
                                color: textColor,
                              ),
                              tableBorder: TableBorder.symmetric(
                                inside: BorderSide(
                                  color: Theme.of(context).dividerColor,
                                ),
                                outside: BorderSide(
                                  color: Theme.of(context).dividerColor,
                                ),
                              ),
                            ),
                        sizedImageBuilder: (config) {
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              config.uri.toString(),
                              width: config.width,
                              height: config.height,
                              fit: BoxFit.contain,
                              errorBuilder: (context, error, stack) =>
                                  Text(config.alt ?? 'Image failed to load'),
                            ),
                          );
                        },
                        builders: const {},
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _KeyHint extends StatelessWidget {
  final String label;
  final String shortcut;
  final Color hintColor;
  const _KeyHint({
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

Future<void> _launch(String href) async {
  final uri = Uri.tryParse(href);
  if (uri == null) return;
  if (await canLaunchUrl(uri)) {
    await launchUrl(
      uri,
      mode: LaunchMode.platformDefault,
      webOnlyWindowName: '_blank',
    );
  }
}
