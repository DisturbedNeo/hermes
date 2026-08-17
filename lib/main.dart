import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:hermes/app_dependencies.dart';
import 'package:hermes/core/models/chat_persistence.dart';
import 'package:hermes/core/services/chat/chat_library_service.dart';
import 'package:hermes/core/services/chat/chat_tabs_service.dart';
import 'package:hermes/core/services/keyboard_shortcuts.dart';
import 'package:hermes/core/services/preferences_service.dart';
import 'package:hermes/core/services/project_system/project_service.dart';
import 'package:hermes/core/services/system_prompt_library_service.dart';
import 'package:hermes/core/services/task_system/task_service.dart';
import 'package:hermes/core/services/theme_manager.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/core/services/workspace_sandbox.dart';
import 'package:hermes/core/services/workspace_service.dart';
import 'package:hermes/ui/chat/chat.dart';
import 'package:hermes/ui/overlays/keyboard_shortcuts_panel.dart';
import 'package:hermes/ui/routes.dart';
import 'package:provider/provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const App());
}

class App extends StatefulWidget {
  const App({super.key, this.exitApplication, this.prepareForExit});

  final Future<AppExitResponse> Function(AppExitType type)? exitApplication;
  final Future<void> Function(NewChatExitPolicy policy)? prepareForExit;

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final AppDependencies _dependencies;

  @override
  void initState() {
    super.initState();
    _dependencies = AppDependencies.create();
  }

  @override
  void dispose() {
    unawaited(_disposeDependencies());
    super.dispose();
  }

  Future<void> _disposeDependencies() async {
    try {
      await _dependencies.dispose();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'hermes application disposal',
          context: ErrorDescription('while disposing the application'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dependencies = _dependencies;
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<PreferencesService>.value(
          value: dependencies.preferencesService,
        ),
        ChangeNotifierProvider<ThemeManager>.value(
          value: dependencies.themeManager,
        ),
        Provider<WorkspaceSandbox>.value(value: dependencies.workspaceSandbox),
        ChangeNotifierProvider<WorkspaceService>.value(
          value: dependencies.workspaceService,
        ),
        Provider<ToolService>.value(value: dependencies.toolService),
        Provider<TaskService>.value(value: dependencies.taskService),
        Provider<ProjectService>.value(value: dependencies.projectService),
        ChangeNotifierProvider<ChatLibraryService>.value(
          value: dependencies.chatLibraryService,
        ),
        ChangeNotifierProvider<SystemPromptLibraryService>.value(
          value: dependencies.systemPromptLibraryService,
        ),
        ChangeNotifierProvider<ChatTabsService>.value(
          value: dependencies.chatTabsService,
        ),
      ],
      child: Builder(
        builder: (context) => _AppShell(
          themeManager: context.read<ThemeManager>(),
          tabs: context.read<ChatTabsService>(),
          chatLibrary: context.read<ChatLibraryService>(),
          systemPromptLibrary: context.read<SystemPromptLibraryService>(),
          workspaceService: context.read<WorkspaceService>(),
          preferencesService: context.read<PreferencesService>(),
          toolService: context.read<ToolService>(),
          disposeWithoutSavingDependencies: dependencies.disposeWithoutSaving,
          exitApplication:
              widget.exitApplication ?? WidgetsBinding.instance.exitApplication,
          prepareForExit:
              widget.prepareForExit ??
              dependencies.chatTabsService.prepareForExit,
        ),
      ),
    );
  }
}

class _AppShell extends StatefulWidget {
  const _AppShell({
    required this.themeManager,
    required this.tabs,
    required this.chatLibrary,
    required this.systemPromptLibrary,
    required this.workspaceService,
    required this.preferencesService,
    required this.toolService,
    required this.disposeWithoutSavingDependencies,
    required this.exitApplication,
    required this.prepareForExit,
  });

  final ThemeManager themeManager;
  final ChatTabsService tabs;
  final ChatLibraryService chatLibrary;
  final SystemPromptLibraryService systemPromptLibrary;
  final WorkspaceService workspaceService;
  final PreferencesService preferencesService;
  final ToolService toolService;
  final Future<void> Function() disposeWithoutSavingDependencies;
  final Future<AppExitResponse> Function(AppExitType type) exitApplication;
  final Future<void> Function(NewChatExitPolicy policy) prepareForExit;

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> with WidgetsBindingObserver {
  final KeyboardShortcutsService _shortcuts = KeyboardShortcutsService();
  bool _exitCleanupStarted = false;
  bool _exitAfterCleanup = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.themeManager.addListener(_handleThemeChanged);
    _registerAppShortcuts();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.themeManager.removeListener(_handleThemeChanged);
    _shortcuts.dispose();
    super.dispose();
  }

