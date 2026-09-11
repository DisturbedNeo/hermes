import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/services/project_system/project_plan_validator.dart';

void main() {
  const validator = ProjectPlanValidator(planningHorizon: 2);

  test('accepts a complete bounded desired plan', () {
    final project = _project();
    final validation = validator.validate(
      project: project,
      proposal: _desired(project, [_task('task_new')]),
      workspaceRoot: '/workspace',
    );

    expect(validation.valid, isTrue);
    expect(validation.issues, isEmpty);
  });

  test('rejects an incomplete planner response', () {
    final project = _projectWithTasks([_task('existing')]);
    final validation = validator.validate(
      project: project,
      proposal: _desired(project, const [], hasCompleteCollections: false),
      workspaceRoot: '/workspace',
    );

    expect(validation.valid, isFalse);
    expect(
      validation.errors.map((issue) => issue.code),
      contains('incomplete_plan'),
    );
  });

  test('rejects dependency cycles and invalid paths before reconciliation', () {
    final project = _project();
    final invalid = _task(
      'task_invalid',
      dependencies: const ['task_invalid', 'missing'],
      writePaths: const ['../outside.txt'],
    );
    final validation = validator.validate(
      project: project,
      proposal: _desired(project, [invalid]),
      workspaceRoot: '/workspace',
    );

    expect(validation.valid, isFalse);
    expect(
      validation.errors.map((issue) => issue.code),
      containsAll([
        'self_dependency',
        'missing_dependency',
        'cyclic_dependencies',
        'path_outside_workspace',
      ]),
    );
  });

  test('requires approval before removing a required criterion', () {
    final project = _project();
    final desired = _desired(project, const [], includeCriteria: false);
    final validation = validator.validate(
      project: project,
      proposal: desired,
      workspaceRoot: '/workspace',
    );

    expect(validation.valid, isFalse);
    expect(
      validation.errors.map((issue) => issue.code),
      contains('required_criterion_removal'),
    );
  });

  test('rejects malformed memory additions and supersessions', () {
    final project = _project(
      memory: [
        _memory('memory_active'),
        _memory('memory_inactive', active: false),
        _memory('memory_protected', protected: true),
        _memory('memory_replacement'),
      ],
    );
    final invalid = _desired(
      project,
      const [],
      memoryAdditions: [
        ProjectMemoryEntry(
          id: 'memory_active',
          kind: ProjectMemoryKind.fact,
          content: '',
          sourceType: ProjectMemorySourceType.planner,
          confidence: ProjectMemoryConfidence.inferred,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 1),
        ),
      ],
      memorySupersessions: const [
        ProjectMemorySupersession(
          entryId: 'memory_inactive',
          supersededById: 'missing_replacement',
        ),
        ProjectMemorySupersession(
          entryId: 'memory_protected',
          supersededById: 'memory_replacement',
        ),
        ProjectMemorySupersession(
          entryId: 'memory_active',
          supersededById: 'memory_active',
        ),
      ],
    );

    final validation = validator.validate(
      project: project,
      proposal: invalid,
      workspaceRoot: '/workspace',
    );

    expect(validation.valid, isFalse);
    expect(
      validation.errors.map((issue) => issue.code),
      containsAll([
        'empty_memory_addition',
        'memory_id_collision',
        'inactive_memory_source',
        'missing_memory_replacement',
        'protected_memory_source',
        'self_memory_supersession',
      ]),
    );
  });

  test('accepts a valid planner memory supersession', () {
    final project = _project(
      memory: [_memory('memory_active'), _memory('memory_replacement')],
    );
    final validation = validator.validate(
      project: project,
      proposal: _desired(
        project,
        const [],
        memorySupersessions: const [
          ProjectMemorySupersession(
            entryId: 'memory_active',
            supersededById: 'memory_replacement',
          ),
        ],
      ),
      workspaceRoot: '/workspace',
    );

    expect(validation.valid, isTrue);
  });

  test('rejects duplicate desired work and desired-vs-existing work', () {
    final project = _project();
    final first = _task('first');
    final duplicateDesired = _task('second').copyWith(
      fingerprint: first.fingerprint,
      expectedEvidence: const [
        TaskEvidenceExpectation(
          id: 'expect_second',
          type: ProjectEvidenceType.taskClaim,
          criterionIds: ['criterion_001'],
          description: 'The second task is checked.',
        ),
      ],
    );
    final desiredValidation = validator.validate(
      project: project,
      proposal: _desired(project, [first, duplicateDesired]),
      workspaceRoot: '/workspace',
    );
    expect(
      desiredValidation.errors.map((issue) => issue.code),
      contains('duplicate_work'),
    );

    final existing = _task('existing');
    final existingValidation = validator.validate(
      project: _projectWithTasks([existing]),
      proposal: _desired(_projectWithTasks([existing]), [
        _task('replacement').copyWith(
          fingerprint: existing.fingerprint,
          expectedEvidence: const [
            TaskEvidenceExpectation(
              id: 'expect_replacement',
              type: ProjectEvidenceType.taskClaim,
              criterionIds: ['criterion_001'],
              description: 'The replacement is checked.',
            ),
          ],
        ),
      ]),
      workspaceRoot: '/workspace',
    );
    expect(
      existingValidation.errors.map((issue) => issue.code),
      contains('duplicate_work'),
    );
  });

  test('rejects ambiguous evidence expectations', () {
    final project = _project();
    final task = _task(
      'ambiguous',
      expectedEvidence: const [
        TaskEvidenceExpectation(
          id: 'expect_a',
          type: ProjectEvidenceType.artifact,
          criterionIds: ['criterion_001'],
          description: 'The report exists.',
          sourceRef: 'report.md',
        ),
        TaskEvidenceExpectation(
          id: 'expect_b',
          type: ProjectEvidenceType.artifact,
          criterionIds: ['criterion_001'],
          description: 'The report is present.',
          sourceRef: 'report.md',
        ),
      ],
    );
    final validation = validator.validate(
      project: project,
      proposal: _desired(project, [task]),
      workspaceRoot: '/workspace',
    );

    expect(
      validation.errors.map((issue) => issue.code),
      contains('ambiguous_evidence_expectation'),
    );
  });

  test('rejects dependencies on omitted tasks', () {
    final project = _projectWithTasks([_task('unfinished')]);
    final validation = validator.validate(
      project: project,
      proposal: _desired(project, [
        _task('dependent', dependencies: const ['unfinished']),
      ]),
      workspaceRoot: '/workspace',
    );

    expect(
      validation.errors.map((issue) => issue.code),
      contains('dead_dependency'),
    );
  });

  test('rejects unknown and conflicting task dispositions', () {
    final project = _projectWithTasks([_task('existing')]);
    final validation = validator.validate(
      project: project,
      proposal: _desired(
        project,
        [_task('existing')],
        deferredTaskIds: const ['existing', 'missing'],
        obsoleteTaskIds: const ['existing'],
      ),
      workspaceRoot: '/workspace',
    );

    expect(
      validation.errors.map((issue) => issue.code),
      containsAll(['unknown_task_disposition', 'conflicting_task_disposition']),
    );
  });

  test('rejects deterministic criteria with artifact-only verification', () {
    final base = _project();
    final project = base.copyWith(
      criteria: [
        base.criteria.single.copyWith(
          verificationMode: ProjectVerificationMode.deterministic,
        ),
      ],
    );
    final task = _task(
      'artifact_only',
      expectedEvidence: const [],
      expectedArtifacts: [
        TaskArtifact(
          id: 'artifact_expected',
          path: 'lib/feature.dart',
          description: 'The implementation file.',
          kind: 'file',
          createdAt: DateTime(2026, 1, 2),
        ),
      ],
    );
    final validation = validator.validate(
      project: project,
      proposal: _desired(project, [task]),
      workspaceRoot: '/workspace',
    );

    expect(
      validation.errors.map((issue) => issue.code),
      contains('impossible_deterministic_verification'),
    );
  });

  test(
    'requires a matching command_passes gate for required command evidence',
    () {
      final project = _project();
      const expectation = TaskEvidenceExpectation(
        id: 'expect_command',
        type: ProjectEvidenceType.command,
        criterionIds: ['criterion_001'],
        description: 'The focused tests pass.',
        required: true,
        sourceRef: 'dart test test/feature_test.dart',
        details: {'working_directory': '.'},
      );
      final withoutGate = _task(
        'command_without_gate',
      ).copyWith(expectedEvidence: const [expectation]);
      final invalid = validator.validate(
        project: project,
        proposal: _desired(project, [withoutGate]),
        workspaceRoot: '/workspace',
      );

      expect(
        invalid.errors.map((issue) => issue.code),
        contains('missing_command_passes_gate'),
      );

      final withGate = withoutGate.copyWith(
        gates: const [
          TaskGate(
            id: 'command_passes',
            required: true,
            scope: 'task',
            params: {
              'command': 'dart test test/feature_test.dart',
              'working_directory': '.',
            },
          ),
        ],
      );
      final valid = validator.validate(
        project: project,
        proposal: _desired(project, [withGate]),
        workspaceRoot: '/workspace',
      );
      expect(
        valid.errors.map((issue) => issue.code),
        isNot(contains('missing_command_passes_gate')),
      );
    },
  );
}

