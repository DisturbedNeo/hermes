library;

import 'dart:async';
import 'dart:convert';

import 'package:hermes/core/json_parsing.dart';
import 'package:hermes/core/uuid.dart';
import 'package:hermes/core/contracts/model_conversation.dart';
import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/features/task/application/contracts/planning_metrics.dart';
import 'package:hermes/features/task/application/contracts/task_snapshot_models.dart';
import 'package:hermes/features/task/application/task_application/task_persistence_ports.dart';
import 'package:hermes/core/contracts/execution_settings.dart';
import 'package:hermes/features/workspace/application/workspace.dart';
import 'package:hermes/features/model/application/model_completion_port.dart';
import 'package:hermes/core/cancellation.dart';
import 'package:hermes/features/project/runtime/project_model_calls.dart';
import 'package:hermes/features/project/runtime/project_criterion_evaluator.dart';
import 'package:hermes/features/project/runtime/project_evidence_service.dart';
import 'package:hermes/features/project/runtime/project_memory_service.dart';
import 'package:hermes/features/project/application/project_application/project_execution_port.dart';
import 'package:hermes/features/project/runtime/project_completion_service.dart';
import 'package:hermes/features/project/domain/project_control_state_service.dart';
import 'package:hermes/features/project/runtime/project_lifecycle_service.dart';
import 'package:hermes/features/project/runtime/project_decision_engine.dart';
import 'package:hermes/features/project/application/contracts/project_checkpoint.dart';
import 'package:hermes/features/project/application/contracts/project_commands.dart';
import 'package:hermes/features/project/runtime/project_plan_patch.dart';
import 'package:hermes/features/project/runtime/project_plan_validator.dart';
import 'package:hermes/features/project/domain/project_workspace_context_service.dart';
import 'package:hermes/features/project/runtime/project_state_models.dart';
import 'package:hermes/features/project/runtime/project_progress_monitor.dart';
import 'package:hermes/features/project/project_repository_port.dart';
import 'package:hermes/features/project/project_aggregate_repository_port.dart';
import 'package:hermes/features/project/runtime/project_aggregate_store.dart';
import 'package:hermes/features/project/runtime/project_handlers.dart';
import 'package:hermes/features/project/runtime/project_aggregate_hydrator.dart';
import 'package:hermes/features/project/runtime/project_persistence_runtime.dart';
import 'package:hermes/features/project/runtime/project_persistence_coordinator.dart';
import 'package:hermes/features/project/runtime/project_plan_revision_coordinator.dart';
import 'package:hermes/features/project/runtime/project_discovery_service.dart';
import 'package:hermes/features/project/runtime/project_evaluation_coordinator.dart';
import 'package:hermes/features/project/runtime/project_command_service.dart';
import 'package:hermes/features/project/domain/project_scheduler.dart';
import 'package:hermes/features/task/application/contracts/question_policy_service.dart';
import 'package:hermes/features/model/application/model_output.dart';
import 'package:hermes/features/task/domain/task_lifecycle_service.dart';
import 'package:hermes/features/task/application/task_application/task_ports.dart';
import 'package:hermes/features/tools/application/tool_contracts.dart';
import 'package:hermes/features/task/application/contracts/task_planning_models.dart';
import 'package:hermes/features/workspace/application/workspace_discovery_profile.dart';
import 'package:hermes/features/workspace/application/workspace_ports.dart';
import 'package:path/path.dart' as path;

part 'project_recovery_policy.dart';
part 'project_execution_operations.dart';
part 'project_execution_core.dart';

// ProjectExecutionRuntime

class ProjectRuntimeDependencies {
  const ProjectRuntimeDependencies({
    required this.planner,
    required this.completionEvaluator,
    required this.scheduler,
    required this.memoryService,
    required this.progressMonitor,
    required this.persistenceCoordinator,
    required this.aggregateStore,
    required this.persistenceHandler,
    required this.stateStore,
    required this.commandService,
    required this.questionPolicy,
    required this.evidenceService,
    required this.criterionEvaluator,
    required this.discoveryService,
    required this.planningHandler,
    required this.decisionEngine,
    required this.controlStateService,
    required this.lifecycleService,
    required this.taskLifecycleService,
    required this.completionService,
    required this.recoveryHandler,
    this.executionPort,
    this.recoveryPort,
  });

