part of 'project_execution_state_machine.dart';

/// Owns user-directed project commands that mutate a persisted project
/// boundary. The execution state machine supplies the execution context and
/// persistence helpers; this coordinator owns the command decisions and
/// transitions themselves.
class ProjectUserCommandCoordinator {
  ProjectUserCommandCoordinator(this._context);

  final ProjectUseCaseContext _context;

  ProjectMemoryService get _memoryService => _context.memoryService;
  ProjectPlanningHandler get _planningHandler => _context.planningHandler;
  ProjectRecoveryPolicy get _recoveryPolicy => _context.recoveryPolicy;
  ProjectScheduler get _scheduler => _context.scheduler;
  ProjectLifecycleService get _lifecycleService => _context.lifecycleService;

  Future<ProjectAggregate> _persistProject(
    String workspaceRoot,
    ProjectAggregate project, {
    ProjectPersistenceContext? persistenceContext,
    ProjectPersistenceCheckpoint checkpoint =
        ProjectPersistenceCheckpoint.runtime,
  }) => _context.persistProject(
    workspaceRoot,
    project,
    persistenceContext: persistenceContext,
    checkpoint: checkpoint,
  );

  ProjectAggregate _transitionProject({
    required ProjectAggregate snapshot,
    required ProjectStatus to,
    required ProjectLifecycleTrigger trigger,
    required String reason,
    ProjectBlocker? blocker,
    required DateTime now,
  }) => _context.transitionProject(
    snapshot: snapshot,
    to: to,
    trigger: trigger,
    reason: reason,
    blocker: blocker,
    now: now,
  );

  List<ProjectPlanRevisionTrigger> _appendTrigger(
    List<ProjectPlanRevisionTrigger> current,
    ProjectPlanRevisionTrigger trigger,
  ) => _context.appendTrigger(current, trigger);

  List<String> _appendUnique(List<String> current, String value) =>
      _context.appendUnique(current, value);

  ProjectDecisionRecord _decision(
    ProjectDecisionType type,
    String summary,
    String rationale, {
    ProjectTaskNode? task,
  }) => _context.decision(type, summary, rationale, task: task);

  ProjectTaskNode? _activeProjectTask(ProjectAggregate project) =>
      _context.activeProjectTask(project);

  Future<ProjectAggregate> retryRecoveryIncident({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
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
    final failure = ProjectRecoveryFailure(
      gateResult: gateResult,
      command: incident.command,
      workingDirectory: incident.workingDirectory,
      summary: incident.failureSummary,
    );
    final recoveryTask = _recoveryPolicy.recoveryTaskForIncident(
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
        recoveryIncidents: _recoveryPolicy.upsertRecoveryIncident(
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

  Future<ProjectAggregate> answerOpenQuestion({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
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

  Future<ProjectAggregate> addUserContext({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
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

  Future<ProjectAggregate> requestScopeChange({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
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

  Future<ProjectAggregate> compactMemory({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
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

  Future<ProjectAggregate> pauseProject({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
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

  Future<ProjectAggregate> clearTaskBlocker({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
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

  Future<ProjectAggregate> approvePlanRevision({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
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

  Future<ProjectAggregate> rejectPlanRevision({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
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

  Future<ProjectAggregate> cancelProject({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
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
    final updated = _lifecycleService
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

  Future<ProjectAggregate> stopProject({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
  }) => cancelProject(workspace: workspace, snapshot: snapshot);
}
