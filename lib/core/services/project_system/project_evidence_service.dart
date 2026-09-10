import 'dart:convert';

import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/models/task.dart';

/// Converts task output into durable, deduplicated Project evidence.
class ProjectEvidenceService {
  const ProjectEvidenceService();

  List<ProjectEvidence> normalizeTaskResult({
    required ProjectDocument project,
    required Task task,
    required TaskResult result,
    required DateTime evaluatedAt,
  }) {
    final additions = <ProjectEvidence>[
      ..._gateEvidence(project, task, result, evaluatedAt),
      ..._artifactEvidence(project, task, result, evaluatedAt),
      ..._claimEvidence(project, task, result, evaluatedAt),
    ];
    return _merge(project.evidence, additions);
  }

  List<ProjectEvidence> _gateEvidence(
    ProjectDocument project,
    Task task,
    TaskResult result,
    DateTime evaluatedAt,
  ) {
    final evidence = <ProjectEvidence>[];
    for (final gate in result.gateResults) {
      final type = _gateEvidenceType(gate);
      final sourceRef = _gateSourceRef(gate, type);
      final matchedExpectations = _matchingExpectations(
        task,
        type,
        sourceRefs: [sourceRef, gate.gateId],
      );
      evidence.add(
        ProjectEvidence(
          id: _evidenceId(
            '${task.id}|${result.taskId}|gate|${gate.gateId}|'
            '${result.finalRunId}|${gate.status.wire}|'
            '${gate.evaluatedAt.toIso8601String()}',
          ),
          type: type,
          criterionIds: _criterionIdsFor(
            project,
            task,
            type,
            matchedExpectations: matchedExpectations,
          ),
          expectationIds: _expectationIdsFor(matchedExpectations),
          taskId: task.id,
          runId: result.finalRunId,
          sourceRef: sourceRef,
          sourceFingerprint: _fingerprint({
            'taskId': task.id,
            'runId': result.finalRunId,
            'gateId': gate.gateId,
            'status': gate.status.wire,
            'summary': gate.summary,
            'expectationIds': _expectationIdsFor(matchedExpectations),
            'details': gate.details,
          }),
          summary: gate.summary.trim().isEmpty
              ? 'Gate ${gate.gateId} reported ${gate.status.wire}.'
              : gate.summary.trim(),
          status: switch (gate.status) {
            TaskGateStatus.passed ||
            TaskGateStatus.advisory => ProjectEvidenceStatus.accepted,
            TaskGateStatus.failed => ProjectEvidenceStatus.rejected,
            TaskGateStatus.pending => ProjectEvidenceStatus.proposed,
          },
          strength:
              gate.status == TaskGateStatus.passed &&
                  gate.details['required'] == true
              ? ProjectEvidenceStrength.conclusive
              : gate.status == TaskGateStatus.passed
              ? ProjectEvidenceStrength.supporting
              : ProjectEvidenceStrength.advisory,
          details: {
            ...gate.details,
            'gateId': gate.gateId,
            'gateStatus': gate.status.wire,
            if (gate.failureDisposition != null)
              'failureDisposition': gate.failureDisposition!.wire,
            if (result.finalRunId != null) 'runId': result.finalRunId,
          },
          createdAt: gate.evaluatedAt,
          evaluatedAt: gate.status == TaskGateStatus.pending
              ? null
              : evaluatedAt,
        ),
      );
    }
    return evidence;
  }

  List<ProjectEvidence> _artifactEvidence(
    ProjectDocument project,
    Task task,
    TaskResult result,
    DateTime evaluatedAt,
  ) {
    return [
      for (final artifact in result.artifacts)
        (() {
          final matchedExpectations = _matchingExpectations(
            task,
            ProjectEvidenceType.artifact,
            sourceRefs: [artifact.path],
          );
          return ProjectEvidence(
            id: _evidenceId(
              '${task.id}|${result.taskId}|artifact|'
              '${artifact.runId ?? ''}|${artifact.path}',
            ),
            type: ProjectEvidenceType.artifact,
            criterionIds: _criterionIdsFor(
              project,
              task,
              ProjectEvidenceType.artifact,
              matchedExpectations: matchedExpectations,
            ),
            expectationIds: _expectationIdsFor(matchedExpectations),
            taskId: task.id,
            runId: artifact.runId,
            sourceRef: artifact.path,
            sourceFingerprint: _fingerprint({
              'taskId': task.id,
              'runId': artifact.runId,
              'path': artifact.path,
              'description': artifact.description,
              'kind': artifact.kind,
              'expectationIds': _expectationIdsFor(matchedExpectations),
            }),
            summary: artifact.description?.trim().isEmpty ?? true
                ? 'Task produced ${artifact.path}.'
                : artifact.description!.trim(),
            status: ProjectEvidenceStatus.accepted,
            strength: ProjectEvidenceStrength.supporting,
            details: {
              'kind': artifact.kind,
              'artifactId': artifact.id,
              if (artifact.runId != null) 'runId': artifact.runId,
            },
            createdAt: artifact.createdAt ?? evaluatedAt,
            evaluatedAt: evaluatedAt,
          );
        })(),
    ];
  }

