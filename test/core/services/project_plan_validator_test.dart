import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/services/project_system/project_plan_validator.dart';

void main() {
  group('ProjectPlanValidator', () {
    const validator = ProjectPlanValidator(planningHorizon: 2);
    late ProjectState project;

    setUp(() {
      project = _project();
    });

    test('accepts a bounded task with stable references', () {
      final proposal = _proposal(project, [_task(id: 'task_new')]);

      final validation = validator.validate(
        project: project,
        proposal: proposal,
        workspaceRoot: '/workspace',
      );

      expect(validation.valid, isTrue);
      expect(validation.issues, isEmpty);
    });

    test('returns structured dependency, boundary, and path errors', () {
      final invalid = _task(
        id: 'task_invalid',
        dependsOnTaskIds: const ['task_invalid', 'missing'],
        doneCriteria: const [],
        outOfScope: const [],
        writePaths: const ['../outside.txt'],
      ).copyWith(expectedEvidence: const [], expectedArtifacts: const []);

      final validation = validator.validate(
        project: project,
        proposal: _proposal(project, [invalid]),
        workspaceRoot: '/workspace',
      );
      final byCode = {for (final issue in validation.errors) issue.code: issue};

      expect(validation.valid, isFalse);
      expect(
        byCode.keys,
        containsAll(<String>{
          'self_dependency',
          'missing_dependency',
          'missing_done_criteria',
          'missing_boundary',
          'missing_expected_verification',
          'path_outside_workspace',
        }),
      );
      expect(byCode['missing_dependency']!.path, contains('dependsOnTaskIds'));
    });

    test('rejects missing and inconsistent evidence criterion links', () {
      final unboundTask = _task(id: 'task_unbound').copyWith(
        criterionIds: const [],
        expectedEvidence: const [
          ProjectEvidenceExpectation(
            id: 'expect_unbound',
            type: ProjectEvidenceType.taskClaim,
            criterionIds: [],
            description: 'Verify the result.',
          ),
        ],
      );
      final unknownEvidenceTask = _task(id: 'task_unknown').copyWith(
        expectedEvidence: const [
          ProjectEvidenceExpectation(
            id: 'expect_unknown',
            type: ProjectEvidenceType.command,
            criterionIds: ['criterion_missing'],
            description: 'Run verification.',
          ),
        ],
      );

      final validation = validator.validate(
        project: project,
        proposal: _proposal(project, [unboundTask, unknownEvidenceTask]),
        workspaceRoot: '/workspace',
      );

      expect(
        validation.errors.map((item) => item.code),
        containsAll([
          'missing_criterion_link',
          'missing_evidence_criterion',
          'unknown_evidence_criterion',
        ]),
      );
    });

    test('requires queued tasks to release criteria removed by a revision', () {
      final queued = _task(id: 'task_existing');
      final withQueuedWork = project.copyWith(backlog: [queued]);
      final proposal = ProjectPlanProposal(
        revision: withQueuedWork.currentRevision + 1,
        triggers: const [ProjectPlanRevisionTrigger.manual],
        summary: 'Remove an outcome.',
        rationale: 'The outcome is no longer in scope.',
        removedCriterionIds: const ['criterion_001'],
        requiresApproval: true,
        createdAt: DateTime(2026, 1, 2),
      );

      final validation = validator.validate(
        project: withQueuedWork,
        proposal: proposal,
        workspaceRoot: '/workspace',
      );

      expect(
        validation.errors.map((item) => item.code),
        contains('removed_criterion_still_in_use'),
      );
    });

    test('rejects cycles and work equivalent to the whole project', () {
      final first = _task(id: 'task_a', dependsOnTaskIds: const ['task_b']);
      final second = _task(
        id: 'task_b',
        objective: 'Complete the entire project end-to-end',
        dependsOnTaskIds: const ['task_a'],
      );

      final validation = validator.validate(
        project: project,
        proposal: _proposal(project, [first, second]),
        workspaceRoot: '/workspace',
      );

      expect(
        validation.errors.map((item) => item.code),
        containsAll(['cyclic_dependencies', 'task_equals_project_goal']),
      );
    });

    test('rejects protected memory and required criterion mutation', () {
      final proposal = ProjectPlanProposal(
        revision: 2,
        triggers: const [ProjectPlanRevisionTrigger.newContext],
        summary: 'Unsafe scope edit',
        rationale: 'Attempt an unsafe edit.',
        removedCriterionIds: const ['criterion_001'],
        memoryAdditions: [
          ProjectMemoryEntry(
            id: 'memory_replacement',
            kind: ProjectMemoryKind.fact,
            content: 'Replacement',
            sourceType: ProjectMemorySourceType.planner,
            confidence: ProjectMemoryConfidence.inferred,
            createdAt: DateTime(2026, 1, 2),
            updatedAt: DateTime(2026, 1, 2),
          ),
        ],
        memorySupersessions: const [
          ProjectMemorySupersession(
            entryId: 'memory_user',
            supersededById: 'memory_replacement',
          ),
        ],
        createdAt: DateTime(2026, 1, 2),
      );

      final validation = validator.validate(
        project: project,
        proposal: proposal,
        workspaceRoot: '/workspace',
      );

      expect(
        validation.errors.map((item) => item.code),
        containsAll([
          'required_criterion_removal',
          'protected_memory_mutation',
        ]),
      );
    });

    test('enforces the ready planning horizon without justification', () {
      final proposal = _proposal(project, [
        _task(id: 'task_1'),
        _task(id: 'task_2'),
        _task(id: 'task_3'),
      ]);

      final validation = validator.validate(
        project: project,
        proposal: proposal,
        workspaceRoot: '/workspace',
      );

      expect(
        validation.errors.map((item) => item.code),
        contains('planning_horizon_exceeded'),
      );
    });
  });
}

