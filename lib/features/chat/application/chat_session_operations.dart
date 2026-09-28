// ignore_for_file: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member, unused_element, unused_field
part of 'chat_controller.dart';

extension _ChatSessionOperations on _ChatApplicationContext {
  // ── Public API (session management + orchestration) ─────────────────────

  bool get isDirty =>
      currentChatId != null &&
      _currentPersistenceRevision != _persistedRevision;

  bool get _hasPendingPersistence =>
      _currentPersistenceRevision != _persistedRevision;

  bool get hasMeaningfulContent => messageStore.messages.any(
    (message) =>
        message.role != MessageRole.system &&
        (message.text.trim().isNotEmpty ||
            message.reasoning.trim().isNotEmpty ||
            message.tools.isNotEmpty),
  );

  bool get isUnsavedNonEmpty => currentChatId == null && hasMeaningfulContent;

  bool get isSystemPromptLocked =>
      chatStream.isStreaming || hasMeaningfulContent || currentChatId != null;

  bool get hasActiveWorkspace =>
      workspace != null && workspace?.missing != true;

  String? get activeTaskJson =>
      activeTask == null ? null : _taskController.encodeTask(activeTask!);

  String? get activeProjectJson => activeProject == null
      ? null
      : _projectApplication.encodeProject(activeProject!);

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

  ModelConfigurationSnapshot? get _activeServerSnapshot =>
      serverManager.current == null
      ? null
      : serverManager.diagnostics.modelSnapshot;

  int? get _diagnosticsContextLimit =>
      currentModelSnapshot?.nCtx ??
      serverManager.diagnostics.modelSnapshot?.nCtx;

  Future<void> newChat({SystemPromptSnapshot? systemPromptSnapshot}) async {
    await flushCurrentChat();

    if (chatStream.isStreaming) {
      messageStore.clearCurrentId();
      await chatStream.stop();
    }

    await _deleteTransientTasksForCurrentScope();
    await _deleteTransientProjectsForCurrentScope();
    _clearSavedState();
    currentSystemPromptSnapshot = systemPromptSnapshot;
    activeProject = null;
    availableProjects = const [];
    activeTask = null;
    availableTasks = const [];
    taskError = null;
    taskStatusMessage = null;
    _clearTaskModelOutput(notify: false);
    currentModelSnapshot = _activeServerSnapshot;
    _historyRevision++;
    messageStore.setMessages([
      systemPrompt.copyWith(text: _buildSystemPrompt()),
    ]);
    _resetPersistenceRevisions();
  }

  Future<bool> openChat(String id) async {
    await flushCurrentChat();

    if (chatStream.isStreaming) {
      messageStore.clearCurrentId();
      await chatStream.stop();
    }

    final snapshot = await _chatLibrary.getChat(id);
    if (snapshot == null) return false;

    await _deleteTransientTasksForCurrentScope();
    _loadingSnapshot = true;
    try {
      currentChatId = snapshot.chat.id;
      _chatSessionScopeId = snapshot.chat.id;
      currentSavedChat = snapshot.chat;
      currentModelSnapshot = snapshot.chat.modelSnapshot;
      _clearTaskModelOutput(notify: false);
      workspace = await _restoreWorkspace(snapshot.chat.workspace);
      if (workspace != null && workspace?.missing != true) {
        activeProject = (await _recoverProject(
          workspace!,
          await _projectApplication.loadLatestProject(
            workspace!,
            chatSessionId: snapshot.chat.id,
          ),
        ))?.project;
        availableProjects = await _projectApplication.listProjects(
          workspace!,
          chatSessionId: snapshot.chat.id,
        );
        activeTask = await _taskForActiveProject(workspace!, activeProject);
        if (activeTask == null && activeProject == null) {
          activeTask = await _recoverTaskSnapshot(
            workspace!,
            await _taskController.loadLatestTask(
              workspace!,
              chatSessionId: snapshot.chat.id,
            ),
          );
        }
        availableTasks = await _taskController.listTasks(
          workspace!,
          chatSessionId: snapshot.chat.id,
        );
      } else {
        activeProject = null;
        availableProjects = const [];
        availableTasks = const [];
        activeTask = null;
      }
      currentSystemPromptSnapshot = snapshot.chat.systemPromptSnapshot;
      _historyRevision++;
      messageStore.setMessages(_withCurrentSystemPrompt(snapshot.messages));
      _resetPersistenceRevisions();
      await _chatLibrary.markOpened(snapshot.chat.id);
      await refreshModelRestorePrompt();
    } finally {
      _loadingSnapshot = false;
    }

    notifyListeners();
    return true;
  }

