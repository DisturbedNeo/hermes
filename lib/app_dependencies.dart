import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hermes/core/services/chat/chat_library_service.dart';
import 'package:hermes/core/services/chat/chat_tabs_service.dart';
import 'package:hermes/core/services/chat_library_repository.dart';
import 'package:hermes/core/services/preferences_service.dart';
import 'package:hermes/core/services/project_system/project_service.dart';
import 'package:hermes/core/services/project_system/project_orchestrator.dart';
import 'package:hermes/core/services/planning_runtime.dart';
import 'package:hermes/core/services/planning_structured_output.dart';
import 'package:hermes/core/services/system_prompt_library_repository.dart';
import 'package:hermes/core/services/system_prompt_library_service.dart';
import 'package:hermes/core/services/task_system/task_repository.dart';
import 'package:hermes/core/services/task_system/task_service.dart';
import 'package:hermes/core/services/task_system/task_planning_service.dart';
import 'package:hermes/core/services/task_system/task_orchestrator.dart';
import 'package:hermes/core/services/theme_manager.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/core/services/workspace_sandbox.dart';
import 'package:hermes/core/services/workspace_service.dart';
import 'package:hermes/core/services/workspace_persistence_coordinator.dart';

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
    required this.taskOrchestrator,
    required this.projectService,
    required this.projectOrchestrator,
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
    const planningRunner = PlanningToolCallRunner();
    const structuredOutput = StructuredPlanningOutputService();
    const taskPlanner = TaskPlanningService(runner: planningRunner);
    final persistenceCoordinator = WorkspacePersistenceCoordinator();
    final taskRepository = TaskRepository(coordinator: persistenceCoordinator);
    final taskService = TaskService(
      toolService: toolService,
      sandbox: workspaceSandbox,
      repository: taskRepository,
      planner: taskPlanner,
      structuredOutput: structuredOutput,
    );
    final projectOrchestrator = ProjectOrchestrator(
      taskService: taskService,
      persistenceCoordinator: persistenceCoordinator,
      planningRunner: planningRunner,
      structuredOutput: structuredOutput,
    );
    final taskOrchestrator = TaskOrchestrator(service: taskService);
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
      projectService: projectOrchestrator,
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
      taskOrchestrator: taskOrchestrator,
      projectService: projectOrchestrator,
      projectOrchestrator: projectOrchestrator,
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
  final TaskOrchestrator taskOrchestrator;
  final ProjectService projectService;
  final ProjectOrchestrator projectOrchestrator;
  final ChatLibraryService chatLibraryService;
  final SystemPromptLibraryService systemPromptLibraryService;
  final ChatTabsService chatTabsService;

  bool _disposed = false;
  Future<void>? _disposeFuture;

  /// Disposes owned dependencies once, in reverse construction order.
  Future<void> dispose() => _startDispose(discardChanges: false);

  Future<void> disposeWithoutSaving() => _startDispose(discardChanges: true);

  Future<void> _startDispose({required bool discardChanges}) {
    if (_disposed) return _disposeFuture ?? Future.value();
    final pending = _disposeFuture;
    if (pending != null) return pending;

    late final Future<void> operation;
    operation = _dispose(discardChanges: discardChanges).whenComplete(() {
      if (!_disposed && identical(_disposeFuture, operation)) {
        _disposeFuture = null;
      }
    });
    _disposeFuture = operation;
    return operation;
  }

  Future<void> _dispose({required bool discardChanges}) async {
    if (discardChanges) {
      await _disposeSafely(chatTabsService.disposeWithoutSaving);
    } else {
      // A failed tab preflight must stop disposal before repositories close.
      await chatTabsService.dispose();
    }
    await _disposeSafely(systemPromptLibraryService.dispose);
    await _disposeSafely(chatLibraryService.dispose);
    await _disposeSafely(workspaceService.dispose);
    await _disposeSafely(themeManager.dispose);
    await _disposeSafely(preferencesService.dispose);
    _disposed = true;
  }

  Future<void> _disposeSafely(FutureOr<void> Function() dispose) async {
    try {
      await dispose();
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'hermes application disposal',
          context: ErrorDescription(
            'while disposing an application dependency',
          ),
        ),
      );
    }
  }
}
