part of 'chat_session_orchestrator.dart';

/// Coordinates the explicit user request to replan unfinished task work.
class ChatTaskReplanUseCase {
  ChatTaskReplanUseCase(ChatTaskReplanCapabilities host) : _host = host;

  final ChatTaskReplanCapabilities _host;

  Future<void> execute() async {
    final currentWorkspace = _host.workspace;
    final client = _host.activeModelSession.completionProvider;
    final snapshot = _host.activeTask;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        client == null ||
        snapshot == null ||
        _host.taskBusy) {
      return;
    }

    _host.dispatchTaskBusy(true);
    final token = _host.beginTaskCancellationScope();
    _host.dispatchTaskError(null);
    _host.dispatchTaskStatusMessage('Replanning unfinished work...');
    _host._beginTaskModelOutput('Replan Model Output');
    _host.emitChange();
    try {
      await _host._taskPlanning.replanUnfinished(
        client: client,
        workspace: currentWorkspace,
        taskId: snapshot.id,
        baseSystemPrompt: _host._buildTaskSystemPrompt(snapshot),
        onModelOutput: _host._handleTaskModelOutput,
        cancellationToken: token,
      );
      await _host.reloadTasks();
      _host._insertTaskAssistantMessage(
        'Unfinished work replanned for **${_host.activeTask!.title}**. Next step: `${_host.activeTask!.currentStepId ?? 'none'}`.',
      );
    } on OperationCancelledException {
      _host._insertTaskAssistantMessage('Replan cancelled.');
    } catch (error) {
      _host.dispatchTaskError(error);
      rethrow;
    } finally {
      _host.dispatchTaskBusy(false);
      _host._endTaskCancellationScope(token);
      _host.dispatchTaskStatusMessage(null);
      _host._finishTaskModelOutput();
      _host.emitChange();
    }
  }
}
