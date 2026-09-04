import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/serialization/model_json.dart';
import 'package:hermes/core/services/project_system/project_plan_revision_service.dart';

void main() {
  group('ProjectPlanRevisionService', () {
    late Directory workspace;
    late ProjectState project;
    const service = ProjectPlanRevisionService();

    setUp(() async {
      workspace = await Directory.systemTemp.createTemp(
        'hermes_plan_revision_',
      );
      project = _project();
    });

    tearDown(() async {
      if (await workspace.exists()) await workspace.delete(recursive: true);
    });

    test('invalid proposal cannot mutate authoritative plan', () async {
      var repairCalls = 0;
      final invalid = _proposal(
        project,
        taskAdditions: [
          _task(id: 'task_invalid', dependsOnTaskIds: const ['missing_task']),
        ],
      );

      final result = await service.prepareAndApply(
        project: project,
        proposal: invalid,
        workspaceRoot: workspace.path,
        repair: (proposal, validation) async {
          repairCalls++;
          return null;
        },
      );

      expect(repairCalls, 1);
      expect(result.repairAttempted, isTrue);
      expect(result.validation.valid, isFalse);
      expect(
        result.validation.errors.map((item) => item.code),
        contains('missing_dependency'),
      );
      expect(result.project.currentRevision, project.currentRevision);
      expect(result.project.planHistory, project.planHistory);
      expect(result.project.backlog, project.backlog);
      expect(result.project.criteria, project.criteria);
      expect(result.project.blocker?.type, ProjectBlockerType.validation);
    });

    test('one successful repair is applied as one revision', () async {
      var repairCalls = 0;
      final invalid = _proposal(
        project,
        taskAdditions: [
          _task(id: 'task_repaired', dependsOnTaskIds: const ['missing_task']),
        ],
      );

      final result = await service.prepareAndApply(
        project: project,
        proposal: invalid,
        workspaceRoot: workspace.path,
        repair: (proposal, validation) async {
          repairCalls++;
          return _proposal(
            project,
            taskAdditions: [_task(id: 'task_repaired')],
          );
        },
      );

      expect(repairCalls, 1);
      expect(result.changed, isTrue);
      expect(result.project.currentRevision, 2);
      expect(result.project.planHistory, hasLength(2));
      expect(result.project.backlog.single.id, 'task_repaired');
      final decision = result.project.memory.singleWhere(
        (entry) => entry.kind == ProjectMemoryKind.decision,
      );
      expect(decision.sourceId, 'revision_2');
      expect(decision.protected, isTrue);
    });

    test('no-op proposal clears triggers without adding history', () async {
      final pending = project.copyWith(
        pendingReplanTriggers: const [ProjectPlanRevisionTrigger.taskCompleted],
      );

      final result = await service.prepareAndApply(
        project: pending,
        proposal: _proposal(pending),
        workspaceRoot: workspace.path,
      );

      expect(result.changed, isFalse);
      expect(result.project.currentRevision, 1);
      expect(result.project.planHistory, hasLength(1));
      expect(result.project.pendingReplanTriggers, isEmpty);
    });

    test('default policy waits for high-risk criterion edit', () async {
      final editedCriterion = project.criteria.single.copyWith(
        statement: 'The revised required outcome is verified.',
      );
      final proposal = _proposal(project, criterionUpserts: [editedCriterion]);

      final pending = await service.prepareAndApply(
        project: project,
        proposal: proposal,
        workspaceRoot: workspace.path,
      );

      expect(pending.awaitingApproval, isTrue);
      expect(pending.project.pendingPlanApproval?.proposal, isNotNull);
      expect(pending.project.blocker?.type, ProjectBlockerType.planApproval);
      expect(pending.project.currentRevision, 1);
      expect(
        pending.project.criteria.single.statement,
        project.criteria.single.statement,
      );
      final restored = ModelJson.decode<ProjectState>(
        ModelJson.encode(pending.project),
      );
      expect(restored.pendingPlanApproval?.proposal?.revision, 2);

      final approved = service.approvePending(
        project: restored,
        workspaceRoot: workspace.path,
      );
      expect(approved.changed, isTrue);
      expect(approved.project.pendingPlanApproval, isNull);
      expect(approved.project.currentRevision, 2);
      expect(
        approved.project.criteria.single.statement,
        editedCriterion.statement,
      );
      expect(
        approved.project.planHistory.last.approvedBy,
        ProjectPlanRevisionApprover.user,
      );
    });

    test('criterion progress upsert applies without approval', () async {
      final completedTask = _task(
        id: 'task_completed',
      ).copyWith(status: ProjectTaskStatus.completed);
      final orphanedEvidence = ProjectEvidence(
        id: 'evidence_completed_command',
        type: ProjectEvidenceType.command,
        criterionIds: const [],
        projectTaskId: completedTask.id,
        taskDocumentId: 'document_completed',
        taskRunId: 'run_completed',
        sourceRef: 'flutter test',
        summary: 'Verification passed.',
        status: ProjectEvidenceStatus.accepted,
        strength: ProjectEvidenceStrength.conclusive,
        createdAt: DateTime(2026, 1, 2),
        evaluatedAt: DateTime(2026, 1, 2),
      );
      final withEvidence = project.copyWith(
        completedTasks: [completedTask],
        evidence: [orphanedEvidence],
      );
      final progress = withEvidence.criteria.single.copyWith(
        status: ProjectCriterionStatus.satisfied,
        evidenceIds: [orphanedEvidence.id],
        notes: 'The completed task supplied accepted evidence.',
      );
      final proposal = _proposal(
        withEvidence,
        criterionUpserts: [progress],
        taskAdditions: [_task(id: 'task_next')],
      );
      final previouslyPaused = withEvidence.copyWith(
        status: ProjectStatus.paused,
        pendingPlanApproval: PendingProjectPlanApproval(
          revision: proposal.revision,
          reason: 'The revision contains high-risk plan changes.',
          summary: proposal.summary,
          highRiskChanges: const [
            'Success criteria or their verification policy changes.',
          ],
          createdAt: proposal.createdAt,
          proposal: proposal,
        ),
        blocker: ProjectBlocker(
          type: ProjectBlockerType.planApproval,
          message: 'The revision contains high-risk plan changes.',
          createdAt: proposal.createdAt,
        ),
      );

      final result = await service.prepareAndApply(
        project: previouslyPaused,
        proposal: proposal,
        workspaceRoot: workspace.path,
      );

      expect(result.awaitingApproval, isFalse);
      expect(result.changed, isTrue);
      expect(result.project.pendingPlanApproval, isNull);
      expect(result.project.currentRevision, 2);
      expect(
        result.project.criteria.single.status,
        ProjectCriterionStatus.satisfied,
      );
      expect(result.project.evidence.single.criterionIds, const [
        'criterion_001',
      ]);
      expect(
        result.project.evidence.single.details['linkedBy'],
        'plan_revision_orphan_repair',
      );
    });

    test('changing whether a criterion is required needs approval', () async {
      final proposal = _proposal(
        project,
        criterionUpserts: [project.criteria.single.copyWith(required: false)],
      );

      final result = await service.prepareAndApply(
        project: project,
        proposal: proposal,
        workspaceRoot: workspace.path,
      );

      expect(result.awaitingApproval, isTrue);
      expect(
        result.project.pendingPlanApproval?.highRiskChanges,
        contains('Success criteria or their verification policy changes.'),
      );
    });

    test(
      'criterion contract edits stale old evidence and reset verification',
      () async {
        final verifiedAt = DateTime(2026, 1, 1);
        final existingEvidence = ProjectEvidence(
          id: 'evidence_old_contract',
          type: ProjectEvidenceType.command,
          criterionIds: const ['criterion_001'],
          projectTaskId: 'task_old',
          taskDocumentId: 'document_old',
          taskRunId: 'run_old',
          sourceRef: 'flutter test',
          summary: 'The old contract passed.',
          status: ProjectEvidenceStatus.accepted,
          strength: ProjectEvidenceStrength.conclusive,
          createdAt: verifiedAt,
          evaluatedAt: verifiedAt,
        );
        final verified = project.copyWith(
          criteria: [
            project.criteria.single.copyWith(
              status: ProjectCriterionStatus.satisfied,
              evidenceIds: [existingEvidence.id],
              verifiedAt: verifiedAt,
            ),
          ],
          evidence: [existingEvidence],
        );
        final proposal = _proposal(
          verified,
          criterionUpserts: [
            verified.criteria.single.copyWith(
              statement: 'The revised bounded outcome is verified.',
            ),
          ],
        );

        final result = await service.prepareAndApply(
          project: verified,
          proposal: proposal,
          workspaceRoot: workspace.path,
          approvalPolicy: ProjectPlanApprovalPolicy.never,
        );

        expect(result.changed, isTrue);
        expect(
          result.project.criteria.single.status,
          ProjectCriterionStatus.unsatisfied,
        );
        expect(result.project.criteria.single.evidenceIds, isEmpty);
        expect(result.project.criteria.single.verifiedAt, isNull);
        expect(
          result.project.evidence.single.status,
          ProjectEvidenceStatus.stale,
        );
        expect(
          result.project.evidence.single.details['staleReason'],
          'criterion_contract_changed',
        );
      },
    );

    test('removed criteria remain as auditable invalidated history', () async {
      final proposal = ProjectPlanProposal(
        revision: project.currentRevision + 1,
        triggers: const [ProjectPlanRevisionTrigger.manual],
        summary: 'Remove an obsolete outcome.',
        rationale: 'The user removed this outcome from scope.',
        removedCriterionIds: const ['criterion_001'],
        requiresApproval: true,
        createdAt: DateTime(2026, 1, 2),
      );

      final result = await service.prepareAndApply(
        project: project,
        proposal: proposal,
        workspaceRoot: workspace.path,
        approvalPolicy: ProjectPlanApprovalPolicy.never,
      );

      expect(result.changed, isTrue);
      expect(result.project.criteria, hasLength(1));
      expect(
        result.project.criteria.single.status,
        ProjectCriterionStatus.invalidated,
      );
      expect(
        result.project.planHistory.last.criterionChanges,
        contains('invalidate:criterion_001'),
      );
    });

    test('removed milestones remain as auditable cancelled history', () async {
      final milestone = ProjectMilestone(
        id: 'milestone_001',
        title: 'Original milestone',
        objective: 'Deliver the original bounded outcome.',
        criterionIds: const ['criterion_001'],
        status: ProjectMilestoneStatus.active,
        exitConditions: const ['The bounded outcome is verified.'],
        order: 1,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      final withMilestone = project.copyWith(milestones: [milestone]);
      final proposal = ProjectPlanProposal(
        revision: withMilestone.currentRevision + 1,
        triggers: const [ProjectPlanRevisionTrigger.manual],
        summary: 'Retire an obsolete milestone.',
        rationale: 'The roadmap changed.',
        removedMilestoneIds: const ['milestone_001'],
        createdAt: DateTime(2026, 1, 2),
      );

      final result = await service.prepareAndApply(
        project: withMilestone,
        proposal: proposal,
        workspaceRoot: workspace.path,
        approvalPolicy: ProjectPlanApprovalPolicy.never,
      );

      expect(result.changed, isTrue);
      expect(result.project.milestones, hasLength(1));
      expect(
        result.project.milestones.single.status,
        ProjectMilestoneStatus.cancelled,
      );
      expect(
        result.project.planHistory.last.milestoneChanges,
        contains('cancel:milestone_001'),
      );
    });

    test(
      'verification-only task edits are retained as real revisions',
      () async {
        final existing = _task(id: 'task_existing');
        final withBacklog = project.copyWith(backlog: [existing]);
        final updatedTask = existing.copyWith(
          expectedEvidence: const [
            ProjectEvidenceExpectation(
              id: 'expect_task',
              type: ProjectEvidenceType.command,
              criterionIds: ['criterion_001'],
              description: 'The focused verification command passes.',
              sourceRef: 'flutter test test/focused_test.dart',
            ),
          ],
        );
        final proposal = ProjectPlanProposal(
          revision: withBacklog.currentRevision + 1,
          triggers: const [ProjectPlanRevisionTrigger.manual],
          summary: 'Tighten task verification.',
          rationale: 'Use a deterministic focused command.',
          taskUpdates: [updatedTask],
          createdAt: DateTime(2026, 1, 2),
        );

        final result = await service.prepareAndApply(
          project: withBacklog,
          proposal: proposal,
          workspaceRoot: workspace.path,
          approvalPolicy: ProjectPlanApprovalPolicy.never,
        );

        expect(result.changed, isTrue);
        expect(result.project.currentRevision, 2);
        expect(
          result.project.backlog.single.expectedEvidence.single.type,
          ProjectEvidenceType.command,
        );
      },
    );

    test('never policy auto-applies a high-risk task', () async {
      final proposal = _proposal(
        project,
        taskAdditions: [_task(id: 'task_release', risk: ProjectTaskRisk.high)],
      );

      final result = await service.prepareAndApply(
        project: project,
        proposal: proposal,
        workspaceRoot: workspace.path,
        approvalPolicy: ProjectPlanApprovalPolicy.never,
      );

      expect(result.awaitingApproval, isFalse);
      expect(result.project.currentRevision, 2);
      expect(result.project.backlog.single.id, 'task_release');
    });
  });
}

ProjectState _project() {
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
    backlog: const [],
    status: ProjectStatus.active,
    activeTaskId: null,
    createdAt: now,
    updatedAt: now,
  );
}

