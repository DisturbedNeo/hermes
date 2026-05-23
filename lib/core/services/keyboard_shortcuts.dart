import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Represents a registered keyboard shortcut in the Hermes application.
enum HermesShortcut {
  newChat(label: 'N', description: 'Create a new chat'),
  closeChat(label: 'W', description: 'Close current chat'),
  saveChat(label: 'S', description: 'Save current chat'),
  openSettings(label: ',', description: 'Open settings panel'),
  toggleTheme(label: 'T', description: 'Toggle dark/light mode'),
  focusComposer(label: '/', description: 'Focus the message composer'),
  cancelGeneration(label: 'Esc', description: 'Cancel streaming/generation'),
  openChatList(label: 'O', description: 'Open chat list panel'),
  toggleJobPanel(label: 'J', description: 'Toggle job panel visibility'),
  showShortcuts(label: '?', description: 'Show keyboard shortcuts help');

  final String label;
  final String description;

  const HermesShortcut({required this.label, required this.description});

  LogicalKeyboardKey get key => switch (this) {
    newChat => LogicalKeyboardKey.keyN,
    closeChat => LogicalKeyboardKey.keyW,
    saveChat => LogicalKeyboardKey.keyS,
    openSettings => LogicalKeyboardKey.comma,
    toggleTheme => LogicalKeyboardKey.keyT,
    focusComposer => LogicalKeyboardKey.slash,
    cancelGeneration => LogicalKeyboardKey.escape,
    openChatList => LogicalKeyboardKey.keyO,
    toggleJobPanel => LogicalKeyboardKey.keyJ,
    showShortcuts => LogicalKeyboardKey.question,
  };

  bool get isMeta => switch (this) {
    cancelGeneration => true,
    _ => false,
  };

  ShortcutActivator get activator => switch (this) {
    cancelGeneration => const SingleActivator(LogicalKeyboardKey.escape),
    showShortcuts => const SingleActivator(
      LogicalKeyboardKey.slash,
      control: true,
      shift: true,
    ),
    _ => SingleActivator(key, control: true),
  };

  Iterable<ShortcutActivator> get activators => switch (this) {
    showShortcuts => const [
      SingleActivator(LogicalKeyboardKey.slash, control: true, shift: true),
      SingleActivator(LogicalKeyboardKey.question, control: true, shift: true),
      SingleActivator(LogicalKeyboardKey.question, control: true),
    ],
    _ => [activator],
  };
}

/// Intent dispatched by the Flutter shortcuts system for a Hermes shortcut.
class HermesShortcutIntent extends Intent {
  final HermesShortcut shortcut;

  const HermesShortcutIntent(this.shortcut);
}

/// Service that manages global keyboard shortcuts for the Hermes application.
///
/// Uses Flutter's [Shortcuts] and [Actions] widget tree integration to handle
/// key events across the entire app. Shortcuts are registered per-widget-tree
/// scope and dispatched via the action system.
class KeyboardShortcutsService extends ChangeNotifier {
  final Map<HermesShortcut, VoidCallback> _handlers = {};

  /// Registers a handler for the given shortcut.
  void register(HermesShortcut shortcut, VoidCallback handler) {
    _handlers[shortcut] = handler;
    notifyListeners();
  }

  /// Unregisters a previously registered shortcut handler.
  void unregister(HermesShortcut shortcut) {
    _handlers.remove(shortcut);
    notifyListeners();
  }

  /// Returns the set of currently registered shortcut activators for use with
  /// [Shortcuts] widget mapping.
  Map<ShortcutActivator, Intent> get activeShortcuts {
    final result = <ShortcutActivator, Intent>{};
    for (final entry in _handlers.entries) {
      final shortcut = entry.key;
      for (final activator in shortcut.activators) {
        result[activator] = HermesShortcutIntent(shortcut);
      }
    }
    return result;
  }

  /// Returns the set of [CallbackAction] instances for use with the [Actions]
  /// widget. Each action maps a [HermesShortcut] enum value to its handler.
  Map<Type, Action<Intent>> get actions {
    return actionsWithFallback();
  }

  /// Returns actions that fall back to the next ancestor [Actions] scope when
  /// this service has no handler for a dispatched shortcut.
  Map<Type, Action<Intent>> actionsWithFallback([
    BuildContext? fallbackContext,
  ]) {
    return <Type, Action<Intent>>{
      HermesShortcutIntent: _HermesShortcutAction(
        this,
        fallbackContext: fallbackContext,
      ),
    };
  }

  /// Checks whether any registered shortcut is currently active.
  bool get hasActiveShortcuts => _handlers.isNotEmpty;

  bool _canHandle(HermesShortcut shortcut) => _handlers.containsKey(shortcut);

  bool _invoke(HermesShortcut shortcut) {
    final handler = _handlers[shortcut];
    if (handler == null) return false;
    handler();
    return true;
  }
}

class _HermesShortcutAction extends ContextAction<HermesShortcutIntent> {
  final KeyboardShortcutsService service;
  final BuildContext? fallbackContext;

  _HermesShortcutAction(this.service, {this.fallbackContext});

  @override
  bool isEnabled(HermesShortcutIntent intent, [BuildContext? context]) {
    if (service._canHandle(intent.shortcut)) return true;
    return _hasFallback(intent);
  }

  @override
  Object? invoke(HermesShortcutIntent intent, [BuildContext? context]) {
    // Try the service's own handler first.
    if (service._invoke(intent.shortcut)) return true;

    // Fall back to the next ancestor Actions scope.
    return _tryFallback(intent);
  }

  /// Returns whether there is a usable fallback action in an ancestor scope.
  bool _hasFallback(HermesShortcutIntent intent) {
    final fallbackContext = this.fallbackContext;
    if (fallbackContext == null) return false;

    final action = Actions.maybeFind<HermesShortcutIntent>(
      fallbackContext,
      intent: intent,
    );
    return action != null && !identical(action, this);
  }

  /// Attempts to dispatch the intent to a fallback action in an ancestor scope.
  ///
  /// Returns `true` if a fallback was found and invoked successfully,
  /// `false` otherwise.
  Object? _tryFallback(HermesShortcutIntent intent) {
    final fallbackContext = this.fallbackContext;
    if (fallbackContext == null) return false;

    final action = Actions.maybeFind<HermesShortcutIntent>(
      fallbackContext,
      intent: intent,
    );
    if (action == null || identical(action, this)) return false;

    final (enabled, _) = Actions.of(fallbackContext)
        .invokeActionIfEnabled(action, intent, fallbackContext);
    return enabled;
  }

  @override
  KeyEventResult toKeyEventResult(
    HermesShortcutIntent intent,
    Object? invokeResult,
  ) {
    return invokeResult == true
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }
}
