import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/services/project_system/project_scheduler.dart';

void main() {
  group('ProjectDependencyGraphValidator', () {
    const validator = ProjectDependencyGraphValidator();

    test('reports missing, self, and cyclic dependencies', () {
      final project = _project(
        backlog: [
          _task('self', dependencies: const ['self']),
          _task('missing', dependencies: const ['absent']),
          _task('cycle_a', dependencies: const ['cycle_b']),
          _task('cycle_b', dependencies: const ['cycle_a']),
        ],
      );

      final result = validator.validate(project);

      expect(result.valid, isFalse);
      expect(
        result.issues.map((issue) => issue.code),
        containsAll([
          ProjectDependencyIssueCode.selfDependency,
          ProjectDependencyIssueCode.missingDependency,
          ProjectDependencyIssueCode.cyclicDependency,
        ]),
      );
      expect(
        result.issuesFor('cycle_a').single.message,
        'Task cycle_a participates in a dependency cycle.',
      );
    });
  });

  group('ProjectScheduler readiness', () {
    const scheduler = ProjectScheduler();

    test('derives readiness from dependency completion, not stored values', () {
      final completed = _task('done', status: ProjectTaskStatus.completed);
      final project = _project(
        completedTasks: [completed],
        backlog: [
          _task(
            'ready_after_done',
            dependencies: const ['done'],
            readiness: ProjectTaskReadiness.waitingDependency,
          ),
          _task(
            'waiting',
            dependencies: const ['unfinished'],
            readiness: ProjectTaskReadiness.ready,
          ),
          _task('unfinished'),
        ],
      );

      final result = scheduler.refreshReadiness(project).project;

      expect(
        result.taskById('ready_after_done')!.readiness,
        ProjectTaskReadiness.ready,
      );
      expect(
        result.taskById('waiting')!.readiness,
        ProjectTaskReadiness.waitingDependency,
      );
      expect(result.taskById('waiting')!.readinessReasons, [
        'Waiting for dependency unfinished (status: queued).',
      ]);
    });

    test('malformed dependency graphs remain non-executable', () {
      final result = scheduler.schedule(
        _project(
          backlog: [
            _task('cycle_a', dependencies: const ['cycle_b']),
            _task('cycle_b', dependencies: const ['cycle_a']),
            _task('missing', dependencies: const ['absent']),
          ],
        ),
      );

      expect(result.selectedTask, isNull);
      expect(result.project.backlog.map((task) => task.readiness).toSet(), {
        ProjectTaskReadiness.waitingDependency,
      });
      expect(result.dependencyValidation.valid, isFalse);
    });

    test('records exact question, approval, and incident wait reasons', () {
      final now = DateTime.utc(2026, 1, 1);
      final result = scheduler.refreshReadiness(
        _project(
          backlog: [_task('normal')],
          openQuestions: [
            PendingProjectQuestion(
              id: 'question_1',
              question: 'Which API should be used?',
              createdAt: now,
            ),
          ],
          pendingPlanApproval: PendingProjectPlanApproval(
            revision: 3,
            reason: 'High-risk change.',
            summary: 'Change the API.',
            createdAt: now,
          ),
          recoveryIncidents: [_incident('incident_1')],
        ),
      );
      final task = result.project.backlog.single;

      expect(task.readiness, ProjectTaskReadiness.waitingInput);
      expect(task.readinessReasons, [
        'Waiting for approval of plan revision 3.',
        'Waiting for project question question_1: Which API should be used?',
        'Active recovery incident incident_1 takes precedence.',
      ]);
    });

    test(
      'marks deferred, obsolete, running, and terminal tasks ineligible',
      () {
        final result = scheduler.refreshReadiness(
          _project(
            backlog: [
              _task('deferred', status: ProjectTaskStatus.deferred),
              _task('obsolete', status: ProjectTaskStatus.obsolete),
              _task('running', status: ProjectTaskStatus.running),
              _task('failed', status: ProjectTaskStatus.failed),
            ],
          ),
        );

        expect(result.project.backlog.map((task) => task.readiness).toSet(), {
          ProjectTaskReadiness.notEligible,
        });
        expect(result.project.taskById('deferred')!.readinessReasons, [
          'Task is deferred.',
        ]);
      },
    );
  });

  group('ProjectScheduler selection', () {
    const scheduler = ProjectScheduler();

    test('uses every deterministic ordering key in the specified order', () {
      final now = DateTime.utc(2026, 1, 10);
      final milestones = [
        _milestone('active', ProjectMilestoneStatus.active, 1),
        _milestone('later', ProjectMilestoneStatus.planned, 2),
      ];

      ProjectTask selected(List<ProjectTask> tasks) => scheduler
          .schedule(_project(backlog: tasks, milestones: milestones))
          .selectedTask!;

      expect(
        selected([
          _task('low', priority: ProjectTaskPriority.low),
          _task('critical', priority: ProjectTaskPriority.critical),
        ]).id,
        'critical',
      );
      expect(
        selected([
          _task('leaf'),
          _task('unblocker'),
          _task('dependent', dependencies: const ['unblocker']),
        ]).id,
        'unblocker',
      );
      expect(
        selected([
          _task('none'),
          _task('risk', riskReduction: ProjectRiskReduction.high),
        ]).id,
        'risk',
      );
      expect(
        selected([
          _task('later', milestoneId: 'later'),
          _task('active', milestoneId: 'active'),
        ]).id,
        'active',
      );
      expect(
        selected([
          _task('newer', createdAt: now),
          _task('older', createdAt: now.subtract(const Duration(days: 1))),
        ]).id,
        'older',
      );
      expect(selected([_task('b'), _task('a')]).id, 'a');
    });

    test(
      'is stable and persists an auditable rationale on the chosen task',
      () {
        final project = _project(backlog: [_task('b'), _task('a')]);

        final first = scheduler.schedule(project);
        final second = scheduler.schedule(project);

        expect(first.selectedTask!.id, second.selectedTask!.id);
        expect(
          first.selectedTask!.selectionRationale,
          contains('normal priority'),
        );
        expect(
          first.selectedTask!.selectionRationale,
          contains('stable task ID a'),
        );
        expect(
          first.project.taskById('a')!.selectionRationale,
          first.selectedTask!.selectionRationale,
        );
      },
    );

    test('exposes all ready tasks in scheduler order', () {
      final project = _project(
        backlog: [
          _task('low', priority: ProjectTaskPriority.low),
          _task('critical', priority: ProjectTaskPriority.critical),
          _task('high', priority: ProjectTaskPriority.high),
        ],
      );

      final ordered = scheduler.orderedReadyTasks(project);

      expect(ordered.map((task) => task.id), ['critical', 'high', 'low']);
    });

    test('selects ready recovery work before higher-priority normal work', () {
      final incident = _incident(
        'incident_1',
        recoveryTaskIds: const ['repair'],
      );
      final result = scheduler.schedule(
        _project(
          backlog: [
            _task('normal', priority: ProjectTaskPriority.critical),
            _task(
              'repair',
              recoveryIncidentId: incident.id,
              priority: ProjectTaskPriority.low,
            ),
          ],
          recoveryIncidents: [incident],
        ),
      );

      expect(result.selectedTask!.id, 'repair');
      expect(
        result.selectedTask!.selectionRationale,
        contains('before normal'),
      );
      expect(
        result.project.taskById('normal')!.readiness,
        ProjectTaskReadiness.waitingInput,
      );
    });
  });
}

