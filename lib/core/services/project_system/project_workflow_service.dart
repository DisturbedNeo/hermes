import 'dart:async';
import 'dart:convert';

import 'package:hermes/core/helpers/json_parsing.dart';
import 'package:hermes/core/helpers/uuid.dart';
import 'package:hermes/core/models/compaction_settings.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/models/planning_metrics.dart';
import 'package:hermes/core/serialization/model_json.dart';
import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/models/task_system_settings.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/cancellation_token.dart';
import 'package:hermes/core/services/project_system/project_model_calls.dart';
import 'package:hermes/core/services/project_system/project_criterion_evaluator.dart';
import 'package:hermes/core/services/project_system/project_discovery_service.dart';
import 'package:hermes/core/services/project_system/project_evidence_service.dart';
import 'package:hermes/core/services/project_system/project_memory_service.dart';
import 'package:hermes/core/services/project_system/orchestration_contracts.dart';
import 'package:hermes/core/services/project_system/project_completion_service.dart';
import 'package:hermes/core/services/project_system/project_control_state_service.dart';
import 'package:hermes/core/services/project_system/project_lifecycle_service.dart';
import 'package:hermes/core/services/project_system/project_plan_revision_service.dart';
import 'package:hermes/core/services/project_system/project_decision_engine.dart';
import 'package:hermes/core/services/project_system/project_checkpoint.dart';
import 'package:hermes/core/services/project_system/project_plan_patch.dart';
import 'package:hermes/core/services/project_system/project_plan_validator.dart';
import 'package:hermes/core/services/project_system/project_state_models.dart';
import 'package:hermes/core/services/project_system/project_progress_monitor.dart';
import 'package:hermes/core/services/project_system/project_repository.dart';
import 'package:hermes/core/services/project_system/project_aggregate_repository.dart';
import 'package:hermes/core/services/project_system/project_aggregate_store.dart';
import 'package:hermes/core/services/project_system/project_handlers.dart';
import 'package:hermes/core/services/project_system/project_state_store.dart';
import 'package:hermes/core/services/project_system/project_command_service.dart';
import 'package:hermes/core/services/project_system/project_run_loop.dart';
import 'package:hermes/core/services/project_system/project_planning_coordinator.dart';
import 'package:hermes/core/services/project_system/project_recovery_service.dart';
import 'package:hermes/core/services/project_system/project_scheduler.dart';
import 'package:hermes/core/services/question_policy_service.dart';
import 'package:hermes/core/services/task_system/task_json.dart';
import 'package:hermes/core/services/task_system/task_model_output.dart';
import 'package:hermes/core/services/task_system/task_lifecycle_service.dart';
import 'package:hermes/core/services/task_system/task_service.dart';
import 'package:hermes/core/services/workspace_discovery_profile.dart';
import 'package:hermes/core/services/planning_runtime.dart';
import 'package:hermes/core/services/planning_structured_output.dart';
import 'package:hermes/core/services/workspace_persistence_coordinator.dart';
import 'package:path/path.dart' as path;

part 'project_execution_phase.dart';
part 'project_planning_phase.dart';
part 'project_persistence_phase.dart';
part 'project_command_phase.dart';

int taskStepLimit(TaskEffort effort) => switch (effort) {
  TaskEffort.small => 1,
  TaskEffort.medium => 4,
  TaskEffort.large => 6,
};

/// Owns the private runtime graph used by the project use cases.
///
/// This type is deliberately not the application-facing service. It contains
/// the execution engine and its injected ports; callers use the thin
/// [ProjectWorkflowService] façade below.
class ProjectWorkflowRuntime {
  ProjectWorkflowRuntime({
    required TaskService taskService,
    ProjectRepository? repository,
    ProjectPlanner? planner,
    ProjectCompletionEvaluator? completionEvaluator,
    ProjectScheduler? scheduler,
    ProjectMemoryService? memoryService,
    ProjectProgressMonitor? progressMonitor,
    WorkspacePersistenceCoordinator? persistenceCoordinator,
    ProjectAggregateRepository? aggregateRepository,
    ProjectStateStore? stateStore,
    ProjectCommandService? commandService,
    ProjectExecutionPort? executionPort,
    ProjectRecoveryPort? recoveryPort,
    PlanningToolCallRunner planningRunner = const PlanningToolCallRunner(),
    StructuredPlanningOutputService structuredOutput =
        const StructuredPlanningOutputService(),
    ProjectLifecycleService lifecycle = const ProjectLifecycleService(),
    TaskLifecycleService? taskLifecycle,
    ProjectCompletionService? completion,
    ProjectRecoveryService? recoveryService,
  }) : _taskService = taskService,
       _repository =
           repository ??
           ProjectRepository(
             coordinator:
                 persistenceCoordinator ?? taskService.repository.coordinator,
           ),
       _persistenceCoordinator =
           persistenceCoordinator ?? taskService.repository.coordinator,
       _providedAggregateRepository = aggregateRepository,
       _providedStateStore = stateStore,
       _providedCommandService = commandService,
       _providedExecutionPort = executionPort,
       _providedRecoveryPort = recoveryPort,
       _planner =
           planner ??
           ProjectModelCalls(
             toolService: taskService.toolService,
             planningRunner: planningRunner,
             structuredOutput: structuredOutput,
           ),
       _completionEvaluator =
           completionEvaluator ??
           ProjectModelCalls(
             toolService: taskService.toolService,
             planningRunner: planningRunner,
             structuredOutput: structuredOutput,
           ),
       _scheduler = scheduler ?? const ProjectScheduler(),
       _memoryService = memoryService ?? const ProjectMemoryService(),
       _progressMonitor = progressMonitor ?? const ProjectProgressMonitor(),
       lifecycleService = lifecycle,
       taskLifecycleService = taskLifecycle ?? const TaskLifecycleService(),
       completionService =
           completion ?? ProjectCompletionService(lifecycle: lifecycle),
       recoveryHandler = ProjectRecoveryHandler(
         recoveryService ?? const ProjectRecoveryService(),
       );

  final TaskService _taskService;
  final ProjectRepository _repository;
  final ProjectPlanner _planner;
  final ProjectCompletionEvaluator _completionEvaluator;
  final ProjectScheduler _scheduler;
  final ProjectMemoryService _memoryService;
  final ProjectProgressMonitor _progressMonitor;
  final WorkspacePersistenceCoordinator _persistenceCoordinator;
  final ProjectLifecycleService lifecycleService;
  final TaskLifecycleService taskLifecycleService;
  final ProjectCompletionService completionService;
  final ProjectRecoveryHandler recoveryHandler;
  final ProjectCommandService? _providedCommandService;
  final ProjectExecutionPort? _providedExecutionPort;
  final ProjectRecoveryPort? _providedRecoveryPort;
  final ProjectAggregateRepository? _providedAggregateRepository;
  final ProjectStateStore? _providedStateStore;
  late final ProjectAggregateRepository _aggregateRepository =
      _providedAggregateRepository ??
      ProjectAggregateRepository(
        projectRepository: _repository,
        taskRepository: _taskService.repository,
        coordinator: _persistenceCoordinator,
      );
  late final ProjectAggregateStore _aggregateStore = ProjectAggregateStore(
    aggregateRepository: _aggregateRepository,
    taskRepository: _taskService.repository,
  );
  late final ProjectPersistenceHandler _persistenceHandler =
      ProjectPersistenceHandler(
        aggregateStore: _aggregateStore,
        scheduler: _scheduler,
        controlState: _controlStateService,
      );
  late final ProjectStateStore _stateStore =
      _providedStateStore ??
      ProjectStateStore(
        projectRepository: _repository,
        aggregateRepository: _aggregateRepository,
        taskService: _taskService,
      );
  late final ProjectCommandService _commandService =
      _providedCommandService ??
      ProjectCommandService(
        stateStore: _stateStore,
        persistenceCoordinator: _persistenceCoordinator,
        runLoop: const ProjectRunLoop(),
      );
  late final ProjectExecutionPort _executionPort =
      _providedExecutionPort ??
      CallbackProjectExecutionPort(_runProjectForCommand);
  late final ProjectRecoveryPort _recoveryPort =
      _providedRecoveryPort ?? CallbackProjectRecoveryPort(_recoverForCommand);
  final QuestionPolicyService _questionPolicy = const QuestionPolicyService();
  final ProjectEvidenceService _evidenceService =
      const ProjectEvidenceService();
  final ProjectCriterionEvaluator _criterionEvaluator =
      const ProjectCriterionEvaluator();
  late final ProjectDiscoveryService _discoveryService =
      ProjectDiscoveryService(
        taskService: _taskService,
        memoryService: _memoryService,
      );
  late final ProjectPlanningHandler _planningHandler = ProjectPlanningHandler(
    coordinator: ProjectPlanningCoordinator(
      discovery: _discoveryService,
      planner: _planner,
      maxAutomaticRepairs: _maxAutomaticInitialPlanRepairs,
    ),
    revisionService: const ProjectPlanRevisionService(),
  );
  final ProjectDecisionEngine _decisionEngine = const ProjectDecisionEngine();
  final ProjectControlStateService _controlStateService =
      const ProjectControlStateService();
  final JsonEncoder _encoder = const JsonEncoder.withIndent('  ');

  // A malformed model plan is a recoverable planning failure. Keep the
  // retry bounded so a persistently invalid model response still becomes a
  // durable, actionable blocker rather than an unbounded model-call loop.
  static const _maxAutomaticInitialPlanRepairs = 2;

  ProjectRepository get repository => _repository;

