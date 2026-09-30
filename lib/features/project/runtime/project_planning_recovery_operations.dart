// ignore_for_file: override_on_non_overriding_member, unused_element
part of 'project_runtime_collaborators.dart';

int taskStepLimit(TaskEffort effort) => switch (effort) {
  TaskEffort.small => 1,
  TaskEffort.medium => 4,
  TaskEffort.large => 6,
};

/// Owns the runtime graph used by the project use cases.

extension ProjectPlanningRecoveryOperations on ProjectRuntimeContext {
  List<Map<String, String>> _validateInitialPlan({
    required ProjectInitialPlanResult initialPlan,
    required WorkspaceDiscoveryProfile workspaceProfile,
  }) {
    final plan = initialPlan.patch.plan;
    final issues = <Map<String, String>>[];
    void add(String code, String message, {String? path}) {
      final issue = <String, String>{'code': code, 'message': message};
      if (path != null) issue['path'] = path;
      issues.add(issue);
    }

    final criteria = plan.criteria;
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

    final taskById = <String, ProjectTaskNode>{};
    for (final task in plan.tasks) {
      if (task.id.trim().isEmpty || taskById.containsKey(task.id)) {
        add(
          'invalid_task_id',
          'Every initial task needs a unique, non-empty stable ID.',
        );
      } else {
        taskById[task.id] = task;
      }
    }
    if (taskById.isEmpty && plan.openQuestions.isEmpty) {
      add(
        'missing_executable_tasks',
        'The initial plan must contain bounded executable work or a blocking question.',
      );
    }

    final milestoneIds = <String>{};
    for (final milestone in plan.milestones) {
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
      final hasConclusiveExpectation = plan.tasks.any(
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
    for (final entry in plan.memoryAdditions) {
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

  @override
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
    required List<ProjectMilestone> milestones,
    required String refinedGoal,
    required List<ProjectCriterion>? criteria,
    required DateTime now,
  }) {
    final criterionIds = criteria?.map((item) => item.id).toList() ?? const [];
    final criterionStatements =
        criteria?.map((item) => item.statement).toList() ?? const [];
    final proposed = milestones.isEmpty
        ? [
            ProjectMilestone(
              id: 'milestone_001',
              title: 'Deliver the project outcome',
              objective: refinedGoal,
              criterionIds: criterionIds,
              status: ProjectMilestoneStatus.active,
              exitConditions: criterionStatements,
              order: 1,
              createdAt: now,
              updatedAt: now,
            ),
          ]
        : milestones;
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

  List<ProjectMemoryEntry> _initialMemory({
    required List<ProjectMemoryEntry> memory,
    required List<String> policyAssumptions,
    required DateTime now,
  }) {
    final entries = <ProjectMemoryEntry>[];
    final usedIds = <String>{};
    final contents = <String>{};
    for (var index = 0; index < memory.length; index++) {
      final proposed = memory[index];
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

  ProjectInitialPlanResult _fallbackInitialPlan(String originalGoal) {
    final now = DateTime.now();
    return ProjectInitialPlanResult(
      patch: ProjectPlanPatch.initial(
        ProjectDesiredPlan(
          revision: 1,
          triggers: const [ProjectPlanRevisionTrigger.initialization],
          summary: 'Initial project roadmap.',
          rationale: 'Created from the safe project fallback.',
          criteria: [
            ProjectCriterion(
              id: 'criterion_001',
              statement: 'Complete the stated project goal.',
              createdAt: now,
              updatedAt: now,
            ),
          ],
          createdAt: now,
        ),
        title: _titleFromPrompt(originalGoal),
        refinedGoal: originalGoal,
        constraints: const ['Stay within the attached workspace.'],
      ),
    );
  }

  /// Coordinates readiness refresh with the aggregate write boundary.
  @override
  Future<ProjectDocument> _persistProject(
    String workspaceRoot,
    ProjectDocument project, {
    ProjectPersistenceContext? persistenceContext,
    ProjectPersistenceCheckpoint checkpoint =
        ProjectPersistenceCheckpoint.runtime,
  }) async {
    return _persistenceHandler.persist(
      workspaceRoot,
      project,
      persistenceContext: persistenceContext,
      checkpoint: checkpoint,
    );
  }

  /// Owns user-facing project commands and interrupted-run recovery.
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

    final recoveredTask = await _taskController.recoverTask(
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
