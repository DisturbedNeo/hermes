import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hermes/core/services/chat/chat_library_service.dart';
import 'package:hermes/core/services/chat/chat_tabs_service.dart';
import 'package:hermes/core/services/chat_library_repository.dart';
import 'package:hermes/core/services/preferences_service.dart';
import 'package:hermes/core/services/project_system/project_service.dart';
import 'package:hermes/core/services/system_prompt_library_repository.dart';
import 'package:hermes/core/services/system_prompt_library_service.dart';
import 'package:hermes/core/services/task_system/task_repository.dart';
import 'package:hermes/core/services/task_system/task_service.dart';
import 'package:hermes/core/services/theme_manager.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/core/services/workspace_sandbox.dart';
import 'package:hermes/core/services/workspace_service.dart';

/// The eagerly-created, application-scoped dependency graph.
///
/// This class owns service lifetimes but intentionally has no type-based lookup
/// API. Dependencies are exposed as typed fields and injected explicitly.
class AppDependencies {
  AppDependencies._({
    required this.preferencesService,
    required this.themeManager,
    required this.workspaceSandbox,
    required this.workspaceService,
    required this.toolService,
    required this.taskService,
    required this.projectService,
    required this.chatLibraryService,
    required this.systemPromptLibraryService,
    required this.chatTabsService,
  });

  factory AppDependencies.create() {
    final preferencesService = PreferencesService();
    final workspaceSandbox = WorkspaceSandbox();
    final themeManager = ThemeManager(preferencesService: preferencesService);
    final workspaceService = WorkspaceService(sandbox: workspaceSandbox);
    final toolService = ToolService(workspaceSandbox: workspaceSandbox);
    final taskRepository = TaskRepository();
    final taskService = TaskService(
      toolService: toolService,
      sandbox: workspaceSandbox,
      repository: taskRepository,
    );
    final projectService = ProjectService(taskService: taskService);
    final chatLibraryRepository = ChatLibraryRepository(
      preferencesService: preferencesService,
    );
    final chatLibraryService = ChatLibraryService(
      repository: chatLibraryRepository,
    );
    final systemPromptLibraryRepository = SystemPromptLibraryRepository(
      preferencesService: preferencesService,
    );
    final systemPromptLibraryService = SystemPromptLibraryService(
      repository: systemPromptLibraryRepository,
    );
    final chatTabsService = ChatTabsService(
      chatLibrary: chatLibraryService,
      systemPromptLibrary: systemPromptLibraryService,
      toolService: toolService,
      taskService: taskService,
      projectService: projectService,
      workspaceService: workspaceService,
      preferencesService: preferencesService,
    );

    return AppDependencies._(
      preferencesService: preferencesService,
      themeManager: themeManager,
      workspaceSandbox: workspaceSandbox,
      workspaceService: workspaceService,
      toolService: toolService,
      taskService: taskService,
      projectService: projectService,
      chatLibraryService: chatLibraryService,
      systemPromptLibraryService: systemPromptLibraryService,
      chatTabsService: chatTabsService,
    );
  }

  final PreferencesService preferencesService;
  final ThemeManager themeManager;
  final WorkspaceSandbox workspaceSandbox;
  final WorkspaceService workspaceService;
  final ToolService toolService;
  final TaskService taskService;
  final ProjectService projectService;
  final ChatLibraryService chatLibraryService;
  final SystemPromptLibraryService systemPromptLibraryService;
  final ChatTabsService chatTabsService;

  Future<void>? _disposeFuture;

  /// Disposes owned dependencies once, in reverse construction order.
  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    await _disposeSafely(chatTabsService.dispose);
    await _disposeSafely(systemPromptLibraryService.dispose);
    await _disposeSafely(chatLibraryService.dispose);
    await _disposeSafely(workspaceService.dispose);
    await _disposeSafely(themeManager.dispose);
    await _disposeSafely(preferencesService.dispose);
  }

  Future<void> _disposeSafely(FutureOr<void> Function() dispose) async {
    try {
      await dispose();
    } catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('Failed to dispose an application dependency: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }
  }
}
