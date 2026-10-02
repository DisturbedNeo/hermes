part of 'chat_session_orchestrator.dart';

/// Owns user-facing session state mutations that are not persistence or work
/// commands. Reducer events remain the only state-write mechanism.
class ChatStateMutationUseCase {
  ChatStateMutationUseCase(this._host);

  final ChatStateMutationCapabilities _host;

  void updateCurrentModelSnapshot(ModelConfigurationSnapshot snapshot) {
    _host.dispatchCurrentModelSnapshot(snapshot);
    _host._requestContextEstimateUpdate(immediate: true);
    _host._markPersistableChange();
    if (_host.pendingModelRestore?.matches(snapshot) ?? false) {
      _host.dispatchPendingModelRestore(null);
      _host.dispatchPendingModelRestoreIssue(null);
    }
    _host.emitChange();
  }

  void dismissPendingModelRestore() {
    _host.dispatchPendingModelRestore(null);
    _host.dispatchPendingModelRestoreIssue(null);
    _host.emitChange();
  }

  void updateSystemPromptSnapshot(SystemPromptSnapshot snapshot) {
    if (_host.isSystemPromptLocked) {
      throw StateError('System prompt is locked for this chat');
    }
    _host.dispatchCurrentSystemPromptSnapshot(snapshot);
    _host._syncSystemPrompt();
    _host.emitChange();
  }

  String buildSystemPromptForTesting({
    String? currentUserRequest,
    List<String> additionalModuleIds = const [],
  }) => _host.buildSystemPromptInternal(
    currentUserRequest: currentUserRequest,
    additionalModuleIds: additionalModuleIds,
  );

  void insertMessage(String text, MessageRole role) {
    if (_host.chatStream.isStreaming) return;
    final t = text.trim();
    if (t.isEmpty) return;
    _host._adoptActiveModelIfRestoreDismissed();
    _host.messageStore.upsert(
      Bubble(
        id: uuid.v7(),
        role: role,
        text: t,
        reasoning: '',
        createdAt: DateTime.now(),
      ),
    );
  }

  void updateCommandExecutionApproval(bool approved) {
    final current = _host.workspace;
    if (current == null) return;
    _host.dispatchWorkspace(
      current.copyWith(commandExecutionApproved: approved),
    );
    _host._markWorkspaceChanged();
  }

  void updateExecutionMode(ExecutionMode mode) {
    if (_host.chatStream.isStreaming || _host.taskBusy) return;
    if (_host.executionMode == mode) return;
    _host.dispatchExecutionMode(mode);
    _host.emitChange();
  }
}
