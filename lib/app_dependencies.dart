import 'dart:convert';

import 'package:hermes/features/chat/application/chat_library_service.dart';
import 'package:hermes/features/chat/application/chat_workspace_controller.dart';
import 'package:hermes/features/chat/infrastructure/chat_library_repository.dart';
import 'package:hermes/features/settings/infrastructure/preferences_service.dart';
import 'package:hermes/features/project/application/project_application/project_application.dart';
import 'package:hermes/features/project/infrastructure/project_aggregate_repository.dart';
import 'package:hermes/features/project/runtime/project_command_service.dart';
import 'package:hermes/features/project/runtime/project_runtime_collaborators.dart';
import 'package:hermes/features/project/infrastructure/project_repository.dart';
import 'package:hermes/features/project/runtime/project_recovery_service.dart';
import 'package:hermes/features/project/runtime/project_aggregate_hydrator.dart';
import 'package:hermes/features/project/runtime/project_model_calls.dart';
import 'package:hermes/features/project/runtime/project_memory_service.dart';
import 'package:hermes/features/project/runtime/project_progress_monitor.dart';
import 'package:hermes/features/project/runtime/project_planning_coordinator.dart';
import 'package:hermes/features/project/runtime/project_plan_revision_service.dart';
import 'package:hermes/features/project/runtime/project_handlers.dart';
import 'package:hermes/features/project/runtime/project_discovery_service.dart';
import 'package:hermes/features/project/runtime/project_aggregate_store.dart';
import 'package:hermes/features/project/runtime/project_criterion_evaluator.dart';
import 'package:hermes/features/project/runtime/project_evidence_service.dart';
import 'package:hermes/features/project/runtime/project_decision_engine.dart';
import 'package:hermes/features/project/runtime/project_completion_service.dart';
import 'package:hermes/features/project/runtime/project_lifecycle_service.dart';
import 'package:hermes/features/project/domain/project_control_state_service.dart';
import 'package:hermes/features/project/domain/project_scheduler.dart';
import 'package:hermes/features/task/domain/task_lifecycle_service.dart';
import 'package:hermes/shared_kernel/planning_runtime.dart';
import 'package:hermes/features/model/infrastructure/llama_server_manager.dart';
import 'package:hermes/shared_kernel/planning_structured_output.dart';
import 'package:hermes/features/chat/infrastructure/system_prompt_library_repository.dart';
import 'package:hermes/features/chat/application/system_prompt_library_service.dart';
import 'package:hermes/features/task/infrastructure/task_repository.dart';
import 'package:hermes/features/task/runtime/task_persistence_store.dart';
import 'package:hermes/features/task/runtime/task_planning_coordinator.dart';
import 'package:hermes/features/task/runtime/task_recovery_service.dart';
import 'package:hermes/features/task/runtime/task_model_completion_service.dart';
import 'package:hermes/features/task/application/task_application/task_controller.dart';
import 'package:hermes/features/model/infrastructure/chat_client.dart';
import 'package:hermes/shared_kernel/chat_persistence.dart';
import 'package:hermes/features/task/runtime/task_tool_execution_service.dart';
import 'package:hermes/features/task/runtime/task_planning_service.dart';
import 'package:hermes/features/task/runtime/task_runtime_collaborators.dart';
import 'package:hermes/features/task/runtime/task_command_service.dart';
import 'package:hermes/features/task/runtime/task_step_runner.dart';
import 'package:hermes/features/task/runtime/task_gate_evaluator.dart';
import 'package:hermes/features/task/runtime/task_view_service.dart';
import 'package:hermes/features/task/application/task_application/task_plan_materializer.dart';
import 'package:hermes/features/chat/presentation/theme_manager.dart';
import 'package:hermes/platform/tool_service.dart';
import 'package:hermes/platform/workspace_sandbox.dart';
import 'package:hermes/platform/workspace_service.dart';
import 'package:hermes/shared_kernel/workspace_persistence_coordinator.dart';
import 'package:hermes/shared_kernel/application_lifecycle.dart';
import 'package:hermes/shared_kernel/model_json.dart';
import 'package:hermes/shared_kernel/question_policy_service.dart';
import 'package:hermes/shared_kernel/workspace_discovery_service.dart';
import 'package:hermes/app/mappers.init.dart';

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
    ModelJson.configureMapperInitialization(initializeMappers);
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
    const taskMaterializer = TaskPlanMaterializer();
    final taskPersistenceStore = TaskPersistenceStore(
      persistence: taskRepository,
    );
    final taskDependencies = TaskRuntimeDependencies(
      toolService: toolService,
      sandbox: workspaceSandbox,
      planningCoordinator: taskPlanningCoordinator,
      persistenceStore: taskPersistenceStore,
      profileService: const WorkspaceDiscoveryProfileService(),
      gateEvaluator: TaskGateEvaluator(sandbox: workspaceSandbox),
      recoveryService: taskRecoveryService,
      modelCompletion: taskModelCompletion,
      toolExecution: taskToolExecution,
      commandService: TaskCommandService(persistence: taskPersistenceStore),
      stepRunner: TaskStepRunner(
        persistence: taskPersistenceStore,
        recovery: taskRecoveryService,
      ),
      taskViewService: const TaskViewService(),
      questionPolicy: const QuestionPolicyService(),
      encoder: const JsonEncoder.withIndent('  '),
    );
    final taskController = TaskController(dependencies: taskDependencies);
    final projectRepository = ProjectRepository(
      coordinator: persistenceCoordinator,
    );
    final projectAggregateRepository = ProjectAggregateRepository(
      projectRepository: projectRepository,
      taskRepository: taskRepository,
      coordinator: persistenceCoordinator,
    );
    final projectStateStore = ProjectAggregateHydrator(
      projectRepository: projectRepository,
      aggregateRepository: projectAggregateRepository,
      taskQueries: taskController,
    );
    final projectCommandService = ProjectCommandService(
      stateStore: projectStateStore,
      persistenceCoordinator: persistenceCoordinator,
    );
    const projectScheduler = ProjectScheduler();
    const projectMemoryService = ProjectMemoryService();
    const projectProgressMonitor = ProjectProgressMonitor();
    const projectLifecycle = ProjectLifecycleService();
    const taskLifecycle = TaskLifecycleService();
    final projectModelCalls = ProjectModelCalls(
      sandbox: workspaceSandbox,
      planningRunner: planningRunner,
      structuredOutput: structuredOutput,
    );
    final projectAggregateStore = ProjectAggregateStore(
      aggregateRepository: projectAggregateRepository,
      taskRepository: taskRepository,
      materializer: taskMaterializer,
    );
    const projectControlState = ProjectControlStateService();
    final projectPersistenceHandler = ProjectPersistenceHandler(
      aggregateStore: projectAggregateStore,
      scheduler: projectScheduler,
      controlState: projectControlState,
    );
    final projectDiscoveryService = ProjectDiscoveryService(
      taskController: taskController,
      memoryService: projectMemoryService,
    );
    final projectPlanningHandler = ProjectPlanningHandler(
      coordinator: ProjectPlanningCoordinator(
        discovery: projectDiscoveryService,
        planner: projectModelCalls,
      ),
      revisionService: const ProjectPlanRevisionService(),
    );
    final projectDependencies = ProjectRuntimeDependencies(
      planner: projectModelCalls,
      completionEvaluator: projectModelCalls,
      scheduler: projectScheduler,
      memoryService: projectMemoryService,
      progressMonitor: projectProgressMonitor,
      persistenceCoordinator: persistenceCoordinator,
      aggregateStore: projectAggregateStore,
      persistenceHandler: projectPersistenceHandler,
      stateStore: projectStateStore,
      commandService: projectCommandService,
      questionPolicy: const QuestionPolicyService(),
      evidenceService: const ProjectEvidenceService(),
      criterionEvaluator: const ProjectCriterionEvaluator(),
      discoveryService: projectDiscoveryService,
      planningHandler: projectPlanningHandler,
      decisionEngine: const ProjectDecisionEngine(),
      controlStateService: projectControlState,
      lifecycleService: projectLifecycle,
      taskLifecycleService: taskLifecycle,
      completionService: ProjectCompletionService(lifecycle: projectLifecycle),
      recoveryHandler: ProjectRecoveryHandler(const ProjectRecoveryService()),
      encoder: const JsonEncoder.withIndent('  '),
    );
    final projectApplication = ProjectApplication(
      taskQueries: taskController,
      taskPlanning: taskController,
      taskProjectPlanning: taskController,
      taskExecution: taskController,
      taskRecovery: taskController,
      taskPersistence: taskRepository,
      toolService: toolService,
      materializer: taskMaterializer,
      repository: projectRepository,
      aggregateRepository: projectAggregateRepository,
      dependencies: projectDependencies,
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
      taskQueries: taskController,
      taskSessions: taskController,
      taskPresentation: taskController,
      taskPlanning: taskController,
      taskExecution: taskController,
      taskRecovery: taskController,
      projectQueries: projectApplication,
      projectSessions: projectApplication,
      projectPlanning: projectApplication,
      projectCommands: projectApplication,
      projectExecution: projectApplication,
      projectRecovery: projectApplication,
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
    lifecycleCoordinator.register(name: 'model', dispose: modelManager.dispose);
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
