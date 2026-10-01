import 'package:hermes/features/project/application/contracts/project_snapshot_models.dart';
import 'package:hermes/features/project/application/contracts/project_commands.dart';
import 'package:hermes/features/project/runtime/project_aggregate_hydrator.dart';
import 'package:hermes/features/project/runtime/project_aggregate_store.dart';
import 'package:hermes/features/project/runtime/project_persistence_runtime.dart';
import 'package:hermes/features/project/project_aggregate_repository_port.dart';
import 'package:hermes/features/project/application/contracts/project_checkpoint.dart';
import 'package:hermes/features/task/application/contracts/task_snapshot_models.dart';
import 'package:hermes/features/workspace/application/workspace.dart';

/// Owns project persistence queries and write-boundary coordination.
///
/// Execution state transitions deliberately depend on this typed capability
/// instead of reaching into the persistence runtime for each operation.
class ProjectPersistenceCoordinator {
  const ProjectPersistenceCoordinator({
    required ProjectPersistenceRuntime persistence,
    required ProjectAggregateHydrator stateStore,
  }) : _persistence = persistence,
       _stateStore = stateStore;

  final ProjectPersistenceRuntime _persistence;
  final ProjectAggregateHydrator _stateStore;

  Future<ProjectAggregate> hydrateProjectTasks(
    WorkspaceAttachment workspace,
    ProjectAggregate project,
  ) => _persistence.hydrateProjectTasks(workspace, project);

  Future<List<ProjectSummary>> listProjects(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
  }) => _persistence.listProjects(workspace, chatSessionId: chatSessionId);

  Future<ProjectLoadResult> loadLatestProject(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
  }) => _persistence.loadLatestProject(workspace, chatSessionId: chatSessionId);

  Future<ProjectLoadResult> loadProject(
    WorkspaceAttachment workspace,
    String projectId, {
    String? chatSessionId,
  }) => _persistence.loadProject(
    workspace,
    projectId,
    chatSessionId: chatSessionId,
  );

  Future<int> deleteProjectsForChatSession(
    WorkspaceAttachment workspace, {
    required String chatSessionId,
  }) => _persistence.deleteProjectsForChatSession(
    workspace,
    chatSessionId: chatSessionId,
  );

  Future<int> deleteOrphanedChatProjects(
    WorkspaceAttachment workspace, {
    required Set<String> retainedChatSessionIds,
  }) => _persistence.deleteOrphanedChatProjects(
    workspace,
    retainedChatSessionIds: retainedChatSessionIds,
  );

  Future<ProjectAggregate> updateProjectChatSessionId({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
    required String chatSessionId,
  }) => _persistence.updateProjectChatSessionId(
    workspace: workspace,
    snapshot: snapshot,
    chatSessionId: chatSessionId,
  );

  Future<ProjectAggregate> updateProject({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
    required ProjectUpdateCommand command,
  }) => _persistence.updateProject(
    workspace: workspace,
    snapshot: snapshot,
    command: command,
  );

  Future<ProjectAggregate> upsertUserWorkspaceNode({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
    String? id,
    required String type,
    required String title,
    String description = '',
    List<String> aliases = const [],
    List<String> tags = const [],
    List<String> references = const [],
    String? sourceId,
  }) => _persistence.upsertUserWorkspaceNode(
    workspace: workspace,
    snapshot: snapshot,
    id: id,
    type: type,
    title: title,
    description: description,
    aliases: aliases,
    tags: tags,
    references: references,
    sourceId: sourceId,
  );

  Future<ProjectAggregate> upsertUserWorkspaceEdge({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
    String? id,
    required String sourceNodeId,
    required String targetNodeId,
    required String label,
    String description = '',
    String? sourceId,
  }) => _persistence.upsertUserWorkspaceEdge(
    workspace: workspace,
    snapshot: snapshot,
    id: id,
    sourceNodeId: sourceNodeId,
    targetNodeId: targetNodeId,
    label: label,
    description: description,
    sourceId: sourceId,
  );

  Future<Task?> loadActiveTask(
    WorkspaceAttachment workspace,
    ProjectAggregate project,
  ) => _persistence.loadActiveTask(workspace, project);

  Future<ProjectAggregate> persistProject(
    String workspaceRoot,
    ProjectAggregate project, {
    ProjectPersistenceContext? persistenceContext,
    ProjectPersistenceCheckpoint checkpoint =
        ProjectPersistenceCheckpoint.runtime,
  }) => _persistence.persistProject(
    workspaceRoot,
    project,
    persistenceContext: persistenceContext,
    checkpoint: checkpoint,
  );

  Future<ProjectTransactionRecoveryResult> recoverInterruptedTransactions(
    WorkspaceAttachment workspace,
  ) => _stateStore.recoverInterruptedTransactions(workspace);
}
