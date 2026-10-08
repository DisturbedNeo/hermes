import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/planning_test_helpers.dart';
import 'package:hermes/core/contracts/acceptance.dart';
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
    );

    expect((view['acceptance'] as List).single['ref'], 'task-complete');
    expect((view['control'] as Map)['outcome'], 'awaiting_approval');
    expect(
      ((view['control'] as Map)['pending_approval'] as Map)['step_ref'],
      'step_1',
    );
  });

  test('task view exposes cursors for navigating bounded collections', () {
    final task = _task(
      steps: [
        for (var index = 1; index <= 3; index++)
          TaskStep(
            id: 'step_$index',
            title: 'Step $index',
            objective: 'Complete step $index.',
            instructions: const [],
            mayEditFiles: false,
            artifacts: const [],
            status: TaskStepStatus.pending,
          ),
      ],
    );
    final first = const TaskViewService().query(task, maxItems: 1);
    final firstPage =
        ((first['navigation'] as Map)['pages'] as Map)['steps'] as Map;

    expect(firstPage['total'], 3);
    expect(firstPage['offset'], 0);
    expect(firstPage['has_more'], isTrue);
    expect(firstPage['next_cursor'], 'steps:1');
    expect((first['steps'] as List), hasLength(1));

    final second = const TaskViewService().query(
      task,
      maxItems: 1,
      section: 'steps',
      cursor: firstPage['next_cursor'] as String,
    );
    final secondPage =
        ((second['navigation'] as Map)['pages'] as Map)['steps'] as Map;

    expect(secondPage['offset'], 1);
    expect(secondPage['next_cursor'], 'steps:2');
    expect((second['steps'] as List).single['ref'], 'step_2');
  });

  test('task view rejects malformed navigation cursors', () {
    expect(
      () => const TaskViewService().query(
        _task(),
        section: 'steps',
        cursor: 'steps:not-a-number',
      ),
      throwsA(
        isA<TaskViewException>().having(
          (error) => error.code,
          'code',
          'invalid_cursor',
        ),
      ),
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
    'task acceptance can use the same temporary step references as task_view',
    () async {
      final context = TaskPlanningToolContext(
        task: _task(),
        workspaceRoot: '/workspace',
        maxSteps: 2,
      );
      final registry = TaskPlanningToolRegistry(context: context);

      final acceptance = await invokePlanning(registry, 'task_add_acceptance', {
        'ref': 'tests-pass',
        'statement': 'The focused tests pass.',
        'verifiers': [
          {'kind': 'command', 'command': 'dart test test/example_test.dart'},
        ],
      });
      expect(acceptance['ok'], isTrue);
      await invokePlanning(registry, 'task_add_step', {
        'ref': 'verify',
        'objective': 'Verify the bounded outcome.',
        'instructions': ['Run the verification.'],
        'acceptance_refs': ['tests-pass'],
      });
      expect(context.builder.steps.single.acceptanceRefs, ['tests-pass']);
    },
  );

  test('builder generates step and check identity and validates the draft', () {
    final baseTask = _task().copyWith(
      acceptance: const [],
    );
    final builder = TaskPlanBuilder(task: baseTask, maxSteps: 2);

    builder.addAcceptance(
      item: const AcceptanceItem(
        ref: 'tests-pass',
        statement: 'The focused tests pass.',
        verifiers: [
          AcceptanceVerifier(
            kind: AcceptanceVerifierKind.command,
            command: 'dart test test/example_test.dart',
          ),
        ],
      ),
    );

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
        acceptanceRefs: ['tests-pass'],
      ),
      commandId: 'add-inspect',
    );
    final committed = builder.commit();

    expect(firstId, startsWith('step_'));
    expect(committed.valid, isTrue);
    expect(committed.task.steps.single.id, firstId);
    expect(committed.task.acceptance.single.ref, 'tests-pass');

    final taskLevelBuilder = TaskPlanBuilder(task: baseTask, maxSteps: 2);
    taskLevelBuilder.addAcceptance(
      item: const AcceptanceItem(
        ref: 'analysis',
        statement: 'Analysis passes.',
        verifiers: [
          AcceptanceVerifier(
            kind: AcceptanceVerifierKind.command,
            command: 'dart analyze',
          ),
        ],
      ),
    );
    expect(taskLevelBuilder.commit().task.acceptance.single.ref, 'analysis');
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
    builder.addAcceptance(
      item: const AcceptanceItem(
        ref: 'directory-output',
        statement: 'The output directory exists and is usable.',
        verifiers: [
          AcceptanceVerifier(
            kind: AcceptanceVerifierKind.artifact,
            path: 'build/output',
            artifactKind: 'directory',
          ),
        ],
      ),
    );
    builder.addStep(
      const TaskPlanStepSpec(
        ref: 'directory',
        title: 'Create output directory',
        objective: 'Create the output directory.',
        instructions: ['Create the directory.'],
        artifacts: [TaskArtifact(path: 'build/output', kind: 'directory')],
        acceptanceRefs: ['directory-output'],
      ),
    );

    final committed = builder.commit();
    expect(committed.valid, isTrue);
    expect(committed.task.steps.single.artifacts.single.kind, 'directory');
    expect(committed.task.acceptance.last.ref, 'directory-output');
  });

  test('required project command checks match canonical directory fields', () {
    final source = _task().copyWith(
      acceptance: const [],
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
    );
    final builder = TaskPlanBuilder(
      task: source,
      maxSteps: 2,
      acceptance: const [
        AcceptanceItem(
          ref: 'project-tests',
          statement: 'The project tests pass.',
          verifiers: [
            AcceptanceVerifier(
              kind: AcceptanceVerifierKind.command,
              command: 'dart test',
            ),
          ],
        ),
      ],
    );

    final committed = builder.commit();
    expect(committed.valid, isTrue);
    expect(committed.task.acceptance.single.ref, 'project-tests');
  });

  test('rejects terminal-policy-blocked checks while adding them', () {
    final builder = TaskPlanBuilder(
      task: _task().copyWith(
        acceptance: const [],
      ),
      maxSteps: 2,
    );

    expect(
      () => builder.addAcceptance(
        item: const AcceptanceItem(
          ref: 'blocked',
          statement: 'The blocked command must not be accepted.',
          verifiers: [
            AcceptanceVerifier(
              kind: AcceptanceVerifierKind.command,
              command: 'test -f output.txt && n=\$(grep -c pattern output.txt)',
            ),
          ],
        ),
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
    expect(builder.acceptance, isEmpty);
  });

  test('reports blocked pre-existing checks during final validation', () {
    final source = _task().copyWith(
      acceptance: const [
        AcceptanceItem(
          ref: 'blocked',
          statement: 'The command must be safe.',
          verifiers: [
            AcceptanceVerifier(
              kind: AcceptanceVerifierKind.command,
              command: 'echo "\$(cat secrets.txt)"',
            ),
          ],
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
    acceptance: const [
      AcceptanceItem(
        ref: 'task-complete',
        statement: 'The bounded task is complete.',
        verifiers: [AcceptanceVerifier(kind: AcceptanceVerifierKind.review)],
      ),
    ],
    steps: steps,
    status: TaskStatus.paused,
    createdAt: now,
    updatedAt: now,
  );
}