  Future<ProjectCommandResult> execute(ProjectExecutionRequest request) =>
      _commandService.execute(request, port: _executionPort);

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
  ) => _stateStore.recoverInterruptedTransactions(workspace);

  Future<ProjectCommandResult> _runProjectForCommand(
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

  Future<ProjectCommandResult> _recoverForCommand(
    ProjectRecoveryRequest request,
  ) => _recoverProjectCore(
    workspace: request.workspace,
    snapshot: request.snapshot,
    onTaskUpdated: request.onTaskUpdated,
  );

  ProjectTaskNode? _activeProjectTask(ProjectDocument project) {
    final id = project.activeTaskId;
    return id == null ? null : project.taskById(id);
  }

  bool _isTerminalTask(ProjectTaskNode task) => switch (task.status) {
    TaskStatus.completed ||
    TaskStatus.failed ||
    TaskStatus.rejected ||
    TaskStatus.split ||
    TaskStatus.cancelled => true,
    _ => false,
  };

  List<ProjectTaskNode> _nonTerminalTasks(ProjectDocument project) =>
      project.tasks.where((task) => !_isTerminalTask(task)).toList();

  List<ProjectTaskNode> _upsertTask(
    ProjectDocument project,
    ProjectTaskNode replacement, {
    String? removeId,
  }) {
    final replaced = <ProjectTaskNode>[];
    var found = false;
    for (final task in project.tasks) {
      if (task.id == removeId) continue;
      if (task.id == replacement.id) {
        replaced.add(replacement);
        found = true;
      } else {
        replaced.add(task);
      }
    }
    if (!found) replaced.add(replacement);
    return replaced;
  }

  ProjectDocument _transitionProject({
    required ProjectDocument snapshot,
    required ProjectStatus to,
    required ProjectLifecycleTrigger trigger,
    String reason = '',
    String? taskId,
    ProjectBlocker? blocker,
    DateTime? now,
  }) => lifecycleService
      .transition(
        snapshot: snapshot,
        to: to,
        trigger: trigger,
        reason: reason,
        taskId: taskId,
        blocker: blocker,
        now: now,
      )
      .project;

  int _currentPlanRevision(ProjectDocument project) {
    var revision = 0;
    for (final item in project.planHistory) {
      if (item.revision > revision) revision = item.revision;
    }
    return revision;
  }

  Future<ProjectDocument> _startBatch({
    required String workspaceRoot,
    required ProjectDocument project,
    required int maxNewTasks,
    ProjectPersistenceContext? persistenceContext,
  }) async {
    final scheduled = _scheduler.schedule(project);
    final frontier = _scheduler.executionFrontier(
      scheduled.project,
      limit: maxNewTasks,
    );
    return _persistProject(
      workspaceRoot,
      scheduled.project.copyWith(
        currentBatchTaskIds: frontier.taskIds,
        currentBatchIndex: 0,
        currentBatchPlanRevision: frontier.planRevision,
        currentBatchProgressObserved: false,
        pendingReplanReason: null,
      ),
      persistenceContext: persistenceContext,
      checkpoint: ProjectPersistenceCheckpoint.frontierSelection,
    );
  }

  ProjectDocument _clearBatch(ProjectDocument project) {
    return project.copyWith(
      currentBatchTaskIds: const [],
      currentBatchIndex: 0,
      currentBatchPlanRevision: 0,
      currentBatchProgressObserved: false,
      pendingReplanReason: null,
    );
  }

  ProjectTaskNode? _currentBatchTask(ProjectDocument project) {
    final id = project.currentBatchTaskId;
    return id == null ? null : project.taskById(id);
  }

  ProjectDocument _advanceBatchCursor(
    ProjectDocument project,
    String completedTaskId,
  ) {
    final index = project.currentBatchTaskIds.indexOf(completedTaskId);
    if (index < project.currentBatchIndex) return project;
    return project.copyWith(currentBatchIndex: index + 1);
  }

  String _replanReasonForTriggers(
    Iterable<ProjectPlanRevisionTrigger> triggers,
  ) {
    final labels = [
      for (final trigger in triggers)
        switch (trigger) {
          ProjectPlanRevisionTrigger.taskFailed =>
            'A task failed and needs a safe recovery decision.',
          ProjectPlanRevisionTrigger.evidenceRejected =>
            'A required evidence item was rejected or became stale.',
          ProjectPlanRevisionTrigger.taskReplanRequested =>
            'The active task reported that the project plan needs revision.',
          ProjectPlanRevisionTrigger.scopeChanged =>
            'The project scope changed and the backlog must be reconciled.',
          ProjectPlanRevisionTrigger.workspaceChanged =>
            'A workspace assumption changed and the plan must be revalidated.',
          ProjectPlanRevisionTrigger.milestoneRoadmapChanged =>
            'A milestone boundary changed and the roadmap must be refreshed.',
          ProjectPlanRevisionTrigger.batchComplete =>
            'The configured execution batch completed.',
          ProjectPlanRevisionTrigger.noReadyTask =>
            'No ready task remained at a safe execution boundary.',
          _ => null,
        },
    ].whereType<String>();
    return labels.isEmpty
        ? 'The project plan needs revision.'
        : labels.join(' ');
  }

  Future<ProjectDocument> _hydrateProjectTasks(
    WorkspaceAttachment workspace,
    ProjectDocument project,
  ) => _stateStore.hydrate(workspace, project);

  Future<List<ProjectSummary>> listProjects(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
  }) {
    return _stateStore.list(workspace, chatSessionId: chatSessionId);
  }

  Future<ProjectDocument?> loadLatestProject(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
  }) async {
    final result = await loadLatestProjectResult(
      workspace,
      chatSessionId: chatSessionId,
    );
    return result.project;
  }

  Future<ProjectLoadResult> loadLatestProjectResult(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
  }) async {
    return _stateStore.loadLatest(workspace, chatSessionId: chatSessionId);
  }

  Future<ProjectDocument?> loadProject(
    WorkspaceAttachment workspace,
    String projectId, {
    String? chatSessionId,
  }) async {
    final result = await loadProjectResult(
      workspace,
      projectId,
      chatSessionId: chatSessionId,
    );
    return result.project;
  }

  Future<ProjectLoadResult> loadProjectResult(
    WorkspaceAttachment workspace,
    String projectId, {
    String? chatSessionId,
  }) async {
    return _stateStore.load(workspace, projectId, chatSessionId: chatSessionId);
  }

  Future<int> deleteProjectsForChatSession(
    WorkspaceAttachment workspace, {
    required String chatSessionId,
  }) async {
    return _stateStore.deleteForChatSession(
      workspace,
      chatSessionId: chatSessionId,
    );
  }

  Future<int> deleteOrphanedChatProjects(
    WorkspaceAttachment workspace, {
    required Set<String> retainedChatSessionIds,
  }) async {
    return _stateStore.deleteOrphaned(
      workspace,
      retainedChatSessionIds: retainedChatSessionIds,
    );
  }

  Future<ProjectDocument> updateProjectChatSessionId({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    required String chatSessionId,
  }) async {
    if (snapshot.chatSessionId == chatSessionId) return snapshot;
    final updated = snapshot.copyWith(
      chatSessionId: chatSessionId,
      updatedAt: DateTime.now(),
    );
    return _persistProject(workspace.rootPath, updated);
  }

  String encodeProject(ProjectDocument project) =>
      '${_encoder.convert(ModelJson.encode(project))}\n';

  Future<ProjectDocument> updateProject({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    required String rawJson,
  }) async {
    final parsed = ModelJson.decode<ProjectDocument>(
      TaskJson.parseObject(rawJson),
    );
    final updated = parsed.copyWith(
      id: snapshot.id,
      chatSessionId: snapshot.chatSessionId,
      createdAt: snapshot.createdAt,
      updatedAt: DateTime.now(),
    );
    return _persistProject(workspace.rootPath, updated);
  }

  Future<Task?> _loadActiveTask(
    WorkspaceAttachment workspace,
    ProjectDocument project,
  ) {
    final taskId = project.activeTaskId;
    if (taskId == null) return Future.value();
    return _taskService.loadTask(
      workspace,
      taskId,
      chatSessionId: project.chatSessionId,
      projectId: project.id,
    );
  }

  Future<ProjectDocument> _revisePlan({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required ProjectDocument project,
    required List<ProjectPlanRevisionTrigger> triggers,
    required String baseSystemPrompt,
    required ProjectPlanApprovalPolicy approvalPolicy,
    required QuestionAutonomy questionAutonomy,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    final debouncedTriggers = triggers.toSet().toList();
    final snapshot = await _discoveryService.collect(
      workspace: workspace,
      project: project,
      goalContext:
          'Original goal:\n${project.originalGoal}\n\nRefined goal:\n${project.refinedGoal}',
      cancellationToken: cancellationToken,
    );
    if (snapshot.workspaceProfile.requiredContextIssues.isNotEmpty) {
      return _blockProject(
        _clearBatch(project),
        ProjectBlockerType.validation,
        _initialPlanningBlockerMessage([
          for (final issue in snapshot.workspaceProfile.requiredContextIssues)
            {'code': issue.code, 'path': issue.path, 'message': issue.message},
        ]),
        DateTime.now(),
      );
    }
    final incremental = await _planner.revisePlanWithCommands(
      client: client,
      baseSystemPrompt: baseSystemPrompt,
      workspace: workspace,
      project: project,
      evidenceSnapshot: snapshot,
      triggers: debouncedTriggers,
      approvalPolicy: approvalPolicy,
      onModelOutput: onModelOutput,
      cancellationToken: cancellationToken,
    );
    final revised = _finishPlanRevision(
      revised: incremental.project,
      questionAutonomy: questionAutonomy,
      modelCalls: incremental.modelCalls,
      planningMetrics: incremental.planningMetrics,
      invalidPlan: !incremental.committed,
      awaitingApproval: incremental.awaitingApproval,
      planningError: incremental.error,
    );
    return revised.copyWith(
      id: project.id,
      persistenceRevision: project.persistenceRevision,
      createdAt: project.createdAt,
      chatSessionId: project.chatSessionId,
    );
  }

  ProjectDocument _finishPlanRevision({
    required ProjectDocument revised,
    required QuestionAutonomy questionAutonomy,
    required int modelCalls,
    required bool invalidPlan,
    required bool awaitingApproval,
    PlanningMetrics planningMetrics = const PlanningMetrics(),
    String? planningError,
  }) {
    revised = revised.copyWith(
      currentBatchTaskIds: const [],
      currentBatchIndex: 0,
      currentBatchPlanRevision: 0,
      currentBatchProgressObserved: false,
      pendingReplanReason: null,
      pendingReplanTriggers: const [],
      boundary: planningError == null && !awaitingApproval
          ? null
          : revised.boundary,
      diagnostics: revised.diagnostics.copyWith(
        projectModelCalls: revised.diagnostics.projectModelCalls + modelCalls,
        planRevisionAttempts: revised.diagnostics.planRevisionAttempts + 1,
        invalidPlanProposals:
            revised.diagnostics.invalidPlanProposals + (invalidPlan ? 1 : 0),
        planningMetrics: revised.diagnostics.planningMetrics.add(
          planningMetrics,
        ),
      ),
    );
    if (planningError != null && planningError.trim().isNotEmpty) {
      return _blockProject(
        revised,
        ProjectBlockerType.validation,
        'Incremental plan revision did not commit: ${planningError.trim()}',
        DateTime.now(),
      );
    }
    if (revised.openQuestions.isNotEmpty) {
      final filtered = _filterProjectQuestions(
        revised.openQuestions,
        autonomy: questionAutonomy,
      );
      final boundary = revised.copyWith(
        openQuestions: filtered.blocking,
        blocker: filtered.blocking.isEmpty && !awaitingApproval
            ? null
            : revised.blocker,
        updatedAt: DateTime.now(),
      );
      revised = _transitionProject(
        snapshot: boundary,
        to: filtered.blocking.isEmpty && !awaitingApproval
            ? ProjectStatus.active
            : boundary.status,
        trigger: ProjectLifecycleTrigger.planRevision,
        reason: filtered.blocking.isEmpty
            ? 'Plan revision questions were resolved.'
            : boundary.blocker?.message ?? 'Plan revision needs user input.',
        blocker: boundary.blocker,
        now: DateTime.now(),
      );
      revised = _recordAssumptions(
        revised,
        filtered.assumptions,
        sourceId: 'revision_${revised.nextRevision - 1}',
      );
    }
    return revised;
  }

  bool _invalidTaskRecoveryMadeProgress({
    required ProjectDocument before,
    required ProjectDocument after,
  }) {
    final currentTask = _activeProjectTask(after);
    if (currentTask != null && _validateProjectTask(currentTask, after).valid) {
      return true;
    }

    final previousTaskIds = before.tasks.map((task) => task.id).toSet();
    final refreshed = _scheduler.refreshReadiness(after).project;
    return refreshed.tasks.any(
      (task) =>
          !previousTaskIds.contains(task.id) &&
          _isSelectableTask(task) &&
          _validateProjectTask(task, refreshed).valid,
    );
  }

  bool _hasExecutableProjectTask(ProjectDocument project) {
    final currentTask = _activeProjectTask(project);
    return (currentTask != null &&
            _validateProjectTask(currentTask, project).valid) ||
        _scheduler.schedule(project).selectedTask != null;
  }

  bool _isSelectableTask(ProjectTaskNode task) {
    return task.status == TaskStatus.queued;
  }

  Future<ProjectDocument> _handleInvalidProjectTask({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required ProjectDocument project,
    required ProjectTaskNode task,
    required List<String> violations,
    required String baseSystemPrompt,
    required ProjectPlanApprovalPolicy approvalPolicy,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    final duplicateViolation = violations.any(
      (violation) =>
          violation.toLowerCase().contains('duplicate') ||
          violation.toLowerCase().contains('repeat'),
    );
    if (duplicateViolation) {
      final now = DateTime.now();
      final duplicate = _duplicateMatchForTask(project, task);
      if (duplicate is _QueuedDuplicateProjectTask) {
        return _transitionProject(
          snapshot: project.copyWith(
            tasks: _upsertTask(project, duplicate.task, removeId: task.id),
            blocker: null,
            updatedAt: now,
          ),
          to: ProjectStatus.active,
          trigger: ProjectLifecycleTrigger.planRevision,
          reason: 'A duplicate task was reconciled into the existing task.',
          now: now,
        );
      }
      if (duplicate is _FailedDuplicateProjectTask) {
        final retryTask = _retryTaskForFailedDuplicate(
          failedTask: duplicate.task,
          duplicateTask: task,
          violations: violations,
          now: now,
        );
        final rejected = task.copyWith(
          status: TaskStatus.rejected,
          rejectionReason: violations.join('\n'),
          updatedAt: now,
        );
        return _transitionProject(
          snapshot: project.copyWith(
            tasks: _upsertTask(
              project.copyWith(tasks: _upsertTask(project, rejected)),
              retryTask,
            ),
            blocker: null,
            decisions: [
              ...project.decisions,
              _decision(
                ProjectDecisionType.rejectTask,
                'Rejected repeated failed project task: ${task.title}',
                violations.join('\n'),
                task: rejected,
              ),
            ],
            updatedAt: now,
          ),
          to: ProjectStatus.active,
          trigger: ProjectLifecycleTrigger.planRevision,
          reason: 'A failed duplicate task was replaced with a retry.',
          now: now,
        );
      }
      final rejected = task.copyWith(
        status: TaskStatus.rejected,
        rejectionReason: violations.join('\n'),
        updatedAt: now,
      );
      return _transitionProject(
        snapshot: project.copyWith(
          tasks: _upsertTask(project, rejected),
          blocker: null,
          decisions: [
            ...project.decisions,
            _decision(
              ProjectDecisionType.rejectTask,
              'Rejected repeated project task: ${task.title}',
              violations.join('\n'),
              task: rejected,
            ),
          ],
          updatedAt: now,
        ),
        to: ProjectStatus.active,
        trigger: ProjectLifecycleTrigger.planRevision,
        reason: 'A repeated task was rejected from the project plan.',
        now: now,
      );
    }

    final incremental = await _planner.splitTaskWithCommands(
      client: client,
      baseSystemPrompt: baseSystemPrompt,
      workspace: workspace,
      project: project,
      oversizedTask: task,
      violations: violations,
      approvalPolicy: approvalPolicy,
      onModelOutput: onModelOutput,
      cancellationToken: cancellationToken,
    );
    if (!incremental.committed) {
      return _blockProject(
        project.copyWith(
          diagnostics: project.diagnostics.copyWith(
            projectModelCalls:
                project.diagnostics.projectModelCalls + incremental.modelCalls,
            planningMetrics: project.diagnostics.planningMetrics.add(
              incremental.planningMetrics.copyWith(
                recoveryAttempts:
                    incremental.planningMetrics.recoveryAttempts + 1,
                validationBlockerCount:
                    incremental.planningMetrics.validationBlockerCount + 1,
              ),
            ),
          ),
          updatedAt: DateTime.now(),
        ),
        ProjectBlockerType.validation,
        'Project task split did not commit: ${incremental.error ?? 'no safe split was produced.'}',
        DateTime.now(),
        taskId: task.id,
      );
    }
    final revisedTask = incremental.project.taskById(task.id);
    final splitMetrics = incremental.planningMetrics.copyWith(
      recoveryAttempts: incremental.planningMetrics.recoveryAttempts + 1,
      recoverySuccesses: incremental.planningMetrics.recoverySuccesses + 1,
    );
    final boundary = incremental.project.copyWith(
      blocker: incremental.awaitingApproval
          ? incremental.project.blocker
          : null,
      decisions: [
        ...incremental.project.decisions,
        _decision(
          ProjectDecisionType.splitTask,
          'Split invalid project task into bounded child tasks.',
          violations.join('\n'),
          task: revisedTask ?? task,
        ),
      ],
      diagnostics: incremental.project.diagnostics.copyWith(
        projectModelCalls:
            incremental.project.diagnostics.projectModelCalls +
            incremental.modelCalls,
        planningMetrics: incremental.project.diagnostics.planningMetrics.add(
          splitMetrics,
        ),
      ),
      updatedAt: DateTime.now(),
    );
    return _transitionProject(
      snapshot: boundary,
      to: incremental.awaitingApproval ? boundary.status : ProjectStatus.active,
      trigger: incremental.awaitingApproval
          ? ProjectLifecycleTrigger.approval
          : ProjectLifecycleTrigger.planRevision,
      reason: incremental.awaitingApproval
          ? boundary.blocker?.message ?? 'Plan revision approval is required.'
          : 'Task split committed after invalid task recovery.',
      blocker: boundary.blocker,
      now: DateTime.now(),
    );
  }

  ProjectEvaluation _evaluateTaskResult(
    ProjectTaskNode projectTask,
    TaskResult result,
    ProjectDocument project,
  ) {
    final accepted = result.status == TaskStatus.completed;
    return ProjectEvaluation(
      taskId: projectTask.id,
      taskAccepted: accepted,
      projectComplete: false,
      summary: result.summary,
      completedCriteria: const [],
      remainingCriteria: _remainingCriteria(project),
      newKnownFacts: [
        if (result.summary.trim().isNotEmpty) result.summary.trim(),
        if (result.memoryUpdate.trim().isNotEmpty) result.memoryUpdate.trim(),
      ],
      artifacts: result.artifacts,
      gateResults: result.gateResults,
      taskAdditions: const [],
      openQuestions: result.userQuestion?.trim().isNotEmpty == true
          ? [
              PendingProjectQuestion(
                id: 'question_${uuid.v7()}',
                question: result.userQuestion!.trim(),
                createdAt: DateTime.now(),
              ),
            ]
          : const [],
      failureReason: accepted ? null : result.error ?? result.summary,
      projectReplanRequested: result.projectReplanRequested,
    );
  }

  ProjectDocument _applyTaskEvidence({
    required ProjectDocument project,
    required ProjectTaskNode task,
    required TaskResult result,
    required DateTime evaluatedAt,
  }) {
    final evidence = _evidenceService.normalizeTaskResult(
      project: _projectForModel(project),
      task: task,
      result: result,
      evaluatedAt: evaluatedAt,
    );
    return _criterionEvaluator.evaluateDeterministically(
      project.copyWith(evidence: evidence, updatedAt: evaluatedAt),
      evaluatedAt: evaluatedAt,
    );
  }

  ProjectDocument _updateProjectState(
    ProjectDocument project,
    ProjectEvaluation evaluation,
    DateTime now, {
    required QuestionAutonomy questionAutonomy,
  }) {
    final task = _activeProjectTask(project);
    if (task == null) return project;
    final filteredQuestions = _filterProjectQuestions(
      evaluation.openQuestions,
      autonomy: questionAutonomy,
    );
    if (!evaluation.taskAccepted) {
      final failure = _taskFailure(evaluation);
      var failedTask = task.copyWith(
        status: TaskStatus.failed,
        rejectionReason: evaluation.failureReason,
        failureKey: failure.failureKey,
        updatedAt: now,
      );
      final recoveryUpdate = _recoveryUpdateForFailedTask(
        project: project,
        failedTask: failedTask,
        evaluation: evaluation,
        now: now,
      );
      failedTask = recoveryUpdate.failedTask;
      final tasks = _upsertTask(project, failedTask);
      final recoveryIncidents = recoveryUpdate.recoveryIncidents;
      final failedBudgetCount = _projectFailureBudgetCount(
        tasks.where((item) => item.status == TaskStatus.failed).toList(),
        recoveryIncidents,
      );
      final reachedFailureLimit = failedBudgetCount >= project.maxFailedTasks;
      final exhaustedIncident = recoveryUpdate.exhaustedIncident;
      final blockingFailure =
          failure.disposition == TaskGateFailureDisposition.blocking &&
          recoveryUpdate.incident == null;
      final failureBlocker = exhaustedIncident != null
          ? ProjectBlocker(
              type: ProjectBlockerType.recoveryFailed,
              message:
                  'Recovery incident `${exhaustedIncident.id}` reached the maximum repair attempt limit of ${exhaustedIncident.maxAttempts}.',
              taskId: failedTask.id,
              createdAt: now,
            )
          : reachedFailureLimit
          ? ProjectBlocker(
              type: ProjectBlockerType.maxFailures,
              message:
                  'Project reached the maximum failed task limit of ${project.maxFailedTasks}.',
              createdAt: now,
            )
          : blockingFailure
          ? ProjectBlocker(
              type: ProjectBlockerType.taskFailed,
              message: failure.summary,
              taskId: failedTask.id,
              createdAt: now,
            )
          : filteredQuestions.blocking.isNotEmpty
          ? ProjectBlocker(
              type: ProjectBlockerType.question,
              message: filteredQuestions.blocking.first.question,
              createdAt: now,
            )
          : null;
      final failureBase = project.copyWith(
        activeTaskId: null,
        tasks: [
          if (recoveryUpdate.recoveryTask != null) recoveryUpdate.recoveryTask!,
          ...tasks.where((item) => item.id != recoveryUpdate.recoveryTask?.id),
        ],
        recoveryIncidents: recoveryIncidents,
        openQuestions: filteredQuestions.blocking,
        blocker: failureBlocker,
        decisions: [
          ...project.decisions,
          _decision(
            ProjectDecisionType.evaluateTask,
            'Project task failed: ${task.title}',
            evaluation.failureReason ?? '',
            task: failedTask,
          ),
          if (recoveryUpdate.recoveryTask != null)
            _decision(
              ProjectDecisionType.createRecoveryTask,
              'Created recovery task for failed gate: ${recoveryUpdate.incident!.failedGateId}',
              recoveryUpdate.incident!.failureSummary,
              task: recoveryUpdate.recoveryTask,
            ),
        ],
        diagnostics: project.diagnostics.copyWith(
          userQuestions:
              project.diagnostics.userQuestions +
              filteredQuestions.blocking.length,
        ),
        updatedAt: now,
      );
      var updated = _transitionProject(
        snapshot: failureBase,
        to: failureBlocker == null
            ? ProjectStatus.active
            : (failureBlocker.type == ProjectBlockerType.question
                  ? ProjectStatus.waitingForUser
                  : ProjectStatus.blocked),
        trigger: ProjectLifecycleTrigger.taskReview,
        reason: failureBlocker?.message ?? 'The failed task was recorded.',
        taskId: failedTask.id,
        blocker: failureBlocker,
        now: now,
      );
      final incident = recoveryUpdate.incident;
      updated = _recordTaskMemory(
        project: updated,
        task: failedTask,
        evaluation: evaluation,
        assumptions: filteredQuestions.assumptions,
        accepted: false,
        recordFailureRisk: incident == null,
        timestamp: now,
      );
      if (incident != null) {
        updated = _memoryService
            .record(
              project: updated,
              kind: ProjectMemoryKind.risk,
              content:
                  'Unresolved recovery risk for ${incident.failedGateId}: ${incident.failureSummary}',
              sourceType: ProjectMemorySourceType.gate,
              sourceId: incident.id,
              confidence: ProjectMemoryConfidence.confirmed,
              protected: true,
              timestamp: now,
            )
            .project;
      }
      return updated;
    }
    final completedTask = task.copyWith(
      status: TaskStatus.completed,
      updatedAt: now,
    );
    final recoveryIncidents = _resolveRecoveryIncidentForTask(
      project.recoveryIncidents,
      completedTask,
      now,
    );
    final completionBlocker = filteredQuestions.blocking.isEmpty
        ? null
        : ProjectBlocker(
            type: ProjectBlockerType.question,
            message: filteredQuestions.blocking.first.question,
            createdAt: now,
          );
    final completionBase = project.copyWith(
      activeTaskId: null,
      tasks: [
        ...evaluation.taskAdditions,
        ..._upsertTask(project, completedTask),
      ],
      artifacts: _mergeArtifacts(project.artifacts, evaluation.artifacts),
      recoveryIncidents: recoveryIncidents,
      openQuestions: filteredQuestions.blocking,
      blocker: completionBlocker,
      decisions: [
        ...project.decisions,
        _decision(
          ProjectDecisionType.evaluateTask,
          'Accepted completed project task: ${task.title}',
          evaluation.summary,
          task: completedTask,
        ),
      ],
      diagnostics: project.diagnostics.copyWith(
        userQuestions:
            project.diagnostics.userQuestions +
            filteredQuestions.blocking.length,
      ),
      updatedAt: now,
    );
    var updated = _transitionProject(
      snapshot: completionBase,
      to: completionBlocker == null
          ? ProjectStatus.active
          : ProjectStatus.waitingForUser,
      trigger: ProjectLifecycleTrigger.taskReview,
      reason: completionBlocker?.message ?? 'The task completed successfully.',
      blocker: completionBlocker,
      now: now,
    );
    updated = _recordTaskMemory(
      project: updated,
      task: completedTask,
      evaluation: evaluation,
      assumptions: filteredQuestions.assumptions,
      accepted: true,
      timestamp: now,
    );
    final recoveryIncidentId = completedTask.recoveryIncidentId;
    if (recoveryIncidentId != null) {
      updated =
          _memoryService
              .resolveRisksForSource(
                project: updated,
                sourceId: recoveryIncidentId,
                resolution:
                    'Recovery incident $recoveryIncidentId was resolved by ${completedTask.title}.',
                timestamp: now,
              )
              ?.project ??
          updated;
    }
    return updated;
  }

  Future<ProjectDocument> _applyCompletionEvaluation({
    required ChatClient client,
    required ProjectDocument project,
    required String baseSystemPrompt,
    ProjectCompletionReviewReason? reviewReason,
    String? reviewMilestoneId,
    TaskModelOutputSink? onModelOutput,
    QuestionAutonomy questionAutonomy = QuestionAutonomy.balanced,
    CancellationToken? cancellationToken,
  }) async {
    if (project.isTerminal ||
        project.status == ProjectStatus.blocked ||
        project.openQuestions.isNotEmpty ||
        project.recoveryIncidents.any(
          (incident) =>
              incident.status == ProjectRecoveryIncidentStatus.active ||
              incident.status == ProjectRecoveryIncidentStatus.exhausted,
        ) ||
        _projectFailureBudgetCount(
              project.tasks
                  .where((task) => task.status == TaskStatus.failed)
                  .toList(),
              project.recoveryIncidents,
            ) >=
            project.maxFailedTasks) {
      return project;
    }
    final now = DateTime.now();
    final remainingByState = _remainingCriteria(project);
    if (remainingByState.isEmpty) {
      return _completeProjectFromEvidence(project, now);
    }
    if (reviewReason == null || !_hasReviewableCriterionEvidence(project)) {
      return _transitionProject(
        snapshot: project,
        to: ProjectStatus.active,
        trigger: ProjectLifecycleTrigger.taskReview,
        reason: 'No completion review is required at this boundary.',
        now: now,
      );
    }

    final evidenceFingerprint = _completionEvidenceFingerprint(project);
    final checkpoint = project.completionReviewCheckpoint;
    if (checkpoint?.reason == reviewReason &&
        checkpoint?.evidenceFingerprint == evidenceFingerprint &&
        checkpoint?.milestoneId == reviewMilestoneId) {
      return _transitionProject(
        snapshot: project,
        to: ProjectStatus.active,
        trigger: ProjectLifecycleTrigger.taskReview,
        reason: 'Completion evidence is unchanged since the last review.',
        now: now,
      );
    }

    final assessment = await _completionEvaluator.evaluateCompletion(
      client: client,
      baseSystemPrompt: baseSystemPrompt,
      project: project,
      onModelOutput: onModelOutput,
      cancellationToken: cancellationToken,
    );
    final assessedProject = project.copyWith(
      completionReviewCheckpoint: ProjectCompletionReviewCheckpoint(
        reason: reviewReason,
        evidenceFingerprint: evidenceFingerprint,
        milestoneId: reviewMilestoneId,
        reviewedAt: now,
      ),
      diagnostics: project.diagnostics.copyWith(
        projectModelCalls: project.diagnostics.projectModelCalls + 1,
      ),
    );
    if (assessment.openQuestions.isNotEmpty) {
      final filtered = _filterProjectQuestions(
        assessment.openQuestions,
        autonomy: questionAutonomy,
      );
      if (filtered.blocking.isEmpty) {
        final resumed = _transitionProject(
          snapshot: assessedProject.copyWith(blocker: null, updatedAt: now),
          to: ProjectStatus.active,
          trigger: ProjectLifecycleTrigger.taskReview,
          reason: 'Completion review questions were resolved automatically.',
          now: now,
        );
        return _recordAssumptions(
          resumed,
          filtered.assumptions,
          sourceId: 'completion_review',
        );
      }
      final waiting = _transitionProject(
        snapshot: assessedProject.copyWith(
          openQuestions: filtered.blocking,
          blocker: ProjectBlocker(
            type: ProjectBlockerType.question,
            message: filtered.blocking.first.question,
            createdAt: now,
          ),
          diagnostics: assessedProject.diagnostics.copyWith(
            userQuestions:
                assessedProject.diagnostics.userQuestions +
                filtered.blocking.length,
          ),
          updatedAt: now,
        ),
        to: ProjectStatus.waitingForUser,
        trigger: ProjectLifecycleTrigger.taskReview,
        reason: filtered.blocking.first.question,
        blocker: ProjectBlocker(
          type: ProjectBlockerType.question,
          message: filtered.blocking.first.question,
          createdAt: now,
        ),
        now: now,
      );
      return _recordAssumptions(
        waiting,
        filtered.assumptions,
        sourceId: 'completion_review',
      );
    }
    var reviewed = _criterionEvaluator.applyModelReview(
      assessedProject,
      projectComplete: assessment.complete,
      remainingCriteria: assessment.remainingCriteria,
      supportedCriterionIds: assessment.supportedCriterionIds,
      rationale: assessment.finalSummary,
      evaluatedAt: now,
    );
    reviewed = reviewed.copyWith(
      completionReviewCheckpoint: ProjectCompletionReviewCheckpoint(
        reason: reviewReason,
        evidenceFingerprint: _completionEvidenceFingerprint(reviewed),
        milestoneId: reviewMilestoneId,
        reviewedAt: now,
      ),
    );
    if (_remainingCriteria(reviewed).isEmpty) {
      return _completeProjectFromEvidence(
        reviewed,
        now,
        summary: assessment.finalSummary,
      );
    }
    return _transitionProject(
      snapshot: reviewed,
      to: ProjectStatus.active,
      trigger: ProjectLifecycleTrigger.taskReview,
      reason: 'Completion review left criteria outstanding.',
      now: now,
    );
  }

  bool _hasReviewableCriterionEvidence(ProjectDocument project) {
    for (final criterion in project.criteria) {
      if (!criterion.required ||
          criterion.status == ProjectCriterionStatus.satisfied ||
          criterion.status == ProjectCriterionStatus.invalidated ||
          (criterion.verificationMode != ProjectVerificationMode.modelReview &&
              criterion.verificationMode != ProjectVerificationMode.mixed)) {
        continue;
      }
      if (project.evidence.any(
        (item) =>
            item.criterionIds.contains(criterion.id) &&
            (item.status == ProjectEvidenceStatus.proposed ||
                item.status == ProjectEvidenceStatus.accepted),
      )) {
        return true;
      }
    }
    return false;
  }

  ProjectCompletionReviewReason? _completionReviewReason({
    required ProjectDocument project,
    required Set<String> newEvidenceIds,
    required String? endedMilestoneId,
    required bool batchEnded,
  }) {
    if (_activeProjectTask(project) == null &&
        _nonTerminalTasks(project).isEmpty) {
      return ProjectCompletionReviewReason.noRemainingTasks;
    }
    if (endedMilestoneId != null) {
      return ProjectCompletionReviewReason.milestoneEnded;
    }
    if (batchEnded) {
      return ProjectCompletionReviewReason.batchEnded;
    }
    final unresolved = project.criteria.where((criterion) {
      return criterion.required &&
          criterion.status != ProjectCriterionStatus.satisfied &&
          criterion.status != ProjectCriterionStatus.invalidated;
    }).toList();
    if (unresolved.length != 1) return null;
    final criterion = unresolved.single;
    if (criterion.verificationMode != ProjectVerificationMode.modelReview &&
        criterion.verificationMode != ProjectVerificationMode.mixed) {
      return null;
    }
    final hasNewRelevantEvidence = project.evidence.any(
      (item) =>
          newEvidenceIds.contains(item.id) &&
          item.criterionIds.contains(criterion.id) &&
          (item.status == ProjectEvidenceStatus.proposed ||
              item.status == ProjectEvidenceStatus.accepted),
    );
    return hasNewRelevantEvidence
        ? ProjectCompletionReviewReason.finalCriterionEvidence
        : null;
  }

  bool _isBatchEnd(ProjectDocument project, String taskId) {
    if (project.currentBatchTaskIds.isEmpty) return true;
    final taskIndex = project.currentBatchTaskIds.indexOf(taskId);
    return taskIndex < 0 || taskIndex == project.currentBatchTaskIds.length - 1;
  }

  String _completionEvidenceFingerprint(ProjectDocument project) {
    final criteria = [
      for (final criterion in project.criteria)
        '${criterion.id}:${criterion.status.name}:${criterion.notes}',
    ]..sort();
    final evidence = [
      for (final item in project.evidence)
        '${item.id}:${item.status.name}:${item.strength.name}:${item.criterionIds.toList()..sort()}',
    ]..sort();
    return jsonEncode({'criteria': criteria, 'evidence': evidence});
  }

  bool _isTerminalMilestoneStatus(ProjectMilestoneStatus status) {
    return status == ProjectMilestoneStatus.completed ||
        status == ProjectMilestoneStatus.blocked ||
        status == ProjectMilestoneStatus.cancelled;
  }

  ProjectDocument _completeProjectFromEvidence(
    ProjectDocument project,
    DateTime now, {
    String summary = '',
  }) {
    return completionService
        .completeFromEvidence(project: project, summary: summary, now: now)
        .project;
  }

  _ProjectTaskValidation _validateProjectTask(
    ProjectTaskNode task,
    ProjectDocument project,
  ) {
    final violations = <String>[];
    if (task.objective.trim().isEmpty) {
      violations.add('Task objective is empty.');
    }
    if (task.doneCriteria.isEmpty) {
      violations.add('Task has no done criteria.');
    }
    if (task.outOfScope.isEmpty) {
      violations.add('Task has no out-of-scope boundaries.');
    }
    final projectCriterionIds = project.criteria.map((item) => item.id).toSet();
    if (task.criterionIds.isEmpty) {
      violations.add('Task has no project criterion IDs.');
    }
    for (final criterionId in task.criterionIds) {
      if (!projectCriterionIds.contains(criterionId)) {
        violations.add('Task references unknown criterion $criterionId.');
      }
    }
    for (final expectation in task.expectedEvidence) {
      if (expectation.criterionIds.isEmpty) {
        violations.add(
          'Evidence expectation ${expectation.id} has no criterion IDs.',
        );
      }
      for (final criterionId in expectation.criterionIds) {
        if (!projectCriterionIds.contains(criterionId)) {
          violations.add(
            'Evidence expectation ${expectation.id} references unknown criterion $criterionId.',
          );
        } else if (!task.criterionIds.contains(criterionId)) {
          violations.add(
            'Evidence expectation ${expectation.id} references criterion $criterionId outside the task.',
          );
        }
      }
    }
    if (task.recoveryIncidentId == null &&
        _knownFingerprints(
          project,
          excludingTaskId: task.id,
        ).contains(task.fingerprint)) {
      violations.add(
        'Task duplicates previous, current, failed, or queued work.',
      );
    }
    if (task.recoveryIncidentId == null &&
        project.decisions.any(
          (decision) =>
              decision.taskPrompt?.trim().isNotEmpty == true &&
              _normalise(decision.taskPrompt!) == _normalise(task.objective),
        )) {
      violations.add('Task repeats a previous project task prompt.');
    }
    if (_normalise(task.objective) == _normalise(project.refinedGoal) ||
        _normalise(task.objective) == _normalise(project.originalGoal)) {
      violations.add('Task objective matches the whole project goal.');
    }
    if (_looksOversized(task.objective)) {
      violations.add('Task objective is too broad for a project task.');
    }
    if (task.criterionIds.length > 3) {
      violations.add('Task covers too many success criteria.');
    }
    if (project.criteria.length > 1 &&
        task.criterionIds.length >= project.criteria.length) {
      violations.add('Task covers the entire project success criteria set.');
    }
    if (task.doneCriteria.length > 5) {
      violations.add('Task has too many done criteria.');
    }
    if (task.objective.length > 700) {
      violations.add('Task objective is too long.');
    }
    return _ProjectTaskValidation(violations.isEmpty, violations);
  }

  _DuplicateProjectTaskMatch? _duplicateMatchForTask(
    ProjectDocument project,
    ProjectTaskNode task,
  ) {
    if (task.recoveryIncidentId != null) return null;
    final fingerprint = task.fingerprint;
    for (final queued in project.tasks) {
      if (queued.id != task.id &&
          queued.status == TaskStatus.queued &&
          queued.fingerprint == fingerprint) {
        return _QueuedDuplicateProjectTask(queued);
      }
    }
    final current = _activeProjectTask(project);
    if (current != null &&
        current.id != task.id &&
        current.fingerprint == fingerprint) {
      return _QueuedDuplicateProjectTask(current);
    }
    for (final failed in project.tasks.where(
      (item) => item.status == TaskStatus.failed,
    )) {
      if (failed.id != task.id &&
          failed.status == TaskStatus.failed &&
          failed.recoveryIncidentId == null &&
          failed.fingerprint == fingerprint) {
        return _FailedDuplicateProjectTask(failed);
      }
    }
    return null;
  }

  ProjectTaskNode _retryTaskForFailedDuplicate({
    required ProjectTaskNode failedTask,
    required ProjectTaskNode duplicateTask,
    required List<String> violations,
    required DateTime now,
  }) {
    final criteria = <String>{
      ...failedTask.criterionIds,
      ...duplicateTask.criterionIds,
    }.toList();
    final objective =
        'Retry failed project task after addressing the previous failure: ${failedTask.objective}';
    return ProjectTaskNode(
      id: 'project_retry_${uuid.v7()}',
      title: 'Retry ${failedTask.title}',
      objective: objective,
      criterionIds: criteria,
      doneCriteria: duplicateTask.doneCriteria.isEmpty
          ? failedTask.doneCriteria
          : duplicateTask.doneCriteria,
      outOfScope: duplicateTask.outOfScope.isEmpty
          ? failedTask.outOfScope
          : duplicateTask.outOfScope,
      context: [
        ...failedTask.context,
        ...duplicateTask.context,
        if (failedTask.rejectionReason?.trim().isNotEmpty == true)
          'Previous failure: ${failedTask.rejectionReason!.trim()}',
        'Duplicate proposal was converted into a retry instead of halting the project.',
        ...violations,
      ],
      expectedEvidence: _replacementExpectedEvidence(
        source: failedTask.expectedEvidence,
        additions: duplicateTask.expectedEvidence,
        criterionIds: criteria,
        idPrefix: 'retry_expectation',
      ),
      expectedArtifacts: duplicateTask.expectedArtifacts.isEmpty
          ? failedTask.expectedArtifacts
          : duplicateTask.expectedArtifacts,
      readPaths: duplicateTask.readPaths.isEmpty
          ? failedTask.readPaths
          : duplicateTask.readPaths,
      writePaths: duplicateTask.writePaths.isEmpty
          ? failedTask.writePaths
          : duplicateTask.writePaths,
      status: TaskStatus.queued,
      recoveryIncidentId: null,
      fingerprint: projectTaskFingerprint(objective, criteria),
      rejectionReason: null,
      createdAt: now,
      updatedAt: now,
    );
  }

  bool _looksOversized(String value) {
    final text = _normalise(value);
    return text.contains('entire project') ||
        text.contains('whole project') ||
        text.contains('complete the project') ||
        text.contains('finish the project') ||
        text.contains('build the app') ||
        text.contains('implement all') ||
        text.contains('end to end') ||
        text.contains('end-to-end');
  }

  TaskPlanningContext _planningContext(
    ProjectDocument project,
    ProjectTaskNode task,
  ) {
    final plan = project.plan;
    final memoryContext = _memoryService.selectContext(
      project: project,
      task: task,
    );
    return TaskPlanningContext(
      projectGoal: plan.refinedGoal,
      projectTaskTitle: task.title,
      projectTaskObjective: task.objective,
      knownFacts: [...memoryContext.lines, ...task.context],
      doneCriteria: task.doneCriteria,
      outOfScope: task.outOfScope,
      expectedArtifacts: task.expectedArtifacts
          .map(
            (artifact) => TaskArtifact(
              path: artifact.path,
              description: artifact.description,
              kind: artifact.kind,
            ),
          )
          .toList(),
      requiredGates: _requiredGatesForTask(project, task),
      criterionIds: task.criterionIds,
      criteria: [
        for (final criterion in plan.criteria)
          if (task.criterionIds.contains(criterion.id))
            TaskProjectCriterion(
              id: criterion.id,
              statement: criterion.statement,
              required: criterion.required,
              verificationMode: criterion.verificationMode.name,
            ),
      ],
      expectedEvidence: [
        for (final expectation in task.expectedEvidence)
          TaskProjectEvidenceExpectation(
            id: expectation.id,
            type: _projectEvidenceTypeWire(expectation.type),
            criterionIds: expectation.criterionIds,
            description: expectation.description,
            required: expectation.required,
            sourceRef: expectation.sourceRef,
            details: expectation.details,
          ),
      ],
      readPaths: task.readPaths,
      writePaths: task.writePaths,
      maxSteps: taskStepLimit(task.effort),
    );
  }

  _RecoveryUpdate _recoveryUpdateForFailedTask({
    required ProjectDocument project,
    required ProjectTaskNode failedTask,
    required ProjectEvaluation evaluation,
    required DateTime now,
  }) {
    final recoveryFailure = _recoveryFailureFor(
      failedTask: failedTask,
      evaluation: evaluation,
    );
    if (recoveryFailure == null) {
      return _RecoveryUpdate(
        failedTask: failedTask,
        recoveryIncidents: project.recoveryIncidents,
      );
    }

    final existing = _matchingRecoveryIncident(
      project.recoveryIncidents,
      recoveryFailure,
      failedTask.recoveryIncidentId,
    );
    final isRecoveryAttempt = failedTask.recoveryIncidentId != null;
    final incidentId = existing?.id ?? 'recovery_${uuid.v7()}';
    final nextAttemptCount =
        (existing?.attemptCount ?? 0) + (isRecoveryAttempt ? 1 : 0);
    final status =
        nextAttemptCount >=
            (existing?.maxAttempts ??
                ProjectRecoveryIncident.defaultMaxAttempts)
        ? ProjectRecoveryIncidentStatus.exhausted
        : ProjectRecoveryIncidentStatus.active;
    final linkedFailedTask = failedTask.copyWith(
      recoveryIncidentId: incidentId,
    );
    final recoveryTask = status == ProjectRecoveryIncidentStatus.active
        ? _recoveryTaskForIncident(
            incidentId: incidentId,
            sourceTask: failedTask,
            failure: recoveryFailure,
            attemptNumber: nextAttemptCount + 1,
            now: now,
          )
        : null;
    final incident =
        (existing ??
                ProjectRecoveryIncident(
                  id: incidentId,
                  status: ProjectRecoveryIncidentStatus.active,
                  sourceTaskIds: const [],
                  sourceTaskTitles: const [],
                  failedGateId: recoveryFailure.gateResult.gateId,
                  command: recoveryFailure.command,
                  workingDirectory: recoveryFailure.workingDirectory,
                  failureSummary: recoveryFailure.summary,
                  attemptCount: 0,
                  maxAttempts: ProjectRecoveryIncident.defaultMaxAttempts,
                  recoveryTaskIds: const [],
                  createdAt: now,
                  updatedAt: now,
                ))
            .copyWith(
              status: status,
              sourceTaskIds: _appendUnique(
                existing?.sourceTaskIds ?? const [],
                failedTask.id,
              ),
              sourceTaskTitles: _appendUnique(
                existing?.sourceTaskTitles ?? const [],
                failedTask.title,
              ),
              failedGateId: recoveryFailure.gateResult.gateId,
              command: recoveryFailure.command,
              workingDirectory: recoveryFailure.workingDirectory,
              failureSummary: recoveryFailure.summary,
              attemptCount: nextAttemptCount,
              recoveryTaskIds: recoveryTask == null
                  ? existing?.recoveryTaskIds ?? const []
                  : _appendUnique(
                      existing?.recoveryTaskIds ?? const [],
                      recoveryTask.id,
                    ),
              updatedAt: now,
              resolvedAt: status == ProjectRecoveryIncidentStatus.exhausted
                  ? now
                  : null,
            );
    return _RecoveryUpdate(
      failedTask: linkedFailedTask,
      recoveryIncidents: _upsertRecoveryIncident(
        project.recoveryIncidents,
        incident,
      ),
      incident: incident,
      recoveryTask: recoveryTask,
      exhaustedIncident: status == ProjectRecoveryIncidentStatus.exhausted
          ? incident
          : null,
    );
  }

  _RecoveryFailure? _recoveryFailureFor({
    required ProjectTaskNode failedTask,
    required ProjectEvaluation evaluation,
  }) {
    final failedGate = evaluation.gateResults
        .where(
          (result) =>
              result.status == TaskGateStatus.failed &&
              result.details['required'] == true,
        )
        .where(
          (result) =>
              result.failureDisposition ==
                  TaskGateFailureDisposition.repairable ||
              failedTask.recoveryIncidentId != null,
        )
        .firstOrNull;
    if (failedGate == null) return null;
    final command = _gateFailureCommand(failedGate);
    final workingDirectory = jsonNullableString(
      failedGate.details['workingDirectory'] ??
          failedGate.details['working_directory'],
    );
    final summary = [
      failedGate.summary,
      _gateDiagnosticSummary(failedGate),
      if (evaluation.failureReason?.trim().isNotEmpty == true)
        evaluation.failureReason!.trim(),
    ].where((item) => item.trim().isNotEmpty).join('\n\n');
    return _RecoveryFailure(
      gateResult: failedGate,
      command: command,
      workingDirectory: workingDirectory,
      summary: _cap(summary.isEmpty ? 'Required gate failed.' : summary, 2000),
    );
  }

  String _gateDiagnosticSummary(TaskGateResult result) {
    final unresolved = result.details['unresolvedErrors'];
    if (unresolved is! List) return '';
    final lines = unresolved.whereType<Map>().take(10).map((raw) {
      final item = jsonMap(raw);
      final code = jsonString(item['code'], fallback: 'unknown_tool_error');
      final toolName = jsonString(item['toolName'], fallback: 'tool');
      final operation = jsonString(item['operationKey']);
      final message = jsonString(item['message']);
      return '- $code ($toolName${operation.isEmpty ? '' : ', $operation'}): $message';
    }).toList();
    return lines.isEmpty ? '' : 'Unresolved diagnostics:\n${lines.join('\n')}';
  }

  TaskFailure _taskFailure(ProjectEvaluation evaluation) {
    final gate = evaluation.gateResults
        .where(
          (result) =>
              result.status == TaskGateStatus.failed &&
              result.details['required'] == true,
        )
        .firstOrNull;
    final unresolved = gate?.details['unresolvedErrors'];
    final advisory = gate?.details['advisoryErrors'];
    final resolved = gate?.details['resolvedErrors'];
    final errorMaps = unresolved is List
        ? unresolved.whereType<Map>().map(jsonMap).toList()
        : const <Map<String, dynamic>>[];
    final errorCodes =
        errorMaps
            .map((item) => jsonString(item['code']))
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final callIds = errorMaps
        .map((item) => jsonString(item['callId']))
        .where((item) => item.isNotEmpty)
        .take(10)
        .toList();
    final operationKeys =
        errorMaps
            .map((item) => jsonString(item['operationKey']))
            .where((item) => item.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final disposition =
        gate?.failureDisposition ?? TaskGateFailureDisposition.blocking;
    final summary = evaluation.failureReason?.trim().isNotEmpty == true
        ? evaluation.failureReason!.trim()
        : gate?.summary ?? 'Task execution failed.';
    final keyParts = [
      gate?.gateId ?? 'execution',
      ...errorCodes,
      ...operationKeys,
      if (errorCodes.isEmpty && operationKeys.isEmpty) _normalise(summary),
    ];
    return TaskFailure(
      gateId: gate?.gateId,
      disposition: disposition,
      failureKey: _cap(keyParts.join('|'), 500),
      summary: _cap(summary, 2000),
      errorCodes: errorCodes,
      toolCallIds: callIds,
      advisoryErrorCount: advisory is List ? advisory.length : 0,
      resolvedErrorCount: resolved is List ? resolved.length : 0,
      unresolvedErrorCount: unresolved is List ? unresolved.length : 0,
    );
  }

  String? _gateFailureCommand(TaskGateResult result) {
    final direct = jsonNullableString(result.details['command']);
    if (direct != null) return direct;
    final failedCommands = result.details['failedCommands'];
    if (failedCommands is List && failedCommands.isNotEmpty) {
      final first = failedCommands.first;
      if (first is Map) return jsonNullableString(first['command']);
    }
    return null;
  }

  ProjectRecoveryIncident? _matchingRecoveryIncident(
    List<ProjectRecoveryIncident> incidents,
    _RecoveryFailure failure,
    String? preferredIncidentId,
  ) {
    if (preferredIncidentId != null) {
      final preferred = incidents
          .where((incident) => incident.id == preferredIncidentId)
          .firstOrNull;
      if (preferred != null) return preferred;
    }
    final key = _recoveryIncidentKey(
      gateId: failure.gateResult.gateId,
      command: failure.command,
      workingDirectory: failure.workingDirectory,
      summary: failure.summary,
    );
    return incidents.where((incident) {
      return incident.status == ProjectRecoveryIncidentStatus.active &&
          _recoveryIncidentKey(
                gateId: incident.failedGateId,
                command: incident.command,
                workingDirectory: incident.workingDirectory,
                summary: incident.failureSummary,
              ) ==
              key;
    }).firstOrNull;
  }

  String _recoveryIncidentKey({
    required String gateId,
    required String? command,
    required String? workingDirectory,
    required String summary,
  }) {
    final commandPart = command?.trim().isNotEmpty == true
        ? command!.trim()
        : _cap(_normalise(summary), 160);
    return [
      _normalise(gateId),
      _normalise(commandPart),
      _normalise(workingDirectory ?? '.'),
    ].join('|');
  }

  List<TaskEvidenceExpectation> _replacementExpectedEvidence({
    required Iterable<TaskEvidenceExpectation> source,
    required Iterable<TaskEvidenceExpectation> additions,
    required Iterable<String> criterionIds,
    required String idPrefix,
  }) {
    final validCriteria = criterionIds.toSet();
    final merged = <String, TaskEvidenceExpectation>{};
    for (final expectation in [...source, ...additions]) {
      final linkedCriteria = expectation.criterionIds
          .where(validCriteria.contains)
          .toSet()
          .toList();
      if (linkedCriteria.isEmpty) continue;
      final normalized = TaskEvidenceExpectation(
        id: expectation.id,
        type: expectation.type,
        criterionIds: linkedCriteria,
        description: expectation.description,
        required: expectation.required,
        sourceRef: expectation.sourceRef,
        details: expectation.details,
      );
      final signature = _evidenceExpectationSignature(normalized);
      final existing = merged[signature];
      merged[signature] = existing == null
          ? normalized
          : TaskEvidenceExpectation(
              id: normalized.id,
              type: normalized.type,
              criterionIds: normalized.criterionIds,
              description: normalized.description,
              required: existing.required || normalized.required,
              sourceRef: normalized.sourceRef,
              details: normalized.details,
            );
    }
    return [
      for (final expectation in merged.values)
        TaskEvidenceExpectation(
          id: '${idPrefix}_${uuid.v7()}',
          type: expectation.type,
          criterionIds: expectation.criterionIds,
          description: expectation.description,
          required: expectation.required,
          sourceRef: expectation.sourceRef,
          details: expectation.details,
        ),
    ];
  }

  String _evidenceExpectationSignature(TaskEvidenceExpectation expectation) {
    final criteria = [...expectation.criterionIds]..sort();
    return [
      expectation.type.name,
      _normalise(expectation.sourceRef ?? ''),
      criteria.join(','),
    ].join('|');
  }

  ProjectTaskNode _recoveryTaskForIncident({
    required String incidentId,
    required ProjectTaskNode sourceTask,
    required _RecoveryFailure failure,
    required int attemptNumber,
    required DateTime now,
  }) {
    final command = failure.command?.trim();
    final gateTarget = command?.isNotEmpty == true
        ? '${failure.gateResult.gateId}: $command'
        : failure.gateResult.gateId;
    final objective = 'Restore required project health gate: $gateTarget';
    final gateType =
        command?.isNotEmpty == true ||
            failure.gateResult.gateId == 'command_passes'
        ? ProjectEvidenceType.command
        : failure.gateResult.gateId == 'human_approval'
        ? ProjectEvidenceType.userApproval
        : ProjectEvidenceType.gate;
    final gateSourceRef = command?.isNotEmpty == true
        ? command
        : failure.gateResult.gateId;
    final recoveryGateExpectation = TaskEvidenceExpectation(
      id: 'recovery_gate_expectation',
      type: gateType,
      criterionIds: sourceTask.criterionIds,
      description: 'The required recovery gate passes: $gateTarget.',
      required: true,
      sourceRef: gateSourceRef,
      details: failure.gateResult.details,
    );
    return ProjectTaskNode(
      id: 'project_recovery_${uuid.v7()}',
      title: 'Recover project health',
      objective: objective,
      criterionIds: sourceTask.criterionIds,
      doneCriteria: [
        'Diagnose why the required gate is failing.',
        'Make the smallest safe repair needed to restore the gate.',
        if (command?.isNotEmpty == true)
          'Run `$command` successfully before completing this task.'
        else
          'Rerun the failed required gate successfully before completing this task.',
      ],
      outOfScope: const [
        'Do not start unrelated feature work.',
        'Do not expand the original project scope.',
      ],
      context: [
        'Recovery incident: $incidentId',
        'Original task: ${sourceTask.title}',
        'Original objective: ${sourceTask.objective}',
        'Failed gate: ${failure.gateResult.gateId}',
        if (command?.isNotEmpty == true) 'Failed command: $command',
        if (failure.workingDirectory?.trim().isNotEmpty == true)
          'Working directory: ${failure.workingDirectory}',
        'Failure summary:\n${failure.summary}',
        'Recovery attempt: $attemptNumber',
      ],
      readPaths: sourceTask.readPaths,
      writePaths: sourceTask.writePaths,
      expectedEvidence: _replacementExpectedEvidence(
        source: sourceTask.expectedEvidence,
        additions: [recoveryGateExpectation],
        criterionIds: sourceTask.criterionIds,
        idPrefix: 'recovery_expectation',
      ),
      expectedArtifacts: const [],
      status: TaskStatus.queued,
      recoveryIncidentId: incidentId,
      fingerprint: projectTaskFingerprint(objective, [
        incidentId,
        'attempt_$attemptNumber',
      ]),
      rejectionReason: null,
      createdAt: now,
      updatedAt: now,
    );
  }

  List<ProjectRecoveryIncident> _upsertRecoveryIncident(
    List<ProjectRecoveryIncident> incidents,
    ProjectRecoveryIncident incident,
  ) {
    var replaced = false;
    final next = <ProjectRecoveryIncident>[];
    for (final current in incidents) {
      if (current.id == incident.id) {
        next.add(incident);
        replaced = true;
      } else {
        next.add(current);
      }
    }
    if (!replaced) next.add(incident);
    return next;
  }

  List<ProjectRecoveryIncident> _resolveRecoveryIncidentForTask(
    List<ProjectRecoveryIncident> incidents,
    ProjectTaskNode completedTask,
    DateTime now,
  ) {
    final incidentId = completedTask.recoveryIncidentId;
    if (incidentId == null) return incidents;
    return [
      for (final incident in incidents)
        incident.id == incidentId &&
                incident.status == ProjectRecoveryIncidentStatus.active
            ? incident.copyWith(
                status: ProjectRecoveryIncidentStatus.resolved,
                updatedAt: now,
                resolvedAt: now,
              )
            : incident,
    ];
  }

  List<TaskGate> _requiredGatesForTask(
    ProjectDocument project,
    ProjectTaskNode task,
  ) {
    final expectedGates = <TaskGate>[
      for (final expectation in task.expectedEvidence)
        if (expectation.required &&
            expectation.type == ProjectEvidenceType.command &&
            expectation.sourceRef?.trim().isNotEmpty == true)
          TaskGate(
            id: 'command_passes',
            required: true,
            scope: 'task',
            params: {
              'command': expectation.sourceRef!.trim(),
              ...expectation.details,
            },
            description: expectation.description,
          )
        else if (expectation.required &&
            expectation.type == ProjectEvidenceType.gate &&
            expectation.sourceRef?.trim().isNotEmpty == true)
          TaskGate(
            id: expectation.sourceRef!.trim(),
            required: true,
            scope: 'task',
            params: expectation.details,
            description: expectation.description,
          )
        else if (expectation.required &&
            expectation.type == ProjectEvidenceType.userApproval)
          TaskGate(
            id: 'human_approval',
            required: true,
            scope: 'task',
            params: expectation.details,
            description: expectation.description,
          ),
    ];
    final incidentId = task.recoveryIncidentId;
    if (incidentId == null) return expectedGates;
    final incident = project.recoveryIncidents
        .where((item) => item.id == incidentId)
        .firstOrNull;
    if (incident == null) return expectedGates;
    return [
      ...expectedGates,
      TaskGate(
        id: incident.failedGateId,
        required: true,
        scope: 'task',
        params: {
          if (incident.command?.trim().isNotEmpty == true)
            'command': incident.command,
          if (incident.workingDirectory?.trim().isNotEmpty == true)
            'working_directory': incident.workingDirectory,
        },
        description: 'Recovery incident ${incident.id} must be resolved.',
      ),
    ];
  }

  int _projectFailureBudgetCount(
    List<ProjectTaskNode> failedTasks,
    List<ProjectRecoveryIncident> recoveryIncidents,
  ) {
    final nonRecoveryFailures = failedTasks
        .where(
          (task) =>
              task.status == TaskStatus.failed &&
              task.recoveryIncidentId == null,
        )
        .map(
          (task) =>
              task.failureKey ??
              '${task.fingerprint}|${_normalise(task.rejectionReason ?? '')}',
        )
        .toSet()
        .length;
    final exhaustedIncidents = recoveryIncidents
        .where(
          (incident) =>
              incident.status == ProjectRecoveryIncidentStatus.exhausted,
        )
        .length;
    return nonRecoveryFailures + exhaustedIncidents;
  }

  List<String> _appendUnique(List<String> current, String value) {
    if (value.trim().isEmpty || current.contains(value)) return current;
    return [...current, value];
  }

  TaskResult _taskResultFromTask(ProjectTaskNode projectTask, Task task) {
    final latestRun = task.runs.isEmpty ? null : task.runs.last;
    final artifacts = <TaskArtifact>[
      for (final run in task.runs)
        for (final artifact in run.artifacts)
          TaskArtifact(
            id: 'artifact_${uuid.v7()}',
            taskId: projectTask.id,
            runId: run.runId,
            path: artifact.path,
            description: artifact.description ?? '',
            kind: artifact.kind,
            createdAt: artifact.createdAt ?? DateTime.now(),
          ),
    ];
    return TaskResult(
      taskId: task.id,
      status: task.status,
      summary: latestRun?.summary ?? task.memorySummary,
      memoryUpdate: latestRun?.memoryUpdate ?? task.memorySummary,
      artifacts: artifacts,
      gateResults: latestRun?.gateResults ?? const [],
      evidenceClaims: [for (final run in task.runs) ...run.evidenceClaims],
      finalRunId: latestRun?.runId,
      toolCallCount: task.runs.fold<int>(
        0,
        (sum, run) => sum + run.toolCalls.length,
      ),
      userQuestion: task.pendingQuestion?.question,
      error: latestRun?.error,
      projectReplanRequested: task.runs.any(
        (run) =>
            run.status == TaskRunStatus.needsReplan ||
            (run.replanReason?.trim().isNotEmpty ?? false),
      ),
    );
  }

  String _projectEvidenceTypeWire(ProjectEvidenceType type) => switch (type) {
    ProjectEvidenceType.taskClaim => 'task_claim',
    ProjectEvidenceType.userApproval => 'user_approval',
    _ => type.name,
  };

  (ProjectBlockerType, String)? _taskBlocker(Task task) {
    if (task.pendingApproval != null) {
      return (
        ProjectBlockerType.taskEditApproval,
        task.pendingApproval!.reason,
      );
    }
    if (task.pendingQuestion != null) {
      return (ProjectBlockerType.taskBlocked, task.pendingQuestion!.question);
    }
    if (task.status == TaskStatus.blocked) {
      return (
        ProjectBlockerType.taskBlocked,
        'Task `${task.title}` is blocked.',
      );
    }
    return null;
  }

  ProjectDocument _syncCurrentTaskFromTask(
    ProjectDocument project,
    Task task,
    DateTime now,
  ) {
    final current = _activeProjectTask(project);
    if (current == null) return project;
    final nextStatus = switch (task.status) {
      TaskStatus.completed => TaskStatus.completed,
      TaskStatus.failed => TaskStatus.failed,
      TaskStatus.cancelled => TaskStatus.cancelled,
      _ => TaskStatus.running,
    };
    return project.copyWith(
      tasks: _upsertTask(
        project,
        current.copyWith(status: nextStatus, updatedAt: now),
      ),
      activeTaskId: task.isTerminal ? null : current.id,
      updatedAt: now,
    );
  }

  ProjectDocument _waitingForUser(ProjectDocument project, DateTime now) {
    final blocker =
        project.blocker ??
        (project.openQuestions.isEmpty
            ? null
            : ProjectBlocker(
                type: ProjectBlockerType.question,
                message: project.openQuestions.first.question,
                createdAt: now,
              ));
    final prepared = project.copyWith(blocker: blocker, updatedAt: now);
    return lifecycleService
        .transition(
          snapshot: prepared,
          to: ProjectStatus.waitingForUser,
          trigger: ProjectLifecycleTrigger.pause,
          reason: blocker?.message ?? 'Project is waiting for user input.',
          blocker: blocker,
          now: now,
        )
        .project;
  }

  _FilteredProjectQuestions _filterProjectQuestions(
    List<PendingProjectQuestion> questions, {
    required QuestionAutonomy autonomy,
  }) {
    final blocking = <PendingProjectQuestion>[];
    final assumptions = <String>[];
    for (final question in questions) {
      final decision = _questionPolicy.decide(
        question: AgentQuestion.fromText(question.question),
        autonomy: autonomy,
      );
      if (decision.shouldBlock) {
        blocking.add(question);
      } else {
        assumptions.add(decision.assumption);
      }
    }
    return _FilteredProjectQuestions(
      blocking: blocking,
      assumptions: assumptions,
    );
  }

  ProjectDocument _blockProject(
    ProjectDocument project,
    ProjectBlockerType type,
    String message,
    DateTime now, {
    String? taskId,
  }) {
    final blocker = ProjectBlocker(
      type: type,
      message: message,
      taskId: taskId,
      createdAt: now,
    );
    return lifecycleService
        .transition(
          snapshot: project,
          to: ProjectStatus.blocked,
          trigger: ProjectLifecycleTrigger.failure,
          reason: message,
          taskId: taskId,
          blocker: blocker,
          now: now,
        )
        .project;
  }

  List<String> _remainingCriteria(ProjectDocument project) {
    return project.criteria
        .where(
          (criterion) =>
              criterion.required &&
              criterion.status != ProjectCriterionStatus.satisfied &&
              criterion.status != ProjectCriterionStatus.invalidated,
        )
        .map((criterion) => criterion.statement)
        .toList();
  }

  List<TaskArtifact> _mergeArtifacts(
    List<TaskArtifact> current,
    List<TaskArtifact> additions,
  ) {
    final byPath = <String, TaskArtifact>{
      for (final artifact in current) artifact.path: artifact,
    };
    for (final artifact in additions) {
      byPath[artifact.path] = artifact;
    }
    return byPath.values.toList();
  }

  ProjectDocument _recordAssumptions(
    ProjectDocument project,
    List<String> assumptions, {
    String? sourceId,
    DateTime? timestamp,
  }) {
    var updated = project;
    for (final assumption in assumptions) {
      if (assumption.trim().isEmpty) continue;
      updated = _memoryService
          .record(
            project: updated,
            kind: ProjectMemoryKind.assumption,
            content: assumption,
            sourceType: ProjectMemorySourceType.planner,
            sourceId: sourceId,
            confidence: ProjectMemoryConfidence.inferred,
            timestamp: timestamp,
          )
          .project;
    }
    return updated;
  }

  ProjectDocument _recordTaskMemory({
    required ProjectDocument project,
    required ProjectTaskNode task,
    required ProjectEvaluation evaluation,
    required List<String> assumptions,
    required bool accepted,
    bool recordFailureRisk = true,
    required DateTime timestamp,
  }) {
    var updated = project;
    if (evaluation.summary.trim().isNotEmpty) {
      updated = _memoryService
          .record(
            project: updated,
            kind: ProjectMemoryKind.summary,
            content: evaluation.summary,
            sourceType: ProjectMemorySourceType.task,
            sourceId: task.id,
            // Task summaries are model-reported descriptions. A completed
            // task can have deterministic evidence, but that evidence does
            // not prove every factual statement in the summary.
            confidence: accepted
                ? ProjectMemoryConfidence.inferred
                : ProjectMemoryConfidence.uncertain,
            timestamp: timestamp,
          )
          .project;
    }
    for (final fact in evaluation.newKnownFacts) {
      if (fact.trim().isEmpty ||
          _normalise(fact) == _normalise(evaluation.summary)) {
        continue;
      }
      updated = _memoryService
          .record(
            project: updated,
            kind: ProjectMemoryKind.fact,
            content: fact,
            sourceType: ProjectMemorySourceType.task,
            sourceId: task.id,
            // Facts extracted from model output remain unverified even when
            // the surrounding task passed its completion gates.
            confidence: accepted
                ? ProjectMemoryConfidence.inferred
                : ProjectMemoryConfidence.uncertain,
            timestamp: timestamp,
          )
          .project;
    }
    if (!accepted &&
        recordFailureRisk &&
        evaluation.failureReason?.trim().isNotEmpty == true) {
      updated = _memoryService
          .record(
            project: updated,
            kind: ProjectMemoryKind.risk,
            content:
                'Task ${task.id} failed: ${evaluation.failureReason!.trim()}',
            sourceType: ProjectMemorySourceType.task,
            sourceId: task.id,
            confidence: ProjectMemoryConfidence.confirmed,
            protected: true,
            timestamp: timestamp,
          )
          .project;
    }
    return _recordAssumptions(
      updated,
      assumptions,
      sourceId: task.id,
      timestamp: timestamp,
    );
  }

  ProjectDocument _projectForModel(
    ProjectDocument project, {
    ProjectTaskNode? task,
  }) {
    final selection = _memoryService.selectContext(
      project: project,
      task: task,
    );
    final selectedIds = selection.selectedMemoryEntryIds.toSet();
    return project.copyWith(
      memory: [
        for (final entry in project.memory)
          if (selectedIds.contains(entry.id)) entry,
      ],
    );
  }

  Set<String> _knownFingerprints(
    ProjectDocument project, {
    String? excludingTaskId,
  }) {
    return {
      for (final task in project.tasks)
        if (task.id != excludingTaskId && task.recoveryIncidentId == null)
          task.fingerprint,
      for (final decision in project.decisions)
        if (decision.taskPrompt?.trim().isNotEmpty == true)
          projectTaskFingerprint(decision.taskPrompt!, const []),
    };
  }

  List<ProjectTaskNode> _normaliseBacklog(List<ProjectTaskNode> tasks) {
    final seen = <String>{};
    return [
      for (final task in tasks)
        if (task.objective.trim().isNotEmpty && seen.add(task.fingerprint))
          task.copyWith(
            status: task.status == TaskStatus.running
                ? TaskStatus.queued
                : task.status,
            updatedAt: DateTime.now(),
          ),
    ];
  }

  List<ProjectTaskNode> _normaliseInitialBacklog(
    List<ProjectTaskNode> tasks,
    List<String> criterionIds,
  ) {
    final knownCriterionIds = criterionIds.toSet();
    return [
      for (final task in _normaliseBacklog(tasks))
        if (task.criterionIds.isNotEmpty &&
            task.criterionIds.every(knownCriterionIds.contains))
          task.copyWith(
            expectedEvidence: [
              for (final expectation in task.expectedEvidence)
                TaskEvidenceExpectation(
                  id: expectation.id,
                  type: expectation.type,
                  criterionIds: expectation.criterionIds.isEmpty
                      ? task.criterionIds
                      : expectation.criterionIds
                            .where(task.criterionIds.contains)
                            .toSet()
                            .toList(),
                  description: expectation.description,
                  required: expectation.required,
                  sourceRef: expectation.sourceRef,
                  details: expectation.details,
                ),
            ],
          ),
    ];
  }

  ProjectDocument _recordTransitionReplanTriggers({
    required ProjectDocument project,
    required ProjectEvaluation evaluation,
    required Set<String> invalidEvidenceIdsBefore,
    required DateTime now,
  }) {
    var milestones = project.milestones;
    var milestoneCompleted = false;
    final satisfiedCriterionIds = {
      for (final criterion in project.criteria)
        if (criterion.status == ProjectCriterionStatus.satisfied) criterion.id,
    };
    milestones = [
      for (final milestone in milestones)
        if (milestone.status != ProjectMilestoneStatus.completed &&
            ((milestone.criterionIds.isNotEmpty &&
                    milestone.criterionIds.every(
                      satisfiedCriterionIds.contains,
                    )) ||
                (() {
                  final taskIds = project.tasks
                      .where((task) => task.milestoneId == milestone.id)
                      .map((task) => task.id)
                      .toSet();
                  return taskIds.isNotEmpty &&
                      taskIds.every(
                        (taskId) =>
                            project.taskById(taskId)?.status ==
                            TaskStatus.completed,
                      );
                })()))
          _completedMilestone(milestone, now, () => milestoneCompleted = true)
        else
          milestone,
    ];
    if (milestoneCompleted) {
      var activatedNext = false;
      milestones = [
        for (final milestone in milestones)
          if (!activatedNext &&
              milestone.status == ProjectMilestoneStatus.planned)
            (() {
              activatedNext = true;
              return ProjectMilestone(
                id: milestone.id,
                title: milestone.title,
                objective: milestone.objective,
                criterionIds: milestone.criterionIds,
                status: ProjectMilestoneStatus.active,
                exitConditions: milestone.exitConditions,
                order: milestone.order,
                createdAt: milestone.createdAt,
                updatedAt: now,
              );
            })()
          else
            milestone,
      ];
    }

    var triggers = _eligibleReplanTriggers(project.pendingReplanTriggers);
    final activeMilestone = milestones
        .where((item) => item.status == ProjectMilestoneStatus.active)
        .firstOrNull;
    final activeMilestoneHasPlannedWork =
        activeMilestone != null &&
        project.tasks.any(
          (task) =>
              task.milestoneId == activeMilestone.id &&
              task.status != TaskStatus.completed &&
              task.status != TaskStatus.failed &&
              task.status != TaskStatus.rejected &&
              task.status != TaskStatus.split &&
              task.status != TaskStatus.deferred &&
              task.status != TaskStatus.obsolete &&
              task.status != TaskStatus.cancelled,
        );
    if (milestoneCompleted &&
        activeMilestone != null &&
        !activeMilestoneHasPlannedWork) {
      triggers = _appendTrigger(
        triggers,
        ProjectPlanRevisionTrigger.milestoneRoadmapChanged,
      );
    }
    if (!evaluation.taskAccepted) {
      triggers = _appendTrigger(
        triggers,
        ProjectPlanRevisionTrigger.taskFailed,
      );
    }
    if (evaluation.projectReplanRequested) {
      triggers = _appendTrigger(
        triggers,
        ProjectPlanRevisionTrigger.taskReplanRequested,
      );
    }
    final hasNewRejectedEvidence = project.evidence.any((item) {
      return (item.status == ProjectEvidenceStatus.rejected ||
              item.status == ProjectEvidenceStatus.stale) &&
          !invalidEvidenceIdsBefore.contains(item.id);
    });
    if (hasNewRejectedEvidence) {
      triggers = _appendTrigger(
        triggers,
        ProjectPlanRevisionTrigger.evidenceRejected,
      );
    }
    final pendingReplanReason = project.isTerminal || triggers.isEmpty
        ? null
        : project.pendingReplanReason ?? _replanReasonForTriggers(triggers);
    return project.copyWith(
      milestones: milestones,
      pendingReplanTriggers: project.isTerminal ? const [] : triggers,
      pendingReplanReason: pendingReplanReason,
      updatedAt: now,
    );
  }

  ProjectMilestone _completedMilestone(
    ProjectMilestone milestone,
    DateTime now,
    void Function() onCompleted,
  ) {
    onCompleted();
    return ProjectMilestone(
      id: milestone.id,
      title: milestone.title,
      objective: milestone.objective,
      criterionIds: milestone.criterionIds,
      status: ProjectMilestoneStatus.completed,
      exitConditions: milestone.exitConditions,
      order: milestone.order,
      createdAt: milestone.createdAt,
      updatedAt: now,
      completedAt: now,
    );
  }

  List<ProjectPlanRevisionTrigger> _appendTrigger(
    List<ProjectPlanRevisionTrigger> current,
    ProjectPlanRevisionTrigger trigger,
  ) {
    return current.contains(trigger) ? current : [...current, trigger];
  }

  static const Set<ProjectPlanRevisionTrigger> _runtimeReplanTriggers = {
    ProjectPlanRevisionTrigger.noReadyTask,
    ProjectPlanRevisionTrigger.taskFailed,
    ProjectPlanRevisionTrigger.evidenceRejected,
    ProjectPlanRevisionTrigger.taskReplanRequested,
    ProjectPlanRevisionTrigger.workspaceChanged,
    ProjectPlanRevisionTrigger.scopeChanged,
    ProjectPlanRevisionTrigger.milestoneRoadmapChanged,
  };

  List<ProjectPlanRevisionTrigger> _eligibleReplanTriggers(
    Iterable<ProjectPlanRevisionTrigger> triggers,
  ) {
    return {
      for (final trigger in triggers)
        if (_runtimeReplanTriggers.contains(trigger)) trigger,
    }.toList();
  }

  ProjectDecisionRecord _decision(
    ProjectDecisionType type,
    String summary,
    String memoryUpdate, {
    ProjectTaskNode? task,
    String? error,
  }) {
    return ProjectDecisionRecord(
      id: 'decision_${uuid.v7()}',
      decision: type,
      summary: summary,
      memoryUpdate: memoryUpdate,
      taskId: task?.id,
      taskTitle: task?.title,
      taskPrompt: task?.objective,
      error: error,
      createdAt: DateTime.now(),
    );
  }

  String _taskPrompt(ProjectDocument project, ProjectTaskNode task) {
    final memoryContext = _memoryService.selectContext(
      project: project,
      task: task,
    );
    final buffer = StringBuffer()
      ..writeln('Project goal:')
      ..writeln(project.refinedGoal)
      ..writeln()
      ..writeln('Selected bounded Project task:')
      ..writeln(task.objective)
      ..writeln()
      ..writeln('Done criteria:')
      ..writeln(_bulletList(task.doneCriteria))
      ..writeln()
      ..writeln('Out of scope:')
      ..writeln(_bulletList(task.outOfScope))
      ..writeln()
      ..writeln('Relevant project success criteria:')
      ..writeln(_bulletList(project.criterionStatementsFor(task)))
      ..writeln()
      ..writeln('Known project facts:')
      ..writeln(_bulletList([...memoryContext.lines, ...task.context]));
    return buffer.toString().trim();
  }

  String _buildTaskSystemPrompt(
    String baseSystemPrompt,
    ProjectDocument project,
    Task? task,
  ) {
    final activeTaskLine = task == null
        ? ''
        : '\nActive task document: ${task.title} (${task.id})';
    final activeRecovery = project.recoveryIncidents
        .where(
          (incident) => incident.status == ProjectRecoveryIncidentStatus.active,
        )
        .firstOrNull;
    final recoveryLine = activeRecovery == null
        ? ''
        : '\nActive recovery incident: ${activeRecovery.id}. Required gate restoration is the only valid project work until this incident is resolved.';
    return '''
$baseSystemPrompt

You are executing one bounded task inside a persistent Project orchestrator.
Project id: ${project.id}
Project goal: ${project.refinedGoal}
Complete only the active bounded Project task. Do not expand into the full project. The application will select the next task after this one is evaluated.$activeTaskLine$recoveryLine
Do not block on prioritization, naming, implementation order, minor layout/design choices, or other reversible preferences; choose a reasonable default, note the assumption, and continue.
Ask the user only for destructive or irreversible actions, credentials/secrets/accounts/API keys, legal/business/product requirement decisions, scope expansion, constraint conflicts, or high-cost ambiguity with no reasonable default.
'''
        .trim();
  }

  String _bulletList(List<String> items) {
    if (items.isEmpty) return '- None specified.';
    return items.map((item) => '- $item').join('\n');
  }

  bool _wasInterrupted(ProjectStatus status) {
    return status == ProjectStatus.initializing ||
        status == ProjectStatus.runningTask ||
        status == ProjectStatus.reviewingTask;
  }

  String _normalise(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  String _cap(String value, int maxChars) {
    if (value.length <= maxChars) return value;
    return '${value.substring(0, maxChars)}...';
  }

  String _newProjectId(String prompt) {
    final slug = _titleFromPrompt(prompt)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final prefix = slug.isEmpty ? 'project' : slug;
    return 'project_${prefix.length > 32 ? prefix.substring(0, 32) : prefix}_${uuid.v7().substring(0, 8)}';
  }

  String _titleFromPrompt(String prompt) {
    final singleLine = prompt.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (singleLine.isEmpty) return 'Untitled project';
    return singleLine.length <= 60
        ? singleLine
        : '${singleLine.substring(0, 57)}...';
  }

  int _normaliseOptionalLimit(int? value, {int fallback = 0}) {
    final resolved = value ?? fallback;
    return resolved < 0 ? 0 : resolved;
  }
}

/// Thin application façade for the project use cases.
///
/// The façade contains no planning, execution, recovery, or persistence
/// policy. It only exposes stable command/query methods and delegates them to
/// the composed runtime. This keeps UI and orchestration wiring independent of
/// the internal handlers and makes each boundary replaceable in tests.
class ProjectWorkflowService {
  ProjectWorkflowService({
    required TaskService taskService,
    ProjectRepository? repository,
    ProjectPlanner? planner,
    ProjectCompletionEvaluator? completionEvaluator,
    ProjectScheduler? scheduler,
    ProjectMemoryService? memoryService,
    ProjectProgressMonitor? progressMonitor,
    WorkspacePersistenceCoordinator? persistenceCoordinator,
    ProjectAggregateRepository? aggregateRepository,
    ProjectStateStore? stateStore,
    ProjectCommandService? commandService,
    ProjectExecutionPort? executionPort,
    ProjectRecoveryPort? recoveryPort,
    PlanningToolCallRunner planningRunner = const PlanningToolCallRunner(),
    StructuredPlanningOutputService structuredOutput =
        const StructuredPlanningOutputService(),
    ProjectLifecycleService lifecycle = const ProjectLifecycleService(),
    TaskLifecycleService? taskLifecycle,
    ProjectCompletionService? completion,
    ProjectRecoveryService? recoveryService,
  }) : _runtime = ProjectWorkflowRuntime(
         taskService: taskService,
         repository: repository,
         planner: planner,
         completionEvaluator: completionEvaluator,
         scheduler: scheduler,
         memoryService: memoryService,
         progressMonitor: progressMonitor,
         persistenceCoordinator: persistenceCoordinator,
         aggregateRepository: aggregateRepository,
         stateStore: stateStore,
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

  final ProjectWorkflowRuntime _runtime;

  ProjectRepository get repository => _runtime.repository;

  Future<ProjectCommandResult> execute(ProjectExecutionRequest request) =>
      _runtime.execute(request);

  Future<ProjectCommandResult> executeUntilStop(
    ProjectExecutionRequest request, {
    required bool boundedRun,
  }) => _runtime.executeUntilStop(request, boundedRun: boundedRun);

  Future<ProjectCommandResult> recover(ProjectRecoveryRequest request) =>
      _runtime.recover(request);

  Future<ProjectTransactionRecoveryResult> recoverPersistence(
    WorkspaceAttachment workspace,
  ) => _runtime.recoverPersistence(workspace);

  Future<List<ProjectSummary>> listProjects(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
  }) => _runtime.listProjects(workspace, chatSessionId: chatSessionId);

  Future<ProjectDocument?> loadLatestProject(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
  }) => _runtime.loadLatestProject(workspace, chatSessionId: chatSessionId);

  Future<ProjectLoadResult> loadLatestProjectResult(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
  }) =>
      _runtime.loadLatestProjectResult(workspace, chatSessionId: chatSessionId);

  Future<ProjectDocument?> loadProject(
    WorkspaceAttachment workspace,
    String projectId, {
    String? chatSessionId,
  }) =>
      _runtime.loadProject(workspace, projectId, chatSessionId: chatSessionId);

  Future<ProjectLoadResult> loadProjectResult(
    WorkspaceAttachment workspace,
    String projectId, {
    String? chatSessionId,
  }) => _runtime.loadProjectResult(
    workspace,
    projectId,
    chatSessionId: chatSessionId,
  );

  Future<int> deleteProjectsForChatSession(
    WorkspaceAttachment workspace, {
    required String chatSessionId,
  }) => _runtime.deleteProjectsForChatSession(
    workspace,
    chatSessionId: chatSessionId,
  );

  Future<int> deleteOrphanedChatProjects(
    WorkspaceAttachment workspace, {
    required Set<String> retainedChatSessionIds,
  }) => _runtime.deleteOrphanedChatProjects(
    workspace,
    retainedChatSessionIds: retainedChatSessionIds,
  );

  Future<ProjectDocument> updateProjectChatSessionId({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    required String chatSessionId,
  }) => _runtime.updateProjectChatSessionId(
    workspace: workspace,
    snapshot: snapshot,
    chatSessionId: chatSessionId,
  );

  String encodeProject(ProjectDocument project) =>
      _runtime.encodeProject(project);

  Future<ProjectDocument> updateProject({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    required String rawJson,
  }) => _runtime.updateProject(
    workspace: workspace,
    snapshot: snapshot,
    rawJson: rawJson,
  );

  Future<ProjectDocument> createProject({
    required WorkspaceAttachment workspace,
    required String userPrompt,
    String? chatSessionId,
    ChatClient? client,
    String baseSystemPrompt = '',
    int? maxIterations,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
    QuestionAutonomy questionAutonomy = QuestionAutonomy.balanced,
  }) => _runtime.createProject(
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

  Future<ProjectDocument> retryRecoveryIncident({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    required String incidentId,
  }) => _runtime.retryRecoveryIncident(
    workspace: workspace,
    snapshot: snapshot,
    incidentId: incidentId,
  );

  Future<ProjectDocument> answerOpenQuestion({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    required String answer,
  }) => _runtime.answerOpenQuestion(
    workspace: workspace,
    snapshot: snapshot,
    answer: answer,
  );

  Future<ProjectDocument> addUserContext({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    required String text,
  }) => _runtime.addUserContext(
    workspace: workspace,
    snapshot: snapshot,
    text: text,
  );

  Future<ProjectDocument> requestScopeChange({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    required String context,
  }) => _runtime.requestScopeChange(
    workspace: workspace,
    snapshot: snapshot,
    context: context,
  );

  Future<ProjectDocument> compactMemory({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    required List<String> coveredEntryIds,
    required String summary,
  }) => _runtime.compactMemory(
    workspace: workspace,
    snapshot: snapshot,
    coveredEntryIds: coveredEntryIds,
    summary: summary,
  );

  Future<ProjectDocument> pauseProject({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
  }) => _runtime.pauseProject(workspace: workspace, snapshot: snapshot);

  Future<ProjectDocument> clearTaskBlocker({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
  }) => _runtime.clearTaskBlocker(workspace: workspace, snapshot: snapshot);

  Future<ProjectDocument> approvePlanRevision({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
  }) => _runtime.approvePlanRevision(workspace: workspace, snapshot: snapshot);

  Future<ProjectDocument> rejectPlanRevision({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
  }) => _runtime.rejectPlanRevision(workspace: workspace, snapshot: snapshot);

  Future<ProjectDocument> cancelProject({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
  }) => _runtime.cancelProject(workspace: workspace, snapshot: snapshot);

  Future<ProjectDocument> stopProject({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
  }) => _runtime.stopProject(workspace: workspace, snapshot: snapshot);
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
  final ProjectDocument project;
  final Task? activeTask;
  final TaskResult? result;

  const _ProjectTaskExecution({
    required this.project,
    this.activeTask,
    this.result,
  });
}

class _RecoveryFailure {
  final TaskGateResult gateResult;
  final String? command;
  final String? workingDirectory;
  final String summary;

  const _RecoveryFailure({
    required this.gateResult,
    required this.command,
    required this.workingDirectory,
    required this.summary,
  });
}

class _RecoveryUpdate {
  final ProjectTaskNode failedTask;
  final List<ProjectRecoveryIncident> recoveryIncidents;
  final ProjectRecoveryIncident? incident;
  final ProjectRecoveryIncident? exhaustedIncident;
  final ProjectTaskNode? recoveryTask;

  const _RecoveryUpdate({
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
