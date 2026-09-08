import 'package:hermes/core/models/project.dart';

/// Applies evidence rules to criterion state without mutating task history.
class ProjectCriterionEvaluator {
  const ProjectCriterionEvaluator();

  ProjectDocument evaluateDeterministically(
    ProjectDocument project, {
    required DateTime evaluatedAt,
  }) {
    final criteria = [
      for (final criterion in project.criteria)
        _evaluateCriterion(project, criterion, project.evidence, evaluatedAt),
    ];
    return project.copyWith(criteria: criteria, updatedAt: evaluatedAt);
  }

  ProjectDocument applyModelReview(
    ProjectDocument project, {
    required bool projectComplete,
    required List<String> remainingCriteria,
    required String rationale,
    required DateTime evaluatedAt,
  }) {
    if (!projectComplete && remainingCriteria.isEmpty) return project;
    final remaining = remainingCriteria.map(_normalise).toSet();
    final hasRecognizedRemaining = project.criteria.any(
      (criterion) => remaining.contains(_normalise(criterion.statement)),
    );
    var evidence = [...project.evidence];
    final criteria = <ProjectCriterion>[];

    for (final criterion in project.criteria) {
      if (criterion.status == ProjectCriterionStatus.satisfied ||
          criterion.status == ProjectCriterionStatus.invalidated ||
          (criterion.verificationMode != ProjectVerificationMode.modelReview &&
              criterion.verificationMode != ProjectVerificationMode.mixed)) {
        criteria.add(criterion);
        continue;
      }
      final relatedIndexes = <int>[
        for (var index = 0; index < evidence.length; index++)
          if (evidence[index].criterionIds.contains(criterion.id)) index,
      ];
      final proposedClaims = relatedIndexes.where(
        (index) =>
            evidence[index].status == ProjectEvidenceStatus.proposed &&
            evidence[index].type == ProjectEvidenceType.taskClaim,
      );
      final acceptedSupporting = relatedIndexes.where(
        (index) => evidence[index].status == ProjectEvidenceStatus.accepted,
      );
      if (proposedClaims.isEmpty && acceptedSupporting.isEmpty) {
        criteria.add(criterion);
        continue;
      }

      final reviewSaysSatisfied =
          projectComplete ||
          (hasRecognizedRemaining &&
              !remaining.contains(_normalise(criterion.statement)));
      final reviewedEvidence = [
        for (final index in relatedIndexes)
          if (evidence[index].status == ProjectEvidenceStatus.accepted ||
              (reviewSaysSatisfied && proposedClaims.contains(index)))
            evidence[index],
      ];
      final satisfied =
          reviewSaysSatisfied &&
          _hasAllRequiredExpectations(project, criterion, reviewedEvidence);
      if (satisfied) {
        final reviewedIndexes = proposedClaims.isNotEmpty
            ? proposedClaims
            : acceptedSupporting.take(1);
        for (final index in reviewedIndexes) {
          final item = evidence[index];
          evidence[index] = item.copyWith(
            status: ProjectEvidenceStatus.accepted,
            details: {...item.details, 'acceptedBy': 'model_review'},
            evaluatedAt: evaluatedAt,
          );
        }
        criteria.add(
          criterion.copyWith(
            status: ProjectCriterionStatus.satisfied,
            notes: rationale.trim().isEmpty
                ? 'Satisfied by bounded model review of persisted evidence.'
                : rationale.trim(),
            updatedAt: evaluatedAt,
            verifiedAt: evaluatedAt,
          ),
        );
      } else {
        if (reviewSaysSatisfied) {
          for (final index in proposedClaims) {
            final item = evidence[index];
            evidence[index] = item.copyWith(
              status: ProjectEvidenceStatus.accepted,
              details: {...item.details, 'acceptedBy': 'model_review'},
              evaluatedAt: evaluatedAt,
            );
          }
        } else {
          for (final index in proposedClaims) {
            final item = evidence[index];
            evidence[index] = item.copyWith(
              status: ProjectEvidenceStatus.rejected,
              details: {...item.details, 'rejectedBy': 'model_review'},
              evaluatedAt: evaluatedAt,
            );
          }
        }
        final hasAccepted =
            acceptedSupporting.isNotEmpty ||
            (reviewSaysSatisfied && proposedClaims.isNotEmpty);
        criteria.add(
          criterion.copyWith(
            status: hasAccepted
                ? ProjectCriterionStatus.partial
                : ProjectCriterionStatus.unsatisfied,
            notes: 'Model review found this criterion still requires evidence.',
            updatedAt: evaluatedAt,
            verifiedAt: null,
          ),
        );
      }
    }

    return project.copyWith(
      evidence: evidence,
      criteria: criteria,
      updatedAt: evaluatedAt,
    );
  }

