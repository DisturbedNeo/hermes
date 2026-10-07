import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/planning_test_helpers.dart';
import 'package:hermes/features/task/domain/task.dart';
import 'package:hermes/features/task/runtime/task_plan_builder.dart';
import 'package:hermes/features/task/runtime/task_planning_tools.dart';
import 'package:hermes/features/task/runtime/task_view_service.dart';

void main() {
  test(
    'task step schema requires an objective and derives an optional title',
    () async {
      final context = TaskPlanningToolContext(
        task: _task(),
        workspaceRoot: '/workspace',
        maxSteps: 2,
      );
      final registry = TaskPlanningToolRegistry(context: context);
      final schema = registry.toolDefinitions
          .singleWhere((item) => item.id == 'task_add_step')
          .schema
          .toWire();
      expect(schema['required'], ['objective']);

      final added = await invokePlanning(registry, 'task_add_step', {
        'objective': 'Complete the bounded step.',
      });
      expect(added['ok'], isTrue);
      expect((added['step'] as Map)['objective'], 'Complete the bounded step.');
      expect((added['state'] as Map)['plan'], isA<Map>());
      expect(context.builder.steps.single.title, 'Complete the bounded step.');
    },
  );

  test('task view exposes evidence links and pending control state', () {
    final now = DateTime(2026, 1, 1);
    final view = const TaskViewService().query(
      _task().copyWith(
        pendingApproval: PendingTaskApproval(
          stepId: 'step_1',
          reason: 'The step edits source files.',
          createdAt: now,
        ),
      ),
      requiredEvidence: const [
        TaskProjectEvidenceExpectation(
          id: 'expect_1',
          criterionIds: ['criterion_1'],
          description: 'The criterion is checked.',
        ),
      ],
    );

    expect((view['required_project_evidence'] as List).single, {
      'type': 'task_claim',
      'criterion_refs': ['criterion_1'],
      'description': 'The criterion is checked.',
      'required': true,
      'source_ref': null,
      'details': {},
    });
    expect((view['control'] as Map)['outcome'], 'awaiting_approval');
    expect(
      ((view['control'] as Map)['pending_approval'] as Map)['step_ref'],
      'step_1',
    );
  });

  test('task view resolves temporary step references from the draft', () async {
    final context = TaskPlanningToolContext(
      task: _task(),
      workspaceRoot: '/workspace',
      maxSteps: 2,
    );
    final registry = TaskPlanningToolRegistry(context: context);

    final added = await invokePlanning(registry, 'task_add_step', {
      'ref': 'inspect',
      'objective': 'Inspect the relevant workspace files.',
      'instructions': ['Read the relevant files.'],
    });
    final step = added['step'] as Map;

    final viewed = await invokePlanning(registry, 'task_view', {
      'step_ref': 'inspect',
    });

    expect(viewed['ok'], isTrue);
    expect((viewed['step_detail'] as Map)['ref'], step['id']);
    expect((viewed['step_detail'] as Map)['objective'], contains('Inspect'));
  });

  test(
    'task checks can use the same temporary step references as task_view',
    () async {
      final context = TaskPlanningToolContext(
        task: _task(),
        workspaceRoot: '/workspace',
        maxSteps: 2,
      );
      final registry = TaskPlanningToolRegistry(context: context);

      await invokePlanning(registry, 'task_add_step', {
        'ref': 'verify',
        'objective': 'Verify the bounded outcome.',
        'instructions': ['Run the verification.'],
      });
      final checked = await invokePlanning(registry, 'task_add_check', {
        'step_ref': 'verify',
        'command': 'dart test test/example_test.dart',
      });

      expect(checked['ok'], isTrue);
      expect((checked['check'] as Map)['step_ref'], 'verify');
      expect(((checked['check'] as Map)['step'] as Map)['ref'], 'verify');
    },
  );

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
                await executePlanning(
                  registry,
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
                await executePlanning(
                  registry,
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

      final discarded = await invokePlanning(registry, 'task_add_step', {
        'ref': 'discarded',
        'title': 'Discarded draft step',
        'objective': 'This draft will be replaced.',
        'instructions': ['Do not retain this draft.'],
      }, commandId: 'discarded');
      expect(discarded['ok'], isTrue);

      final reset = await invokePlanning(
        registry,
        'task_reset_plan',
        const {},
        commandId: 'reset',
      );
      expect(reset['ok'], isTrue);
      expect(context.builder.steps.map((step) => step.id), ['completed_step']);

      final added = await invokePlanning(registry, 'task_add_step', {
        'ref': 'replacement',
        'title': 'Replacement step',
        'objective': 'Complete the replacement work.',
        'instructions': ['Complete the replacement.'],
      }, commandId: 'replacement');

      expect(added['ok'], isTrue);
      final viewed = await invokePlanning(registry, 'task_view', {
        'step_ref': 'replacement',
      }, commandId: 'view-replacement');
      expect(viewed['ok'], isTrue);
      expect(
        (viewed['step_detail'] as Map)['objective'],
        'Complete the replacement work.',
      );

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

  test('directory artifacts use the same actual-type non-empty gate', () {
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
      'artifact_nonempty',
    ]);
  });

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

  test('rejects terminal-policy-blocked checks while adding them', () {
    final builder = TaskPlanBuilder(task: _task(), maxSteps: 2);

    expect(
      () => builder.addCheck(
        command: 'test -f output.txt && n=\$(grep -c pattern output.txt)',
      ),
      throwsA(
        isA<TaskPlanBuilderException>()
            .having((error) => error.code, 'code', 'blocked_command')
            .having(
              (error) => error.message,
              'message',
              contains('command substitution'),
            ),
      ),
    );
    expect(builder.taskGates, isEmpty);
  });

  test('reports blocked pre-existing checks during final validation', () {
    final source = _task().copyWith(
      gates: const [
        TaskGate(
          id: 'command_passes',
          params: {
            'command': 'echo "\$(cat secrets.txt)"',
            'working_directory': '.',
          },
        ),
      ],
    );
    final committed = TaskPlanBuilder(task: source, maxSteps: 2).commit();

    expect(committed.valid, isFalse);
    expect(
      committed.issues,
      contains(
        isA<TaskPlanIssue>()
            .having((issue) => issue.code, 'code', 'blocked_command')
            .having(
              (issue) => issue.message,
              'message',
              contains('command substitution'),
            ),
      ),
    );
  });
}

TaskAggregate _task({List<TaskStep> steps = const []}) {
  final now = DateTime(2026, 1, 1);
  return TaskAggregate(
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
