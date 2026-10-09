import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/contracts/acceptance.dart';
import 'package:hermes/features/task/domain/task.dart';
import 'package:hermes/features/task/runtime/task_plan_builder.dart';

void main() {
  test('builder generates step and acceptance identity', () {
    final baseTask = _task().copyWith(acceptance: const []);
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
  });

  test('directory artifacts use the actual-type non-empty gate', () {
    final builder = TaskPlanBuilder(
      task: _task().copyWith(acceptance: const []),
      maxSteps: 2,
    );
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
    expect(committed.task.acceptance.single.ref, 'directory-output');
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

  test('rejects blocked checks while adding them', () {
    final builder = TaskPlanBuilder(
      task: _task().copyWith(acceptance: const []),
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

TaskAggregate _task() {
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
    status: TaskStatus.paused,
    createdAt: now,
    updatedAt: now,
  );
}
