import 'package:hermes/core/models/project.dart';

enum ProjectDependencyIssueCode {
  missingDependency,
  selfDependency,
  cyclicDependency,
}

class ProjectDependencyIssue {
  final ProjectDependencyIssueCode code;
  final String taskId;
  final String? dependencyId;
  final String message;

  const ProjectDependencyIssue({
    required this.code,
    required this.taskId,
    this.dependencyId,
    required this.message,
  });
}

class ProjectDependencyValidationResult {
  final List<ProjectDependencyIssue> issues;

  const ProjectDependencyValidationResult(this.issues);

  bool get valid => issues.isEmpty;

  List<ProjectDependencyIssue> issuesFor(String taskId) => [
    for (final issue in issues)
      if (issue.taskId == taskId) issue,
  ];
}

class ProjectDependencyGraphValidator {
  const ProjectDependencyGraphValidator();

  ProjectDependencyValidationResult validate(ProjectDocument project) {
    final tasks = _projectTasks(project);
    final taskById = <String, ProjectTask>{};
    for (final task in tasks) {
      taskById.putIfAbsent(task.id, () => task);
    }

    final issues = <ProjectDependencyIssue>[];
    final issueKeys = <String>{};
    void add(ProjectDependencyIssue issue) {
      final key =
          '${issue.code.name}:${issue.taskId}:${issue.dependencyId ?? ''}';
      if (issueKeys.add(key)) issues.add(issue);
    }

    for (final task in tasks) {
      for (final dependencyId in task.dependsOnTaskIds) {
        if (dependencyId == task.id) {
          add(
            ProjectDependencyIssue(
              code: ProjectDependencyIssueCode.selfDependency,
              taskId: task.id,
              dependencyId: dependencyId,
              message: 'Task ${task.id} cannot depend on itself.',
            ),
          );
        } else if (!taskById.containsKey(dependencyId)) {
          add(
            ProjectDependencyIssue(
              code: ProjectDependencyIssueCode.missingDependency,
              taskId: task.id,
              dependencyId: dependencyId,
              message: 'Task ${task.id} depends on missing task $dependencyId.',
            ),
          );
        }
      }
    }

    final visitState = <String, int>{};
    final stack = <String>[];
    final cyclicTaskIds = <String>{};

    void visit(String taskId) {
      visitState[taskId] = 1;
      stack.add(taskId);
      final task = taskById[taskId]!;
      for (final dependencyId in task.dependsOnTaskIds) {
        if (dependencyId == taskId || !taskById.containsKey(dependencyId)) {
          continue;
        }
        final state = visitState[dependencyId] ?? 0;
        if (state == 0) {
          visit(dependencyId);
        } else if (state == 1) {
          final cycleStart = stack.indexOf(dependencyId);
          cyclicTaskIds.addAll(stack.sublist(cycleStart));
        }
      }
      stack.removeLast();
      visitState[taskId] = 2;
    }

    for (final taskId in taskById.keys.toList()..sort()) {
      if ((visitState[taskId] ?? 0) == 0) visit(taskId);
    }
    for (final taskId in cyclicTaskIds.toList()..sort()) {
      add(
        ProjectDependencyIssue(
          code: ProjectDependencyIssueCode.cyclicDependency,
          taskId: taskId,
          message: 'Task $taskId participates in a dependency cycle.',
        ),
      );
    }

    issues.sort((a, b) {
      final taskOrder = a.taskId.compareTo(b.taskId);
      if (taskOrder != 0) return taskOrder;
      final codeOrder = a.code.index.compareTo(b.code.index);
      if (codeOrder != 0) return codeOrder;
      return (a.dependencyId ?? '').compareTo(b.dependencyId ?? '');
    });
    return ProjectDependencyValidationResult(List.unmodifiable(issues));
  }
}

class ProjectScheduleResult {
  final ProjectDocument project;
  final ProjectTask? selectedTask;
  final ProjectDependencyValidationResult dependencyValidation;

  const ProjectScheduleResult({
    required this.project,
    required this.selectedTask,
    required this.dependencyValidation,
  });
}

