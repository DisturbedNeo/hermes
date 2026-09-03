import 'package:hermes/core/helpers/uuid.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/services/project_system/project_memory_service.dart';
import 'package:hermes/core/services/project_system/project_plan_validator.dart';

typedef ProjectPlanRepair =
    Future<ProjectPlanProposal?> Function(
      ProjectPlanProposal proposal,
      ProjectPlanValidationResult validation,
    );

class ProjectPlanRevisionResult {
  final ProjectState project;
  final ProjectPlanValidationResult validation;
  final bool repairAttempted;
  final bool changed;
  final bool awaitingApproval;

  const ProjectPlanRevisionResult({
    required this.project,
    required this.validation,
    required this.repairAttempted,
    required this.changed,
    required this.awaitingApproval,
  });
}

/// Owns validation, the single repair pass, approval routing, and atomic apply.
class ProjectPlanRevisionService {
  const ProjectPlanRevisionService({
    ProjectPlanValidator validator = const ProjectPlanValidator(),
  }) : _validator = validator;

  final ProjectPlanValidator _validator;
  static const ProjectMemoryService _memoryService = ProjectMemoryService();

  Future<ProjectPlanRevisionResult> prepareAndApply({
    required ProjectState project,
    required ProjectPlanProposal proposal,
    required String workspaceRoot,
    ProjectPlanApprovalPolicy approvalPolicy =
        ProjectPlanApprovalPolicy.highRiskOnly,
    ProjectPlanRepair? repair,
  }) async {
    var candidate = proposal;
    var validation = _validator.validate(
      project: project,
      proposal: candidate,
      workspaceRoot: workspaceRoot,
    );
    var repairAttempted = false;
    if (!validation.valid && repair != null) {
      repairAttempted = true;
      final repaired = await repair(candidate, validation);
      if (repaired != null) {
        candidate = repaired;
        validation = _validator.validate(
          project: project,
          proposal: candidate,
          workspaceRoot: workspaceRoot,
        );
      }
    }
    if (!validation.valid) {
      final codes = validation.errors
          .map((item) => item.code)
          .toSet()
          .join(', ');
      final blocked = project.copyWith(
        pendingReplanTriggers: const [],
        status: ProjectStatus.blocked,
        phase: ProjectPhase.planning,
        blocker: ProjectBlocker(
          type: ProjectBlockerType.validation,
          message:
              'Plan revision ${candidate.revision} was rejected after validation${repairAttempted ? ' and one repair pass' : ''}. Resolve: $codes.',
          createdAt: DateTime.now(),
        ),
        updatedAt: DateTime.now(),
      );
      return ProjectPlanRevisionResult(
        project: blocked,
        validation: validation,
        repairAttempted: repairAttempted,
        changed: false,
        awaitingApproval: false,
      );
    }

    final preview = _apply(
      project: project,
      proposal: candidate,
      validation: validation,
      approver: ProjectPlanRevisionApprover.automatic,
      recordRevision: false,
    );
    if (!_planChanged(project, preview)) {
      return ProjectPlanRevisionResult(
        project: project.copyWith(
          pendingReplanTriggers: const [],
          updatedAt: DateTime.now(),
        ),
        validation: validation,
        repairAttempted: repairAttempted,
        changed: false,
        awaitingApproval: false,
      );
    }

    final highRiskChanges = _highRiskChanges(candidate);
    final requiresApproval = switch (approvalPolicy) {
      ProjectPlanApprovalPolicy.never => false,
      ProjectPlanApprovalPolicy.everyRevision => true,
      ProjectPlanApprovalPolicy.highRiskOnly =>
        candidate.requiresApproval || highRiskChanges.isNotEmpty,
    };
    if (requiresApproval) {
      final reason = candidate.approvalReason.trim().isNotEmpty
          ? candidate.approvalReason.trim()
          : highRiskChanges.isEmpty
          ? 'The current policy requires approval for every revision.'
          : 'The revision contains high-risk plan changes.';
      final pending = PendingProjectPlanApproval(
        revision: candidate.revision,
        reason: reason,
        summary: candidate.summary,
        highRiskChanges: highRiskChanges,
        createdAt: candidate.createdAt,
        proposal: candidate,
      );
      return ProjectPlanRevisionResult(
        project: project.copyWith(
          pendingPlanApproval: pending,
          pendingReplanTriggers: const [],
          status: ProjectStatus.paused,
          phase: ProjectPhase.planning,
          blocker: ProjectBlocker(
            type: ProjectBlockerType.planApproval,
            message: reason,
            createdAt: DateTime.now(),
          ),
          updatedAt: DateTime.now(),
        ),
        validation: validation,
        repairAttempted: repairAttempted,
        changed: false,
        awaitingApproval: true,
      );
    }

    return ProjectPlanRevisionResult(
      project: _apply(
        project: project,
        proposal: candidate,
        validation: validation,
        approver: ProjectPlanRevisionApprover.automatic,
      ),
      validation: validation,
      repairAttempted: repairAttempted,
      changed: true,
      awaitingApproval: false,
    );
  }

