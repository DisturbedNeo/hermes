import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/services/project_system/project_scheduler.dart';

/// A bounded read model for project planning.
///
/// This deliberately does not serialize [ProjectState] or [Task]. Runtime
/// execution data such as runs, logs, gate results, and full evidence stays
/// behind the task and execution services.
class ProjectViewService {
  const ProjectViewService({
    this.defaultMaxItems = 20,
    this.maxTextLength = 600,
    ProjectScheduler scheduler = const ProjectScheduler(),
  }) : _scheduler = scheduler;

  final int defaultMaxItems;
  final int maxTextLength;
  final ProjectScheduler _scheduler;

  Map<String, dynamic> query(
    ProjectState project, {
    String? taskRef,
    String? criterionRef,
    String? memoryQuery,
    int? maxItems,
  }) {
    final limit = _limit(maxItems ?? defaultMaxItems);
    final schedule = _scheduler.refreshReadiness(project);
    final tasks = _boundedTasks(project, limit);
    final result = <String, dynamic>{
      'project': {
        'id': project.id,
        'title': _text(project.title),
        'status': project.status.wire,
        'base_revision': project.nextRevision - 1,
        'active_task_ref': project.activeTaskId,
      },
      'goal': {
        'original': _text(project.originalGoal),
        'refined': _text(project.refinedGoal),
      },
      'constraints': [
        for (final item in project.constraints.take(limit)) _text(item),
      ],
      'criteria': [
        for (final criterion in project.criteria.take(limit))
          _criterionSummary(criterion),
      ],
      'milestones': [
        for (final milestone
            in (project.milestones.toList()
                  ..sort((a, b) => a.order.compareTo(b.order)))
                .take(limit))
          _milestoneSummary(milestone, limit),
      ],
      'tasks': [for (final task in tasks) _taskSummary(task, schedule, limit)],
      'ready_tasks': [
        for (final task in _scheduler.orderedReadyTasks(project).take(limit))
          _taskSummary(task, schedule, limit),
      ],
      'blocked_tasks': [
        for (final task in project.tasks)
          if (schedule.readinessFor(task.id) != TaskReadiness.ready &&
              _isPlannerRelevant(task))
            {
              'ref': task.id,
              'title': _text(task.title),
              'readiness': _readinessWire(schedule.readinessFor(task.id)),
              'reasons': [
                for (final reason in schedule.reasonsFor(task.id).take(4))
                  _text(reason),
              ],
            },
      ].take(limit).toList(),
      'current_blocker': _blockerSummary(project),
      'pending_questions': [
        for (final question in project.openQuestions.take(limit))
          {'id': question.id, 'question': _text(question.question)},
      ],
      'recent_failures': _recentFailures(project, limit),
      'truncated': {
        'criteria': project.criteria.length > limit,
        'milestones': project.milestones.length > limit,
        'tasks':
            _boundedTasks(project, limit).length <
            _plannerRelevantTasks(project).length,
      },
    };

    final requestedTask = taskRef?.trim();
    if (requestedTask != null && requestedTask.isNotEmpty) {
      final task = project.taskById(requestedTask);
      if (task == null) {
        throw ProjectViewException(
          code: 'unknown_reference',
          path: 'task',
          message: 'Task reference $requestedTask does not exist.',
        );
      }
      result['task_detail'] = _taskDetail(task, schedule, limit);
    }

    final requestedCriterion = criterionRef?.trim();
    if (requestedCriterion != null && requestedCriterion.isNotEmpty) {
      final criterion = project.criteria
          .where((item) => item.id == requestedCriterion)
          .firstOrNull;
      if (criterion == null) {
        throw ProjectViewException(
          code: 'unknown_reference',
          path: 'criterion',
          message: 'Criterion reference $requestedCriterion does not exist.',
        );
      }
      result['criterion_detail'] = _criterionDetail(project, criterion, limit);
    }

    final memorySearch = memoryQuery?.trim();
    if (memorySearch != null && memorySearch.isNotEmpty) {
      final normalised = memorySearch.toLowerCase();
      result['memory_detail'] = [
        for (final entry in project.memory)
          if (entry.active &&
              '${entry.content} ${entry.kind.name} ${entry.sourceId ?? ''}'
                  .toLowerCase()
                  .contains(normalised))
            _memorySummary(entry),
      ].take(limit).toList();
    }

    return result;
  }

