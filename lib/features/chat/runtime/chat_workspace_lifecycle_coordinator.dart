import 'package:hermes/features/project/application/contracts/project_snapshot_models.dart';
import 'package:hermes/features/project/application/project_application/project_execution_port.dart';
import 'package:hermes/features/project/application/project_application/project_ports.dart';
import 'package:hermes/features/task/application/contracts/task_snapshot_models.dart';
import 'package:hermes/features/task/application/contracts/task_summary.dart';
import 'package:hermes/features/task/application/task_application/task_ports.dart';
import 'package:hermes/features/workspace/application/workspace.dart';
import 'package:hermes/features/workspace/application/workspace_ports.dart';

class ChatWorkspaceLoadResult {
  const ChatWorkspaceLoadResult({
    required this.workspace,
    required this.activeProject,
    required this.availableProjects,
    required this.activeTask,
    required this.availableTasks,
  });

  final WorkspaceAttachment workspace;
  final ProjectAggregate? activeProject;
  final List<ProjectSummary> availableProjects;
  final Task? activeTask;
  final List<TaskSummary> availableTasks;
}

/// Owns workspace attach/detach loading and scope cleanup for a chat session.
class ChatWorkspaceLifecycleCoordinator {
  const ChatWorkspaceLifecycleCoordinator({
    required WorkspacePort workspaceService,
    required TaskSessionPort taskSessions,
    required ProjectSessionPort projectSessions,
    required TaskWorkflowQueryPort taskQueries,
    required ProjectWorkflowQueryPort projectQueries,
    required Future<ProjectCommandResult?> Function(
      WorkspaceAttachment workspace,
      ProjectAggregate? snapshot,
    )
    recoverProject,
    required Future<Task?> Function(
      WorkspaceAttachment workspace,
      Task? snapshot,
    )
    recoverTask,
    required Future<Task?> Function(
      WorkspaceAttachment workspace,
      ProjectAggregate? project,
    )
    taskForActiveProject,
  }) : _workspaceService = workspaceService,
       _taskSessions = taskSessions,
       _projectSessions = projectSessions,
       _taskQueries = taskQueries,
       _projectQueries = projectQueries,
       _recoverProject = recoverProject,
       _recoverTask = recoverTask,
       _taskForActiveProject = taskForActiveProject;

  final WorkspacePort _workspaceService;
  final TaskSessionPort _taskSessions;
  final ProjectSessionPort _projectSessions;
  final TaskWorkflowQueryPort _taskQueries;
  final ProjectWorkflowQueryPort _projectQueries;
  final Future<ProjectCommandResult?> Function(
    WorkspaceAttachment workspace,
    ProjectAggregate? snapshot,
  )
  _recoverProject;
  final Future<Task?> Function(WorkspaceAttachment workspace, Task? snapshot)
  _recoverTask;
  final Future<Task?> Function(
    WorkspaceAttachment workspace,
    ProjectAggregate? project,
  )
  _taskForActiveProject;

  Future<ChatWorkspaceLoadResult> attach({
    required String folderPath,
    required WorkspaceAttachment? previousWorkspace,
    required String? previousChatId,
    required String previousScopeId,
  }) async {
    final nextWorkspace = await _workspaceService.attach(folderPath);
    if (previousChatId == null &&
        previousWorkspace != null &&
        !previousWorkspace.missing &&
        previousWorkspace.rootPath != nextWorkspace.rootPath) {
      await _taskSessions.deleteTasksForChatSession(
        previousWorkspace,
        chatSessionId: previousScopeId,
      );
      await _projectSessions.deleteProjectsForChatSession(
        previousWorkspace,
        chatSessionId: previousScopeId,
      );
    }

    final activeProject = (await _recoverProject(
      nextWorkspace,
      await _projectQueries.loadLatestProject(
        nextWorkspace,
        chatSessionId: previousChatId ?? previousScopeId,
      ),
    ))?.project;
    final availableProjects = await _projectQueries.listProjects(
      nextWorkspace,
      chatSessionId: previousChatId ?? previousScopeId,
    );
    var activeTask = await _taskForActiveProject(nextWorkspace, activeProject);
    if (activeTask == null && activeProject == null) {
      activeTask = await _recoverTask(
        nextWorkspace,
        await _taskQueries.loadLatestTask(
          nextWorkspace,
          chatSessionId: previousChatId ?? previousScopeId,
        ),
      );
    }
    final availableTasks = await _taskQueries.listTasks(
      nextWorkspace,
      chatSessionId: previousChatId ?? previousScopeId,
    );
    return ChatWorkspaceLoadResult(
      workspace: nextWorkspace,
      activeProject: activeProject,
      availableProjects: availableProjects,
      activeTask: activeTask,
      availableTasks: availableTasks,
    );
  }

  Future<void> deleteTransientScope({
    required WorkspaceAttachment? workspace,
    required String scopeId,
    required Future<void> Function() deleteTransientTasks,
    required Future<void> Function() deleteTransientProjects,
  }) async {
    if (workspace == null || workspace.missing) return;
    await deleteTransientTasks();
    await deleteTransientProjects();
  }
}
