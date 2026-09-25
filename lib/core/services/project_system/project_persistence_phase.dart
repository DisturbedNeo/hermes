part of 'project_workflow_service.dart';

/// Coordinates readiness refresh with the aggregate write boundary.
extension ProjectPersistencePhase on ProjectWorkflowService {
  Future<ProjectDocument> _persistProject(
    String workspaceRoot,
    ProjectDocument project, {
    ProjectPersistenceContext? persistenceContext,
    ProjectPersistenceCheckpoint checkpoint =
        ProjectPersistenceCheckpoint.runtime,
  }) async {
    project = _controlStateService.synchronise(project);
    final refreshed = _scheduler
        .refreshReadiness(project)
        .project
        .copyWith(
          taskIds: project.tasks.isEmpty
              ? project.taskIds
              : [for (final task in project.tasks) task.id],
        );
    return _aggregateStore.commit(
      workspaceRoot: workspaceRoot,
      project: refreshed,
      context: persistenceContext,
      checkpoint: checkpoint,
    );
  }
}
