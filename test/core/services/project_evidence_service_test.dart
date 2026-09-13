import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/services/project_system/project_criterion_evaluator.dart';
import 'package:hermes/core/services/project_system/project_evidence_service.dart';

void main() {
  const evidenceService = ProjectEvidenceService();
  const criterionEvaluator = ProjectCriterionEvaluator();
  final timestamp = DateTime.utc(2026, 1, 1);

  group('ProjectEvidenceService', () {
    test('task completion creates only proposed criterion claims', () {
      final project = _project(timestamp);

      final evidence = evidenceService.normalizeTaskResult(
        project: project,
        task: project.tasks.single,
        result: _result(timestamp, summary: 'The task completed.'),
        evaluatedAt: timestamp,
      );
      final evaluated = criterionEvaluator.evaluateDeterministically(
        project.copyWith(evidence: evidence),
        evaluatedAt: timestamp,
      );

      expect(evidence.single.type, ProjectEvidenceType.taskClaim);
      expect(evidence.single.status, ProjectEvidenceStatus.proposed);
      expect(
        evaluated.criteria.single.status,
        ProjectCriterionStatus.unsatisfied,
      );
    });

    test(
      'required command evidence deterministically satisfies a criterion',
      () {
        final project = _project(
          timestamp,
          verificationMode: ProjectVerificationMode.deterministic,
        );
        final result = _result(
          timestamp,
          summary: '',
          finalRunId: 'run_command',
          gates: [
            TaskGateResult(
              gateId: 'command_passes',
              status: TaskGateStatus.passed,
              summary: 'All tests passed.',
              details: const {'required': true, 'command': 'flutter test'},
              evaluatedAt: timestamp,
            ),
          ],
        );

        final evidence = evidenceService.normalizeTaskResult(
          project: project,
          task: project.tasks.single,
          result: result,
          evaluatedAt: timestamp,
        );
        final evaluated = criterionEvaluator.evaluateDeterministically(
          project.copyWith(evidence: evidence),
          evaluatedAt: timestamp,
        );

        expect(evidence.single.type, ProjectEvidenceType.command);
        expect(evidence.single.runId, 'run_command');
        expect(evidence.single.details['runId'], 'run_command');
        expect(evidence.single.status, ProjectEvidenceStatus.accepted);
        expect(evidence.single.strength, ProjectEvidenceStrength.conclusive);
        expect(evidence.single.details['origin'], 'gate_evaluation');
        expect(
          evaluated.criteria.single.status,
          ProjectCriterionStatus.satisfied,
        );
      },
    );

    test('artifact existence is supporting rather than conclusive', () {
      final project = _project(timestamp);
      final evidence = evidenceService.normalizeTaskResult(
        project: project,
        task: project.tasks.single,
        result: _result(
          timestamp,
          summary: '',
          artifacts: [
            TaskArtifact(
              id: 'artifact_1',
              taskId: 'document_1',
              runId: 'run_artifact',
              path: 'report.md',
              description: 'Generated report',
              kind: 'file',
              createdAt: timestamp,
            ),
          ],
        ),
        evaluatedAt: timestamp,
      );
      final evaluated = criterionEvaluator.evaluateDeterministically(
        project.copyWith(evidence: evidence),
        evaluatedAt: timestamp,
      );

      expect(evidence.single.strength, ProjectEvidenceStrength.supporting);
      expect(evidence.single.details['origin'], 'workspace_provenance');
      expect(evidence.single.runId, 'run_artifact');
      expect(evaluated.criteria.single.status, ProjectCriterionStatus.partial);
    });

    test(
      'requires every required expectation before satisfying a criterion',
      () {
        final project = _project(
          timestamp,
          verificationMode: ProjectVerificationMode.deterministic,
          expectedEvidence: const [
            TaskEvidenceExpectation(
              id: 'expect_command',
              type: ProjectEvidenceType.command,
              criterionIds: ['criterion_001'],
              description: 'The focused tests pass.',
              sourceRef: 'flutter test',
            ),
            TaskEvidenceExpectation(
              id: 'expect_artifact',
              type: ProjectEvidenceType.artifact,
              criterionIds: ['criterion_001'],
              description: 'The report exists.',
              sourceRef: 'report.md',
            ),
          ],
        );
        final commandOnly = evidenceService.normalizeTaskResult(
          project: project,
          task: project.tasks.single,
          result: _result(
            timestamp,
            summary: '',
            gates: [
              TaskGateResult(
                gateId: 'command_passes',
                status: TaskGateStatus.passed,
                summary: 'Tests passed.',
                details: const {'required': true, 'command': 'flutter test'},
                evaluatedAt: timestamp,
              ),
            ],
          ),
          evaluatedAt: timestamp,
        );
        final partial = criterionEvaluator.evaluateDeterministically(
          project.copyWith(evidence: commandOnly),
          evaluatedAt: timestamp,
        );

        expect(commandOnly.single.expectationIds, ['expect_command']);
        expect(partial.criteria.single.status, ProjectCriterionStatus.partial);

        final completeEvidence = evidenceService.normalizeTaskResult(
          project: project.copyWith(evidence: commandOnly),
          task: project.tasks.single,
          result: _result(
            timestamp,
            summary: '',
            artifacts: [
              TaskArtifact(
                id: 'artifact_report',
                taskId: 'document_1',
                runId: 'run_artifact',
                path: 'report.md',
                description: 'Generated report.',
                kind: 'file',
                createdAt: timestamp,
              ),
            ],
          ),
          evaluatedAt: timestamp,
        );
        final complete = criterionEvaluator.evaluateDeterministically(
          project.copyWith(evidence: completeEvidence),
          evaluatedAt: timestamp,
        );

        expect(completeEvidence.last.expectationIds, ['expect_artifact']);
        expect(
          complete.criteria.single.status,
          ProjectCriterionStatus.satisfied,
        );
      },
    );

    test('records every expectation matched by one command output', () {
      final project = _project(
        timestamp,
        verificationMode: ProjectVerificationMode.deterministic,
      );
      final secondCriterion = ProjectCriterion(
        id: 'criterion_002',
        statement: 'The report remains formatted.',
        verificationMode: ProjectVerificationMode.deterministic,
        createdAt: timestamp,
        updatedAt: timestamp,
      );
      final task = project.tasks.single.copyWith(
        criterionIds: const ['criterion_001', 'criterion_002'],
        expectedEvidence: const [
          TaskEvidenceExpectation(
            id: 'expect_tests',
            type: ProjectEvidenceType.command,
            criterionIds: ['criterion_001'],
            description: 'The tests pass.',
            sourceRef: 'flutter test',
          ),
          TaskEvidenceExpectation(
            id: 'expect_format',
            type: ProjectEvidenceType.command,
            criterionIds: ['criterion_002'],
            description: 'The formatter passes.',
            sourceRef: 'flutter test',
          ),
        ],
      );
      final twoCriterionProject = project.copyWith(
        criteria: [project.criteria.single, secondCriterion],
        tasks: [task],
      );
      final evidence = evidenceService.normalizeTaskResult(
        project: twoCriterionProject,
        task: task,
        result: _result(
          timestamp,
          summary: '',
          gates: [
            TaskGateResult(
              gateId: 'command_passes',
              status: TaskGateStatus.passed,
              summary: 'The shared verification command passed.',
              details: const {'required': true, 'command': 'flutter test'},
              evaluatedAt: timestamp,
            ),
          ],
        ),
        evaluatedAt: timestamp,
      );

      expect(evidence.single.expectationIds, ['expect_tests', 'expect_format']);
      expect(evidence.single.criterionIds, ['criterion_001', 'criterion_002']);
      final evaluated = criterionEvaluator.evaluateDeterministically(
        twoCriterionProject.copyWith(evidence: evidence),
        evaluatedAt: timestamp,
      );
      expect(
        evaluated.criteria.map((criterion) => criterion.status),
        everyElement(ProjectCriterionStatus.satisfied),
      );
    });

    test(
      'replacement evidence satisfies a criterion after failed task history',
      () {
        final project = _project(
          timestamp,
          verificationMode: ProjectVerificationMode.deterministic,
          expectedEvidence: const [
            TaskEvidenceExpectation(
              id: 'old_expectation',
              type: ProjectEvidenceType.command,
              criterionIds: ['criterion_001'],
              description: 'The verification command passes.',
              sourceRef: 'flutter test',
            ),
          ],
        );
        final failedTask = project.tasks.single.copyWith(
          status: TaskStatus.failed,
        );
        final replacementTask = project.tasks.single.copyWith(
          id: 'replacement_task',
          expectedEvidence: const [
            TaskEvidenceExpectation(
              id: 'new_expectation',
              type: ProjectEvidenceType.command,
              criterionIds: ['criterion_001'],
              description: 'The replacement verification command passes.',
              sourceRef: 'flutter test',
            ),
          ],
        );
        final replacementProject = project.copyWith(
          tasks: [failedTask, replacementTask],
        );
        final evidence = evidenceService.normalizeTaskResult(
          project: replacementProject,
          task: replacementTask,
          result: _result(
            timestamp,
            summary: '',
            gates: [
              TaskGateResult(
                gateId: 'command_passes',
                status: TaskGateStatus.passed,
                summary: 'The replacement verification passed.',
                details: const {'required': true, 'command': 'flutter test'},
                evaluatedAt: timestamp,
              ),
            ],
          ),
          evaluatedAt: timestamp,
        );

        final evaluated = criterionEvaluator.evaluateDeterministically(
          replacementProject.copyWith(evidence: evidence),
          evaluatedAt: timestamp,
        );

        expect(evidence.single.taskId, 'replacement_task');
        expect(evidence.single.expectationIds, ['new_expectation']);
        expect(
          evaluated.criteria.single.status,
          ProjectCriterionStatus.satisfied,
        );
      },
    );

    test('associates an explicit claim with its evidence expectation', () {
      final project = _project(
        timestamp,
        expectedEvidence: const [
          TaskEvidenceExpectation(
            id: 'expect_claim',
            type: ProjectEvidenceType.taskClaim,
            criterionIds: ['criterion_001'],
            description: 'The task outcome is confirmed.',
          ),
        ],
      );
      final evidence = evidenceService.normalizeTaskResult(
        project: project,
        task: project.tasks.single,
        result: _result(
          timestamp,
          summary: '',
          claims: const [
            TaskEvidenceClaim(
              criterionId: 'criterion_001',
              expectationId: 'expect_claim',
              claim: 'The outcome is confirmed.',
              sourceRef: 'run_1',
            ),
          ],
        ),
        evaluatedAt: timestamp,
      );

      expect(evidence.single.expectationIds, ['expect_claim']);
    });

    test(
      'model review does not satisfy a criterion with partial expectations',
      () {
        final project = _project(
          timestamp,
          expectedEvidence: const [
            TaskEvidenceExpectation(
              id: 'expect_first',
              type: ProjectEvidenceType.taskClaim,
              criterionIds: ['criterion_001'],
              description: 'The first outcome is confirmed.',
            ),
            TaskEvidenceExpectation(
              id: 'expect_second',
              type: ProjectEvidenceType.taskClaim,
              criterionIds: ['criterion_001'],
              description: 'The second outcome is confirmed.',
            ),
          ],
        );
        final evidence = evidenceService.normalizeTaskResult(
          project: project,
          task: project.tasks.single,
          result: _result(
            timestamp,
            summary: '',
            claims: const [
              TaskEvidenceClaim(
                criterionId: 'criterion_001',
                expectationId: 'expect_first',
                claim: 'The first outcome is confirmed.',
                sourceRef: 'run_1',
                suggestedStrength: TaskEvidenceClaimStrength.supporting,
              ),
            ],
          ),
          evaluatedAt: timestamp,
        );
        final reviewed = criterionEvaluator.applyModelReview(
          project.copyWith(evidence: evidence),
          projectComplete: true,
          remainingCriteria: const [],
          rationale: 'The first item was reviewed.',
          evaluatedAt: timestamp,
        );

        expect(reviewed.evidence.single.status, ProjectEvidenceStatus.accepted);
        expect(reviewed.criteria.single.status, ProjectCriterionStatus.partial);
      },
    );

    test(
      'attributes final evidence claims to their task run and criterion',
      () {
        final project = _project(timestamp);
        final evidence = evidenceService.normalizeTaskResult(
          project: project,
          task: project.tasks.single,
          result: _result(
            timestamp,
            summary: '',
            finalRunId: 'run_final',
            claims: const [
              TaskEvidenceClaim(
                criterionId: 'criterion_001',
                claim: 'The final review confirms the report is usable.',
                sourceRef: 'final review',
                runId: 'run_final',
              ),
            ],
          ),
          evaluatedAt: timestamp,
        );

        expect(evidence.single.taskId, 'task_1');
        expect(evidence.single.runId, 'run_final');
        expect(evidence.single.criterionIds, ['criterion_001']);
        expect(evidence.single.details['runId'], 'run_final');
      },
    );

    test(
      'keeps identical claims from distinct task runs uniquely attributable',
      () {
        final project = _project(timestamp);
        TaskResult resultFor(String runId) => _result(
          timestamp,
          summary: '',
          finalRunId: runId,
          claims: [
            TaskEvidenceClaim(
              criterionId: 'criterion_001',
              claim: 'The report satisfies the bounded review.',
              sourceRef: 'final review',
              runId: runId,
            ),
          ],
        );

        final first = evidenceService.normalizeTaskResult(
          project: project,
          task: project.tasks.single,
          result: resultFor('run_1'),
          evaluatedAt: timestamp,
        );
        final second = evidenceService.normalizeTaskResult(
          project: project.copyWith(evidence: first),
          task: project.tasks.single,
          result: resultFor('run_2'),
          evaluatedAt: timestamp.add(const Duration(minutes: 1)),
        );

        expect(second, hasLength(2));
        expect(second.map((item) => item.id).toSet(), hasLength(2));
        expect(second.map((item) => item.runId), {'run_1', 'run_2'});
      },
    );

    test(
      'matches command evidence to source-specific criterion expectations',
      () {
        final base = _project(
          timestamp,
          verificationMode: ProjectVerificationMode.deterministic,
        );
        final secondCriterion = ProjectCriterion(
          id: 'criterion_002',
          statement: 'The source remains formatted.',
          verificationMode: ProjectVerificationMode.deterministic,
          createdAt: timestamp,
          updatedAt: timestamp,
        );
        final task = base.tasks.single.copyWith(
          criterionIds: const ['criterion_001', 'criterion_002'],
          expectedEvidence: const [
            TaskEvidenceExpectation(
              id: 'expect_tests',
              type: ProjectEvidenceType.command,
              criterionIds: ['criterion_001'],
              description: 'Tests pass.',
              sourceRef: 'flutter test',
            ),
            TaskEvidenceExpectation(
              id: 'expect_format',
              type: ProjectEvidenceType.command,
              criterionIds: ['criterion_002'],
              description: 'Formatting passes.',
              sourceRef: 'dart format --output=none .',
            ),
          ],
        );
        final project = base.copyWith(
          criteria: [base.criteria.single, secondCriterion],
          tasks: [task],
        );

        final evidence = evidenceService.normalizeTaskResult(
          project: project,
          task: task,
          result: _result(
            timestamp,
            summary: '',
            finalRunId: 'run_tests',
            gates: [
              TaskGateResult(
                gateId: 'command_passes',
                status: TaskGateStatus.passed,
                summary: 'Tests passed.',
                details: const {'required': true, 'command': 'flutter test'},
                evaluatedAt: timestamp,
              ),
            ],
          ),
          evaluatedAt: timestamp,
        );

        expect(evidence.single.sourceRef, 'flutter test');
        expect(evidence.single.criterionIds, ['criterion_001']);
      },
    );

    test('a failing command does not stale evidence from another command', () {
      final project = _project(
        timestamp,
        verificationMode: ProjectVerificationMode.deterministic,
      );
      final passed = evidenceService.normalizeTaskResult(
        project: project,
        task: project.tasks.single,
        result: _result(
          timestamp,
          summary: '',
          gates: [
            TaskGateResult(
              gateId: 'command_passes',
              status: TaskGateStatus.passed,
              summary: 'Tests passed.',
              details: const {'required': true, 'command': 'flutter test'},
              evaluatedAt: timestamp,
            ),
          ],
        ),
        evaluatedAt: timestamp,
      );
      final failedAt = timestamp.add(const Duration(minutes: 1));

      final combined = evidenceService.normalizeTaskResult(
        project: project.copyWith(evidence: passed),
        task: project.tasks.single,
        result: _result(
          failedAt,
          summary: '',
          gates: [
            TaskGateResult(
              gateId: 'command_passes',
              status: TaskGateStatus.failed,
              summary: 'Analysis failed.',
              details: const {'required': true, 'command': 'flutter analyze'},
              evaluatedAt: failedAt,
            ),
          ],
        ),
        evaluatedAt: failedAt,
      );

      expect(combined, hasLength(2));
      expect(combined.first.status, ProjectEvidenceStatus.accepted);
      expect(combined.last.status, ProjectEvidenceStatus.rejected);
      expect(combined.map((item) => item.sourceRef), [
        'flutter test',
        'flutter analyze',
      ]);
    });

    test('deduplicates repeated evidence and stales a contradicted gate', () {
      final project = _project(
        timestamp,
        verificationMode: ProjectVerificationMode.deterministic,
      );
      final passed = _result(
        timestamp,
        summary: '',
        gates: [
          TaskGateResult(
            gateId: 'command_passes',
            status: TaskGateStatus.passed,
            summary: 'Passed.',
            details: const {'required': true, 'command': 'dart test'},
            evaluatedAt: timestamp,
          ),
        ],
      );
      final first = evidenceService.normalizeTaskResult(
        project: project,
        task: project.tasks.single,
        result: passed,
        evaluatedAt: timestamp,
      );
      final duplicate = evidenceService.normalizeTaskResult(
        project: project.copyWith(evidence: first),
        task: project.tasks.single,
        result: passed,
        evaluatedAt: timestamp,
      );
      final failedAt = timestamp.add(const Duration(minutes: 1));
      final contradicted = evidenceService.normalizeTaskResult(
        project: project.copyWith(evidence: duplicate),
        task: project.tasks.single,
        result: _result(
          failedAt,
          summary: '',
          gates: [
            TaskGateResult(
              gateId: 'command_passes',
              status: TaskGateStatus.failed,
              summary: 'Failed.',
              details: const {'required': true, 'command': 'dart test'},
              evaluatedAt: failedAt,
            ),
          ],
        ),
        evaluatedAt: failedAt,
      );

      expect(duplicate, hasLength(1));
      expect(contradicted, hasLength(2));
      expect(contradicted.first.status, ProjectEvidenceStatus.stale);
      expect(contradicted.last.status, ProjectEvidenceStatus.rejected);

      final revalidated = evidenceService.normalizeTaskResult(
        project: project.copyWith(
          evidence: [
            first.single.copyWith(status: ProjectEvidenceStatus.stale),
          ],
        ),
        task: project.tasks.single,
        result: passed,
        evaluatedAt: failedAt.add(const Duration(minutes: 1)),
      );
      expect(revalidated, hasLength(2));
      expect(revalidated.last.status, ProjectEvidenceStatus.accepted);
    });
  });

  group('ProjectCriterionEvaluator model review', () {
    test('cannot satisfy a criterion when no evidence exists', () {
      final project = _project(timestamp);

      final reviewed = criterionEvaluator.applyModelReview(
        project,
        projectComplete: true,
        remainingCriteria: const [],
        rationale: 'Unsupported model assertion.',
        evaluatedAt: timestamp,
      );

      expect(reviewed.evidence, isEmpty);
      expect(
        reviewed.criteria.single.status,
        ProjectCriterionStatus.unsatisfied,
      );
    });

    test(
      'accepts a proposed non-advisory semantic claim with persisted rationale',
      () {
        final project = _project(timestamp);
        final evidence = evidenceService.normalizeTaskResult(
          project: project,
          task: project.tasks.single,
          result: _result(
            timestamp,
            summary: 'The report is usable.',
            claims: const [
              TaskEvidenceClaim(
                criterionId: 'criterion_001',
                claim: 'The report is usable.',
                sourceRef: 'run_1',
                suggestedStrength: TaskEvidenceClaimStrength.supporting,
              ),
            ],
          ),
          evaluatedAt: timestamp,
        );

        final reviewed = criterionEvaluator.applyModelReview(
          project.copyWith(evidence: evidence),
          projectComplete: true,
          remainingCriteria: const [],
          rationale:
              'The persisted task result adequately demonstrates quality.',
          evaluatedAt: timestamp,
        );

        expect(reviewed.evidence.single.status, ProjectEvidenceStatus.accepted);
        expect(reviewed.evidence.single.details['acceptedBy'], 'model_review');
        expect(
          reviewed.criteria.single.status,
          ProjectCriterionStatus.satisfied,
        );
        expect(reviewed.criteria.single.notes, contains('adequately'));
      },
    );

    test('supported criterion IDs promote supporting evidence to partial', () {
      final project = _project(timestamp);
      final evidence = evidenceService.normalizeTaskResult(
        project: project,
        task: project.tasks.single,
        result: _result(
          timestamp,
          summary: 'The first bounded result is present.',
          claims: const [
            TaskEvidenceClaim(
              criterionId: 'criterion_001',
              claim: 'The first bounded result is present.',
              sourceRef: 'run_1',
              suggestedStrength: TaskEvidenceClaimStrength.supporting,
            ),
          ],
        ),
        evaluatedAt: timestamp,
      );

      final reviewed = criterionEvaluator.applyModelReview(
        project.copyWith(evidence: evidence),
        projectComplete: false,
        remainingCriteria: const ['The report is correct and usable.'],
        supportedCriterionIds: const ['criterion_001'],
        rationale: 'The persisted evidence supports part of the criterion.',
        evaluatedAt: timestamp,
      );

      expect(reviewed.evidence.single.status, ProjectEvidenceStatus.accepted);
      expect(reviewed.evidence.single.details['acceptedBy'], 'model_review');
      expect(reviewed.criteria.single.status, ProjectCriterionStatus.partial);
    });

    test('advisory evidence is never promoted by supported criterion IDs', () {
      final project = _project(timestamp);
      final evidence = evidenceService.normalizeTaskResult(
        project: project,
        task: project.tasks.single,
        result: _result(timestamp, summary: 'Work was attempted.'),
        evaluatedAt: timestamp,
      );

      final reviewed = criterionEvaluator.applyModelReview(
        project.copyWith(evidence: evidence),
        projectComplete: false,
        remainingCriteria: const ['The report is correct and usable.'],
        supportedCriterionIds: const ['criterion_001'],
        rationale: 'The claim is only advisory.',
        evaluatedAt: timestamp,
      );

      expect(reviewed.evidence.single.status, ProjectEvidenceStatus.proposed);
      expect(
        reviewed.criteria.single.status,
        ProjectCriterionStatus.unsatisfied,
      );
    });

    test(
      'rejects an insufficient claim and leaves the criterion unsatisfied',
      () {
        final project = _project(timestamp);
        final evidence = evidenceService.normalizeTaskResult(
          project: project,
          task: project.tasks.single,
          result: _result(timestamp, summary: 'Work was attempted.'),
          evaluatedAt: timestamp,
        );

        final reviewed = criterionEvaluator.applyModelReview(
          project.copyWith(evidence: evidence),
          projectComplete: false,
          remainingCriteria: const ['The report is correct and usable.'],
          rationale: '',
          evaluatedAt: timestamp,
        );

        expect(reviewed.evidence.single.status, ProjectEvidenceStatus.rejected);
        expect(
          reviewed.criteria.single.status,
          ProjectCriterionStatus.unsatisfied,
        );
      },
    );
  });
}

