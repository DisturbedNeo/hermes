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

  test('round-trips the clean-slate task collection', () {
    final now = DateTime(2026, 1, 1);
    final task = ProjectTask(
      id: 'task_1',
      title: 'Bounded task',
      objective: 'Do one bounded thing',
      criterionIds: const ['criterion_1'],
      doneCriteria: const ['The thing is done.'],
      outOfScope: const ['The rest of the project.'],
      context: const [],
      expectedArtifacts: const [],
      status: ProjectTaskStatus.queued,
      taskDocumentId: null,
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

    final decoded = ModelJson.decode<ProjectDocument>(
      ModelJson.encode(project),
    );
    expect(decoded.schemaVersion, 5);
    expect(decoded.tasks.single.id, 'task_1');
    expect(decoded.nextRevision, 2);
    expect(ModelJson.encode(decoded), ModelJson.encode(project));
  });

  test('round-trips evidence expectation identities', () {
    final now = DateTime(2026, 1, 1);
    final evidence = ProjectEvidence(
      id: 'evidence_1',
      type: ProjectEvidenceType.artifact,
      criterionIds: const ['criterion_1'],
      expectationIds: const ['expect_artifact'],
      projectTaskId: 'task_1',
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