  final ProjectPlanner planner;
  final ProjectCompletionEvaluator completionEvaluator;
  final ProjectScheduler scheduler;
  final ProjectMemoryService memoryService;
  final ProjectProgressMonitor progressMonitor;
  final PersistencePort persistenceCoordinator;
  final ProjectAggregateStore aggregateStore;
  final ProjectPersistenceHandler persistenceHandler;
  final ProjectAggregateHydrator stateStore;
  final ProjectCommandService commandService;
  final QuestionPolicyService questionPolicy;
  final ProjectEvidenceService evidenceService;
  final ProjectCriterionEvaluator criterionEvaluator;
  final ProjectDiscoveryService discoveryService;
  final ProjectPlanningHandler planningHandler;
  final ProjectDecisionEngine decisionEngine;
  final ProjectControlStateService controlStateService;
  final ProjectLifecycleService lifecycleService;
  final TaskLifecycleService taskLifecycleService;
  final ProjectCompletionService completionService;
  final ProjectRecoveryHandler recoveryHandler;
  final ProjectCommandExecutionPort? executionPort;
  final ProjectRecoveryPort? recoveryPort;
}

class ProjectExecutionStateMachine {
  ProjectExecutionStateMachine({
    required TaskQueryPort taskQueries,
    required TaskPlanningPort taskPlanning,
    required TaskProjectPlanningPort taskProjectPlanning,
    required TaskExecutionPort taskExecution,
    required TaskRecoveryPort taskRecovery,
    required this.taskPersistence,
    required this.toolService,
    required this.materializer,
    required ProjectRepositoryPort repository,
    required ProjectAggregateRepositoryPort aggregateRepository,
    required ProjectRuntimeDependencies dependencies,
    required ProjectCommandExecutionPort executionPort,
    required ProjectRecoveryPort recoveryPort,
  }) : _taskPlanning = taskPlanning,
       _taskProjectPlanning = taskProjectPlanning,
       _taskExecution = taskExecution,
       _taskRecovery = taskRecovery,
       _repository = repository,
       _aggregateRepository = aggregateRepository,
       _planner = dependencies.planner,
       _completionEvaluator = dependencies.completionEvaluator,
       _scheduler = dependencies.scheduler,
       _memoryService = dependencies.memoryService,
       _progressMonitor = dependencies.progressMonitor,
       lifecycleService = dependencies.lifecycleService,
       taskLifecycleService = dependencies.taskLifecycleService,
       completionService = dependencies.completionService,
       recoveryHandler = dependencies.recoveryHandler,
       _persistenceCoordinator = ProjectPersistenceCoordinator(
         persistence: ProjectPersistenceRuntime(
           stateStore: dependencies.stateStore,
           persistenceHandler: dependencies.persistenceHandler,
           taskQueries: taskQueries,
         ),
         stateStore: dependencies.stateStore,
       ),
       _commandService = dependencies.commandService,
       _executionPort = executionPort,
       _recoveryPort = recoveryPort,
       _questionPolicy = dependencies.questionPolicy,
       _evidenceService = dependencies.evidenceService,
       _criterionEvaluator = dependencies.criterionEvaluator,
       _planRevisionCoordinator = ProjectPlanRevisionCoordinator(
         discovery: dependencies.discoveryService,
         planner: dependencies.planner,
       ),
       _planningHandler = dependencies.planningHandler,
       _decisionEngine = dependencies.decisionEngine,
       _controlStateService = dependencies.controlStateService {
    _evaluationCoordinator = ProjectEvaluationCoordinator(
      evidenceService: _evidenceService,
      criterionEvaluator: _criterionEvaluator,
      remainingCriteria: _remainingCriteria,
      projectForModel: _projectForModel,
    );
  }

  final TaskPlanningPort _taskPlanning;
  final TaskProjectPlanningPort _taskProjectPlanning;
  final TaskExecutionPort _taskExecution;
  final TaskRecoveryPort _taskRecovery;
  final TaskPersistencePort taskPersistence;
  final ToolRegistryPort toolService;
  final TaskMaterializerPort materializer;
  final ProjectRepositoryPort _repository;
  final ProjectPlanner _planner;
  final ProjectCompletionEvaluator _completionEvaluator;
  final ProjectScheduler _scheduler;
  final ProjectMemoryService _memoryService;
  final ProjectProgressMonitor _progressMonitor;
  final ProjectLifecycleService lifecycleService;
  final TaskLifecycleService taskLifecycleService;
  final ProjectCompletionService completionService;
  final ProjectRecoveryHandler recoveryHandler;
  final ProjectAggregateRepositoryPort _aggregateRepository;
  final ProjectPersistenceCoordinator _persistenceCoordinator;
  final ProjectCommandService _commandService;
  final ProjectCommandExecutionPort _executionPort;
  final ProjectRecoveryPort _recoveryPort;
  final QuestionPolicyService _questionPolicy;
  final ProjectEvidenceService _evidenceService;
  final ProjectCriterionEvaluator _criterionEvaluator;
  final ProjectPlanRevisionCoordinator _planRevisionCoordinator;
  final ProjectPlanningHandler _planningHandler;
  final ProjectDecisionEngine _decisionEngine;
  final ProjectControlStateService _controlStateService;
  late final ProjectEvaluationCoordinator _evaluationCoordinator;
  final ProjectRecoveryPolicy _recoveryPolicy = ProjectRecoveryPolicy();

