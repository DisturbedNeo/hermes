part of 'chat_session_orchestrator.dart';

/// Owns saved-chat lifecycle operations and model-restore transitions.
class ChatSessionLifecycleUseCase {
  ChatSessionLifecycleUseCase(this._host);

  final ChatSessionLifecycleCapabilities _host;

  Future<void> newChat({SystemPromptSnapshot? systemPromptSnapshot}) async {
    await flushCurrentChat();

    if (_host.chatStream.isStreaming) {
      _host.messageStore.clearCurrentId();
      await _host.chatStream.stop();
    }

    await _host._deleteTransientTasksForCurrentScope();
    await _host._deleteTransientProjectsForCurrentScope();
    _host._clearSavedState();
    _host.dispatchCurrentSystemPromptSnapshot(systemPromptSnapshot);
    _host.dispatchActiveProject(null);
    _host.dispatchAvailableProjects(const []);
    _host.dispatchActiveTask(null);
    _host.dispatchAvailableTasks(const []);
    _host.dispatchTaskError(null);
    _host.dispatchTaskStatusMessage(null);
    _host._clearTaskModelOutput(notify: false);
    _host.dispatchCurrentModelSnapshot(_host._activeServerSnapshot);
    _host._historyRevision++;
    final initialMessages = _host._withCurrentSystemPrompt(
      const [],
      currentUserRequest: null,
    );
    if (initialMessages.isNotEmpty) {
      _host._setManagedSystemPromptText(initialMessages.first.text);
    }
    _host.messageStore.setMessages(initialMessages);
    _host._resetPersistenceRevisions();
  }

  Future<bool> openChat(String id) async {
    await flushCurrentChat();

    if (_host.chatStream.isStreaming) {
      _host.messageStore.clearCurrentId();
      await _host.chatStream.stop();
    }

    final snapshot = await _host._chatLibrary.getChat(id);
    if (snapshot == null) return false;

    await _host._deleteTransientTasksForCurrentScope();
    _host.loadingSnapshot = true;
    try {
      _host.dispatchCurrentChatId(snapshot.chat.id);
      _host.chatSessionScopeId = snapshot.chat.id;
      _host.dispatchCurrentSavedChat(snapshot.chat);
      _host.dispatchCurrentModelSnapshot(snapshot.chat.modelSnapshot);
      _host._clearTaskModelOutput(notify: false);
      _host.dispatchWorkspace(
        await _host._restoreWorkspace(snapshot.chat.workspace),
      );
      if (_host.workspace != null && _host.workspace?.missing != true) {
        _host.dispatchActiveProject(
          (await _host._recoverProject(
            _host.workspace!,
            await _host._projectQueries.loadLatestProject(
              _host.workspace!,
              chatSessionId: snapshot.chat.id,
            ),
          ))?.project,
        );
        _host.dispatchAvailableProjects(
          await _host._projectQueries.listProjects(
            _host.workspace!,
            chatSessionId: snapshot.chat.id,
          ),
        );
        _host.dispatchActiveTask(
          await _host._taskForActiveProject(
            _host.workspace!,
            _host.activeProject,
          ),
        );
        if (_host.activeTask == null && _host.activeProject == null) {
          _host.dispatchActiveTask(
            await _host._recoverTaskSnapshot(
              _host.workspace!,
              await _host._taskQueries.loadLatestTask(
                _host.workspace!,
                chatSessionId: snapshot.chat.id,
              ),
            ),
          );
        }
        _host.dispatchAvailableTasks(
          await _host._taskQueries.listTasks(
            _host.workspace!,
            chatSessionId: snapshot.chat.id,
          ),
        );
      } else {
        _host.dispatchActiveProject(null);
        _host.dispatchAvailableProjects(const []);
        _host.dispatchAvailableTasks(const []);
        _host.dispatchActiveTask(null);
      }
      _host.dispatchCurrentSystemPromptSnapshot(null);
      _host._historyRevision++;
      _host.messageStore.setMessages(
        _host._withCurrentSystemPrompt(
          snapshot.messages,
          currentUserRequest: null,
        ),
      );
      // A loaded transcript is user-authored history. Do not let later
      // workspace changes regenerate its system message implicitly.
      _host._setManagedSystemPromptText(null);
      _host._resetPersistenceRevisions();
      await _host._chatLibrary.markOpened(snapshot.chat.id);
      await _host.refreshModelRestorePrompt();
    } finally {
      _host.loadingSnapshot = false;
    }

    _host.emitChange();
    return true;
  }

  Future<SavedChat> saveCurrentChat({String? title}) =>
      _host._queueSave(title: title, force: true);

  Future<SavedChat> retrySave() => _host._queueSave(force: true);

  Future<void> deleteSavedChat(String chatId) async {
    final snapshot = await _host._chatLibrary.getChat(chatId);
    final workspaces = _host._workspacesForSavedChatDeletion(
      chatId,
      snapshot?.chat.workspace,
    );
    await _host._chatLibrary.deleteChat(chatId);
    try {
      await _host._deleteProjectsForChatSessionInWorkspaces(chatId, workspaces);
      await _host._deleteTasksForChatSessionInWorkspaces(chatId, workspaces);
    } finally {
      await resetIfCurrentSavedChatDeleted(chatId);
    }
  }

  Future<void> resetIfCurrentSavedChatDeleted(String chatId) async {
    if (_host.currentChatId == chatId) {
      _host._clearSavedState();
      await newChat();
    }
  }

  Future<void> flushCurrentChat() async {
    _host._autosave.cancelPendingSchedule();
    while (true) {
      await _host._autosave.waitForIdle();
      if (_host.currentChatId == null || !_host._hasPendingPersistence) return;
      await _host._queueSave(force: true);
    }
  }

  Future<void> restorePendingModel() async {
    final snapshot = _host.pendingModelRestore;
    if (snapshot == null) return;

    final availability = await _host.serverLifecycle.validateConfiguration(
      snapshot,
    );
    if (availability.modelPathMissing) {
      throw FlutterError('Saved model file not found: ${snapshot.modelPath}');
    }
    final mtpModelPath = snapshot.mtpModelPath;
    if (availability.mtpModelPathMissing && mtpModelPath != null) {
      throw FlutterError('Saved MTP model file not found: $mtpModelPath');
    }

    _host.dispatchPendingModelRestore(null);
    _host.dispatchPendingModelRestoreIssue(null);
    _host.emitChange();

    await _host.serverLifecycle.startWithSnapshot(snapshot);
    _host.updateCurrentModelSnapshot(snapshot);
  }

  Future<void> refreshModelRestorePrompt() async {
    await _host._prepareModelRestorePrompt(_host.currentModelSnapshot);
    _host.emitChange();
  }
}