  List<Task> _boundedTasks(ProjectState project, int limit) {
    final relevant = _plannerRelevantTasks(project);
    final active = relevant.where((task) => !_isTerminal(task)).toList();
    final recent = relevant.toList()
      ..sort((a, b) {
        final updated = b.updatedAt.compareTo(a.updatedAt);
        return updated != 0 ? updated : a.id.compareTo(b.id);
      });
    final selected = <Task>[];
    for (final task in [...active, ...recent]) {
      if (selected.any((item) => item.id == task.id)) continue;
      selected.add(task);
      if (selected.length == limit) break;
    }
    return selected;
  }

  List<Task> _plannerRelevantTasks(ProjectState project) => [
    for (final task in project.tasks)
      if (!_isTerminal(task) || task.status == TaskStatus.completed) task,
  ];

  Map<String, dynamic> _criterionSummary(ProjectCriterion criterion) => {
    'ref': criterion.id,
    'statement': _text(criterion.statement),
    'required': criterion.required,
    'status': criterion.status.name,
    'verification_mode': criterion.verificationMode.name,
  };

  Map<String, dynamic> _criterionDetail(
    ProjectState project,
    ProjectCriterion criterion,
    int limit,
  ) => {
    ..._criterionSummary(criterion),
    'notes': _text(criterion.notes),
    'linked_task_refs': [
      for (final task in project.tasks)
        if (task.criterionIds.contains(criterion.id)) task.id,
    ].take(limit).toList(),
  };

  Map<String, dynamic> _milestoneSummary(
    ProjectMilestone milestone,
    int limit,
  ) => {
    'ref': milestone.id,
    'title': _text(milestone.title),
    'objective': _text(milestone.objective),
    'status': milestone.status.name,
    'criterion_refs': milestone.criterionIds.take(limit).toList(),
  };

  Map<String, dynamic> _taskSummary(
    Task task,
    ProjectScheduleResult schedule,
    int limit,
  ) => {
    'ref': task.id,
    'title': _text(task.title),
    'objective': _text(task.objective),
    'status': task.status.wire,
    'readiness': _readinessWire(schedule.readinessFor(task.id)),
    'criterion_refs': task.criterionIds.take(limit).toList(),
    'milestone_ref': task.milestoneId,
    'dependency_refs': task.dependsOnTaskIds.take(limit).toList(),
    'priority': task.priority.name,
    'risk': task.risk.name,
    'risk_reduction': task.riskReduction.name,
    'effort': task.effort.name,
    'updated_at': task.updatedAt.toUtc().toIso8601String(),
  };

  Map<String, dynamic> _taskDetail(
    Task task,
    ProjectScheduleResult schedule,
    int limit,
  ) => {
    ..._taskSummary(task, schedule, limit),
    'constraints': [
      for (final item in task.constraints.take(limit)) _text(item),
    ],
    'read_paths': [for (final path in task.readPaths.take(limit)) _text(path)],
    'write_paths': [
      for (final path in task.writePaths.take(limit)) _text(path),
    ],
    'done_criteria': [
      for (final item in task.doneCriteria.take(limit)) _text(item),
    ],
    'out_of_scope': [
      for (final item in task.outOfScope.take(limit)) _text(item),
    ],
    'context': [for (final item in task.context.take(limit)) _text(item)],
    'expected_artifacts': [
      for (final artifact in task.expectedArtifacts.take(limit))
        {
          'path': _text(artifact.path),
          'description': artifact.description == null
              ? null
              : _text(artifact.description!),
          'kind': artifact.kind,
        },
    ],
    'rejection_reason': task.rejectionReason == null
        ? null
        : _text(task.rejectionReason!),
    'failure': task.failure == null
        ? null
        : {
            'gate_ref': task.failure!.gateId,
            'disposition': task.failure!.disposition.name,
            'summary': _text(task.failure!.summary),
            'error_codes': task.failure!.errorCodes.take(limit).toList(),
            'unresolved_error_count': task.failure!.unresolvedErrorCount,
          },
    'checks': [
      for (final gate in task.gates.take(limit))
        {
          'kind': gate.id,
          'required': gate.required,
          'command': gate.params['command'] == null
              ? null
              : _text(gate.params['command'].toString()),
          'working_directory': gate.params['working_directory'] == null
              ? null
              : _text(gate.params['working_directory'].toString()),
          'description': gate.description == null
              ? null
              : _text(gate.description!),
        },
    ],
    'evidence_intents': [
      for (final expectation in task.expectedEvidence.take(limit))
        {
          'kind': expectation.type.name,
          'criterion_refs': expectation.criterionIds.take(limit).toList(),
          'description': _text(expectation.description),
          'required': expectation.required,
          'source_ref': expectation.sourceRef == null
              ? null
              : _text(expectation.sourceRef!),
        },
    ],
  };

