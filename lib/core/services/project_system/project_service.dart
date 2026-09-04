import 'dart:async';
import 'dart:convert';

import 'package:hermes/core/helpers/json_parsing.dart';
import 'package:hermes/core/helpers/uuid.dart';
import 'package:hermes/core/models/compaction_settings.dart';
import 'package:hermes/core/models/project.dart';
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

typedef ProjectTaskSnapshotSink = void Function(TaskDocument? task);
typedef ProjectCompactionStatusSink = void Function(String status);

int projectTaskStepLimit(ProjectTaskEffort effort) => switch (effort) {
  ProjectTaskEffort.small => 2,
  ProjectTaskEffort.medium => 4,
  ProjectTaskEffort.large => 6,
};

class ProjectRunResult {
  final ProjectDocument project;
  final TaskDocument? activeTask;

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

  ProjectRepository get repository => _repository;

  Future<ProjectDocument> _persistProject(
    String workspaceRoot,
    ProjectDocument project,
  ) async {
    final refreshed = _scheduler.refreshReadiness(project).project;
    await _repository.saveSnapshot(workspaceRoot, refreshed);
    return refreshed;
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
  }) {
    return _repository.loadLatestProject(
      workspace.rootPath,
      chatSessionId: chatSessionId,
    );
  }

  Future<ProjectDocument?> loadProject(
    WorkspaceAttachment workspace,
    String projectId, {
    String? chatSessionId,
  }) {
    return _repository.loadProject(
      workspace.rootPath,
      projectId,
      chatSessionId: chatSessionId,
    );
  }

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
      cancellationToken: cancellationToken,
    );
    final metadata = {
      ...discovery.toMap(),
      'commandExecutionApproved': workspace.commandExecutionApproved,
    };
    final init = client == null
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
    cancellationToken?.throwIfCancelled();
    final filteredQuestions = _filterProjectQuestions(
      init.openQuestions,
      autonomy: questionAutonomy,
    );
    final initialCriteria = init.criteria.isEmpty ? null : init.criteria;
    final initialCriterionIds =
        initialCriteria?.map((item) => item.id).toList() ??
        [
          for (var index = 0; index < init.successCriteria.length; index++)
            'criterion_${(index + 1).toString().padLeft(3, '0')}',
        ];
    final initialBacklog = _normaliseInitialBacklog(
      init.backlog,
      initialCriterionIds,
    );
    final initialMilestones = _initialMilestones(
      init: init,
      criteria: initialCriteria,
      backlog: initialBacklog,
      now: now,
    );
    final initialMemory = _initialMemory(
      init,
      filteredQuestions.assumptions,
      now,
    );
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
      successCriteria: init.successCriteria.isEmpty
          ? const ['Complete the stated project goal.']
          : init.successCriteria,
      criteria: initialCriteria,
      backlog: initialBacklog,
      currentTask: null,
      completedTasks: const [],
      failedTasks: const [],
      artifacts: const [],
      memory: initialMemory,
      milestones: initialMilestones,
      currentRevision: 1,
      planHistory: [
        ProjectPlanRevision(
          revision: 1,
          trigger: ProjectPlanRevisionTrigger.initialization,
          summary: 'Initial project roadmap.',
          rationale:
              'Created criteria, milestones, and the bounded near-term plan from discovery.',
          addedTaskIds: initialBacklog.map((task) => task.id).toList(),
          criterionChanges: [
            for (final criterion
                in initialCriteria ?? const <ProjectCriterion>[])
              'add:${criterion.id}',
          ],
          milestoneChanges: [
            for (final milestone in initialMilestones) 'add:${milestone.id}',
          ],
          createdAt: now,
          approvedAt: now,
          approvedBy: ProjectPlanRevisionApprover.automatic,
        ),
      ],
      openQuestions: filteredQuestions.blocking,
      status: filteredQuestions.blocking.isEmpty
          ? ProjectStatus.active
          : ProjectStatus.waitingForUser,
      phase: ProjectPhase.discovery,
      iterationCount: 0,
      maxIterations: _normaliseOptionalLimit(
        maxIterations,
        fallback: ProjectDocument.defaultMaxIterations,
      ),
      maxFailedTasks: ProjectDocument.defaultMaxFailedTasks,
      activeTaskId: null,
      chatSessionId: chatSessionId,
      completionSummary: '',
      blocker: filteredQuestions.blocking.isEmpty
          ? null
          : ProjectBlocker(
              type: ProjectBlockerType.question,
              message: filteredQuestions.blocking.first.question,
              createdAt: now,
            ),
      decisions: const [],
      diagnostics: ProjectDiagnostics(
        projectModelCalls: client == null ? 0 : 1,
        userQuestions: filteredQuestions.blocking.length,
      ),
      createdAt: now,
      updatedAt: now,
    );
    return _persistProject(workspace.rootPath, project);
  }

  Future<ProjectDocument> updateProject({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    required String rawJson,
  }) async {
    final parsed = ModelJson.decode<ProjectDocument>(
      TaskJson.parseObject(rawJson),
    );
    final updated = parsed.copyWith(
      schemaVersion: ProjectDocument.currentSchemaVersion,
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
        phase: ProjectPhase.planning,
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
    final sourceTask = snapshot.failedTasks.reversed
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
      phase: ProjectPhase.execution,
      blocker: null,
      backlog: [
        recoveryTask,
        ...snapshot.backlog.where(
          (task) => task.recoveryIncidentId != incident.id,
        ),
      ],
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
    final pendingProposal = project.pendingPlanApproval?.proposal;
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

      final initialSchedule = _scheduler.schedule(project);
      project = initialSchedule.project;
      var candidate = project.currentTask ?? initialSchedule.selectedTask;
      final replanTriggers = [...project.pendingReplanTriggers];
      if (candidate == null && replanTriggers.isEmpty) {
        project = await _applyCompletionEvaluation(
          client: client,
          project: project,
          baseSystemPrompt: baseSystemPrompt,
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
        replanTriggers.add(ProjectPlanRevisionTrigger.noReadyTask);
      }

      if (project.currentTask == null && replanTriggers.isNotEmpty) {
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
        final revisedSchedule = _scheduler.schedule(project);
        project = revisedSchedule.project;
        candidate = revisedSchedule.selectedTask;
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

      final resumingActiveTask =
          project.currentTask?.id == candidate.id &&
          project.activeTaskId != null &&
          activeTask?.id == project.activeTaskId;
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
          onModelOutput: onModelOutput,
          cancellationToken: cancellationToken,
        );
        if (project.status == ProjectStatus.blocked) {
          project = await _persistProject(workspace.rootPath, project);
          return ProjectRunResult(project: project, activeTask: activeTask);
        }
        final recoveryMadeProgress = _invalidTaskRecoveryMadeProgress(
          before: projectBeforeRecovery,
          after: project,
        );
        if (recoveryMadeProgress) {
          consecutiveInvalidCandidates = 0;
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
        phase: ProjectPhase.verification,
        updatedAt: now,
      );
      project = await _persistProject(workspace.rootPath, project);

      final evaluatedProjectTask = project.currentTask ?? candidate;
      final criterionStatusesBefore = {
        for (final criterion in project.criteria)
          criterion.id: criterion.status,
      };
      final acceptedEvidenceIdsBefore = {
        for (final item in project.evidence)
          if (item.status == ProjectEvidenceStatus.accepted) item.id,
      };
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
      project = await _applyCompletionEvaluation(
        client: client,
        project: project,
        baseSystemPrompt: baseSystemPrompt,
        onModelOutput: onModelOutput,
        questionAutonomy: questionAutonomy,
        cancellationToken: cancellationToken,
      );
      project = _recordTransitionReplanTriggers(
        project: project,
        evaluation: evaluation,
        invalidEvidenceIdsBefore: invalidEvidenceIds,
        now: now,
      );
      project = _progressMonitor.recordTaskResult(
        project: project,
        task: evaluatedProjectTask,
        taskAccepted: evaluation.taskAccepted,
        criterionStatusesBefore: criterionStatusesBefore,
        acceptedEvidenceIdsBefore: acceptedEvidenceIdsBefore,
        evaluatedAt: now,
      );
      project = project.copyWith(
        iterationCount: project.iterationCount + 1,
        updatedAt: DateTime.now(),
      );
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
    final question = snapshot.pendingQuestion;
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
        ProjectPlanRevisionTrigger.newContext,
      ),
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
    if (snapshot.pendingQuestion != null) {
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
      pendingReplanTriggers: _appendTrigger(
        snapshot.pendingReplanTriggers,
        ProjectPlanRevisionTrigger.newContext,
      ),
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

  /// Queues a user-requested rolling plan revision.
  ///
  /// The optional reason is retained as protected project memory so it is
  /// available to the planner and survives later context compaction.
  Future<ProjectDocument> requestManualReplan({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    String reason = '',
  }) async {
    if (snapshot.isTerminal || snapshot.pendingPlanApproval != null) {
      return snapshot;
    }
    final now = DateTime.now();
    var updated = snapshot.copyWith(
      status: ProjectStatus.active,
      blocker:
          snapshot.blocker?.type == ProjectBlockerType.planApproval ||
              snapshot.blocker?.type == ProjectBlockerType.stagnation
          ? null
          : snapshot.blocker,
      pendingReplanTriggers: _appendTrigger(
        snapshot.pendingReplanTriggers,
        ProjectPlanRevisionTrigger.manual,
      ),
      updatedAt: now,
      diagnostics: snapshot.diagnostics.copyWith(
        consecutiveNoProgressIterations: 0,
        recentNoProgressTaskIds: const [],
      ),
    );
    final trimmedReason = reason.trim();
    if (trimmedReason.isNotEmpty) {
      updated = _memoryService
          .record(
            project: updated,
            kind: ProjectMemoryKind.requirement,
            content: 'User requested replanning: $trimmedReason',
            sourceType: ProjectMemorySourceType.user,
            sourceId: 'manual_replan_${now.microsecondsSinceEpoch}',
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

  Future<ProjectDocument> approveNextProjectTask({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
  }) async {
    final task = snapshot.currentTask;
    if (task == null) return snapshot;
    final updated = snapshot.copyWith(
      currentTask: task.copyWith(
        status: ProjectTaskStatus.approved,
        updatedAt: DateTime.now(),
      ),
      status: ProjectStatus.active,
      blocker: null,
      updatedAt: DateTime.now(),
      diagnostics: snapshot.diagnostics.copyWith(
        userApprovals: snapshot.diagnostics.userApprovals + 1,
      ),
    );
    return _persistProject(workspace.rootPath, updated);
  }

  Future<ProjectDocument> clearTaskBlocker({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
  }) async {
    final type = snapshot.blocker?.type;
    if (type != ProjectBlockerType.taskApproval &&
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
    final updated = snapshot.copyWith(
      status: ProjectStatus.cancelled,
      activeTaskId: null,
      currentTask: snapshot.currentTask?.copyWith(
        status: ProjectTaskStatus.cancelled,
        updatedAt: now,
      ),
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

  Future<TaskDocument?> _loadActiveTask(
    WorkspaceAttachment workspace,
    ProjectDocument project,
  ) {
    final activeTaskId = project.activeTaskId;
    if (activeTaskId == null) return Future.value();
    return _taskService.loadTask(
      workspace,
      activeTaskId,
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
      cancellationToken: cancellationToken,
    );
    final planningProject = _projectForModel(project);
    final proposal = await _modelCalls.revisePlan(
      client: client,
      baseSystemPrompt: baseSystemPrompt,
      workspace: workspace,
      project: planningProject,
      evidenceSnapshot: snapshot,
      triggers: debouncedTriggers,
      onModelOutput: onModelOutput,
      cancellationToken: cancellationToken,
    );
    final result = await _planRevisionService.prepareAndApply(
      project: project,
      proposal: proposal,
      workspaceRoot: workspace.rootPath,
      approvalPolicy: approvalPolicy,
      repair: (invalid, validation) {
        return _modelCalls.repairPlanProposal(
          client: client,
          baseSystemPrompt: baseSystemPrompt,
          workspace: workspace,
          project: planningProject,
          proposal: invalid,
          validationIssues: validation.issues
              .map((item) => item.toMap())
              .toList(),
          onModelOutput: onModelOutput,
          cancellationToken: cancellationToken,
        );
      },
    );
    var revised = result.project.copyWith(
      diagnostics: result.project.diagnostics.copyWith(
        projectModelCalls:
            result.project.diagnostics.projectModelCalls +
            1 +
            (result.repairAttempted ? 1 : 0),
        planRevisionAttempts:
            result.project.diagnostics.planRevisionAttempts + 1,
        invalidPlanProposals:
            result.project.diagnostics.invalidPlanProposals +
            (result.repairAttempted || !result.validation.valid ? 1 : 0),
      ),
    );
    if (revised.openQuestions.isNotEmpty) {
      final filtered = _filterProjectQuestions(
        revised.openQuestions,
        autonomy: questionAutonomy,
      );
      revised = revised.copyWith(
        openQuestions: filtered.blocking,
        status: filtered.blocking.isEmpty && !result.awaitingApproval
            ? ProjectStatus.active
            : revised.status,
        blocker: filtered.blocking.isEmpty && !result.awaitingApproval
            ? null
            : revised.blocker,
        updatedAt: DateTime.now(),
      );
      revised = _recordAssumptions(
        revised,
        filtered.assumptions,
        sourceId: 'revision_${revised.currentRevision}',
      );
    }
    return revised;
  }

  bool _invalidTaskRecoveryMadeProgress({
    required ProjectDocument before,
    required ProjectDocument after,
  }) {
    final currentTask = after.currentTask;
    if (currentTask != null && _validateProjectTask(currentTask, after).valid) {
      return true;
    }

    final previousBacklogIds = before.backlog.map((task) => task.id).toSet();
    final refreshed = _scheduler.refreshReadiness(after).project;
    return refreshed.backlog.any(
      (task) =>
          !previousBacklogIds.contains(task.id) &&
          _isSelectableTask(task) &&
          _validateProjectTask(task, refreshed).valid,
    );
  }

  bool _hasExecutableProjectTask(ProjectDocument project) {
    final currentTask = project.currentTask;
    return (currentTask != null &&
            _validateProjectTask(currentTask, project).valid) ||
        _scheduler.schedule(project).selectedTask != null;
  }

  bool _isSelectableTask(ProjectTask task) {
    return (task.status == ProjectTaskStatus.queued ||
            task.status == ProjectTaskStatus.proposed ||
            task.status == ProjectTaskStatus.approved) &&
        task.readiness == ProjectTaskReadiness.ready;
  }

  Future<ProjectDocument> _handleInvalidProjectTask({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required ProjectDocument project,
    required ProjectTask task,
    required List<String> violations,
    required String baseSystemPrompt,
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
          currentTask: duplicate.task,
          status: ProjectStatus.active,
          phase: ProjectPhase.execution,
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
          status: ProjectTaskStatus.rejected,
          rejectionReason: violations.join('\n'),
          updatedAt: now,
        );
        return project.copyWith(
          currentTask: retryTask,
          failedTasks: [...project.failedTasks, rejected],
          status: ProjectStatus.active,
          phase: ProjectPhase.execution,
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
        status: ProjectTaskStatus.rejected,
        rejectionReason: violations.join('\n'),
        updatedAt: now,
      );
      return project.copyWith(
        failedTasks: [...project.failedTasks, rejected],
        backlog: project.backlog.where((item) => item.id != task.id).toList(),
        status: ProjectStatus.active,
        phase: ProjectPhase.planning,
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

    final split = await _modelCalls.splitTask(
      client: client,
      baseSystemPrompt: baseSystemPrompt,
      project: _projectForModel(project, task: task),
      oversizedTask: task,
      violations: violations,
      onModelOutput: onModelOutput,
      cancellationToken: cancellationToken,
    );
    final known = _knownFingerprints(project)..add(task.fingerprint);
    final splitTasks = _normaliseBacklog(split)
        .where((item) => !known.contains(item.fingerprint))
        .where((item) => _validateProjectTask(item, project).valid)
        .take(5)
        .toList();

    final now = DateTime.now();
    final rejected = task.copyWith(
      status: splitTasks.isEmpty
          ? ProjectTaskStatus.rejected
          : ProjectTaskStatus.split,
      rejectionReason: violations.join('\n'),
      updatedAt: now,
    );
    if (splitTasks.isEmpty) {
      return _blockProject(
        project.copyWith(
          failedTasks: [...project.failedTasks, rejected],
          backlog: project.backlog.where((item) => item.id != task.id).toList(),
          decisions: [
            ...project.decisions,
            _decision(
              ProjectDecisionType.rejectTask,
              'Rejected oversized project task: ${task.title}',
              violations.join('\n'),
              task: rejected,
            ),
          ],
          diagnostics: project.diagnostics.copyWith(
            projectModelCalls: project.diagnostics.projectModelCalls + 1,
          ),
          updatedAt: now,
        ),
        ProjectBlockerType.validation,
        'Project task was too broad and could not be split safely: ${violations.join('; ')}',
        now,
      );
    }

    return project.copyWith(
      backlog: [
        ...splitTasks,
        ...project.backlog.where((item) => item.id != task.id),
      ],
      failedTasks: [...project.failedTasks, rejected],
      status: ProjectStatus.active,
      phase: ProjectPhase.planning,
      decisions: [
        ...project.decisions,
        _decision(
          ProjectDecisionType.splitTask,
          'Split oversized project task into ${splitTasks.length} smaller task(s).',
          violations.join('\n'),
          task: rejected,
        ),
      ],
      diagnostics: project.diagnostics.copyWith(
        projectModelCalls: project.diagnostics.projectModelCalls + 1,
      ),
      updatedAt: now,
    );
  }

  Future<_ProjectTaskExecution> _executeProjectTask({
    required ChatClient client,
    required WorkspaceAttachment workspace,
    required ProjectDocument project,
    required ProjectTask projectTask,
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
    final runningProjectTask = projectTask.copyWith(
      status: ProjectTaskStatus.running,
      updatedAt: now,
    );
    var workingProject = project.copyWith(
      status: ProjectStatus.runningTask,
      phase: ProjectPhase.execution,
      currentTask: runningProjectTask,
      backlog: project.backlog
          .where((task) => task.id != projectTask.id)
          .toList(),
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
    workingProject = await _persistProject(workspace.rootPath, workingProject);

    final existingTask = workingProject.activeTaskId == null
        ? null
        : await _loadActiveTask(workspace, workingProject);
    var activeTask =
        existingTask ??
        await _taskService.createTask(
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
          planningContext: _planningContext(workingProject, projectTask),
          onModelOutput: onModelOutput,
          cancellationToken: cancellationToken,
        );
    final taskDocumentId = activeTask.id;
    workingProject = workingProject.copyWith(
      activeTaskId: taskDocumentId,
      currentTask: runningProjectTask.copyWith(
        taskDocumentId: taskDocumentId,
        updatedAt: DateTime.now(),
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
      );
      onTaskUpdated?.call(activeTask);
    }

    final result = _taskResultFromTask(workingProject.currentTask!, activeTask);
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
    ProjectTask projectTask,
    TaskResult result,
    ProjectDocument project,
  ) {
    final accepted = result.status == TaskStatus.completed;
    return ProjectEvaluation(
      projectTaskId: projectTask.id,
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
      backlogAdditions: const [],
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
    required ProjectTask task,
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
    final task = project.currentTask;
    if (task == null) return project;
    final filteredQuestions = _filterProjectQuestions(
      evaluation.openQuestions,
      autonomy: questionAutonomy,
    );
    if (!evaluation.taskAccepted) {
      final failure = _projectTaskFailure(evaluation);
      var failedTask = task.copyWith(
        status: ProjectTaskStatus.failed,
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
      final failedTasks = [...project.failedTasks, failedTask];
      final recoveryIncidents = recoveryUpdate.recoveryIncidents;
      final failedBudgetCount = _projectFailureBudgetCount(
        failedTasks,
        recoveryIncidents,
      );
      final reachedFailureLimit = failedBudgetCount >= project.maxFailedTasks;
      final exhaustedIncident = recoveryUpdate.exhaustedIncident;
      final blockingFailure =
          failure.disposition == TaskGateFailureDisposition.blocking &&
          recoveryUpdate.incident == null;
      var updated = project.copyWith(
        currentTask: null,
        activeTaskId: null,
        failedTasks: failedTasks,
        backlog: [
          if (recoveryUpdate.recoveryTask != null) recoveryUpdate.recoveryTask!,
          ...project.backlog.where(
            (item) => item.id != recoveryUpdate.recoveryTask?.id,
          ),
        ],
        recoveryIncidents: recoveryIncidents,
        openQuestions: filteredQuestions.blocking,
        status: exhaustedIncident != null || blockingFailure
            ? ProjectStatus.blocked
            : reachedFailureLimit
            ? ProjectStatus.blocked
            : ProjectStatus.active,
        phase: ProjectPhase.execution,
        blocker: exhaustedIncident != null
            ? ProjectBlocker(
                type: ProjectBlockerType.recoveryFailed,
                message:
                    'Recovery incident `${exhaustedIncident.id}` reached the maximum repair attempt limit of ${exhaustedIncident.maxAttempts}.',
                taskId: failedTask.taskDocumentId ?? failedTask.id,
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
                taskId: failedTask.taskDocumentId ?? failedTask.id,
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
      status: ProjectTaskStatus.completed,
      updatedAt: now,
    );
    final recoveryIncidents = _resolveRecoveryIncidentForTask(
      project.recoveryIncidents,
      completedTask,
      now,
    );
    var updated = project.copyWith(
      currentTask: null,
      activeTaskId: null,
      completedTasks: [...project.completedTasks, completedTask],
      artifacts: _mergeArtifacts(project.artifacts, evaluation.artifacts),
      recoveryIncidents: recoveryIncidents,
      openQuestions: filteredQuestions.blocking,
      backlog: [...evaluation.backlogAdditions, ...project.backlog],
      status: filteredQuestions.blocking.isEmpty
          ? ProjectStatus.active
          : ProjectStatus.waitingForUser,
      phase: ProjectPhase.execution,
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
              project.failedTasks,
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
    if (!_hasReviewableCriterionEvidence(project)) {
      return project.copyWith(
        status: ProjectStatus.active,
        phase: project.backlog.isEmpty
            ? ProjectPhase.planning
            : ProjectPhase.execution,
        updatedAt: now,
      );
    }

    final assessment = await _modelCalls.evaluateCompletion(
      client: client,
      baseSystemPrompt: baseSystemPrompt,
      project: project,
      onModelOutput: onModelOutput,
      cancellationToken: cancellationToken,
    );
    final assessedProject = project.copyWith(
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
            phase: project.backlog.isEmpty
                ? ProjectPhase.planning
                : ProjectPhase.execution,
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
    final reviewed = _criterionEvaluator.applyModelReview(
      assessedProject,
      projectComplete: assessment.complete,
      remainingCriteria: assessment.remainingCriteria,
      rationale: assessment.finalSummary,
      evaluatedAt: now,
    );
    if (_remainingCriteria(reviewed).isEmpty) {
      return _completeProjectFromEvidence(
        reviewed,
        now,
        summary: assessment.finalSummary,
      );
    }
    return reviewed.copyWith(
      status: ProjectStatus.active,
      phase: reviewed.backlog.isEmpty
          ? ProjectPhase.planning
          : ProjectPhase.execution,
      updatedAt: now,
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

  ProjectDocument _completeProjectFromEvidence(
    ProjectDocument project,
    DateTime now, {
    String summary = '',
  }) {
    return project.copyWith(
      status: ProjectStatus.completed,
      phase: ProjectPhase.finalization,
      completionSummary: summary.trim().isEmpty
          ? 'All required project criteria are satisfied by accepted evidence.'
          : summary.trim(),
      completedAt: now,
      blocker: null,
      updatedAt: now,
    );
  }

  _ProjectTaskValidation _validateProjectTask(
    ProjectTask task,
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
    if (task.relevantSuccessCriteria.length > 3) {
      violations.add('Task covers too many success criteria.');
    }
    if (project.successCriteria.length > 1 &&
        task.relevantSuccessCriteria.length >= project.successCriteria.length) {
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
    ProjectTask task,
  ) {
    if (task.recoveryIncidentId != null) return null;
    final fingerprint = task.fingerprint;
    for (final queued in project.backlog) {
      if (queued.id != task.id && queued.fingerprint == fingerprint) {
        return _QueuedDuplicateProjectTask(queued);
      }
    }
    final current = project.currentTask;
    if (current != null &&
        current.id != task.id &&
        current.fingerprint == fingerprint) {
      return _QueuedDuplicateProjectTask(current);
    }
    for (final failed in project.failedTasks) {
      if (failed.id != task.id &&
          failed.status == ProjectTaskStatus.failed &&
          failed.recoveryIncidentId == null &&
          failed.fingerprint == fingerprint) {
        return _FailedDuplicateProjectTask(failed);
      }
    }
    return null;
  }

  ProjectTask _retryTaskForFailedDuplicate({
    required ProjectTask failedTask,
    required ProjectTask duplicateTask,
    required List<String> violations,
    required DateTime now,
  }) {
    final criteria = duplicateTask.relevantSuccessCriteria.isEmpty
        ? failedTask.relevantSuccessCriteria
        : duplicateTask.relevantSuccessCriteria;
    final objective =
        'Retry failed project task after addressing the previous failure: ${failedTask.objective}';
    return ProjectTask(
      id: 'project_retry_${uuid.v7()}',
      title: 'Retry ${failedTask.title}',
      objective: objective,
      relevantSuccessCriteria: criteria,
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
      expectedArtifacts: duplicateTask.expectedArtifacts.isEmpty
          ? failedTask.expectedArtifacts
          : duplicateTask.expectedArtifacts,
      status: ProjectTaskStatus.queued,
      taskDocumentId: null,
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
    ProjectTask task,
  ) {
    final memoryContext = _memoryService.selectContext(
      project: project,
      task: task,
    );
    return TaskPlanningContext(
      projectGoal: project.refinedGoal,
      projectTaskObjective: task.objective,
      knownFacts: [...memoryContext.lines, ...task.context],
      doneCriteria: task.doneCriteria,
      outOfScope: task.outOfScope,
      expectedArtifacts: task.expectedArtifacts
          .map(
            (artifact) => TaskArtifact(
              path: artifact.path,
              description: artifact.description,
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
      maxSteps: projectTaskStepLimit(task.effort),
    );
  }

  ProjectTask? _activeRecoveryTask(ProjectDocument project) {
    final activeIncidents =
        project.recoveryIncidents
            .where(
              (incident) =>
                  incident.status == ProjectRecoveryIncidentStatus.active,
            )
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    for (final incident in activeIncidents) {
      for (final taskId in incident.recoveryTaskIds.reversed) {
        final task = project.backlog
            .where((item) => item.id == taskId)
            .firstOrNull;
        if (task != null) return task;
      }
      final fallback = project.backlog
          .where((task) => task.recoveryIncidentId == incident.id)
          .firstOrNull;
      if (fallback != null) return fallback;
    }
    return null;
  }

  _RecoveryUpdate _recoveryUpdateForFailedTask({
    required ProjectDocument project,
    required ProjectTask failedTask,
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
                failedTask.taskDocumentId ?? failedTask.id,
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
    required ProjectTask failedTask,
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

  ProjectTaskFailure _projectTaskFailure(ProjectEvaluation evaluation) {
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
    return ProjectTaskFailure(
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

  ProjectTask _recoveryTaskForIncident({
    required String incidentId,
    required ProjectTask sourceTask,
    required _RecoveryFailure failure,
    required int attemptNumber,
    required DateTime now,
  }) {
    final command = failure.command?.trim();
    final gateTarget = command?.isNotEmpty == true
        ? '${failure.gateResult.gateId}: $command'
        : failure.gateResult.gateId;
    final objective = 'Restore required project health gate: $gateTarget';
    return ProjectTask(
      id: 'project_recovery_${uuid.v7()}',
      title: 'Recover project health',
      objective: objective,
      relevantSuccessCriteria: sourceTask.relevantSuccessCriteria,
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
      expectedArtifacts: const [],
      status: ProjectTaskStatus.queued,
      taskDocumentId: null,
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
    ProjectTask completedTask,
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
    ProjectTask task,
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
    List<ProjectTask> failedTasks,
    List<ProjectRecoveryIncident> recoveryIncidents,
  ) {
    final nonRecoveryFailures = failedTasks
        .where(
          (task) =>
              task.status == ProjectTaskStatus.failed &&
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

  TaskResult _taskResultFromTask(ProjectTask projectTask, TaskDocument task) {
    final latestRun = task.runs.isEmpty ? null : task.runs.last;
    final artifacts = <ProjectArtifact>[
      for (final run in task.runs)
        for (final artifact in run.artifacts)
          ProjectArtifact(
            id: 'artifact_${uuid.v7()}',
            projectTaskId: projectTask.id,
            taskDocumentId: task.id,
            taskRunId: run.runId,
            path: artifact.path,
            description: artifact.description ?? '',
            kind: 'file',
            createdAt: artifact.createdAt ?? DateTime.now(),
          ),
    ];
    return TaskResult(
      taskDocumentId: task.id,
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

  (ProjectBlockerType, String)? _taskBlocker(TaskDocument task) {
    if (task.pendingApproval != null) {
      return (ProjectBlockerType.taskApproval, task.pendingApproval!.reason);
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
    TaskDocument task,
    DateTime now,
  ) {
    final current = project.currentTask;
    if (current == null) return project;
    return project.copyWith(
      currentTask: current.copyWith(
        taskDocumentId: task.id,
        status: switch (task.status) {
          TaskStatus.completed => ProjectTaskStatus.completed,
          TaskStatus.failed => ProjectTaskStatus.failed,
          TaskStatus.cancelled => ProjectTaskStatus.cancelled,
          _ => ProjectTaskStatus.running,
        },
        updatedAt: now,
      ),
      activeTaskId: task.id,
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

  List<ProjectArtifact> _mergeArtifacts(
    List<ProjectArtifact> current,
    List<ProjectArtifact> additions,
  ) {
    final byPath = <String, ProjectArtifact>{
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
    required ProjectTask task,
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
            confidence: accepted
                ? ProjectMemoryConfidence.confirmed
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
            confidence: accepted
                ? ProjectMemoryConfidence.confirmed
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
    ProjectTask? task,
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
      for (final task in project.backlog)
        if (task.id != excludingTaskId) task.fingerprint,
      if (project.currentTask != null &&
          project.currentTask!.id != excludingTaskId)
        project.currentTask!.fingerprint,
      for (final task in project.completedTasks)
        if (task.id != excludingTaskId) task.fingerprint,
      for (final task in project.failedTasks)
        if (task.id != excludingTaskId && task.recoveryIncidentId == null)
          task.fingerprint,
      for (final decision in project.decisions)
        if (decision.taskPrompt?.trim().isNotEmpty == true)
          projectTaskFingerprint(decision.taskPrompt!, const []),
    };
  }

  List<ProjectTask> _normaliseBacklog(List<ProjectTask> tasks) {
    final seen = <String>{};
    return [
      for (final task in tasks)
        if (task.objective.trim().isNotEmpty && seen.add(task.fingerprint))
          task.copyWith(
            status: task.status == ProjectTaskStatus.running
                ? ProjectTaskStatus.queued
                : task.status,
            updatedAt: DateTime.now(),
          ),
    ];
  }

  List<ProjectTask> _normaliseInitialBacklog(
    List<ProjectTask> tasks,
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
                ProjectEvidenceExpectation(
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

  List<ProjectMilestone> _initialMilestones({
    required ProjectInitialisation init,
    required List<ProjectCriterion>? criteria,
    required List<ProjectTask> backlog,
    required DateTime now,
  }) {
    final criterionIds =
        criteria?.map((item) => item.id).toList() ??
        [
          for (var index = 0; index < init.successCriteria.length; index++)
            'criterion_${(index + 1).toString().padLeft(3, '0')}',
        ];
    final proposed = init.milestones.isEmpty
        ? [
            ProjectMilestone(
              id: 'milestone_001',
              title: 'Deliver the project outcome',
              objective: init.refinedGoal,
              criterionIds: criterionIds,
              status: ProjectMilestoneStatus.active,
              exitConditions: init.successCriteria,
              taskIds: backlog.map((item) => item.id).toList(),
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
              : proposed[index].status,
          exitConditions: proposed[index].exitConditions,
          taskIds: {
            ...proposed[index].taskIds,
            ...backlog
                .where((task) => task.milestoneId == proposed[index].id)
                .map((task) => task.id),
          }.toList(),
          order: proposed[index].order,
          createdAt: proposed[index].createdAt,
          updatedAt: now,
          completedAt: proposed[index].completedAt,
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
          confidence: proposed.confidence,
          protected:
              proposed.kind == ProjectMemoryKind.requirement ||
              proposed.kind == ProjectMemoryKind.decision ||
              proposed.kind == ProjectMemoryKind.risk,
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

    for (final content in init.knownFacts) {
      add(content, ProjectMemoryKind.fact);
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
    final completedTaskIds = project.completedTasks
        .map((item) => item.id)
        .toSet();
    milestones = [
      for (final milestone in milestones)
        if (milestone.status != ProjectMilestoneStatus.completed &&
            ((milestone.criterionIds.isNotEmpty &&
                    milestone.criterionIds.every(
                      satisfiedCriterionIds.contains,
                    )) ||
                (milestone.taskIds.isNotEmpty &&
                    milestone.taskIds.every(completedTaskIds.contains))))
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
                taskIds: milestone.taskIds,
                order: milestone.order,
                createdAt: milestone.createdAt,
                updatedAt: now,
              );
            })()
          else
            milestone,
      ];
    }

    var triggers = [...project.pendingReplanTriggers];
    if (milestoneCompleted) {
      triggers = _appendTrigger(
        triggers,
        ProjectPlanRevisionTrigger.milestoneCompleted,
      );
    }
    final readyCount = project.backlog.where((task) {
      return task.status == ProjectTaskStatus.queued &&
          task.readiness == ProjectTaskReadiness.ready;
    }).length;
    final completedSinceRevision = project.completedTasks.where((task) {
      return task.revisionUpdated >= project.currentRevision;
    }).length;
    if (evaluation.taskAccepted &&
        (readyCount < 2 ||
            completedSinceRevision >= 3 ||
            evaluation.newKnownFacts.isNotEmpty ||
            evaluation.artifacts.isNotEmpty)) {
      triggers = _appendTrigger(
        triggers,
        ProjectPlanRevisionTrigger.taskCompleted,
      );
    }
    if (!evaluation.taskAccepted && _activeRecoveryTask(project) == null) {
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
    return project.copyWith(
      milestones: milestones,
      pendingReplanTriggers: project.isTerminal ? const [] : triggers,
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
      taskIds: milestone.taskIds,
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

  ProjectInitialisation _fallbackInitialisation(String originalGoal) {
    return ProjectInitialisation(
      title: _titleFromPrompt(originalGoal),
      refinedGoal: originalGoal,
      successCriteria: const ['Complete the stated project goal.'],
      constraints: const ['Stay within the attached workspace.'],
      knownFacts: const [],
      openQuestions: const [],
      backlog: const [],
    );
  }

  ProjectDecisionRecord _decision(
    ProjectDecisionType type,
    String summary,
    String memoryUpdate, {
    ProjectTask? task,
    String? error,
  }) {
    return ProjectDecisionRecord(
      id: 'decision_${uuid.v7()}',
      decision: type,
      summary: summary,
      memoryUpdate: memoryUpdate,
      taskId: task?.taskDocumentId ?? task?.id,
      taskTitle: task?.title,
      taskPrompt: task?.objective,
      error: error,
      createdAt: DateTime.now(),
    );
  }

  String _taskPrompt(ProjectDocument project, ProjectTask task) {
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
    TaskDocument? task,
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
  final ProjectTask task;

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
  final TaskDocument? activeTask;
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
  final ProjectTask failedTask;
  final List<ProjectRecoveryIncident> recoveryIncidents;
  final ProjectRecoveryIncident? incident;
  final ProjectRecoveryIncident? exhaustedIncident;
  final ProjectTask? recoveryTask;

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