  ProjectPlanRevisionResult approvePending({
    required ProjectState project,
    required String workspaceRoot,
  }) {
    final proposal = project.pendingPlanApproval?.proposal;
    if (proposal == null) {
      return ProjectPlanRevisionResult(
        project: project,
        validation: const ProjectPlanValidationResult([]),
        repairAttempted: false,
        changed: false,
        awaitingApproval: false,
      );
    }
    final validation = _validator.validate(
      project: project,
      proposal: proposal,
      workspaceRoot: workspaceRoot,
    );
    if (!validation.valid) {
      return ProjectPlanRevisionResult(
        project: project.copyWith(
          pendingPlanApproval: null,
          status: ProjectStatus.blocked,
          blocker: ProjectBlocker(
            type: ProjectBlockerType.validation,
            message:
                'The pending plan no longer validates against current state.',
            createdAt: DateTime.now(),
          ),
          updatedAt: DateTime.now(),
        ),
        validation: validation,
        repairAttempted: false,
        changed: false,
        awaitingApproval: false,
      );
    }
    return ProjectPlanRevisionResult(
      project: _apply(
        project: project,
        proposal: proposal,
        validation: validation,
        approver: ProjectPlanRevisionApprover.user,
      ),
      validation: validation,
      repairAttempted: false,
      changed: true,
      awaitingApproval: false,
    );
  }