  List<ProjectEvidence> _claimEvidence(
    ProjectDocument project,
    Task task,
    TaskResult result,
    DateTime evaluatedAt,
  ) {
    final validCriterionIds = project.criteria.map((item) => item.id).toSet();
    final claims = <TaskEvidenceClaim>[
      ...result.evidenceClaims,
      if (result.status == TaskStatus.completed &&
          result.summary.trim().isNotEmpty)
        for (final criterionId in task.criterionIds)
          if (!result.evidenceClaims.any(
            (claim) => claim.criterionId == criterionId,
          ))
            TaskEvidenceClaim(
              criterionId: criterionId,
              claim: result.summary.trim(),
              sourceRef: result.taskId,
              expectationId: _uniqueClaimExpectationId(
                task,
                criterionId,
                TaskEvidenceClaimType.taskClaim,
                result.taskId,
              ),
              runId: result.finalRunId,
            ),
    ];
    return [
      for (final claim in claims)
        if (validCriterionIds.contains(claim.criterionId) &&
            task.criterionIds.contains(claim.criterionId))
          (() {
            final runId = claim.runId ?? result.finalRunId;
            final expectationId = _claimExpectationId(task, claim);
            final expectationIds = expectationId == null
                ? const <String>[]
                : [expectationId];
            return ProjectEvidence(
              id: _evidenceId(
                '${task.id}|${result.taskId}|claim|'
                '${runId ?? ''}|${claim.criterionId}|${claim.sourceRef}|'
                '${claim.expectationId ?? ''}|${claim.claim}',
              ),
              type: _projectEvidenceType(claim.evidenceType),
              criterionIds: [claim.criterionId],
              expectationIds: expectationIds,
              taskId: task.id,
              runId: runId,
              sourceRef: claim.sourceRef,
              sourceFingerprint: _fingerprint({
                'criterionId': claim.criterionId,
                'claim': claim.claim,
                'sourceRef': claim.sourceRef,
                'expectationId': expectationId,
                'runId': runId,
              }),
              summary: claim.claim.trim(),
              status: ProjectEvidenceStatus.proposed,
              strength: _projectStrength(claim.suggestedStrength),
              details: {'origin': 'task_claim', 'runId': ?runId},
              createdAt: evaluatedAt,
            );
          })(),
    ];
  }

  List<String> _criterionIdsFor(
    ProjectDocument project,
    Task task,
    ProjectEvidenceType type, {
    required List<TaskEvidenceExpectation> matchedExpectations,
  }) {
    final expected = matchedExpectations
        .expand((item) => item.criterionIds)
        .toSet()
        .toList();
    if (expected.isNotEmpty) return expected;
    if (task.expectedEvidence.any((item) => item.type == type)) {
      return const [];
    }
    if (type == ProjectEvidenceType.artifact) return task.criterionIds;
    final criteriaById = {
      for (final criterion in project.criteria) criterion.id: criterion,
    };
    return task.criterionIds.where((id) {
      final mode = criteriaById[id]?.verificationMode;
      return switch (type) {
        ProjectEvidenceType.gate || ProjectEvidenceType.command =>
          mode == ProjectVerificationMode.deterministic,
        ProjectEvidenceType.userApproval =>
          mode == ProjectVerificationMode.humanApproval,
        _ => true,
      };
    }).toList();
  }

  List<TaskEvidenceExpectation> _matchingExpectations(
    Task task,
    ProjectEvidenceType type, {
    required List<String> sourceRefs,
  }) {
    final normalizedSources = sourceRefs.map(_normaliseSourceRef).toSet();
    return task.expectedEvidence
        .where((item) => item.type == type)
        .where(
          (item) =>
              item.sourceRef?.trim().isNotEmpty != true ||
              normalizedSources.contains(_normaliseSourceRef(item.sourceRef!)),
        )
        .toList();
  }

  List<String> _expectationIdsFor(
    List<TaskEvidenceExpectation> expectations,
  ) {
    final ids = <String>[];
    final seen = <String>{};
    for (final expectation in expectations) {
      if (seen.add(expectation.id)) ids.add(expectation.id);
    }
    return ids;
  }

