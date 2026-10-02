part of 'project_execution_state_machine.dart';

extension ProjectExecutionLifecycle on ProjectExecutionUseCase {
  bool _blocksInitialPlanningForContextIssue(
    WorkspaceRequiredContextIssue issue,
  ) => issue.code == 'required_context_unreadable';
  // Project helper operations

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

  ProjectAggregate _syncCurrentTaskFromTask(
    ProjectAggregate project,
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

  ProjectAggregate _waitingForUser(ProjectAggregate project, DateTime now) {
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

  ProjectFilteredQuestions _filterProjectQuestions(
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
    return ProjectFilteredQuestions(
      blocking: blocking,
      assumptions: assumptions,
    );
  }

  ProjectAggregate _blockProject(
    ProjectAggregate project,
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

  List<String> _remainingCriteria(ProjectAggregate project) {
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

  ProjectAggregate _recordAssumptions(
    ProjectAggregate project,
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

  ProjectAggregate _recordTaskMemory({
    required ProjectAggregate project,
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

  ProjectAggregate _projectForModel(
    ProjectAggregate project, {
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
    ProjectAggregate project, {
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

  ProjectAggregate _recordTransitionReplanTriggers({
    required ProjectAggregate project,
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
        if (ProjectExecutionStateMachine._runtimeReplanTriggers.contains(
          trigger,
        ))
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

  String _taskPrompt(ProjectAggregate project, ProjectTaskNode task) {
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
    ProjectAggregate project,
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

  // Project planning and recovery operations
  /// Owns the runtime graph used by the project use cases.
  List<ProjectPlanValidationIssue> _validateInitialPlan({
    required ProjectInitialPlanResult initialPlan,
    required WorkspaceDiscoveryProfile workspaceProfile,
  }) {
    final plan = initialPlan.patch.plan;
    final issues = <ProjectPlanValidationIssue>[];
    void add(String code, String message, {String? path}) {
      issues.add(
        ProjectPlanValidationIssue(
          code: code,
          message: message,
          path: path ?? '',
        ),
      );
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

  String _initialPlanningBlockerMessage(
    List<ProjectPlanValidationIssue> issues,
  ) {
    final details = issues
        .map((issue) {
          final path = issue.path;
          return '${issue.code}${path.isEmpty ? '' : ' ($path)'}: ${issue.message}';
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
  Future<ProjectAggregate> _persistProject(
    String workspaceRoot,
    ProjectAggregate project, {
    ProjectPersistenceContext? persistenceContext,
    ProjectPersistenceCheckpoint checkpoint =
        ProjectPersistenceCheckpoint.runtime,
  }) => _persistenceCoordinator.persistProject(
    workspaceRoot,
    project,
    persistenceContext: persistenceContext,
    checkpoint: checkpoint,
  );

  /// Owns user-facing project commands and interrupted-run recovery.
  Future<ProjectCommandResult> _recoverProjectCore({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
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

    final recoveredTask = await _taskRecovery.recoverTask(
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
}
