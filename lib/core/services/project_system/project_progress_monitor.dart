import 'package:hermes/core/models/project.dart';

/// Records project progress at task boundaries while evaluating stagnation at
/// persisted batch boundaries. A successful task is allowed to be one part of
/// a larger criterion implementation without consuming the stagnation budget.
class ProjectProgressMonitor {
  final int stagnationThreshold;

  const ProjectProgressMonitor({this.stagnationThreshold = 3})
    : assert(stagnationThreshold > 0);

  ProjectDocument recordTaskResult({
    required ProjectDocument project,
    required Task task,
    required bool taskAccepted,
    bool excludeFromStagnation = false,
    required Map<String, ProjectCriterionStatus> criterionStatusesBefore,
    Set<String> acceptedEvidenceIdsBefore = const {},
    required DateTime evaluatedAt,
  }) {
    var progressed = false;
    var reversals = 0;
    for (final criterion in project.criteria) {
      final before = criterionStatusesBefore[criterion.id];
      if (before == null) continue;
      final beforeRank = _criterionProgressRank(before);
      final afterRank = _criterionProgressRank(criterion.status);
      if (afterRank > beforeRank) progressed = true;
      if (afterRank < beforeRank) reversals++;
    }

    final batchTaskIds = project.currentBatchTaskIds.isEmpty
        ? <String>{task.id}
        : project.currentBatchTaskIds.toSet();
    final taskIndex = project.currentBatchTaskIds.indexOf(task.id);
    final isBatchEnd =
        project.currentBatchTaskIds.isEmpty ||
        taskIndex < 0 ||
        taskIndex == project.currentBatchTaskIds.length - 1;
    final newAcceptedBatchEvidence = project.evidence.any(
      (item) =>
          item.status == ProjectEvidenceStatus.accepted &&
          !acceptedEvidenceIdsBefore.contains(item.id) &&
          item.taskId != null &&
          batchTaskIds.contains(item.taskId) &&
          item.criterionIds.isNotEmpty,
    );
    if (!progressed) progressed = newAcceptedBatchEvidence;

    final diagnostics = project.diagnostics;
    final taskExecutions = diagnostics.taskExecutions + 1;
    final completedTaskExecutions =
        diagnostics.completedTaskExecutions + (taskAccepted ? 1 : 0);
    final nextReversals = diagnostics.criterionReversals + reversals;

    if (excludeFromStagnation) {
      return project.copyWith(
        currentBatchProgressObserved: false,
        diagnostics: diagnostics.copyWith(
          taskExecutions: taskExecutions,
          completedTaskExecutions: completedTaskExecutions,
          criterionReversals: nextReversals,
          consecutiveNoProgressBatches: 0,
          recentNoProgressBatchIds: const [],
        ),
        updatedAt: evaluatedAt,
      );
    }

    if (!taskAccepted) {
      return project.copyWith(
        diagnostics: diagnostics.copyWith(
          taskExecutions: taskExecutions,
          completedTaskExecutions: completedTaskExecutions,
          criterionReversals: nextReversals,
        ),
        updatedAt: evaluatedAt,
      );
    }

    final observedBatchProgress =
        project.currentBatchProgressObserved || progressed;
    if (!isBatchEnd) {
      return project.copyWith(
        currentBatchProgressObserved: observedBatchProgress,
        diagnostics: diagnostics.copyWith(
          taskExecutions: taskExecutions,
          completedTaskExecutions: completedTaskExecutions,
          criterionReversals: nextReversals,
        ),
        updatedAt: evaluatedAt,
      );
    }

    final batchProgressed = observedBatchProgress;
    final noProgressBatch = !batchProgressed;
    final consecutive = noProgressBatch
        ? diagnostics.consecutiveNoProgressBatches + 1
        : 0;
    final batchId = _batchId(project, task);
    final recentBatchIds = noProgressBatch
        ? [
            ...diagnostics.recentNoProgressBatchIds,
            batchId,
          ].reversed.take(stagnationThreshold).toList().reversed.toList()
        : const <String>[];
    final nextDiagnostics = diagnostics.copyWith(
      taskExecutions: taskExecutions,
      completedTaskExecutions: completedTaskExecutions,
      completedBatchesWithoutCriterionProgress:
          diagnostics.completedBatchesWithoutCriterionProgress +
          (noProgressBatch ? 1 : 0),
      criterionReversals: nextReversals,
      consecutiveNoProgressBatches: consecutive,
      recentNoProgressBatchIds: recentBatchIds,
    );
    final completed = project.copyWith(
      currentBatchProgressObserved: false,
      diagnostics: nextDiagnostics,
      updatedAt: evaluatedAt,
    );
    if (consecutive < stagnationThreshold ||
        completed.isTerminal ||
        completed.blocker != null) {
      return completed;
    }
    return completed.copyWith(
      status: ProjectStatus.blocked,
      blocker: ProjectBlocker(
        type: ProjectBlockerType.stagnation,
        message:
            'Project stopped after $consecutive completed batches made no '
            'criterion progress. Recent batches: ${recentBatchIds.join(', ')}. '
            'Completed-without-progress total: '
            '${nextDiagnostics.completedBatchesWithoutCriterionProgress}. '
            'Request a manual replan with new direction before continuing.',
        taskId: task.id,
        createdAt: evaluatedAt,
      ),
      updatedAt: evaluatedAt,
    );
  }

  String _batchId(ProjectDocument project, Task task) {
    if (project.currentBatchTaskIds.isEmpty) return 'single:${task.id}';
    return '${project.currentBatchPlanRevision}:'
        '${project.currentBatchTaskIds.join(',')}';
  }

  int _criterionProgressRank(ProjectCriterionStatus status) => switch (status) {
    ProjectCriterionStatus.unsatisfied ||
    ProjectCriterionStatus.invalidated => 0,
    ProjectCriterionStatus.partial => 1,
    ProjectCriterionStatus.satisfied => 2,
  };
}