  ProjectState _apply({
    required ProjectState project,
    required ProjectPlanProposal proposal,
    required ProjectPlanValidationResult validation,
    required ProjectPlanRevisionApprover approver,
    bool recordRevision = true,
  }) {
    final now = DateTime.now();
    var evidence = [...project.evidence];
    final criterionById = {for (final item in project.criteria) item.id: item};
    for (final proposed in proposal.criterionUpserts) {
      final existing = criterionById[proposed.id];
      if (existing == null) {
        criterionById[proposed.id] = ProjectCriterion(
          id: proposed.id,
          statement: proposed.statement,
          required: proposed.required,
          verificationMode: proposed.verificationMode,
          notes: proposed.notes,
          createdAt: now,
          updatedAt: now,
        );
        continue;
      }
      final contractChanged =
          existing.statement.trim() != proposed.statement.trim() ||
          existing.verificationMode != proposed.verificationMode;
      if (contractChanged) {
        evidence = [
          for (final item in evidence)
            if (item.criterionIds.contains(existing.id) &&
                (item.status == ProjectEvidenceStatus.accepted ||
                    item.status == ProjectEvidenceStatus.proposed))
              item.copyWith(
                status: ProjectEvidenceStatus.stale,
                details: {
                  ...item.details,
                  'staleReason': 'criterion_contract_changed',
                  'staleRevision': proposal.revision,
                },
                evaluatedAt: now,
              )
            else
              item,
        ];
      }
      criterionById[proposed.id] = existing.copyWith(
        statement: proposed.statement,
        required: proposed.required,
        status: contractChanged
            ? ProjectCriterionStatus.unsatisfied
            : existing.status,
        verificationMode: proposed.verificationMode,
        evidenceIds: contractChanged ? const [] : existing.evidenceIds,
        notes: proposed.notes.trim().isNotEmpty
            ? proposed.notes
            : contractChanged
            ? 'Criterion contract changed in revision ${proposal.revision}; previous evidence must be revalidated.'
            : existing.notes,
        updatedAt: now,
        verifiedAt: contractChanged ? null : existing.verifiedAt,
      );
    }
    for (final id in proposal.removedCriterionIds) {
      final existing = criterionById[id];
      if (existing != null) {
        criterionById[id] = existing.copyWith(
          status: ProjectCriterionStatus.invalidated,
          notes:
              'Invalidated by plan revision ${proposal.revision}: ${proposal.rationale}',
          updatedAt: now,
          verifiedAt: null,
        );
      }
    }

    final milestoneById = {
      for (final item in project.milestones) item.id: item,
    };
    for (final proposed in proposal.milestoneUpserts) {
      final existing = milestoneById[proposed.id];
      milestoneById[proposed.id] = ProjectMilestone(
        id: proposed.id,
        title: proposed.title,
        objective: proposed.objective,
        criterionIds: proposed.criterionIds,
        status: existing?.status ?? ProjectMilestoneStatus.planned,
        exitConditions: proposed.exitConditions,
        taskIds: proposed.taskIds,
        order: proposed.order,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
        completedAt: existing?.completedAt,
      );
    }
    for (final id in proposal.removedMilestoneIds) {
      final existing = milestoneById[id];
      if (existing != null) {
        milestoneById[id] = ProjectMilestone(
          id: existing.id,
          title: existing.title,
          objective: existing.objective,
          criterionIds: existing.criterionIds,
          status: ProjectMilestoneStatus.cancelled,
          exitConditions: existing.exitConditions,
          taskIds: existing.taskIds,
          order: existing.order,
          createdAt: existing.createdAt,
          updatedAt: now,
          completedAt: existing.completedAt,
        );
      }
    }

    final backlogById = {for (final item in project.backlog) item.id: item};
    for (final proposed in proposal.taskUpdates) {
      final existing = backlogById[proposed.id];
      if (existing != null) {
        backlogById[proposed.id] = _mergeTask(
          existing,
          proposed,
          proposal.revision,
          now,
        );
      }
    }
    for (final proposed in proposal.taskAdditions) {
      backlogById[proposed.id] = proposed.copyWith(
        status: proposed.status == ProjectTaskStatus.deferred
            ? ProjectTaskStatus.deferred
            : ProjectTaskStatus.queued,
        taskDocumentId: null,
        recoveryIncidentId: null,
        rejectionReason: null,
        failure: null,
        revisionIntroduced: proposal.revision,
        revisionUpdated: proposal.revision,
        createdAt: now,
        updatedAt: now,
      );
    }
    for (final id in proposal.deferredTaskIds) {
      final task = backlogById[id];
      if (task != null) {
        backlogById[id] = task.copyWith(
          status: ProjectTaskStatus.deferred,
          readiness: ProjectTaskReadiness.notEligible,
          readinessReasons: ['Deferred by plan revision ${proposal.revision}.'],
          revisionUpdated: proposal.revision,
          updatedAt: now,
        );
      }
    }
    for (final id in proposal.obsoleteTaskIds) {
      final task = backlogById[id];
      if (task != null) {
        backlogById[id] = task.copyWith(
          status: ProjectTaskStatus.obsolete,
          readiness: ProjectTaskReadiness.notEligible,
          readinessReasons: [
            'Made obsolete by plan revision ${proposal.revision}.',
          ],
          revisionUpdated: proposal.revision,
          updatedAt: now,
        );
      }
    }

    var memoryProject = project;
    for (final proposed in proposal.memoryAdditions) {
      memoryProject = _memoryService
          .record(
            project: memoryProject,
            id: proposed.id,
            kind: proposed.kind,
            content: proposed.content,
            sourceType: ProjectMemorySourceType.planner,
            sourceId: proposed.sourceId,
            confidence: proposed.confidence,
            protected:
                proposed.protected ||
                proposed.kind == ProjectMemoryKind.requirement ||
                proposed.kind == ProjectMemoryKind.decision ||
                proposed.kind == ProjectMemoryKind.risk,
            deduplicate: false,
            timestamp: now,
          )
          .project;
    }
    for (var index = 0; index < proposal.assumptions.length; index++) {
      final content = proposal.assumptions[index].trim();
      if (content.isEmpty ||
          memoryProject.memory.any(
            (item) => item.active && item.content.trim() == content,
          )) {
        continue;
      }
      memoryProject = _memoryService
          .record(
            project: memoryProject,
            id: 'memory_r${proposal.revision}_${index + 1}',
            kind: ProjectMemoryKind.assumption,
            content: content,
            sourceType: ProjectMemorySourceType.planner,
            sourceId: 'revision_${proposal.revision}',
            confidence: ProjectMemoryConfidence.inferred,
            timestamp: now,
          )
          .project;
    }
    for (final edit in proposal.memorySupersessions) {
      memoryProject = _memoryService.supersede(
        project: memoryProject,
        replacementEntryId: edit.supersededById,
        coveredEntryIds: [edit.entryId],
        timestamp: now,
      );
    }
    if (recordRevision) {
      memoryProject = _memoryService
          .record(
            project: memoryProject,
            id: 'memory_revision_${proposal.revision}',
            kind: ProjectMemoryKind.decision,
            content:
                'Applied plan revision ${proposal.revision}: ${proposal.summary}\nRationale: ${proposal.rationale}',
            sourceType: ProjectMemorySourceType.planner,
            sourceId: 'revision_${proposal.revision}',
            confidence: ProjectMemoryConfidence.confirmed,
            protected: true,
            timestamp: now,
          )
          .project;
    }

    final questions = <PendingProjectQuestion>[
      ...project.openQuestions,
      for (final question in proposal.openQuestions)
        if (!project.openQuestions.any((item) => item.id == question.id))
          question,
    ];
    final criterionChanges = <String>[
      ...proposal.criterionUpserts.map((item) => 'upsert:${item.id}'),
      ...proposal.removedCriterionIds.map((id) => 'invalidate:$id'),
    ];
    final milestoneChanges = <String>[
      ...proposal.milestoneUpserts.map((item) => 'upsert:${item.id}'),
      ...proposal.removedMilestoneIds.map((id) => 'cancel:$id'),
    ];
    final warnings = validation.warnings
        .map((item) => '${item.code}: ${item.message}')
        .toList();
    final revision = ProjectPlanRevision(
      revision: proposal.revision,
      trigger:
          proposal.triggers.firstOrNull ?? ProjectPlanRevisionTrigger.manual,
      summary: proposal.summary,
      rationale: proposal.triggers.length <= 1
          ? proposal.rationale
          : '${proposal.rationale}\nTriggers: ${proposal.triggers.map((item) => item.name).join(', ')}',
      addedTaskIds: proposal.taskAdditions.map((item) => item.id).toList(),
      updatedTaskIds: proposal.taskUpdates.map((item) => item.id).toList(),
      removedTaskIds: [
        ...proposal.deferredTaskIds,
        ...proposal.obsoleteTaskIds,
      ],
      criterionChanges: criterionChanges,
      milestoneChanges: milestoneChanges,
      validationWarnings: warnings,
      createdAt: proposal.createdAt,
      approvedAt: now,
      approvedBy: approver,
    );

    return project.copyWith(
      criteria: criterionById.values.toList(),
      evidence: evidence,
      milestones: milestoneById.values.toList()
        ..sort((a, b) => a.order.compareTo(b.order)),
      backlog: backlogById.values.toList(),
      memory: memoryProject.memory,
      openQuestions: questions,
      currentRevision: recordRevision
          ? proposal.revision
          : project.currentRevision,
      planHistory: recordRevision
          ? [...project.planHistory, revision]
          : project.planHistory,
      pendingPlanApproval: null,
      pendingReplanTriggers: const [],
      status: questions.isEmpty
          ? ProjectStatus.active
          : ProjectStatus.waitingForUser,
      phase: ProjectPhase.planning,
      blocker: questions.isEmpty
          ? null
          : ProjectBlocker(
              type: ProjectBlockerType.question,
              message: questions.first.question,
              createdAt: now,
            ),
      decisions: recordRevision
          ? [
              ...project.decisions,
              ProjectDecisionRecord(
                id: 'decision_${uuid.v7()}',
                decision: approver == ProjectPlanRevisionApprover.user
                    ? ProjectDecisionType.approvePlanRevision
                    : ProjectDecisionType.applyPlanRevision,
                summary: proposal.summary,
                memoryUpdate: proposal.rationale,
                createdAt: now,
              ),
            ]
          : project.decisions,
      updatedAt: now,
    );
  }

