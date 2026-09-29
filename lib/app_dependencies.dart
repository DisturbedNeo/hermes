import 'package:hermes/features/chat/runtime/chat_application/chat_library_service.dart';
import 'package:hermes/features/chat/application/chat_workspace_controller.dart';
import 'package:hermes/features/chat/infrastructure/chat_library_repository.dart';
import 'package:hermes/features/settings/infrastructure/preferences_service.dart';
import 'package:hermes/features/project/application/project_application/project_application.dart';
import 'package:hermes/features/project/infrastructure/project_aggregate_repository.dart';
import 'package:hermes/features/project/runtime/project_command_service.dart';
import 'package:hermes/features/project/infrastructure/project_repository.dart';
import 'package:hermes/features/project/runtime/project_state_store.dart';
import 'package:hermes/features/project/runtime/project_recovery_service.dart';
import 'package:hermes/core/services/planning_runtime.dart';
import 'package:hermes/core/services/llama_server_manager.dart';
import 'package:hermes/core/services/planning_structured_output.dart';
import 'package:hermes/features/chat/infrastructure/system_prompt_library_repository.dart';
import 'package:hermes/core/services/system_prompt_library_service.dart';
import 'package:hermes/features/task/infrastructure/task_repository.dart';
import 'package:hermes/features/task/runtime/task_persistence_store.dart';
import 'package:hermes/features/task/runtime/task_planning_coordinator.dart';
import 'package:hermes/features/task/runtime/task_recovery_service.dart';
import 'package:hermes/features/task/runtime/task_model_completion_service.dart';
import 'package:hermes/features/task/application/task_application/task_controller.dart';
import 'package:hermes/features/model/infrastructure/chat_client.dart';
import 'package:hermes/core/models/chat_persistence.dart';
import 'package:hermes/features/task/runtime/task_tool_execution_service.dart';
import 'package:hermes/features/task/runtime/task_planning_service.dart';
import 'package:hermes/core/services/theme_manager.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/core/services/workspace_sandbox.dart';
import 'package:hermes/core/services/workspace_service.dart';
import 'package:hermes/core/services/workspace_persistence_coordinator.dart';
import 'package:hermes/shared_kernel/application_lifecycle.dart';

/// The eagerly-created, application-scoped dependency graph.
///
/// This class owns service lifetimes but intentionally has no type-based lookup
/// API. Dependencies are exposed as typed fields and injected explicitly.
class AppDependencies implements ApplicationLifecycle {
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
    required this.lifecycleCoordinator,
  });

  factory AppDependencies.create() {
    final preferencesService = PreferencesService();
    final workspaceSandbox = WorkspaceSandbox();
    final themeManager = ThemeManager(preferencesService: preferencesService);
    final workspaceService = WorkspaceService(sandbox: workspaceSandbox);
    final toolService = ToolService(workspaceSandbox: workspaceSandbox);
    final modelManager = LlamaServerManager(
      clientFactory: ({required baseUrl, required model, onDiagnostics}) =>
          ChatClient(
            baseUrl: baseUrl,
            model: model,
            onDiagnostics: onDiagnostics,
          ),
    );
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
    final lifecycleCoordinator = ApplicationLifecycleCoordinator();
    lifecycleCoordinator.register(
      name: 'preferences',
      dispose: preferencesService.dispose,
    );
    lifecycleCoordinator.register(name: 'theme', dispose: themeManager.dispose);
    lifecycleCoordinator.register(
      name: 'workspace',
      dispose: workspaceService.dispose,
    );
    lifecycleCoordinator.register(
      name: 'chat library',
      dispose: chatLibraryService.dispose,
    );
    lifecycleCoordinator.register(
      name: 'system prompt library',
      dispose: systemPromptLibraryService.dispose,
    );
    lifecycleCoordinator.register(
      name: 'chat workspace',
      quiesce: () =>
          chatWorkspaceController.prepareForExit(NewChatExitPolicy.discard),
      flush: () =>
          chatWorkspaceController.prepareForExit(NewChatExitPolicy.save),
      dispose: chatWorkspaceController.dispose,
      disposeWithoutSaving: chatWorkspaceController.disposeWithoutSaving,
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
      lifecycleCoordinator: lifecycleCoordinator,
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
  final ApplicationLifecycleCoordinator lifecycleCoordinator;

  @override
  ApplicationLifecycleState get lifecycleState =>
      lifecycleCoordinator.lifecycleState;

  @override
  Future<void> start() => lifecycleCoordinator.start();

  @override
  Future<void> quiesce() => lifecycleCoordinator.quiesce();

  @override
  Future<void> flush() => lifecycleCoordinator.flush();

  /// Disposes owned dependencies once, in reverse construction order.
  Future<void> dispose() => lifecycleCoordinator.dispose();

  Future<void> disposeWithoutSaving() =>
      lifecycleCoordinator.disposeWithoutSaving();
}
