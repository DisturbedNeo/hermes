library;

import 'dart:async';
import 'dart:convert';

import 'package:hermes/core/json_parsing.dart';
import 'package:hermes/core/uuid.dart';
import 'package:hermes/core/contracts/model_conversation.dart';
import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/features/task/application/contracts/planning_metrics.dart';
import 'package:hermes/features/task/domain/task.dart';
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
import 'package:hermes/features/project/runtime/project_planning_policy.dart';
import 'package:hermes/features/project/domain/project_workspace_context_service.dart';
import 'package:hermes/features/project/runtime/project_state_models.dart';
import 'package:hermes/features/project/runtime/project_progress_monitor.dart';
import 'package:hermes/features/project/project_aggregate_repository_port.dart';
import 'package:hermes/features/project/runtime/project_aggregate_store.dart';
import 'package:hermes/features/project/runtime/project_handlers.dart';
import 'package:hermes/features/project/runtime/project_aggregate_hydrator.dart';
import 'package:hermes/features/project/runtime/project_persistence_runtime.dart';
import 'package:hermes/features/project/runtime/project_persistence_coordinator.dart';
import 'package:hermes/features/project/runtime/project_plan_revision_coordinator.dart';
import 'package:hermes/features/project/runtime/project_discovery_service.dart';
import 'package:hermes/features/project/runtime/project_workspace_graph_maintenance_coordinator.dart';
import 'package:hermes/features/project/runtime/project_evaluation_coordinator.dart';
import 'package:hermes/features/project/runtime/project_command_service.dart';
import 'package:hermes/features/project/domain/project_scheduler.dart';
import 'package:hermes/features/task/application/contracts/question_policy_service.dart';
import 'package:hermes/features/model/application/model_output.dart';
import 'package:hermes/features/task/domain/task_lifecycle_service.dart';
import 'package:hermes/features/task/application/task_application/task_ports.dart';
import 'package:hermes/features/task/application/task_application/task_persistence_ports.dart';
import 'package:hermes/features/tools/application/tool_contracts.dart';
import 'package:hermes/features/task/application/contracts/task_planning_models.dart';
import 'package:hermes/features/workspace/application/workspace_discovery_profile.dart';
import 'package:hermes/features/workspace/application/workspace_ports.dart';
import 'package:path/path.dart' as path;

