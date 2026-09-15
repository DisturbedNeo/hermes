import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/serialization/model_json.dart';

void main() {
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
      currentBatchProgressObserved: true,
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
    expect(decoded.currentBatchProgressObserved, isTrue);
    expect(decoded.currentBatchTaskId, 'task_2');
  });

  test('rejects an embedded task collection', () {
    expect(
      () => ModelJson.decode<ProjectDocument>({
        'id': 'project_embedded_tasks',
        'tasks': const [],
      }),
      throwsA(anything),
    );
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
