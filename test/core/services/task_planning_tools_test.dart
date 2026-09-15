import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/services/task_system/task_plan_builder.dart';
import 'package:hermes/core/services/task_system/task_planning_tools.dart';

void main() {
  test('builder generates step and check identity and validates the draft', () {
    final builder = TaskPlanBuilder(task: _task(), maxSteps: 2);

    final firstId = builder.addStep(
      const TaskPlanStepSpec(
        ref: 'inspect',
        title: 'Inspect the workspace',
        objective: 'Inspect the relevant source files.',
        instructions: ['Read the relevant files.'],
        artifacts: [
          TaskArtifact(
            path: '.agent/tasks/task_1/inspection.md',
            description: 'Inspection notes',
          ),
        ],
      ),
      commandId: 'add-inspect',
    );
    final expectationId = builder.addCheck(
      stepReference: 'inspect',
      command: 'dart test test/example_test.dart',
      commandId: 'check-tests',
    );
    final committed = builder.commit();

    expect(firstId, startsWith('step_'));
    expect(expectationId, startsWith('expect_'));
    expect(committed.valid, isTrue);
    expect(committed.task.steps.single.id, firstId);
    expect(committed.task.steps.single.gates.map((gate) => gate.id), [
      'artifact_exists',
      'artifact_nonempty',
      'command_passes',
    ]);
    expect(committed.task.expectedEvidence.single.id, expectationId);

    final taskLevelBuilder = TaskPlanBuilder(task: _task(), maxSteps: 2);
    taskLevelBuilder.addCheck(command: 'dart analyze');
    expect(
      taskLevelBuilder.commit().task.gates.map((gate) => gate.id),
      contains('command_passes'),
    );
  });

  test(
    'registry rejects persistent step fields without changing the draft',
    () async {
      final context = TaskPlanningToolContext(
        task: _task(),
        workspaceRoot: '/workspace',
        maxSteps: 2,
      );
      final registry = TaskPlanningToolRegistry(context: context);

      final rejected =
          jsonDecode(
                await registry.execute(
                  'task_add_step',
                  jsonEncode({
                    'id': 'model_step',
                    'title': 'Invalid step',
                    'objective': 'This must be rejected.',
                    'instructions': [],
                  }),
                  commandId: 'invalid-step',
                ),
              )
              as Map<String, dynamic>;
      final accepted =
          jsonDecode(
                await registry.execute(
                  'task_add_step',
                  jsonEncode({
                    'ref': 'valid',
                    'title': 'Valid step',
                    'objective': 'Add a valid step.',
                    'instructions': ['Do the work.'],
                  }),
                  commandId: 'valid-step',
                ),
              )
              as Map<String, dynamic>;

      expect(rejected['ok'], isFalse);
      expect(rejected['code'], 'invalid_argument');
      expect(accepted['ok'], isTrue);
      expect(context.builder.steps, hasLength(1));
    },
  );

  test(
    'replan builder preserves completed steps and only adds fresh steps',
    () async {
      final source = _task(
        steps: const [
          TaskStep(
            id: 'completed_step',
            title: 'Completed step',
            objective: 'Preserve this work.',
            instructions: [],
            mayEditFiles: false,
            artifacts: [],
            status: TaskStepStatus.completed,
          ),
          TaskStep(
            id: 'unfinished_step',
            title: 'Unfinished step',
            objective: 'Replace this work.',
            instructions: [],
            mayEditFiles: false,
            artifacts: [],
            status: TaskStepStatus.pending,
          ),
        ],
      );
      final context = TaskPlanningToolContext(
        task: source,
        workspaceRoot: '/workspace',
        maxSteps: 3,
        preserveCompletedStepsOnly: true,
      );
      final registry = TaskPlanningToolRegistry(context: context);

      final discarded = await registry.invoke('task_add_step', {
        'ref': 'discarded',
        'title': 'Discarded draft step',
        'objective': 'This draft will be replaced.',
        'instructions': ['Do not retain this draft.'],
      }, commandId: 'discarded');
      expect(discarded['ok'], isTrue);

      final reset = await registry.invoke(
        'task_reset_plan',
        const {},
        commandId: 'reset',
      );
      expect(reset['ok'], isTrue);
      expect(context.builder.steps.map((step) => step.id), ['completed_step']);

      final added = await registry.invoke('task_add_step', {
        'ref': 'replacement',
        'title': 'Replacement step',
        'objective': 'Complete the replacement work.',
        'instructions': ['Complete the replacement.'],
      }, commandId: 'replacement');

      expect(added['ok'], isTrue);
      final committed = context.builder.commit();
      expect(committed.valid, isTrue);
      expect(committed.task.steps.map((step) => step.id), [
        'completed_step',
        isNot('unfinished_step'),
      ]);
      expect(committed.task.steps.last.title, 'Replacement step');
      expect(committed.task.steps.first.status, TaskStepStatus.completed);
    },
  );

  test(
    'directory artifacts require existence but not file non-empty checks',
    () {
      final builder = TaskPlanBuilder(task: _task(), maxSteps: 2);
      builder.addStep(
        const TaskPlanStepSpec(
          ref: 'directory',
          title: 'Create output directory',
          objective: 'Create the output directory.',
          instructions: ['Create the directory.'],
          artifacts: [TaskArtifact(path: 'build/output', kind: 'directory')],
        ),
      );

      final committed = builder.commit();
      expect(committed.valid, isTrue);
      expect(committed.task.steps.single.artifacts.single.kind, 'directory');
      expect(committed.task.steps.single.gates.map((gate) => gate.id), [
        'artifact_exists',
      ]);
    },
  );

  test('required project command checks match canonical directory fields', () {
    final source = _task().copyWith(
      steps: const [
        TaskStep(
          id: 'existing',
          title: 'Existing step',
          objective: 'Complete the existing step.',
          instructions: [],
          mayEditFiles: false,
          artifacts: [],
          status: TaskStepStatus.pending,
        ),
      ],
      gates: const [
        TaskGate(
          id: 'command_passes',
          required: false,
          params: {'command': 'dart test', 'working_directory': '.'},
        ),
      ],
    );
    final builder = TaskPlanBuilder(
      task: source,
      maxSteps: 2,
      requiredGates: const [
        TaskGate(
          id: 'command_passes',
          params: {'command': 'dart test', 'working_directory': '.'},
        ),
      ],
    );

    final committed = builder.commit();
    expect(committed.valid, isTrue);
    expect(committed.task.gates, hasLength(1));
    expect(committed.task.gates.single.required, isTrue);
  });
}

Task _task({List<TaskStep> steps = const []}) {
  final now = DateTime(2026, 1, 1);
  return Task(
    id: 'task_1',
    title: 'Bounded task',
    objective: 'Complete the bounded task.',
    successCriteria: const ['The bounded task is complete.'],
    steps: steps,
    status: TaskStatus.paused,
    createdAt: now,
    updatedAt: now,
  );
}
