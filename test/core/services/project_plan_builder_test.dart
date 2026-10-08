import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/contracts/acceptance.dart';
import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/features/task/domain/task.dart';
import 'package:hermes/features/project/runtime/project_plan_builder.dart';
import 'package:hermes/features/project/runtime/project_plan_patch.dart';
import 'package:hermes/features/project/runtime/project_plan_revision_service.dart';

void main() {
  test(
    'creates a complete plan with generated IDs and check metadata',
    () async {
      final builder = ProjectPlanBuilder(
        project: _project(),
        now: DateTime(2026, 1, 2),
        approvalReason: '',
      );
      final criterionId = builder.addCriterion(
        ref: 'quality',
        statement: 'The bounded implementation is verified.',
      );
      final taskId = builder.addTask(
        const ProjectTaskSpec(
          ref: 'implementation',
          title: 'Implement the bounded slice',
          objective: 'Implement one bounded slice of the outcome.',
          acceptance: [
            AcceptanceItem(
              ref: 'quality-proof',
              statement: 'The slice is implemented and checked.',
              criterionIds: ['quality'],
              verifiers: [
                AcceptanceVerifier(kind: AcceptanceVerifierKind.review),
              ],
            ),
          ],
          outOfScope: ['Unrelated project work.'],
        ),
      );
      final noteId = builder.addNote(
        kind: ProjectMemoryKind.assumption,
        content: 'The existing test command remains the project check.',
      );

      expect(criterionId, startsWith('criterion_'));
      expect(taskId, startsWith('task_'));
      expect(builder.taskIdFor('implementation'), taskId);
      expect(noteId, startsWith('memory_'));

      final committed = await builder.commit(
        workspaceRoot: '/workspace',
        approvalPolicy: ProjectPlanApprovalPolicy.never,
      );

      expect(committed.validation.valid, isTrue);
      expect(committed.patch.revision, committed.proposal.revision);
      expect(
        committed.patch.source,
        ProjectPlanPatchSource.incrementalRevision,
      );
      expect(committed.patch.plan.tasks, hasLength(1));
      final task = committed.project.taskById(taskId)!;
      expect(task.acceptance.single.verifiers.single.kind, AcceptanceVerifierKind.review);
      expect(committed.project.memory.any((item) => item.id == noteId), isTrue);
    },
  );

  test('links dependencies and applies an explicit deferral', () async {
    final builder = ProjectPlanBuilder(project: _project());
    final firstId = builder.addTask(
      const ProjectTaskSpec(
        ref: 'first',
        title: 'First bounded slice',
        objective: 'Implement the first bounded slice.',
        acceptance: [
          AcceptanceItem(
            ref: 'first-proof',
            statement: 'The first slice is checked.',
            criterionIds: ['criterion_001'],
            verifiers: [
              AcceptanceVerifier(kind: AcceptanceVerifierKind.review),
            ],
          ),
        ],
        outOfScope: ['The second slice.'],
      ),
    );
    final secondId = builder.addTask(
      const ProjectTaskSpec(
        ref: 'second',
        title: 'Second bounded slice',
        objective: 'Implement the second bounded slice.',
        acceptance: [
          AcceptanceItem(
            ref: 'second-proof',
            statement: 'The second slice is checked.',
            criterionIds: ['criterion_001'],
            verifiers: [
              AcceptanceVerifier(kind: AcceptanceVerifierKind.review),
            ],
          ),
        ],
        outOfScope: ['The first slice.'],
      ),
    );
    builder.setDependency(
      taskReference: 'second',
      dependencyReference: 'first',
    );
    builder.setDisposition(
      taskReference: 'second',
      disposition: ProjectPlanTaskDisposition.deferred,
    );

    final committed = await builder.commit(
      workspaceRoot: '/workspace',
      approvalPolicy: ProjectPlanApprovalPolicy.never,
    );

    expect(committed.validation.valid, isTrue);
    expect(committed.project.taskById(secondId)?.dependsOnTaskIds, [firstId]);
    expect(committed.project.taskById(secondId)?.status, TaskStatus.deferred);
  });

  test('keeps acceptance as the sole verification authoring source', () async {
    final source = _task('checked');
    final builder = ProjectPlanBuilder(project: _project(tasks: [source]));

    builder.updateTask(
      'checked',
      constraints: ['Keep verification within the task boundary.'],
    );
    builder.updateTask(
      'checked',
      acceptance: const [
        AcceptanceItem(
          ref: 'checked-proof',
          statement: 'The bounded slice is checked.',
          criterionIds: ['criterion_001'],
          verifiers: [
            AcceptanceVerifier(
              kind: AcceptanceVerifierKind.command,
              command: 'dart test',
              required: true,
            ),
          ],
        ),
      ],
    );
    final committed = await builder.commit(
      workspaceRoot: '/workspace',
      approvalPolicy: ProjectPlanApprovalPolicy.never,
    );

    final task = committed.project.taskById('checked')!;
    expect(committed.result.changed, isTrue);
    expect(task.acceptance.single.verifiers.single.required, isTrue);
    expect(task.constraints, ['Keep verification within the task boundary.']);
  });

  test('command idempotency includes artifact metadata', () {
    final builder = ProjectPlanBuilder(project: _project());
    final spec = const ProjectTaskSpec(
      ref: 'artifact_task',
      title: 'Produce output',
      objective: 'Produce the bounded output.',
      acceptance: const [
        AcceptanceItem(
          ref: 'output-proof',
          statement: 'The output is produced.',
          criterionIds: ['criterion_001'],
          verifiers: [
            AcceptanceVerifier(
              kind: AcceptanceVerifierKind.artifact,
              path: 'output',
              artifactKind: 'file',
            ),
          ],
        ),
      ],
      outOfScope: ['Unrelated work.'],
    );
    builder.addTask(spec, commandId: 'add-artifact-task');

    expect(
      () => builder.addTask(
        const ProjectTaskSpec(
          ref: 'artifact_task',
          title: 'Produce output',
          objective: 'Produce the bounded output.',
          acceptance: const [
            AcceptanceItem(
              ref: 'output-proof',
              statement: 'The output is produced.',
              criterionIds: ['criterion_001'],
              verifiers: [
                AcceptanceVerifier(
                  kind: AcceptanceVerifierKind.artifact,
                  path: 'output',
                  artifactKind: 'directory',
                ),
              ],
            ),
          ],
          outOfScope: ['Unrelated work.'],
        ),
        commandId: 'add-artifact-task',
      ),
      throwsA(
        isA<ProjectPlanBuilderException>().having(
          (error) => error.code,
          'code',
          'duplicate_command',
        ),
      ),
    );
  });

  test('rejects duplicate references without partially changing the draft', () {
    final builder = ProjectPlanBuilder(project: _project());
    final spec = const ProjectTaskSpec(
      ref: 'same',
      title: 'A bounded slice',
      objective: 'Implement a bounded slice.',
      acceptance: const [
        AcceptanceItem(
          ref: 'same-proof',
          statement: 'The slice is checked.',
          criterionIds: ['criterion_001'],
          verifiers: [AcceptanceVerifier(kind: AcceptanceVerifierKind.review)],
        ),
      ],
      outOfScope: ['Unrelated work.'],
    );
    builder.addTask(spec);

    expect(
      () => builder.addTask(spec),
      throwsA(
        isA<ProjectPlanBuilderException>().having(
          (error) => error.code,
          'code',
          'duplicate_reference',
        ),
      ),
    );
    expect(builder.taskIdFor('same'), isNotEmpty);

    expect(
      () => builder.addTasks([
        const ProjectTaskSpec(
          ref: 'valid_batch_item',
          title: 'Another bounded slice',
          objective: 'Implement another bounded slice.',
          acceptance: const [
            AcceptanceItem(
              ref: 'other-proof',
              statement: 'The other slice is checked.',
              criterionIds: ['criterion_001'],
              verifiers: [
                AcceptanceVerifier(kind: AcceptanceVerifierKind.review),
              ],
            ),
          ],
          outOfScope: ['Unrelated work.'],
        ),
        const ProjectTaskSpec(
          ref: 'invalid_batch_item',
          title: 'Invalid bounded slice',
          objective: 'Implement an invalid bounded slice.',
          acceptance: const [
            AcceptanceItem(
              ref: 'invalid-proof',
              statement: 'The invalid slice is checked.',
              criterionIds: ['missing_criterion'],
              verifiers: [
                AcceptanceVerifier(kind: AcceptanceVerifierKind.review),
              ],
            ),
          ],
          outOfScope: ['Unrelated work.'],
        ),
      ]),
      throwsA(isA<ProjectPlanBuilderException>()),
    );
    expect(
      () => builder.taskIdFor('valid_batch_item'),
      throwsA(isA<ProjectPlanBuilderException>()),
    );
  });

  test('retries the same command without creating another task', () {
    final builder = ProjectPlanBuilder(project: _project());
    const spec = ProjectTaskSpec(
      ref: 'idempotent',
      title: 'An idempotent slice',
      objective: 'Implement an idempotent bounded slice.',
      acceptance: const [
        AcceptanceItem(
          ref: 'idempotent-proof',
          statement: 'The idempotent slice is checked.',
          criterionIds: ['criterion_001'],
          verifiers: [AcceptanceVerifier(kind: AcceptanceVerifierKind.review)],
        ),
      ],
      outOfScope: ['Unrelated work.'],
    );

    final firstId = builder.addTask(spec, commandId: 'command-1');
    final retryId = builder.addTask(spec, commandId: 'command-1');

    expect(retryId, firstId);
    expect(
      () => builder.addTask(
        const ProjectTaskSpec(
          ref: 'idempotent',
          title: 'A changed slice',
          objective: 'Implement a changed bounded slice.',
          acceptance: const [
            AcceptanceItem(
              ref: 'idempotent-proof',
              statement: 'The changed slice is checked.',
              criterionIds: ['criterion_001'],
              verifiers: [
                AcceptanceVerifier(kind: AcceptanceVerifierKind.review),
              ],
            ),
          ],
          outOfScope: ['Unrelated work.'],
        ),
        commandId: 'command-1',
      ),
      throwsA(
        isA<ProjectPlanBuilderException>().having(
          (error) => error.code,
          'code',
          'duplicate_command',
        ),
      ),
    );
  });

  test('keeps generated task IDs unique across repeated command sequences', () {
    final builder = ProjectPlanBuilder(project: _project());
    final ids = <String>{};
    for (var index = 0; index < 3; index++) {
      ids.add(
        builder.addTask(
          ProjectTaskSpec(
            ref: 'sequence_$index',
            title: 'Generated task $index',
            objective: 'Implement generated slice $index.',
            acceptance: const [
              AcceptanceItem(
                ref: 'generated-proof',
                statement: 'The generated slice is checked.',
                criterionIds: ['criterion_001'],
                verifiers: [
                  AcceptanceVerifier(kind: AcceptanceVerifierKind.review),
                ],
              ),
            ],
            outOfScope: const ['Unrelated work.'],
          ),
        ),
      );
    }
    expect(ids, hasLength(3));
    expect(
      () => builder.addTask(
        const ProjectTaskSpec(
          ref: 'too_many',
          title: 'Too many tasks',
          objective: 'Exceed the bounded planning slice.',
          acceptance: const [
            AcceptanceItem(
              ref: 'too-many-proof',
              statement: 'The slice is checked.',
              criterionIds: ['criterion_001'],
              verifiers: [
                AcceptanceVerifier(kind: AcceptanceVerifierKind.review),
              ],
            ),
          ],
          outOfScope: ['Unrelated work.'],
        ),
      ),
      throwsA(
        isA<ProjectPlanBuilderException>().having(
          (error) => error.code,
          'code',
          'new_task_limit_exceeded',
        ),
      ),
    );
  });

  test('rejects a dead dependency before changing the draft', () {
    final failed = _task('failed').copyWith(status: TaskStatus.failed);
    final builder = ProjectPlanBuilder(
      project: _project(tasks: [failed, _task('live')]),
    );

    expect(
      () => builder.setDependency(
        taskReference: 'live',
        dependencyReference: 'failed',
      ),
      throwsA(
        isA<ProjectPlanBuilderException>().having(
          (error) => error.code,
          'code',
          'dead_dependency',
        ),
      ),
    );
    expect(builder.taskIdFor('live'), 'live');
  });

  test('cannot update terminal history and retries with a fresh ID', () async {
    final failed = _task('failed').copyWith(
      status: TaskStatus.failed,
      rejectionReason: 'The previous verification failed.',
    );
    final builder = ProjectPlanBuilder(project: _project(tasks: [failed]));

    expect(
      () => builder.updateTask('failed', title: 'Overwrite the failure'),
      throwsA(
        isA<ProjectPlanBuilderException>().having(
          (error) => error.code,
          'code',
          'terminal_task_immutable',
        ),
      ),
    );

    final retryId = builder.retryTask(taskReference: 'failed');
    expect(retryId, isNot('failed'));
    final committed = await builder.commit(
      workspaceRoot: '/workspace',
      approvalPolicy: ProjectPlanApprovalPolicy.never,
    );

    expect(committed.validation.valid, isTrue);
    expect(committed.project.taskById('failed')?.id, failed.id);
    expect(committed.project.taskById('failed')?.status, TaskStatus.failed);
    expect(committed.project.taskById(retryId)?.status, TaskStatus.queued);
    expect(
      committed.project.taskById(retryId)?.context,
      contains('Previous rejection: The previous verification failed.'),
    );
  });

  test(
    'splits a task into fresh children and preserves the parent history',
    () async {
      final parent = _task('parent');
      final builder = ProjectPlanBuilder(project: _project(tasks: [parent]));
      final childIds = builder.splitTask(
        taskReference: 'parent',
        children: const [
          ProjectTaskSpec(
            ref: 'child_one',
            title: 'First child',
            objective: 'Implement the first child slice.',
          ),
          ProjectTaskSpec(
            ref: 'child_two',
            title: 'Second child',
            objective: 'Implement the second child slice.',
          ),
        ],
      );

      final committed = await builder.commit(
        workspaceRoot: '/workspace',
        approvalPolicy: ProjectPlanApprovalPolicy.never,
      );

      expect(committed.validation.valid, isTrue);
      expect(childIds, hasLength(2));
      expect(childIds.toSet(), hasLength(2));
      expect(committed.project.taskById('parent')?.status, TaskStatus.split);
      expect(
        committed.project.taskById(childIds[0])?.status,
        TaskStatus.queued,
      );
      expect(
        committed.project.taskById(childIds[1])?.status,
        TaskStatus.queued,
      );
    },
  );

  test('splitting a deterministic task requires atomic child checks', () async {
    final base = _project();
    final project = base.copyWith(
      criteria: [
        base.criteria.single.copyWith(
          verificationMode: ProjectVerificationMode.deterministic,
        ),
      ],
    );
    final parent = _task('parent').copyWith(
      acceptance: const [
        AcceptanceItem(
          ref: 'parent-command-proof',
          statement: 'The deterministic slice is checked.',
          criterionIds: ['criterion_001'],
          verifiers: [
            AcceptanceVerifier(
              kind: AcceptanceVerifierKind.command,
              command: 'dart test',
            ),
          ],
        ),
      ],
    );
    final builder = ProjectPlanBuilder(
      project: project.copyWith(tasks: [ProjectTaskNode.fromTask(parent)]),
    );

    final childIds = builder.splitTask(
      taskReference: 'parent',
      children: const [
        ProjectTaskSpec(
          ref: 'child_one',
          title: 'First child',
          objective: 'Implement the first child slice.',
          acceptance: [
            AcceptanceItem(
              ref: 'child-command-proof',
              statement: 'The child command passes.',
              criterionIds: ['criterion_001'],
              verifiers: [
                AcceptanceVerifier(
                  kind: AcceptanceVerifierKind.command,
                  command: 'dart test',
                ),
              ],
            ),
          ],
        ),
        ProjectTaskSpec(
          ref: 'child_two',
          title: 'Second child',
          objective: 'Implement the second child slice.',
        ),
      ],
    );
    final committed = await builder.commit(
      workspaceRoot: '/workspace',
      approvalPolicy: ProjectPlanApprovalPolicy.never,
    );

    expect(committed.validation.valid, isTrue);
    expect(committed.project.taskById('parent')?.status, TaskStatus.split);
    final checkedChild = committed.project.taskById(childIds.first)!;
    expect(checkedChild.acceptance.single.verifiers.single.required, isTrue);
    expect(
      checkedChild.acceptance.single.verifiers.single.command,
      'dart test',
    );
    expect(
      checkedChild.acceptance.any(
        (item) => item.verifiers.any(
          (verifier) =>
              verifier.kind == AcceptanceVerifierKind.command &&
              verifier.required,
        ),
      ),
      isTrue,
    );
  });

  test('rewires dependents to wait for every split child', () async {
    final parent = _task('parent');
    final dependent = _task('dependent').copyWith(dependsOnTaskIds: ['parent']);
    final builder = ProjectPlanBuilder(
      project: _project(tasks: [parent, dependent]),
    );
    final childIds = builder.splitTask(
      taskReference: 'parent',
      children: const [
        ProjectTaskSpec(
          ref: 'child_one',
          title: 'First child',
          objective: 'Implement the first child slice.',
        ),
        ProjectTaskSpec(
          ref: 'child_two',
          title: 'Second child',
          objective: 'Implement the second child slice.',
        ),
      ],
    );

    final committed = await builder.commit(
      workspaceRoot: '/workspace',
      approvalPolicy: ProjectPlanApprovalPolicy.never,
    );

    expect(committed.validation.valid, isTrue);
    expect(committed.project.taskById('dependent')?.dependsOnTaskIds, childIds);
  });

  test(
    'preserves split metadata while a revision waits for approval',
    () async {
      final parent = _task('parent');
      final builder = ProjectPlanBuilder(project: _project(tasks: [parent]));
      builder.splitTask(
        taskReference: 'parent',
        children: const [
          ProjectTaskSpec(
            ref: 'child',
            title: 'Bounded child',
            objective: 'Implement the bounded child slice.',
          ),
          ProjectTaskSpec(
            ref: 'verify',
            title: 'Verify bounded child',
            objective: 'Verify the bounded child slice.',
          ),
        ],
      );

      final pending = await builder.commit(
        workspaceRoot: '/workspace',
        approvalPolicy: ProjectPlanApprovalPolicy.everyRevision,
      );

      expect(pending.result.awaitingApproval, isTrue);
      expect(pending.proposal.splitTaskIds, ['parent']);
      final approved = const ProjectPlanRevisionService().approvePending(
        project: pending.project,
        workspaceRoot: '/workspace',
      );
      expect(approved.project.taskById('parent')?.status, TaskStatus.split);
      expect(approved.project.tasks, hasLength(3));
      expect(
        approved.project.tasks.any((task) => task.title == 'Bounded child'),
        isTrue,
      );
    },
  );
}

ProjectAggregate _project({List<TaskAggregate> tasks = const []}) {
  final now = DateTime(2026, 1, 1);
  return ProjectAggregate(
    id: 'project_1',
    title: 'Project',
    originalGoal: 'Deliver a bounded outcome',
    refinedGoal: 'Deliver a bounded outcome',
    criteria: [
      ProjectCriterion(
        id: 'criterion_001',
        statement: 'The bounded outcome is verified.',
        createdAt: now,
        updatedAt: now,
        verifiedAt: null,
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

TaskAggregate _task(String id) {
  final now = DateTime(2026, 1, 1);
  final objective = 'Implement bounded slice $id.';
  return TaskAggregate(
    id: id,
    title: 'Bounded slice $id',
    objective: objective,
    acceptance: const [
      AcceptanceItem(
        ref: 'task-proof',
        statement: 'The bounded slice is independently checked.',
        criterionIds: ['criterion_001'],
        verifiers: [AcceptanceVerifier(kind: AcceptanceVerifierKind.review)],
      ),
    ],
    outOfScope: const ['Unrelated project work.'],
    status: TaskStatus.queued,
    fingerprint: projectTaskFingerprint(objective, const ['criterion_001']),
    createdAt: now,
    updatedAt: now,
  );
}
