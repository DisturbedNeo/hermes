import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/task.dart';

void main() {
  test('task JSON remains backward compatible without gates', () {
    final task = TaskDocument.fromJson({
      'id': 'task_1',
      'title': 'Old task',
      'originalPrompt': 'Do work',
      'goal': 'Do work',
      'constraints': <String>[],
      'successCriteria': ['Done'],
      'steps': [
        {
          'id': 'step_1',
          'title': 'Step 1',
          'objective': 'Work',
          'instructions': ['Work'],
          'mayEditFiles': false,
          'artifacts': <Map<String, dynamic>>[],
          'status': 'pending',
        },
      ],
      'status': 'paused',
      'currentStepId': 'step_1',
      'memorySummary': '',
      'runs': <Map<String, dynamic>>[],
      'createdAt': '2026-01-01T00:00:00.000',
      'updatedAt': '2026-01-01T00:00:00.000',
    });

    expect(task.gates, isEmpty);
    expect(task.steps.single.gates, isEmpty);
  });

  test('serializes task, step, and run gate metadata', () {
    final now = DateTime(2026, 1, 1);
    final task = TaskDocument(
      id: 'task_1',
      title: 'Task',
      originalPrompt: 'Do work',
      goal: 'Do work',
      constraints: const [],
      successCriteria: const ['Done'],
      gates: const [TaskGate(id: 'no_tool_errors', scope: 'task')],
      steps: const [
        TaskStep(
          id: 'step_1',
          title: 'Step 1',
          objective: 'Work',
          instructions: ['Work'],
          mayEditFiles: false,
          artifacts: [],
          gates: [
            TaskGate(
              id: 'artifact_exists',
              params: {
                'paths': ['out.md'],
              },
            ),
          ],
          status: TaskStepStatus.pending,
        ),
      ],
      status: TaskStatus.paused,
      currentStepId: 'step_1',
      memorySummary: '',
      runs: [
        TaskRun(
          runId: 'run_1',
          stepId: 'step_1',
          status: TaskRunStatus.completed,
          summary: 'Done',
          memoryUpdate: '',
          toolCalls: const [],
          artifacts: const [],
          gateResults: [
            TaskGateResult(
              gateId: 'no_tool_errors',
              status: TaskGateStatus.passed,
              summary: 'Passed',
              evaluatedAt: now,
            ),
          ],
          startedAt: now,
        ),
      ],
      createdAt: now,
      updatedAt: now,
    );

    final decoded = TaskDocument.fromJson(task.toJson());

    expect(decoded.gates.single.id, 'no_tool_errors');
    expect(decoded.steps.single.gates.single.id, 'artifact_exists');
    expect(
      decoded.runs.single.gateResults.single.status,
      TaskGateStatus.passed,
    );
  });
}