  void _registerAppShortcuts() {
    final tabs = widget.tabs;
    final themeManager = widget.themeManager;

    _shortcuts.register(HermesShortcut.newChat, () => tabs.newTab());
    _shortcuts.register(
      HermesShortcut.saveChat,
      () => unawaited(tabs.saveCurrentChat()),
    );
    _shortcuts.register(
      HermesShortcut.toggleTheme,
      () => unawaited(themeManager.toggleTheme()),
    );
    _shortcuts.register(HermesShortcut.cancelGeneration, () {
      final activeChat = tabs.activeChat;
      if (activeChat == null) return;
      if (activeChat.taskBusy) {
        if (!activeChat.taskCancellationRequested) {
          unawaited(activeChat.cancelTaskRun());
        }
      } else {
        unawaited(activeChat.cancelGeneration());
      }
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
    if (mounted) setState(() {});
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    if (_exitAfterCleanup) return AppExitResponse.exit;
    if (_exitCleanupStarted) return AppExitResponse.cancel;

    _exitCleanupStarted = true;
    Timer.run(() => unawaited(_beginExit()));

    return AppExitResponse.cancel;
  }

  Future<void> _beginExit() async {
    var policy = NewChatExitPolicy.discard;
    if (widget.tabs.tabs.any((tab) => tab.isUnsavedNonEmpty)) {
      final choice = await _showUnsavedChatsDialog();
      if (choice == null || choice == _UnsavedChatsExitAction.cancel) {
        _exitCleanupStarted = false;
        return;
      }
      policy = choice == _UnsavedChatsExitAction.saveAll
          ? NewChatExitPolicy.save
          : NewChatExitPolicy.discard;
    }

    await _prepareAndExit(policy);
  }

  Future<void> _prepareAndExit(NewChatExitPolicy policy) async {
    try {
      await widget.prepareForExit(policy);
    } catch (error) {
      final action = await _showExitFailureDialog(error);
      if (action == _ExitFailureAction.retry) {
        await _prepareAndExit(policy);
        return;
      }
      if (action == _ExitFailureAction.exitWithoutSaving) {
        await _finishExit();
        return;
      }
      _exitCleanupStarted = false;
      return;
    }
    await _finishExit();
  }

  Future<void> _finishExit() async {
    await widget.disposeWithoutSavingDependencies();
    _exitAfterCleanup = true;
    await widget.exitApplication(AppExitType.required);
  }

  BuildContext? get _dialogContext => AppNavigator.navigatorKey.currentContext;

  Future<_UnsavedChatsExitAction?> _showUnsavedChatsDialog() {
    final dialogContext = _dialogContext;
    if (dialogContext == null) return Future.value();
    final count = widget.tabs.tabs.where((tab) => tab.isUnsavedNonEmpty).length;
    return showDialog<_UnsavedChatsExitAction>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Save new chats before exiting?'),
        content: Text(
          count == 1
              ? 'One new chat has not been saved.'
              : '$count new chats have not been saved.',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(context, _UnsavedChatsExitAction.cancel),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, _UnsavedChatsExitAction.discardNew),
            child: const Text('Discard new chats'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, _UnsavedChatsExitAction.saveAll),
            child: const Text('Save all and exit'),
          ),
        ],
      ),
    );
  }

  Future<_ExitFailureAction?> _showExitFailureDialog(Object error) {
    final dialogContext = _dialogContext;
    if (dialogContext == null) return Future.value();
    return showDialog<_ExitFailureAction>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Could not save chats'),
        content: Text('Hermes will stay open so you can retry.\n\n$error'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _ExitFailureAction.cancel),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, _ExitFailureAction.exitWithoutSaving),
            child: const Text('Exit without saving'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _ExitFailureAction.retry),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shortcutKeys = _shortcuts.activeShortcuts;
    return MaterialApp(
      title: 'Hermes',
      theme: widget.themeManager.currentTheme,
      initialRoute: AppRoutes.home,
      onGenerateRoute: (settings) => generateRoute(
        settings,
        homeBuilder: (_) => Chat(
          tabs: widget.tabs,
          chatLibrary: widget.chatLibrary,
          systemPromptLibrary: widget.systemPromptLibrary,
          workspaceService: widget.workspaceService,
          preferencesService: widget.preferencesService,
          toolService: widget.toolService,
        ),
      ),
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

enum _UnsavedChatsExitAction { saveAll, discardNew, cancel }

enum _ExitFailureAction { retry, exitWithoutSaving, cancel }
