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
        task: project.backlog.single,
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
          task: project.backlog.single,
          result: result,
          evaluatedAt: timestamp,
        );
        final evaluated = criterionEvaluator.evaluateDeterministically(
          project.copyWith(evidence: evidence),
          evaluatedAt: timestamp,
        );

        expect(evidence.single.type, ProjectEvidenceType.command);
        expect(evidence.single.taskRunId, 'run_command');
        expect(evidence.single.details['runId'], 'run_command');
        expect(evidence.single.status, ProjectEvidenceStatus.accepted);
        expect(evidence.single.strength, ProjectEvidenceStrength.conclusive);
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
        task: project.backlog.single,
        result: _result(
          timestamp,
          summary: '',
          artifacts: [
            ProjectArtifact(
              id: 'artifact_1',
              projectTaskId: 'task_1',
              taskDocumentId: 'document_1',
              taskRunId: 'run_artifact',
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
      expect(evidence.single.taskRunId, 'run_artifact');
      expect(evaluated.criteria.single.status, ProjectCriterionStatus.partial);
    });

    test(
      'attributes final evidence claims to their task run and criterion',
      () {
        final project = _project(timestamp);
        final evidence = evidenceService.normalizeTaskResult(
          project: project,
          task: project.backlog.single,
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

        expect(evidence.single.projectTaskId, 'task_1');
        expect(evidence.single.taskDocumentId, 'document_1');
        expect(evidence.single.taskRunId, 'run_final');
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
          task: project.backlog.single,
          result: resultFor('run_1'),
          evaluatedAt: timestamp,
        );
        final second = evidenceService.normalizeTaskResult(
          project: project.copyWith(evidence: first),
          task: project.backlog.single,
          result: resultFor('run_2'),
          evaluatedAt: timestamp.add(const Duration(minutes: 1)),
        );

        expect(second, hasLength(2));
        expect(second.map((item) => item.id).toSet(), hasLength(2));
        expect(second.map((item) => item.taskRunId), {'run_1', 'run_2'});
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
        final task = base.backlog.single.copyWith(
          criterionIds: const ['criterion_001', 'criterion_002'],
          expectedEvidence: const [
            ProjectEvidenceExpectation(
              id: 'expect_tests',
              type: ProjectEvidenceType.command,
              criterionIds: ['criterion_001'],
              description: 'Tests pass.',
              sourceRef: 'flutter test',
            ),
            ProjectEvidenceExpectation(
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
          backlog: [task],
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
        task: project.backlog.single,
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
        task: project.backlog.single,
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
        task: project.backlog.single,
        result: passed,
        evaluatedAt: timestamp,
      );
      final duplicate = evidenceService.normalizeTaskResult(
        project: project.copyWith(evidence: first),
        task: project.backlog.single,
        result: passed,
        evaluatedAt: timestamp,
      );
      final failedAt = timestamp.add(const Duration(minutes: 1));
      final contradicted = evidenceService.normalizeTaskResult(
        project: project.copyWith(evidence: duplicate),
        task: project.backlog.single,
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

    test('accepts a proposed semantic claim with persisted rationale', () {
      final project = _project(timestamp);
      final evidence = evidenceService.normalizeTaskResult(
        project: project,
        task: project.backlog.single,
        result: _result(timestamp, summary: 'The report is usable.'),
        evaluatedAt: timestamp,
      );

      final reviewed = criterionEvaluator.applyModelReview(
        project.copyWith(evidence: evidence),
        projectComplete: true,
        remainingCriteria: const [],
        rationale: 'The persisted task result adequately demonstrates quality.',
        evaluatedAt: timestamp,
      );

      expect(reviewed.evidence.single.status, ProjectEvidenceStatus.accepted);
      expect(reviewed.evidence.single.details['acceptedBy'], 'model_review');
      expect(reviewed.criteria.single.status, ProjectCriterionStatus.satisfied);
      expect(reviewed.criteria.single.notes, contains('adequately'));
    });

    test(
      'rejects an insufficient claim and leaves the criterion unsatisfied',
      () {
        final project = _project(timestamp);
        final evidence = evidenceService.normalizeTaskResult(
          project: project,
          task: project.backlog.single,
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
}) {
  final criterion = ProjectCriterion(
    id: 'criterion_001',
    statement: 'The report is correct and usable.',
    verificationMode: verificationMode,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
  final task = ProjectTask(
    id: 'task_1',
    title: 'Create report',
    objective: 'Create the bounded report.',
    criterionIds: const ['criterion_001'],
    doneCriteria: const ['Create the report.'],
    outOfScope: const ['Do not change unrelated files.'],
    context: const [],
    expectedArtifacts: const [],
    status: ProjectTaskStatus.queued,
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
    backlog: [task],
    status: ProjectStatus.active,
    activeTaskId: null,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

TaskResult _result(
  DateTime timestamp, {
  required String summary,
  List<ProjectArtifact> artifacts = const [],
  List<TaskGateResult> gates = const [],
  List<TaskEvidenceClaim> claims = const [],
  String? finalRunId,
}) {
  return TaskResult(
    taskDocumentId: 'document_1',
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
