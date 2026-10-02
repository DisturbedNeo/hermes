part of 'chat_session_orchestrator.dart';

extension ChatSessionStateOperations on ChatSessionOrchestrator {
  // ── Session state management ────────────────────────────────────────────

  void _handleMessagesChanged() {
    _dispatchChatState(
      ChatMessagesChanged(messageStore.messages),
      notify: false,
    );
    _dispatchChatState(
      ChatHistoryRevisionChanged(_historyRevision),
      notify: false,
    );
    _requestContextEstimateUpdate();
    if (_disposed || _loadingSnapshot) return;
    _markPersistableChange();
  }

  void _handlePreferencesChanged() {
    unawaited(_loadTaskSystemSettings());
  }

  Future<TaskSystemSettings> _loadTaskSystemSettings() async {
    final settings = await _preferencesService.getTaskSystemSettings();
    if (_disposed) return settings;
    if (taskSystemSettings != settings) {
      dispatchTaskSystemSettings(settings);
      emitChange();
    }
    return settings;
  }

  Future<TaskSystemSettings> _refreshTaskSystemSettings() {
    return _loadTaskSystemSettings();
  }

  Future<bool> _taskSystemEnabled() async {
    return (await _refreshTaskSystemSettings()).enabled;
  }

  String get _taskScopeId => currentChatId ?? _chatSessionScopeId;

  Future<String> _ensureTaskScopeId() async => _taskScopeId;

  Future<void> _deleteTransientTasksForCurrentScope() async {
    if (currentChatId != null) return;
    final currentWorkspace = workspace;
    if (currentWorkspace == null || currentWorkspace.missing) return;
    await _taskSessions.deleteTasksForChatSession(
      currentWorkspace,
      chatSessionId: _chatSessionScopeId,
    );
    dispatchActiveTask(null);
    dispatchAvailableTasks(const []);
  }

  Future<void> _deleteTransientProjectsForCurrentScope() async {
    if (currentChatId != null) return;
    final currentWorkspace = workspace;
    if (currentWorkspace == null || currentWorkspace.missing) return;
    await _projectSessions.deleteProjectsForChatSession(
      currentWorkspace,
      chatSessionId: _chatSessionScopeId,
    );
    dispatchActiveProject(null);
    dispatchAvailableProjects(const []);
  }

  List<WorkspaceAttachment> _workspacesForSavedChatDeletion(
    String chatId,
    WorkspaceAttachment? savedWorkspace,
  ) {
    final byRoot = <String, WorkspaceAttachment>{};
    void add(WorkspaceAttachment? item) {
      if (item == null || item.missing) return;
      byRoot[item.rootPath] = item;
    }

    add(savedWorkspace);
    if (currentChatId == chatId) add(workspace);
    return byRoot.values.toList();
  }

  Future<void> _deleteTasksForChatSessionInWorkspaces(
    String chatSessionId,
    Iterable<WorkspaceAttachment> workspaces,
  ) async {
    for (final workspace in workspaces) {
      await _taskSessions.deleteTasksForChatSession(
        workspace,
        chatSessionId: chatSessionId,
      );
    }
  }

  Future<void> _deleteProjectsForChatSessionInWorkspaces(
    String chatSessionId,
    Iterable<WorkspaceAttachment> workspaces,
  ) async {
    for (final workspace in workspaces) {
      await _projectSessions.deleteProjectsForChatSession(
        workspace,
        chatSessionId: chatSessionId,
      );
    }
  }

  Future<void> _clearProjectTaskBlocker() async {
    final project = activeProject;
    final currentWorkspace = workspace;
    if (project == null ||
        currentWorkspace == null ||
        currentWorkspace.missing) {
      return;
    }
    final type = project.blocker?.type;
    if (type != ProjectBlockerType.taskEditApproval &&
        type != ProjectBlockerType.taskBlocked &&
        type != ProjectBlockerType.taskFailed) {
      return;
    }
    dispatchActiveProject(
      await _projectCommands.clearTaskBlocker(
        workspace: currentWorkspace,
        snapshot: project,
      ),
    );
  }

  CancellationToken _beginTaskCancellationScope({bool reuseExisting = false}) {
    final token = _commandCoordinator.begin(reuseExisting: reuseExisting);
    dispatchTaskCancellationRequested(false);
    return token;
  }

  void _endTaskCancellationScope(CancellationToken token) {
    _commandCoordinator.end(token);
    dispatchTaskCancellationRequested(false);
  }

