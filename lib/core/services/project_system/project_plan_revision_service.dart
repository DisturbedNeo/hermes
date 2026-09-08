import 'dart:convert';

import 'package:hermes/core/helpers/uuid.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/services/project_system/project_memory_service.dart';
import 'package:hermes/core/services/project_system/project_plan_validator.dart';

typedef ProjectPlanRepair =
    Future<ProjectDesiredPlan?> Function(
      ProjectDesiredPlan plan,
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

/// Validates, approves, and deterministically reconciles complete desired plans.
class ProjectPlanRevisionService {
  const ProjectPlanRevisionService({
    ProjectPlanValidator validator = const ProjectPlanValidator(),
  }) : _validator = validator;

  final ProjectPlanValidator _validator;
  static const ProjectMemoryService _memoryService = ProjectMemoryService();

  Future<ProjectPlanRevisionResult> prepareAndApply({
    required ProjectState project,
    required ProjectDesiredPlan proposal,
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
      return ProjectPlanRevisionResult(
        project: project.copyWith(
          pendingReplanTriggers: const [],
          status: ProjectStatus.blocked,
          blocker: ProjectBlocker(
            type: ProjectBlockerType.validation,
            message:
                'Plan revision ${candidate.revision} was rejected after validation${repairAttempted ? ' and one repair pass' : ''}. Resolve: $codes.',
            createdAt: DateTime.now(),
          ),
          updatedAt: DateTime.now(),
        ),
        validation: validation,
        repairAttempted: repairAttempted,
        changed: false,
        awaitingApproval: false,
      );
    }

    late final ProjectState preview;
    try {
      preview = _apply(
        project: project,
        proposal: candidate,
        validation: validation,
        approver: ProjectPlanRevisionApprover.automatic,
        recordRevision: false,
      );
    } on ArgumentError catch (error) {
      return _reconciliationFailure(
        project: project,
        validation: validation,
        repairAttempted: repairAttempted,
        revision: candidate.revision,
        error: error,
      );
    } on StateError catch (error) {
      return _reconciliationFailure(
        project: project,
        validation: validation,
        repairAttempted: repairAttempted,
        revision: candidate.revision,
        error: error,
      );
    }
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

    final highRiskReasons = _highRiskReasons(project, candidate);
    final highRiskChanges = highRiskReasons
        .map((item) => item.message)
        .toList();
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
      return ProjectPlanRevisionResult(
        project: project.copyWith(
          pendingPlanApproval: PendingProjectPlanApproval(
            revision: candidate.revision,
            reason: reason,
            summary: candidate.summary,
            highRiskChanges: highRiskChanges,
            highRiskReasonCodes: highRiskReasons
                .map((item) => item.code)
                .toList(),
            createdAt: candidate.createdAt,
            desiredPlan: candidate,
          ),
          pendingReplanTriggers: const [],
          status: ProjectStatus.paused,
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

    try {
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
    } on ArgumentError catch (error) {
      return _reconciliationFailure(
        project: project,
        validation: validation,
        repairAttempted: repairAttempted,
        revision: candidate.revision,
        error: error,
      );
    } on StateError catch (error) {
      return _reconciliationFailure(
        project: project,
        validation: validation,
        repairAttempted: repairAttempted,
        revision: candidate.revision,
        error: error,
      );
    }
  }

  ProjectPlanRevisionResult approvePending({
    required ProjectState project,
    required String workspaceRoot,
  }) {
    final proposal = project.pendingPlanApproval?.desiredPlan;
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
    try {
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
    } on ArgumentError catch (error) {
      return _reconciliationFailure(
        project: project.copyWith(pendingPlanApproval: null),
        validation: validation,
        repairAttempted: false,
        revision: proposal.revision,
        error: error,
      );
    } on StateError catch (error) {
      return _reconciliationFailure(
        project: project.copyWith(pendingPlanApproval: null),
        validation: validation,
        repairAttempted: false,
        revision: proposal.revision,
        error: error,
      );
    }
  }

  ProjectState _apply({
    required ProjectState project,
    required ProjectDesiredPlan proposal,
    required ProjectPlanValidationResult validation,
    required ProjectPlanRevisionApprover approver,
    bool recordRevision = true,
  }) {
    final now = DateTime.now();
    final existingCriteria = {
      for (final item in project.criteria) item.id: item,
    };
    final desiredCriteria = <String, ProjectCriterion>{};
    final contractChangedCriterionIds = <String>{};
    for (final desired in proposal.criteria) {
      final existing = existingCriteria[desired.id];
      if (existing == null) {
        desiredCriteria[desired.id] = desired.copyWith(
          status: ProjectCriterionStatus.unsatisfied,
          verifiedAt: null,
          createdAt: now,
          updatedAt: now,
        );
        continue;
      }
      final contractChanged =
          existing.statement.trim() != desired.statement.trim() ||
          existing.required != desired.required ||
          existing.verificationMode != desired.verificationMode;
      if (contractChanged) contractChangedCriterionIds.add(desired.id);
      desiredCriteria[desired.id] = existing.copyWith(
        statement: desired.statement,
        required: desired.required,
        verificationMode: desired.verificationMode,
        status: contractChanged
            ? ProjectCriterionStatus.unsatisfied
            : existing.status,
        notes: contractChanged
            ? 'Criterion contract changed in revision ${proposal.revision}; previous evidence must be revalidated.'
            : desired.notes.trim().isNotEmpty
            ? desired.notes
            : existing.notes,
        updatedAt: now,
        verifiedAt: contractChanged ? null : existing.verifiedAt,
      );
    }
    for (final existing in project.criteria) {
      if (!desiredCriteria.containsKey(existing.id)) {
        desiredCriteria[existing.id] = existing.copyWith(
          status: ProjectCriterionStatus.invalidated,
          notes: 'Invalidated by plan revision ${proposal.revision}.',
          updatedAt: now,
          verifiedAt: null,
        );
      }
    }

    final existingMilestones = {
      for (final item in project.milestones) item.id: item,
    };
    final desiredMilestones = <String, ProjectMilestone>{};
    for (final desired in proposal.milestones) {
      final existing = existingMilestones[desired.id];
      if (existing?.status == ProjectMilestoneStatus.completed) {
        desiredMilestones[desired.id] = existing!;
        continue;
      }
      desiredMilestones[desired.id] = ProjectMilestone(
        id: desired.id,
        title: desired.title,
        objective: desired.objective,
        criterionIds: desired.criterionIds,
        status: existing?.status ?? ProjectMilestoneStatus.planned,
        exitConditions: desired.exitConditions,
        order: desired.order,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
        completedAt: existing?.completedAt,
      );
    }
    for (final existing in project.milestones) {
      if (!desiredMilestones.containsKey(existing.id)) {
        if (existing.status == ProjectMilestoneStatus.completed) {
          desiredMilestones[existing.id] = existing;
          continue;
        }
        desiredMilestones[existing.id] = ProjectMilestone(
          id: existing.id,
          title: existing.title,
          objective: existing.objective,
          criterionIds: existing.criterionIds,
          status: ProjectMilestoneStatus.cancelled,
          exitConditions: existing.exitConditions,
          order: existing.order,
          createdAt: existing.createdAt,
          updatedAt: now,
          completedAt: existing.completedAt,
        );
      }
    }

    final desiredById = {for (final task in proposal.tasks) task.id: task};
    final tasksById = <String, ProjectTask>{};
    for (final existing in project.tasks) {
      final desired = desiredById[existing.id];
      if (_preserveTask(existing)) {
        tasksById[existing.id] = existing;
      } else if (desired == null) {
        tasksById[existing.id] = existing.copyWith(
          status: proposal.deferredTaskIds.contains(existing.id)
              ? ProjectTaskStatus.deferred
              : ProjectTaskStatus.obsolete,
          revisionUpdated: proposal.revision,
          updatedAt: now,
        );
      } else {
        tasksById[existing.id] = _mergeTask(
          existing,
          desired,
          proposal.revision,
          now,
        ).copyWith(status: _desiredTaskStatus(proposal, desired));
      }
    }
    for (final desired in proposal.tasks) {
      if (tasksById.containsKey(desired.id)) continue;
      tasksById[desired.id] = desired.copyWith(
        status: _desiredTaskStatus(proposal, desired),
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
            confidence: ProjectMemoryConfidence.inferred,
            protected: false,
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
            sourceType: ProjectMemorySourceType.system,
            sourceId: 'revision_${proposal.revision}',
            confidence: ProjectMemoryConfidence.confirmed,
            protected: true,
            timestamp: now,
          )
          .project;
    }

    final revision = ProjectPlanRevision(
      revision: proposal.revision,
      trigger:
          proposal.triggers.firstOrNull ??
          ProjectPlanRevisionTrigger.noReadyTask,
      summary: proposal.summary,
      rationale: proposal.rationale,
      addedTaskIds: [
        for (final task in proposal.tasks)
          if (!project.tasks.any((existing) => existing.id == task.id)) task.id,
      ],
      updatedTaskIds: [
        for (final task in proposal.tasks)
          if (project.tasks.any((existing) => existing.id == task.id)) task.id,
      ],
      removedTaskIds: [
        for (final task in project.tasks)
          if (!_preserveTask(task) && !desiredById.containsKey(task.id))
            task.id,
      ],
      criterionChanges: _criterionChanges(project.criteria, proposal.criteria),
      milestoneChanges: _milestoneChanges(
        project.milestones,
        desiredMilestones.values.toList(),
      ),
      validationWarnings: validation.warnings
          .map((item) => '${item.code}: ${item.message}')
          .toList(),
      createdAt: proposal.createdAt,
      approvedAt: now,
      approvedBy: approver,
    );

    final questions = proposal.openQuestions;
    final revisedEvidence = project.evidence.map((item) {
      final linkedToChangedCriterion = item.criterionIds.any(
        contractChangedCriterionIds.contains,
      );
      if (linkedToChangedCriterion &&
          (item.status == ProjectEvidenceStatus.accepted ||
              item.status == ProjectEvidenceStatus.proposed)) {
        return item.copyWith(
          status: ProjectEvidenceStatus.stale,
          details: {
            ...item.details,
            'staleReason': 'criterion_contract_changed',
            'staleRevision': proposal.revision,
          },
          evaluatedAt: now,
        );
      }
      return item;
    }).toList();
    final normalizedMilestones = _normaliseMilestones(desiredMilestones.values);
    return project.copyWith(
      criteria: desiredCriteria.values.toList(),
      milestones: normalizedMilestones,
      tasks: tasksById.values.toList(),
      evidence: revisedEvidence,
      memory: memoryProject.memory,
      openQuestions: questions,
      planHistory: recordRevision
          ? [...project.planHistory, revision]
          : project.planHistory,
      pendingPlanApproval: null,
      pendingReplanTriggers: const [],
      status: questions.isEmpty
          ? ProjectStatus.active
          : ProjectStatus.waitingForUser,
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

  static ProjectTaskStatus _desiredTaskStatus(
    ProjectDesiredPlan proposal,
    ProjectTask task,
  ) {
    if (proposal.obsoleteTaskIds.contains(task.id)) {
      return ProjectTaskStatus.obsolete;
    }
    if (proposal.deferredTaskIds.contains(task.id)) {
      return ProjectTaskStatus.deferred;
    }
    return task.status == ProjectTaskStatus.deferred ||
            task.status == ProjectTaskStatus.obsolete
        ? task.status
        : ProjectTaskStatus.queued;
  }

  static List<ProjectMilestone> _normaliseMilestones(
    Iterable<ProjectMilestone> source,
  ) {
    final sorted = [...source]
      ..sort((a, b) {
        final order = a.order.compareTo(b.order);
        return order != 0 ? order : a.id.compareTo(b.id);
      });
    var activeAssigned = false;
    final normalized = <ProjectMilestone>[];
    for (final milestone in sorted) {
      if (milestone.status == ProjectMilestoneStatus.active) {
        if (activeAssigned) {
          normalized.add(
            _withMilestoneStatus(milestone, ProjectMilestoneStatus.planned),
          );
        } else {
          activeAssigned = true;
          normalized.add(milestone);
        }
        continue;
      }
      if (!activeAssigned &&
          milestone.status == ProjectMilestoneStatus.planned) {
        activeAssigned = true;
        normalized.add(
          _withMilestoneStatus(milestone, ProjectMilestoneStatus.active),
        );
        continue;
      }
      normalized.add(milestone);
    }
    return normalized;
  }

  static ProjectMilestone _withMilestoneStatus(
    ProjectMilestone milestone,
    ProjectMilestoneStatus status,
  ) => ProjectMilestone(
    id: milestone.id,
    title: milestone.title,
    objective: milestone.objective,
    criterionIds: milestone.criterionIds,
    status: status,
    exitConditions: milestone.exitConditions,
    order: milestone.order,
    createdAt: milestone.createdAt,
    updatedAt: milestone.updatedAt,
    completedAt: status == ProjectMilestoneStatus.completed
        ? milestone.completedAt
        : null,
  );

  static bool _preserveTask(ProjectTask task) =>
      task.status == ProjectTaskStatus.running ||
      task.status == ProjectTaskStatus.completed ||
      task.status == ProjectTaskStatus.failed ||
      task.status == ProjectTaskStatus.rejected ||
      task.status == ProjectTaskStatus.split ||
      task.status == ProjectTaskStatus.cancelled;

  static ProjectTask _mergeTask(
    ProjectTask existing,
    ProjectTask desired,
    int revision,
    DateTime now,
  ) {
    return existing.copyWith(
      title: desired.title,
      objective: desired.objective,
      criterionIds: desired.criterionIds,
      milestoneId: desired.milestoneId,
      dependsOnTaskIds: desired.dependsOnTaskIds,
      priority: desired.priority,
      risk: desired.risk,
      riskReduction: desired.riskReduction,
      effort: desired.effort,
      selectionRationale: desired.selectionRationale,
      revisionUpdated: revision,
      expectedEvidence: desired.expectedEvidence,
      readPaths: desired.readPaths,
      writePaths: desired.writePaths,
      legacyWriteAccess: desired.legacyWriteAccess,
      doneCriteria: desired.doneCriteria,
      outOfScope: desired.outOfScope,
      context: desired.context,
      expectedArtifacts: desired.expectedArtifacts,
      fingerprint: desired.fingerprint,
      updatedAt: now,
    );
  }

  static bool _planChanged(ProjectState before, ProjectState after) =>
      _criterionSignature(before.criteria) !=
          _criterionSignature(after.criteria) ||
      _milestoneSignature(before.milestones) !=
          _milestoneSignature(after.milestones) ||
      _taskSignature(before.tasks) != _taskSignature(after.tasks) ||
      _memorySignature(before.memory) != _memorySignature(after.memory) ||
      _questionSignature(before.openQuestions) !=
          _questionSignature(after.openQuestions);

  static String _criterionSignature(
    List<ProjectCriterion> items,
  ) => ([...items]..sort((a, b) => a.id.compareTo(b.id)))
      .map(
        (item) =>
            '${item.id}|${item.statement}|${item.required}|${item.status.name}|${item.verificationMode.name}|${item.notes}',
      )
      .join('||');

  static String _milestoneSignature(
    List<ProjectMilestone> items,
  ) => ([...items]..sort((a, b) => a.id.compareTo(b.id)))
      .map(
        (item) =>
            '${item.id}|${item.title}|${item.objective}|${item.criterionIds.join(',')}|${item.status.name}|${item.exitConditions.join(',')}|${item.order}|${item.completedAt?.toIso8601String() ?? ''}',
      )
      .join('||');

  static String _taskSignature(
    List<ProjectTask> items,
  ) => ([...items]..sort((a, b) => a.id.compareTo(b.id)))
      .map(
        (item) =>
            '${item.id}|${item.title}|${item.objective}|${item.criterionIds.join(',')}|${item.milestoneId}|${item.dependsOnTaskIds.join(',')}|${item.priority.name}|${item.risk.name}|${item.riskReduction.name}|${item.effort.name}|${item.selectionRationale}|${item.status.name}|${_evidenceSignature(item.expectedEvidence)}|${item.readPaths.join(',')}|${item.writePaths.join(',')}|${item.legacyWriteAccess}|${item.doneCriteria.join(',')}|${item.outOfScope.join(',')}|${item.context.join(',')}|${_artifactSignature(item.expectedArtifacts)}|${item.taskDocumentId}|${item.recoveryIncidentId}|${item.fingerprint}',
      )
      .join('||');

  static String _evidenceSignature(
    List<ProjectEvidenceExpectation> items,
  ) => items
      .map(
        (item) =>
            '${item.id}|${item.type.name}|${item.criterionIds.join(',')}|${item.description}|${item.required}|${item.sourceRef}|${_stableJson(item.details)}',
      )
      .join(';;');

  static String _artifactSignature(List<ProjectArtifact> items) => items
      .map(
        (item) =>
            '${item.id}|${item.projectTaskId}|${item.taskDocumentId}|${item.taskRunId}|${item.path}|${item.description}|${item.kind}',
      )
      .join(';;');

  static String _questionSignature(List<PendingProjectQuestion> items) =>
      items.map((item) => '${item.id}|${item.question}').join('||');

  static String _stableJson(Object? value) {
    Object? normalise(Object? current) {
      if (current is Map) {
        final keys = current.keys.map((key) => key.toString()).toList()..sort();
        return {for (final key in keys) key: normalise(current[key])};
      }
      if (current is Iterable) return current.map(normalise).toList();
      return current;
    }

    return jsonEncode(normalise(value));
  }

  static String _memorySignature(
    List<ProjectMemoryEntry> items,
  ) => ([...items]..sort((a, b) => a.id.compareTo(b.id)))
      .map(
        (item) =>
            '${item.id}|${item.kind.name}|${item.content}|${item.sourceType.name}|${item.sourceId}|${item.confidence.name}|${item.protected}|${item.active}|${item.supersedesId}|${item.coveredEntryIds.join(',')}',
      )
      .join('||');

  static List<String> _criterionChanges(
    List<ProjectCriterion> before,
    List<ProjectCriterion> after,
  ) => [
    for (final item in after)
      if (!before.any((old) => old.id == item.id))
        'add:${item.id}'
      else if (_criterionSignature([item]) !=
          _criterionSignature(
            before.where((old) => old.id == item.id).toList(),
          ))
        'update:${item.id}',
    for (final item in before)
      if (!after.any((current) => current.id == item.id)) 'remove:${item.id}',
  ];

  static List<String> _milestoneChanges(
    List<ProjectMilestone> before,
    List<ProjectMilestone> after,
  ) => [
    for (final item in after)
      if (!before.any((old) => old.id == item.id))
        'add:${item.id}'
      else if (_milestoneSignature([item]) !=
          _milestoneSignature(
            before.where((old) => old.id == item.id).toList(),
          ))
        'update:${item.id}',
    for (final item in before)
      if (!after.any((current) => current.id == item.id)) 'remove:${item.id}',
  ];

  static List<_ProjectPlanRiskReason> _highRiskReasons(
    ProjectState project,
    ProjectDesiredPlan proposal,
  ) {
    final changes = <_ProjectPlanRiskReason>[];
    final existingCriteria = {
      for (final criterion in project.criteria) criterion.id: criterion,
    };
    for (final criterion in proposal.criteria) {
      final existing = existingCriteria[criterion.id];
      if (existing == null ||
          existing.statement.trim() != criterion.statement.trim() ||
          existing.required != criterion.required ||
          existing.verificationMode != criterion.verificationMode) {
        changes.add(
          const _ProjectPlanRiskReason(
            'criterion_contract_changed',
            'Success criteria or their verification policy changes.',
          ),
        );
        break;
      }
    }
    final desiredIds = proposal.criteria.map((item) => item.id).toSet();
    if (project.criteria.any(
      (item) => item.required && !desiredIds.contains(item.id),
    )) {
      changes.add(
        const _ProjectPlanRiskReason(
          'required_criterion_removed',
          'A required success criterion is removed from the desired plan.',
        ),
      );
    }
    final desiredMilestoneIds = proposal.milestones
        .map((item) => item.id)
        .toSet();
    for (final milestone in project.milestones) {
      if (milestone.status != ProjectMilestoneStatus.completed &&
          !desiredMilestoneIds.contains(milestone.id)) {
        changes.add(
          _ProjectPlanRiskReason(
            'milestone_removed',
            'A nonterminal milestone is removed: ${milestone.title}.',
          ),
        );
      }
    }
    if (proposal.requiresApproval) {
      changes.add(
        _ProjectPlanRiskReason(
          'model_requested_approval',
          proposal.approvalReason.trim().isEmpty
              ? 'The planner explicitly requested approval.'
              : proposal.approvalReason.trim(),
        ),
      );
    }
    for (final task in proposal.tasks) {
      if (task.risk == ProjectTaskRisk.high) {
        changes.add(
          _ProjectPlanRiskReason(
            'high_risk_task',
            'High-risk task: ${task.title}.',
          ),
        );
      }
      final destructive =
          '${task.title} ${task.objective} ${task.writePaths.join(' ')}';
      if (RegExp(
        r'\b(delete|drop|destroy|publish|deploy|release|migrate production)\b',
        caseSensitive: false,
      ).hasMatch(destructive)) {
        changes.add(
          _ProjectPlanRiskReason(
            'destructive_or_external_task',
            'Potentially destructive or externally visible task: ${task.title}.',
          ),
        );
      }
    }
    final seen = <String>{};
    return [
      for (final item in changes)
        if (seen.add(item.code)) item,
    ];
  }

  ProjectPlanRevisionResult _reconciliationFailure({
    required ProjectState project,
    required ProjectPlanValidationResult validation,
    required bool repairAttempted,
    required int revision,
    required Object error,
  }) {
    final issue = ProjectPlanValidationIssue(
      code: 'reconciliation_failed',
      path: 'memory',
      message: 'Plan revision $revision could not be reconciled safely: $error',
    );
    final nextValidation = ProjectPlanValidationResult([
      ...validation.issues,
      issue,
    ]);
    return ProjectPlanRevisionResult(
      project: project.copyWith(
        status: ProjectStatus.blocked,
        blocker: ProjectBlocker(
          type: ProjectBlockerType.validation,
          message:
              'Plan revision $revision was rejected during reconciliation.',
          createdAt: DateTime.now(),
        ),
        updatedAt: DateTime.now(),
      ),
      validation: nextValidation,
      repairAttempted: repairAttempted,
      changed: false,
      awaitingApproval: false,
    );
  }
}

class _ProjectPlanRiskReason {
  final String code;
  final String message;

  const _ProjectPlanRiskReason(this.code, this.message);
}