  List<Map<String, dynamic>> _recentFailures(ProjectState project, int limit) {
    final failures = <_FailureSummary>[];
    for (final task in project.tasks) {
      final summary = task.failure?.summary.trim();
      final rejection = task.rejectionReason?.trim();
      if ((task.status == TaskStatus.failed ||
              task.status == TaskStatus.rejected) &&
          (summary?.isNotEmpty == true || rejection?.isNotEmpty == true)) {
        failures.add(
          _FailureSummary(
            updatedAt: task.updatedAt,
            value: {
              'source': 'task',
              'task_ref': task.id,
              'summary': _text(
                summary?.isNotEmpty == true ? summary! : rejection!,
              ),
              'status': task.status.wire,
            },
          ),
        );
      }
    }
    for (final incident in project.recoveryIncidents) {
      failures.add(
        _FailureSummary(
          updatedAt: incident.updatedAt,
          value: {
            'source': 'recovery',
            'incident_ref': incident.id,
            'task_refs': incident.sourceTaskIds.take(limit).toList(),
            'summary': _text(incident.failureSummary),
            'status': incident.status.name,
            'attempts': incident.attemptCount,
          },
        ),
      );
    }
    failures.sort((a, b) {
      final updated = b.updatedAt.compareTo(a.updatedAt);
      return updated != 0
          ? updated
          : a.value.toString().compareTo(b.value.toString());
    });
    return [for (final item in failures.take(limit)) item.value];
  }

  Map<String, dynamic>? _blockerSummary(ProjectState project) {
    final blocker = project.blocker;
    if (blocker == null) return null;
    return {
      'type': blocker.type.wire,
      'message': _text(blocker.message),
      'task_ref': blocker.taskId,
    };
  }

  Map<String, dynamic> _memorySummary(ProjectMemoryEntry entry) => {
    'id': entry.id,
    'kind': entry.kind.name,
    'content': _text(entry.content),
    'source_id': entry.sourceId == null ? null : _text(entry.sourceId!),
    'confidence': entry.confidence.name,
  };

  int _limit(int requested) => requested.clamp(1, 100).toInt();

  String _text(String value) {
    final text = value.trim();
    if (text.length <= maxTextLength) return text;
    return '${text.substring(0, maxTextLength - 1).trimRight()}…';
  }

  static bool _isPlannerRelevant(Task task) => !_isTerminal(task);

  static bool _isTerminal(Task task) => switch (task.status) {
    TaskStatus.completed ||
    TaskStatus.failed ||
    TaskStatus.rejected ||
    TaskStatus.split ||
    TaskStatus.cancelled ||
    TaskStatus.deferred ||
    TaskStatus.obsolete => true,
    _ => false,
  };

  static String _readinessWire(TaskReadiness readiness) => switch (readiness) {
    TaskReadiness.waitingDependency => 'waiting_dependency',
    TaskReadiness.waitingInput => 'waiting_input',
    TaskReadiness.notEligible => 'not_eligible',
    TaskReadiness.ready => 'ready',
  };
}

class ProjectViewException implements Exception {
  final String code;
  final String path;
  final String message;

  const ProjectViewException({
    required this.code,
    required this.path,
    required this.message,
  });

  @override
  String toString() => '$code ($path): $message';
}

class _FailureSummary {
  final DateTime updatedAt;
  final Map<String, dynamic> value;

  const _FailureSummary({required this.updatedAt, required this.value});
}
