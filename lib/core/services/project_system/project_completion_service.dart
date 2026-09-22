import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/services/project_system/project_lifecycle_service.dart';

/// Owns the final project transition after criteria and evidence evaluation.
/// Evaluation itself remains in the existing criterion/evidence collaborators;
/// this service is the only focused boundary allowed to enter `completed`.
class ProjectCompletionService {
  const ProjectCompletionService({
    this.lifecycle = const ProjectLifecycleService(),
  });

  final ProjectLifecycleService lifecycle;

  ProjectTransitionResult completeFromEvidence({
    required ProjectDocument project,
    String summary = '',
    DateTime? now,
  }) {
    final unresolved = project.criteria.where(
      (criterion) =>
          criterion.required &&
          criterion.status != ProjectCriterionStatus.satisfied &&
          criterion.status != ProjectCriterionStatus.invalidated,
    );
    if (unresolved.isNotEmpty) {
      throw StateError(
        'Project cannot complete while required criteria remain unresolved.',
      );
    }
    if (project.openQuestions.isNotEmpty) {
      throw StateError('Project cannot complete while questions are open.');
    }
    final transition = lifecycle.transition(
      snapshot: project,
      to: ProjectStatus.completed,
      trigger: ProjectLifecycleTrigger.completion,
      reason: summary,
      completionApproved: true,
      now: now,
    );
    final completed = transition.project.copyWith(
      completionSummary: summary.trim().isEmpty
          ? 'All required project criteria are satisfied by accepted evidence.'
          : summary.trim(),
    );
    return ProjectTransitionResult(
      project: completed,
      transition: transition.transition,
    );
  }
}