  static ProjectTask _mergeTask(
    ProjectTask existing,
    ProjectTask proposed,
    int revision,
    DateTime now,
  ) {
    return existing.copyWith(
      title: proposed.title,
      objective: proposed.objective,
      criterionIds: proposed.criterionIds,
      milestoneId: proposed.milestoneId,
      dependsOnTaskIds: proposed.dependsOnTaskIds,
      priority: proposed.priority,
      risk: proposed.risk,
      riskReduction: proposed.riskReduction,
      effort: proposed.effort,
      readiness: proposed.readiness,
      readinessReasons: proposed.readinessReasons,
      selectionRationale: proposed.selectionRationale,
      revisionUpdated: revision,
      expectedEvidence: proposed.expectedEvidence,
      readPaths: proposed.readPaths,
      writePaths: proposed.writePaths,
      doneCriteria: proposed.doneCriteria,
      outOfScope: proposed.outOfScope,
      context: proposed.context,
      expectedArtifacts: proposed.expectedArtifacts,
      fingerprint: proposed.fingerprint,
      updatedAt: now,
    );
  }

  static bool _planChanged(ProjectState before, ProjectState after) {
    return _criterionSignature(before.criteria) !=
            _criterionSignature(after.criteria) ||
        _milestoneSignature(before.milestones) !=
            _milestoneSignature(after.milestones) ||
        _taskSignature(before.backlog) != _taskSignature(after.backlog) ||
        _memorySignature(before.memory) != _memorySignature(after.memory) ||
        before.openQuestions.map((item) => item.id).join('|') !=
            after.openQuestions.map((item) => item.id).join('|');
  }