ProjectPlanProposal _proposal(
  ProjectState project, {
  List<ProjectCriterion> criterionUpserts = const [],
  List<ProjectTask> taskAdditions = const [],
}) {
  return ProjectPlanProposal(
    revision: project.currentRevision + 1,
    triggers: const [ProjectPlanRevisionTrigger.noReadyTask],
    summary: 'Revise the near-term plan.',
    rationale: 'A bounded revision is needed.',
    criterionUpserts: criterionUpserts,
    taskAdditions: taskAdditions,
    createdAt: DateTime(2026, 1, 2),
  );
}

ProjectTask _task({
  required String id,
  List<String> dependsOnTaskIds = const [],
  ProjectTaskRisk risk = ProjectTaskRisk.low,
}) {
  final now = DateTime(2026, 1, 2);
  final objective = 'Implement and verify bounded slice $id.';
  return ProjectTask(
    id: id,
    title: 'Bounded slice $id',
    objective: objective,
    criterionIds: const ['criterion_001'],
    dependsOnTaskIds: dependsOnTaskIds,
    risk: risk,
    expectedEvidence: const [
      ProjectEvidenceExpectation(
        id: 'expect_task',
        type: ProjectEvidenceType.taskClaim,
        criterionIds: ['criterion_001'],
        description: 'The done criteria are independently checked.',
      ),
    ],
    doneCriteria: const ['The bounded slice is implemented and checked.'],
    outOfScope: const ['Do not change unrelated project scope.'],
    context: const [],
    expectedArtifacts: const [],
    status: ProjectTaskStatus.queued,
    taskDocumentId: null,
    fingerprint: projectTaskFingerprint(objective, const ['criterion_001']),
    rejectionReason: null,
    createdAt: now,
    updatedAt: now,
  );
}