ProjectDocument _project({
  List<ProjectTask> backlog = const [],
  List<ProjectTask> completedTasks = const [],
  List<ProjectMilestone> milestones = const [],
  List<ProjectRecoveryIncident> recoveryIncidents = const [],
  List<PendingProjectQuestion> openQuestions = const [],
  PendingProjectPlanApproval? pendingPlanApproval,
}) {
  final now = DateTime.utc(2026, 1, 1);
  return ProjectDocument(
    id: 'project',
    title: 'Project',
    originalGoal: 'Deliver the project.',
    refinedGoal: 'Deliver the project.',
    constraints: const [],
    backlog: backlog,
    completedTasks: completedTasks,
    milestones: milestones,
    recoveryIncidents: recoveryIncidents,
    openQuestions: openQuestions,
    pendingPlanApproval: pendingPlanApproval,
    status: ProjectStatus.active,
    activeTaskId: null,
    createdAt: now,
    updatedAt: now,
  );
}

ProjectTask _task(
  String id, {
  List<String> dependencies = const [],
  ProjectTaskPriority priority = ProjectTaskPriority.normal,
  ProjectRiskReduction riskReduction = ProjectRiskReduction.none,
  ProjectTaskReadiness readiness = ProjectTaskReadiness.ready,
  ProjectTaskStatus status = ProjectTaskStatus.queued,
  String? milestoneId,
  String? recoveryIncidentId,
  DateTime? createdAt,
}) {
  final now = createdAt ?? DateTime.utc(2026, 1, 1);
  return ProjectTask(
    id: id,
    title: 'Task $id',
    objective: 'Complete bounded work for $id.',
    dependsOnTaskIds: dependencies,
    priority: priority,
    riskReduction: riskReduction,
    readiness: readiness,
    milestoneId: milestoneId,
    doneCriteria: const ['The work is verified.'],
    outOfScope: const ['Unrelated work.'],
    context: const [],
    expectedArtifacts: const [],
    status: status,
    taskDocumentId: null,
    recoveryIncidentId: recoveryIncidentId,
    fingerprint: 'fingerprint_$id',
    rejectionReason: null,
    createdAt: now,
    updatedAt: now,
  );
}

ProjectMilestone _milestone(
  String id,
  ProjectMilestoneStatus status,
  int order,
) {
  final now = DateTime.utc(2026, 1, 1);
  return ProjectMilestone(
    id: id,
    title: 'Milestone $id',
    objective: 'Complete milestone $id.',
    status: status,
    order: order,
    createdAt: now,
    updatedAt: now,
  );
}

ProjectRecoveryIncident _incident(
  String id, {
  List<String> recoveryTaskIds = const [],
}) {
  final now = DateTime.utc(2026, 1, 1);
  return ProjectRecoveryIncident(
    id: id,
    status: ProjectRecoveryIncidentStatus.active,
    sourceTaskIds: const ['source'],
    sourceTaskTitles: const ['Source'],
    failedGateId: 'gate',
    failureSummary: 'Gate failed.',
    attemptCount: 0,
    recoveryTaskIds: recoveryTaskIds,
    createdAt: now,
    updatedAt: now,
  );
}
