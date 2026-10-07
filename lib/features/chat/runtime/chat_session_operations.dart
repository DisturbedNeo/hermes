part of 'chat_session_orchestrator.dart';

extension ChatSessionOperations on ChatWorkUseCase {
  // ── Public API (session management + orchestration) ─────────────────────

  bool get isDirty =>
      currentChatId != null &&
      _currentPersistenceRevision != _persistedRevision;

  bool get hasMeaningfulContent => messageStore.messages.any(
    (message) =>
        message.role != MessageRole.system &&
        (message.text.trim().isNotEmpty ||
            message.reasoning.trim().isNotEmpty ||
            message.tools.isNotEmpty),
  );

  bool get isUnsavedNonEmpty => currentChatId == null && hasMeaningfulContent;

  /// Prevents selecting a new prompt-library preset after a chat has started.
  /// It does not lock the transcript's system message, which remains directly
  /// editable like every other message.
  bool get isSystemPromptLocked =>
      chatStream.isStreaming || hasMeaningfulContent || currentChatId != null;

  bool get hasActiveWorkspace =>
      workspace != null && workspace?.missing != true;

  String? get activeTaskJson =>
      activeTask == null ? null : _panelProtocol.encodeTask(activeTask!);

  String? get activeProjectJson => activeProject == null
      ? null
      : _panelProtocol.encodeProject(activeProject!);

  String get displayTitle {
    final savedTitle = currentSavedChat?.title;
    if (savedTitle != null && savedTitle.trim().isNotEmpty) return savedTitle;

    final first = messageStore.messages
        .where((m) => m.role != MessageRole.system && m.text.trim().isNotEmpty)
        .map((m) => m.text.trim().replaceAll(RegExp(r'\s+'), ' '))
        .firstOrNull;

    if (first == null) return 'New chat';
    return first.length <= 40 ? first : '${first.substring(0, 37)}...';
  }

  Future<TaskAggregate?> _recoverTaskSnapshot(
    WorkspaceAttachment current,
    TaskAggregate? snapshot,
  ) async {
    if (snapshot == null) return null;
    final result = await _taskRecovery.recoverTask(
      workspace: current,
      taskId: snapshot.id,
      persist: true,
    );
    return _taskQueries.loadTask(
      current,
      result.task.id,
      chatSessionId: snapshot.chatSessionId,
      projectId: snapshot.projectId,
    );
  }

  Future<ProjectCommandResult?> _recoverProject(
    WorkspaceAttachment current,
    ProjectAggregate? snapshot,
  ) async {
    if (snapshot == null) return null;
    final result = await _projectRecovery.recover(
      ProjectWorkflowRecovery(
        workspace: current,
        projectId: snapshot.id,
        onTaskUpdated: (_) {},
      ),
    );
    final project = await _projectQueries.loadProject(
      current,
      result.project.id,
      chatSessionId: snapshot.chatSessionId,
    );
    if (project == null) return null;
    final task = result.activeTask == null
        ? null
        : await _taskQueries.loadTask(
            current,
            result.activeTask!.id,
            chatSessionId: result.activeTask!.chatSessionId,
            projectId: result.activeTask!.projectId,
          );
    return ProjectCommandResult.fromSnapshot(
      project: project,
      activeTask: task,
      persistenceDiagnostics: result.persistenceDiagnostics,
    );
  }

  Future<TaskAggregate?> _taskForActiveProject(
    WorkspaceAttachment current,
    ProjectAggregate? project,
  ) async {
    final taskId = project?.activeTaskId;
    if (project == null || taskId == null) return null;
    return _recoverTaskSnapshot(
      current,
      await _taskQueries.loadTask(
        current,
        taskId,
        chatSessionId: project.chatSessionId,
        projectId: project.id,
      ),
    );
  }

  // ── Task orchestration ──────────────────────────────────────────────────

  Future<void> _runTaskInternal({bool keepBusy = false}) async {
    final currentWorkspace = workspace;
    final client = activeModelSession.completionProvider;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        client == null ||
        activeTask == null ||
        taskBusy && !keepBusy) {
      return;
    }

    final token = _beginTaskCancellationScope(reuseExisting: keepBusy);

    if (!keepBusy) {
      dispatchTaskBusy(true);
      dispatchTaskError(null);
      _beginTaskModelOutput('Task Run Model Output');
      emitChange();
    }
    await _refreshTaskSystemSettings();
    dispatchTaskStatusMessage('Running task...');
    emitChange();

    try {
      while (true) {
        if (token.isCancelled) break;
        final snapshot = activeTask;
        if (snapshot == null) break;
        if (snapshot.nextRunnableStep == null) break;
        await _runNextTaskStepInternal(keepBusy: true);
        if (token.isCancelled) break;

        final updated = activeTask;
        if (updated == null ||
            updated.status == TaskStatus.completed ||
            updated.status == TaskStatus.blocked ||
            updated.status == TaskStatus.failed ||
            updated.status == TaskStatus.cancelled ||
            _presentationMessages.taskNeedsIntervention(updated)) {
          break;
        }
      }
    } on OperationCancelledException {
      _insertTaskAssistantMessage('Task run cancelled.');
    } catch (e) {
      dispatchTaskError(e);
      _insertTaskErrorBubble('Failed to run task: $e');
    } finally {
      if (!keepBusy) {
        dispatchTaskBusy(false);
        _endTaskCancellationScope(token);
        dispatchTaskStatusMessage(null);
        _finishTaskModelOutput();
        emitChange();
      }
    }
  }
}
