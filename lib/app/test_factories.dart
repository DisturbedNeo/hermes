import 'dart:convert';

import 'package:hermes/features/project/application/project_application/project_application.dart';
import 'package:hermes/features/project/project_aggregate_repository_port.dart';
import 'package:hermes/features/project/runtime/project_command_service.dart';
import 'package:hermes/features/project/runtime/project_completion_service.dart';
import 'package:hermes/features/project/runtime/project_lifecycle_service.dart';
import 'package:hermes/features/project/runtime/project_memory_service.dart';
import 'package:hermes/features/project/runtime/project_progress_monitor.dart';
import 'package:hermes/features/project/runtime/project_recovery_service.dart';
import 'package:hermes/features/project/application/project_application/project_workflow_port.dart';
import 'package:hermes/features/project/runtime/project_workflow_adapter.dart';
import 'package:hermes/features/project/runtime/project_execution_state_machine.dart';
import 'package:hermes/features/project/runtime/project_model_calls.dart';
import 'package:hermes/features/project/runtime/project_discovery_service.dart';
import 'package:hermes/features/project/runtime/project_plan_revision_service.dart';
import 'package:hermes/features/project/runtime/project_handlers.dart';
import 'package:hermes/features/project/runtime/project_aggregate_store.dart';
import 'package:hermes/features/project/runtime/project_aggregate_hydrator.dart';
import 'package:hermes/features/project/runtime/project_criterion_evaluator.dart';
import 'package:hermes/features/project/runtime/project_evidence_service.dart';
import 'package:hermes/features/project/runtime/project_decision_engine.dart';
import 'package:hermes/features/project/domain/project_scheduler.dart';
import 'package:hermes/features/project/domain/project_control_state_service.dart';
import 'package:hermes/features/task/application/task_application/task_controller.dart';
import 'package:hermes/features/task/application/task_application/task_persistence_ports.dart';
import 'package:hermes/features/task/application/task_application/task_plan_materializer.dart';
import 'package:hermes/features/task/infrastructure/task_repository.dart';
import 'package:hermes/features/task/domain/task_lifecycle_service.dart';
import 'package:hermes/features/task/runtime/task_persistence_store.dart';
import 'package:hermes/features/task/runtime/task_recovery_service.dart';
import 'package:hermes/features/task/runtime/task_planning_service.dart';
import 'package:hermes/features/task/runtime/task_planning_coordinator.dart';
import 'package:hermes/features/task/runtime/task_tool_execution_service.dart';
import 'package:hermes/features/task/runtime/task_model_completion_service.dart';
import 'package:hermes/features/task/application/task_application/task_workflow_port.dart';
import 'package:hermes/features/task/runtime/task_workflow_adapter.dart';
import 'package:hermes/features/task/runtime/task_execution_coordinator.dart';
import 'package:hermes/features/task/runtime/task_command_service.dart';
import 'package:hermes/features/task/runtime/task_step_runner.dart';
import 'package:hermes/features/task/runtime/task_gate_evaluator.dart';
import 'package:hermes/features/task/runtime/task_view_service.dart';
import 'package:hermes/features/project/infrastructure/project_aggregate_repository.dart';
import 'package:hermes/features/project/infrastructure/project_repository.dart';
import 'package:hermes/features/task/application/protocol/planning_runtime.dart';
import 'package:hermes/features/task/application/protocol/planning_structured_output.dart';
import 'package:hermes/features/tools/application/tool_contracts.dart';
import 'package:hermes/features/workspace/infrastructure/workspace_discovery_service.dart';
import 'package:hermes/features/workspace/application/workspace_discovery.dart';
import 'package:hermes/features/workspace/application/workspace_ports.dart';
import 'package:hermes/features/workspace/infrastructure/workspace_change_discovery_service.dart';
import 'package:hermes/platform/yaml_document_validator.dart';
import 'package:hermes/features/task/application/contracts/question_policy_service.dart';
import 'package:hermes/platform/tool_service.dart';
import 'package:hermes/features/tools/application/tool_protocol_adapter.dart';
import 'package:hermes/platform/workspace_sandbox.dart';
import 'package:hermes/app/modules/persistence_module.dart';
import 'package:hermes/features/persistence/application/task_snapshot_store_port.dart';
import 'package:hermes/features/persistence/application/project_snapshot_store_port.dart';

/// Explicit construction helpers for tests that need lightweight adapters.
/// Production composition is kept in [AppDependencies].
TaskWorkflowPort createTestTaskWorkflow(TaskController controller) =>
    TaskWorkflowAdapter(delegate: controller);