  Future<SavedChat> saveCurrentChat({String? title}) async {
    return _queueSave(title: title, force: true);
  }

  Future<SavedChat> retrySave() => _queueSave(force: true);

  Future<void> deleteSavedChat(String chatId) async {
    final snapshot = await _chatLibrary.getChat(chatId);
    final workspaces = _workspacesForSavedChatDeletion(
      chatId,
      snapshot?.chat.workspace,
    );
    await _chatLibrary.deleteChat(chatId);
    try {
      await _deleteProjectsForChatSessionInWorkspaces(chatId, workspaces);
      await _deleteTasksForChatSessionInWorkspaces(chatId, workspaces);
    } finally {
      await resetIfCurrentSavedChatDeleted(chatId);
    }
  }

  Future<void> resetIfCurrentSavedChatDeleted(String chatId) async {
    if (currentChatId == chatId) {
      _clearSavedState();
      await newChat();
    }
  }

  Future<void> flushCurrentChat() async {
    _autosaveTimer?.cancel();
    _autosaveTimer = null;
    while (true) {
      await _saveChain;
      if (currentChatId == null || !_hasPendingPersistence) return;
      await _queueSave(force: true);
    }
  }

  void setCurrentModelSnapshot(ModelConfigurationSnapshot snapshot) {
    currentModelSnapshot = snapshot;
    _requestContextEstimateUpdate(immediate: true);
    _markPersistableChange();

    if (pendingModelRestore?.matches(snapshot) ?? false) {
      pendingModelRestore = null;
      pendingModelRestoreIssue = null;
    }

    notifyListeners();
  }

  Future<void> restorePendingModel() async {
    final snapshot = pendingModelRestore;
    if (snapshot == null) return;

    if (!await File(snapshot.modelPath).exists()) {
      throw FlutterError('Saved model file not found: ${snapshot.modelPath}');
    }
    final mtpModelPath = snapshot.mtpModelPath;
    if (snapshot.mtpEnabled &&
        mtpModelPath != null &&
        !await File(mtpModelPath).exists()) {
      throw FlutterError('Saved MTP model file not found: $mtpModelPath');
    }

    pendingModelRestore = null;
    pendingModelRestoreIssue = null;
    notifyListeners();

    await serverManager.startWithSnapshot(snapshot);
    setCurrentModelSnapshot(snapshot);
  }

  void dismissPendingModelRestore() {
    pendingModelRestore = null;
    pendingModelRestoreIssue = null;
    notifyListeners();
  }

  void setSystemPromptSnapshot(SystemPromptSnapshot snapshot) {
    if (isSystemPromptLocked) {
      throw StateError('System prompt is locked for this chat');
    }

    currentSystemPromptSnapshot = snapshot;
    _syncSystemPrompt();
    notifyListeners();
  }

  @visibleForTesting
  String buildSystemPromptForTesting({
    String? currentUserRequest,
    List<String> additionalModuleIds = const [],
  }) {
    return _buildSystemPrompt(
      currentUserRequest: currentUserRequest,
      additionalModuleIds: additionalModuleIds,
    );
  }

  Future<void> refreshModelRestorePrompt() async {
    await _prepareModelRestorePrompt(currentModelSnapshot);
    notifyListeners();
  }

