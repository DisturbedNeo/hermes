part of 'chat_session_orchestrator.dart';

/// Owns chat-originated task and project plan edits. It coordinates busy/error
/// presentation state around the focused task/project application ports; the
/// session facade only exposes the stable entry points.
class ChatTaskPlanUseCase {
  ChatTaskPlanUseCase(ChatTaskPlanCapabilities host) : _host = host;

  final ChatTaskPlanCapabilities _host;

  Future<void> updateTaskTaskBrief(TaskPlanUpdateCommand command) async {
    await updateTaskPlan(command);
  }

  Future<void> updateTaskSpec(TaskPlanUpdateCommand command) async {
    await updateTaskPlan(command);
  }

  Future<void> updateTaskPlan(TaskPlanUpdateCommand command) async {
    final currentWorkspace = _host.workspace;
    final snapshot = _host.activeTask;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null ||
        _host.taskBusy) {
      return;
    }

    _host.dispatchTaskBusy(true);
    _host.dispatchTaskError(null);
    _host.dispatchTaskStatusMessage('Updating task plan...');
    _host.emitChange();
    try {
      await _host._taskPlanning.updateTaskPlan(
        workspace: currentWorkspace,
        taskId: snapshot.id,
        command: command,
      );
      await _host.reloadTasks();
      _host._insertTaskAssistantMessage(
        'Task plan updated for **${_host.activeTask!.title}**.',
      );
    } catch (error) {
      _host.dispatchTaskError(error);
      rethrow;
    } finally {
      _host.dispatchTaskBusy(false);
      _host.dispatchTaskStatusMessage(null);
      _host.emitChange();
    }
  }

  Future<void> updateProjectPlan(ProjectUpdateCommand command) async {
    final currentWorkspace = _host.workspace;
    final snapshot = _host.activeProject;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null ||
        _host.taskBusy) {
      return;
    }

    _host.dispatchTaskBusy(true);
    _host.dispatchTaskError(null);
    _host.dispatchTaskStatusMessage('Updating project...');
    _host.emitChange();
    try {
      await _host._projectCommands.updateProject(
        workspace: currentWorkspace,
        projectId: snapshot.id,
        command: command,
      );
      await _host.reloadTasks();
      _host._insertTaskAssistantMessage(
        'Project updated for **${_host.activeProject!.title}**.',
      );
    } catch (error) {
      _host.dispatchTaskError(error);
      rethrow;
    } finally {
      _host.dispatchTaskBusy(false);
      _host.dispatchTaskStatusMessage(null);
      _host.emitChange();
    }
  }

  Future<String> readTaskArtifact(String artifactPath) async {
    final currentWorkspace = _host.workspace;
    if (currentWorkspace == null || currentWorkspace.missing) {
      throw StateError('No active workspace is attached.');
    }
    return _host._taskPresentation.readArtifact(
      workspace: currentWorkspace,
      artifactPath: artifactPath,
    );
  }
}
