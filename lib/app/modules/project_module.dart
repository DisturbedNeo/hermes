import 'package:hermes/features/project/application/project_application/project_application.dart';
import 'package:hermes/features/project/domain/project_control_state_service.dart';
import 'package:hermes/features/project/domain/project_scheduler.dart';
import 'package:hermes/features/project/runtime/project_aggregate_hydrator.dart';
import 'package:hermes/features/project/runtime/project_aggregate_store.dart';
import 'package:hermes/features/project/runtime/project_command_service.dart';
import 'package:hermes/features/project/runtime/project_completion_service.dart';
import 'package:hermes/features/project/runtime/project_criterion_evaluator.dart';
import 'package:hermes/features/project/runtime/project_decision_engine.dart';
import 'package:hermes/features/project/runtime/project_discovery_service.dart';
import 'package:hermes/features/project/runtime/project_evidence_service.dart';
import 'package:hermes/features/project/runtime/project_handlers.dart';
import 'package:hermes/features/project/runtime/project_lifecycle_service.dart';
import 'package:hermes/features/project/runtime/project_memory_service.dart';
import 'package:hermes/features/project/runtime/project_model_calls.dart';
import 'package:hermes/features/project/runtime/project_plan_revision_service.dart';
import 'package:hermes/features/project/runtime/project_planning_coordinator.dart';
import 'package:hermes/features/project/runtime/project_progress_monitor.dart';
import 'package:hermes/features/project/runtime/project_recovery_service.dart';
import 'package:hermes/features/project/runtime/project_execution_runtime.dart';
import 'package:hermes/features/project/application/project_application/project_workflow_port.dart';
import 'package:hermes/features/project/runtime/project_workflow_adapter.dart';
import 'package:hermes/features/task/application/contracts/question_policy_service.dart';
import 'package:hermes/features/task/application/task_application/task_plan_materializer.dart';
import 'package:hermes/features/task/application/task_application/task_controller.dart';
import 'package:hermes/features/task/domain/task_lifecycle_service.dart';
import 'package:hermes/features/task/application/protocol/planning_runtime.dart';
import 'package:hermes/features/task/application/protocol/planning_structured_output.dart';
import 'package:hermes/app/modules/persistence_module.dart';
import 'package:hermes/app/modules/workspace_tools_module.dart';

/// Project planning, execution, recovery, and persistence capabilities.
class ProjectModule {
  ProjectModule._({required this.application, required this.workflow});

  factory ProjectModule.create({
    required PersistenceModule persistence,
    required WorkspaceToolsModule workspace,
    required TaskController task,
  }) {
    const planningRunner = PlanningToolCallRunner();
    const structuredOutput = StructuredPlanningOutputService();
    final modelCalls = ProjectModelCalls(
      sandbox: workspace.sandbox,
      planningRunner: planningRunner,
      structuredOutput: structuredOutput,
    );
    const scheduler = ProjectScheduler();
    const memory = ProjectMemoryService();
    const progress = ProjectProgressMonitor();
    const lifecycle = ProjectLifecycleService();
    const taskLifecycle = TaskLifecycleService();
    const materializer = TaskPlanMaterializer();
    final stateStore = ProjectAggregateHydrator(
      projectRepository: persistence.projects,
      aggregateRepository: persistence.projectAggregates,
      taskQueries: task,
    );
    final commandService = ProjectCommandService(
      stateStore: stateStore,
      persistenceCoordinator: persistence.coordinator,
    );
    final aggregateStore = ProjectAggregateStore(
      aggregateRepository: persistence.projectAggregates,
      taskRepository: persistence.tasks,
      materializer: materializer,
    );
    final controlState = const ProjectControlStateService();
    final persistenceHandler = ProjectPersistenceHandler(
      aggregateStore: aggregateStore,
      scheduler: scheduler,
      controlState: controlState,
    );
    final discovery = ProjectDiscoveryService(
      taskController: task,
      changeDiscovery: workspace.changeDiscovery,
      profileService: workspace.discovery,
      memoryService: memory,
    );
    final planningHandler = ProjectPlanningHandler(
      coordinator: ProjectPlanningCoordinator(
        discovery: discovery,
        planner: modelCalls,
      ),
      revisionService: const ProjectPlanRevisionService(),
    );
    final dependencies = ProjectRuntimeDependencies(
      planner: modelCalls,
      completionEvaluator: modelCalls,
      scheduler: scheduler,
      memoryService: memory,
      progressMonitor: progress,
      persistenceCoordinator: persistence.coordinator,
      aggregateStore: aggregateStore,
      persistenceHandler: persistenceHandler,
      stateStore: stateStore,
      commandService: commandService,
      questionPolicy: const QuestionPolicyService(),
      evidenceService: const ProjectEvidenceService(),
      criterionEvaluator: const ProjectCriterionEvaluator(),
      discoveryService: discovery,
      planningHandler: planningHandler,
      decisionEngine: const ProjectDecisionEngine(),
      controlStateService: controlState,
      lifecycleService: lifecycle,
      taskLifecycleService: taskLifecycle,
      completionService: ProjectCompletionService(lifecycle: lifecycle),
      recoveryHandler: ProjectRecoveryHandler(const ProjectRecoveryService()),
    );
    final application = ProjectApplication(
      taskQueries: task,
      taskPlanning: task,
      taskProjectPlanning: task,
      taskExecution: task,
      taskRecovery: task,
      toolService: workspace.tools,
      materializer: materializer,
      aggregateRepository: persistence.projectAggregates,
      dependencies: dependencies,
    );
    return ProjectModule._(
      application: application,
      workflow: ProjectWorkflowAdapter(delegate: application),
    );
  }

  final ProjectApplication application;
  final ProjectWorkflowPort workflow;
}
