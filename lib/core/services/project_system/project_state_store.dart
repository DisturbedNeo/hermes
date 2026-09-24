import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/persistence_contracts.dart';
import 'package:hermes/core/services/project_system/project_aggregate_repository.dart';
import 'package:hermes/core/services/project_system/project_control_state_service.dart';
import 'package:hermes/core/services/project_system/project_repository.dart';
import 'package:hermes/core/services/task_system/task_service.dart';

/// The project aggregate's persistence and hydration boundary.
///
/// Project documents contain task ids while task documents contain the full
/// task history. This store is the one place that knows how to load the
/// aggregate and rehydrate that relationship; run and planning code receives
/// ordinary domain objects instead of repository details.
class ProjectStateStore {
  ProjectStateStore({
    required ProjectRepository projectRepository,
    required ProjectAggregateRepository aggregateRepository,
    required TaskService taskService,
  }) : _projectRepository = projectRepository,
       _aggregateRepository = aggregateRepository,
       _taskService = taskService;

  final ProjectRepository _projectRepository;
  final ProjectAggregateRepository _aggregateRepository;
  final TaskService _taskService;
  final ProjectControlStateService _controlStateService =
      const ProjectControlStateService();

  ProjectRepository get projectRepository => _projectRepository;
  ProjectAggregateRepository get aggregateRepository => _aggregateRepository;

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
              project.copyWith(tasks: result.canonicalTasks),
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

  Future<ProjectDocument> hydrate(
    WorkspaceAttachment workspace,
    ProjectDocument project,
  ) async {
    final cached = {for (final task in project.tasks) task.id: task};
    final tasks = <Task>[];
    for (final taskId in project.taskIds) {
      final task = await _taskService.loadTask(
        workspace,
        taskId,
        chatSessionId: project.chatSessionId,
        projectId: project.id,
        includeHistory: false,
      );
      final resolved = task ?? cached[taskId];
      if (resolved != null) tasks.add(resolved);
    }
    return _controlStateService.synchronise(project.copyWith(tasks: tasks));
  }

  Future<ProjectPersistenceDiagnostics> inspect(
    WorkspaceAttachment workspace,
    ProjectDocument project,
  ) => _aggregateRepository.inspect(workspace.rootPath, project);

  Future<ProjectRevisionCheckResult> checkRevisions(
    WorkspaceAttachment workspace,
    ProjectDocument project,
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
