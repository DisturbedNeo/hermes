part of 'project_workflow_service.dart';

/// Owns user-facing project commands and interrupted-run recovery.
mixin ProjectCommandPhase on ProjectWorkflowRuntime {
  @override
  Future<ProjectCommandResult> _recoverProjectCore({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
    ProjectTaskSnapshotSink? onTaskUpdated,
  }) async {
    final loaded = await _aggregateRepository.loadProject(
      workspace.rootPath,
      snapshot.id,
      chatSessionId: snapshot.chatSessionId,
      includeHistory: false,
    );
    final persistenceDiagnostics = loaded.diagnostics;
    if (persistenceDiagnostics.isReadOnly) {
      return ProjectCommandResult.fromSnapshot(
        project: snapshot,
        persistenceDiagnostics: persistenceDiagnostics,
      );
    }
    snapshot = loaded.project == null
        ? await _hydrateProjectTasks(workspace, snapshot)
        : snapshot.copyWith(
            tasks: loaded.canonicalTasks.map(ProjectTaskNode.fromTask).toList(),
          );
    final persistenceContext = ProjectPersistenceContext(
      loaded.canonicalTasks,
      health: persistenceDiagnostics,
    );
    if (snapshot.isTerminal) {
      return ProjectCommandResult.fromSnapshot(
        project: snapshot,
        activeTask: await _loadActiveTask(workspace, snapshot),
        persistenceDiagnostics: persistenceDiagnostics,
      );
    }

    final activeTask = await _loadActiveTask(workspace, snapshot);
    if (!_wasInterrupted(snapshot.status)) {
      return ProjectCommandResult.fromSnapshot(
        project: snapshot,
        activeTask: activeTask,
        persistenceDiagnostics: persistenceDiagnostics,
      );
    }

    final now = DateTime.now();
    if (snapshot.activeTaskId == null) {
      final blocker = snapshot.openQuestions.isEmpty
          ? null
          : ProjectBlocker(
              type: ProjectBlockerType.question,
              message: snapshot.openQuestions.first.question,
              createdAt: now,
            );
      final recovered = _transitionProject(
        snapshot: snapshot.copyWith(blocker: blocker, updatedAt: now),
        to: blocker == null
            ? ProjectStatus.active
            : ProjectStatus.waitingForUser,
        trigger: ProjectLifecycleTrigger.recovery,
        reason: blocker?.message ?? 'Recovered project execution state.',
        blocker: blocker,
        now: now,
      );
      final persisted = await _persistProject(
        workspace.rootPath,
        recovered,
        persistenceContext: persistenceContext,
      );
      return ProjectCommandResult.fromSnapshot(
        project: persisted,
        persistenceDiagnostics: persistenceDiagnostics,
      );
    }

    if (activeTask == null) {
      final blocked = _blockProject(
        snapshot.copyWith(activeTaskId: null, updatedAt: now),
        ProjectBlockerType.error,
        'Recovered an interrupted project, but its active task was missing.',
        now,
      );
      final persisted = await _persistProject(
        workspace.rootPath,
        blocked,
        persistenceContext: persistenceContext,
      );
      onTaskUpdated?.call(null);
      return ProjectCommandResult.fromSnapshot(
        project: persisted,
        persistenceDiagnostics: persistenceDiagnostics,
      );
    }

    final recoveredTask = await _taskService.recoverTask(
      workspace: workspace,
      snapshot: activeTask,
      persist: false,
    );
    persistenceContext.stageTask(recoveredTask);
    onTaskUpdated?.call(recoveredTask);
    var recovered = recoveryHandler.reconcile(
      project: snapshot,
      recoveredTask: recoveredTask,
      now: now,
    );
    recovered = await _persistProject(
      workspace.rootPath,
      recovered,
      persistenceContext: persistenceContext,
    );
    return ProjectCommandResult.fromSnapshot(
      project: recovered,
      activeTask: recoveredTask,
      persistenceDiagnostics: persistenceDiagnostics,
    );
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
    var updated = _transitionProject(
      snapshot: snapshot.copyWith(
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
      ),
      to: ProjectStatus.active,
      trigger: ProjectLifecycleTrigger.recovery,
      reason: 'Recovery retry approved by the user.',
      now: now,
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
    var updated = _transitionProject(
      snapshot: snapshot.copyWith(
        openQuestions: remainingQuestions,
        blocker: null,
        pendingReplanTriggers: _appendTrigger(
          snapshot.pendingReplanTriggers,
          ProjectPlanRevisionTrigger.scopeChanged,
        ),
        pendingReplanReason:
            'The project scope changed and the backlog must be reconciled.',
        updatedAt: DateTime.now(),
      ),
      to: ProjectStatus.active,
      trigger: ProjectLifecycleTrigger.answerQuestion,
      reason: 'The user answered an open project question.',
      now: DateTime.now(),
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
    var updated = snapshot.isTerminal
        ? snapshot.copyWith(
            blocker: snapshot.blocker?.type == ProjectBlockerType.question
                ? null
                : snapshot.blocker,
            updatedAt: DateTime.now(),
          )
        : _transitionProject(
            snapshot: snapshot.copyWith(
              blocker: snapshot.blocker?.type == ProjectBlockerType.question
                  ? null
                  : snapshot.blocker,
              updatedAt: DateTime.now(),
            ),
            to: ProjectStatus.active,
            trigger: ProjectLifecycleTrigger.userContext,
            reason: 'The user added project context.',
            now: DateTime.now(),
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
    var updated = _transitionProject(
      snapshot: snapshot.copyWith(
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
      ),
      to: ProjectStatus.active,
      trigger: ProjectLifecycleTrigger.userContext,
      reason: 'The user changed project scope.',
      now: now,
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
    final updated = _transitionProject(
      snapshot: snapshot,
      to: ProjectStatus.paused,
      trigger: ProjectLifecycleTrigger.pause,
      reason: 'Project paused by the user.',
      now: DateTime.now(),
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
    final updated = _transitionProject(
      snapshot: snapshot.copyWith(blocker: null, updatedAt: DateTime.now()),
      to: ProjectStatus.active,
      trigger: ProjectLifecycleTrigger.answerQuestion,
      reason: 'The task blocker was cleared by the user.',
      now: DateTime.now(),
    );
    return _persistProject(workspace.rootPath, updated);
  }

  Future<ProjectDocument> approvePlanRevision({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
  }) async {
    final result = _planningHandler.approvePending(
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
    final boundary = schedule.project.copyWith(
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
    var updated = _transitionProject(
      snapshot: boundary,
      to: hasReadyWork ? ProjectStatus.active : ProjectStatus.paused,
      trigger: ProjectLifecycleTrigger.approval,
      reason: hasReadyWork
          ? 'Rejected plan approval; existing ready work remains.'
          : boundary.blocker?.message ?? 'Plan approval was rejected.',
      blocker: boundary.blocker,
      now: now,
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
    final prepared = snapshot.copyWith(
      activeTaskId: null,
      tasks: [
        for (final task in snapshot.tasks)
          task.id == activeTask?.id
              ? task.copyWith(status: TaskStatus.cancelled, updatedAt: now)
              : task,
      ],
      openQuestions: const [],
      blocker: null,
      updatedAt: now,
    );
    final updated = lifecycleService
        .transition(
          snapshot: prepared,
          to: ProjectStatus.cancelled,
          trigger: ProjectLifecycleTrigger.cancel,
          reason: 'Project cancelled by the user.',
          now: now,
        )
        .project;
    return _persistProject(workspace.rootPath, updated);
  }

  Future<ProjectDocument> stopProject({
    required WorkspaceAttachment workspace,
    required ProjectDocument snapshot,
  }) {
    return cancelProject(workspace: workspace, snapshot: snapshot);
  }
}
