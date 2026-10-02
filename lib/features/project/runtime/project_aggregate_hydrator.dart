import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/features/workspace/application/workspace.dart';
import 'package:hermes/features/persistence/application/persistence_contracts.dart';
import 'package:hermes/features/project/project_aggregate_repository_port.dart';
import 'package:hermes/features/project/domain/project_control_state_service.dart';
import 'package:hermes/features/project/project_repository_port.dart';
import 'package:hermes/features/task/application/task_application/task_ports.dart';

/// The project aggregate's persistence and hydration boundary.
///
/// Project documents contain task ids while task documents contain the full
/// task history. This store is the one place that knows how to load the
/// aggregate and rehydrate that relationship; run and planning code receives
/// ordinary domain objects instead of repository details.
class ProjectAggregateHydrator {
  ProjectAggregateHydrator({
    required ProjectRepositoryPort projectRepository,
    required ProjectAggregateRepositoryPort aggregateRepository,
    required TaskQueryPort taskQueries,
  }) : _projectRepository = projectRepository,
       _aggregateRepository = aggregateRepository,
       _taskQueries = taskQueries;

  final ProjectRepositoryPort _projectRepository;
  final ProjectAggregateRepositoryPort _aggregateRepository;
  final TaskQueryPort _taskQueries;
  final ProjectControlStateService _controlStateService =
      const ProjectControlStateService();

  Future<List<ProjectSummary>> list(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
  }) => _projectRepository.listProjects(
    workspace.rootPath,
    chatSessionId: chatSessionId,
  );

  Future<ProjectLoadResult> load(
    WorkspaceAttachment workspace,
    String projectId, {
    String? chatSessionId,
  }) async {
    final result = await _aggregateRepository.loadProject(
      workspace.rootPath,
      projectId,
      chatSessionId: chatSessionId,
      includeHistory: false,
    );
    final project = result.project;
    return project == null
        ? result
        : ProjectLoadResult(
            project: _controlStateService.synchronise(
              project.copyWith(
                tasks: [
                  for (final task in result.canonicalTasks)
                    ProjectTaskNode.fromTask(task),
                ],
              ),
            ),
            diagnostics: result.diagnostics,
            canonicalTasks: result.canonicalTasks,
          );
  }

  Future<ProjectLoadResult> loadLatest(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
  }) async {
    final summaries = await list(workspace, chatSessionId: chatSessionId);
    if (summaries.isEmpty) {
      return const ProjectLoadResult(
        project: null,
        diagnostics: ProjectPersistenceDiagnostics(),
      );
    }
    return load(workspace, summaries.first.id, chatSessionId: chatSessionId);
  }

  Future<ProjectAggregate> hydrate(
    WorkspaceAttachment workspace,
    ProjectAggregate project,
  ) async {
    final cached = {for (final task in project.tasks) task.id: task};
    final tasks = <ProjectTaskNode>[];
    for (final taskId in project.taskIds) {
      final task = await _taskQueries.loadTask(
        workspace,
        taskId,
        chatSessionId: project.chatSessionId,
        projectId: project.id,
        includeHistory: false,
      );
      final resolved = task == null
          ? cached[taskId]
          : ProjectTaskNode.fromTask(task);
      if (resolved != null) tasks.add(resolved);
    }
    return _controlStateService.synchronise(project.copyWith(tasks: tasks));
  }

  Future<ProjectPersistenceDiagnostics> inspect(
    WorkspaceAttachment workspace,
    ProjectAggregate project,
  ) => _aggregateRepository.inspect(workspace.rootPath, project);

  Future<ProjectTransactionRecoveryResult> recoverInterruptedTransactions(
    WorkspaceAttachment workspace,
  ) => _aggregateRepository.recoverInterruptedTransactions(workspace.rootPath);

  Future<ProjectRevisionCheckResult> checkRevisions(
    WorkspaceAttachment workspace,
    ProjectAggregate project,
  ) => _aggregateRepository.checkRevisions(workspace.rootPath, project);

  Future<int> deleteForChatSession(
    WorkspaceAttachment workspace, {
    required String chatSessionId,
  }) async {
    if (workspace.missing) return 0;
    final projects = await list(workspace, chatSessionId: chatSessionId);
    return deleteIds(workspace, projects.map((project) => project.id));
  }

  Future<int> deleteOrphaned(
    WorkspaceAttachment workspace, {
    required Set<String> retainedChatSessionIds,
  }) async {
    if (workspace.missing) return 0;
    final projects = await list(workspace);
    return deleteIds(
      workspace,
      projects
          .where(
            (project) =>
                project.chatSessionId != null &&
                !retainedChatSessionIds.contains(project.chatSessionId),
          )
          .map((project) => project.id),
    );
  }

  Future<int> deleteIds(
    WorkspaceAttachment workspace,
    Iterable<String> projectIds,
  ) async {
    var deleted = 0;
    for (final projectId in projectIds) {
      final loaded = await _aggregateRepository.loadProject(
        workspace.rootPath,
        projectId,
      );
      final project = loaded.project;
      if (project != null &&
          await _aggregateRepository.deleteProject(
            workspace.rootPath,
            project,
          )) {
        deleted++;
      }
    }
    return deleted;
  }
}