  String? _claimExpectationId(Task task, TaskEvidenceClaim claim) {
    final type = _projectEvidenceType(claim.evidenceType);
    final explicit = claim.expectationId?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      final matches = task.expectedEvidence.where(
        (item) =>
            item.id == explicit &&
            item.type == type &&
            item.criterionIds.contains(claim.criterionId),
      );
      return matches.length == 1 ? explicit : null;
    }
    return _uniqueClaimExpectationId(
      task,
      claim.criterionId,
      claim.evidenceType,
      claim.sourceRef,
    );
  }

  String? _uniqueClaimExpectationId(
    Task task,
    String criterionId,
    TaskEvidenceClaimType type,
    String sourceRef,
  ) {
    final projectType = _projectEvidenceType(type);
    final normalizedSource = _normaliseSourceRef(sourceRef);
    final matches = task.expectedEvidence.where(
      (item) =>
          item.type == projectType &&
          item.criterionIds.contains(criterionId) &&
          (item.sourceRef?.trim().isNotEmpty != true ||
              _normaliseSourceRef(item.sourceRef!) == normalizedSource),
    );
    return matches.length == 1 ? matches.single.id : null;
  }

  ProjectEvidenceType _gateEvidenceType(TaskGateResult gate) {
    if (gate.gateId == 'command_passes' ||
        gate.details.containsKey('command')) {
      return ProjectEvidenceType.command;
    }
    if (gate.gateId == 'human_approval') {
      return ProjectEvidenceType.userApproval;
    }
    return ProjectEvidenceType.gate;
  }

  String _gateSourceRef(TaskGateResult gate, ProjectEvidenceType type) {
    if (type == ProjectEvidenceType.command) {
      final command = (gate.details['command'] ?? '').toString().trim();
      if (command.isNotEmpty) return command;
    }
    return gate.gateId;
  }

  String _normaliseSourceRef(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  List<ProjectEvidence> _merge(
    List<ProjectEvidence> existing,
    List<ProjectEvidence> additions,
  ) {
    final merged = [...existing];
    final fingerprints = {
      for (final item in merged)
        if (item.sourceFingerprint != null &&
            item.status != ProjectEvidenceStatus.stale)
          item.sourceFingerprint!: item.id,
    };
    for (final addition in additions) {
      if (addition.sourceFingerprint case final fingerprint?
          when fingerprints.containsKey(fingerprint)) {
        continue;
      }
      if (addition.status == ProjectEvidenceStatus.rejected) {
        for (var index = 0; index < merged.length; index++) {
          final previous = merged[index];
          if (previous.status == ProjectEvidenceStatus.accepted &&
              previous.type == addition.type &&
              previous.sourceRef == addition.sourceRef &&
              _sameIds(previous.criterionIds, addition.criterionIds)) {
            merged[index] = previous.copyWith(
              status: ProjectEvidenceStatus.stale,
              evaluatedAt: addition.evaluatedAt,
            );
          }
        }
      }
      merged.add(addition);
      if (addition.sourceFingerprint != null) {
        fingerprints[addition.sourceFingerprint!] = addition.id;
      }
    }
    return merged;
  }

  bool _sameIds(List<String> left, List<String> right) {
    return left.length == right.length && left.toSet().containsAll(right);
  }

  ProjectEvidenceType _projectEvidenceType(TaskEvidenceClaimType type) =>
      switch (type) {
        TaskEvidenceClaimType.gate => ProjectEvidenceType.gate,
        TaskEvidenceClaimType.artifact => ProjectEvidenceType.artifact,
        TaskEvidenceClaimType.command => ProjectEvidenceType.command,
        TaskEvidenceClaimType.taskClaim => ProjectEvidenceType.taskClaim,
        TaskEvidenceClaimType.userApproval => ProjectEvidenceType.userApproval,
      };

  ProjectEvidenceStrength _projectStrength(
    TaskEvidenceClaimStrength strength,
  ) => switch (strength) {
    TaskEvidenceClaimStrength.advisory => ProjectEvidenceStrength.advisory,
    TaskEvidenceClaimStrength.supporting => ProjectEvidenceStrength.supporting,
    TaskEvidenceClaimStrength.conclusive => ProjectEvidenceStrength.conclusive,
  };

  String _evidenceId(String value) => 'evidence_${_stableHash(value)}';

  String _fingerprint(Map<String, dynamic> value) =>
      _stableHash(jsonEncode(value));

  String _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final codeUnit in value.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