ProjectWorkflowPort createTestProjectWorkflow(ProjectApplication application) =>
    ProjectWorkflowAdapter(delegate: application);

TaskController createTestTaskController({
  required ToolRegistryPort toolService,
  required WorkspaceSandboxPort sandbox,
  TaskPersistencePort? persistence,
  TaskPersistenceStore? persistenceStore,
  TaskRecoveryService? recoveryService,
  TaskPlanner? planner,
  TaskPlanningCoordinatorPort? planningCoordinator,
  TaskModelCompletionPort? modelCompletion,
  TaskToolExecutionPort? toolExecution,
  StructuredPlanningOutputService? structuredOutput,
  WorkspaceDiscoveryPort? profileService,
}) {
  final resolvedPersistence =
      persistence ??
      TaskRepository(coordinator: PersistenceModule.create().coordinator);
  final resolvedPersistenceStore =
      persistenceStore ??
      TaskPersistenceStore(persistence: resolvedPersistence);
  final resolvedRecovery = recoveryService ?? const TaskRecoveryService();
  final resolvedPlanner = planner ?? const TaskPlanningService();
  final resolvedPlanningCoordinator =
      planningCoordinator ?? TaskPlanningCoordinator(planner: resolvedPlanner);
  final resolvedStructuredOutput =
      structuredOutput ?? const StructuredPlanningOutputService();
  final resolvedModelCompletion =
      modelCompletion ??
      TaskModelCompletionService(structuredOutput: resolvedStructuredOutput);
  final resolvedToolExecution =
      toolExecution ??
      TaskToolExecutionService(
        protocol: ToolProtocolAdapter(registry: toolService),
        sandbox: sandbox,
      );

  return TaskController(
    dependencies: TaskRuntimeDependencies(
      toolService: toolService,
      sandbox: sandbox,
      planningCoordinator: resolvedPlanningCoordinator,
      persistenceStore: resolvedPersistenceStore,
      profileService:
          profileService ?? const WorkspaceDiscoveryProfileService(),
      gateEvaluator: TaskGateEvaluator(
        sandbox: sandbox,
        yamlValidator: const YamlDocumentValidator(),
      ),
      recoveryService: resolvedRecovery,
      modelCompletion: resolvedModelCompletion,
      toolExecution: resolvedToolExecution,
      commandService: TaskCommandService(persistence: resolvedPersistenceStore),
      stepRunner: TaskStepRunner(
        persistence: resolvedPersistenceStore,
        recovery: resolvedRecovery,
      ),
      taskViewService: const TaskViewService(),
      questionPolicy: const QuestionPolicyService(),
      encoder: const JsonEncoder.withIndent('  '),
    ),
  );
}