/// Computes authoritative readiness and picks one task using stable ordering.
class ProjectScheduler {
  const ProjectScheduler({
    ProjectDependencyGraphValidator dependencyValidator =
        const ProjectDependencyGraphValidator(),
  }) : _dependencyValidator = dependencyValidator;

  final ProjectDependencyGraphValidator _dependencyValidator;

  ProjectScheduleResult refreshReadiness(ProjectDocument project) {
    final validation = _dependencyValidator.validate(project);
    final refreshedBacklog = [
      for (final task in project.backlog)
        _withComputedReadiness(project, task, validation),
    ];
    final currentTask = project.currentTask == null
        ? null
        : _withComputedReadiness(project, project.currentTask!, validation);
    return ProjectScheduleResult(
      project: project.copyWith(
        backlog: refreshedBacklog,
        currentTask: currentTask,
      ),
      selectedTask: null,
      dependencyValidation: validation,
    );
  }

  ProjectScheduleResult schedule(ProjectDocument project) {
    final refreshed = refreshReadiness(project);
    var scheduledProject = refreshed.project;
    final recoverySelection = _selectRecoveryTask(scheduledProject);
    final selection = recoverySelection ?? _selectNormalTask(scheduledProject);
    if (selection == null) return refreshed;

    final selected = selection.task.copyWith(
      selectionRationale: selection.rationale,
    );
    scheduledProject = scheduledProject.copyWith(
      backlog: [
        for (final task in scheduledProject.backlog)
          if (task.id == selected.id) selected else task,
      ],
    );
    return ProjectScheduleResult(
      project: scheduledProject,
      selectedTask: selected,
      dependencyValidation: refreshed.dependencyValidation,
    );
  }

  /// Returns every currently ready task in the same stable order used for
  /// selection. Recovery work remains first when an incident is active.
  List<ProjectTask> orderedReadyTasks(ProjectDocument project) {
    final refreshed = refreshReadiness(project).project;
    final ready = _orderedNormalTasks(refreshed);
    final recovery = _selectRecoveryTask(refreshed)?.task;
    if (recovery == null) return List.unmodifiable(ready);
    return List.unmodifiable([
      recovery,
      for (final task in ready)
        if (task.id != recovery.id) task,
    ]);
  }

  ProjectTask _withComputedReadiness(
    ProjectDocument project,
    ProjectTask task,
    ProjectDependencyValidationResult validation,
  ) {
    final ineligibleReason = _ineligibleReason(task.status);
    if (ineligibleReason != null) {
      return task.copyWith(
        readiness: ProjectTaskReadiness.notEligible,
        readinessReasons: [ineligibleReason],
      );
    }

    final dependencyReasons = <String>[
      for (final issue in validation.issuesFor(task.id)) issue.message,
    ];
    for (final dependencyId in task.dependsOnTaskIds) {
      final dependency = project.taskById(dependencyId);
      if (dependency != null &&
          dependency.status != ProjectTaskStatus.completed) {
        dependencyReasons.add(
          'Waiting for dependency $dependencyId '
          '(status: ${dependency.status.name}).',
        );
      }
    }
    if (dependencyReasons.isNotEmpty) {
      return task.copyWith(
        readiness: ProjectTaskReadiness.waitingDependency,
        readinessReasons: _unique(dependencyReasons),
      );
    }

    final inputReasons = _inputReasons(project, task);
    if (inputReasons.isNotEmpty) {
      return task.copyWith(
        readiness: ProjectTaskReadiness.waitingInput,
        readinessReasons: inputReasons,
      );
    }

    return task.copyWith(
      readiness: ProjectTaskReadiness.ready,
      readinessReasons: const [
        'All dependencies are complete and no blocking input is pending.',
      ],
    );
  }

