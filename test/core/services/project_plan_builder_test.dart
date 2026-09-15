import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/services/project_system/project_plan_builder.dart';
import 'package:hermes/core/services/project_system/project_plan_revision_service.dart';

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
        const ProjectPlanTaskSpec(
          ref: 'implementation',
          title: 'Implement the bounded slice',
          objective: 'Implement one bounded slice of the outcome.',
          criterionRefs: ['quality'],
          doneCriteria: ['The slice is implemented and checked.'],
          outOfScope: ['Unrelated project work.'],
        ),
      );
      final expectationId = builder.addCommandCheck(
        taskReference: 'implementation',
        command: 'dart test',
        criterionRefs: ['quality'],
      );
      final noteId = builder.addNote(
        kind: ProjectMemoryKind.assumption,
        content: 'The existing test command remains the project check.',
      );

      expect(criterionId, startsWith('criterion_'));
      expect(taskId, startsWith('task_'));
      expect(builder.taskIdFor('implementation'), taskId);
      expect(expectationId, startsWith('expect_'));
      expect(noteId, startsWith('memory_'));

      final committed = await builder.commit(
        workspaceRoot: '/workspace',
        approvalPolicy: ProjectPlanApprovalPolicy.never,
      );

      expect(committed.validation.valid, isTrue);
      final task = committed.project.taskById(taskId)!;
      expect(task.gates.single.id, 'command_passes');
      expect(task.gates.single.params['command'], 'dart test');
      expect(
        task.expectedEvidence.any((item) => item.id == expectationId),
        isTrue,
      );
      expect(committed.project.memory.any((item) => item.id == noteId), isTrue);
    },
  );

  test('links dependencies and applies an explicit deferral', () async {
    final builder = ProjectPlanBuilder(project: _project());
    final firstId = builder.addTask(
      const ProjectPlanTaskSpec(
        ref: 'first',
        title: 'First bounded slice',
        objective: 'Implement the first bounded slice.',
        criterionRefs: ['criterion_001'],
        doneCriteria: ['The first slice is checked.'],
        outOfScope: ['The second slice.'],
      ),
    );
    final secondId = builder.addTask(
      const ProjectPlanTaskSpec(
        ref: 'second',
        title: 'Second bounded slice',
        objective: 'Implement the second bounded slice.',
        criterionRefs: ['criterion_001'],
        doneCriteria: ['The second slice is checked.'],
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

  test('repairs an existing command expectation and gate together', () async {
    final source = _task('checked').copyWith(
      gates: [
        const TaskGate(
          id: 'command_passes',
          required: false,
          scope: 'task',
          params: {'command': 'dart test', 'working_directory': '.'},
        ),
      ],
      expectedEvidence: [
        const TaskEvidenceExpectation(
          id: 'expect_checked_command',
          type: ProjectEvidenceType.command,
          criterionIds: ['criterion_001'],
          description: 'The bounded slice is checked.',
          required: false,
          sourceRef: 'dart test',
          details: {'working_directory': '.'},
        ),
      ],
    );
    final builder = ProjectPlanBuilder(project: _project(tasks: [source]));

    builder.updateTask(
      'checked',
      constraints: ['Keep verification within the task boundary.'],
    );
    final expectationId = builder.addCommandCheck(
      taskReference: 'checked',
      command: 'dart test',
      required: true,
    );
    final committed = await builder.commit(
      workspaceRoot: '/workspace',
      approvalPolicy: ProjectPlanApprovalPolicy.never,
    );

    final task = committed.project.taskById('checked')!;
    expect(expectationId, 'expect_checked_command');
    expect(committed.result.changed, isTrue);
    expect(task.gates.single.required, isTrue);
    expect(task.expectedEvidence.single.required, isTrue);
    expect(task.constraints, ['Keep verification within the task boundary.']);
  });

  test('command idempotency includes artifact metadata', () {
    final builder = ProjectPlanBuilder(project: _project());
    final spec = const ProjectPlanTaskSpec(
      ref: 'artifact_task',
      title: 'Produce output',
      objective: 'Produce the bounded output.',
      criterionRefs: ['criterion_001'],
      doneCriteria: ['The output is produced.'],
      outOfScope: ['Unrelated work.'],
      expectedArtifacts: [TaskArtifact(path: 'output', kind: 'file')],
    );
    builder.addTask(spec, commandId: 'add-artifact-task');

    expect(
      () => builder.addTask(
        const ProjectPlanTaskSpec(
          ref: 'artifact_task',
          title: 'Produce output',
          objective: 'Produce the bounded output.',
          criterionRefs: ['criterion_001'],
          doneCriteria: ['The output is produced.'],
          outOfScope: ['Unrelated work.'],
          expectedArtifacts: [TaskArtifact(path: 'output', kind: 'directory')],
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
    final spec = const ProjectPlanTaskSpec(
      ref: 'same',
      title: 'A bounded slice',
      objective: 'Implement a bounded slice.',
      criterionRefs: ['criterion_001'],
      doneCriteria: ['The slice is checked.'],
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
        const ProjectPlanTaskSpec(
          ref: 'valid_batch_item',
          title: 'Another bounded slice',
          objective: 'Implement another bounded slice.',
          criterionRefs: ['criterion_001'],
          doneCriteria: ['The other slice is checked.'],
          outOfScope: ['Unrelated work.'],
        ),
        const ProjectPlanTaskSpec(
          ref: 'invalid_batch_item',
          title: 'Invalid bounded slice',
          objective: 'Implement an invalid bounded slice.',
          criterionRefs: ['missing_criterion'],
          doneCriteria: ['The invalid slice is checked.'],
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
    const spec = ProjectPlanTaskSpec(
      ref: 'idempotent',
      title: 'An idempotent slice',
      objective: 'Implement an idempotent bounded slice.',
      criterionRefs: ['criterion_001'],
      doneCriteria: ['The idempotent slice is checked.'],
      outOfScope: ['Unrelated work.'],
    );

    final firstId = builder.addTask(spec, commandId: 'command-1');
    final retryId = builder.addTask(spec, commandId: 'command-1');

    expect(retryId, firstId);
    expect(
      () => builder.addTask(
        const ProjectPlanTaskSpec(
          ref: 'idempotent',
          title: 'A changed slice',
          objective: 'Implement a changed bounded slice.',
          criterionRefs: ['criterion_001'],
          doneCriteria: ['The changed slice is checked.'],
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
    for (var sequence = 0; sequence < 5; sequence++) {
      for (var index = 0; index < 50; index++) {
        ids.add(
          builder.addTask(
            ProjectPlanTaskSpec(
              ref: 'sequence_${sequence}_$index',
              title: 'Generated task $sequence-$index',
              objective: 'Implement generated slice $sequence-$index.',
              criterionRefs: const ['criterion_001'],
              doneCriteria: const ['The generated slice is checked.'],
              outOfScope: const ['Unrelated work.'],
            ),
          ),
        );
      }
    }
    expect(ids, hasLength(250));
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
    expect(committed.project.taskById('failed'), same(failed));
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
          ProjectPlanTaskSpec(
            ref: 'child_one',
            title: 'First child',
            objective: 'Implement the first child slice.',
          ),
          ProjectPlanTaskSpec(
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

  test('rewires dependents to wait for every split child', () async {
    final parent = _task('parent');
    final dependent = _task('dependent').copyWith(dependsOnTaskIds: ['parent']);
    final builder = ProjectPlanBuilder(
      project: _project(tasks: [parent, dependent]),
    );
    final childIds = builder.splitTask(
      taskReference: 'parent',
      children: const [
        ProjectPlanTaskSpec(
          ref: 'child_one',
          title: 'First child',
          objective: 'Implement the first child slice.',
        ),
        ProjectPlanTaskSpec(
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
          ProjectPlanTaskSpec(
            ref: 'child',
            title: 'Bounded child',
            objective: 'Implement the bounded child slice.',
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
      expect(approved.project.tasks, hasLength(2));
      expect(
        approved.project.tasks.any((task) => task.title == 'Bounded child'),
        isTrue,
      );
    },
  );
}

ProjectState _project({List<Task> tasks = const []}) {
  final now = DateTime(2026, 1, 1);
  return ProjectState(
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
    tasks: tasks,
    status: ProjectStatus.active,
    activeTaskId: null,
    createdAt: now,
    updatedAt: now,
  );
}

Task _task(String id) {
  final now = DateTime(2026, 1, 1);
  final objective = 'Implement bounded slice $id.';
  return Task(
    id: id,
    title: 'Bounded slice $id',
    objective: objective,
    criterionIds: const ['criterion_001'],
    expectedEvidence: [
      TaskEvidenceExpectation(
        id: 'expect_$id',
        criterionIds: const ['criterion_001'],
        description: 'The bounded slice is independently checked.',
      ),
    ],
    doneCriteria: const ['The bounded slice is implemented and checked.'],
    outOfScope: const ['Unrelated project work.'],
    status: TaskStatus.queued,
    fingerprint: projectTaskFingerprint(objective, const ['criterion_001']),
    createdAt: now,
    updatedAt: now,
  );
}