  ProjectCriterion _evaluateCriterion(
    ProjectDocument project,
    ProjectCriterion criterion,
    List<ProjectEvidence> evidence,
    DateTime evaluatedAt,
  ) {
    if (criterion.status == ProjectCriterionStatus.invalidated) {
      return criterion;
    }
    final accepted = evidence
        .where(
          (item) =>
              item.status == ProjectEvidenceStatus.accepted &&
              item.criterionIds.contains(criterion.id),
        )
        .toList();
    final modelAccepted = accepted.where(
      (item) => item.details['acceptedBy'] == 'model_review',
    );
    final deterministic = accepted.where(
      (item) =>
          item.strength == ProjectEvidenceStrength.conclusive &&
          (item.type == ProjectEvidenceType.gate ||
              item.type == ProjectEvidenceType.command),
    );
    final approvals = accepted.where(
      (item) => item.type == ProjectEvidenceType.userApproval,
    );

    final satisfied =
        _hasAllRequiredExpectations(project, criterion, accepted) &&
        (modelAccepted.isNotEmpty ||
            (criterion.verificationMode ==
                    ProjectVerificationMode.deterministic &&
                deterministic.isNotEmpty) ||
            (criterion.verificationMode == ProjectVerificationMode.mixed &&
                deterministic.isNotEmpty) ||
            (criterion.verificationMode ==
                    ProjectVerificationMode.humanApproval &&
                approvals.isNotEmpty));
    if (satisfied) {
      return criterion.copyWith(
        status: ProjectCriterionStatus.satisfied,
        notes: modelAccepted.isNotEmpty
            ? 'Satisfied by bounded model review of accepted evidence.'
            : approvals.isNotEmpty
            ? 'Satisfied by accepted user approval.'
            : 'Satisfied by conclusive deterministic evidence.',
        updatedAt: evaluatedAt,
        verifiedAt: criterion.verifiedAt ?? evaluatedAt,
      );
    }
    return criterion.copyWith(
      status: accepted.isEmpty
          ? ProjectCriterionStatus.unsatisfied
          : ProjectCriterionStatus.partial,
      notes: accepted.isEmpty
          ? 'No accepted evidence currently satisfies this criterion.'
          : 'Accepted evidence is supporting but not yet conclusive.',
      updatedAt: evaluatedAt,
      verifiedAt: null,
    );
  }

  bool _hasAllRequiredExpectations(
    ProjectDocument project,
    ProjectCriterion criterion,
    Iterable<ProjectEvidence> accepted,
  ) {
    final required = <String, String>{};
    for (final task in project.tasks) {
      if (task.status == ProjectTaskStatus.deferred ||
          task.status == ProjectTaskStatus.obsolete ||
          task.status == ProjectTaskStatus.failed ||
          task.status == ProjectTaskStatus.rejected ||
          task.status == ProjectTaskStatus.split ||
          task.status == ProjectTaskStatus.cancelled) {
        continue;
      }
      for (final expectation in task.expectedEvidence) {
        if (expectation.required &&
            expectation.criterionIds.contains(criterion.id)) {
          required[expectation.id] = task.id;
        }
      }
    }
    return required.entries.every(
      (entry) => accepted.any(
        (item) =>
            item.projectTaskId == entry.value &&
            item.expectationIds.contains(entry.key),
      ),
    );
  }

  String _normalise(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}