part 'project_recovery_policy.dart';
part 'project_execution_operations.dart';
part 'project_execution_core.dart';
part 'project_execution_lifecycle.dart';
part 'project_user_command_coordinator.dart';
part 'project_planning_use_case.dart';
part 'project_execution_context.dart';
part 'project_execution_use_case.dart';

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
    required TaskWorkflowQueryPort taskQueries,
    required TaskPlanningPort taskPlanning,
    required TaskProjectPlanningPort taskProjectPlanning,
    required TaskExecutionPort taskExecution,
    required TaskRecoveryPort taskRecovery,
    required this.toolService,
    required this.materializer,
    required ProjectAggregateReadPort aggregateRepository,
    required ProjectRuntimeDependencies dependencies,
    required ProjectCommandExecutionPort executionPort,
    required ProjectRecoveryPort recoveryPort,
  }) : _taskPlanning = taskPlanning,
       _taskProjectPlanning = taskProjectPlanning,
       _taskExecution = taskExecution,
       _taskRecovery = taskRecovery,
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
       _graphMaintenanceCoordinator =
           ProjectWorkspaceGraphMaintenanceCoordinator(
             discovery: dependencies.discoveryService,
             planner: dependencies.planner,
           ),
       _planningHandler = dependencies.planningHandler,
       _decisionEngine = dependencies.decisionEngine,
       _controlStateService = dependencies.controlStateService {
    final useCaseContext = ProjectUseCaseContext(
      taskPlanning: _taskPlanning,
      taskProjectPlanning: _taskProjectPlanning,
      taskExecution: _taskExecution,
      taskRecovery: _taskRecovery,
      toolService: toolService,
      materializer: materializer,
      aggregateRepository: _aggregateRepository,
      persistenceCoordinator: _persistenceCoordinator,
      planner: _planner,
      completionEvaluator: _completionEvaluator,
      completionService: completionService,
      progressMonitor: _progressMonitor,
      evidenceService: _evidenceService,
      criterionEvaluator: _criterionEvaluator,
      planRevisionCoordinator: _planRevisionCoordinator,
      graphMaintenanceCoordinator: _graphMaintenanceCoordinator,
      decisionEngine: _decisionEngine,
      questionPolicy: _questionPolicy,
      recoveryHandler: recoveryHandler,
      evaluationCoordinator: () => _evaluationCoordinator,
      planningHandler: _planningHandler,
      controlStateService: _controlStateService,
      memoryService: _memoryService,
      recoveryPolicy: _recoveryPolicy,
      scheduler: _scheduler,
      lifecycleService: lifecycleService,
      titleFromPrompt: (prompt) => _executionUseCase._titleFromPrompt(prompt),
      newProjectId: (prompt) => _executionUseCase._newProjectId(prompt),
      normaliseOptionalLimit: (value, {fallback = 0}) =>
          _executionUseCase._normaliseOptionalLimit(value, fallback: fallback),
      persistProject:
          (
            workspaceRoot,
            project, {
            persistenceContext,
            checkpoint = ProjectPersistenceCheckpoint.runtime,
          }) => _executionUseCase._persistProject(
            workspaceRoot,
            project,
            persistenceContext: persistenceContext,
            checkpoint: checkpoint,
          ),
      transitionProject:
          ({
            required snapshot,
            required to,
            required trigger,
            required reason,
            blocker,
            required now,
          }) => _executionUseCase._transitionProject(
            snapshot: snapshot,
            to: to,
            trigger: trigger,
            reason: reason,
            blocker: blocker,
            now: now,
          ),
      appendTrigger: (current, trigger) =>
          _executionUseCase._appendTrigger(current, trigger),
      appendUnique: (current, value) =>
          _executionUseCase._appendUnique(current, value),
      decision: (type, summary, rationale, {task}) =>
          _executionUseCase._decision(type, summary, rationale, task: task),
      activeProjectTask: (project) =>
          _executionUseCase._activeProjectTask(project),
    );
    _userCommands = ProjectUserCommandCoordinator(useCaseContext);
    _planningUseCase = ProjectPlanningUseCase(useCaseContext);
    _executionUseCase = ProjectExecutionUseCase(useCaseContext);
    _evaluationCoordinator = ProjectEvaluationCoordinator(
      evidenceService: _evidenceService,
      criterionEvaluator: _criterionEvaluator,
      remainingCriteria: _executionUseCase._remainingCriteria,
      projectForModel: _executionUseCase._projectForModel,
    );
  }

  final TaskPlanningPort _taskPlanning;
  final TaskProjectPlanningPort _taskProjectPlanning;
  final TaskExecutionPort _taskExecution;
  final TaskRecoveryPort _taskRecovery;
  final ToolRegistryPort toolService;
  final TaskMaterializerPort materializer;
  final ProjectPlanner _planner;
  final ProjectCompletionEvaluator _completionEvaluator;
  final ProjectScheduler _scheduler;
  final ProjectMemoryService _memoryService;
  final ProjectProgressMonitor _progressMonitor;
  final ProjectLifecycleService lifecycleService;
  final TaskLifecycleService taskLifecycleService;
  final ProjectCompletionService completionService;
  final ProjectRecoveryHandler recoveryHandler;
  final ProjectAggregateReadPort _aggregateRepository;
  final ProjectPersistenceCoordinator _persistenceCoordinator;
  final ProjectCommandService _commandService;
  final ProjectCommandExecutionPort _executionPort;
  final ProjectRecoveryPort _recoveryPort;
  final QuestionPolicyService _questionPolicy;
  final ProjectEvidenceService _evidenceService;
  final ProjectCriterionEvaluator _criterionEvaluator;
  final ProjectPlanRevisionCoordinator _planRevisionCoordinator;
  final ProjectWorkspaceGraphMaintenanceCoordinator
  _graphMaintenanceCoordinator;
  final ProjectPlanningHandler _planningHandler;
  final ProjectDecisionEngine _decisionEngine;
  final ProjectControlStateService _controlStateService;
  late final ProjectEvaluationCoordinator _evaluationCoordinator;
  final ProjectRecoveryPolicy _recoveryPolicy = ProjectRecoveryPolicy();
  late final ProjectUserCommandCoordinator _userCommands;
  late final ProjectPlanningUseCase _planningUseCase;
  late final ProjectExecutionUseCase _executionUseCase;

  static const Set<ProjectPlanRevisionTrigger> _runtimeReplanTriggers = {
    ProjectPlanRevisionTrigger.initialization,
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

  Future<ProjectCommandResult> execute(ProjectExecutionRequest request) =>
      _commandService.execute(request, port: _executionPort);

  Future<List<ProjectSummary>> listProjects(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
  }) => _persistenceCoordinator.listProjects(
    workspace,
    chatSessionId: chatSessionId,
  );

  Future<ProjectAggregate?> loadLatestProject(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
  }) async => (await _persistenceCoordinator.loadLatestProject(
    workspace,
    chatSessionId: chatSessionId,
  )).project;

  Future<ProjectLoadResult> loadLatestProjectResult(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
  }) => _persistenceCoordinator.loadLatestProject(
    workspace,
    chatSessionId: chatSessionId,
  );

  Future<ProjectAggregate?> loadProject(
    WorkspaceAttachment workspace,
    String projectId, {
    String? chatSessionId,
  }) async => (await _persistenceCoordinator.loadProject(
    workspace,
    projectId,
    chatSessionId: chatSessionId,
  )).project;

  Future<ProjectLoadResult> loadProjectResult(
    WorkspaceAttachment workspace,
    String projectId, {
    String? chatSessionId,
  }) => _persistenceCoordinator.loadProject(
    workspace,
    projectId,
    chatSessionId: chatSessionId,
  );

  Future<int> deleteProjectsForChatSession(
    WorkspaceAttachment workspace, {
    required String chatSessionId,
  }) => _persistenceCoordinator.deleteProjectsForChatSession(
    workspace,
    chatSessionId: chatSessionId,
  );

  Future<int> deleteOrphanedChatProjects(
    WorkspaceAttachment workspace, {
    required Set<String> retainedChatSessionIds,
  }) => _persistenceCoordinator.deleteOrphanedChatProjects(
    workspace,
    retainedChatSessionIds: retainedChatSessionIds,
  );

  Future<void> updateProjectChatSessionId({
    required WorkspaceAttachment workspace,
    required String projectId,
    required String sourceChatSessionId,
    required String chatSessionId,
  }) => _persistenceCoordinator.updateProjectChatSessionId(
    workspace: workspace,
    projectId: projectId,
    sourceChatSessionId: sourceChatSessionId,
    chatSessionId: chatSessionId,
  );

  Future<ProjectAggregate> updateProject({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
    required ProjectUpdateCommand command,
  }) => _persistenceCoordinator.updateProject(
    workspace: workspace,
    snapshot: snapshot,
    command: command,
  );

  Future<ProjectAggregate> upsertUserWorkspaceNode({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
    String? id,
    required String type,
    required String title,
    String description = '',
    List<String> aliases = const [],
    List<String> tags = const [],
    List<String> references = const [],
    String? sourceId,
  }) => _persistenceCoordinator.upsertUserWorkspaceNode(
    workspace: workspace,
    snapshot: snapshot,
    id: id,
    type: type,
    title: title,
    description: description,
    aliases: aliases,
    tags: tags,
    references: references,
    sourceId: sourceId,
  );

  Future<ProjectAggregate> upsertUserWorkspaceEdge({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
    String? id,
    required String sourceNodeId,
    required String targetNodeId,
    required String label,
    String description = '',
    String? sourceId,
  }) => _persistenceCoordinator.upsertUserWorkspaceEdge(
    workspace: workspace,
    snapshot: snapshot,
    id: id,
    sourceNodeId: sourceNodeId,
    targetNodeId: targetNodeId,
    label: label,
    description: description,
    sourceId: sourceId,
  );

  Future<ProjectTransactionRecoveryResult> recoverPersistence(
    WorkspaceAttachment workspace,
  ) => _persistenceCoordinator.recoverInterruptedTransactions(workspace);

  Future<ProjectAggregate> createProject({
    required WorkspaceAttachment workspace,
    required String userPrompt,
    String? chatSessionId,
    ModelConversationPort? client,
    String baseSystemPrompt = '',
    int? maxIterations,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
    QuestionAutonomy questionAutonomy = QuestionAutonomy.balanced,
  }) => _planningUseCase.createProject(
    workspace: workspace,
    userPrompt: userPrompt,
    chatSessionId: chatSessionId,
    client: client,
    baseSystemPrompt: baseSystemPrompt,
    maxIterations: maxIterations,
    onModelOutput: onModelOutput,
    cancellationToken: cancellationToken,
    questionAutonomy: questionAutonomy,
  );

  Future<ProjectCommandResult> runProjectForCommand(
    ProjectExecutionRequest request,
  ) => _executionUseCase.runProjectForCommand(request);

  Future<ProjectCommandResult> recoverProjectForCommand(
    ProjectRecoveryRequest request,
  ) => _executionUseCase.recoverProjectForCommand(request);

  Future<ProjectAggregate> retryRecoveryIncident({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
    required String incidentId,
  }) => _userCommands.retryRecoveryIncident(
    workspace: workspace,
    snapshot: snapshot,
    incidentId: incidentId,
  );

  Future<ProjectAggregate> answerOpenQuestion({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
    required String answer,
  }) => _userCommands.answerOpenQuestion(
    workspace: workspace,
    snapshot: snapshot,
    answer: answer,
  );

  Future<ProjectAggregate> addUserContext({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
    required String text,
  }) => _userCommands.addUserContext(
    workspace: workspace,
    snapshot: snapshot,
    text: text,
  );

  Future<ProjectAggregate> requestScopeChange({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
    required String context,
  }) => _userCommands.requestScopeChange(
    workspace: workspace,
    snapshot: snapshot,
    context: context,
  );

  Future<ProjectAggregate> compactMemory({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
    required List<String> coveredEntryIds,
    required String summary,
  }) => _userCommands.compactMemory(
    workspace: workspace,
    snapshot: snapshot,
    coveredEntryIds: coveredEntryIds,
    summary: summary,
  );

  Future<ProjectAggregate> pauseProject({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
  }) => _userCommands.pauseProject(workspace: workspace, snapshot: snapshot);

  Future<ProjectAggregate> clearTaskBlocker({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
  }) =>
      _userCommands.clearTaskBlocker(workspace: workspace, snapshot: snapshot);

  Future<ProjectAggregate> approvePlanRevision({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
  }) => _userCommands.approvePlanRevision(
    workspace: workspace,
    snapshot: snapshot,
  );

  Future<ProjectAggregate> rejectPlanRevision({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
  }) => _userCommands.rejectPlanRevision(
    workspace: workspace,
    snapshot: snapshot,
  );

  Future<ProjectAggregate> cancelProject({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
  }) => _userCommands.cancelProject(workspace: workspace, snapshot: snapshot);

  Future<ProjectAggregate> stopProject({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
  }) => _userCommands.stopProject(workspace: workspace, snapshot: snapshot);
}

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
  final TaskAggregate? activeTask;
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

class ProjectFilteredQuestions {
  final List<PendingProjectQuestion> blocking;
  final List<String> assumptions;

  const ProjectFilteredQuestions({
    required this.blocking,
    required this.assumptions,
  });
}
