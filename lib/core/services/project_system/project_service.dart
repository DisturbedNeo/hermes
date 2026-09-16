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
import 'package:hermes/core/services/project_system/project_plan_revision_service.dart';
import 'package:hermes/core/services/project_system/project_progress_monitor.dart';
import 'package:hermes/core/services/project_system/project_repository.dart';
import 'package:hermes/core/services/project_system/project_scheduler.dart';
import 'package:hermes/core/services/question_policy_service.dart';
import 'package:hermes/core/services/task_system/task_json.dart';
import 'package:hermes/core/services/task_system/task_model_output.dart';
import 'package:hermes/core/services/task_system/task_service.dart';
import 'package:hermes/core/services/workspace_discovery_profile.dart';
import 'package:path/path.dart' as path;

typedef ProjectTaskSnapshotSink = void Function(Task? task);
typedef ProjectCompactionStatusSink = void Function(String status);

int taskStepLimit(TaskEffort effort) => switch (effort) {
  TaskEffort.small => 1,
  TaskEffort.medium => 4,
  TaskEffort.large => 6,
};

class ProjectRunResult {
  final ProjectDocument project;
  final Task? activeTask;

  const ProjectRunResult({required this.project, this.activeTask});
}

class ProjectService {
  ProjectService({
    required TaskService taskService,
    ProjectRepository? repository,
    ProjectPlanningGateway? modelCalls,
    ProjectScheduler? scheduler,
    ProjectMemoryService? memoryService,
    ProjectProgressMonitor? progressMonitor,
  }) : _taskService = taskService,
       _repository = repository ?? ProjectRepository(),
       _modelCalls =
           modelCalls ??
           ProjectModelCalls(toolService: taskService.toolService),
       _scheduler = scheduler ?? const ProjectScheduler(),
       _memoryService = memoryService ?? const ProjectMemoryService(),
       _progressMonitor = progressMonitor ?? const ProjectProgressMonitor();

  final TaskService _taskService;
  final ProjectRepository _repository;
  final ProjectPlanningGateway _modelCalls;
  final ProjectScheduler _scheduler;
  final ProjectMemoryService _memoryService;
  final ProjectProgressMonitor _progressMonitor;
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
  final ProjectPlanRevisionService _planRevisionService =
      const ProjectPlanRevisionService();
  final JsonEncoder _encoder = const JsonEncoder.withIndent('  ');

  // A malformed model plan is a recoverable planning failure. Keep the
  // retry bounded so a persistently invalid model response still becomes a
  // durable, actionable blocker rather than an unbounded model-call loop.
  static const _maxAutomaticInitialPlanRepairs = 2;

  ProjectRepository get repository => _repository;

  Task? _activeProjectTask(ProjectDocument project) {
    final id = project.activeTaskId;
    return id == null ? null : project.taskById(id);
  }

  bool _isTerminalTask(Task task) => switch (task.status) {
    TaskStatus.completed ||
    TaskStatus.failed ||
    TaskStatus.rejected ||
    TaskStatus.split ||
    TaskStatus.cancelled => true,
    _ => false,
  };

  List<Task> _nonTerminalTasks(ProjectDocument project) =>
      project.tasks.where((task) => !_isTerminalTask(task)).toList();