  // ── Task model output management ────────────────────────────────────────

  void _beginTaskModelOutput(String title) {
    _finishTaskModelOutputBubble(clearCurrent: true);
    dispatchTaskModelOutputTitle(title);
    dispatchTaskModelOutputText('');
    dispatchTaskModelOutputReasoning('');
    dispatchTaskModelOutputActive(true);
    _taskModelOutputLabel = null;
    _taskModelOutputTextSection = null;
    _taskModelOutputReasoningLabel = null;
    _taskModelOutputContextEstimate = null;
  }

  void _clearTaskModelOutput({bool notify = true}) {
    _finishTaskModelOutputBubble(clearCurrent: true);
    _taskModelOutputNotifier.cancel();
    dispatchTaskModelOutputTitle(null);
    dispatchTaskModelOutputText('');
    dispatchTaskModelOutputReasoning('');
    dispatchTaskModelOutputActive(false);
    _taskModelOutputLabel = null;
    _taskModelOutputTextSection = null;
    _taskModelOutputReasoningLabel = null;
    _taskModelOutputContextEstimate = null;
    if (notify && !_disposed) emitChange();
  }

  void _handleTaskModelOutput(TaskModelOutputEvent event) {
    if (taskModelOutputTitle == null) {
      _beginTaskModelOutput('Task Model Output');
    }

    var notifyImmediately = false;
    switch (event.type) {
      case TaskModelOutputEventType.start:
        notifyImmediately = true;
        _taskModelOutputContextEstimate = event.estimatedContextTokens;
        serverManager.telemetry.updateContextEstimate(
          event.estimatedContextTokens,
          contextLimitTokens: _diagnosticsContextLimit,
        );
        _session.startTaskModelOutputBubble();
        _taskModelOutputLabel = event.label;
        _taskModelOutputTextSection = null;
        appendTaskModelOutputText('\n\n## ${event.label}\n');
      case TaskModelOutputEventType.content:
        _ensureTaskModelTextSection(event.label, 'output');
        appendTaskModelOutputText(event.text);
        _session.appendTaskModelToken(event);
      case TaskModelOutputEventType.reasoning:
        _ensureTaskModelReasoningSection(event.label);
        appendTaskModelOutputReasoning(event.text);
        _session.appendTaskModelToken(event);
      case TaskModelOutputEventType.toolCall:
        _ensureTaskModelTextSection(event.label, 'tool-call');
        appendTaskModelOutputText('\nTool call:\n${event.text}\n');
        _session.appendTaskModelToken(event);
      case TaskModelOutputEventType.toolResult:
        _ensureTaskModelTextSection(event.label, 'tool-result');
        appendTaskModelOutputText('\nTool result:\n${event.text}\n');
        _session.appendTaskToolResult(event);
      case TaskModelOutputEventType.done:
        notifyImmediately = true;
        _taskModelOutputTextSection = null;
        _session.normaliseTaskModelOutputBubble();
      case TaskModelOutputEventType.error:
        notifyImmediately = true;
        _ensureTaskModelTextSection(event.label, 'error');
        appendTaskModelOutputText('\nError: ${event.text}\n');
        _session.flushPendingTokens();
        messageStore.appendCurrentError(event.text);
    }

    _notifyTaskModelOutputChanged(immediate: notifyImmediately);
  }

  void _notifyTaskModelOutputChanged({bool immediate = false}) {
    if (_disposed) return;
    if (immediate) {
      _taskModelOutputNotifier.cancel();
      emitChange();
      return;
    }

    _taskModelOutputNotifier.schedule();
  }

  void _ensureTaskModelTextSection(String label, String section) {
    if (_taskModelOutputLabel != label) {
      _taskModelOutputLabel = label;
      _taskModelOutputTextSection = null;
      appendTaskModelOutputText('\n\n## $label\n');
    }
    if (_taskModelOutputTextSection == section) return;
    _taskModelOutputTextSection = section;
    switch (section) {
      case 'output':
      case 'tool-call':
      case 'tool-result':
      case 'error':
        appendTaskModelOutputText('\n');
    }
  }

  void _ensureTaskModelReasoningSection(String label) {
    if (_taskModelOutputReasoningLabel == label) return;
    _taskModelOutputReasoningLabel = label;
    appendTaskModelOutputReasoning(
      '${taskModelOutputReasoning.trim().isEmpty ? '' : '\n\n'}## $label\n',
    );
  }