/// Explicit test-only composition for project application behavior tests.
/// Defaults are adapters local to this factory, never runtime fallbacks.
ProjectApplication createTestProjectApplication({
  required TaskController taskController,
  TaskSnapshotStorePort? taskPersistence,
  ToolRegistryPort? toolService,
  WorkspaceSandboxPort? sandbox,
  TaskMaterializerPort? materializer,
  ProjectSnapshotStorePort? repository,
  ProjectAggregateRepositoryPort? aggregateRepository,
  ProjectPlanner? planner,
  ProjectCompletionEvaluator? completionEvaluator,
  ProjectScheduler? scheduler,
  ProjectMemoryService? memoryService,
  ProjectProgressMonitor? progressMonitor,
  PersistencePort? persistenceCoordinator,
  ProjectCommandService? commandService,
  ProjectCommandExecutionPort? executionPort,
  ProjectRecoveryPort? recoveryPort,
  PlanningToolCallRunner? planningRunner,
  StructuredPlanningOutputService? structuredOutput,
  ProjectLifecycleService? lifecycle,
  TaskLifecycleService? taskLifecycle,
  ProjectCompletionService? completion,
  ProjectRecoveryService? recoveryService,
}) {
  final resolvedCoordinator =
      persistenceCoordinator ??
      (taskPersistence is TaskRepository
          ? taskPersistence.coordinator
          : null) ??
      PersistenceModule.create().coordinator;
  final resolvedTasks =
      taskPersistence ?? TaskRepository(coordinator: resolvedCoordinator);
  final resolvedSandbox = sandbox ?? WorkspaceSandbox();
  final resolvedTools =
      toolService ??
      ToolService(
        workspaceSandbox: resolvedSandbox is WorkspaceSandbox
            ? resolvedSandbox
            : WorkspaceSandbox(),
      );
  final resolvedProjects =
      repository ?? ProjectRepository(coordinator: resolvedCoordinator);
  final resolvedAggregate =
      aggregateRepository ??
      ProjectAggregateRepository(
        projectRepository: resolvedProjects,
        taskRepository: resolvedTasks,
        coordinator:
            persistenceCoordinator ??
            (resolvedTasks is TaskRepository
                ? resolvedTasks.coordinator
                : resolvedCoordinator),
      );
  final resolvedPlanningRunner =
      planningRunner ?? const PlanningToolCallRunner();
  final resolvedStructuredOutput =
      structuredOutput ?? const StructuredPlanningOutputService();
  final resolvedModelCalls = ProjectModelCalls(
    sandbox: resolvedSandbox,
    planningRunner: resolvedPlanningRunner,
    structuredOutput: resolvedStructuredOutput,
  );
  final resolvedPlanner = planner ?? resolvedModelCalls;
  final resolvedCompletionEvaluator = completionEvaluator ?? resolvedModelCalls;
  final resolvedScheduler = scheduler ?? const ProjectScheduler();
  final resolvedMemoryService = memoryService ?? const ProjectMemoryService();
  final resolvedProgressMonitor =
      progressMonitor ?? const ProjectProgressMonitor();
  final resolvedLifecycle = lifecycle ?? const ProjectLifecycleService();
  final resolvedTaskLifecycle = taskLifecycle ?? const TaskLifecycleService();
  final resolvedRecoveryService =
      recoveryService ?? const ProjectRecoveryService();
  final resolvedStateStore = ProjectAggregateHydrator(
    projectRepository: resolvedProjects,
    aggregateRepository: resolvedAggregate,
    taskQueries: taskController,
  );
  final resolvedCommandService =
      commandService ??
      ProjectCommandService(
        stateStore: resolvedStateStore,
        persistenceCoordinator: resolvedCoordinator,
      );
  final resolvedAggregateStore = ProjectAggregateStore(
    aggregateRepository: resolvedAggregate,
    taskRepository: resolvedTasks,
    materializer: materializer ?? const TaskPlanMaterializer(),
  );
  const resolvedControlState = ProjectControlStateService();
  final resolvedPersistenceHandler = ProjectPersistenceHandler(
    aggregateStore: resolvedAggregateStore,
    scheduler: resolvedScheduler,
    controlState: resolvedControlState,
  );
  final resolvedDiscovery = ProjectDiscoveryService(
    taskController: taskController,
    changeDiscovery: WorkspaceChangeDiscoveryService(commands: resolvedSandbox),
    memoryService: resolvedMemoryService,
    profileService: const WorkspaceDiscoveryProfileService(),
  );
  final resolvedPlanningHandler = ProjectPlanningHandler(
    revisionService: const ProjectPlanRevisionService(),
  );
  final resolvedCompletion =
      completion ?? ProjectCompletionService(lifecycle: resolvedLifecycle);

  return ProjectApplication(
    taskQueries: taskController,
    taskPlanning: taskController,
    taskProjectPlanning: taskController,
    taskExecution: taskController,
    taskRecovery: taskController,
    toolService: resolvedTools,
    materializer: materializer ?? const TaskPlanMaterializer(),
    aggregateRepository: resolvedAggregate,
    dependencies: ProjectRuntimeDependencies(
      planner: resolvedPlanner,
      completionEvaluator: resolvedCompletionEvaluator,
      scheduler: resolvedScheduler,
      memoryService: resolvedMemoryService,
      progressMonitor: resolvedProgressMonitor,
      persistenceCoordinator: resolvedCoordinator,
      aggregateStore: resolvedAggregateStore,
      persistenceHandler: resolvedPersistenceHandler,
      stateStore: resolvedStateStore,
      commandService: resolvedCommandService,
      questionPolicy: const QuestionPolicyService(),
      evidenceService: const ProjectEvidenceService(),
      criterionEvaluator: const ProjectCriterionEvaluator(),
      discoveryService: resolvedDiscovery,
      planningHandler: resolvedPlanningHandler,
      decisionEngine: const ProjectDecisionEngine(),
      controlStateService: resolvedControlState,
      lifecycleService: resolvedLifecycle,
      taskLifecycleService: resolvedTaskLifecycle,
      completionService: resolvedCompletion,
      recoveryHandler: ProjectRecoveryHandler(resolvedRecoveryService),
      executionPort: executionPort,
      recoveryPort: recoveryPort,
    ),
  );
}
