import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/serialization/model_json.dart';

void main() {
  test('rejects unsupported persisted project schemas', () {
    expect(
      () => ModelJson.decode<ProjectDocument>({
        'schema_version': 4,
        'id': 'legacy-project',
        'title': 'Legacy',
      }),
      throwsA(anything),
    );
  });

  test('persists ordered task IDs without embedding task records', () {
    final now = DateTime(2026, 1, 1);
    final task = Task(
      id: 'task_1',
      title: 'Bounded task',
      objective: 'Do one bounded thing',
      criterionIds: const ['criterion_1'],
      doneCriteria: const ['The thing is done.'],
      outOfScope: const ['The rest of the project.'],
      context: const [],
      expectedArtifacts: const [],
      status: TaskStatus.queued,
      fingerprint: 'task_1',
      rejectionReason: null,
      createdAt: now,
      updatedAt: now,
    );
    final project = ProjectDocument(
      id: 'project_1',
      title: 'Project',
      originalGoal: 'Build it',
      refinedGoal: 'Build it safely',
      criteria: [
        ProjectCriterion(
          id: 'criterion_1',
          statement: 'It works',
          createdAt: now,
          updatedAt: now,
        ),
      ],
      constraints: const [],
      tasks: [task],
      status: ProjectStatus.active,
      activeTaskId: null,
      createdAt: now,
      updatedAt: now,
    );

    final encoded = ModelJson.encode(project);
    expect(encoded['taskIds'], ['task_1']);
    expect(encoded, isNot(contains('tasks')));

    final decoded = ModelJson.decode<ProjectDocument>(encoded);
    expect(decoded.schemaVersion, ProjectDocument.currentSchemaVersion);
    expect(decoded.taskIds, ['task_1']);
    expect(decoded.tasks, isEmpty);
    expect(decoded.nextRevision, 2);
    expect(ModelJson.encode(decoded), encoded);
  });

  test('persists and restores the resumable batch cursor', () {
    final now = DateTime(2026, 1, 1);
    final project = ProjectDocument(
      id: 'project_batch',
      title: 'Batch project',
      originalGoal: 'Run a batch',
      refinedGoal: 'Run a batch safely',
      criteria: [
        ProjectCriterion(
          id: 'criterion_1',
          statement: 'The batch is complete.',
          createdAt: now,
          updatedAt: now,
        ),
      ],
      constraints: const [],
      tasks: const [],
      taskIds: const ['task_1', 'task_2', 'task_3'],
      currentBatchTaskIds: const ['task_1', 'task_2', 'task_3'],
      currentBatchIndex: 1,
      currentBatchPlanRevision: 4,
      pendingReplanReason: 'The batch reached a safe boundary.',
      status: ProjectStatus.paused,
      activeTaskId: null,
      createdAt: now,
      updatedAt: now,
    );

    final encoded = ModelJson.encode(project);
    expect(encoded['currentBatchTaskIds'], ['task_1', 'task_2', 'task_3']);
    expect(encoded['currentBatchIndex'], 1);
    expect(encoded['currentBatchPlanRevision'], 4);
    expect(
      encoded['pendingReplanReason'],
      'The batch reached a safe boundary.',
    );

    final decoded = ModelJson.decode<ProjectDocument>(encoded);
    expect(decoded.currentBatchTaskIds, project.currentBatchTaskIds);
    expect(decoded.currentBatchIndex, 1);
    expect(decoded.currentBatchPlanRevision, 4);
    expect(decoded.pendingReplanReason, project.pendingReplanReason);
    expect(decoded.currentBatchTaskId, 'task_2');
  });

  test('upgrades a Phase 2 project with an empty batch cursor', () {
    final now = DateTime(2026, 1, 1);
    final raw = <String, dynamic>{
      'schemaVersion': 5,
      'id': 'project_phase_2',
      'title': 'Phase 2 project',
      'originalGoal': 'Keep the project running.',
      'refinedGoal': 'Keep the project running safely.',
      'criteria': [
        {
          'id': 'criterion_1',
          'statement': 'The project is safe.',
          'createdAt': now.toIso8601String(),
          'updatedAt': now.toIso8601String(),
        },
      ],
      'constraints': <String>[],
      'taskIds': <String>[],
      'status': 'active',
      'activeTaskId': null,
      'createdAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
    };

    final decoded = ModelJson.decode<ProjectDocument>(raw);
    expect(decoded.schemaVersion, ProjectDocument.currentSchemaVersion);
    expect(decoded.currentBatchTaskIds, isEmpty);
    expect(decoded.currentBatchIndex, 0);
    expect(decoded.currentBatchPlanRevision, 0);
    expect(decoded.pendingReplanReason, isNull);
  });

  test('round-trips evidence expectation identities', () {
    final now = DateTime(2026, 1, 1);
    final evidence = ProjectEvidence(
      id: 'evidence_1',
      type: ProjectEvidenceType.artifact,
      criterionIds: const ['criterion_1'],
      expectationIds: const ['expect_artifact'],
      taskId: 'task_1',
      sourceRef: 'report.md',
      summary: 'The report exists.',
      status: ProjectEvidenceStatus.accepted,
      strength: ProjectEvidenceStrength.supporting,
      createdAt: now,
      evaluatedAt: now,
    );

    final decoded = ModelJson.decode<ProjectEvidence>(
      ModelJson.encode(evidence),
    );
    expect(decoded.expectationIds, ['expect_artifact']);
    expect(ModelJson.encode(decoded), ModelJson.encode(evidence));
  });
}