  void _finishTaskModelOutputBubble({required bool clearCurrent}) {
    final id = _session.taskModelOutputMessageId;
    if (id == null) return;
    _session.normaliseTaskModelOutputBubble();
    final index = messageStore.messages.indexWhere(
      (message) => message.id == id,
    );
    if (index >= 0) {
      final message = messageStore.messages[index];
      if (message.text.trim().isEmpty &&
          message.reasoning.trim().isEmpty &&
          message.tools.isEmpty) {
        messageStore.removeById(id);
      }
    }
    if (clearCurrent && messageStore.currentMessage?.id == id) {
      messageStore.clearCurrentId();
    }
    _session.clearTaskModelOutputBubble();
  }

  void _finishTaskModelOutput() {
    _finishTaskModelOutputBubble(clearCurrent: true);
    dispatchTaskModelOutputActive(false);
    _taskModelOutputContextEstimate = null;
    _requestContextEstimateUpdate(immediate: true);
  }

  void _insertTaskAssistantMessage(String text) {
    if (!taskSystemSettings.showTaskMessagesInChat) return;
    messageStore.upsert(
      Bubble(
        id: uuid.v7(),
        role: MessageRole.assistant,
        text: text,
        reasoning: '',
        createdAt: DateTime.now(),
      ),
    );
  }

  /// Inserts a bubble indicating that a task operation failed.
  void _insertTaskErrorBubble(String errorMessage) {
    messageStore.upsert(
      Bubble(
        id: uuid.v7(),
        role: MessageRole.assistant,
        text: errorMessage,
        reasoning: '',
        createdAt: DateTime.now(),
      ),
    );
  }

  // ── Context estimation ──────────────────────────────────────────────────

  void _requestContextEstimateUpdate({bool immediate = false}) {
    if (_disposed) return;
    final activeOutput = chatStream.isStreaming || taskModelOutputActive;
    if (immediate || !activeOutput) {
      _contextEstimateScheduler.cancel();
      _updateContextEstimate();
      return;
    }

    _contextEstimateScheduler.schedule();
  }

  void _updateContextEstimate() {
    if (taskModelOutputActive && _taskModelOutputContextEstimate != null) {
      serverManager.telemetry.updateContextEstimate(
        _taskModelOutputContextEstimate,
        contextLimitTokens: _diagnosticsContextLimit,
      );
      return;
    }

    final snapshot = currentModelSnapshot;
    if (snapshot == null || messageStore.messages.isEmpty) {
      serverManager.telemetry.updateContextEstimate(null);
      return;
    }

    final payload = PayloadBuilder.buildPayloadWithTools(
      messages: _payloadMessages(),
      upToIndexInclusive: messageStore.messages.length - 1,
      omitCoveredMessages: true,
    );
    serverManager.telemetry.updateContextEstimate(
      ContextEstimator.estimateChatCompletionRequest(messages: payload),
      contextLimitTokens: snapshot.nCtx,
    );
  }

