import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/services/keyboard_shortcuts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('nested shortcut scopes fall back to parent handlers', (
    tester,
  ) async {
    final root = KeyboardShortcutsService();
    final panel = KeyboardShortcutsService();
    final composer = KeyboardShortcutsService();
    addTearDown(root.dispose);
    addTearDown(panel.dispose);
    addTearDown(composer.dispose);

    var themeToggles = 0;
    var newChats = 0;
    var closedChats = 0;
    var openedPanels = 0;
    var focusedComposer = 0;
    var shortcutHelp = 0;

    root
      ..register(HermesShortcut.toggleTheme, () => themeToggles++)
      ..register(HermesShortcut.newChat, () => newChats++)
      ..register(HermesShortcut.showShortcuts, () => shortcutHelp++);
    panel
      ..register(HermesShortcut.closeChat, () => closedChats++)
      ..register(HermesShortcut.openChatList, () => openedPanels++);
    composer.register(HermesShortcut.focusComposer, () => focusedComposer++);

    await tester.pumpWidget(
      MaterialApp(
        home: _ShortcutScope(
          service: root,
          child: _ShortcutScope(
            service: panel,
            fallback: true,
            child: _ShortcutScope(
              service: composer,
              fallback: true,
              child: const Focus(autofocus: true, child: SizedBox()),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await _sendShortcut(tester, LogicalKeyboardKey.slash, control: true);
    await _sendShortcut(tester, LogicalKeyboardKey.keyO, control: true);
    await _sendShortcut(tester, LogicalKeyboardKey.keyW, control: true);
    await _sendShortcut(tester, LogicalKeyboardKey.keyT, control: true);
    await _sendShortcut(tester, LogicalKeyboardKey.keyN, control: true);
    await _sendShortcut(
      tester,
      LogicalKeyboardKey.slash,
      control: true,
      shift: true,
    );

    expect(focusedComposer, 1);
    expect(openedPanels, 1);
    expect(closedChats, 1);
    expect(themeToggles, 1);
    expect(newChats, 1);
    expect(shortcutHelp, 1);
  });
}

class _ShortcutScope extends StatelessWidget {
  final KeyboardShortcutsService service;
  final Widget child;
  final bool fallback;

  const _ShortcutScope({
    required this.service,
    required this.child,
    this.fallback = false,
  });

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) {
        return Shortcuts(
          shortcuts: service.activeShortcuts,
          child: Actions(
            actions: fallback
                ? service.actionsWithFallback(context)
                : service.actions,
            child: child,
          ),
        );
      },
    );
  }
}

Future<void> _sendShortcut(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool control = false,
  bool shift = false,
}) async {
  if (control) await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);

  await tester.sendKeyEvent(key);

  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  if (control) await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
}
