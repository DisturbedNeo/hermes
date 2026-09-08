import 'package:hermes/core/models/project.dart';

/// Records orchestration progress and stops repeated successful-but-unproductive
/// task loops before they consume the remaining project budget.
class ProjectProgressMonitor {
  final int stagnationThreshold;

  const ProjectProgressMonitor({this.stagnationThreshold = 3})
    : assert(stagnationThreshold > 0);

  ProjectDocument recordTaskResult({
    required ProjectDocument project,
    required ProjectTask task,
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
    if (!progressed) {
      progressed = project.evidence.any(
        (item) =>
            item.status == ProjectEvidenceStatus.accepted &&
            !acceptedEvidenceIdsBefore.contains(item.id) &&
            item.projectTaskId == task.id &&
            item.criterionIds.any(task.criterionIds.contains),
      );
    }

    final diagnostics = project.diagnostics;
    final noProgress = taskAccepted && !progressed && !excludeFromStagnation;
    final consecutive = excludeFromStagnation
        ? 0
        : taskAccepted
        ? noProgress
              ? diagnostics.consecutiveNoProgressIterations + 1
              : 0
        : diagnostics.consecutiveNoProgressIterations;
    final recentTaskIds = excludeFromStagnation
        ? const <String>[]
        : taskAccepted
        ? noProgress
              ? [
                  ...diagnostics.recentNoProgressTaskIds,
                  task.id,
                ].reversed.take(stagnationThreshold).toList().reversed.toList()
              : const <String>[]
        : diagnostics.recentNoProgressTaskIds;
    final nextDiagnostics = diagnostics.copyWith(
      taskExecutions: diagnostics.taskExecutions + 1,
      completedTaskExecutions:
          diagnostics.completedTaskExecutions + (taskAccepted ? 1 : 0),
      completedTasksWithoutCriterionProgress:
          diagnostics.completedTasksWithoutCriterionProgress +
          (noProgress ? 1 : 0),
      criterionReversals: diagnostics.criterionReversals + reversals,
      consecutiveNoProgressIterations: consecutive,
      recentNoProgressTaskIds: recentTaskIds,
    );
    if (consecutive < stagnationThreshold ||
        project.isTerminal ||
        project.blocker != null) {
      return project.copyWith(
        diagnostics: nextDiagnostics,
        updatedAt: evaluatedAt,
      );
    }
    return project.copyWith(
      status: ProjectStatus.blocked,
      blocker: ProjectBlocker(
        type: ProjectBlockerType.stagnation,
        message:
            'Project stopped after $consecutive completed tasks made no '
            'criterion progress. Recent tasks: ${recentTaskIds.join(', ')}. '
            'Completed-without-progress total: '
            '${nextDiagnostics.completedTasksWithoutCriterionProgress}. '
            'Request a manual replan with new direction before continuing.',
        taskId: task.id,
        createdAt: evaluatedAt,
      ),
      diagnostics: nextDiagnostics,
      updatedAt: evaluatedAt,
    );
  }

  int _criterionProgressRank(ProjectCriterionStatus status) => switch (status) {
    ProjectCriterionStatus.unsatisfied ||
    ProjectCriterionStatus.invalidated => 0,
    ProjectCriterionStatus.partial => 1,
    ProjectCriterionStatus.satisfied => 2,
  };
}
