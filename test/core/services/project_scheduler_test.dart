import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/features/project/application/contracts/project_snapshot_models.dart';
import 'package:hermes/features/task/application/contracts/task_snapshot_models.dart';
import 'package:hermes/features/project/domain/project_scheduler.dart';

void main() {
  const scheduler = ProjectScheduler();

  test('derives readiness without mutating persisted tasks', () {
    final project = _project([
      _task('done', status: TaskStatus.completed),
      _task('ready', dependencies: const ['done']),
      _task('waiting', dependencies: const ['unfinished']),
      _task('unfinished'),
    ]);
    final before = project.tasks.map((task) => task.toJson()).toList();

    final result = scheduler.refreshReadiness(project);

    expect(result.project, same(project));
    expect(result.readinessFor('ready'), TaskReadiness.ready);
    expect(result.readinessFor('waiting'), TaskReadiness.waitingDependency);
    expect(result.reasonsFor('waiting'), [
      'Waiting for dependency unfinished (status: queued).',
    ]);
    expect(project.tasks.map((task) => task.toJson()).toList(), before);
  });

  test('rejects missing, self, and cyclic dependencies', () {
    final result = scheduler.schedule(
      _project([
        _task('self', dependencies: const ['self']),
        _task('missing', dependencies: const ['absent']),
        _task('cycle_a', dependencies: const ['cycle_b']),
        _task('cycle_b', dependencies: const ['cycle_a']),
      ]),
    );

    expect(result.selectedTask, isNull);
    expect(result.dependencyValidation.valid, isFalse);
    expect(
      result.readiness.values,
      everyElement(TaskReadiness.waitingDependency),
    );
  });

  test('selects deterministically and exposes the derived rationale', () {
    final project = _project([
      _task('low', priority: TaskPriority.low),
      _task('critical', priority: TaskPriority.critical),
    ]);
    final result = scheduler.schedule(project);

    expect(result.selectedTask?.id, 'critical');
    expect(result.selectionRationale, contains('critical priority'));
    expect(result.selectedTask?.selectionRationale, result.selectionRationale);
    expect(
      result.project.taskById('critical')?.selectionRationale,
      result.selectionRationale,
    );
    expect(project.taskById('critical')?.selectionRationale, isEmpty);
    expect(
      scheduler
          .orderedReadyTasks(_project([_task('b'), _task('a')]))
          .map((task) => task.id),
      ['a', 'b'],
    );
  });

  test('marks deferred, obsolete, running, and terminal tasks ineligible', () {
    final result = scheduler.refreshReadiness(
      _project([
        _task('deferred', status: TaskStatus.deferred),
        _task('obsolete', status: TaskStatus.obsolete),
        _task('running', status: TaskStatus.running),
        _task('failed', status: TaskStatus.failed),
      ]),
    );

    expect(result.readiness.values, everyElement(TaskReadiness.notEligible));
    expect(result.reasonsFor('deferred'), ['Task is deferred.']);
  });

  test(
    'treats dependencies on non-completable tasks as permanently blocked',
    () {
      final result = scheduler.refreshReadiness(
        _project([
          _task('obsolete', status: TaskStatus.obsolete),
          _task('dependent', dependencies: const ['obsolete']),
        ]),
      );

      expect(
        result.dependencyValidation.issues.map((issue) => issue.code),
        contains(ProjectDependencyIssueCode.deadDependency),
      );
      expect(result.readinessFor('dependent'), TaskReadiness.notEligible);
      expect(
        result.reasonsFor('dependent'),
        contains(contains('non-completable')),
      );
    },
  );

  test('builds a bounded frontier without turning its limit into a replan', () {
    final frontier = scheduler.executionFrontier(
      _project([
        _task('done', status: TaskStatus.completed),
        _task('ready_a', dependencies: const ['done']),
        _task('ready_b', dependencies: const ['done']),
        _task('waiting', dependencies: const ['ready_a']),
      ]),
      limit: 1,
    );

    expect(frontier.planRevision, 1);
    expect(frontier.taskIds, ['ready_a']);
  });
}

ProjectAggregate _project(List<Task> tasks) {
  final now = DateTime.utc(2026, 1, 1);
  return ProjectAggregate(
    id: 'project',
    title: 'Project',
    originalGoal: 'Deliver the project.',
    refinedGoal: 'Deliver the project.',
    criteria: [
      ProjectCriterion(
        id: 'criterion_1',
        statement: 'The project is delivered.',
        createdAt: now,
        updatedAt: now,
      ),
    ],
    constraints: const [],
    tasks: [for (final task in tasks) ProjectTaskNode.fromTask(task)],
    status: ProjectStatus.active,
    activeTaskId: null,
    createdAt: now,
    updatedAt: now,
  );
}

Task _task(
  String id, {
  List<String> dependencies = const [],
  TaskPriority priority = TaskPriority.normal,
  TaskStatus status = TaskStatus.queued,
}) {
  final now = DateTime.utc(2026, 1, 1);
  return Task(
    id: id,
    title: 'Task $id',
    objective: 'Complete bounded work for $id.',
    criterionIds: const ['criterion_1'],
    dependsOnTaskIds: dependencies,
    priority: priority,
    doneCriteria: const ['The work is verified.'],
    outOfScope: const ['Unrelated work.'],
    context: const [],
    expectedArtifacts: const [],
    status: status,
    rejectionReason: null,
    fingerprint: 'fingerprint_$id',
    createdAt: now,
    updatedAt: now,
  );
}