  void _scheduleAutosave() {
    if (_disposed || currentChatId == null) return;
    _autosave.schedule(() async {
      final save = _queueSave();
      unawaited(save.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
    });
  }

  void _markPersistableChange() {
    if (_disposed || _loadingSnapshot) return;
    _currentPersistenceRevision++;
    _scheduleAutosave();
  }

  void _resetPersistenceRevisions() {
    _currentPersistenceRevision = 0;
    _persistedRevision = 0;
  }

  Future<SavedChat> _queueSave({String? title, bool force = false}) {
    _session.flushPendingTokens();
    _autosave.cancelPendingSchedule();

    final completer = Completer<SavedChat>();

    final operation = _autosave.enqueue(() async {
      if (_disposed) {
        throw StateError('ChatRuntimeController is disposed');
      }

      if (!force && currentChatId != null && !_hasPendingPersistence) {
        return currentSavedChat!;
      }

      final capturedRevision = _currentPersistenceRevision;
      final previousChatId = currentChatId;
      final previousScopeId = _taskScopeId;
      final capturedMessages = messageStore.messages.toList(growable: false);
      final capturedModelSnapshot = currentModelSnapshot;
      final capturedWorkspace = workspace;
      final capturedSystemPromptSnapshot = currentSystemPromptSnapshot;
      final capturedActiveTaskId = activeTask?.id;
      final capturedActiveProjectId = activeProject?.id;
      final saved = await _persistenceRuntime.save(
        ChatPersistenceRequest(
          chatId: previousChatId,
          title: title,
          messages: capturedMessages,
          modelSnapshot: capturedModelSnapshot,
          workspace: capturedWorkspace,
          systemPromptSnapshot: capturedSystemPromptSnapshot,
        ),
      );

      dispatchCurrentChatId(saved.id);
      _chatSessionScopeId = saved.id;
      dispatchCurrentSavedChat(saved);
      if (previousChatId == null) {
        _pendingScopeMove ??= _PendingScopeMove(
          previousScopeId: previousScopeId,
          savedChatId: saved.id,
          workspace: capturedWorkspace,
          activeTaskId: capturedActiveTaskId,
          activeProjectId: capturedActiveProjectId,
        );
      }
      final pendingMove = _pendingScopeMove;
      if (pendingMove != null && pendingMove.savedChatId == saved.id) {
        await _moveTaskScope(
          previousScopeId: pendingMove.previousScopeId,
          savedChatId: pendingMove.savedChatId,
          scopeWorkspace: pendingMove.workspace,
          activeTaskId: pendingMove.activeTaskId,
        );
        await _moveProjectScope(
          previousScopeId: pendingMove.previousScopeId,
          savedChatId: pendingMove.savedChatId,
          scopeWorkspace: pendingMove.workspace,
          activeProjectId: pendingMove.activeProjectId,
        );
        _pendingScopeMove = null;
      }
      _persistedRevision = capturedRevision;
      dispatchSaveFailure(null);
      if (_hasPendingPersistence) _scheduleAutosave();
      emitChange();
      return saved;
    });

    operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {
        _recordSaveFailure(error, stackTrace);
      },
    );
    operation.then(completer.complete, onError: completer.completeError);
    return completer.future;
  }

  Future<void> _moveTaskScope({
    required String previousScopeId,
    required String savedChatId,
    required WorkspaceAttachment? scopeWorkspace,
    required String? activeTaskId,
  }) async {
    if (previousScopeId == savedChatId) return;
    final currentWorkspace = scopeWorkspace;
    if (currentWorkspace == null || currentWorkspace.missing) return;

    final tasks = await _taskQueries.listTasks(
      currentWorkspace,
      chatSessionId: previousScopeId,
    );
    for (final task in tasks) {
      final snapshot = await _taskQueries.loadTask(
        currentWorkspace,
        task.id,
        chatSessionId: previousScopeId,
      );
      if (snapshot == null) continue;
      final updated = await _taskSessions.updateTaskChatSessionId(
        workspace: currentWorkspace,
        snapshot: snapshot,
        chatSessionId: savedChatId,
      );
      if (updated.id == activeTaskId &&
          workspace?.rootPath == currentWorkspace.rootPath) {
        dispatchActiveTask(updated);
      }
    }
    final scopedTasks = await _taskQueries.listTasks(
      currentWorkspace,
      chatSessionId: savedChatId,
    );
    if (workspace?.rootPath == currentWorkspace.rootPath) {
      dispatchAvailableTasks(scopedTasks);
    }
  }

  Future<void> _moveProjectScope({
    required String previousScopeId,
    required String savedChatId,
    required WorkspaceAttachment? scopeWorkspace,
    required String? activeProjectId,
  }) async {
    if (previousScopeId == savedChatId) return;
    final currentWorkspace = scopeWorkspace;
    if (currentWorkspace == null || currentWorkspace.missing) return;

    final projects = await _projectQueries.listProjects(
      currentWorkspace,
      chatSessionId: previousScopeId,
    );
    for (final project in projects) {
      final snapshot = await _projectQueries.loadProject(
        currentWorkspace,
        project.id,
        chatSessionId: previousScopeId,
      );
      if (snapshot == null) continue;
      final updated = await _projectSessions.updateProjectChatSessionId(
        workspace: currentWorkspace,
        snapshot: snapshot,
        chatSessionId: savedChatId,
      );
      if (updated.id == activeProjectId &&
          workspace?.rootPath == currentWorkspace.rootPath) {
        dispatchActiveProject(updated);
      }
    }
    final scopedProjects = await _projectQueries.listProjects(
      currentWorkspace,
      chatSessionId: savedChatId,
    );
    if (workspace?.rootPath == currentWorkspace.rootPath) {
      dispatchAvailableProjects(scopedProjects);
    }
  }

