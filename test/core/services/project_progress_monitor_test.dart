import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/services/project_system/project_progress_monitor.dart';

void main() {
  const monitor = ProjectProgressMonitor();
  final now = DateTime.utc(2026, 1, 1);

  test('multiple successful tasks in one batch do not trigger stagnation', () {
    var project = _batchedProject(now, ['task_1', 'task_2', 'task_3']);
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

    expect(project.status, ProjectStatus.active);
    expect(project.blocker, isNull);
    expect(project.diagnostics.taskExecutions, 3);
    expect(project.diagnostics.completedTaskExecutions, 3);
    expect(project.diagnostics.completedBatchesWithoutCriterionProgress, 1);
    expect(project.diagnostics.consecutiveNoProgressBatches, 1);
    expect(project.currentBatchProgressObserved, isFalse);
  });

  test('blocks after three complete no-progress batches', () {
    var project = _project(now);
    for (var index = 1; index <= 3; index++) {
      final taskId = 'batch_task_$index';
      project = _batchedProject(now, [
        taskId,
      ], planRevision: index).copyWith(diagnostics: project.diagnostics);
      project = monitor.recordTaskResult(
        project: project,
        task: _task(taskId, now),
        taskAccepted: true,
        criterionStatusesBefore: const {
          'criterion_1': ProjectCriterionStatus.unsatisfied,
        },
        evaluatedAt: now.add(Duration(minutes: index)),
      );
    }

    expect(project.status, ProjectStatus.blocked);
    expect(project.blocker?.type, ProjectBlockerType.stagnation);
    expect(project.blocker?.message, contains('3 completed batches'));
    expect(project.blocker?.message, contains('1:batch_task_1'));
    expect(project.diagnostics.completedBatchesWithoutCriterionProgress, 3);
    expect(project.diagnostics.consecutiveNoProgressBatches, 3);
    expect(project.diagnostics.recentNoProgressBatchIds, [
      '1:batch_task_1',
      '2:batch_task_2',
      '3:batch_task_3',
    ]);
  });

  test('progress observed by an earlier task counts when the batch closes', () {
    var project = _batchedProject(now, ['task_1', 'task_2']).copyWith(
      criteria: [
        _project(
          now,
        ).criteria.single.copyWith(status: ProjectCriterionStatus.partial),
      ],
    );
    project = monitor.recordTaskResult(
      project: project,
      task: _task('task_1', now),
      taskAccepted: true,
      criterionStatusesBefore: const {
        'criterion_1': ProjectCriterionStatus.unsatisfied,
      },
      evaluatedAt: now,
    );
    project = monitor.recordTaskResult(
      project: project,
      task: _task('task_2', now),
      taskAccepted: true,
      criterionStatusesBefore: const {
        'criterion_1': ProjectCriterionStatus.partial,
      },
      evaluatedAt: now.add(const Duration(minutes: 1)),
    );

    expect(project.status, ProjectStatus.active);
    expect(project.currentBatchProgressObserved, isFalse);
    expect(project.diagnostics.consecutiveNoProgressBatches, 0);
    expect(project.diagnostics.completedBatchesWithoutCriterionProgress, 0);
  });

  test('criterion progress resets the consecutive batch count', () {
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
    expect(project.diagnostics.consecutiveNoProgressBatches, 0);
    expect(project.diagnostics.recentNoProgressBatchIds, isEmpty);
    expect(project.diagnostics.completedBatchesWithoutCriterionProgress, 1);
  });

  test('new accepted supporting evidence counts as batch progress', () {
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
    expect(project.diagnostics.consecutiveNoProgressBatches, 0);
    expect(project.diagnostics.recentNoProgressBatchIds, isEmpty);
    expect(project.diagnostics.completedBatchesWithoutCriterionProgress, 1);
  });

  test(
    'successful diagnostic replanning does not consume stagnation budget',
    () {
      final initial = _project(now).copyWith(
        diagnostics: const ProjectDiagnostics(
          consecutiveNoProgressBatches: 2,
          recentNoProgressBatchIds: ['batch_old_1', 'batch_old_2'],
          completedBatchesWithoutCriterionProgress: 2,
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
      expect(project.diagnostics.completedBatchesWithoutCriterionProgress, 2);
      expect(project.diagnostics.consecutiveNoProgressBatches, 0);
      expect(project.diagnostics.recentNoProgressBatchIds, isEmpty);
    },
  );

  test('failed work does not consume the stagnation budget', () {
    final initial = _project(now).copyWith(
      diagnostics: const ProjectDiagnostics(
        consecutiveNoProgressBatches: 2,
        recentNoProgressBatchIds: ['batch_1', 'batch_2'],
        completedBatchesWithoutCriterionProgress: 2,
      ),
      criteria: [
        _project(
          now,
        ).criteria.single.copyWith(status: ProjectCriterionStatus.invalidated),
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
    expect(project.diagnostics.consecutiveNoProgressBatches, 2);
    expect(project.diagnostics.completedBatchesWithoutCriterionProgress, 2);
    expect(project.diagnostics.recentNoProgressBatchIds, [
      'batch_1',
      'batch_2',
    ]);
  });
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

ProjectDocument _batchedProject(
  DateTime now,
  List<String> taskIds, {
  int planRevision = 1,
}) {
  return _project(now).copyWith(
    currentBatchTaskIds: taskIds,
    currentBatchPlanRevision: planRevision,
  );
}

Task _task(String id, DateTime now) {
  return Task(
    id: id,
    title: id,
    objective: 'Implement bounded slice $id.',
    criterionIds: const ['criterion_1'],
    doneCriteria: const ['The bounded slice is complete.'],
    outOfScope: const ['Unrelated work.'],
    createdAt: now,
    updatedAt: now,
  );
}
