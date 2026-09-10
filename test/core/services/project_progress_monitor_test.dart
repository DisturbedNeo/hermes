import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/services/project_system/project_progress_monitor.dart';

void main() {
  const monitor = ProjectProgressMonitor();
  final now = DateTime.utc(2026, 1, 1);

  test('blocks after three completed tasks make no criterion progress', () {
    var project = _project(now);
    final before = {'criterion_1': ProjectCriterionStatus.unsatisfied};

    for (var index = 1; index <= 3; index++) {
      project = monitor.recordTaskResult(
        project: project,
        task: _task('task_$index', now),
        taskAccepted: true,
        criterionStatusesBefore: before,
        evaluatedAt: now.add(Duration(minutes: index)),
      );
    }

    expect(project.status, ProjectStatus.blocked);
    expect(project.blocker?.type, ProjectBlockerType.stagnation);
    expect(project.blocker?.message, contains('3 completed tasks'));
    expect(project.blocker?.message, contains('task_1, task_2, task_3'));
    expect(project.diagnostics.taskExecutions, 3);
    expect(project.diagnostics.completedTaskExecutions, 3);
    expect(project.diagnostics.completedTasksWithoutCriterionProgress, 3);
    expect(project.diagnostics.consecutiveNoProgressIterations, 3);
  });

  test('criterion progress resets the consecutive stagnation count', () {
    var project = monitor.recordTaskResult(
      project: _project(now),
      task: _task('task_1', now),
      taskAccepted: true,
      criterionStatusesBefore: const {
        'criterion_1': ProjectCriterionStatus.unsatisfied,
      },
      evaluatedAt: now,
    );
    project = monitor.recordTaskResult(
      project: project.copyWith(
        criteria: [
          project.criteria.single.copyWith(
            status: ProjectCriterionStatus.partial,
          ),
        ],
      ),
      task: _task('task_2', now),
      taskAccepted: true,
      criterionStatusesBefore: const {
        'criterion_1': ProjectCriterionStatus.unsatisfied,
      },
      evaluatedAt: now,
    );

    expect(project.status, ProjectStatus.active);
    expect(project.diagnostics.consecutiveNoProgressIterations, 0);
    expect(project.diagnostics.recentNoProgressTaskIds, isEmpty);
    expect(project.diagnostics.completedTasksWithoutCriterionProgress, 1);
  });

  test('new accepted supporting evidence counts as progress', () {
    final first = monitor.recordTaskResult(
      project: _project(now),
      task: _task('task_1', now),
      taskAccepted: true,
      criterionStatusesBefore: const {
        'criterion_1': ProjectCriterionStatus.unsatisfied,
      },
      evaluatedAt: now,
    );
    final evidence = ProjectEvidence(
      id: 'evidence_task_2',
      type: ProjectEvidenceType.artifact,
      criterionIds: const ['criterion_1'],
      taskId: 'task_2',
      runId: 'run_task_2',
      sourceRef: 'report.md',
      summary: 'The report artifact was produced.',
      status: ProjectEvidenceStatus.accepted,
      strength: ProjectEvidenceStrength.supporting,
      createdAt: now,
      evaluatedAt: now,
    );

    final project = monitor.recordTaskResult(
      project: first.copyWith(evidence: [evidence]),
      task: _task('task_2', now),
      taskAccepted: true,
      criterionStatusesBefore: const {
        'criterion_1': ProjectCriterionStatus.unsatisfied,
      },
      acceptedEvidenceIdsBefore: const {},
      evaluatedAt: now,
    );

    expect(project.status, ProjectStatus.active);
    expect(project.diagnostics.consecutiveNoProgressIterations, 0);
    expect(project.diagnostics.recentNoProgressTaskIds, isEmpty);
    expect(project.diagnostics.completedTasksWithoutCriterionProgress, 1);
  });

  test(
    'successful diagnostic replanning does not consume stagnation budget',
    () {
      final initial = _project(now).copyWith(
        diagnostics: const ProjectDiagnostics(
          consecutiveNoProgressIterations: 2,
          recentNoProgressTaskIds: ['task_old_1', 'task_old_2'],
          completedTasksWithoutCriterionProgress: 2,
        ),
      );

      final project = monitor.recordTaskResult(
        project: initial,
        task: _task('diagnostic_task', now),
        taskAccepted: true,
        excludeFromStagnation: true,
        criterionStatusesBefore: const {
          'criterion_1': ProjectCriterionStatus.unsatisfied,
        },
        evaluatedAt: now,
      );

      expect(project.status, ProjectStatus.active);
      expect(project.diagnostics.completedTaskExecutions, 1);
      expect(project.diagnostics.completedTasksWithoutCriterionProgress, 2);
      expect(project.diagnostics.consecutiveNoProgressIterations, 0);
      expect(project.diagnostics.recentNoProgressTaskIds, isEmpty);
    },
  );

  test(
    'records criterion reversals without treating failed work as progress',
    () {
      final initial = _project(now).copyWith(
        criteria: [
          _project(now).criteria.single.copyWith(
            status: ProjectCriterionStatus.invalidated,
          ),
        ],
      );

      final project = monitor.recordTaskResult(
        project: initial,
        task: _task('failed_task', now),
        taskAccepted: false,
        criterionStatusesBefore: const {
          'criterion_1': ProjectCriterionStatus.satisfied,
        },
        evaluatedAt: now,
      );

      expect(project.diagnostics.taskExecutions, 1);
      expect(project.diagnostics.completedTaskExecutions, 0);
      expect(project.diagnostics.criterionReversals, 1);
      expect(project.diagnostics.consecutiveNoProgressIterations, 0);
    },
  );
}

ProjectDocument _project(DateTime now) {
  return ProjectDocument(
    id: 'project',
    title: 'Project',
    originalGoal: 'Ship the project.',
    refinedGoal: 'Ship the project.',
    criteria: [
      ProjectCriterion(
        id: 'criterion_1',
        statement: 'The outcome is verified.',
        createdAt: now,
        updatedAt: now,
      ),
    ],
    constraints: const [],
    status: ProjectStatus.active,
    activeTaskId: null,
    createdAt: now,
    updatedAt: now,
  );
}

Task _task(String id, DateTime now) {
  return Task(
    id: id,
    title: id,
    objective: 'Complete $id.',
    criterionIds: const ['criterion_1'],
    doneCriteria: const ['The task is done.'],
    outOfScope: const [],
    context: const [],
    expectedArtifacts: const [],
    status: TaskStatus.completed,
    fingerprint: id,
    rejectionReason: null,
    createdAt: now,
    updatedAt: now,
  );
}
