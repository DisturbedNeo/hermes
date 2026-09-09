import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/services/project_system/project_criterion_evaluator.dart';
import 'package:hermes/core/services/project_system/project_plan_revision_service.dart';

void main() {
  late Directory workspace;
  const service = ProjectPlanRevisionService();

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('hermes_plan_revision_');
  });

  tearDown(() async {
    if (await workspace.exists()) await workspace.delete(recursive: true);
  });

  test('invalid desired plans do not partially apply', () async {
    final project = _project([_task('existing')]);
    final invalid = _desired(project, [
      _task('invalid', dependencies: const ['missing']),
    ]);
    final result = await service.prepareAndApply(
      project: project,
      proposal: invalid,
      workspaceRoot: workspace.path,
    );

    expect(result.validation.valid, isFalse);
    expect(result.project.tasks.map((task) => task.id), ['existing']);
    expect(result.project.planHistory, hasLength(1));
  });

  test('automatically retries invalid desired plans before blocking', () async {
    final project = _project([_task('existing')]);
    final invalid = _desired(project, [
      _task('invalid', dependencies: const ['missing']),
    ]);
    var repairCalls = 0;
    final result = await service.prepareAndApply(
      project: project,
      proposal: invalid,
      workspaceRoot: workspace.path,
      approvalPolicy: ProjectPlanApprovalPolicy.never,
      repair: (candidate, _) async {
        repairCalls++;
        return repairCalls == 1
            ? candidate
            : _desired(project, [_task('fixed')]);
      },
    );

    expect(repairCalls, 2);
    expect(result.changed, isTrue);
    expect(result.project.taskById('fixed'), isNotNull);
    expect(result.project.status, ProjectStatus.active);
  });

  test(
    'reconciliation retains terminal history and makes new work queued',
    () async {
      final completed = _task('completed').copyWith(
        status: ProjectTaskStatus.completed,
        taskDocumentId: 'document_completed',
      );
      final active = _task('active').copyWith(
        status: ProjectTaskStatus.running,
        taskDocumentId: 'document_active',
      );
      final project = _project([
        completed,
        active,
        _task('omitted'),
      ], activeTaskId: 'active');
      final result = await service.prepareAndApply(
        project: project,
        proposal: _desired(project, [_task('new')]),
        workspaceRoot: workspace.path,
        approvalPolicy: ProjectPlanApprovalPolicy.never,
      );

      expect(result.changed, isTrue);
      expect(
        result.project.taskById('completed')?.status,
        ProjectTaskStatus.completed,
      );
      expect(
        result.project.taskById('completed')?.taskDocumentId,
        'document_completed',
      );
      expect(
        result.project.taskById('active')?.status,
        ProjectTaskStatus.running,
      );
      expect(
        result.project.taskById('active')?.taskDocumentId,
        'document_active',
      );
      expect(result.project.taskById('new')?.status, ProjectTaskStatus.queued);
      expect(
        result.project.taskById('omitted')?.status,
        ProjectTaskStatus.obsolete,
      );
    },
  );

  test('preserves explicit task dispositions during reconciliation', () async {
    final project = _project([_task('existing')]);
    final result = await service.prepareAndApply(
      project: project,
      proposal: _desired(
        project,
        [
          _task('existing', status: ProjectTaskStatus.deferred),
          _task(
            'new',
            status: ProjectTaskStatus.obsolete,
            expectedEvidence: const [
              ProjectEvidenceExpectation(
                id: 'expect_new',
                type: ProjectEvidenceType.taskClaim,
                criterionIds: ['criterion_001'],
                description: 'The new task is independently checked.',
              ),
            ],
          ),
        ],
        deferredTaskIds: const ['existing'],
        obsoleteTaskIds: const ['new'],
      ),
      workspaceRoot: workspace.path,
      approvalPolicy: ProjectPlanApprovalPolicy.never,
    );

    expect(result.validation.valid, isTrue);
    expect(
      result.project.taskById('existing')?.status,
      ProjectTaskStatus.deferred,
    );
    expect(result.project.taskById('new')?.status, ProjectTaskStatus.obsolete);
  });

  test(
    'explicit empty plans retire only mutable work and preserve history',
    () async {
      final completed = _task('completed', status: ProjectTaskStatus.completed);
      final queued = _task('queued');
      final project = _project([completed, queued]);
      final result = await service.prepareAndApply(
        project: project,
        proposal: _desired(
          project,
          const [],
          criteria: const [],
          requiresApproval: true,
        ),
        workspaceRoot: workspace.path,
        approvalPolicy: ProjectPlanApprovalPolicy.never,
      );

      expect(result.changed, isTrue);
      expect(
        result.project.criteria.single.status,
        ProjectCriterionStatus.invalidated,
      );
      expect(
        result.project.taskById('completed')?.status,
        ProjectTaskStatus.completed,
      );
      expect(
        result.project.taskById('queued')?.status,
        ProjectTaskStatus.obsolete,
      );
    },
  );

  test('applies verification and safety-only task changes', () async {
    final project = _project([_task('existing')]);
    final revised = _task(
      'existing',
      writePaths: const ['lib/new_feature.dart'],
      selectionRationale: 'The new path is the bounded implementation surface.',
      expectedEvidence: const [
        ProjectEvidenceExpectation(
          id: 'expect_task',
          type: ProjectEvidenceType.command,
          criterionIds: ['criterion_001'],
          description: 'The focused verification command passes.',
        ),
      ],
      expectedArtifacts: [
        ProjectArtifact(
          id: 'artifact_existing',
          projectTaskId: null,
          taskDocumentId: null,
          path: 'lib/new_feature.dart',
          description: 'The bounded implementation file.',
          kind: 'file',
          createdAt: DateTime(2026, 1, 2),
        ),
      ],
    );
    final result = await service.prepareAndApply(
      project: project,
      proposal: _desired(project, [revised]),
      workspaceRoot: workspace.path,
      approvalPolicy: ProjectPlanApprovalPolicy.never,
    );

    expect(result.changed, isTrue);
    expect(result.project.taskById('existing')?.writePaths, [
      'lib/new_feature.dart',
    ]);
    expect(
      result.project.taskById('existing')?.expectedEvidence.single.type,
      ProjectEvidenceType.command,
    );
    expect(
      result.project.taskById('existing')?.expectedArtifacts.single.path,
      'lib/new_feature.dart',
    );
  });

  test('detects edits to existing open-question content', () async {
    final project = _project(
      const [],
      openQuestions: [
        PendingProjectQuestion(
          id: 'question_1',
          question: 'Which platform should be first?',
          createdAt: DateTime(2026, 1, 1),
        ),
      ],
    );
    final result = await service.prepareAndApply(
      project: project,
      proposal: _desired(
        project,
        const [],
        openQuestions: [
          PendingProjectQuestion(
            id: 'question_1',
            question: 'Which desktop platform should be first?',
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
      ),
      workspaceRoot: workspace.path,
      approvalPolicy: ProjectPlanApprovalPolicy.never,
    );

    expect(result.changed, isTrue);
    expect(
      result.project.openQuestions.single.question,
      'Which desktop platform should be first?',
    );
  });

  test('preserves completed milestones when omitted or modified', () async {
    final completed = _milestone(
      'milestone_done',
      status: ProjectMilestoneStatus.completed,
      completedAt: DateTime(2026, 1, 3),
    );
    final project = _project(const [], milestones: [completed]);
    final result = await service.prepareAndApply(
      project: project,
      proposal: _desired(
        project,
        [_task('new')],
        milestones: [
          ProjectMilestone(
            id: completed.id,
            title: 'Planner attempted to rewrite history',
            objective: completed.objective,
            criterionIds: completed.criterionIds,
            status: ProjectMilestoneStatus.cancelled,
            exitConditions: completed.exitConditions,
            order: completed.order,
            createdAt: completed.createdAt,
            updatedAt: completed.updatedAt,
            completedAt: completed.completedAt,
          ),
        ],
      ),
      workspaceRoot: workspace.path,
      approvalPolicy: ProjectPlanApprovalPolicy.never,
    );

    final preserved = result.project.milestones.single;
    expect(preserved.title, completed.title);
    expect(preserved.status, ProjectMilestoneStatus.completed);
    expect(preserved.completedAt, completed.completedAt);
  });

  test('normalizes new milestone lifecycle state', () async {
    final project = _project(const []);
    final first = _milestone(
      'milestone_first',
      status: ProjectMilestoneStatus.completed,
      completedAt: DateTime(2026, 1, 2),
      order: 1,
    );
    final second = _milestone(
      'milestone_second',
      status: ProjectMilestoneStatus.blocked,
      order: 2,
    );
    final result = await service.prepareAndApply(
      project: project,
      proposal: _desired(project, const [], milestones: [second, first]),
      workspaceRoot: workspace.path,
      approvalPolicy: ProjectPlanApprovalPolicy.never,
    );

    expect(result.validation.valid, isTrue);
    expect(result.project.milestones[0].id, 'milestone_first');
    expect(result.project.milestones[0].status, ProjectMilestoneStatus.active);
    expect(result.project.milestones[0].completedAt, isNull);
    expect(result.project.milestones[1].status, ProjectMilestoneStatus.planned);
  });

  test('requires approval before removing a nonterminal milestone', () async {
    final milestone = _milestone(
      'milestone_active',
      status: ProjectMilestoneStatus.active,
    );
    final project = _project(const [], milestones: [milestone]);
    final pending = await service.prepareAndApply(
      project: project,
      proposal: _desired(project, [_task('new')], milestones: const []),
      workspaceRoot: workspace.path,
    );

    expect(pending.awaitingApproval, isTrue);
    expect(
      pending.project.milestones.single.status,
      ProjectMilestoneStatus.active,
    );
    expect(
      pending.project.pendingPlanApproval?.highRiskReasonCodes,
      contains('milestone_removed'),
    );

    final approved = service.approvePending(
      project: pending.project,
      workspaceRoot: workspace.path,
    );
    expect(
      approved.project.milestones.single.status,
      ProjectMilestoneStatus.cancelled,
    );
  });

  test('blocks invalid memory edits without mutating memory', () async {
    final existing = _memory('memory_existing');
    final project = _project(const [], memory: [existing]);
    final result = await service.prepareAndApply(
      project: project,
      proposal: _desired(
        project,
        const [],
        memoryAdditions: [
          ProjectMemoryEntry(
            id: 'memory_existing',
            kind: ProjectMemoryKind.fact,
            content: '',
            sourceType: ProjectMemorySourceType.planner,
            confidence: ProjectMemoryConfidence.inferred,
            createdAt: DateTime(2026, 1, 2),
            updatedAt: DateTime(2026, 1, 2),
          ),
        ],
      ),
      workspaceRoot: workspace.path,
    );

    expect(result.changed, isFalse);
    expect(result.project.status, ProjectStatus.blocked);
    expect(result.project.memory, [existing]);
    expect(
      result.validation.errors.map((issue) => issue.code),
      contains('memory_id_collision'),
    );
  });

  test('applies a valid memory supersession', () async {
    final source = _memory('memory_source');
    final replacement = _memory('memory_replacement');
    final project = _project(const [], memory: [source, replacement]);
    final result = await service.prepareAndApply(
      project: project,
      proposal: _desired(
        project,
        const [],
        memorySupersessions: const [
          ProjectMemorySupersession(
            entryId: 'memory_source',
            supersededById: 'memory_replacement',
          ),
        ],
      ),
      workspaceRoot: workspace.path,
      approvalPolicy: ProjectPlanApprovalPolicy.never,
    );

    expect(result.changed, isTrue);
    expect(
      result.project.memory.firstWhere((entry) => entry.id == source.id).active,
      isFalse,
    );
    expect(
      result.project.memory
          .firstWhere((entry) => entry.id == replacement.id)
          .coveredEntryIds,
      contains(source.id),
    );
  });

  test(
    'high-risk desired changes store the desired plan for approval',
    () async {
      final project = _project(const []);
      final criterion = project.criteria.single.copyWith(
        statement: 'A materially different required outcome.',
      );
      final desired = ProjectDesiredPlan(
        revision: project.nextRevision,
        triggers: const [ProjectPlanRevisionTrigger.noReadyTask],
        summary: 'Revise the plan.',
        rationale: 'Keep bounded work actionable.',
        criteria: [criterion],
        milestones: project.milestones,
        tasks: const [],
        createdAt: DateTime(2026, 1, 2),
      );
      final pending = await service.prepareAndApply(
        project: project,
        proposal: desired,
        workspaceRoot: workspace.path,
      );

      expect(pending.awaitingApproval, isTrue);
      expect(
        pending
            .project
            .pendingPlanApproval
            ?.desiredPlan
            ?.criteria
            .single
            .statement,
        criterion.statement,
      );
      expect(
        pending.project.criteria.single.statement,
        project.criteria.single.statement,
      );
      final approved = service.approvePending(
        project: pending.project,
        workspaceRoot: workspace.path,
      );
      expect(approved.project.criteria.single.statement, criterion.statement);
      expect(approved.project.pendingPlanApproval, isNull);
      expect(approved.project.planHistory, hasLength(2));
    },
  );

  test(
    'stales accepted and proposed evidence when a criterion contract changes',
    () async {
      final task = _task('existing');
      final project = _project([task]).copyWith(
        evidence: [
          ProjectEvidence(
            id: 'evidence_accepted',
            type: ProjectEvidenceType.taskClaim,
            criterionIds: const ['criterion_001'],
            expectationIds: const ['expect_task'],
            projectTaskId: task.id,
            sourceRef: 'run_1',
            summary: 'The old contract was satisfied.',
            status: ProjectEvidenceStatus.accepted,
            createdAt: DateTime(2026, 1, 1),
          ),
          ProjectEvidence(
            id: 'evidence_proposed',
            type: ProjectEvidenceType.taskClaim,
            criterionIds: const ['criterion_001'],
            expectationIds: const ['expect_task'],
            projectTaskId: task.id,
            sourceRef: 'run_2',
            summary: 'A second old-contract claim.',
            status: ProjectEvidenceStatus.proposed,
            createdAt: DateTime(2026, 1, 1),
          ),
        ],
      );
      final revisedCriterion = project.criteria.single.copyWith(
        statement: 'The materially revised outcome is verified.',
      );
      final result = await service.prepareAndApply(
        project: project,
        proposal: _desired(project, [task], criteria: [revisedCriterion]),
        workspaceRoot: workspace.path,
        approvalPolicy: ProjectPlanApprovalPolicy.never,
      );

      expect(result.changed, isTrue);
      expect(
        result.project.evidence.map((item) => item.status),
        everyElement(ProjectEvidenceStatus.stale),
      );
      expect(
        result.project.evidence.map((item) => item.details['staleReason']),
        everyElement('criterion_contract_changed'),
      );
      expect(
        result.project.evidence.map((item) => item.details['staleRevision']),
        everyElement(2),
      );
      final evaluated = const ProjectCriterionEvaluator()
          .evaluateDeterministically(
            result.project,
            evaluatedAt: DateTime(2026, 1, 3),
          );
      expect(
        evaluated.criteria.single.status,
        ProjectCriterionStatus.unsatisfied,
      );
    },
  );
}

ProjectState _project(
  List<ProjectTask> tasks, {
  String? activeTaskId,
  List<ProjectMilestone> milestones = const [],
  List<ProjectMemoryEntry> memory = const [],
  List<PendingProjectQuestion> openQuestions = const [],
}) {
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
    constraints: const [],
    tasks: tasks,
    milestones: milestones,
    memory: memory,
    openQuestions: openQuestions,
    status: ProjectStatus.active,
    activeTaskId: activeTaskId,
    createdAt: now,
    updatedAt: now,
  );
}