  Future<void> _prepareModelRestorePrompt(
    ModelConfigurationSnapshot? snapshot,
  ) async {
    dispatchPendingModelRestore(null);
    dispatchPendingModelRestoreIssue(null);

    if (snapshot == null || snapshot.matches(_activeServerSnapshot)) return;

    dispatchPendingModelRestore(snapshot);
    final availability = await serverManager.validateConfiguration(snapshot);
    if (availability.modelPathMissing) {
      dispatchPendingModelRestoreIssue(
        'Saved model file not found: ${snapshot.modelPath}',
      );
      return;
    }

    final mtpModelPath = snapshot.mtpModelPath;
    if (availability.mtpModelPathMissing && mtpModelPath != null) {
      dispatchPendingModelRestoreIssue(
        'Saved MTP model file not found: $mtpModelPath',
      );
    }
  }

  void _clearSavedState() {
    dispatchCurrentChatId(null);
    _chatSessionScopeId = uuid.v7();
    dispatchCurrentSavedChat(null);
    dispatchWorkspace(null);
    dispatchActiveProject(null);
    dispatchAvailableProjects(const []);
    dispatchActiveTask(null);
    dispatchAvailableTasks(const []);
    dispatchTaskError(null);
    dispatchTaskStatusMessage(null);
    dispatchCurrentSystemPromptSnapshot(null);
    dispatchPendingModelRestore(null);
    dispatchPendingModelRestoreIssue(null);
    _pendingScopeMove = null;
    _resetPersistenceRevisions();
    dispatchSaveFailure(null);
    emitChange();
  }

  void _recordSaveFailure(Object error, StackTrace stackTrace) {
    dispatchSaveFailure(
      ChatSaveFailure(
        error: error,
        stackTrace: stackTrace,
        occurredAt: DateTime.now(),
      ),
    );
    if (!_disposed) emitChange();
  }

  Future<WorkspaceAttachment?> _restoreWorkspace(
    WorkspaceAttachment? saved,
  ) async {
    if (saved == null) return null;
    return _workspaceService.restore(
      rootPath: saved.rootPath,
      displayName: saved.displayName,
      lastOpenedAt: saved.lastOpenedAt,
    );
  }

  // ── System prompt construction ──────────────────────────────────────────

  String _buildSystemPrompt({
    String? currentUserRequest,
    List<String> additionalModuleIds = const [],
  }) {
    return _promptConstruction.build(
      snapshot: currentSystemPromptSnapshot,
      workspace: workspace,
      currentUserRequest: currentUserRequest,
      additionalModuleIds: additionalModuleIds,
    );
  }

  String _buildTaskSystemPrompt(Task snapshot) {
    return _buildSystemPrompt(currentUserRequest: snapshot.originalPrompt);
  }

  String _buildProjectSystemPrompt(ProjectAggregate snapshot) {
    return _buildSystemPrompt(currentUserRequest: snapshot.originalGoal);
  }

  List<Bubble> _withCurrentSystemPrompt(
    List<Bubble> messages, {
    String? currentUserRequest,
  }) {
    final promptText = _buildSystemPrompt(
      currentUserRequest: currentUserRequest,
    );
    if (messages.isEmpty) return [systemPrompt.copyWith(text: promptText)];

    final copy = List<Bubble>.of(messages);
    if (copy.first.role == MessageRole.system) {
      copy[0] = copy.first.copyWith(text: promptText);
    } else {
      copy.insert(0, systemPrompt.copyWith(text: promptText));
    }
    return copy;
  }

  void _syncSystemPrompt() {
    messageStore.setMessages(_withCurrentSystemPrompt(messageStore.messages));
  }

  List<Bubble> _payloadMessages({String? currentUserRequest}) {
    return _withCurrentSystemPrompt(
      messageStore.messages,
      currentUserRequest: currentUserRequest,
    );
  }

  void _markWorkspaceChanged() {
    _markPersistableChange();
    emitChange();
  }

  void _adoptActiveModelIfRestoreDismissed() {
    if (pendingModelRestore != null) return;

    final activeSnapshot = _activeServerSnapshot;
    if (activeSnapshot != null &&
        !activeSnapshot.matches(currentModelSnapshot)) {
      dispatchCurrentModelSnapshot(activeSnapshot);
      _requestContextEstimateUpdate(immediate: true);
      _markPersistableChange();
      emitChange();
    }
  }

  // Presentation message construction is delegated to
  // ChatPresentationMessageBuilder.
}
