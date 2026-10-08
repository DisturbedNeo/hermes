import 'dart:convert';

import 'package:hermes/core/contracts/acceptance.dart';
import 'package:hermes/features/project/domain/project.dart';

/// Converts task output into durable, deduplicated Project evidence.
class ProjectEvidenceService {
  const ProjectEvidenceService();

  List<ProjectEvidence> normalizeTaskResult({
    required ProjectAggregate project,
    required ProjectTaskNode task,
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
    ProjectAggregate project,
    ProjectTaskNode task,
    TaskResult result,
    DateTime evaluatedAt,
  ) {
    final evidence = <ProjectEvidence>[];
    for (final gate in result.gateResults) {
      if (gate.gateId == 'artifact_nonempty') continue;
      final type = _gateEvidenceType(gate);
      final sourceRef = _gateSourceRef(gate, type);
      final acceptanceRef = gate.details['acceptance_ref']?.toString();
      // Engine-owned safety gates do not become project evidence.
      if (acceptanceRef == null || acceptanceRef.trim().isEmpty) {
        continue;
      }
      final matchedVerifiers = _matchingVerifiers(
        task,
        type,
        sourceRefs: [sourceRef, gate.gateId],
        acceptanceRef: acceptanceRef,
      );
      if (matchedVerifiers.isEmpty ||
          matchedVerifiers.every((item) => item.item.criterionIds.isEmpty)) {
        continue;
      }
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
            matchedVerifiers: matchedVerifiers,
          ),
          expectationIds: _expectationIdsFor(matchedVerifiers),
          taskId: task.id,
          runId: result.finalRunId,
          sourceRef: sourceRef,
          sourceFingerprint: _fingerprint({
            'taskId': task.id,
            'runId': result.finalRunId,
            'gateId': gate.gateId,
            'status': gate.status.wire,
            'summary': gate.summary,
            'expectationIds': _expectationIdsFor(matchedVerifiers),
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
            'origin': 'gate_evaluation',
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
    ProjectAggregate project,
    ProjectTaskNode task,
    TaskResult result,
    DateTime evaluatedAt,
  ) {
    final evidence = <ProjectEvidence>[];
    for (final artifact in result.artifacts) {
      final matchedVerifiers = _matchingVerifiers(
        task,
        ProjectEvidenceType.artifact,
        sourceRefs: [artifact.path],
      );
      if (matchedVerifiers.isEmpty ||
          matchedVerifiers.every((item) => item.item.criterionIds.isEmpty)) {
        continue;
      }
      evidence.add(
        ProjectEvidence(
          id: _evidenceId(
            '${task.id}|${result.taskId}|artifact|'
            '${artifact.runId ?? ''}|${artifact.path}',
          ),
          type: ProjectEvidenceType.artifact,
          criterionIds: _criterionIdsFor(
            project,
            task,
            ProjectEvidenceType.artifact,
            matchedVerifiers: matchedVerifiers,
          ),
          expectationIds: _expectationIdsFor(matchedVerifiers),
          taskId: task.id,
          runId: artifact.runId,
          sourceRef: artifact.path,
          sourceFingerprint: _fingerprint({
            'taskId': task.id,
            'runId': artifact.runId,
            'path': artifact.path,
            'description': artifact.description,
            'kind': artifact.kind,
            'expectationIds': _expectationIdsFor(matchedVerifiers),
          }),
          summary: artifact.description?.trim().isEmpty ?? true
              ? 'Task produced ${artifact.path}.'
              : artifact.description!.trim(),
          status: ProjectEvidenceStatus.accepted,
          strength: ProjectEvidenceStrength.supporting,
          details: {
            'origin': 'workspace_provenance',
            'kind': artifact.kind,
            'artifactId': artifact.id,
            if (artifact.runId != null) 'runId': artifact.runId,
          },
          createdAt: artifact.createdAt ?? evaluatedAt,
          evaluatedAt: evaluatedAt,
        ),
      );
    }
    return evidence;
  }

  List<ProjectEvidence> _claimEvidence(
    ProjectAggregate project,
    ProjectTaskNode task,
    TaskResult result,
    DateTime evaluatedAt,
  ) {
    final validCriterionIds = project.criteria.map((item) => item.id).toSet();
    // A task summary is an operational report, not evidence. Only explicit
    // claims are retained here, and those remain proposed/advisory until an
    // independent deterministic gate, artifact provenance check, or human
    // approval supplies authoritative evidence.
    final claims = result.evidenceClaims;
    return [
      for (final claim in claims)
        if (validCriterionIds.contains(claim.criterionId) &&
            _linkedAcceptance(task, claim.acceptanceRef, claim.criterionId))
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
              // The model may describe a claim as a command, artifact, or
              // approval, but it did not create that authoritative evidence.
              // Preserve the requested label only in details for diagnosis.
              type: ProjectEvidenceType.taskClaim,
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
              details: {
                'origin': 'task_claim',
                if (claim.acceptanceRef != null)
                  'acceptanceRef': claim.acceptanceRef,
                'claimedEvidenceType': claim.evidenceType.name,
                'runId': ?runId,
              },
              createdAt: evaluatedAt,
            );
          })(),
    ];
  }

