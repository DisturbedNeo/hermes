import 'package:hermes/core/uuid.dart';
import 'package:hermes/features/project/application/contracts/project_snapshot_models.dart';
import 'package:hermes/features/project/runtime/project_criterion_evaluator.dart';
import 'package:hermes/features/project/runtime/project_evidence_service.dart';

typedef ProjectCriteriaSelector = List<String> Function(ProjectAggregate);
typedef ProjectModelSnapshot = ProjectAggregate Function(ProjectAggregate);

/// Converts task outcomes into project evaluations and authoritative evidence.
///
/// This collaborator owns the evidence/completion input boundary; the project
/// state machine remains responsible for lifecycle transitions and recovery.
class ProjectEvaluationCoordinator {
  const ProjectEvaluationCoordinator({
    required ProjectEvidenceService evidenceService,
    required ProjectCriterionEvaluator criterionEvaluator,
    required ProjectCriteriaSelector remainingCriteria,
    required ProjectModelSnapshot projectForModel,
  }) : _evidenceService = evidenceService,
       _criterionEvaluator = criterionEvaluator,
       _remainingCriteria = remainingCriteria,
       _projectForModel = projectForModel;

  final ProjectEvidenceService _evidenceService;
  final ProjectCriterionEvaluator _criterionEvaluator;
  final ProjectCriteriaSelector _remainingCriteria;
  final ProjectModelSnapshot _projectForModel;

  ProjectEvaluation evaluateTaskResult(
    ProjectTaskNode projectTask,
    TaskResult result,
    ProjectAggregate project,
  ) {
    final accepted = result.status == TaskStatus.completed;
    return ProjectEvaluation(
      taskId: projectTask.id,
      taskAccepted: accepted,
      projectComplete: false,
      summary: result.summary,
      completedCriteria: const [],
      remainingCriteria: _remainingCriteria(project),
      newKnownFacts: [
        if (result.summary.trim().isNotEmpty) result.summary.trim(),
        if (result.memoryUpdate.trim().isNotEmpty) result.memoryUpdate.trim(),
      ],
      artifacts: result.artifacts,
      gateResults: result.gateResults,
      taskAdditions: const [],
      openQuestions: result.userQuestion?.trim().isNotEmpty == true
          ? [
              PendingProjectQuestion(
                id: 'question_${uuid.v7()}',
                question: result.userQuestion!.trim(),
                createdAt: DateTime.now(),
              ),
            ]
          : const [],
      failureReason: accepted ? null : result.error ?? result.summary,
      projectReplanRequested: result.projectReplanRequested,
    );
  }

  ProjectAggregate applyTaskEvidence({
    required ProjectAggregate project,
    required ProjectTaskNode task,
    required TaskResult result,
    required DateTime evaluatedAt,
  }) {
    final evidence = _evidenceService.normalizeTaskResult(
      project: _projectForModel(project),
      task: task,
      result: result,
      evaluatedAt: evaluatedAt,
    );
    return _criterionEvaluator.evaluateDeterministically(
      project.copyWith(evidence: evidence, updatedAt: evaluatedAt),
      evaluatedAt: evaluatedAt,
    );
  }
}
