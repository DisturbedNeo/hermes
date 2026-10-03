part of 'project_execution_state_machine.dart';

extension ProjectExecutionOperations on ProjectExecutionUseCase {
  bool _isBootstrapShell(ProjectAggregate project) =>
      project.tasks.isEmpty &&
      project.criteria.isEmpty &&
      project.milestones.isEmpty;

  ProjectTaskNode? _activeProjectTask(ProjectAggregate project) {
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

  List<ProjectTaskNode> _nonTerminalTasks(ProjectAggregate project) =>
      project.tasks.where((task) => !_isTerminalTask(task)).toList();

  List<ProjectTaskNode> _upsertTask(
    ProjectAggregate project,
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

  ProjectAggregate _transitionProject({
    required ProjectAggregate snapshot,
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

  int _currentPlanRevision(ProjectAggregate project) {
    var revision = 0;
    for (final item in project.planHistory) {
      if (item.revision > revision) revision = item.revision;
    }
    return revision;
  }

  Future<ProjectAggregate> _startBatch({
    required String workspaceRoot,
    required ProjectAggregate project,
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

  ProjectAggregate _clearBatch(ProjectAggregate project) {
    return project.copyWith(
      currentBatchTaskIds: const [],
      currentBatchIndex: 0,
      currentBatchPlanRevision: 0,
      currentBatchProgressObserved: false,
      pendingReplanReason: null,
    );
  }

  ProjectTaskNode? _currentBatchTask(ProjectAggregate project) {
    final id = project.currentBatchTaskId;
    return id == null ? null : project.taskById(id);
  }

  ProjectAggregate _advanceBatchCursor(
    ProjectAggregate project,
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

  Future<ProjectAggregate> _hydrateProjectTasks(
    WorkspaceAttachment workspace,
    ProjectAggregate project,
  ) => _persistenceCoordinator.hydrateProjectTasks(workspace, project);

  Future<TaskAggregate?> _loadActiveTask(
    WorkspaceAttachment workspace,
    ProjectAggregate project,
  ) => _persistenceCoordinator.loadActiveTask(workspace, project);

  Future<ProjectAggregate> _revisePlan({
    required ModelConversationPort client,
    required WorkspaceAttachment workspace,
    required ProjectAggregate project,
    required List<ProjectPlanRevisionTrigger> triggers,
    required String baseSystemPrompt,
    required ProjectPlanApprovalPolicy approvalPolicy,
    ProjectPlanningPass planningPass = ProjectPlanningPass.maintenance,
    ProjectPlanningLimits planningLimits = ProjectPlanningLimits.maintenance,
    required QuestionAutonomy questionAutonomy,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    final revision = await _planRevisionCoordinator.revise(
      ProjectPlanRevisionRequest(
        client: client,
        workspace: workspace,
        project: project,
        triggers: triggers,
        baseSystemPrompt: baseSystemPrompt,
        approvalPolicy: approvalPolicy,
        planningPass: planningPass,
        planningLimits: planningLimits,
        onModelOutput: onModelOutput,
        cancellationToken: cancellationToken,
      ),
    );
    if (revision.hasContextIssues) {
      final message = _planningContextBlockerMessage([
        for (final issue in revision.contextIssues)
          ProjectPlanValidationIssue(
            code: issue.code,
            path: issue.path,
            message: issue.message,
          ),
      ]);
      if (planningPass == ProjectPlanningPass.bootstrap) {
        return _controlStateService.withOutcome(
          _clearBatch(project),
          outcome: ProjectControlOutcome.degradedPlanning,
          message: message,
          action: 'retry_planning',
          reasonCode: 'planning_context_unavailable',
          now: DateTime.now(),
        );
      }
      return _blockProject(
        _clearBatch(project),
        ProjectBlockerType.validation,
        message,
        DateTime.now(),
      );
    }
    final incremental = revision.incremental!;
    final revised = _finishPlanRevision(
      revised: incremental.project,
      questionAutonomy: questionAutonomy,
      modelCalls: incremental.modelCalls,
      planningMetrics: incremental.planningMetrics,
      invalidPlan: !incremental.committed,
      awaitingApproval: incremental.awaitingApproval,
      planningError: incremental.error,
      planningPass: planningPass,
    );
    return revised.copyWith(
      id: project.id,
      persistenceRevision: project.persistenceRevision,
      createdAt: project.createdAt,
      chatSessionId: project.chatSessionId,
    );
  }

  ProjectAggregate _finishPlanRevision({
    required ProjectAggregate revised,
    required QuestionAutonomy questionAutonomy,
    required int modelCalls,
    required bool invalidPlan,
    required bool awaitingApproval,
    PlanningMetrics planningMetrics = const PlanningMetrics(),
    String? planningError,
    ProjectPlanningPass planningPass = ProjectPlanningPass.maintenance,
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
      return _controlStateService.withOutcome(
        revised,
        outcome: ProjectControlOutcome.degradedPlanning,
        message:
            'Incremental plan revision did not commit: ${planningError.trim()}',
        action: 'retry_planning',
        reasonCode: 'planning_failed',
        now: DateTime.now(),
      );
    }
    if (planningPass == ProjectPlanningPass.bootstrap && invalidPlan) {
      return _controlStateService.withOutcome(
        revised.copyWith(
          status: ProjectStatus.active,
          blocker: null,
          pendingPlanApproval: null,
        ),
        outcome: ProjectControlOutcome.degradedPlanning,
        message: 'The first project slice did not pass plan validation.',
        action: 'retry_planning',
        reasonCode: 'bootstrap_plan_invalid',
        now: DateTime.now(),
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
    required ProjectAggregate before,
    required ProjectAggregate after,
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

  bool _hasExecutableProjectTask(ProjectAggregate project) {
    final currentTask = _activeProjectTask(project);
    return (currentTask != null &&
            _validateProjectTask(currentTask, project).valid) ||
        _scheduler.schedule(project).selectedTask != null;
  }

  bool _isSelectableTask(ProjectTaskNode task) {
    return task.status == TaskStatus.queued;
  }

  Future<ProjectAggregate> _handleInvalidProjectTask({
    required ModelConversationPort client,
    required WorkspaceAttachment workspace,
    required ProjectAggregate project,
    required ProjectTaskNode task,
    required List<String> violations,
    required String baseSystemPrompt,
    required ProjectPlanApprovalPolicy approvalPolicy,
    ModelOutputSink? onModelOutput,
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
      planningPass: ProjectPlanningPass.split,
      planningLimits: ProjectPlanningLimits.split,
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
    ProjectAggregate project,
  ) => _evaluationCoordinator.evaluateTaskResult(projectTask, result, project);

  ProjectAggregate _applyTaskEvidence({
    required ProjectAggregate project,
    required ProjectTaskNode task,
    required TaskResult result,
    required DateTime evaluatedAt,
  }) => _evaluationCoordinator.applyTaskEvidence(
    project: project,
    task: task,
    result: result,
    evaluatedAt: evaluatedAt,
  );

  ProjectAggregate _updateProjectState(
    ProjectAggregate project,
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
      final failure = _recoveryPolicy.taskFailure(evaluation);
      var failedTask = task.copyWith(
        status: TaskStatus.failed,
        rejectionReason: evaluation.failureReason,
        failureKey: failure.failureKey,
        updatedAt: now,
      );
      final recoveryUpdate = _recoveryPolicy.recoveryUpdateForFailedTask(
        project: project,
        failedTask: failedTask,
        evaluation: evaluation,
        now: now,
      );
      failedTask = recoveryUpdate.failedTask;
      final tasks = _upsertTask(project, failedTask);
      final recoveryIncidents = recoveryUpdate.recoveryIncidents;
      final failedBudgetCount = _recoveryPolicy.projectFailureBudgetCount(
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
    final recoveryIncidents = _recoveryPolicy.resolveRecoveryIncidentForTask(
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

  // Project evaluation operations
  Future<ProjectAggregate> _applyCompletionEvaluation({
    required ModelConversationPort client,
    required ProjectAggregate project,
    required String baseSystemPrompt,
    ProjectCompletionReviewReason? reviewReason,
    String? reviewMilestoneId,
    ModelOutputSink? onModelOutput,
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
        _recoveryPolicy.projectFailureBudgetCount(
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

  bool _hasReviewableCriterionEvidence(ProjectAggregate project) {
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
    required ProjectAggregate project,
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

  bool _isBatchEnd(ProjectAggregate project, String taskId) {
    if (project.currentBatchTaskIds.isEmpty) return true;
    final taskIndex = project.currentBatchTaskIds.indexOf(taskId);
    return taskIndex < 0 || taskIndex == project.currentBatchTaskIds.length - 1;
  }

  String _completionEvidenceFingerprint(ProjectAggregate project) {
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

  ProjectAggregate _completeProjectFromEvidence(
    ProjectAggregate project,
    DateTime now, {
    String summary = '',
  }) {
    return completionService
        .completeFromEvidence(project: project, summary: summary, now: now)
        .project;
  }

  _ProjectTaskValidation _validateProjectTask(
    ProjectTaskNode task,
    ProjectAggregate project,
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
    ProjectAggregate project,
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
      expectedEvidence: _recoveryPolicy.replacementExpectedEvidence(
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
    ProjectAggregate project,
    ProjectTaskNode task,
  ) {
    final plan = project.plan;
    final memoryContext = _memoryService.selectContext(
      project: project,
      task: task,
    );
    final workspaceContext = const ProjectWorkspaceContextService()
        .selectContext(project: project, task: task);
    return TaskPlanningContext(
      projectGoal: plan.refinedGoal,
      projectTaskTitle: task.title,
      projectTaskObjective: task.objective,
      knownFacts: [...memoryContext.lines, ...task.context],
      workspaceOrientation: workspaceContext.orientation,
      workspaceContext: workspaceContext.lines,
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
      requiredGates: _recoveryPolicy.requiredGatesForTask(project, task),
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
      maxSteps: ProjectExecutionStateMachine.taskStepLimit(task.effort),
    );
  }

  // Project execution operations
  /// Executes bounded project runs and owns the task execution protocol.
}
