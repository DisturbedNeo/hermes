import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/planning_test_helpers.dart';
import 'package:hermes/core/contracts/acceptance.dart';
import 'package:hermes/core/contracts/acceptance_compiler.dart';
import 'package:hermes/features/persistence/application/persistence_contracts.dart';
import 'package:hermes/features/persistence/infrastructure/dto/aggregate_snapshot_codecs.dart';
import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/features/project/runtime/project_evidence_service.dart';
import 'package:hermes/features/project/runtime/project_planning_tools.dart';
import 'package:hermes/features/task/domain/task.dart';
import 'package:hermes/features/task/runtime/task_plan_builder.dart';

void main() {
  test('acceptance contract encodes and decodes typed verifiers', () {
    const item = AcceptanceItem(
      ref: 'keyboard-accessible',
      statement: 'Every report-dialog action is keyboard reachable.',
      criterionIds: ['criterion_001'],
      verifiers: [
        AcceptanceVerifier(
          kind: AcceptanceVerifierKind.command,
          command: 'flutter test test/ui/report_dialog_test.dart',
          workingDirectory: '.',
        ),
      ],
    );

    final encoded = jsonDecode(item.toJson()) as Map<String, dynamic>;
    final decoded = AcceptanceItemMapper.fromMap(encoded);

    expect(decoded.ref, item.ref);
    expect(decoded.statement, item.statement);
    expect(decoded.criterionIds, item.criterionIds);
    expect(decoded.verifiers.single.kind, AcceptanceVerifierKind.command);
    expect(decoded.verifiers.single.command, item.verifiers.single.command);
  });

  group('AcceptanceCompiler', () {
    const compiler = AcceptanceCompiler();

    test('rejects missing statement, verifier, and required verifier', () {
      expect(
        () => compiler.compile([
          const AcceptanceItem(
            ref: 'x',
            statement: '',
            verifiers: [
              AcceptanceVerifier(kind: AcceptanceVerifierKind.review),
            ],
          ),
        ]),
        throwsA(
          isA<AcceptanceContractException>().having(
            (error) => error.code,
            'code',
            'missing_acceptance_statement',
          ),
        ),
      );
      expect(
        () => compiler.compile([
          const AcceptanceItem(ref: 'x', statement: 'A statement.'),
        ]),
        throwsA(
          isA<AcceptanceContractException>().having(
            (error) => error.code,
            'code',
            'missing_acceptance_verifier',
          ),
        ),
      );
      expect(
        () => compiler.compile([
          const AcceptanceItem(
            ref: 'x',
            statement: 'A statement.',
            verifiers: [
              AcceptanceVerifier(
                kind: AcceptanceVerifierKind.review,
                required: false,
              ),
            ],
          ),
        ]),
        throwsA(
          isA<AcceptanceContractException>().having(
            (error) => error.code,
            'code',
            'missing_required_verifier',
          ),
        ),
      );
    });

    test('rejects duplicate refs and unsafe workspace paths', () {
      const item = AcceptanceItem(
        ref: 'same',
        statement: 'A statement.',
        verifiers: [
          AcceptanceVerifier(
            kind: AcceptanceVerifierKind.artifact,
            path: 'output/report.md',
          ),
        ],
      );
      expect(
        () => compiler.compile([item, item]),
        throwsA(
          isA<AcceptanceContractException>().having(
            (error) => error.code,
            'code',
            'duplicate_acceptance_ref',
          ),
        ),
      );
      expect(
        () => compiler.compile([
          const AcceptanceItem(
            ref: 'unsafe',
            statement: 'A statement.',
            verifiers: [
              AcceptanceVerifier(
                kind: AcceptanceVerifierKind.artifact,
                path: '../outside.txt',
              ),
            ],
          ),
        ]),
        throwsA(
          isA<AcceptanceContractException>().having(
            (error) => error.code,
            'code',
            'unsafe_workspace_path',
          ),
        ),
      );
      expect(
        () => compiler.compile([
          const AcceptanceItem(
            ref: 'unsafe',
            statement: 'A statement.',
            verifiers: [
              AcceptanceVerifier(
                kind: AcceptanceVerifierKind.command,
                command: 'flutter test',
                workingDirectory: r'C:\workspace',
              ),
            ],
          ),
        ]),
        throwsA(isA<AcceptanceContractException>()),
      );
    });

    test('requires criteria only for project acceptance', () {
      const local = AcceptanceItem(
        ref: 'local',
        statement: 'The local note is present.',
        verifiers: [AcceptanceVerifier(kind: AcceptanceVerifierKind.review)],
      );
      expect(compiler.compile([local]).verifiers, hasLength(1));
      expect(
        () => compiler.compile([local], requireProjectCriteria: true),
        throwsA(
          isA<AcceptanceContractException>().having(
            (error) => error.code,
            'code',
            'missing_acceptance_criterion',
          ),
        ),
      );
    });
  });

  test('project task planning rejects unknown acceptance criteria', () async {
    final registry = ProjectPlanningToolRegistry(
      context: ProjectPlanningContext(
        project: _project(),
        workspaceRoot: '/workspace',
      ),
    );
    final response = await invokePlanning(registry, 'task_add', {
      'objective': 'Implement the bounded outcome.',
      'acceptance': [
        {
          'ref': 'unknown-link',
          'statement': 'The outcome is verified.',
          'criterion_ids': [99],
          'verifiers': [
            {'kind': 'review'},
          ],
        },
      ],
      'out_of_scope': ['Unrelated project work.'],
      'steps': [
        {'objective': 'Implement the bounded outcome.'},
      ],
    });

    expect(response['ok'], isFalse);
    expect(response['code'], 'unknown_reference');
  });

  test('acceptance can attach to exactly one task step', () {
    const acceptance = AcceptanceItem(
      ref: 'tests-pass',
      statement: 'The focused tests pass.',
      verifiers: [
        AcceptanceVerifier(
          kind: AcceptanceVerifierKind.command,
          command: 'flutter test test/example_test.dart',
        ),
      ],
    );
    final builder = TaskPlanBuilder(
      task: _task(),
      maxSteps: 3,
      acceptance: const [acceptance],
    );
    final stepId = builder.addStep(
      const TaskPlanStepSpec(
        ref: 'verify',
        objective: 'Run the focused tests.',
        acceptanceRefs: ['tests-pass'],
      ),
    );
    final committed = builder.commit();

    expect(committed.valid, isTrue);
    expect(committed.task.stepById(stepId)!.acceptanceRefs, ['tests-pass']);
    expect(committed.task.acceptance.single.ref, 'tests-pass');

    expect(
      () => builder.addStep(
        const TaskPlanStepSpec(
          objective: 'Attach it twice.',
          acceptanceRefs: ['tests-pass'],
        ),
      ),
      throwsA(isA<TaskPlanBuilderException>()),
    );
  });

  test('snapshots persist acceptance and reject unsupported envelopes', () {
    const acceptance = AcceptanceItem(
      ref: 'tests-pass',
      statement: 'The focused tests pass.',
      criterionIds: ['criterion_001'],
      verifiers: [
        AcceptanceVerifier(
          kind: AcceptanceVerifierKind.command,
          command: 'flutter test test/example_test.dart',
        ),
      ],
    );
    final task = _task().copyWith(acceptance: const [acceptance]);
    final document = TaskSnapshotCodec.encode(task);

    expect(document['acceptance'], isNotEmpty);
    expect(document, isNot(contains('gates')));
    expect(document, isNot(contains('successCriteria')));
    expect(document, isNot(contains('criterionIds')));
    expect(document, isNot(contains('doneCriteria')));
    expect(document, isNot(contains('expectedEvidence')));
    expect(document, isNot(contains('expectedArtifacts')));

    final envelope = SnapshotEnvelope.encode(document, 1);
    final reloaded = TaskSnapshotCodec.decode(
      SnapshotEnvelope.decode(envelope).document,
    );
    expect(reloaded.acceptance.single.ref, 'tests-pass');
    expect(
      () => SnapshotEnvelope.decode({
        'schema': 'hermes.v1',
        'revision': 1,
        'document': document,
      }),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('unsupported metadata'),
        ),
      ),
    );
  });

  test('local acceptance never becomes project evidence', () {
    final now = DateTime(2026, 1, 1);
    const local = AcceptanceItem(
      ref: 'local-note',
      statement: 'The local note is reviewed.',
      verifiers: [AcceptanceVerifier(kind: AcceptanceVerifierKind.review)],
    );
    final task = TaskAggregate(
      id: 'task_local',
      title: 'Local task',
      objective: 'Keep local proof local.',
      acceptance: const [local],
      createdAt: now,
      updatedAt: now,
    );
    final project = _project();
    final evidence = const ProjectEvidenceService().normalizeTaskResult(
      project: project,
      task: ProjectTaskNode.fromTask(task),
      result: TaskResult(
        taskId: task.id,
        status: TaskStatus.completed,
        summary: 'Done.',
        memoryUpdate: '',
        artifacts: const [],
        gateResults: [
          TaskGateResult(
            gateId: 'model_review',
            status: TaskGateStatus.passed,
            summary: 'Reviewed.',
            details: {'acceptance_ref': 'local-note', 'required': true},
            evaluatedAt: now,
          ),
        ],
        toolCallCount: 0,
      ),
      evaluatedAt: now,
    );

    expect(evidence, isEmpty);
  });

  test(
    'project-linked acceptance attributes verifier evidence to criteria',
    () {
      final now = DateTime(2026, 1, 1);
      const linked = AcceptanceItem(
        ref: 'tests-pass',
        statement: 'The focused tests pass.',
        criterionIds: ['criterion_001'],
        verifiers: [
          AcceptanceVerifier(
            kind: AcceptanceVerifierKind.command,
            command: 'flutter test test/example_test.dart',
          ),
        ],
      );
      final task = TaskAggregate(
        id: 'task_linked',
        title: 'Linked task',
        objective: 'Produce linked proof.',
        acceptance: const [linked],
        createdAt: now,
        updatedAt: now,
      );
      final evidence = const ProjectEvidenceService().normalizeTaskResult(
        project: _project(),
        task: ProjectTaskNode.fromTask(task),
        result: TaskResult(
          taskId: task.id,
          status: TaskStatus.completed,
          summary: 'Done.',
          memoryUpdate: '',
          artifacts: const [],
          gateResults: [
            TaskGateResult(
              gateId: 'command_passes',
              status: TaskGateStatus.passed,
              summary: 'The command passed.',
              details: {
                'acceptance_ref': 'tests-pass',
                'verifier_index': 0,
                'required': true,
                'command': 'flutter test test/example_test.dart',
              },
              evaluatedAt: now,
            ),
          ],
          toolCallCount: 1,
        ),
        evaluatedAt: now,
      );

      expect(evidence.single.criterionIds, ['criterion_001']);
      expect(evidence.single.expectationIds, ['acceptance_tests-pass_0']);
      expect(evidence.single.type, ProjectEvidenceType.command);
    },
  );
}

TaskAggregate _task() {
  final now = DateTime(2026, 1, 1);
  return TaskAggregate(
    id: 'task_acceptance',
    title: 'Acceptance task',
    objective: 'Implement the bounded acceptance example.',
    createdAt: now,
    updatedAt: now,
  );
}

ProjectAggregate _project() {
  final now = DateTime(2026, 1, 1);
  return ProjectAggregate(
    id: 'project_acceptance',
    title: 'Acceptance project',
    originalGoal: 'Deliver the acceptance example.',
    refinedGoal: 'Deliver the acceptance example safely.',
    constraints: const [],
    criteria: [
      ProjectCriterion(
        id: 'criterion_001',
        statement: 'The acceptance example is complete.',
        createdAt: now,
        updatedAt: now,
        verifiedAt: null,
      ),
    ],
    status: ProjectStatus.active,
    activeTaskId: null,
    createdAt: now,
    updatedAt: now,
  );
}