  List<String> _criterionIdsFor(
    ProjectAggregate project,
    ProjectTaskNode task,
    ProjectEvidenceType type, {
    required List<_AcceptanceVerifierMatch> matchedVerifiers,
  }) {
    final expected = matchedVerifiers
        .expand((item) => item.item.criterionIds)
        .toSet()
        .toList();
    return expected;
  }

  List<_AcceptanceVerifierMatch> _matchingVerifiers(
    ProjectTaskNode task,
    ProjectEvidenceType type, {
    required List<String> sourceRefs,
    String? acceptanceRef,
  }) {
    final normalizedSources = sourceRefs.map(_normaliseSourceRef).toSet();
    final matches = <_AcceptanceVerifierMatch>[];
    for (final item in task.acceptance) {
      for (var index = 0; index < item.verifiers.length; index++) {
        final verifier = item.verifiers[index];
        final verifierType = switch (verifier.kind) {
          AcceptanceVerifierKind.command => ProjectEvidenceType.command,
          AcceptanceVerifierKind.artifact => ProjectEvidenceType.artifact,
          AcceptanceVerifierKind.review => ProjectEvidenceType.gate,
          AcceptanceVerifierKind.approval => ProjectEvidenceType.userApproval,
        };
        if (verifierType != type) continue;
        final source = verifier.command ?? verifier.path;
        if (acceptanceRef != null && item.ref != acceptanceRef && source == null) {
          continue;
        }
        if (source != null &&
            source.trim().isNotEmpty &&
            !normalizedSources.contains(_normaliseSourceRef(source))) {
          continue;
        }
        matches.add((item: item, verifier: verifier, index: index));
      }
    }
    return matches;
  }

  List<String> _expectationIdsFor(List<_AcceptanceVerifierMatch> verifiers) {
    final ids = <String>[];
    final seen = <String>{};
    for (final verifier in verifiers) {
      final id = 'acceptance_${verifier.item.ref}_${verifier.index}';
      if (seen.add(id)) ids.add(id);
    }
    return ids;
  }

  String? _claimExpectationId(ProjectTaskNode task, TaskEvidenceClaim claim) =>
      null;

  bool _linkedAcceptance(
    ProjectTaskNode task,
    String? acceptanceRef,
    String criterionId,
  ) => task.acceptance.any(
    (item) =>
        item.ref == acceptanceRef && item.criterionIds.contains(criterionId),
  );

  ProjectEvidenceType _gateEvidenceType(TaskGateResult gate) {
    if (gate.gateId == 'command_passes' ||
        gate.details.containsKey('command')) {
      return ProjectEvidenceType.command;
    }
    if (gate.gateId == 'artifact_exists' ||
        gate.gateId == 'artifact_nonempty') {
      return ProjectEvidenceType.artifact;
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
    if (type == ProjectEvidenceType.artifact) {
      final artifactPath = (gate.details['path'] ?? '').toString().trim();
      if (artifactPath.isNotEmpty) return artifactPath;
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

typedef _AcceptanceVerifierMatch = ({
  AcceptanceItem item,
  AcceptanceVerifier verifier,
  int index,
});
