import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/shared_kernel/task.dart';
import 'package:hermes/shared_kernel/project_task_models.dart';
import 'package:hermes/shared_kernel/task_plan_materializer.dart';

void main() {
  test('updates planning metadata without replacing execution history', () {
    final now = DateTime(2026, 1, 1);
    final step = TaskStep(
      id: 'step_1',
      title: 'Execute',
      objective: 'Execute the task.',
      instructions: const ['Do it.'],
      mayEditFiles: true,
      artifacts: const [],
      status: TaskStepStatus.completed,
    );
    final run = TaskRun(
      runId: 'run_1',
      stepId: step.id,
      status: TaskRunStatus.completed,
      summary: 'Completed the step.',
      memoryUpdate: 'The step is verified.',
      toolCalls: const [],
      artifacts: const [],
      startedAt: now,
      completedAt: now,
    );
    final existing = Task(
      id: 'task_1',
      title: 'Old title',
      objective: 'Old objective',
      steps: [step],
      currentStepId: step.id,
      runs: [run],
      status: TaskStatus.completed,
      createdAt: now,
      updatedAt: now,
    );
    final node = ProjectTaskNode.fromTask(
      existing,
    ).copyWith(title: 'Revised title', objective: 'Revised objective');

    final updated = TaskPlanMaterializer().apply(
      node,
      existing,
      projectId: 'project_1',
    );

    expect(updated.title, 'Revised title');
    expect(updated.objective, 'Revised objective');
    expect(updated.steps, same(existing.steps));
    expect(updated.runs, same(existing.runs));
    expect(updated.currentStepId, existing.currentStepId);
  });
}
