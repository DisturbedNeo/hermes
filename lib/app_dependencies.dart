import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hermes/features/chat/application/chat_application/chat_library_service.dart';
import 'package:hermes/features/chat/application/chat_workspace_controller.dart';
import 'package:hermes/core/services/chat_library_repository.dart';
import 'package:hermes/core/services/preferences_service.dart';
import 'package:hermes/features/project/application/project_application/project_application.dart';
import 'package:hermes/features/project/application/project_application/project_aggregate_repository.dart';
import 'package:hermes/features/project/application/project_application/project_command_service.dart';
import 'package:hermes/features/project/application/project_application/project_repository.dart';
import 'package:hermes/features/project/application/project_application/project_state_store.dart';
import 'package:hermes/features/project/application/project_application/project_recovery_service.dart';
import 'package:hermes/core/services/planning_runtime.dart';
import 'package:hermes/core/services/llama_server_manager.dart';
import 'package:hermes/core/services/planning_structured_output.dart';
import 'package:hermes/core/services/system_prompt_library_repository.dart';
import 'package:hermes/core/services/system_prompt_library_service.dart';
import 'package:hermes/features/task/application/task_application/task_repository.dart';
import 'package:hermes/features/task/application/task_application/task_persistence_store.dart';
import 'package:hermes/features/task/application/task_application/task_planning_coordinator.dart';
import 'package:hermes/features/task/application/task_application/task_recovery_service.dart';
import 'package:hermes/features/task/application/task_application/task_model_completion_service.dart';
import 'package:hermes/features/task/application/task_application/task_controller.dart';
import 'package:hermes/features/task/application/task_application/task_tool_execution_service.dart';
import 'package:hermes/features/task/application/task_application/task_planning_service.dart';
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
    required this.modelManager,
    required this.taskController,
    required this.projectApplication,
    required this.chatLibraryService,
    required this.systemPromptLibraryService,
    required this.chatWorkspaceController,
  });

  factory AppDependencies.create() {
    final preferencesService = PreferencesService();
    final workspaceSandbox = WorkspaceSandbox();
    final themeManager = ThemeManager(preferencesService: preferencesService);
    final workspaceService = WorkspaceService(sandbox: workspaceSandbox);
    final toolService = ToolService(workspaceSandbox: workspaceSandbox);
    final modelManager = LlamaServerManager();
    const planningRunner = PlanningToolCallRunner();
    const structuredOutput = StructuredPlanningOutputService();
    const taskPlanner = TaskPlanningService(runner: planningRunner);
    const taskPlanningCoordinator = TaskPlanningCoordinator(
      planner: taskPlanner,
    );
    const taskRecoveryService = TaskRecoveryService();
    final taskModelCompletion = TaskModelCompletionService(
      structuredOutput: structuredOutput,
    );
    final taskToolExecution = TaskToolExecutionService(
      toolService: toolService,
      sandbox: workspaceSandbox,
    );
    final persistenceCoordinator = WorkspacePersistenceCoordinator();
    final taskRepository = TaskRepository(coordinator: persistenceCoordinator);
    final taskPersistenceStore = TaskPersistenceStore(
      repository: taskRepository,
    );
    final taskController = TaskController(
      toolService: toolService,
      sandbox: workspaceSandbox,
      persistenceStore: taskPersistenceStore,
      planningCoordinator: taskPlanningCoordinator,
      recoveryService: taskRecoveryService,
      modelCompletion: taskModelCompletion,
      toolExecution: taskToolExecution,
      structuredOutput: structuredOutput,
    );
    final projectRepository = ProjectRepository(
      coordinator: persistenceCoordinator,
    );
    final projectAggregateRepository = ProjectAggregateRepository(
      projectRepository: projectRepository,
      taskRepository: taskRepository,
      coordinator: persistenceCoordinator,
    );
    final projectStateStore = ProjectStateStore(
      projectRepository: projectRepository,
      aggregateRepository: projectAggregateRepository,
      taskController: taskController,
    );
    final projectCommandService = ProjectCommandService(
      stateStore: projectStateStore,
      persistenceCoordinator: persistenceCoordinator,
    );
    final projectApplication = ProjectApplication(
      taskController: taskController,
      repository: projectRepository,
      aggregateRepository: projectAggregateRepository,
      stateStore: projectStateStore,
      commandService: projectCommandService,
      recoveryService: const ProjectRecoveryService(),
      persistenceCoordinator: persistenceCoordinator,
      planningRunner: planningRunner,
      structuredOutput: structuredOutput,
    );
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
    final chatWorkspaceController = ChatWorkspaceController(
      serverManager: modelManager,
      chatLibrary: chatLibraryService,
      systemPromptLibrary: systemPromptLibraryService,
      toolService: toolService,
      taskController: taskController,
      projectApplication: projectApplication,
      workspaceService: workspaceService,
      preferencesService: preferencesService,
    );

    return AppDependencies._(
      preferencesService: preferencesService,
      themeManager: themeManager,
      workspaceSandbox: workspaceSandbox,
      workspaceService: workspaceService,
      toolService: toolService,
      modelManager: modelManager,
      taskController: taskController,
      projectApplication: projectApplication,
      chatLibraryService: chatLibraryService,
      systemPromptLibraryService: systemPromptLibraryService,
      chatWorkspaceController: chatWorkspaceController,
    );
  }

  final PreferencesService preferencesService;
  final ThemeManager themeManager;
  final WorkspaceSandbox workspaceSandbox;
  final WorkspaceService workspaceService;
  final ToolService toolService;
  final LlamaServerManager modelManager;
  final TaskController taskController;
  final ProjectApplication projectApplication;
  final ChatLibraryService chatLibraryService;
  final SystemPromptLibraryService systemPromptLibraryService;
  final ChatWorkspaceController chatWorkspaceController;

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
      await _disposeSafely(chatWorkspaceController.disposeWithoutSaving);
    } else {
      // A failed tab preflight must stop disposal before repositories close.
      await chatWorkspaceController.dispose();
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
