import 'package:hermes/core/services/project_system/orchestration_contracts.dart';
import 'package:hermes/core/models/project.dart';

typedef ProjectRunIteration =
    Future<ProjectCommandResult> Function(ProjectExecutionRequest request);

/// Owns the continuation policy for project runs.
///
/// A project command may either execute one bounded batch or continue through
/// automatically resumable pauses. The loop knows that policy; the iteration
/// itself remains in the project execution port.
class ProjectRunLoop {
  const ProjectRunLoop();

  Future<ProjectCommandResult> run(
    ProjectExecutionRequest request, {
    required bool boundedRun,
    required ProjectRunIteration iteration,
  }) async {
    var current = request;
    while (true) {
      final result = await iteration(current);
      if (boundedRun || !_canContinue(result)) return result;
      current = current.copyWith(snapshot: result.project);
    }
  }

  bool _canContinue(ProjectCommandResult result) {
    final project = result.project;
    final outcome = project.boundary?.outcome;
    return (outcome == ProjectControlOutcome.paused ||
            (outcome == null && project.status == ProjectStatus.paused)) &&
        project.activeTaskId == null &&
        project.pendingPlanApproval == null &&
        project.openQuestions.isEmpty &&
        project.blocker == null;
  }
}
