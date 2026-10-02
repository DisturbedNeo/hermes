import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/features/task/domain/task.dart';
import 'package:hermes/features/project/runtime/project_state_models.dart';
import 'package:hermes/features/project/application/contracts/project_task_models.dart';

void main() {
  test('exposes separate plan, execution, evidence, and control views', () {
    final now = DateTime(2026, 1, 1);
    final task = TaskAggregate(
      id: 'task_1',
      title: 'Task',
      objective: 'Do the task',
      status: TaskStatus.running,
      createdAt: now,
      updatedAt: now,
    );
    final project = ProjectAggregate(
      id: 'project_1',
      title: 'Project',
      originalGoal: 'Build it',
      refinedGoal: 'Build it safely',
      criteria: const [],
      constraints: const [],
      tasks: [ProjectTaskNode.fromTask(task)],
      status: ProjectStatus.runningTask,
      activeTaskId: task.id,
      createdAt: now,
      updatedAt: now,
    );

    expect(project.plan.tasks.single.id, task.id);
    expect(project.execution.activeTaskId, task.id);
    expect(project.evidenceState.evidence, isEmpty);
    expect(project.control.status, ProjectStatus.runningTask);

    final execution = TaskExecution.fromTask(task, observedAt: now);
    expect(execution.taskId, task.id);
    expect(execution.status, TaskStatus.running);
    expect(execution.latestRun, isNull);
  });
}
