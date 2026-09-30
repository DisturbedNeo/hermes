// ignore_for_file: unused_element, unused_field
part of 'project_runtime_collaborators.dart';

extension ProjectHelperOperations on ProjectRuntimeContext {
  ProjectRepositoryPort get repository => _repository;

  Future<ProjectCommandResult> execute(ProjectExecutionRequest request) =>
      _commandService.execute(request, port: _executionPort);

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

  List<ProjectPlanRevisionTrigger> _eligibleReplanTriggers(
    Iterable<ProjectPlanRevisionTrigger> triggers,
  ) {
    return {
      for (final trigger in triggers)
        if (ProjectRuntimeContext._runtimeReplanTriggers.contains(trigger))
          trigger,
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
    final workspaceContext = const ProjectWorkspaceContextService()
        .selectContext(project: project, task: task);
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
    if (workspaceContext.orientation.trim().isNotEmpty ||
        workspaceContext.lines.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Workspace orientation:')
        ..writeln(
          workspaceContext.orientation.trim().isEmpty
              ? '- None specified.'
              : workspaceContext.orientation,
        )
        ..writeln()
        ..writeln('Relevant workspace context:')
        ..writeln(_bulletList(workspaceContext.lines));
    }
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