  void insertMessage(String text, MessageRole role) {
    if (chatStream.isStreaming) return;

    final t = text.trim();

    if (t.isEmpty) return;

    _adoptActiveModelIfRestoreDismissed();

    messageStore.upsert(
      Bubble(
        id: uuid.v7(),
        role: role,
        text: t,
        reasoning: '',
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> attachWorkspace(String folderPath) async {
    if (chatStream.isStreaming) return;
    final previousWorkspace = workspace;
    final previousChatId = currentChatId;
    final previousScopeId = _chatSessionScopeId;
    final nextWorkspace = await _workspaceService.attach(folderPath);
    if (previousChatId == null &&
        previousWorkspace != null &&
        !previousWorkspace.missing &&
        previousWorkspace.rootPath != nextWorkspace.rootPath) {
      await _taskController.deleteTasksForChatSession(
        previousWorkspace,
        chatSessionId: previousScopeId,
      );
      await _projectApplication.deleteProjectsForChatSession(
        previousWorkspace,
        chatSessionId: previousScopeId,
      );
    }
    workspace = nextWorkspace;
    _syncSystemPrompt();
    final scopeId = _taskScopeId;
    activeProject = (await _recoverProject(
      workspace!,
      await _projectApplication.loadLatestProject(
        workspace!,
        chatSessionId: scopeId,
      ),
    ))?.project;
    availableProjects = await _projectApplication.listProjects(
      workspace!,
      chatSessionId: scopeId,
    );
    activeTask = await _taskForActiveProject(workspace!, activeProject);
    if (activeTask == null && activeProject == null) {
      activeTask = await _recoverTaskSnapshot(
        workspace!,
        await _taskController.loadLatestTask(
          workspace!,
          chatSessionId: scopeId,
        ),
      );
    }
    availableTasks = await _taskController.listTasks(
      workspace!,
      chatSessionId: scopeId,
    );
    _markWorkspaceChanged();
  }

  Future<void> detachWorkspace() async {
    if (chatStream.isStreaming) return;
    await _deleteTransientTasksForCurrentScope();
    await _deleteTransientProjectsForCurrentScope();
    workspace = null;
    activeProject = null;
    availableProjects = const [];
    activeTask = null;
    availableTasks = const [];
    _syncSystemPrompt();
    _markWorkspaceChanged();
  }

  void setCommandExecutionApproved(bool approved) {
    final current = workspace;
    if (current == null) return;
    workspace = current.copyWith(commandExecutionApproved: approved);
    _markWorkspaceChanged();
  }

  void setExecutionMode(ExecutionMode mode) {
    if (chatStream.isStreaming || taskBusy) return;
    if (executionMode == mode) return;
    executionMode = mode;
    notifyListeners();
  }

  Future<void> send(String text, {List<String>? tools = const []}) async {
    if (chatStream.isStreaming || taskBusy) return;

    final t = text.trim();
    if (t.isEmpty) return;

    final command = _parseSlashCommand(t);
    if (command != null) {
      await _handleSlashCommand(command);
      return;
    }

    if (executionMode == ExecutionMode.task) {
      final settings = await _refreshTaskSystemSettings();
      await _startTaskFromPrompt(
        t,
        runFirstPhase: !settings.requireApprovalBeforeExecution,
      );
      return;
    }

    if (executionMode == ExecutionMode.project) {
      final settings = await _refreshTaskSystemSettings();
      await _startProjectFromPrompt(
        t,
        runAfterCreation: !settings.requireApprovalBeforeExecution,
      );
      return;
    }

    _adoptActiveModelIfRestoreDismissed();

    messageStore.upsert(
      Bubble(
        id: uuid.v7(),
        role: MessageRole.user,
        text: t,
        reasoning: '',
        createdAt: DateTime.now(),
      ),
    );

    await _session.streamAssistantResponse(
      includeToolResults: false,
      addGenerationPrompt: true,
      selectedToolIds: tools ?? const [],
      anchorId: null,
    );
  }
}
