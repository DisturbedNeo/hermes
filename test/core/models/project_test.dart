import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/features/task/domain/task.dart';

void main() {
  test(
    'ProjectAggregate exposes one task collection and derives revisions',
    () {
      final now = DateTime(2026, 1, 1);
      final project = ProjectAggregate(
        id: 'project_1',
        title: 'Project',
        originalGoal: 'Build the app',
        refinedGoal: 'Build the app safely',
        criteria: [
          ProjectCriterion(
            id: 'criterion_1',
            statement: 'The app works',
            createdAt: now,
            updatedAt: now,
          ),
        ],
        constraints: const [],
        tasks: const [],
        status: ProjectStatus.active,
        activeTaskId: null,
        createdAt: now,
        updatedAt: now,
      );

      expect(project.tasks, isEmpty);
      expect(project.nextRevision, 2);
      expect(project.taskById('missing'), isNull);
    },
  );

  test('task lifecycle status is the authority for task state', () {
    final now = DateTime(2026, 1, 1);
    final task = Task(
      id: 'task_1',
      title: 'Task',
      objective: 'Do one thing',
      criterionIds: const ['criterion_1'],
      doneCriteria: const ['Done'],
      outOfScope: const ['Everything else'],
      context: const [],
      expectedArtifacts: const [],
      status: TaskStatus.completed,
      fingerprint: 'task',
      rejectionReason: null,
      createdAt: now,
      updatedAt: now,
    );
    expect(task.status, TaskStatus.completed);
  });

  test('addresses the active task through its canonical ID', () {
    final now = DateTime(2026, 1, 1);
    final task = Task(
      id: 'project_task_1',
      title: 'Task',
      objective: 'Do one bounded thing',
      criterionIds: const ['criterion_1'],
      doneCriteria: const ['Done'],
      outOfScope: const ['Everything else'],
      context: const [],
      expectedArtifacts: const [],
      status: TaskStatus.running,
      fingerprint: 'task',
      rejectionReason: null,
      createdAt: now,
      updatedAt: now,
    );
    final project = ProjectAggregate(
      id: 'project_1',
      title: 'Project',
      originalGoal: 'Build the app',
      refinedGoal: 'Build the app safely',
      criteria: [
        ProjectCriterion(
          id: 'criterion_1',
          statement: 'The app works',
          createdAt: now,
          updatedAt: now,
        ),
      ],
      constraints: const [],
      tasks: [ProjectTaskNode.fromTask(task)],
      status: ProjectStatus.runningTask,
      activeTaskId: task.id,
      createdAt: now,
      updatedAt: now,
    );

    expect(project.activeTaskId, task.id);
    expect(project.taskById(project.activeTaskId!)?.id, task.id);
  });
}