ProjectState _project({List<ProjectMemoryEntry> memory = const []}) {
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
      ),
    ],
    constraints: const ['Stay in the workspace.'],
    tasks: const [],
    status: ProjectStatus.active,
    activeTaskId: null,
    memory: memory,
    createdAt: now,
    updatedAt: now,
  );
}

ProjectState _projectWithTasks(List<Task> tasks) {
  final project = _project();
  return project.copyWith(tasks: tasks);
}

ProjectDesiredPlan _desired(
  ProjectState project,
  List<Task> tasks, {
  bool includeCriteria = true,
  List<ProjectMemoryEntry> memoryAdditions = const [],
  List<ProjectMemorySupersession> memorySupersessions = const [],
  List<String> deferredTaskIds = const [],
  List<String> obsoleteTaskIds = const [],
  bool hasCompleteCollections = true,
}) {
  return ProjectDesiredPlan(
    revision: project.nextRevision,
    triggers: const [ProjectPlanRevisionTrigger.noReadyTask],
    summary: 'Revise the near-term plan.',
    rationale: 'A bounded revision is needed.',
    hasCompleteCollections: hasCompleteCollections,
    criteria: includeCriteria ? project.criteria : const [],
    milestones: project.milestones,
    tasks: tasks,
    deferredTaskIds: deferredTaskIds,
    obsoleteTaskIds: obsoleteTaskIds,
    memoryAdditions: memoryAdditions,
    memorySupersessions: memorySupersessions,
    createdAt: DateTime(2026, 1, 2),
  );
}

