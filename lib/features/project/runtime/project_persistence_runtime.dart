import 'package:hermes/core/model_json.dart';
import 'package:hermes/features/project/application/contracts/project_checkpoint.dart';
import 'package:hermes/features/project/application/contracts/project_commands.dart';
import 'package:hermes/features/project/application/contracts/project_snapshot_models.dart';
import 'package:hermes/features/project/project_aggregate_repository_port.dart';
import 'package:hermes/features/project/runtime/project_aggregate_hydrator.dart';
import 'package:hermes/features/project/runtime/project_handlers.dart';
import 'package:hermes/features/project/runtime/project_aggregate_store.dart';
import 'package:hermes/features/project/runtime/project_workspace_graph_service.dart';
import 'package:hermes/features/task/application/task_application/task_ports.dart';
import 'package:hermes/features/task/application/contracts/task_snapshot_models.dart';
import 'package:hermes/features/workspace/application/workspace.dart';

/// Owns project snapshot queries and writes for the runtime graph.
///
/// This service deliberately has no model-loop or execution dependency. It is
/// the only runtime collaborator that coordinates project persistence and
/// task hydration at the project boundary.
class ProjectPersistenceRuntime {
  const ProjectPersistenceRuntime({
    required this.stateStore,
    required this.persistenceHandler,
    required this.taskQueries,
  });

  final ProjectAggregateHydrator stateStore;
  final ProjectPersistenceHandler persistenceHandler;
  final TaskQueryPort taskQueries;

  Future<ProjectAggregate> hydrateProjectTasks(
    WorkspaceAttachment workspace,
    ProjectAggregate project,
  ) => stateStore.hydrate(workspace, project);

  Future<List<ProjectSummary>> listProjects(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
  }) => stateStore.list(workspace, chatSessionId: chatSessionId);

  Future<ProjectLoadResult> loadLatestProject(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
  }) => stateStore.loadLatest(workspace, chatSessionId: chatSessionId);

  Future<ProjectLoadResult> loadProject(
    WorkspaceAttachment workspace,
    String projectId, {
    String? chatSessionId,
  }) => stateStore.load(workspace, projectId, chatSessionId: chatSessionId);

  Future<int> deleteProjectsForChatSession(
    WorkspaceAttachment workspace, {
    required String chatSessionId,
  }) =>
      stateStore.deleteForChatSession(workspace, chatSessionId: chatSessionId);

  Future<int> deleteOrphanedChatProjects(
    WorkspaceAttachment workspace, {
    required Set<String> retainedChatSessionIds,
  }) => stateStore.deleteOrphaned(
    workspace,
    retainedChatSessionIds: retainedChatSessionIds,
  );

  Future<ProjectAggregate> updateProjectChatSessionId({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
    required String chatSessionId,
  }) async {
    if (snapshot.chatSessionId == chatSessionId) return snapshot;
    return persistProject(
      workspace.rootPath,
      snapshot.copyWith(
        chatSessionId: chatSessionId,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<ProjectAggregate> updateProject({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
    required ProjectUpdateCommand command,
  }) async {
    final parsed = ModelJson.decode<ProjectAggregate>(command.toWire());
    final updated = parsed.copyWith(
      id: snapshot.id,
      chatSessionId: snapshot.chatSessionId,
      createdAt: snapshot.createdAt,
      updatedAt: DateTime.now(),
    );
    return persistProject(workspace.rootPath, updated);
  }

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
  }) async {
    final updated = const ProjectWorkspaceGraphService().upsertUserNode(
      project: snapshot,
      id: id,
      type: type,
      title: title,
      description: description,
      aliases: aliases,
      tags: tags,
      references: references,
      sourceId: sourceId,
    );
    return persistProject(
      workspace.rootPath,
      updated,
      checkpoint: ProjectPersistenceCheckpoint.userBoundary,
    );
  }

  Future<ProjectAggregate> upsertUserWorkspaceEdge({
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
    String? id,
    required String sourceNodeId,
    required String targetNodeId,
    required String label,
    String description = '',
    String? sourceId,
  }) async {
    final updated = const ProjectWorkspaceGraphService().upsertUserEdge(
      project: snapshot,
      id: id,
      sourceNodeId: sourceNodeId,
      targetNodeId: targetNodeId,
      label: label,
      description: description,
      sourceId: sourceId,
    );
    return persistProject(
      workspace.rootPath,
      updated,
      checkpoint: ProjectPersistenceCheckpoint.userBoundary,
    );
  }

  Future<Task?> loadActiveTask(
    WorkspaceAttachment workspace,
    ProjectAggregate project,
  ) {
    final taskId = project.activeTaskId;
    if (taskId == null) return Future.value();
    return taskQueries.loadTask(
      workspace,
      taskId,
      chatSessionId: project.chatSessionId,
      projectId: project.id,
    );
  }

  Future<ProjectAggregate> persistProject(
    String workspaceRoot,
    ProjectAggregate project, {
    ProjectPersistenceContext? persistenceContext,
    ProjectPersistenceCheckpoint checkpoint =
        ProjectPersistenceCheckpoint.runtime,
  }) => persistenceHandler.persist(
    workspaceRoot,
    project,
    persistenceContext: persistenceContext,
    checkpoint: checkpoint,
  );
}