  List<Task> _upsertTask(
    ProjectDocument project,
    Task replacement, {
    String? removeId,
  }) {
    final replaced = <Task>[];
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

  Future<ProjectDocument> _persistProject(
    String workspaceRoot,
    ProjectDocument project,
  ) async {
    final refreshed = _scheduler
        .refreshReadiness(project)
        .project
        .copyWith(
          taskIds: project.tasks.isEmpty
              ? project.taskIds
              : [for (final task in project.tasks) task.id],
        );
    for (final task in refreshed.tasks) {
      final existing = await _taskService.repository.loadTask(
        workspaceRoot,
        task.id,
      );
      final taskToSave = _taskForPersistence(
        task,
        existing,
        projectId: refreshed.id,
        chatSessionId: refreshed.chatSessionId,
      );
      await _taskService.repository.saveSnapshot(workspaceRoot, taskToSave);
    }
    await _repository.saveSnapshot(workspaceRoot, refreshed);
    return refreshed;
  }

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
  }) async {
    final scheduled = _scheduler.schedule(project);
    final readyTasks = <Task>[];
    final seen = <String>{};
    final selected = scheduled.selectedTask;
    if (selected != null && seen.add(selected.id)) readyTasks.add(selected);
    for (final task in _scheduler.orderedReadyTasks(scheduled.project)) {
      if (seen.add(task.id)) readyTasks.add(task);
    }
    final batchSize = maxNewTasks <= 0 ? readyTasks.length : maxNewTasks;
    final batchTaskIds = [
      for (final task in readyTasks.take(batchSize)) task.id,
    ];
    return _persistProject(
      workspaceRoot,
      scheduled.project.copyWith(
        currentBatchTaskIds: batchTaskIds,
        currentBatchIndex: 0,
        currentBatchPlanRevision: _currentPlanRevision(scheduled.project),
        currentBatchProgressObserved: false,
        pendingReplanReason: null,
      ),
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

  Task? _currentBatchTask(ProjectDocument project) {
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

  bool _hasWorkOutsideBatch(ProjectDocument project) {
    final batchIds = project.currentBatchTaskIds.toSet();
    return project.tasks.any(
      (task) => !_isTerminalTask(task) && !batchIds.contains(task.id),
    );
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

  Task _taskForPersistence(
    Task projectTask,
    Task? existing, {
    required String projectId,
    required String? chatSessionId,
  }) {
    if (existing == null || projectTask.steps.isNotEmpty) {
      return projectTask.copyWith(
        projectId: projectId,
        chatSessionId: chatSessionId,
      );
    }
    // A project-side planning update must not erase executable steps or task
    // history that already exists under the same canonical task ID.
    return existing.copyWith(
      id: projectTask.id,
      title: projectTask.title,
      originalPrompt: projectTask.originalPrompt,
      objective: projectTask.objective,
      constraints: projectTask.constraints,
      successCriteria: projectTask.successCriteria,
      gates: projectTask.gates.isEmpty ? existing.gates : projectTask.gates,
      criterionIds: projectTask.criterionIds,
      milestoneId: projectTask.milestoneId,
      dependsOnTaskIds: projectTask.dependsOnTaskIds,
      priority: projectTask.priority,
      risk: projectTask.risk,
      riskReduction: projectTask.riskReduction,
      effort: projectTask.effort,
      selectionRationale: projectTask.selectionRationale,
      revisionIntroduced: projectTask.revisionIntroduced,
      revisionUpdated: projectTask.revisionUpdated,
      expectedEvidence: projectTask.expectedEvidence.isEmpty
          ? existing.expectedEvidence
          : projectTask.expectedEvidence,
      readPaths: projectTask.readPaths,
      writePaths: projectTask.writePaths,
      doneCriteria: projectTask.doneCriteria,
      outOfScope: projectTask.outOfScope,
      context: projectTask.context,
      expectedArtifacts: projectTask.expectedArtifacts.isEmpty
          ? existing.expectedArtifacts
          : projectTask.expectedArtifacts,
      status: projectTask.status,
      recoveryIncidentId: projectTask.recoveryIncidentId,
      fingerprint: projectTask.fingerprint,
      rejectionReason: projectTask.rejectionReason,
      failure: projectTask.failure ?? existing.failure,
      projectId: projectId,
      chatSessionId: chatSessionId,
    );
  }

  /// Loads the task records referenced by a project snapshot. The in-memory
  /// task list is only a hydration cache; canonical task definitions live in
  /// the task repository and are addressed by [ProjectState.taskIds].
  Future<ProjectDocument> _hydrateProjectTasks(
    WorkspaceAttachment workspace,
    ProjectDocument project,
  ) async {
    // A newly-created in-memory project may be handed directly to the runner
    // before its task documents have been persisted. Persisted projects cannot
    // contain an embedded `tasks` field because ProjectStateJsonHook rejects
    // it; this cache only supports that current in-memory lifecycle.
    final cachedById = {for (final task in project.tasks) task.id: task};
    final hydrated = <Task>[];
    for (final id in project.taskIds) {
      final loaded = await _taskService.loadTask(
        workspace,
        id,
        chatSessionId: project.chatSessionId,
        projectId: project.id,
      );
      final task = loaded ?? cachedById[id];
      if (task != null) hydrated.add(task);
    }
    return project.copyWith(tasks: hydrated);
  }

  Future<List<ProjectSummary>> listProjects(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
  }) {
    return _repository.listProjects(
      workspace.rootPath,
      chatSessionId: chatSessionId,
    );
  }

  Future<ProjectDocument?> loadLatestProject(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
  }) async {
    final project = await _repository.loadLatestProject(
      workspace.rootPath,
      chatSessionId: chatSessionId,
    );
    return project == null ? null : _prepareLoadedProject(workspace, project);
  }

  Future<ProjectDocument?> loadProject(
    WorkspaceAttachment workspace,
    String projectId, {
    String? chatSessionId,
  }) async {
    final project = await _repository.loadProject(
      workspace.rootPath,
      projectId,
      chatSessionId: chatSessionId,
    );
    return project == null ? null : _prepareLoadedProject(workspace, project);
  }

  Future<ProjectDocument> _prepareLoadedProject(
    WorkspaceAttachment workspace,
    ProjectDocument project,
  ) => _hydrateProjectTasks(workspace, project);

  Future<int> deleteProjectsForChatSession(
    WorkspaceAttachment workspace, {
    required String chatSessionId,
  }) {
    if (workspace.missing) return Future.value(0);
    return _repository.deleteProjectsForChatSession(
      workspace.rootPath,
      chatSessionId: chatSessionId,
    );
  }

  Future<int> deleteOrphanedChatProjects(
    WorkspaceAttachment workspace, {
    required Set<String> retainedChatSessionIds,
  }) {
    if (workspace.missing) return Future.value(0);
    return _repository.deleteOrphanedChatProjects(
      workspace.rootPath,
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
  }) async {
    cancellationToken?.throwIfCancelled();
    final now = DateTime.now();
    final discovery = await _discoveryService.collect(
      workspace: workspace,
      goalContext: userPrompt,
      cancellationToken: cancellationToken,
    );
    final metadata = {
      ...discovery.toMap(),
      'commandExecutionApproved': workspace.commandExecutionApproved,
    };
    var modelCallCount = 0;
    var repairAttempts = 0;
    var planningIssues = <Map<String, String>>[
      for (final issue in discovery.workspaceProfile.requiredContextIssues)
        if (_blocksInitialPlanningForContextIssue(issue))
          {'code': issue.code, 'path': issue.path, 'message': issue.message},
    ];
    var init = client == null || planningIssues.isNotEmpty
        ? _fallbackInitialisation(userPrompt)
        : await _modelCalls.initializeProject(
            client: client,
            baseSystemPrompt: baseSystemPrompt,
            workspace: workspace,
            originalGoal: userPrompt,
            workspaceMetadata: metadata,
            onModelOutput: onModelOutput,
            cancellationToken: cancellationToken,
          );
    var planningMetrics = init.planningMetrics;
    if (client != null && planningIssues.isEmpty) {
      modelCallCount++;
      planningIssues = _validateInitialisation(
        initialisation: init,
        workspaceProfile: discovery.workspaceProfile,
      );
      while (planningIssues.isNotEmpty &&
          repairAttempts < _maxAutomaticInitialPlanRepairs) {
        repairAttempts++;
        final repaired = await _modelCalls.repairInitialisation(
          client: client,
          baseSystemPrompt: baseSystemPrompt,
          workspace: workspace,
          originalGoal: userPrompt,
          workspaceMetadata: metadata,
          initialisation: init,
          validationIssues: planningIssues,
          onModelOutput: onModelOutput,
          cancellationToken: cancellationToken,
        );
        modelCallCount++;
        if (repaired != null) {
          planningMetrics = planningMetrics.add(repaired.planningMetrics);
          init = repaired;
          planningIssues = _validateInitialisation(
            initialisation: init,
            workspaceProfile: discovery.workspaceProfile,
          );
        }
      }
    }
    cancellationToken?.throwIfCancelled();
    final planningBlocked = planningIssues.isNotEmpty;
    final filteredQuestions = _filterProjectQuestions(
      init.openQuestions,
      autonomy: questionAutonomy,
    );
    final initialCriteria = init.criteria;
    final initialCriterionIds = initialCriteria.map((item) => item.id).toList();
    final initialBacklog = planningBlocked
        ? const <Task>[]
        : _normaliseInitialBacklog(init.tasks, initialCriterionIds);
    final initialMilestones = _initialMilestones(
      init: init,
      criteria: initialCriteria,
      now: now,
    );
    final initialMemory = _initialMemory(
      init,
      filteredQuestions.assumptions,
      now,
    );
    if (planningMetrics.planningCalls == 0 && modelCallCount > 0) {
      planningMetrics = planningMetrics.copyWith(planningCalls: modelCallCount);
    }
    planningMetrics = planningMetrics.copyWith(
      planningStartedAt: now,
      fullPlanRepairCount: planningMetrics.fullPlanRepairCount + repairAttempts,
      validationBlockerCount:
          planningMetrics.validationBlockerCount + (planningBlocked ? 1 : 0),
      timeToFirstExecutableMs:
          !planningBlocked &&
              filteredQuestions.blocking.isEmpty &&
              initialBacklog.any((task) => task.status == TaskStatus.queued)
          ? DateTime.now().difference(now).inMilliseconds
          : null,
    );
    if (planningMetrics.planningCalls > modelCallCount) {
      modelCallCount = planningMetrics.planningCalls;
    }
    final project = ProjectDocument(
      id: _newProjectId(userPrompt),
      title: init.title.trim().isEmpty
          ? _titleFromPrompt(userPrompt)
          : init.title,
      originalGoal: userPrompt,
      refinedGoal: init.refinedGoal.trim().isEmpty
          ? userPrompt
          : init.refinedGoal,
      constraints: init.constraints.isEmpty
          ? const ['Stay within the attached workspace.']
          : init.constraints,
      criteria: initialCriteria,
      tasks: initialBacklog,
      artifacts: const [],
      memory: initialMemory,
      milestones: initialMilestones,
      planHistory: [
        ProjectPlanRevision(
          revision: 1,
          trigger: ProjectPlanRevisionTrigger.initialization,
          summary: planningBlocked
              ? 'Initial project planning blocked.'
              : 'Initial project roadmap.',
          rationale: planningBlocked
              ? _initialPlanningBlockerMessage(planningIssues)
              : 'Created criteria, milestones, and the bounded near-term plan from discovery.',
          addedTaskIds: initialBacklog.map((task) => task.id).toList(),
          criterionChanges: [
            for (final criterion in initialCriteria) 'add:${criterion.id}',
          ],
          milestoneChanges: [
            for (final milestone in initialMilestones) 'add:${milestone.id}',
          ],
          validationWarnings: [
            for (final issue in planningIssues)
              '${issue['code']}: ${issue['message']}',
          ],
          createdAt: now,
          approvedAt: planningBlocked ? null : now,
          approvedBy: planningBlocked
              ? null
              : ProjectPlanRevisionApprover.automatic,
        ),
      ],
      openQuestions: filteredQuestions.blocking,
      status: planningBlocked
          ? ProjectStatus.blocked
          : filteredQuestions.blocking.isEmpty
          ? ProjectStatus.active
          : ProjectStatus.waitingForUser,
      iterationCount: 0,
      maxIterations: _normaliseOptionalLimit(
        maxIterations,
        fallback: ProjectDocument.defaultMaxIterations,
      ),
      maxFailedTasks: ProjectDocument.defaultMaxFailedTasks,
      activeTaskId: null,
      chatSessionId: chatSessionId,
      completionSummary: '',
      blocker: planningBlocked
          ? ProjectBlocker(
              type: ProjectBlockerType.validation,
              message: _initialPlanningBlockerMessage(planningIssues),
              createdAt: now,
            )
          : filteredQuestions.blocking.isEmpty
          ? null
          : ProjectBlocker(
              type: ProjectBlockerType.question,
              message: filteredQuestions.blocking.first.question,
              createdAt: now,
            ),
      decisions: const [],
      diagnostics: ProjectDiagnostics(
        projectModelCalls: modelCallCount,
        userQuestions: filteredQuestions.blocking.length,
        planningMetrics: planningMetrics,
      ),
      createdAt: now,
      updatedAt: now,
    );
    return _persistProject(workspace.rootPath, project);
  }

  bool _blocksInitialPlanningForContextIssue(
    WorkspaceRequiredContextIssue issue,
  ) => issue.code == 'required_context_unreadable';

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

  Future<ProjectRunResult> recoverProject({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    ProjectTaskSnapshotSink? onTaskUpdated,
  }) async {
    snapshot = await _hydrateProjectTasks(workspace, snapshot);
    if (snapshot.isTerminal) {
      return ProjectRunResult(
        project: snapshot,
        activeTask: await _loadActiveTask(workspace, snapshot),
      );
    }

    final activeTask = await _loadActiveTask(workspace, snapshot);
    if (!_wasInterrupted(snapshot.status)) {
      return ProjectRunResult(project: snapshot, activeTask: activeTask);
    }

    final now = DateTime.now();
    if (snapshot.activeTaskId == null) {
      final recovered = snapshot.copyWith(
        status: snapshot.openQuestions.isEmpty
            ? ProjectStatus.active
            : ProjectStatus.waitingForUser,
        updatedAt: now,
      );
      final persisted = await _persistProject(workspace.rootPath, recovered);
      return ProjectRunResult(project: persisted);
    }

    if (activeTask == null) {
      final blocked = _blockProject(
        snapshot.copyWith(activeTaskId: null, updatedAt: now),
        ProjectBlockerType.error,
        'Recovered an interrupted project, but its active task was missing.',
        now,
      );
      final persisted = await _persistProject(workspace.rootPath, blocked);
      onTaskUpdated?.call(null);
      return ProjectRunResult(project: persisted);
    }

    final recoveredTask = await _taskService.recoverTask(
      workspace: workspace,
      snapshot: activeTask,
    );
    onTaskUpdated?.call(recoveredTask);
    final taskStatusBlocker = _taskBlocker(recoveredTask);
    var recovered = _syncCurrentTaskFromTask(snapshot, recoveredTask, now);
    recovered = taskStatusBlocker == null
        ? recovered.copyWith(status: ProjectStatus.active, updatedAt: now)
        : _blockProject(
            recovered,
            taskStatusBlocker.$1,
            taskStatusBlocker.$2,
            now,
            taskId: recoveredTask.id,
          );
    recovered = await _persistProject(workspace.rootPath, recovered);
    return ProjectRunResult(project: recovered, activeTask: recoveredTask);
  }

  Future<ProjectDocument> retryRecoveryIncident({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    required String incidentId,
  }) async {
    final incident = snapshot.recoveryIncidents
        .where(
          (item) =>
              item.id == incidentId &&
              item.status == ProjectRecoveryIncidentStatus.exhausted,
        )
        .firstOrNull;
    if (incident == null) return snapshot;
    final sourceTask = snapshot.tasks
        .where((task) => task.status == TaskStatus.failed)
        .toList()
        .reversed
        .where((task) => task.recoveryIncidentId == incidentId)
        .firstOrNull;
    if (sourceTask == null) return snapshot;

    final now = DateTime.now();
    final gateResult = TaskGateResult(
      gateId: incident.failedGateId,
      status: TaskGateStatus.failed,
      summary: incident.failureSummary,
      details: {
        'required': true,
        if (incident.command?.trim().isNotEmpty == true)
          'command': incident.command,
        if (incident.workingDirectory?.trim().isNotEmpty == true)
          'workingDirectory': incident.workingDirectory,
      },
      failureDisposition: TaskGateFailureDisposition.repairable,
      evaluatedAt: now,
    );
    final failure = _RecoveryFailure(
      gateResult: gateResult,
      command: incident.command,
      workingDirectory: incident.workingDirectory,
      summary: incident.failureSummary,
    );
    final recoveryTask = _recoveryTaskForIncident(
      incidentId: incident.id,
      sourceTask: sourceTask,
      failure: failure,
      attemptNumber: incident.attemptCount + 1,
      now: now,
    );
    final reactivated = incident.copyWith(
      status: ProjectRecoveryIncidentStatus.active,
      maxAttempts: incident.attemptCount + 1,
      recoveryTaskIds: _appendUnique(incident.recoveryTaskIds, recoveryTask.id),
      updatedAt: now,
      resolvedAt: null,
    );
    var updated = snapshot.copyWith(
      status: ProjectStatus.active,
      blocker: null,
      tasks: [recoveryTask, ...snapshot.tasks],
      recoveryIncidents: _upsertRecoveryIncident(
        snapshot.recoveryIncidents,
        reactivated,
      ),
      decisions: [
        ...snapshot.decisions,
        _decision(
          ProjectDecisionType.retryRecovery,
          'Granted one additional recovery attempt for ${incident.id}.',
          incident.failureSummary,
          task: recoveryTask,
        ),
      ],
      updatedAt: now,
    );
    updated = _memoryService
        .record(
          project: updated,
          kind: ProjectMemoryKind.decision,
          content:
              'User granted one additional recovery attempt for ${incident.id}.',
          sourceType: ProjectMemorySourceType.user,
          sourceId: incident.id,
          confidence: ProjectMemoryConfidence.confirmed,
          protected: true,
          timestamp: now,
        )
        .project;
    return _persistProject(workspace.rootPath, updated);
  }

  Future<ProjectRunResult> runNextProjectTask({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    required String baseSystemPrompt,
    bool requirePhaseApproval = false,
    CompactionSettings? compactionSettings,
    int? contextLimitTokens,
    ProjectCompactionStatusSink? onCompactionStatus,
    TaskModelOutputSink? onModelOutput,
    ProjectTaskSnapshotSink? onTaskUpdated,
    CancellationToken? cancellationToken,
    QuestionAutonomy questionAutonomy = QuestionAutonomy.balanced,
    ProjectPlanApprovalPolicy planApprovalPolicy =
        ProjectPlanApprovalPolicy.highRiskOnly,
  }) {
    return runProject(
      client: client,
      workspace: workspace,
      snapshot: snapshot,
      baseSystemPrompt: baseSystemPrompt,
      maxNewTasks: 1,
      requirePhaseApproval: requirePhaseApproval,
      compactionSettings: compactionSettings,
      contextLimitTokens: contextLimitTokens,
      onCompactionStatus: onCompactionStatus,
      onModelOutput: onModelOutput,
      onTaskUpdated: onTaskUpdated,
      cancellationToken: cancellationToken,
      questionAutonomy: questionAutonomy,
      planApprovalPolicy: planApprovalPolicy,
    );
  }

  Future<ProjectRunResult> runProject({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    required String baseSystemPrompt,
    required int maxNewTasks,
    int? maxIterations,
    bool requirePhaseApproval = false,
    CompactionSettings? compactionSettings,
    int? contextLimitTokens,
    ProjectCompactionStatusSink? onCompactionStatus,
    TaskModelOutputSink? onModelOutput,
    ProjectTaskSnapshotSink? onTaskUpdated,
    CancellationToken? cancellationToken,
    QuestionAutonomy questionAutonomy = QuestionAutonomy.balanced,
    ProjectPlanApprovalPolicy planApprovalPolicy =
        ProjectPlanApprovalPolicy.highRiskOnly,
  }) async {
    cancellationToken?.throwIfCancelled();
    final recovered = await recoverProject(
      workspace: workspace,
      snapshot: snapshot,
      onTaskUpdated: onTaskUpdated,
    );
    var project = recovered.project;
    var activeTask = recovered.activeTask;
    if (maxIterations != null && project.maxIterations != maxIterations) {
      project = project.copyWith(
        maxIterations: _normaliseOptionalLimit(maxIterations),
        updatedAt: DateTime.now(),
      );
      project = await _persistProject(workspace.rootPath, project);
    }
    if (project.isTerminal) {
      return ProjectRunResult(project: project, activeTask: activeTask);
    }
    final pendingProposal = project.pendingPlanApproval?.desiredPlan;
    if (pendingProposal != null) {
      final reconsidered = await _planRevisionService.prepareAndApply(
        project: project,
        proposal: pendingProposal,
        workspaceRoot: workspace.rootPath,
        approvalPolicy: planApprovalPolicy,
      );
      if (reconsidered.changed || !reconsidered.validation.valid) {
        project = await _persistProject(
          workspace.rootPath,
          reconsidered.project,
        );
      }
    }
    if (project.pendingPlanApproval != null) {
      return ProjectRunResult(project: project, activeTask: activeTask);
    }
    final canAutomaticallyReplanValidationBlocker =
        project.blocker?.type == ProjectBlockerType.validation &&
        project.activeTaskId == null;
    if (canAutomaticallyReplanValidationBlocker) {
      project = project.copyWith(
        status: ProjectStatus.active,
        blocker: null,
        pendingReplanTriggers: _appendTrigger(
          project.pendingReplanTriggers,
          ProjectPlanRevisionTrigger.noReadyTask,
        ),
        updatedAt: DateTime.now(),
      );
      project = await _persistProject(workspace.rootPath, project);
    }
    final canResumeValidationBlocker =
        project.blocker?.type == ProjectBlockerType.validation &&
        _hasExecutableProjectTask(project);
    if (project.blocker?.type == ProjectBlockerType.budget ||
        project.blocker?.type == ProjectBlockerType.duplicateTask ||
        canResumeValidationBlocker) {
      project = project.copyWith(
        status: ProjectStatus.active,
        blocker: null,
        updatedAt: DateTime.now(),
      );
      project = await _persistProject(workspace.rootPath, project);
    }

    if (project.activeTaskId != null && project.currentBatchTaskIds.isEmpty) {
      project = await _persistProject(
        workspace.rootPath,
        project.copyWith(
          currentBatchTaskIds: [project.activeTaskId!],
          currentBatchIndex: 0,
          currentBatchPlanRevision: _currentPlanRevision(project),
        ),
      );
    } else if (project.activeTaskId == null &&
        project.currentBatchPlanRevision != 0 &&
        project.currentBatchPlanRevision != _currentPlanRevision(project)) {
      project = await _persistProject(workspace.rootPath, _clearBatch(project));
    }

    final allowedIterations = maxNewTasks <= 0 ? null : maxNewTasks;
    var runIterations = 0;
    var consecutiveInvalidCandidates = 0;

    while (!project.isTerminal) {
      cancellationToken?.throwIfCancelled();
      if (project.openQuestions.isNotEmpty) {
        final filtered = _filterProjectQuestions(
          project.openQuestions,
          autonomy: questionAutonomy,
        );
        if (filtered.assumptions.isNotEmpty) {
          project = project.copyWith(
            openQuestions: filtered.blocking,
            blocker: filtered.blocking.isEmpty
                ? null
                : ProjectBlocker(
                    type: ProjectBlockerType.question,
                    message: filtered.blocking.first.question,
                    createdAt: DateTime.now(),
                  ),
            status: filtered.blocking.isEmpty
                ? ProjectStatus.active
                : ProjectStatus.waitingForUser,
            updatedAt: DateTime.now(),
          );
          project = _recordAssumptions(
            project,
            filtered.assumptions,
            sourceId: 'question_policy',
          );
          project = await _persistProject(workspace.rootPath, project);
        }
      }
      if (project.openQuestions.isNotEmpty ||
          project.blocker?.type == ProjectBlockerType.question) {
        project = _waitingForUser(project, DateTime.now());
        project = await _persistProject(workspace.rootPath, project);
        return ProjectRunResult(project: project, activeTask: activeTask);
      }
      if (project.status == ProjectStatus.blocked &&
          project.blocker?.type != ProjectBlockerType.budget) {
        return ProjectRunResult(project: project, activeTask: activeTask);
      }
      if (project.maxIterations > 0 &&
          project.iterationCount >= project.maxIterations) {
        project = _blockProject(
          project,
          ProjectBlockerType.budget,
          'Project reached the maximum iteration limit of ${project.maxIterations}.',
          DateTime.now(),
        );
        project = await _persistProject(workspace.rootPath, project);
        return ProjectRunResult(project: project, activeTask: activeTask);
      }
      if (allowedIterations != null && runIterations >= allowedIterations) {
        project = project.copyWith(
          status: ProjectStatus.paused,
          updatedAt: DateTime.now(),
        );
        project = await _persistProject(workspace.rootPath, project);
        return ProjectRunResult(project: project, activeTask: activeTask);
      }

      var replanTriggers = _eligibleReplanTriggers(
        project.pendingReplanTriggers,
      );
      if (replanTriggers.length != project.pendingReplanTriggers.length ||
          (replanTriggers.isNotEmpty && project.pendingReplanReason == null)) {
        project = project.copyWith(
          pendingReplanTriggers: replanTriggers,
          pendingReplanReason: replanTriggers.isEmpty
              ? null
              : _replanReasonForTriggers(replanTriggers),
        );
      }

      if (_activeProjectTask(project) == null && replanTriggers.isEmpty) {
        if (project.currentBatchPlanRevision != 0 &&
            project.currentBatchPlanRevision != _currentPlanRevision(project)) {
          project = await _persistProject(
            workspace.rootPath,
            _clearBatch(project),
          );
        }
        if (project.currentBatchTaskIds.isNotEmpty &&
            project.currentBatchIndex >= project.currentBatchTaskIds.length) {
          if (_hasWorkOutsideBatch(project)) {
            replanTriggers = _appendTrigger(
              replanTriggers,
              ProjectPlanRevisionTrigger.batchComplete,
            );
            project = project.copyWith(
              pendingReplanTriggers: replanTriggers,
              pendingReplanReason:
                  project.pendingReplanReason ??
                  _replanReasonForTriggers(replanTriggers),
            );
          } else {
            project = await _persistProject(
              workspace.rootPath,
              _clearBatch(project),
            );
          }
        }
        if (replanTriggers.isEmpty && !project.hasCurrentBatch) {
          project = await _startBatch(
            workspaceRoot: workspace.rootPath,
            project: project,
            maxNewTasks: maxNewTasks,
          );
        }
      }

      var candidate = _activeProjectTask(project) ?? _currentBatchTask(project);
      if (_activeProjectTask(project) == null &&
          candidate?.isTerminal == true) {
        project = await _persistProject(
          workspace.rootPath,
          _advanceBatchCursor(project, candidate!.id),
        );
        continue;
      }
      if (candidate == null && replanTriggers.isEmpty) {
        project = await _applyCompletionEvaluation(
          client: client,
          project: project,
          baseSystemPrompt: baseSystemPrompt,
          reviewReason: _nonTerminalTasks(project).isEmpty
              ? ProjectCompletionReviewReason.noRemainingTasks
              : null,
          onModelOutput: onModelOutput,
          questionAutonomy: questionAutonomy,
          cancellationToken: cancellationToken,
        );
        if (project.isTerminal ||
            project.status == ProjectStatus.waitingForUser ||
            project.openQuestions.isNotEmpty) {
          project = await _persistProject(workspace.rootPath, project);
          return ProjectRunResult(project: project, activeTask: activeTask);
        }
        replanTriggers = _appendTrigger(
          replanTriggers,
          ProjectPlanRevisionTrigger.noReadyTask,
        );
        project = project.copyWith(
          pendingReplanTriggers: replanTriggers,
          pendingReplanReason:
              project.pendingReplanReason ??
              _replanReasonForTriggers(replanTriggers),
        );
      }

      if (_shouldRevisePlan(
        project: project,
        candidate: candidate,
        triggers: replanTriggers,
      )) {
        project = await _revisePlan(
          client: client,
          workspace: workspace,
          project: project,
          triggers: replanTriggers,
          baseSystemPrompt: baseSystemPrompt,
          approvalPolicy: planApprovalPolicy,
          questionAutonomy: questionAutonomy,
          onModelOutput: onModelOutput,
          cancellationToken: cancellationToken,
        );
        project = await _persistProject(workspace.rootPath, project);
        if (project.pendingPlanApproval != null ||
            project.status == ProjectStatus.blocked ||
            project.status == ProjectStatus.waitingForUser) {
          return ProjectRunResult(project: project, activeTask: activeTask);
        }
        continue;
      }

      if (candidate == null) {
        project = _blockProject(
          project.copyWith(
            diagnostics: project.diagnostics.copyWith(
              noReadyTaskBlocks: project.diagnostics.noReadyTaskBlocks + 1,
            ),
          ),
          ProjectBlockerType.validation,
          'The validated plan left no ready bounded task. Revise the scope, constraints, or dependencies before resuming.',
          DateTime.now(),
        );
        project = await _persistProject(workspace.rootPath, project);
        return ProjectRunResult(project: project, activeTask: activeTask);
      }

      final activeProjectTask = _activeProjectTask(project);
      final resumingActiveTask =
          activeProjectTask?.id == candidate.id &&
          activeTask != null &&
          activeTask.id == activeProjectTask?.id;
      final validation = resumingActiveTask
          ? const _ProjectTaskValidation(true, [])
          : _validateProjectTask(candidate, project);
      if (!validation.valid) {
        final projectBeforeRecovery = project;
        project = await _handleInvalidProjectTask(
          client: client,
          workspace: workspace,
          project: project,
          task: candidate,
          violations: validation.violations,
          baseSystemPrompt: baseSystemPrompt,
          approvalPolicy: planApprovalPolicy,
          onModelOutput: onModelOutput,
          cancellationToken: cancellationToken,
        );
        if (project.status == ProjectStatus.blocked) {
          project = await _persistProject(workspace.rootPath, project);
          return ProjectRunResult(project: project, activeTask: activeTask);
        }
        if (project.pendingPlanApproval != null) {
          project = await _persistProject(workspace.rootPath, project);
          return ProjectRunResult(project: project, activeTask: activeTask);
        }
        final recoveryMadeProgress = _invalidTaskRecoveryMadeProgress(
          before: projectBeforeRecovery,
          after: project,
        );
        if (recoveryMadeProgress || project.taskById(candidate.id) == null) {
          consecutiveInvalidCandidates = 0;
          // Selection recovery can replace the candidate with a fresh task.
          // Rebuild the batch from the repaired project so that replacement
          // work is eligible without changing the normal sequential path.
          project = _clearBatch(project);
        } else {
          consecutiveInvalidCandidates++;
        }
        if (consecutiveInvalidCandidates >= 3) {
          project = _blockProject(
            project,
            ProjectBlockerType.validation,
            'Project task selection produced $consecutiveInvalidCandidates invalid candidates in a row.',
            DateTime.now(),
          );
          project = await _persistProject(workspace.rootPath, project);
          return ProjectRunResult(project: project, activeTask: activeTask);
        }
        project = await _persistProject(workspace.rootPath, project);
        continue;
      }
      consecutiveInvalidCandidates = 0;

      final execution = await _executeProjectTask(
        client: client,
        workspace: workspace,
        project: project,
        projectTask: candidate,
        baseSystemPrompt: baseSystemPrompt,
        requirePhaseApproval: requirePhaseApproval,
        compactionSettings: compactionSettings,
        contextLimitTokens: contextLimitTokens,
        onCompactionStatus: onCompactionStatus,
        onModelOutput: onModelOutput,
        onTaskUpdated: onTaskUpdated,
        cancellationToken: cancellationToken,
        questionAutonomy: questionAutonomy,
      );
      project = execution.project;
      activeTask = execution.activeTask;
      if (execution.result == null) {
        return ProjectRunResult(project: project, activeTask: activeTask);
      }

      final now = DateTime.now();
      project = project.copyWith(
        status: ProjectStatus.reviewingTask,
        updatedAt: now,
      );
      project = await _persistProject(workspace.rootPath, project);

      final evaluatedProjectTask = _activeProjectTask(project) ?? candidate;
      final criterionStatusesBefore = {
        for (final criterion in project.criteria)
          criterion.id: criterion.status,
      };
      final acceptedEvidenceIdsBefore = {
        for (final item in project.evidence)
          if (item.status == ProjectEvidenceStatus.accepted) item.id,
      };
      final evidenceIdsBefore = project.evidence.map((item) => item.id).toSet();
      final activeMilestoneIdBefore = project.milestones
          .where((item) => item.status == ProjectMilestoneStatus.active)
          .map((item) => item.id)
          .firstOrNull;
      final invalidEvidenceIds = {
        for (final item in project.evidence)
          if (item.status == ProjectEvidenceStatus.rejected ||
              item.status == ProjectEvidenceStatus.stale)
            item.id,
      };
      final evaluation = _evaluateTaskResult(
        evaluatedProjectTask,
        execution.result!,
        project,
      );
      project = _updateProjectState(
        project,
        evaluation,
        now,
        questionAutonomy: questionAutonomy,
      );
      project = _applyTaskEvidence(
        project: project,
        task: evaluatedProjectTask,
        result: execution.result!,
        evaluatedAt: now,
      );
      project = _recordTransitionReplanTriggers(
        project: project,
        evaluation: evaluation,
        invalidEvidenceIdsBefore: invalidEvidenceIds,
        now: now,
      );
      final endedMilestoneId =
          activeMilestoneIdBefore != null &&
              project.milestones.any(
                (item) =>
                    item.id == activeMilestoneIdBefore &&
                    _isTerminalMilestoneStatus(item.status),
              )
          ? activeMilestoneIdBefore
          : null;
      final batchEnded = _isBatchEnd(project, evaluatedProjectTask.id);
      final reviewReason = _completionReviewReason(
        project: project,
        newEvidenceIds: project.evidence
            .where((item) => !evidenceIdsBefore.contains(item.id))
            .map((item) => item.id)
            .toSet(),
        endedMilestoneId: endedMilestoneId,
        batchEnded: batchEnded,
      );
      project = await _applyCompletionEvaluation(
        client: client,
        project: project,
        baseSystemPrompt: baseSystemPrompt,
        reviewReason: reviewReason,
        reviewMilestoneId: endedMilestoneId,
        onModelOutput: onModelOutput,
        questionAutonomy: questionAutonomy,
        cancellationToken: cancellationToken,
      );
      project = _progressMonitor.recordTaskResult(
        project: project,
        task: evaluatedProjectTask,
        taskAccepted: evaluation.taskAccepted,
        excludeFromStagnation: evaluation.projectReplanRequested,
        criterionStatusesBefore: criterionStatusesBefore,
        acceptedEvidenceIdsBefore: acceptedEvidenceIdsBefore,
        evaluatedAt: now,
      );
      project = project.copyWith(
        iterationCount: project.iterationCount + 1,
        updatedAt: DateTime.now(),
      );
      project = _advanceBatchCursor(project, evaluatedProjectTask.id);
      final pendingTriggers = _eligibleReplanTriggers(
        project.pendingReplanTriggers,
      );
      if (pendingTriggers.isNotEmpty && project.pendingReplanReason == null) {
        project = project.copyWith(
          pendingReplanReason: _replanReasonForTriggers(pendingTriggers),
        );
      }
      if (pendingTriggers.isEmpty &&
          project.currentBatchTaskIds.isNotEmpty &&
          project.currentBatchIndex >= project.currentBatchTaskIds.length &&
          _hasWorkOutsideBatch(project)) {
        final batchTriggers = _appendTrigger(
          pendingTriggers,
          ProjectPlanRevisionTrigger.batchComplete,
        );
        project = project.copyWith(
          pendingReplanTriggers: batchTriggers,
          pendingReplanReason: _replanReasonForTriggers(batchTriggers),
        );
      }
      project = await _persistProject(workspace.rootPath, project);
      runIterations++;
      if (project.status == ProjectStatus.completed ||
          project.status == ProjectStatus.failed ||
          project.status == ProjectStatus.waitingForUser ||
          project.status == ProjectStatus.blocked) {
        return ProjectRunResult(project: project, activeTask: activeTask);
      }
    }

    return ProjectRunResult(project: project, activeTask: activeTask);
  }

  Future<ProjectDocument> answerOpenQuestion({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    required String answer,
  }) async {
    final question = snapshot.openQuestions.firstOrNull;
    final trimmed = answer.trim();
    if (question == null || trimmed.isEmpty) return snapshot;
    final remainingQuestions = snapshot.openQuestions
        .where((item) => item.id != question.id)
        .toList();
    var updated = snapshot.copyWith(
      status: ProjectStatus.active,
      openQuestions: remainingQuestions,
      blocker: null,
      pendingReplanTriggers: _appendTrigger(
        snapshot.pendingReplanTriggers,
        ProjectPlanRevisionTrigger.scopeChanged,
      ),
      pendingReplanReason:
          'The project scope changed and the backlog must be reconciled.',
      updatedAt: DateTime.now(),
    );
    updated = _memoryService
        .recordUserAnswer(project: updated, question: question, answer: trimmed)
        .project;
    return _persistProject(workspace.rootPath, updated);
  }

  Future<ProjectDocument> addUserContext({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    required String text,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return snapshot;
    if (snapshot.openQuestions.isNotEmpty) {
      return answerOpenQuestion(
        workspace: workspace,
        snapshot: snapshot,
        answer: trimmed,
      );
    }
    var updated = snapshot.copyWith(
      status: snapshot.isTerminal ? snapshot.status : ProjectStatus.active,
      blocker: snapshot.blocker?.type == ProjectBlockerType.question
          ? null
          : snapshot.blocker,
      updatedAt: DateTime.now(),
    );
    updated = _memoryService
        .record(
          project: updated,
          kind: ProjectMemoryKind.requirement,
          content: 'User added project context: $trimmed',
          sourceType: ProjectMemorySourceType.user,
          confidence: ProjectMemoryConfidence.confirmed,
          protected: true,
        )
        .project;
    return _persistProject(workspace.rootPath, updated);
  }

  /// Records an explicit user scope change and queues one plan revision.
  Future<ProjectDocument> requestScopeChange({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    required String context,
  }) async {
    if (snapshot.isTerminal || snapshot.pendingPlanApproval != null) {
      return snapshot;
    }
    final now = DateTime.now();
    final trimmedReason = context.trim();
    var updated = snapshot.copyWith(
      status: ProjectStatus.active,
      blocker:
          snapshot.blocker?.type == ProjectBlockerType.planApproval ||
              snapshot.blocker?.type == ProjectBlockerType.stagnation
          ? null
          : snapshot.blocker,
      pendingReplanTriggers: _appendTrigger(
        snapshot.pendingReplanTriggers,
        ProjectPlanRevisionTrigger.scopeChanged,
      ),
      pendingReplanReason: trimmedReason.isEmpty
          ? 'The project scope changed and the backlog must be reconciled.'
          : 'User changed project scope: $trimmedReason',
      updatedAt: now,
      diagnostics: snapshot.diagnostics.copyWith(
        consecutiveNoProgressBatches: 0,
        recentNoProgressBatchIds: const [],
      ),
    );
    if (trimmedReason.isNotEmpty) {
      updated = _memoryService
          .record(
            project: updated,
            kind: ProjectMemoryKind.requirement,
            content: 'User changed project scope: $trimmedReason',
            sourceType: ProjectMemorySourceType.user,
            sourceId: 'scope_change_${now.microsecondsSinceEpoch}',
            confidence: ProjectMemoryConfidence.confirmed,
            protected: true,
            timestamp: now,
          )
          .project;
    }
    return _persistProject(workspace.rootPath, updated);
  }

  Future<ProjectDocument> compactMemory({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    required List<String> coveredEntryIds,
    required String summary,
  }) async {
    final compacted = _memoryService.compact(
      project: snapshot,
      coveredEntryIds: coveredEntryIds,
      summary: summary,
    );
    return _persistProject(workspace.rootPath, compacted.project);
  }

  Future<ProjectDocument> pauseProject({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
  }) async {
    final updated = snapshot.copyWith(
      status: ProjectStatus.paused,
      updatedAt: DateTime.now(),
    );
    return _persistProject(workspace.rootPath, updated);
  }

  Future<ProjectDocument> clearTaskBlocker({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
  }) async {
    final type = snapshot.blocker?.type;
    if (type != ProjectBlockerType.taskEditApproval &&
        type != ProjectBlockerType.taskBlocked &&
        type != ProjectBlockerType.taskFailed) {
      return snapshot;
    }
    final updated = snapshot.copyWith(
      status: ProjectStatus.active,
      blocker: null,
      updatedAt: DateTime.now(),
    );
    return _persistProject(workspace.rootPath, updated);
  }

  Future<ProjectDocument> approvePlanRevision({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
  }) async {
    final result = _planRevisionService.approvePending(
      project: snapshot,
      workspaceRoot: workspace.rootPath,
    );
    return _persistProject(
      workspace.rootPath,
      result.project.copyWith(
        diagnostics: result.project.diagnostics.copyWith(
          userApprovals: result.project.diagnostics.userApprovals + 1,
        ),
      ),
    );
  }

  Future<ProjectDocument> rejectPlanRevision({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
  }) async {
    final pending = snapshot.pendingPlanApproval;
    if (pending == null) return snapshot;
    final now = DateTime.now();
    final rejectionBase = snapshot.copyWith(
      pendingPlanApproval: null,
      blocker: null,
      updatedAt: now,
    );
    final schedule = _scheduler.schedule(rejectionBase);
    final hasReadyWork = schedule.selectedTask != null;
    var updated = schedule.project.copyWith(
      status: hasReadyWork ? ProjectStatus.active : ProjectStatus.paused,
      blocker: hasReadyWork
          ? null
          : ProjectBlocker(
              type: ProjectBlockerType.planApproval,
              message:
                  'Plan revision ${pending.revision} was rejected and no ready work remains. Provide new direction before replanning.',
              createdAt: now,
            ),
      decisions: [
        ...snapshot.decisions,
        _decision(
          ProjectDecisionType.rejectPlanRevision,
          'Rejected plan revision ${pending.revision}: ${pending.summary}',
          pending.reason,
        ),
      ],
      updatedAt: now,
    );
    updated = _memoryService
        .record(
          project: updated,
          kind: ProjectMemoryKind.decision,
          content: 'User rejected plan revision ${pending.revision}.',
          sourceType: ProjectMemorySourceType.user,
          sourceId: 'revision_${pending.revision}',
          confidence: ProjectMemoryConfidence.confirmed,
          protected: true,
          timestamp: now,
        )
        .project;
    return _persistProject(workspace.rootPath, updated);
  }

  Future<ProjectDocument> cancelProject({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
  }) async {
    final now = DateTime.now();
    final activeTask = _activeProjectTask(snapshot);
    final updated = snapshot.copyWith(
      status: ProjectStatus.cancelled,
      activeTaskId: null,
      tasks: [
        for (final task in snapshot.tasks)
          task.id == activeTask?.id
              ? task.copyWith(status: TaskStatus.cancelled, updatedAt: now)
              : task,
      ],
      openQuestions: const [],
      blocker: null,
      completedAt: now,
      updatedAt: now,
    );
    return _persistProject(workspace.rootPath, updated);
  }

  Future<ProjectDocument> stopProject({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
  }) {
    return cancelProject(workspace: workspace, snapshot: snapshot);
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
    final incremental = await _modelCalls.revisePlanWithCommands(
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
    return _finishPlanRevision(
      revised: incremental.project,
      questionAutonomy: questionAutonomy,
      modelCalls: incremental.modelCalls,
      planningMetrics: incremental.planningMetrics,
      invalidPlan: !incremental.committed,
      awaitingApproval: incremental.awaitingApproval,
      planningError: incremental.error,
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
      revised = revised.copyWith(
        openQuestions: filtered.blocking,
        status: filtered.blocking.isEmpty && !awaitingApproval
            ? ProjectStatus.active
            : revised.status,
        blocker: filtered.blocking.isEmpty && !awaitingApproval
            ? null
            : revised.blocker,
        updatedAt: DateTime.now(),
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

  bool _isSelectableTask(Task task) {
    return task.status == TaskStatus.queued;
  }

  Future<ProjectDocument> _handleInvalidProjectTask({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required ProjectDocument project,
    required Task task,
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
        return project.copyWith(
          tasks: _upsertTask(project, duplicate.task, removeId: task.id),
          status: ProjectStatus.active,
          blocker: null,
          updatedAt: now,
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
        return project.copyWith(
          tasks: _upsertTask(
            project.copyWith(tasks: _upsertTask(project, rejected)),
            retryTask,
          ),
          status: ProjectStatus.active,
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
        );
      }
      final rejected = task.copyWith(
        status: TaskStatus.rejected,
        rejectionReason: violations.join('\n'),
        updatedAt: now,
      );
      return project.copyWith(
        tasks: _upsertTask(project, rejected),
        status: ProjectStatus.active,
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
      );
    }

    final incremental = await _modelCalls.splitTaskWithCommands(
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
    return incremental.project.copyWith(
      status: incremental.awaitingApproval
          ? incremental.project.status
          : ProjectStatus.active,
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
  }

  Future<_ProjectTaskExecution> _executeProjectTask({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required ProjectDocument project,
    required Task projectTask,
    required String baseSystemPrompt,
    required bool requirePhaseApproval,
    CompactionSettings? compactionSettings,
    int? contextLimitTokens,
    ProjectCompactionStatusSink? onCompactionStatus,
    TaskModelOutputSink? onModelOutput,
    ProjectTaskSnapshotSink? onTaskUpdated,
    CancellationToken? cancellationToken,
    QuestionAutonomy questionAutonomy = QuestionAutonomy.balanced,
  }) async {
    cancellationToken?.throwIfCancelled();
    final now = DateTime.now();
    final effectiveCriterionIds = projectTask.criterionIds
        .where((id) => project.criteria.any((criterion) => criterion.id == id))
        .toSet();
    if (effectiveCriterionIds.isEmpty) {
      final blocked = _blockProject(
        project,
        ProjectBlockerType.validation,
        'Task ${projectTask.id} has no valid project criteria; no task document was created.',
        now,
        taskId: projectTask.id,
      );
      return _ProjectTaskExecution(
        project: await _persistProject(workspace.rootPath, blocked),
      );
    }
    final runningProjectTask = projectTask.copyWith(
      status: TaskStatus.running,
      updatedAt: now,
    );
    var workingProject = project.copyWith(
      status: ProjectStatus.runningTask,
      activeTaskId: projectTask.id,
      tasks: _upsertTask(project, runningProjectTask),
      blocker: null,
      decisions: [
        ...project.decisions,
        _decision(
          ProjectDecisionType.createTask,
          'Selected next bounded project task: ${projectTask.title}',
          '',
          task: projectTask,
        ),
      ],
      updatedAt: now,
    );
    final loadedTask = await _loadActiveTask(workspace, workingProject);
    // A queued Task record is the project definition, not yet an executable
    // plan. Only reuse a record once it contains executable steps.
    final existingTask = loadedTask?.steps.isNotEmpty == true
        ? loadedTask
        : null;
    workingProject = await _persistProject(workspace.rootPath, workingProject);

    final planningContext = _planningContext(workingProject, projectTask);
    late Task activeTask;
    if (existingTask != null) {
      activeTask = existingTask;
    } else {
      activeTask = projectTask.effort == TaskEffort.small
          ? await _taskService.createProjectTask(
              workspace: workspace,
              userPrompt: _taskPrompt(workingProject, projectTask),
              chatSessionId: workingProject.chatSessionId,
              projectId: workingProject.id,
              planningContext: planningContext,
              canonicalTaskId: projectTask.id,
            )
          : await _taskService.createTask(
              client: client,
              workspace: workspace,
              userPrompt: _taskPrompt(workingProject, projectTask),
              selectedMode: ExecutionMode.task,
              baseSystemPrompt: _buildTaskSystemPrompt(
                baseSystemPrompt,
                workingProject,
                null,
              ),
              chatSessionId: workingProject.chatSessionId,
              projectId: workingProject.id,
              planningContext: planningContext,
              canonicalTaskId: projectTask.id,
              onModelOutput: onModelOutput,
              cancellationToken: cancellationToken,
            );
    }
    final executionRequest = TaskExecutionRequest.fromPlanningContext(
      planningContext,
    );
    workingProject = workingProject.copyWith(
      activeTaskId: projectTask.id,
      tasks: _upsertTask(
        workingProject,
        runningProjectTask.copyWith(updatedAt: DateTime.now()),
      ),
      updatedAt: DateTime.now(),
    );
    workingProject = await _persistProject(workspace.rootPath, workingProject);
    onTaskUpdated?.call(activeTask);

    while (activeTask.nextRunnableStep != null && !activeTask.isTerminal) {
      cancellationToken?.throwIfCancelled();
      activeTask = await _taskService.runNextStep(
        client: client,
        workspace: workspace,
        snapshot: activeTask,
        baseSystemPrompt: _buildTaskSystemPrompt(
          baseSystemPrompt,
          workingProject,
          activeTask,
        ),
        requirePhaseApproval: requirePhaseApproval,
        compactionSettings: compactionSettings,
        contextLimitTokens: contextLimitTokens,
        onCompactionStatus: onCompactionStatus,
        onModelOutput: onModelOutput,
        cancellationToken: cancellationToken,
        questionAutonomy: questionAutonomy,
        executionRequest: executionRequest,
      );
      onTaskUpdated?.call(activeTask);
      workingProject = _syncCurrentTaskFromTask(
        workingProject,
        activeTask,
        DateTime.now(),
      );
      workingProject = await _persistProject(
        workspace.rootPath,
        workingProject,
      );

      final latestRun = activeTask.runs.isEmpty ? null : activeTask.runs.last;
      final interrupted =
          latestRun?.status == TaskRunStatus.failed ||
          latestRun?.status == TaskRunStatus.cancelled;
      if (activeTask.status == TaskStatus.paused && interrupted) {
        final paused = workingProject.copyWith(
          status: ProjectStatus.paused,
          blocker: null,
          updatedAt: DateTime.now(),
        );
        final persisted = await _persistProject(workspace.rootPath, paused);
        return _ProjectTaskExecution(
          project: persisted,
          activeTask: activeTask,
        );
      }

      if (cancellationToken?.isCancelled == true) {
        final paused = workingProject.copyWith(
          status: ProjectStatus.paused,
          updatedAt: DateTime.now(),
        );
        final persisted = await _persistProject(workspace.rootPath, paused);
        return _ProjectTaskExecution(
          project: persisted,
          activeTask: activeTask,
        );
      }

      final blocker = _taskBlocker(activeTask);
      if (blocker != null) {
        final blocked = _blockProject(
          workingProject,
          blocker.$1,
          blocker.$2,
          DateTime.now(),
          taskId: activeTask.id,
        ).copyWith(status: ProjectStatus.waitingForUser);
        final persisted = await _persistProject(workspace.rootPath, blocked);
        return _ProjectTaskExecution(
          project: persisted,
          activeTask: activeTask,
        );
      }
    }

    if (!activeTask.isTerminal && activeTask.nextRunnableStep == null) {
      activeTask = await _taskService.runNextStep(
        client: client,
        workspace: workspace,
        snapshot: activeTask,
        baseSystemPrompt: _buildTaskSystemPrompt(
          baseSystemPrompt,
          workingProject,
          activeTask,
        ),
        requirePhaseApproval: requirePhaseApproval,
        compactionSettings: compactionSettings,
        contextLimitTokens: contextLimitTokens,
        onCompactionStatus: onCompactionStatus,
        onModelOutput: onModelOutput,
        cancellationToken: cancellationToken,
        questionAutonomy: questionAutonomy,
        executionRequest: executionRequest,
      );
      onTaskUpdated?.call(activeTask);
    }

    final result = _taskResultFromTask(
      _activeProjectTask(workingProject) ?? projectTask,
      activeTask,
    );
    return _ProjectTaskExecution(
      project: _syncCurrentTaskFromTask(
        workingProject,
        activeTask,
        DateTime.now(),
      ),
      activeTask: activeTask,
      result: result,
    );
  }

  ProjectEvaluation _evaluateTaskResult(
    Task projectTask,
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
    required Task task,
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
        failure: failure,
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
      var updated = project.copyWith(
        activeTaskId: null,
        tasks: [
          if (recoveryUpdate.recoveryTask != null) recoveryUpdate.recoveryTask!,
          ...tasks.where((item) => item.id != recoveryUpdate.recoveryTask?.id),
        ],
        recoveryIncidents: recoveryIncidents,
        openQuestions: filteredQuestions.blocking,
        status: exhaustedIncident != null || blockingFailure
            ? ProjectStatus.blocked
            : reachedFailureLimit
            ? ProjectStatus.blocked
            : ProjectStatus.active,
        blocker: exhaustedIncident != null
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
            : null,
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
    var updated = project.copyWith(
      activeTaskId: null,
      tasks: [
        ...evaluation.taskAdditions,
        ..._upsertTask(project, completedTask),
      ],
      artifacts: _mergeArtifacts(project.artifacts, evaluation.artifacts),
      recoveryIncidents: recoveryIncidents,
      openQuestions: filteredQuestions.blocking,
      status: filteredQuestions.blocking.isEmpty
          ? ProjectStatus.active
          : ProjectStatus.waitingForUser,
      blocker: filteredQuestions.blocking.isEmpty
          ? null
          : ProjectBlocker(
              type: ProjectBlockerType.question,
              message: filteredQuestions.blocking.first.question,
              createdAt: now,
            ),
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
      return project.copyWith(status: ProjectStatus.active, updatedAt: now);
    }

    final evidenceFingerprint = _completionEvidenceFingerprint(project);
    final checkpoint = project.completionReviewCheckpoint;
    if (checkpoint?.reason == reviewReason &&
        checkpoint?.evidenceFingerprint == evidenceFingerprint &&
        checkpoint?.milestoneId == reviewMilestoneId) {
      return project.copyWith(status: ProjectStatus.active, updatedAt: now);
    }

    final assessment = await _modelCalls.evaluateCompletion(
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
        return _recordAssumptions(
          assessedProject.copyWith(
            status: ProjectStatus.active,
            blocker: null,
            updatedAt: now,
          ),
          filtered.assumptions,
          sourceId: 'completion_review',
        );
      }
      return _recordAssumptions(
        assessedProject.copyWith(
          status: ProjectStatus.waitingForUser,
          openQuestions: filtered.blocking,
          blocker: ProjectBlocker(
            type: ProjectBlockerType.question,
            message: filtered.blocking.first.question,
            createdAt: now,
          ),
          updatedAt: now,
          diagnostics: assessedProject.diagnostics.copyWith(
            userQuestions:
                assessedProject.diagnostics.userQuestions +
                filtered.blocking.length,
          ),
        ),
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
    return reviewed.copyWith(status: ProjectStatus.active, updatedAt: now);
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
    return project.copyWith(
      status: ProjectStatus.completed,
      completionSummary: summary.trim().isEmpty
          ? 'All required project criteria are satisfied by accepted evidence.'
          : summary.trim(),
      completedAt: now,
      blocker: null,
      updatedAt: now,
    );
  }

  _ProjectTaskValidation _validateProjectTask(
    Task task,
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
    Task task,
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

  Task _retryTaskForFailedDuplicate({
    required Task failedTask,
    required Task duplicateTask,
    required List<String> violations,
    required DateTime now,
  }) {
    final criteria = <String>{
      ...failedTask.criterionIds,
      ...duplicateTask.criterionIds,
    }.toList();
    final objective =
        'Retry failed project task after addressing the previous failure: ${failedTask.objective}';
    return Task(
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

  TaskPlanningContext _planningContext(ProjectDocument project, Task task) {
    final memoryContext = _memoryService.selectContext(
      project: project,
      task: task,
    );
    return TaskPlanningContext(
      projectGoal: project.refinedGoal,
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
        for (final criterion in project.criteria)
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
    required Task failedTask,
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
    required Task failedTask,
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

  Task _recoveryTaskForIncident({
    required String incidentId,
    required Task sourceTask,
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
    return Task(
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
    Task completedTask,
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

  List<TaskGate> _requiredGatesForTask(ProjectDocument project, Task task) {
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
    List<Task> failedTasks,
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
              task.failure?.failureKey ??
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

  TaskResult _taskResultFromTask(Task projectTask, Task task) {
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
    return project.copyWith(
      status: ProjectStatus.waitingForUser,
      blocker:
          project.blocker ??
          (project.openQuestions.isEmpty
              ? null
              : ProjectBlocker(
                  type: ProjectBlockerType.question,
                  message: project.openQuestions.first.question,
                  createdAt: now,
                )),
      updatedAt: now,
    );
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
    return project.copyWith(
      status: ProjectStatus.blocked,
      blocker: ProjectBlocker(
        type: type,
        message: message,
        taskId: taskId,
        createdAt: now,
      ),
      updatedAt: now,
    );
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
    required Task task,
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

  ProjectDocument _projectForModel(ProjectDocument project, {Task? task}) {
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

  List<Task> _normaliseBacklog(List<Task> tasks) {
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

  List<Task> _normaliseInitialBacklog(
    List<Task> tasks,
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

  List<Map<String, String>> _validateInitialisation({
    required ProjectInitialisation initialisation,
    required WorkspaceDiscoveryProfile workspaceProfile,
  }) {
    final issues = <Map<String, String>>[];
    void add(String code, String message, {String? path}) {
      final issue = <String, String>{'code': code, 'message': message};
      if (path != null) issue['path'] = path;
      issues.add(issue);
    }

    final criteria = initialisation.criteria;
    final criterionIds = <String>{};
    for (final criterion in criteria) {
      if (criterion.id.trim().isEmpty || criterion.statement.trim().isEmpty) {
        add(
          'invalid_criterion',
          'Every success criterion needs a non-empty stable ID and statement.',
        );
      } else if (!criterionIds.add(criterion.id)) {
        add(
          'duplicate_criterion_id',
          'Criterion ID ${criterion.id} is declared more than once.',
        );
      }
      if (criterion.status != ProjectCriterionStatus.unsatisfied ||
          criterion.verifiedAt != null) {
        add(
          'unsupported_initial_criterion_progress',
          'Criterion ${criterion.id} claims evaluator-owned progress during initialization.',
        );
      }
    }
    if (criterionIds.isEmpty) {
      add(
        'missing_criteria',
        'The initial plan must define at least one success criterion.',
      );
    }

    final taskById = <String, Task>{};
    for (final task in initialisation.tasks) {
      if (task.id.trim().isEmpty || taskById.containsKey(task.id)) {
        add(
          'invalid_task_id',
          'Every initial task needs a unique, non-empty stable ID.',
        );
      } else {
        taskById[task.id] = task;
      }
    }
    if (taskById.isEmpty && initialisation.openQuestions.isEmpty) {
      add(
        'missing_executable_tasks',
        'The initial plan must contain bounded executable work or a blocking question.',
      );
    }

    final milestoneIds = <String>{};
    for (final milestone in initialisation.milestones) {
      if (milestone.id.trim().isEmpty || !milestoneIds.add(milestone.id)) {
        add(
          'invalid_milestone_id',
          'Every milestone needs a unique, non-empty stable ID.',
        );
      }
      for (final criterionId in milestone.criterionIds) {
        if (!criterionIds.contains(criterionId)) {
          add(
            'unknown_milestone_criterion',
            'Milestone ${milestone.id} references unknown criterion $criterionId.',
          );
        }
      }
    }
    if (taskById.isNotEmpty && milestoneIds.isEmpty) {
      add(
        'missing_milestones',
        'The initial plan must place executable work in at least one milestone.',
      );
    }

    final workspacePaths = {
      for (final item in workspaceProfile.treePaths)
        _normaliseWorkspacePath(
          item.endsWith('/') ? item.substring(0, item.length - 1) : item,
        ),
    };
    for (final task in taskById.values) {
      if (task.objective.trim().isEmpty ||
          task.doneCriteria.isEmpty ||
          task.outOfScope.isEmpty) {
        add(
          'invalid_task_structure',
          'Task ${task.id} needs an objective, done criteria, and out-of-scope boundaries.',
        );
      }
      if (task.status != TaskStatus.queued &&
          task.status != TaskStatus.deferred) {
        add(
          'invalid_initial_task_status',
          'Task ${task.id} cannot claim execution progress during initialization.',
        );
      }
      if (task.criterionIds.isEmpty) {
        add(
          'task_without_criteria',
          'Task ${task.id} must reference at least one project criterion.',
        );
      }
      for (final criterionId in task.criterionIds) {
        if (!criterionIds.contains(criterionId)) {
          add(
            'unknown_task_criterion',
            'Task ${task.id} references unknown criterion $criterionId.',
          );
        }
      }
      if (task.milestoneId == null ||
          !milestoneIds.contains(task.milestoneId)) {
        add(
          'unknown_task_milestone',
          'Task ${task.id} must reference a declared milestone.',
        );
      }
      for (final dependencyId in task.dependsOnTaskIds) {
        if (!taskById.containsKey(dependencyId) || dependencyId == task.id) {
          add(
            'invalid_task_dependency',
            'Task ${task.id} has invalid dependency $dependencyId.',
          );
        }
      }
      if (task.expectedEvidence.isEmpty) {
        add(
          'missing_evidence_expectation',
          'Task ${task.id} must declare expected evidence.',
        );
      }
      for (final expectation in task.expectedEvidence) {
        if (expectation.id.trim().isEmpty ||
            expectation.description.trim().isEmpty) {
          add(
            'invalid_evidence_expectation',
            'Every evidence expectation on task ${task.id} needs an ID and description.',
          );
        }
        if (expectation.criterionIds.isEmpty) {
          add(
            'evidence_without_criteria',
            'Evidence ${expectation.id} on task ${task.id} has no criterion link.',
          );
        }
        for (final criterionId in expectation.criterionIds) {
          if (!criterionIds.contains(criterionId) ||
              !task.criterionIds.contains(criterionId)) {
            add(
              'invalid_evidence_criterion',
              'Evidence ${expectation.id} references criterion $criterionId outside task ${task.id}.',
            );
          }
        }
      }
      for (final readPath in task.readPaths) {
        final normalized = _normaliseWorkspacePath(readPath);
        if (!_isSafeRelativeWorkspacePath(normalized)) {
          add(
            'read_path_outside_workspace',
            'Task ${task.id} readPath is outside the workspace.',
            path: readPath,
          );
          continue;
        }
        final exists = workspacePaths.any(
          (candidate) => _pathCovers(candidate, normalized),
        );
        final producedByDependency = task.dependsOnTaskIds.any((dependencyId) {
          final dependency = taskById[dependencyId];
          if (dependency == null) return false;
          final outputs = <String>[
            ...dependency.writePaths,
            ...dependency.expectedArtifacts.map((item) => item.path),
          ].map(_normaliseWorkspacePath);
          return outputs.any((output) => _pathCovers(output, normalized));
        });
        if (!exists && !producedByDependency) {
          add(
            'ungrounded_read_path',
            'Task ${task.id} treats a missing path as existing, and no declared dependency produces it.',
            path: readPath,
          );
        }
      }
      for (final writePath in task.writePaths) {
        final normalized = _normaliseWorkspacePath(writePath);
        if (!_isSafeRelativeWorkspacePath(normalized)) {
          add(
            'write_path_outside_workspace',
            'Task ${task.id} writePath is outside the workspace.',
            path: writePath,
          );
        }
      }
      for (final artifact in task.expectedArtifacts) {
        final normalized = _normaliseWorkspacePath(artifact.path);
        if (artifact.path.trim().isEmpty ||
            !_isSafeRelativeWorkspacePath(normalized)) {
          add(
            'artifact_path_outside_workspace',
            'Task ${task.id} has an invalid expected artifact path.',
            path: artifact.path,
          );
        }
      }
      if (task.effort == TaskEffort.small &&
          task.expectedArtifacts.isNotEmpty &&
          task.writePaths.isEmpty) {
        add(
          'missing_write_paths',
          'Small artifact-producing tasks must declare write paths.',
        );
      }
    }

    for (final criterion in criteria) {
      if (criterion.status == ProjectCriterionStatus.satisfied ||
          criterion.verificationMode != ProjectVerificationMode.deterministic) {
        continue;
      }
      final hasConclusiveExpectation = initialisation.tasks.any(
        (task) => task.expectedEvidence.any(
          (expectation) =>
              expectation.required &&
              expectation.criterionIds.contains(criterion.id) &&
              (expectation.type == ProjectEvidenceType.gate ||
                  expectation.type == ProjectEvidenceType.command),
        ),
      );
      if (!hasConclusiveExpectation) {
        add(
          'impossible_deterministic_verification',
          'Deterministic criterion ${criterion.id} needs a required gate or command evidence expectation.',
        );
      }
    }

    final dependencyGraph = <String, List<String>>{
      for (final task in taskById.values) task.id: task.dependsOnTaskIds,
    };
    if (_hasDependencyCycle(dependencyGraph)) {
      add(
        'cyclic_dependencies',
        'The initial task dependency graph contains a cycle.',
      );
    }

    final memoryIds = <String>{};
    for (final entry in initialisation.memory) {
      if (entry.id.trim().isEmpty || !memoryIds.add(entry.id)) {
        add(
          'invalid_memory_id',
          'Planner memory entries need unique, non-empty IDs.',
        );
      }
      if (entry.content.trim().isEmpty) {
        add('empty_memory', 'Planner memory entries cannot be empty.');
      }
    }
    return issues;
  }

  String _initialPlanningBlockerMessage(List<Map<String, String>> issues) {
    final details = issues
        .map((issue) {
          final path = issue['path'];
          return '${issue['code']}${path == null ? '' : ' ($path)'}: ${issue['message']}';
        })
        .join(' ');
    return 'Initial planning was blocked because required context or plan structure was invalid. $details';
  }

  String _normaliseWorkspacePath(String value) => path
      .normalize(value.trim().replaceAll('\\', '/'))
      .replaceFirst(RegExp(r'^\./'), '');

  bool _isSafeRelativeWorkspacePath(String value) =>
      value.isNotEmpty &&
      !path.isAbsolute(value) &&
      value != '..' &&
      !value.startsWith('../');

  bool _pathCovers(String declaredPath, String candidatePath) {
    if (declaredPath.isEmpty || candidatePath.isEmpty) return false;
    return candidatePath == declaredPath ||
        candidatePath.startsWith('$declaredPath/');
  }

  bool _hasDependencyCycle(Map<String, List<String>> graph) {
    final states = <String, int>{};

    bool visit(String id) {
      final state = states[id] ?? 0;
      if (state == 1) return true;
      if (state == 2) return false;
      states[id] = 1;
      for (final dependency in graph[id] ?? const <String>[]) {
        if (graph.containsKey(dependency) && visit(dependency)) return true;
      }
      states[id] = 2;
      return false;
    }

    for (final id in graph.keys) {
      if (visit(id)) return true;
    }
    return false;
  }

  List<ProjectMilestone> _initialMilestones({
    required ProjectInitialisation init,
    required List<ProjectCriterion>? criteria,
    required DateTime now,
  }) {
    final criterionIds = criteria?.map((item) => item.id).toList() ?? const [];
    final criterionStatements =
        criteria?.map((item) => item.statement).toList() ?? const [];
    final proposed = init.milestones.isEmpty
        ? [
            ProjectMilestone(
              id: 'milestone_001',
              title: 'Deliver the project outcome',
              objective: init.refinedGoal,
              criterionIds: criterionIds,
              status: ProjectMilestoneStatus.active,
              exitConditions: criterionStatements,
              order: 1,
              createdAt: now,
              updatedAt: now,
            ),
          ]
        : init.milestones;
    return [
      for (var index = 0; index < proposed.length; index++)
        ProjectMilestone(
          id: proposed[index].id,
          title: proposed[index].title,
          objective: proposed[index].objective,
          criterionIds: proposed[index].criterionIds,
          status: index == 0
              ? ProjectMilestoneStatus.active
              : ProjectMilestoneStatus.planned,
          exitConditions: proposed[index].exitConditions,
          order: proposed[index].order,
          createdAt: proposed[index].createdAt,
          updatedAt: now,
          completedAt: null,
        ),
    ];
  }

  List<ProjectMemoryEntry> _initialMemory(
    ProjectInitialisation init,
    List<String> policyAssumptions,
    DateTime now,
  ) {
    final entries = <ProjectMemoryEntry>[];
    final usedIds = <String>{};
    final contents = <String>{};
    for (var index = 0; index < init.memory.length; index++) {
      final proposed = init.memory[index];
      final content = proposed.content.trim();
      if (content.isEmpty || !contents.add(_normalise(content))) continue;
      final baseId = proposed.id.trim().isEmpty
          ? 'memory_${(index + 1).toString().padLeft(3, '0')}'
          : proposed.id;
      var id = baseId;
      var suffix = 2;
      while (!usedIds.add(id)) {
        id = '${baseId}_$suffix';
        suffix++;
      }
      entries.add(
        ProjectMemoryEntry(
          id: id,
          kind: proposed.kind,
          content: content,
          sourceType: ProjectMemorySourceType.planner,
          sourceId: proposed.sourceId,
          confidence: ProjectMemoryConfidence.inferred,
          protected: false,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    var index = entries.length + 1;
    void add(String content, ProjectMemoryKind kind) {
      if (content.trim().isEmpty || !contents.add(_normalise(content))) {
        return;
      }
      var id = 'memory_${index.toString().padLeft(3, '0')}';
      while (!usedIds.add(id)) {
        index++;
        id = 'memory_${index.toString().padLeft(3, '0')}';
      }
      entries.add(
        ProjectMemoryEntry(
          id: id,
          kind: kind,
          content: content.trim(),
          sourceType: ProjectMemorySourceType.planner,
          confidence: ProjectMemoryConfidence.inferred,
          createdAt: now,
          updatedAt: now,
        ),
      );
      index++;
    }

    for (final content in policyAssumptions) {
      add(content, ProjectMemoryKind.assumption);
    }
    return entries;
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
    ProjectPlanRevisionTrigger.batchComplete,
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

  bool _shouldRevisePlan({
    required ProjectDocument project,
    required Task? candidate,
    required List<ProjectPlanRevisionTrigger> triggers,
  }) {
    if (_activeProjectTask(project) != null || triggers.isEmpty) return false;
    if (triggers.length == 1 &&
        triggers.single == ProjectPlanRevisionTrigger.noReadyTask) {
      return candidate == null;
    }
    return true;
  }

  ProjectInitialisation _fallbackInitialisation(String originalGoal) {
    return ProjectInitialisation(
      title: _titleFromPrompt(originalGoal),
      refinedGoal: originalGoal,
      criteria: [
        ProjectCriterion(
          id: 'criterion_001',
          statement: 'Complete the stated project goal.',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ],
      constraints: const ['Stay within the attached workspace.'],
      openQuestions: const [],
      tasks: const [],
    );
  }

  ProjectDecisionRecord _decision(
    ProjectDecisionType type,
    String summary,
    String memoryUpdate, {
    Task? task,
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

  String _taskPrompt(ProjectDocument project, Task task) {
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

class _ProjectTaskValidation {
  final bool valid;
  final List<String> violations;

  const _ProjectTaskValidation(this.valid, this.violations);
}

sealed class _DuplicateProjectTaskMatch {
  final Task task;

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
  final Task failedTask;
  final List<ProjectRecoveryIncident> recoveryIncidents;
  final ProjectRecoveryIncident? incident;
  final ProjectRecoveryIncident? exhaustedIncident;
  final Task? recoveryTask;

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