ProjectMemoryEntry _memory(
  String id, {
  bool active = true,
  bool protected = false,
}) {
  final now = DateTime(2026, 1, 1);
  return ProjectMemoryEntry(
    id: id,
    kind: ProjectMemoryKind.fact,
    content: 'Memory content for $id.',
    sourceType: ProjectMemorySourceType.planner,
    confidence: ProjectMemoryConfidence.inferred,
    active: active,
    protected: protected,
    createdAt: now,
    updatedAt: now,
  );
}

Task _task(
  String id, {
  List<String> dependencies = const [],
  List<String> writePaths = const ['lib/feature.dart'],
  List<TaskEvidenceExpectation>? expectedEvidence,
  List<TaskArtifact> expectedArtifacts = const [],
}) {
  final now = DateTime(2026, 1, 2);
  final objective = 'Implement bounded slice $id.';
  return Task(
    id: id,
    title: 'Bounded slice $id',
    objective: objective,
    criterionIds: const ['criterion_001'],
    dependsOnTaskIds: dependencies,
    expectedEvidence:
        expectedEvidence ??
        const [
          TaskEvidenceExpectation(
            id: 'expect_task',
            type: ProjectEvidenceType.taskClaim,
            criterionIds: ['criterion_001'],
            description: 'The done criteria are independently checked.',
          ),
        ],
    writePaths: writePaths,
    doneCriteria: const ['The bounded slice is implemented and checked.'],
    outOfScope: const ['Do not change unrelated project scope.'],
    context: const [],
    expectedArtifacts: expectedArtifacts,
    status: TaskStatus.queued,
    fingerprint: projectTaskFingerprint(objective, const ['criterion_001']),
    rejectionReason: null,
    createdAt: now,
    updatedAt: now,
  );
}
