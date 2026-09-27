part of 'project_workflow_service.dart';

/// Coordinates readiness refresh with the aggregate write boundary.
mixin ProjectPersistencePhase on ProjectWorkflowRuntime {
  @override
  Future<ProjectDocument> _persistProject(
    String workspaceRoot,
    ProjectDocument project, {
    ProjectPersistenceContext? persistenceContext,
    ProjectPersistenceCheckpoint checkpoint =
        ProjectPersistenceCheckpoint.runtime,
  }) async {
    return _persistenceHandler.persist(
      workspaceRoot,
      project,
      persistenceContext: persistenceContext,
      checkpoint: checkpoint,
    );
  }
}