  static String _criterionSignature(
    List<ProjectCriterion> items,
  ) => ([...items]..sort((a, b) => a.id.compareTo(b.id)))
      .map((item) {
        return '${item.id}|${item.statement}|${item.required}|${item.status.name}|${item.verificationMode.name}|${item.evidenceIds.join(',')}|${item.notes}';
      })
      .join('||');

  static String _milestoneSignature(
    List<ProjectMilestone> items,
  ) => ([...items]..sort((a, b) => a.id.compareTo(b.id)))
      .map((item) {
        return '${item.id}|${item.title}|${item.objective}|${item.criterionIds.join(',')}|${item.status.name}|${item.exitConditions.join(',')}|${item.taskIds.join(',')}|${item.order}';
      })
      .join('||');

  static String _taskSignature(
    List<ProjectTask> items,
  ) => ([...items]..sort((a, b) => a.id.compareTo(b.id)))
      .map((item) {
        final expectations = item.expectedEvidence
            .map(
              (expectation) =>
                  '${expectation.id}:${expectation.type.name}:${expectation.criterionIds.join(',')}:${expectation.description}:${expectation.required}:${expectation.sourceRef}:${expectation.details}',
            )
            .join(';');
        final artifacts = item.expectedArtifacts
            .map(
              (artifact) =>
                  '${artifact.id}:${artifact.path}:${artifact.description}:${artifact.kind}',
            )
            .join(';');
        return '${item.id}|${item.title}|${item.objective}|${item.criterionIds.join(',')}|${item.milestoneId}|${item.dependsOnTaskIds.join(',')}|${item.priority.name}|${item.risk.name}|${item.riskReduction.name}|${item.effort.name}|${item.status.name}|${item.doneCriteria.join(',')}|${item.outOfScope.join(',')}|${item.context.join(',')}|$expectations|$artifacts|${item.readPaths.join(',')}|${item.writePaths.join(',')}';
      })
      .join('||');

  static String _memorySignature(
    List<ProjectMemoryEntry> items,
  ) => ([...items]..sort((a, b) => a.id.compareTo(b.id)))
      .map(
        (item) =>
            '${item.id}|${item.kind.name}|${item.content}|${item.sourceType.name}|${item.sourceId}|${item.confidence.name}|${item.protected}|${item.active}|${item.supersedesId}|${item.coveredEntryIds.join(',')}',
      )
      .join('||');

  static List<String> _highRiskChanges(ProjectPlanProposal proposal) {
    final changes = <String>[];
    if (proposal.criterionUpserts.isNotEmpty ||
        proposal.removedCriterionIds.isNotEmpty) {
      changes.add('Success criteria or their verification policy changes.');
    }
    if (proposal.removedMilestoneIds.isNotEmpty ||
        proposal.obsoleteTaskIds.isNotEmpty) {
      changes.add('Previously planned scope is removed or made obsolete.');
    }
    for (final task in [...proposal.taskAdditions, ...proposal.taskUpdates]) {
      if (task.risk == ProjectTaskRisk.high) {
        changes.add('High-risk task: ${task.title}.');
      }
      final destructive =
          '${task.title} ${task.objective} ${task.writePaths.join(' ')}';
      if (RegExp(
        r'\b(delete|drop|destroy|publish|deploy|release|migrate production)\b',
        caseSensitive: false,
      ).hasMatch(destructive)) {
        changes.add(
          'Potentially destructive or externally visible task: ${task.title}.',
        );
      }
    }
    return changes.toSet().toList();
  }
}