ProjectState _project() {
  final now = DateTime(2026, 1, 1);
  return ProjectState(
    id: 'project_1',
    title: 'Project',
    originalGoal: 'Deliver the product',
    refinedGoal: 'Deliver the product',
    criteria: [
      ProjectCriterion(
        id: 'criterion_001',
        statement: 'The product is verified.',
        createdAt: now,
        updatedAt: now,
      ),
    ],
    constraints: const [],
    backlog: const [],
    memory: [
      ProjectMemoryEntry(
        id: 'memory_user',
        kind: ProjectMemoryKind.requirement,
        content: 'Do not change the public contract.',
        sourceType: ProjectMemorySourceType.user,
        confidence: ProjectMemoryConfidence.confirmed,
        protected: true,
        createdAt: now,
        updatedAt: now,
      ),
    ],
    status: ProjectStatus.active,
    activeTaskId: null,
    createdAt: now,
    updatedAt: now,
  );
}

ProjectPlanProposal _proposal(ProjectState project, List<ProjectTask> tasks) {
  return ProjectPlanProposal(
    revision: project.currentRevision + 1,
    triggers: const [ProjectPlanRevisionTrigger.noReadyTask],
    summary: 'Add bounded work.',
    rationale: 'Keep the near-term plan actionable.',
    taskAdditions: tasks,
    createdAt: DateTime(2026, 1, 2),
  );
}

ProjectTask _task({
  required String id,
  String? objective,
  List<String> dependsOnTaskIds = const [],
  List<String> doneCriteria = const ['The bounded work is verified.'],
  List<String> outOfScope = const ['Do not change unrelated work.'],
  List<String> writePaths = const ['lib/feature.dart'],
}) {
  final now = DateTime(2026, 1, 2);
  final taskObjective = objective ?? 'Implement bounded work for $id.';
  return ProjectTask(
    id: id,
    title: 'Task $id',
    objective: taskObjective,
    criterionIds: const ['criterion_001'],
    dependsOnTaskIds: dependsOnTaskIds,
    expectedEvidence: const [
      ProjectEvidenceExpectation(
        id: 'expected_verification',
        type: ProjectEvidenceType.taskClaim,
        criterionIds: ['criterion_001'],
        description: 'Verify the task done criteria.',
      ),
    ],
    writePaths: writePaths,
    doneCriteria: doneCriteria,
    outOfScope: outOfScope,
    context: const [],
    expectedArtifacts: const [],
    status: ProjectTaskStatus.queued,
    taskDocumentId: null,
    fingerprint: projectTaskFingerprint(taskObjective, const ['criterion_001']),
    rejectionReason: null,
    createdAt: now,
    updatedAt: now,
  );
}