  List<String> _inputReasons(ProjectDocument project, ProjectTask task) {
    final reasons = <String>[];
    final approval = project.pendingPlanApproval;
    if (approval != null) {
      reasons.add(
        'Waiting for approval of plan revision ${approval.revision}.',
      );
    }
    for (final question in project.openQuestions) {
      reasons.add(
        'Waiting for project question ${question.id}: ${question.question}',
      );
    }

    final blocker = project.blocker;
    if (blocker != null &&
        _isInputBlocker(blocker.type) &&
        (blocker.taskId == null ||
            blocker.taskId == task.id ||
            blocker.taskId == task.taskDocumentId)) {
      reasons.add(
        'Waiting for ${_blockerLabel(blocker.type)}: ${blocker.message}',
      );
    }

    final activeIncidents = [
      for (final incident in project.recoveryIncidents)
        if (incident.status == ProjectRecoveryIncidentStatus.active) incident,
    ];
    final belongsToActiveIncident = activeIncidents.any(
      (incident) =>
          incident.id == task.recoveryIncidentId ||
          incident.recoveryTaskIds.contains(task.id),
    );
    if (activeIncidents.isNotEmpty && !belongsToActiveIncident) {
      final ids = activeIncidents.map((incident) => incident.id).toList()
        ..sort();
      reasons.add(
        'Active recovery incident ${ids.join(', ')} takes precedence.',
      );
    }
    return _unique(reasons);
  }

  _TaskSelection? _selectRecoveryTask(ProjectDocument project) {
    final incidents =
        project.recoveryIncidents
            .where(
              (incident) =>
                  incident.status == ProjectRecoveryIncidentStatus.active,
            )
            .toList()
          ..sort((a, b) {
            final created = a.createdAt.compareTo(b.createdAt);
            return created != 0 ? created : a.id.compareTo(b.id);
          });
    for (final incident in incidents) {
      for (final taskId in incident.recoveryTaskIds.reversed) {
        final task = _readyTaskById(project.backlog, taskId);
        if (task != null) {
          return _TaskSelection(
            task,
            'Selected recovery task ${task.id} for active incident '
            '${incident.id} before normal project work.',
          );
        }
      }
      final fallback =
          project.backlog
              .where(
                (task) =>
                    task.recoveryIncidentId == incident.id && _isReady(task),
              )
              .toList()
            ..sort(_compareStableAgeAndId);
      if (fallback.isNotEmpty) {
        final task = fallback.first;
        return _TaskSelection(
          task,
          'Selected recovery task ${task.id} for active incident '
          '${incident.id} before normal project work.',
        );
      }
    }
    return null;
  }

  _TaskSelection? _selectNormalTask(ProjectDocument project) {
    final ready = _orderedNormalTasks(project);
    if (ready.isEmpty) return null;

    final selected = ready.first;
    final downstream = _downstreamCount(project.backlog, selected.id);
    final milestone = selected.milestoneId == null
        ? 'no milestone'
        : _milestoneDescription(project, selected.milestoneId!);
    return _TaskSelection(
      selected,
      'Selected by deterministic scheduler: ${selected.priority.name} '
      'priority; unblocks $downstream downstream task${downstream == 1 ? '' : 's'}; '
      '${selected.riskReduction.name} risk reduction; $milestone; '
      'created ${selected.createdAt.toUtc().toIso8601String()}; '
      'stable task ID ${selected.id}.',
    );
  }

  List<ProjectTask> _orderedNormalTasks(ProjectDocument project) {
    final ready = project.backlog.where(_isReady).toList();
    if (ready.isEmpty) return ready;

    final downstreamCounts = <String, int>{
      for (final task in project.backlog)
        task.id: _downstreamCount(project.backlog, task.id),
    };
    ready.sort((a, b) {
      var result = a.priority.index.compareTo(b.priority.index);
      if (result != 0) return result;
      result = (downstreamCounts[b.id] ?? 0).compareTo(
        downstreamCounts[a.id] ?? 0,
      );
      if (result != 0) return result;
      result = a.riskReduction.index.compareTo(b.riskReduction.index);
      if (result != 0) return result;
      result = _milestoneRank(project, a).compareTo(_milestoneRank(project, b));
      if (result != 0) return result;
      return _compareStableAgeAndId(a, b);
    });
    return ready;
  }

