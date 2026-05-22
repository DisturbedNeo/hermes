import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:hermes/core/services/chat/chat_tabs_service.dart';
import 'package:hermes/core/services/keyboard_shortcuts.dart';
import 'package:hermes/core/services/service_provider.dart';
import 'package:hermes/core/services/theme_manager.dart';
import 'package:hermes/ui/overlays/keyboard_shortcuts_panel.dart';
import 'package:hermes/ui/routes.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await serviceProvider.initialize();

  runApp(const App());
}

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with WidgetsBindingObserver {
  final ThemeManager _themeManager = serviceProvider.get<ThemeManager>();
  final KeyboardShortcutsService _shortcuts = KeyboardShortcutsService();
  bool _exitCleanupStarted = false;
  bool _exitAfterCleanup = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _themeManager.addListener(_handleThemeChanged);
    _registerAppShortcuts();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _themeManager.removeListener(_handleThemeChanged);
    _shortcuts.dispose();
    super.dispose();
  }

  void _registerAppShortcuts() {
    final tabs = serviceProvider.get<ChatTabsService>();
    final themeMgr = _themeManager;

    // App-level shortcuts that don't depend on widget state
    _shortcuts.register(HermesShortcut.newChat, () => tabs.newTab());
    _shortcuts.register(
      HermesShortcut.saveChat,
      () => unawaited(tabs.saveCurrentChat()),
    );
    _shortcuts.register(
      HermesShortcut.toggleTheme,
      () => unawaited(themeMgr.toggleTheme()),
    );
    _shortcuts.register(HermesShortcut.cancelGeneration, () {
      final activeChat = tabs.activeChat;
      if (activeChat != null) unawaited(activeChat.cancelGeneration());
    });
    _shortcuts.register(HermesShortcut.showShortcuts, _showShortcutsDialog);
  }

  void _showShortcutsDialog() {
    final navigatorContext = AppNavigator.navigatorKey.currentContext;
    if (navigatorContext == null) return;

    showDialog(
      context: navigatorContext,
      builder: (dialogContext) => const KeyboardShortcutsPanel(),
    );
  }

  void _handleThemeChanged() {
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        break;
      case AppLifecycleState.detached:
        break;
      case AppLifecycleState.resumed:
        break;
      case AppLifecycleState.inactive:
        break;
      case AppLifecycleState.hidden:
        break;
    }
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    if (_exitAfterCleanup) return AppExitResponse.exit;
    if (_exitCleanupStarted) return AppExitResponse.cancel;

    _exitCleanupStarted = true;
    Timer.run(() => unawaited(_disposeServicesAndExit()));

    return AppExitResponse.cancel;
  }

  Future<void> _disposeServicesAndExit() async {
    try {
      await serviceProvider.dispose();
    } finally {
      _exitAfterCleanup = true;
      await WidgetsBinding.instance.exitApplication(AppExitType.required);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shortcutKeys = _shortcuts.activeShortcuts;
    return MaterialApp(
      title: 'Codex',
      theme: _themeManager.currentTheme,
      initialRoute: AppRoutes.home,
      onGenerateRoute: generateRoute,
      navigatorKey: AppNavigator.navigatorKey,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return Shortcuts(
          shortcuts: shortcutKeys,
          child: Actions(
            actions: _shortcuts.actions,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}