ProjectDesiredPlan _desired(
  ProjectState project,
  List<ProjectTask> tasks, {
  List<ProjectCriterion>? criteria,
  List<ProjectMilestone>? milestones,
  List<PendingProjectQuestion>? openQuestions,
  List<ProjectMemoryEntry> memoryAdditions = const [],
  List<ProjectMemorySupersession> memorySupersessions = const [],
  List<String> deferredTaskIds = const [],
  List<String> obsoleteTaskIds = const [],
  bool requiresApproval = false,
}) {
  return ProjectDesiredPlan(
    revision: project.nextRevision,
    triggers: const [ProjectPlanRevisionTrigger.noReadyTask],
    summary: 'Revise the plan.',
    rationale: 'Keep bounded work actionable.',
    criteria: criteria ?? project.criteria,
    milestones: milestones ?? project.milestones,
    tasks: tasks,
    deferredTaskIds: deferredTaskIds,
    obsoleteTaskIds: obsoleteTaskIds,
    memoryAdditions: memoryAdditions,
    memorySupersessions: memorySupersessions,
    openQuestions: openQuestions ?? project.openQuestions,
    requiresApproval: requiresApproval,
    createdAt: DateTime(2026, 1, 2),
  );
}

ProjectTask _task(
  String id, {
  List<String> dependencies = const [],
  List<String> writePaths = const ['lib/feature.dart'],
  List<ProjectEvidenceExpectation>? expectedEvidence,
  List<ProjectArtifact> expectedArtifacts = const [],
  String selectionRationale = '',
  ProjectTaskStatus status = ProjectTaskStatus.queued,
}) {
  final now = DateTime(2026, 1, 2);
  final objective = 'Implement bounded slice $id.';
  return ProjectTask(
    id: id,
    title: 'Bounded slice $id',
    objective: objective,
    criterionIds: const ['criterion_001'],
    dependsOnTaskIds: dependencies,
    selectionRationale: selectionRationale,
    expectedEvidence:
        expectedEvidence ??
        const [
          ProjectEvidenceExpectation(
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
    status: status,
    taskDocumentId: null,
    fingerprint: projectTaskFingerprint(objective, const ['criterion_001']),
    rejectionReason: null,
    createdAt: now,
    updatedAt: now,
  );
}

ProjectMilestone _milestone(
  String id, {
  ProjectMilestoneStatus status = ProjectMilestoneStatus.planned,
  DateTime? completedAt,
  int order = 1,
}) {
  final now = DateTime(2026, 1, 1);
  return ProjectMilestone(
    id: id,
    title: 'Milestone $id',
    objective: 'Complete $id.',
    criterionIds: const ['criterion_001'],
    status: status,
    exitConditions: const ['The milestone outcome is verified.'],
    order: order,
    createdAt: now,
    updatedAt: now,
    completedAt: completedAt,
  );
}

ProjectMemoryEntry _memory(String id) {
  final now = DateTime(2026, 1, 1);
  return ProjectMemoryEntry(
    id: id,
    kind: ProjectMemoryKind.fact,
    content: 'Memory content for $id.',
    sourceType: ProjectMemorySourceType.planner,
    confidence: ProjectMemoryConfidence.inferred,
    createdAt: now,
    updatedAt: now,
  );
}
