import 'package:hermes/features/project/application/project_application/project_application.dart';
import 'package:hermes/features/project/project_aggregate_repository_port.dart';
import 'package:hermes/features/project/project_repository_port.dart';
import 'package:hermes/features/project/runtime/project_command_service.dart';
import 'package:hermes/features/project/runtime/project_completion_service.dart';
import 'package:hermes/features/project/runtime/project_lifecycle_service.dart';
import 'package:hermes/features/project/runtime/project_memory_service.dart';
import 'package:hermes/features/project/runtime/project_planning_gateway.dart';
import 'package:hermes/features/project/runtime/project_progress_monitor.dart';
import 'package:hermes/features/project/runtime/project_recovery_service.dart';
import 'package:hermes/features/project/domain/project_scheduler.dart';
import 'package:hermes/features/task/application/task_application/task_controller.dart';
import 'package:hermes/features/task/application/task_application/task_persistence_ports.dart';
import 'package:hermes/features/task/application/task_application/task_plan_materializer.dart';
import 'package:hermes/features/task/application/task_application/task_ports.dart';
import 'package:hermes/features/task/infrastructure/task_repository.dart';
import 'package:hermes/features/task/domain/task_lifecycle_service.dart';
import 'package:hermes/features/task/runtime/task_persistence_store.dart';
import 'package:hermes/features/task/runtime/task_recovery_service.dart';
import 'package:hermes/features/task/runtime/task_planning_service.dart';
import 'package:hermes/features/task/runtime/task_planning_coordinator.dart';
import 'package:hermes/features/task/runtime/task_tool_execution_service.dart';
import 'package:hermes/features/task/runtime/task_model_completion_service.dart';
import 'package:hermes/features/project/infrastructure/project_aggregate_repository.dart';
import 'package:hermes/features/project/infrastructure/project_repository.dart';
import 'package:hermes/shared_kernel/planning_runtime.dart';
import 'package:hermes/shared_kernel/planning_structured_output.dart';
import 'package:hermes/shared_kernel/tool_contracts.dart';
import 'package:hermes/shared_kernel/workspace_discovery_service.dart';
import 'package:hermes/shared_kernel/workspace_ports.dart';
import 'package:hermes/platform/tool_service.dart';
import 'package:hermes/platform/workspace_sandbox.dart';

/// Explicit construction helpers for tests that need lightweight adapters.
/// Production composition is kept in [AppDependencies].
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
  WorkspaceDiscoveryProfileService? profileService,
}) => TaskController(
  toolService: toolService,
  sandbox: sandbox,
  persistence: persistence ?? TaskRepository(),
  persistenceStore: persistenceStore,
  recoveryService: recoveryService,
  planner: planner,
  planningCoordinator: planningCoordinator,
  modelCompletion: modelCompletion,
  toolExecution: toolExecution,
  structuredOutput: structuredOutput,
  profileService: profileService,
);

/// Explicit test-only composition for project application behavior tests.
/// Defaults are adapters local to this factory, never runtime fallbacks.
ProjectApplication createTestProjectApplication({
  required TaskProjectPort taskController,
  TaskPersistencePort? taskPersistence,
  ToolRegistryPort? toolService,
  WorkspaceSandboxPort? sandbox,
  TaskMaterializerPort? materializer,
  ProjectRepositoryPort? repository,
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
  final resolvedTasks = taskPersistence ?? TaskRepository();
  final resolvedSandbox = sandbox ?? WorkspaceSandbox();
  final resolvedTools =
      toolService ??
      ToolService(
        workspaceSandbox: resolvedSandbox is WorkspaceSandbox
            ? resolvedSandbox
            : WorkspaceSandbox(),
      );
  final resolvedProjects = repository ?? ProjectRepository();
  final resolvedAggregate =
      aggregateRepository ??
      ProjectAggregateRepository(
        projectRepository: resolvedProjects,
        taskRepository: resolvedTasks,
        coordinator: persistenceCoordinator ?? resolvedTasks.coordinator,
      );

  return ProjectApplication(
    taskController: taskController,
    taskPersistence: resolvedTasks,
    toolService: resolvedTools,
    sandbox: resolvedSandbox,
    materializer: materializer ?? TaskPlanMaterializer(),
    repository: resolvedProjects,
    aggregateRepository: resolvedAggregate,
    planner: planner,
    completionEvaluator: completionEvaluator,
    scheduler: scheduler,
    memoryService: memoryService,
    progressMonitor: progressMonitor,
    persistenceCoordinator: persistenceCoordinator,
    commandService: commandService,
    executionPort: executionPort,
    recoveryPort: recoveryPort,
    planningRunner: planningRunner,
    structuredOutput: structuredOutput,
    lifecycle: lifecycle,
    taskLifecycle: taskLifecycle,
    completion: completion,
    recoveryService: recoveryService,
  );
}
