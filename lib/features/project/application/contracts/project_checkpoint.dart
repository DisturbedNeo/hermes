enum ProjectPersistenceCheckpoint {
  initialization,
  frontierSelection,
  taskExecutionStarted,
  taskExecution,
  taskReview,
  planRevision,
  userBoundary,
  recovery,
  workspaceGraphMaintenance,
  runtime,
}

extension ProjectPersistenceCheckpointWire on ProjectPersistenceCheckpoint {
  String get wire => switch (this) {
    ProjectPersistenceCheckpoint.taskExecutionStarted =>
      'task_execution_started',
    ProjectPersistenceCheckpoint.taskExecution => 'task_execution',
    ProjectPersistenceCheckpoint.frontierSelection => 'frontier_selection',
    ProjectPersistenceCheckpoint.taskReview => 'task_review',
    ProjectPersistenceCheckpoint.planRevision => 'plan_revision',
    ProjectPersistenceCheckpoint.userBoundary => 'user_boundary',
    ProjectPersistenceCheckpoint.workspaceGraphMaintenance =>
      'workspace_graph_maintenance',
    _ => name,
  };
}