  static int _downstreamCount(List<ProjectTask> tasks, String taskId) {
    final dependents = <String, Set<String>>{};
    for (final task in tasks) {
      for (final dependencyId in task.dependsOnTaskIds) {
        dependents.putIfAbsent(dependencyId, () => <String>{}).add(task.id);
      }
    }
    final seen = <String>{};
    final pending = <String>[taskId];
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      for (final dependent in dependents[current] ?? const <String>{}) {
        if (seen.add(dependent)) pending.add(dependent);
      }
    }
    return seen.length;
  }

  static int _milestoneRank(ProjectDocument project, ProjectTask task) {
    if (task.milestoneId == null) return 1000000;
    final milestone = project.milestones
        .where((item) => item.id == task.milestoneId)
        .firstOrNull;
    if (milestone == null) return 1000000;
    return switch (milestone.status) {
      ProjectMilestoneStatus.active => 0,
      ProjectMilestoneStatus.planned => 1 + milestone.order,
      ProjectMilestoneStatus.blocked => 500000 + milestone.order,
      ProjectMilestoneStatus.completed => 600000 + milestone.order,
      ProjectMilestoneStatus.cancelled => 700000 + milestone.order,
    };
  }

  static String _milestoneDescription(
    ProjectDocument project,
    String milestoneId,
  ) {
    final milestone = project.milestones
        .where((item) => item.id == milestoneId)
        .firstOrNull;
    if (milestone == null) return 'unknown milestone $milestoneId';
    return '${milestone.status.name} milestone ${milestone.id} '
        '(order ${milestone.order})';
  }

  static ProjectTask? _readyTaskById(List<ProjectTask> tasks, String id) {
    for (final task in tasks) {
      if (task.id == id && _isReady(task)) return task;
    }
    return null;
  }

  static bool _isReady(ProjectTask task) =>
      (task.status == ProjectTaskStatus.queued ||
          task.status == ProjectTaskStatus.proposed ||
          task.status == ProjectTaskStatus.approved) &&
      task.readiness == ProjectTaskReadiness.ready;

  static String? _ineligibleReason(ProjectTaskStatus status) {
    return switch (status) {
      ProjectTaskStatus.queued ||
      ProjectTaskStatus.proposed ||
      ProjectTaskStatus.approved => null,
      ProjectTaskStatus.running => 'Task is already running.',
      ProjectTaskStatus.completed => 'Task is already complete.',
      ProjectTaskStatus.failed => 'Task is terminal with failed status.',
      ProjectTaskStatus.rejected => 'Task was rejected.',
      ProjectTaskStatus.split => 'Task was replaced by split tasks.',
      ProjectTaskStatus.deferred => 'Task is deferred.',
      ProjectTaskStatus.obsolete => 'Task is obsolete.',
      ProjectTaskStatus.cancelled => 'Task is terminal with cancelled status.',
    };
  }

  static bool _isInputBlocker(ProjectBlockerType type) => switch (type) {
    ProjectBlockerType.question ||
    ProjectBlockerType.taskApproval ||
    ProjectBlockerType.taskBlocked ||
    ProjectBlockerType.planApproval => true,
    _ => false,
  };

  static String _blockerLabel(ProjectBlockerType type) => switch (type) {
    ProjectBlockerType.question => 'question',
    ProjectBlockerType.taskApproval => 'task approval',
    ProjectBlockerType.taskBlocked => 'blocked task input',
    ProjectBlockerType.planApproval => 'plan approval',
    _ => 'external input',
  };

  static List<String> _unique(List<String> values) {
    final seen = <String>{};
    return [
      for (final value in values)
        if (seen.add(value)) value,
    ];
  }

  static int _compareStableAgeAndId(ProjectTask a, ProjectTask b) {
    final created = a.createdAt.compareTo(b.createdAt);
    return created != 0 ? created : a.id.compareTo(b.id);
  }
}

class _TaskSelection {
  final ProjectTask task;
  final String rationale;

  const _TaskSelection(this.task, this.rationale);
}

List<ProjectTask> _projectTasks(ProjectDocument project) => [
  ...project.backlog,
  if (project.currentTask != null) project.currentTask!,
  ...project.completedTasks,
  ...project.failedTasks,
];