ProjectDocument _project(
  DateTime timestamp, {
  ProjectVerificationMode verificationMode = ProjectVerificationMode.mixed,
  List<TaskEvidenceExpectation> expectedEvidence = const [],
}) {
  final criterion = ProjectCriterion(
    id: 'criterion_001',
    statement: 'The report is correct and usable.',
    verificationMode: verificationMode,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
  final task = Task(
    id: 'task_1',
    title: 'Create report',
    objective: 'Create the bounded report.',
    criterionIds: const ['criterion_001'],
    expectedEvidence: expectedEvidence,
    doneCriteria: const ['Create the report.'],
    outOfScope: const ['Do not change unrelated files.'],
    context: const [],
    expectedArtifacts: const [],
    status: TaskStatus.queued,
    taskDocumentId: null,
    fingerprint: 'create-report',
    rejectionReason: null,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
  return ProjectDocument(
    id: 'project_1',
    title: 'Report project',
    originalGoal: 'Create a report',
    refinedGoal: 'Create a correct report',
    criteria: [criterion],
    constraints: const [],
    tasks: [task],
    status: ProjectStatus.active,
    activeTaskId: null,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

TaskResult _result(
  DateTime timestamp, {
  required String summary,
  List<TaskArtifact> artifacts = const [],
  List<TaskGateResult> gates = const [],
  List<TaskEvidenceClaim> claims = const [],
  String? finalRunId,
}) {
  return TaskResult(
    taskId: 'document_1',
    status: TaskStatus.completed,
    summary: summary,
    memoryUpdate: '',
    artifacts: artifacts,
    gateResults: gates,
    evidenceClaims: claims,
    finalRunId: finalRunId,
    toolCallCount: 0,
  );
}
