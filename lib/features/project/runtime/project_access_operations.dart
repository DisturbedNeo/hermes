// ignore_for_file: unused_element, unused_field
part of 'project_runtime_engine.dart';

extension _ProjectAccessOperations on _ProjectApplicationContext {
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

  Future<ProjectDocument> upsertUserWorkspaceNode({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    String? id,
    required String type,
    required String title,
    String description = '',
    List<String> aliases = const [],
    List<String> tags = const [],
    List<String> references = const [],
    String? sourceId,
  }) async {
    final updated = const ProjectWorkspaceGraphService().upsertUserNode(
      project: snapshot,
      id: id,
      type: type,
      title: title,
      description: description,
      aliases: aliases,
      tags: tags,
      references: references,
      sourceId: sourceId,
    );
    return _persistProject(
      workspace.rootPath,
      updated,
      checkpoint: ProjectPersistenceCheckpoint.userBoundary,
    );
  }

  Future<ProjectDocument> upsertUserWorkspaceEdge({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    String? id,
    required String sourceNodeId,
    required String targetNodeId,
    required String label,
    String description = '',
    String? sourceId,
  }) async {
    final updated = const ProjectWorkspaceGraphService().upsertUserEdge(
      project: snapshot,
      id: id,
      sourceNodeId: sourceNodeId,
      targetNodeId: targetNodeId,
      label: label,
      description: description,
      sourceId: sourceId,
    );
    return _persistProject(
      workspace.rootPath,
      updated,
      checkpoint: ProjectPersistenceCheckpoint.userBoundary,
    );
  }

  Future<Task?> _loadActiveTask(
    WorkspaceAttachment workspace,
    ProjectDocument project,
  ) {
    final taskId = project.activeTaskId;
    if (taskId == null) return Future.value();
    return _taskController.loadTask(
      workspace,
      taskId,
      chatSessionId: project.chatSessionId,
      projectId: project.id,
    );
  }

  Future<ProjectDocument> _revisePlan({
    required ModelProvider client,
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
    required ModelProvider client,
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
}
