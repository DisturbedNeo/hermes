// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member, unused_element, unused_field
part of 'chat_controller.dart';

extension _ChatPersistenceOperations on _ChatApplicationContext {
  void _handlePreferencesChanged() {
    unawaited(_loadTaskSystemSettings());
  }

  Future<TaskSystemSettings> _loadTaskSystemSettings() async {
    final settings = await _preferencesService.getTaskSystemSettings();
    if (_disposed) return settings;
    if (taskSystemSettings != settings) {
      taskSystemSettings = settings;
      notifyListeners();
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
    await _taskController.deleteTasksForChatSession(
      currentWorkspace,
      chatSessionId: _chatSessionScopeId,
    );
    activeTask = null;
    availableTasks = const [];
  }

  Future<void> _deleteTransientProjectsForCurrentScope() async {
    if (currentChatId != null) return;
    final currentWorkspace = workspace;
    if (currentWorkspace == null || currentWorkspace.missing) return;
    await _projectApplication.deleteProjectsForChatSession(
      currentWorkspace,
      chatSessionId: _chatSessionScopeId,
    );
    activeProject = null;
    availableProjects = const [];
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
      await _taskController.deleteTasksForChatSession(
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
      await _projectApplication.deleteProjectsForChatSession(
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
    activeProject = await _projectApplication.clearTaskBlocker(
      workspace: currentWorkspace,
      snapshot: project,
    );
  }

  CancellationToken _beginTaskCancellationScope({bool reuseExisting = false}) {
    final token = _commandCoordinator.begin(reuseExisting: reuseExisting);
    taskCancellationRequested = false;
    return token;
  }

  void _endTaskCancellationScope(CancellationToken token) {
    _commandCoordinator.end(token);
    taskCancellationRequested = false;
  }

  // ── Task model output management ────────────────────────────────────────

  void _beginTaskModelOutput(String title) {
    _finishTaskModelOutputBubble(clearCurrent: true);
    taskModelOutputTitle = title;
    taskModelOutputText = '';
    taskModelOutputReasoning = '';
    taskModelOutputActive = true;
    _taskModelOutputLabel = null;
    _taskModelOutputTextSection = null;
    _taskModelOutputReasoningLabel = null;
    _taskModelOutputContextEstimate = null;
  }

  void _clearTaskModelOutput({bool notify = true}) {
    _finishTaskModelOutputBubble(clearCurrent: true);
    _taskModelOutputNotifier.cancel();
    taskModelOutputTitle = null;
    taskModelOutputText = '';
    taskModelOutputReasoning = '';
    taskModelOutputActive = false;
    _taskModelOutputLabel = null;
    _taskModelOutputTextSection = null;
    _taskModelOutputReasoningLabel = null;
    _taskModelOutputContextEstimate = null;
    if (notify && !_disposed) notifyListeners();
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
        serverManager.diagnostics.updateContextEstimate(
          event.estimatedContextTokens,
          contextLimitTokens: _diagnosticsContextLimit,
        );
        _session.startTaskModelOutputBubble();
        _taskModelOutputLabel = event.label;
        _taskModelOutputTextSection = null;
        taskModelOutputText += '\n\n## ${event.label}\n';
      case TaskModelOutputEventType.content:
        _ensureTaskModelTextSection(event.label, 'output');
        taskModelOutputText += event.text;
        _session.appendTaskModelToken(event);
      case TaskModelOutputEventType.reasoning:
        _ensureTaskModelReasoningSection(event.label);
        taskModelOutputReasoning += event.text;
        _session.appendTaskModelToken(event);
      case TaskModelOutputEventType.toolCall:
        _ensureTaskModelTextSection(event.label, 'tool-call');
        taskModelOutputText += '\nTool call:\n${event.text}\n';
        _session.appendTaskModelToken(event);
      case TaskModelOutputEventType.toolResult:
        _ensureTaskModelTextSection(event.label, 'tool-result');
        taskModelOutputText += '\nTool result:\n${event.text}\n';
        _session.appendTaskToolResult(event);
      case TaskModelOutputEventType.done:
        notifyImmediately = true;
        _taskModelOutputTextSection = null;
        _session.normaliseTaskModelOutputBubble();
      case TaskModelOutputEventType.error:
        notifyImmediately = true;
        _ensureTaskModelTextSection(event.label, 'error');
        taskModelOutputText += '\nError: ${event.text}\n';
        _session.flushPendingTokens();
        messageStore.appendCurrentError(event.text);
    }

    _notifyTaskModelOutputChanged(immediate: notifyImmediately);
  }

  void _notifyTaskModelOutputChanged({bool immediate = false}) {
    if (_disposed) return;
    if (immediate) {
      _taskModelOutputNotifier.cancel();
      notifyListeners();
      return;
    }

    _taskModelOutputNotifier.schedule();
  }

  void _ensureTaskModelTextSection(String label, String section) {
    if (_taskModelOutputLabel != label) {
      _taskModelOutputLabel = label;
      _taskModelOutputTextSection = null;
      taskModelOutputText += '\n\n## $label\n';
    }
    if (_taskModelOutputTextSection == section) return;
    _taskModelOutputTextSection = section;
    switch (section) {
      case 'output':
      case 'tool-call':
      case 'tool-result':
      case 'error':
        taskModelOutputText += '\n';
    }
  }

  void _ensureTaskModelReasoningSection(String label) {
    if (_taskModelOutputReasoningLabel == label) return;
    _taskModelOutputReasoningLabel = label;
    taskModelOutputReasoning +=
        '${taskModelOutputReasoning.trim().isEmpty ? '' : '\n\n'}## $label\n';
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
    taskModelOutputActive = false;
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
      serverManager.diagnostics.updateContextEstimate(
        _taskModelOutputContextEstimate,
        contextLimitTokens: _diagnosticsContextLimit,
      );
      return;
    }

    final snapshot = currentModelSnapshot;
    if (snapshot == null || messageStore.messages.isEmpty) {
      serverManager.diagnostics.updateContextEstimate(null);
      return;
    }

    final payload = PayloadBuilder.buildPayloadWithTools(
      messages: _payloadMessages(),
      upToIndexInclusive: messageStore.messages.length - 1,
      omitCoveredMessages: true,
    );
    serverManager.diagnostics.updateContextEstimate(
      ContextEstimator.estimateChatCompletionRequest(messages: payload),
      contextLimitTokens: snapshot.nCtx,
    );
  }

  void _scheduleAutosave() {
    if (_disposed || currentChatId == null) return;
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(const Duration(milliseconds: 600), () {
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
    _autosaveTimer?.cancel();
    _autosaveTimer = null;

    final completer = Completer<SavedChat>();

    final operation = _saveChain.then((_) async {
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
      final saved = await _chatLibrary.saveChatSnapshot(
        chatId: previousChatId,
        title: title,
        messages: capturedMessages,
        modelSnapshot: capturedModelSnapshot,
        workspace: capturedWorkspace,
        systemPromptSnapshot: capturedSystemPromptSnapshot,
      );

      currentChatId = saved.id;
      _chatSessionScopeId = saved.id;
      currentSavedChat = saved;
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
      saveFailure = null;
      if (_hasPendingPersistence) _scheduleAutosave();
      notifyListeners();
      return saved;
    });

    _saveChain = operation.then<void>(
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

    final tasks = await _taskController.listTasks(
      currentWorkspace,
      chatSessionId: previousScopeId,
    );
    for (final task in tasks) {
      final snapshot = await _taskController.loadTask(
        currentWorkspace,
        task.id,
        chatSessionId: previousScopeId,
      );
      if (snapshot == null) continue;
      final updated = await _taskController.updateTaskChatSessionId(
        workspace: currentWorkspace,
        snapshot: snapshot,
        chatSessionId: savedChatId,
      );
      if (updated.id == activeTaskId &&
          workspace?.rootPath == currentWorkspace.rootPath) {
        activeTask = updated;
      }
    }
    final scopedTasks = await _taskController.listTasks(
      currentWorkspace,
      chatSessionId: savedChatId,
    );
    if (workspace?.rootPath == currentWorkspace.rootPath) {
      availableTasks = scopedTasks;
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

    final projects = await _projectApplication.listProjects(
      currentWorkspace,
      chatSessionId: previousScopeId,
    );
    for (final project in projects) {
      final snapshot = await _projectApplication.loadProject(
        currentWorkspace,
        project.id,
        chatSessionId: previousScopeId,
      );
      if (snapshot == null) continue;
      final updated = await _projectApplication.updateProjectChatSessionId(
        workspace: currentWorkspace,
        snapshot: snapshot,
        chatSessionId: savedChatId,
      );
      if (updated.id == activeProjectId &&
          workspace?.rootPath == currentWorkspace.rootPath) {
        activeProject = updated;
      }
    }
    final scopedProjects = await _projectApplication.listProjects(
      currentWorkspace,
      chatSessionId: savedChatId,
    );
    if (workspace?.rootPath == currentWorkspace.rootPath) {
      availableProjects = scopedProjects;
    }
  }

  Future<void> _prepareModelRestorePrompt(
    ModelConfigurationSnapshot? snapshot,
  ) async {
    pendingModelRestore = null;
    pendingModelRestoreIssue = null;

    if (snapshot == null || snapshot.matches(_activeServerSnapshot)) return;

    pendingModelRestore = snapshot;
    if (!await File(snapshot.modelPath).exists()) {
      pendingModelRestoreIssue =
          'Saved model file not found: ${snapshot.modelPath}';
      return;
    }

    final mtpModelPath = snapshot.mtpModelPath;
    if (snapshot.mtpEnabled &&
        mtpModelPath != null &&
        !await File(mtpModelPath).exists()) {
      pendingModelRestoreIssue =
          'Saved MTP model file not found: $mtpModelPath';
    }
  }

  void _clearSavedState() {
    currentChatId = null;
    _chatSessionScopeId = uuid.v7();
    currentSavedChat = null;
    workspace = null;
    activeProject = null;
    availableProjects = const [];
    activeTask = null;
    availableTasks = const [];
    taskError = null;
    taskStatusMessage = null;
    currentSystemPromptSnapshot = null;
    pendingModelRestore = null;
    pendingModelRestoreIssue = null;
    _pendingScopeMove = null;
    _resetPersistenceRevisions();
    saveFailure = null;
    notifyListeners();
  }

  void _recordSaveFailure(Object error, StackTrace stackTrace) {
    saveFailure = ChatSaveFailure(
      error: error,
      stackTrace: stackTrace,
      occurredAt: DateTime.now(),
    );
    if (!_disposed) notifyListeners();
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
    final snapshot = currentSystemPromptSnapshot;
    if (snapshot?.preset != null) {
      final result = _promptAssembler.assemble(
        PromptAssemblyRequest(
          preset: snapshot!.preset,
          availableModules: snapshot.modules,
          selectedModuleIds: {
            ...snapshot.selectedModuleIds,
            ...additionalModuleIds,
          }.toList(),
          autoModuleIds: _autoModuleIdsForWorkspace(),
          workspaceRootPath: workspace?.rootPath,
          workspaceMissing: workspace?.missing ?? false,
          commandExecutionApproved: workspace?.commandExecutionApproved == true,
          currentUserRequest: currentUserRequest,
        ),
      );
      if (result.text.trim().isNotEmpty) return result.text;
      if (snapshot.text.trim().isNotEmpty) return snapshot.text.trim();
    }

    final basePrompt =
        currentSystemPromptSnapshot?.text.trim().isNotEmpty == true
        ? currentSystemPromptSnapshot!.text.trim()
        : _ChatApplicationContext.defaultSystemPromptText;
    final currentWorkspace = workspace;
    if (currentWorkspace == null) {
      return basePrompt;
    }

    if (currentWorkspace.missing) {
      return '$basePrompt\n\nA workspace was attached to this chat, but the folder is currently missing, so workspace tools are unavailable.';
    }

    final terminalStatus = currentWorkspace.commandExecutionApproved
        ? 'enabled for this chat'
        : 'disabled for this chat until the user enables it from the workspace chip';

    return '''
$basePrompt

This chat has an attached workspace. The workspace root is:
${currentWorkspace.rootPath}

Workspace rules:
- Use workspace tools for file and folder operations.
- Only operate inside the attached workspace and use workspace-relative paths.
- Inspect relevant files before editing them.
- Prefer small, precise changes.
- Explain destructive file operations before performing them.
- Host terminal commands run with the application's host permissions, are not confined to the workspace, and are currently $terminalStatus.
'''
        .trim();
  }
}