  static const Set<ProjectPlanRevisionTrigger> _runtimeReplanTriggers = {
    ProjectPlanRevisionTrigger.noReadyTask,
    ProjectPlanRevisionTrigger.taskFailed,
    ProjectPlanRevisionTrigger.evidenceRejected,
    ProjectPlanRevisionTrigger.taskReplanRequested,
    ProjectPlanRevisionTrigger.workspaceChanged,
    ProjectPlanRevisionTrigger.scopeChanged,
    ProjectPlanRevisionTrigger.milestoneRoadmapChanged,
  };

  static int taskStepLimit(TaskEffort effort) => switch (effort) {
    TaskEffort.small => 1,
    TaskEffort.medium => 4,
    TaskEffort.large => 6,
  };
  // Project access operations
  /// Executes successive bounded runs until the project reaches a user-facing
  /// boundary. The command gate is held for the whole sequence, so another
  /// tab cannot start a second project command between automatic continuations.
  Future<ProjectCommandResult> executeUntilStop(
    ProjectExecutionRequest request, {
    required bool boundedRun,
  }) => _commandService.executeUntilStop(
    request,
    boundedRun: boundedRun,
    port: _executionPort,
  );

  Future<ProjectCommandResult> recover(ProjectRecoveryRequest request) =>
      _commandService.recover(request, port: _recoveryPort);

  Future<ProjectTransactionRecoveryResult> recoverPersistence(
    WorkspaceAttachment workspace,
  ) => _persistenceCoordinator.recoverInterruptedTransactions(workspace);

  Future<ProjectCommandResult> runProjectForCommand(
    ProjectExecutionRequest request,
  ) => _runProjectCore(
    client: request.client,
    workspace: request.workspace,
    snapshot: request.snapshot,
    baseSystemPrompt: request.baseSystemPrompt,
    maxNewTasks: request.maxNewTasks,
    maxIterations: request.maxIterations,
    requirePhaseApproval: request.requirePhaseApproval,
    compactionSettings: request.compactionSettings,
    contextLimitTokens: request.contextLimitTokens,
    onCompactionStatus: request.onCompactionStatus,
    onModelOutput: request.onModelOutput,
    onTaskUpdated: request.onTaskUpdated,
    cancellationToken: request.cancellationToken,
    questionAutonomy: request.questionAutonomy,
    planApprovalPolicy: request.planApprovalPolicy,
  );

  Future<ProjectCommandResult> recoverProjectForCommand(
    ProjectRecoveryRequest request,
  ) => _recoverProjectCore(
    workspace: request.workspace,
    snapshot: request.snapshot,
    onTaskUpdated: request.onTaskUpdated,
  );
}

// lib/features/project/runtime/project_operation_models.dart

class _ProjectTaskValidation {
  final bool valid;
  final List<String> violations;

  const _ProjectTaskValidation(this.valid, this.violations);
}

sealed class _DuplicateProjectTaskMatch {
  final ProjectTaskNode task;

  const _DuplicateProjectTaskMatch(this.task);
}

class _QueuedDuplicateProjectTask extends _DuplicateProjectTaskMatch {
  const _QueuedDuplicateProjectTask(super.task);
}

class _FailedDuplicateProjectTask extends _DuplicateProjectTaskMatch {
  const _FailedDuplicateProjectTask(super.task);
}

class _ProjectTaskExecution {
  final ProjectAggregate project;
  final Task? activeTask;
  final TaskResult? result;

  const _ProjectTaskExecution({
    required this.project,
    this.activeTask,
    this.result,
  });
}

class ProjectRecoveryFailure {
  final TaskGateResult gateResult;
  final String? command;
  final String? workingDirectory;
  final String summary;

  const ProjectRecoveryFailure({
    required this.gateResult,
    required this.command,
    required this.workingDirectory,
    required this.summary,
  });
}

class ProjectRecoveryUpdate {
  final ProjectTaskNode failedTask;
  final List<ProjectRecoveryIncident> recoveryIncidents;
  final ProjectRecoveryIncident? incident;
  final ProjectRecoveryIncident? exhaustedIncident;
  final ProjectTaskNode? recoveryTask;

  const ProjectRecoveryUpdate({
    required this.failedTask,
    required this.recoveryIncidents,
    this.incident,
    this.exhaustedIncident,
    this.recoveryTask,
  });
}

class _FilteredProjectQuestions {
  final List<PendingProjectQuestion> blocking;
  final List<String> assumptions;

  const _FilteredProjectQuestions({
    required this.blocking,
    required this.assumptions,
  });
}
