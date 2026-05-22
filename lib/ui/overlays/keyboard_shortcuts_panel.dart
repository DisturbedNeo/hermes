import 'package:flutter/material.dart';

/// A dialog overlay that displays all available keyboard shortcuts.
class KeyboardShortcutsPanel extends StatelessWidget {
  const KeyboardShortcutsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Keyboard Shortcuts'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(theme.textTheme, 'Navigation'),
            _shortcutRow(context, 'New chat', 'Ctrl+N'),
            _shortcutRow(context, 'Open chat list', 'Ctrl+O'),
            _shortcutRow(context, 'Toggle job panel', 'Ctrl+J'),
            const SizedBox(height: 12),
            _sectionHeader(theme.textTheme, 'Actions'),
            _shortcutRow(context, 'Save chat', 'Ctrl+S'),
            _shortcutRow(context, 'Focus composer', 'Ctrl+/'),
            _shortcutRow(context, 'Cancel generation', 'Esc'),
            const SizedBox(height: 12),
            _sectionHeader(theme.textTheme, 'Settings'),
            _shortcutRow(context, 'Open settings', 'Ctrl+,'),
            _shortcutRow(context, 'Toggle theme', 'Ctrl+T'),
            _shortcutRow(context, 'Show shortcuts help', 'Ctrl+?'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _sectionHeader(TextTheme theme, String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        label,
        style: theme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _shortcutRow(BuildContext context, String action, String shortcut) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(action, style: Theme.of(context).textTheme.bodyMedium),
          _keyBadge(shortcut),
        ],
      ),
    );
  }

  static Widget _keyBadge(String key) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.grey.shade400),
      ),
      child: Text(
        key,
        style: const TextStyle(
          fontSize: 12,
          fontFamily: 'monospace',
          color: Colors.black87,
        ),
      ),
    );
  }
}
