library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hermes/features/chat/application/contracts/message_role.dart';
import 'package:hermes/features/chat/application/protocol/context_estimator.dart';
import 'package:hermes/core/throttled_scheduler.dart';
import 'package:hermes/core/uuid.dart';
import 'package:hermes/features/chat/application/contracts/bubble.dart';
import 'package:hermes/features/chat/application/contracts/chat_token.dart';
import 'package:hermes/features/chat/application/contracts/chat_persistence.dart';
import 'package:hermes/features/project/application/contracts/project_snapshot_models.dart';
import 'package:hermes/features/task/application/contracts/task_snapshot_models.dart';
import 'package:hermes/features/task/application/contracts/task_system_settings.dart';
import 'package:hermes/features/model/application/model_configuration.dart';
import 'package:hermes/features/chat/application/contracts/saved_chat.dart';
import 'package:hermes/features/chat/application/contracts/system_prompt.dart';
import 'package:hermes/features/workspace/application/workspace.dart';
import 'package:hermes/features/chat/application/contracts/assistant_ops.dart';
import 'package:hermes/features/chat/application/contracts/content_normaliser.dart';
import 'package:hermes/features/chat/application/chat_library_service.dart';
import 'package:hermes/features/chat/runtime/chat_application/chat_session_manager.dart';
import 'package:hermes/features/chat/runtime/chat_application/chat_prompt_construction_service.dart';
import 'package:hermes/features/chat/runtime/chat_application/chat_persistence_runtime.dart';
import 'package:hermes/features/chat/runtime/chat_session_host.dart';
import 'package:hermes/features/chat/runtime/chat_application/chat_command_coordinator.dart';
import 'package:hermes/features/chat/application/chat_view_state.dart';
import 'package:hermes/features/chat/domain/chat_state.dart';
import 'package:hermes/features/chat/domain/chat_panel_read_models.dart';
import 'package:hermes/features/chat/runtime/chat_application/chat_tool_execution_service.dart';
import 'package:hermes/features/chat/runtime/chat_application/chat_stream.dart';
import 'package:hermes/features/chat/runtime/chat_application/message_store.dart';
import 'package:hermes/core/cancellation.dart';
import 'package:hermes/features/project/application/project_application/project_ports.dart';
import 'package:hermes/features/project/application/project_application/project_execution_port.dart';
import 'package:hermes/features/persistence/application/persistence_contracts.dart';
import 'package:hermes/features/model/application/model_output.dart';
import 'package:hermes/features/task/application/task_application/task_ports.dart';
import 'package:hermes/features/task/application/contracts/task_summary.dart';
import 'package:hermes/features/task/application/contracts/task_commands.dart';
import 'package:hermes/features/project/application/contracts/project_commands.dart';
import 'package:hermes/features/model/application/model_server_port.dart';
import 'package:hermes/features/settings/application/preferences_port.dart';
import 'package:hermes/features/chat/application/protocol/payload_builder.dart';
import 'package:hermes/features/tools/application/tool_contracts.dart';
import 'package:hermes/features/tools/application/tool_protocol_adapter.dart';
import 'package:hermes/features/chat/infrastructure/chat_panel_protocol_adapter.dart';
import 'package:hermes/features/workspace/application/workspace_ports.dart';

// ChatSessionRuntime

// Chat session operations

// Chat work operations

// Chat persistence operations

// Chat prompt operations

// Chat lifecycle operations

// Chat operation models

class _SlashCommand {
  final String name;
  final String argument;
  final String raw;

  const _SlashCommand({
    required this.name,
    required this.argument,
    required this.raw,
  });
}

class _PendingScopeMove {
  const _PendingScopeMove({
    required this.previousScopeId,
    required this.savedChatId,
    required this.workspace,
    required this.activeTaskId,
    required this.activeProjectId,
  });

  final String previousScopeId;
  final String savedChatId;
  final WorkspaceAttachment? workspace;
  final String? activeTaskId;
  final String? activeProjectId;
}

class ChatSessionRuntime extends ChangeNotifier implements ChatSessionHost {
  static const String defaultSystemPromptName = 'Default';
  static const String defaultSystemPromptText = 'You are a helpful assistant.';
  static const Duration _contextEstimateThrottle = Duration(milliseconds: 500);
  static const Duration _taskModelOutputNotifyThrottle = Duration(
    milliseconds: 100,
  );

  final String tabId;
  final ModelServerPort serverManager;
  final MessageStore messageStore = MessageStore();
  final ChatStream<ChatToken> chatStream = ChatStream<ChatToken>();

  final ToolRegistryPort _toolService;
  final TaskQueryPort _taskQueries;
  final TaskSessionPort _taskSessions;
  final TaskPresentationPort _taskPresentation;
  final ChatPanelProtocolAdapter _panelProtocol;
  final TaskPlanningPort _taskPlanning;
  final TaskExecutionPort _taskExecution;
  final TaskRecoveryPort _taskRecovery;
  final ProjectQueryPort _projectQueries;
  final ProjectSessionPort _projectSessions;
  final ProjectPlanningPort _projectPlanning;
  final ProjectCommandPort _projectCommands;
  final ProjectExecutionPort _projectExecution;
  final ProjectRecoveryCommandsPort _projectRecovery;
  final ChatLibraryService _chatLibrary;
  final WorkspacePort _workspaceService;
  final PreferencesPort _preferencesService;
  final ChatCommandCoordinator _commandCoordinator;
  final ChatPromptConstructionService _promptConstruction;
  final ChatPersistenceRuntime _persistenceRuntime;

  late final Bubble systemPrompt;

  bool _disposed = false;
  bool _loadingSnapshot = false;
  int _currentPersistenceRevision = 0;
  int _persistedRevision = 0;
  int _historyRevision = 0;
  Timer? _autosaveTimer;
  Future<void> _saveChain = Future.value();
  _PendingScopeMove? _pendingScopeMove;
  Future<void>? _disposeFuture;
  String _chatSessionScopeId = uuid.v7();

  // ── ChatSessionManager instance ─────────────────────────────────────────

  late final ChatSessionManager _session;

  late ChatState _state;
  ProjectAggregate? _activeProjectAggregate;
  Task? _activeTaskAggregate;
  final ChatStateReducer _stateReducer = const ChatStateReducer();

  /// The only authoritative user-visible state for this tab.
  ChatState get state => _state;

  void _dispatchChatState(ChatStateEvent event, {bool notify = true}) {
    _state = _stateReducer.reduce(_state, event);
    if (notify) emitChange();
  }

  /// Publicly-named notification capability for focused runtime services.
  void emitChange() => super.notifyListeners();

  String? get currentChatId => _state.currentChatId;
  void dispatchCurrentChatId(String? value) =>
      _dispatchChatState(ChatCurrentChatChanged(value));

  SavedChat? get currentSavedChat => _state.currentSavedChat;
  void dispatchCurrentSavedChat(SavedChat? value) =>
      _dispatchChatState(ChatSavedChatChanged(value));

  ModelConfigurationSnapshot? get currentModelSnapshot =>
      _state.currentModelSnapshot;
  void dispatchCurrentModelSnapshot(ModelConfigurationSnapshot? value) =>
      _dispatchChatState(ChatModelSnapshotChanged(value));

  ModelConfigurationSnapshot? get pendingModelRestore =>
      _state.pendingModelRestore;
  void dispatchPendingModelRestore(ModelConfigurationSnapshot? value) =>
      _dispatchChatState(ChatPendingModelRestoreChanged(value));

  String? get pendingModelRestoreIssue => _state.pendingModelRestoreIssue;
  void dispatchPendingModelRestoreIssue(String? value) =>
      _dispatchChatState(ChatPendingModelRestoreIssueChanged(value));

  WorkspaceAttachment? get workspace => _state.workspace;
  void dispatchWorkspace(WorkspaceAttachment? value) =>
      _dispatchChatState(ChatWorkspaceChanged(value));

  SystemPromptSnapshot? get currentSystemPromptSnapshot => _state.systemPrompt;
  void dispatchCurrentSystemPromptSnapshot(SystemPromptSnapshot? value) =>
      _dispatchChatState(ChatSystemPromptChanged(value));

  ExecutionMode get executionMode => _state.executionMode;
  void dispatchExecutionMode(ExecutionMode value) =>
      _dispatchChatState(ChatExecutionModeChanged(value));

  ProjectAggregate? get activeProject => _activeProjectAggregate;
  void dispatchActiveProject(ProjectAggregate? value) {
    _activeProjectAggregate = value;
    _dispatchChatState(
      ChatProjectChanged(
        value == null ? null : ProjectPanelReadModel.fromAggregate(value),
      ),
    );
  }

  ProjectPersistenceDiagnostics? get activeProjectPersistenceDiagnostics =>
      _state.activeProjectPersistenceDiagnostics;
  void dispatchActiveProjectPersistenceDiagnostics(
    ProjectPersistenceDiagnostics? value,
  ) {
    _dispatchChatState(ChatProjectDiagnosticsChanged(value));
  }

  List<ProjectSummary> get availableProjects => _state.availableProjects;
  void dispatchAvailableProjects(List<ProjectSummary> value) =>
      _dispatchChatState(ChatProjectsChanged(value));

  Task? get activeTask => _activeTaskAggregate;
  void dispatchActiveTask(Task? value) {
    _activeTaskAggregate = value;
    _dispatchChatState(
      ChatTaskChanged(
        value == null ? null : TaskPanelReadModel.fromAggregate(value),
      ),
    );
  }

  List<TaskSummary> get availableTasks => _state.availableTasks;
  void dispatchAvailableTasks(List<TaskSummary> value) =>
      _dispatchChatState(ChatTasksChanged(value));

  TaskSystemSettings get taskSystemSettings => _state.taskSystemSettings;
  void dispatchTaskSystemSettings(TaskSystemSettings value) =>
      _dispatchChatState(ChatTaskSettingsChanged(value));

  bool get taskBusy => _state.taskBusy;
  void dispatchTaskBusy(bool value) =>
      _dispatchChatState(ChatTaskBusyChanged(value));

  bool get taskCancellationRequested => _state.taskCancellationRequested;
  void dispatchTaskCancellationRequested(bool value) =>
      _dispatchChatState(ChatTaskCancellationChanged(value));

  String? get taskStatusMessage => _state.taskStatusMessage;
  void dispatchTaskStatusMessage(String? value) =>
      _dispatchChatState(ChatTaskStatusMessageChanged(value));

  Object? get taskError => _state.taskError;
  void dispatchTaskError(Object? value) =>
      _dispatchChatState(ChatTaskErrorChanged(value));

  String? get taskModelOutputTitle => _state.taskModelOutputTitle;
  void dispatchTaskModelOutputTitle(String? value) =>
      _dispatchChatState(ChatTaskModelOutputTitleChanged(value));

  String get taskModelOutputText => _state.taskModelOutputText;
  void dispatchTaskModelOutputText(String value) =>
      _dispatchChatState(ChatTaskModelOutputTextChanged(value));
  void appendTaskModelOutputText(String value) =>
      dispatchTaskModelOutputText('$taskModelOutputText$value');

  String get taskModelOutputReasoning => _state.taskModelOutputReasoning;
  void dispatchTaskModelOutputReasoning(String value) =>
      _dispatchChatState(ChatTaskModelOutputReasoningChanged(value));
  void appendTaskModelOutputReasoning(String value) =>
      dispatchTaskModelOutputReasoning('$taskModelOutputReasoning$value');

  bool get taskModelOutputActive => _state.taskModelOutputActive;
  void dispatchTaskModelOutputActive(bool value) =>
      _dispatchChatState(ChatTaskModelOutputActiveChanged(value));

  ChatSaveFailure? get saveFailure => _state.saveFailure;
  void dispatchSaveFailure(ChatSaveFailure? value) =>
      _dispatchChatState(ChatSaveFailureChanged(value));
  String? _taskModelOutputLabel;
  String? _taskModelOutputTextSection;
  String? _taskModelOutputReasoningLabel;
  int? _taskModelOutputContextEstimate;
  late final ThrottledScheduler _contextEstimateScheduler;
  late final ThrottledScheduler _taskModelOutputNotifier;

  /// Changes when this tab replaces its entire displayed conversation.
  int get historyRevision => _historyRevision;

  ChatViewState get viewState => ChatViewState(
    tabId: _state.tabId,
    messages: _state.messages,
    historyRevision: _state.historyRevision,
    currentChatId: _state.currentChatId,
    currentSavedChat: _state.currentSavedChat,
    currentModelSnapshot: _state.currentModelSnapshot,
    pendingModelRestore: _state.pendingModelRestore,
    pendingModelRestoreIssue: _state.pendingModelRestoreIssue,
    workspace: _state.workspace,
    systemPrompt: _state.systemPrompt,
    executionMode: _state.executionMode,
    activeProject: _state.activeProject,
    activeProjectPersistenceDiagnostics:
        _state.activeProjectPersistenceDiagnostics,
    availableProjects: _state.availableProjects,
    activeTask: _state.activeTask,
    availableTasks: _state.availableTasks,
    taskSystemSettings: _state.taskSystemSettings,
    taskBusy: _state.taskBusy,
    taskCancellationRequested: _state.taskCancellationRequested,
    taskStatusMessage: _state.taskStatusMessage,
    taskError: _state.taskError,
    taskModelOutputTitle: _state.taskModelOutputTitle,
    taskModelOutputText: _state.taskModelOutputText,
    taskModelOutputReasoning: _state.taskModelOutputReasoning,
    taskModelOutputActive: _state.taskModelOutputActive,
    saveFailure: _state.saveFailure,
  );

  int? get sessionDiagnosticsContextLimit => _diagnosticsContextLimit;

  String? sessionTaskModelOutputLabel() => _taskModelOutputLabel;

  void updateSessionTaskModelOutputLabel(String? value) {
    _taskModelOutputLabel = value;
  }

  String? sessionTaskModelOutputTextSection() => _taskModelOutputTextSection;

  void updateSessionTaskModelOutputTextSection(String? value) {
    _taskModelOutputTextSection = value;
  }

  String? sessionTaskModelOutputReasoningLabel() =>
      _taskModelOutputReasoningLabel;

  void updateSessionTaskModelOutputReasoningLabel(String? value) {
    _taskModelOutputReasoningLabel = value;
  }

  String buildSystemPrompt({String? currentUserRequest}) =>
      _buildSystemPrompt(currentUserRequest: currentUserRequest);

  void markWorkspaceChanged() {
    _markPersistableChange();
    emitChange();
  }

  void sessionNotifyListeners() => emitChange();

  void requestContextEstimateUpdate({bool immediate = false}) {
    _requestContextEstimateUpdate(immediate: immediate);
  }

  bool get workspaceToolsEnabled => hasActiveWorkspace;

  List<String> get defaultToolIds => workspaceToolsEnabled
      ? _toolService.defaultToolIds(includeWorkspaceTools: true)
      : const [];

  void _disposeChangeNotifier() => super.dispose();

  ChatSessionRuntime({
    String? tabId,
    required this.serverManager,
    required ToolRegistryPort toolService,
    required ToolProtocolAdapter toolProtocol,
    required ChatToolExecutionPort toolExecution,
    required TaskQueryPort taskQueries,
    required TaskSessionPort taskSessions,
    required TaskPresentationPort taskPresentation,
    required ChatPanelProtocolAdapter panelProtocol,
    required TaskPlanningPort taskPlanning,
    required TaskExecutionPort taskExecution,
    required TaskRecoveryPort taskRecovery,
    required ProjectQueryPort projectQueries,
    required ProjectSessionPort projectSessions,
    required ProjectPlanningPort projectPlanning,
    required ProjectCommandPort projectCommands,
    required ProjectExecutionPort projectExecution,
    required ProjectRecoveryCommandsPort projectRecovery,
    required ChatLibraryService chatLibrary,
    required WorkspacePort workspaceService,
    required PreferencesPort preferencesService,
    ChatCommandCoordinator? commandCoordinator,
    SystemPromptSnapshot? initialSystemPromptSnapshot,
  }) : tabId = tabId ?? uuid.v7(),
       _toolService = toolService,
       _chatLibrary = chatLibrary,
       _workspaceService = workspaceService,
       _preferencesService = preferencesService,
       _taskQueries = taskQueries,
       _taskSessions = taskSessions,
       _taskPresentation = taskPresentation,
       _panelProtocol = panelProtocol,
       _taskPlanning = taskPlanning,
       _taskExecution = taskExecution,
       _taskRecovery = taskRecovery,
       _projectQueries = projectQueries,
       _projectSessions = projectSessions,
       _projectPlanning = projectPlanning,
       _projectCommands = projectCommands,
       _projectExecution = projectExecution,
       _projectRecovery = projectRecovery,
       _promptConstruction = const ChatPromptConstructionService(),
       _persistenceRuntime = ChatPersistenceRuntime(library: chatLibrary),
       _commandCoordinator = commandCoordinator ?? ChatCommandCoordinator() {
    _state = ChatState(
      tabId: this.tabId,
      messages: const <Bubble>[],
      historyRevision: _historyRevision,
      systemPrompt: initialSystemPromptSnapshot,
    );
    systemPrompt = Bubble(
      id: uuid.v7(),
      role: MessageRole.system,
      text: _buildSystemPrompt(),
      reasoning: '',
      createdAt: DateTime.now(),
    );
    messageStore.setMessages([systemPrompt]);
    _dispatchChatState(ChatMessagesChanged(messageStore.messages));

    _contextEstimateScheduler = ThrottledScheduler(
      interval: _contextEstimateThrottle,
      onTick: _updateContextEstimate,
    );
    _taskModelOutputNotifier = ThrottledScheduler(
      interval: _taskModelOutputNotifyThrottle,
      onTick: () {
        if (!_disposed) emitChange();
      },
    );
    messageStore.addListener(_handleMessagesChanged);
    _preferencesService.addListener(_handlePreferencesChanged);
    unawaited(_loadTaskSystemSettings());

    dispatchCurrentModelSnapshot(_activeServerSnapshot);

    // Initialize the session manager with all streaming/LLM dependencies
    _session = ChatSessionManager(
      messageStore: messageStore,
      chatStream: chatStream,
      serverManager: serverManager,
      toolService: _toolService,
      toolExecution: toolExecution,
      preferencesService: _preferencesService,
      host: this,
    );
  }

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

  String? get activeTaskJson => _activeTaskAggregate == null
      ? null
      : _panelProtocol.encodeTask(_activeTaskAggregate!);

  String? get activeProjectJson => activeProject == null
      ? null
      : _panelProtocol.encodeProject(_activeProjectAggregate!);

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
      !serverManager.session.value.isActive
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
    dispatchCurrentSystemPromptSnapshot(systemPromptSnapshot);
    dispatchActiveProject(null);
    dispatchAvailableProjects(const []);
    dispatchActiveTask(null);
    dispatchAvailableTasks(const []);
    dispatchTaskError(null);
    dispatchTaskStatusMessage(null);
    _clearTaskModelOutput(notify: false);
    dispatchCurrentModelSnapshot(_activeServerSnapshot);
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
      dispatchCurrentChatId(snapshot.chat.id);
      _chatSessionScopeId = snapshot.chat.id;
      dispatchCurrentSavedChat(snapshot.chat);
      dispatchCurrentModelSnapshot(snapshot.chat.modelSnapshot);
      _clearTaskModelOutput(notify: false);
      dispatchWorkspace(await _restoreWorkspace(snapshot.chat.workspace));
      if (workspace != null && workspace?.missing != true) {
        dispatchActiveProject(
          (await _recoverProject(
            workspace!,
            await _projectQueries.loadLatestProject(
              workspace!,
              chatSessionId: snapshot.chat.id,
            ),
          ))?.project,
        );
        dispatchAvailableProjects(
          await _projectQueries.listProjects(
            workspace!,
            chatSessionId: snapshot.chat.id,
          ),
        );
        dispatchActiveTask(
          await _taskForActiveProject(workspace!, activeProject),
        );
        if (activeTask == null && activeProject == null) {
          dispatchActiveTask(
            await _recoverTaskSnapshot(
              workspace!,
              await _taskQueries.loadLatestTask(
                workspace!,
                chatSessionId: snapshot.chat.id,
              ),
            ),
          );
        }
        dispatchAvailableTasks(
          await _taskQueries.listTasks(
            workspace!,
            chatSessionId: snapshot.chat.id,
          ),
        );
      } else {
        dispatchActiveProject(null);
        dispatchAvailableProjects(const []);
        dispatchAvailableTasks(const []);
        dispatchActiveTask(null);
      }
      dispatchCurrentSystemPromptSnapshot(snapshot.chat.systemPromptSnapshot);
      _historyRevision++;
      messageStore.setMessages(_withCurrentSystemPrompt(snapshot.messages));
      _resetPersistenceRevisions();
      await _chatLibrary.markOpened(snapshot.chat.id);
      await refreshModelRestorePrompt();
    } finally {
      _loadingSnapshot = false;
    }

    emitChange();
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

  void updateCurrentModelSnapshot(ModelConfigurationSnapshot snapshot) {
    dispatchCurrentModelSnapshot(snapshot);
    _requestContextEstimateUpdate(immediate: true);
    _markPersistableChange();

    if (pendingModelRestore?.matches(snapshot) ?? false) {
      dispatchPendingModelRestore(null);
      dispatchPendingModelRestoreIssue(null);
    }

    emitChange();
  }

  Future<void> restorePendingModel() async {
    final snapshot = pendingModelRestore;
    if (snapshot == null) return;

    final availability = await serverManager.validateConfiguration(snapshot);
    if (availability.modelPathMissing) {
      throw FlutterError('Saved model file not found: ${snapshot.modelPath}');
    }
    final mtpModelPath = snapshot.mtpModelPath;
    if (availability.mtpModelPathMissing && mtpModelPath != null) {
      throw FlutterError('Saved MTP model file not found: $mtpModelPath');
    }

    dispatchPendingModelRestore(null);
    dispatchPendingModelRestoreIssue(null);
    emitChange();

    await serverManager.startWithSnapshot(snapshot);
    updateCurrentModelSnapshot(snapshot);
  }

  void dismissPendingModelRestore() {
    dispatchPendingModelRestore(null);
    dispatchPendingModelRestoreIssue(null);
    emitChange();
  }

  void updateSystemPromptSnapshot(SystemPromptSnapshot snapshot) {
    if (isSystemPromptLocked) {
      throw StateError('System prompt is locked for this chat');
    }

    dispatchCurrentSystemPromptSnapshot(snapshot);
    _syncSystemPrompt();
    emitChange();
  }

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
    emitChange();
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
      await _taskSessions.deleteTasksForChatSession(
        previousWorkspace,
        chatSessionId: previousScopeId,
      );
      await _projectSessions.deleteProjectsForChatSession(
        previousWorkspace,
        chatSessionId: previousScopeId,
      );
    }
    dispatchWorkspace(nextWorkspace);
    _syncSystemPrompt();
    final scopeId = _taskScopeId;
    dispatchActiveProject(
      (await _recoverProject(
        workspace!,
        await _projectQueries.loadLatestProject(
          workspace!,
          chatSessionId: scopeId,
        ),
      ))?.project,
    );
    dispatchAvailableProjects(
      await _projectQueries.listProjects(workspace!, chatSessionId: scopeId),
    );
    dispatchActiveTask(await _taskForActiveProject(workspace!, activeProject));
    if (activeTask == null && activeProject == null) {
      dispatchActiveTask(
        await _recoverTaskSnapshot(
          workspace!,
          await _taskQueries.loadLatestTask(workspace!, chatSessionId: scopeId),
        ),
      );
    }
    dispatchAvailableTasks(
      await _taskQueries.listTasks(workspace!, chatSessionId: scopeId),
    );
    _markWorkspaceChanged();
  }

  Future<void> detachWorkspace() async {
    if (chatStream.isStreaming) return;
    await _deleteTransientTasksForCurrentScope();
    await _deleteTransientProjectsForCurrentScope();
    dispatchWorkspace(null);
    dispatchActiveProject(null);
    dispatchAvailableProjects(const []);
    dispatchActiveTask(null);
    dispatchAvailableTasks(const []);
    _syncSystemPrompt();
    _markWorkspaceChanged();
  }

  void updateCommandExecutionApproval(bool approved) {
    final current = workspace;
    if (current == null) return;
    dispatchWorkspace(current.copyWith(commandExecutionApproved: approved));
    _markWorkspaceChanged();
  }

  void updateExecutionMode(ExecutionMode mode) {
    if (chatStream.isStreaming || taskBusy) return;
    if (executionMode == mode) return;
    dispatchExecutionMode(mode);
    emitChange();
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

  Future<void> generateOrContinue({
    List<String>? tools = const [],
    bool preferActiveWork = true,
  }) async {
    if (chatStream.isStreaming || taskBusy) return;

    if (preferActiveWork && await _continueActiveWorkIfAvailable()) {
      return;
    }

    if (messageStore.isEmpty) return;

    _adoptActiveModelIfRestoreDismissed();

    var lastMessage = messageStore.last;
    if (lastMessage.role == MessageRole.assistant) {
      lastMessage = ContentNormaliser.normalise(lastMessage);
      messageStore.upsert(lastMessage);
    }

    final continuationTargetId =
        lastMessage.role == MessageRole.assistant && lastMessage.tools.isEmpty
        ? lastMessage.id
        : null;

    await _session.streamAssistantResponse(
      includeToolResults: false,
      addGenerationPrompt: lastMessage.role != MessageRole.assistant,
      selectedToolIds: tools ?? const [],
      anchorId: null,
      targetAssistantId: continuationTargetId,
    );
  }

  Future<bool> _continueActiveWorkIfAvailable() async {
    final project = activeProject;
    if (project != null) {
      if (project.isTerminal) return false;
      await runProject();
      return true;
    }

    final task = activeTask;
    if (task == null || task.isTerminal || task.nextRunnableStep == null) {
      return false;
    }

    await runTask();
    return true;
  }

  Future<void> cancelGeneration() async {
    await _session.cancelGeneration();
  }

  Future<void> cancelTaskRun() async {
    if (!taskBusy) return;
    final token = _commandCoordinator.activeToken;
    dispatchTaskCancellationRequested(true);
    dispatchTaskStatusMessage('Cancelling run...');
    emitChange();
    if (token == null) {
      await _commandCoordinator.cancel();
      return;
    }
    await _commandCoordinator.cancel();
  }

  Future<void> reloadTasks() async {
    final current = workspace;
    if (current == null || current.missing) {
      dispatchAvailableTasks(const []);
      dispatchAvailableProjects(const []);
      dispatchActiveTask(null);
      dispatchActiveProject(null);
      emitChange();
      return;
    }

    final scopeId = _taskScopeId;
    dispatchActiveProject(
      (await _recoverProject(
        current,
        activeProject ??
            await _projectQueries.loadLatestProject(
              current,
              chatSessionId: scopeId,
            ),
      ))?.project,
    );
    dispatchAvailableProjects(
      await _projectQueries.listProjects(current, chatSessionId: scopeId),
    );
    final activeScopeId = activeTask?.chatSessionId;
    final scopedActiveTask =
        activeTask != null &&
            (activeScopeId == null || activeScopeId == scopeId)
        ? activeTask
        : null;
    dispatchActiveTask(await _taskForActiveProject(current, activeProject));
    if (activeTask == null && activeProject == null) {
      dispatchActiveTask(
        await _recoverTaskSnapshot(
          current,
          scopedActiveTask ??
              await _taskQueries.loadLatestTask(
                current,
                chatSessionId: scopeId,
              ),
        ),
      );
    }
    dispatchAvailableTasks(
      await _taskQueries.listTasks(current, chatSessionId: scopeId),
    );
    emitChange();
  }

  Future<Task?> _recoverTaskSnapshot(
    WorkspaceAttachment current,
    Task? snapshot,
  ) {
    if (snapshot == null) return Future.value();
    return _taskRecovery.recoverTask(workspace: current, snapshot: snapshot);
  }

  Future<ProjectCommandResult?> _recoverProject(
    WorkspaceAttachment current,
    ProjectAggregate? snapshot,
  ) {
    if (snapshot == null) return Future.value();
    return _projectExecution.recover(
      ProjectRecoveryRequest(
        workspace: current,
        snapshot: snapshot,
        onTaskUpdated: (task) => dispatchActiveTask(task),
      ),
    );
  }

  Future<Task?> _taskForActiveProject(
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

  Future<void> resumeLatestTask() async {
    final current = workspace;
    final scopeId = _taskScopeId;
    if (current == null || current.missing || taskBusy) {
      return;
    }
    dispatchActiveTask(
      await _recoverTaskSnapshot(
        current,
        await _taskQueries.loadLatestTask(current, chatSessionId: scopeId),
      ),
    );
    await reloadTasks();
  }

  Future<void> loadTask(String taskId) async {
    final current = workspace;
    final scopeId = _taskScopeId;
    if (current == null || current.missing || taskBusy) {
      return;
    }
    dispatchActiveTask(
      await _recoverTaskSnapshot(
        current,
        await _taskQueries.loadTask(current, taskId, chatSessionId: scopeId),
      ),
    );
    await reloadTasks();
  }

  Future<void> resumeLatestProject() async {
    final current = workspace;
    final scopeId = _taskScopeId;
    if (current == null || current.missing || taskBusy) {
      return;
    }
    final result = await _recoverProject(
      current,
      await _projectQueries.loadLatestProject(current, chatSessionId: scopeId),
    );
    dispatchActiveProject(result?.project);
    dispatchActiveTask(result?.activeTask);
    dispatchActiveProjectPersistenceDiagnostics(result?.persistenceDiagnostics);
    await reloadTasks();
  }

  Future<void> loadProject(String projectId) async {
    final current = workspace;
    final scopeId = _taskScopeId;
    if (current == null || current.missing || taskBusy) {
      return;
    }
    final result = await _recoverProject(
      current,
      await _projectQueries.loadProject(
        current,
        projectId,
        chatSessionId: scopeId,
      ),
    );
    dispatchActiveProject(result?.project);
    dispatchActiveTask(result?.activeTask);
    dispatchActiveProjectPersistenceDiagnostics(result?.persistenceDiagnostics);
    await reloadTasks();
  }

  Future<void> runNextProjectTask() async {
    await _runProjectInternal(maxNewTasks: 1);
  }

  Future<void> runProject() async {
    await _runProjectInternal();
  }

  Future<void> runNextTaskPhase() async {
    await _runNextTaskStepInternal();
  }

  Future<void> runTask() async {
    await _runTaskInternal();
  }

  Future<void> planActiveTask({bool runAfterPlanning = false}) async {
    if (runAfterPlanning) await runTask();
  }

  // ── Task orchestration ──────────────────────────────────────────────────

  Future<void> _runTaskInternal({bool keepBusy = false}) async {
    final currentWorkspace = workspace;
    final client = serverManager.completionProvider;
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
            _taskNeedsInterventionBeforeContinuing(updated)) {
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

  Future<void> retryTaskPhase() async {
    final currentWorkspace = workspace;
    final snapshot = activeTask;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null ||
        taskBusy) {
      return;
    }

    dispatchActiveTask(
      await _taskExecution.retryCurrentStep(
        workspace: currentWorkspace,
        snapshot: snapshot,
      ),
    );
    await _clearProjectTaskBlocker();
    await reloadTasks();
  }

  Future<void> skipTaskPhase() async {
    final currentWorkspace = workspace;
    final snapshot = activeTask;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null ||
        taskBusy) {
      return;
    }

    dispatchActiveTask(
      await _taskExecution.skipCurrentStep(
        workspace: currentWorkspace,
        snapshot: snapshot,
      ),
    );
    await _clearProjectTaskBlocker();
    await reloadTasks();
  }

  Future<void> stopTask() async {
    final currentWorkspace = workspace;
    final snapshot = activeTask;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null) {
      return;
    }

    if (taskBusy) {
      await cancelTaskRun();
      return;
    }

    dispatchActiveTask(
      await _taskExecution.stopTask(
        workspace: currentWorkspace,
        snapshot: snapshot,
      ),
    );
    await reloadTasks();
  }

  Future<void> answerTaskQuestion(String answer) async {
    final currentWorkspace = workspace;
    final snapshot = activeTask;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null ||
        taskBusy) {
      return;
    }

    dispatchActiveTask(
      await _taskExecution.answerOpenQuestion(
        workspace: currentWorkspace,
        snapshot: snapshot,
        answer: answer,
      ),
    );
    await _clearProjectTaskBlocker();
    await reloadTasks();
  }

  Future<void> approveTaskStep() async {
    final currentWorkspace = workspace;
    final snapshot = activeTask;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null ||
        taskBusy) {
      return;
    }

    dispatchActiveTask(
      await _taskExecution.approvePendingStep(
        workspace: currentWorkspace,
        snapshot: snapshot,
      ),
    );
    await _clearProjectTaskBlocker();
    await reloadTasks();
  }

  Future<void> answerProjectQuestion(String answer) async {
    final currentWorkspace = workspace;
    final snapshot = activeProject;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null ||
        taskBusy) {
      return;
    }

    dispatchActiveProject(
      await _projectCommands.answerOpenQuestion(
        workspace: currentWorkspace,
        snapshot: snapshot,
        answer: answer,
      ),
    );
    await reloadTasks();
  }

  Future<void> stopProject() async {
    final currentWorkspace = workspace;
    final snapshot = activeProject;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null) {
      return;
    }

    if (taskBusy) {
      await cancelTaskRun();
      return;
    }

    dispatchActiveProject(
      await _projectCommands.stopProject(
        workspace: currentWorkspace,
        snapshot: snapshot,
      ),
    );
    dispatchActiveTask(null);
    await reloadTasks();
  }

  Future<void> pauseProject() async {
    final currentWorkspace = workspace;
    final snapshot = activeProject;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null ||
        taskBusy) {
      return;
    }

    dispatchActiveProject(
      await _projectCommands.pauseProject(
        workspace: currentWorkspace,
        snapshot: snapshot,
      ),
    );
    await reloadTasks();
  }

  Future<void> retryProjectRecovery(String incidentId) async {
    final currentWorkspace = workspace;
    final snapshot = activeProject;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null ||
        taskBusy) {
      return;
    }

    dispatchActiveProject(
      await _projectRecovery.retryRecoveryIncident(
        workspace: currentWorkspace,
        snapshot: snapshot,
        incidentId: incidentId,
      ),
    );
    await reloadTasks();
  }

  Future<void> approveProjectPlanRevision() async {
    final currentWorkspace = workspace;
    final snapshot = activeProject;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null ||
        taskBusy ||
        snapshot.pendingPlanApproval == null) {
      return;
    }
    dispatchActiveProject(
      await _projectCommands.approvePlanRevision(
        workspace: currentWorkspace,
        snapshot: snapshot,
      ),
    );
    await reloadTasks();
  }

  Future<void> rejectProjectPlanRevision() async {
    final currentWorkspace = workspace;
    final snapshot = activeProject;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null ||
        taskBusy ||
        snapshot.pendingPlanApproval == null) {
      return;
    }
    dispatchActiveProject(
      await _projectCommands.rejectPlanRevision(
        workspace: currentWorkspace,
        snapshot: snapshot,
      ),
    );
    await reloadTasks();
  }

  Future<void> replanProject([String reason = '']) async {
    final currentWorkspace = workspace;
    final snapshot = activeProject;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null ||
        snapshot.activeTaskId != null ||
        snapshot.pendingPlanApproval != null ||
        taskBusy) {
      return;
    }
    dispatchActiveProject(
      await _projectPlanning.requestScopeChange(
        workspace: currentWorkspace,
        snapshot: snapshot,
        context: reason.trim().isEmpty
            ? 'User explicitly requested a roadmap revision.'
            : reason,
      ),
    );
    await reloadTasks();
    await _runProjectInternal();
  }

  Future<void> _handleSlashCommand(_SlashCommand command) async {
    switch (command.name) {
      case 'task':
        if (command.argument.trim().isEmpty) {
          _session.insertUserAndAssistant(
            command.raw,
            'Usage: `/task <request>` creates and runs a structured task.',
          );
          return;
        }
        await _startTaskFromPrompt(command.argument, runFirstPhase: true);
      case 'plan':
        if (command.argument.trim().isEmpty) {
          _session.insertUserAndAssistant(
            command.raw,
            'Usage: `/plan <request>` creates a task plan without running it.',
          );
          return;
        }
        await _startTaskFromPrompt(command.argument, runFirstPhase: false);
      case 'refine':
        await _refinePromptFromCommand(command);
      case 'continue':
        await _continueTaskFromCommand(command.raw);
      case 'project':
        if (command.argument.trim().isEmpty) {
          _session.insertUserAndAssistant(
            command.raw,
            'Usage: `/project <goal>` creates and runs a supervised project.',
          );
          return;
        }
        await _startProjectFromPrompt(command.argument, runAfterCreation: true);
      case 'continue-project':
        await _continueProjectFromCommand(command.raw);
      default:
        throw StateError('Unknown slash command: ${command.name}');
    }
  }

  Future<void> _refinePromptFromCommand(_SlashCommand command) async {
    final client = serverManager.completionProvider;
    if (client == null) return;

    final prompt = command.argument.trim();
    if (prompt.isEmpty) {
      _session.insertUserAndAssistant(
        command.raw,
        'Usage: `/refine <request>` creates a Task Brief without planning or running a task.',
      );
      return;
    }
    if (!await _taskSystemEnabled()) {
      _session.insertUserAndAssistant(
        command.raw,
        'Structured tasks are disabled in Settings.',
      );
      return;
    }

    _adoptActiveModelIfRestoreDismissed();
    messageStore.upsert(
      Bubble(
        id: uuid.v7(),
        role: MessageRole.user,
        text: command.raw,
        reasoning: '',
        createdAt: DateTime.now(),
      ),
    );

    dispatchTaskBusy(true);
    final token = _beginTaskCancellationScope();
    dispatchTaskError(null);
    dispatchTaskStatusMessage('Refining task brief...');
    _beginTaskModelOutput('Task Brief Model Output');
    emitChange();

    try {
      final brief = await _taskPlanning.refineTaskBrief(
        client: client,
        workspace: workspace?.missing == true ? null : workspace,
        userPrompt: prompt,
        selectedMode: ExecutionMode.refine,
        onModelOutput: _handleTaskModelOutput,
        cancellationToken: token,
      );
      messageStore.upsert(
        Bubble(
          id: uuid.v7(),
          role: MessageRole.assistant,
          text: _taskBriefMessage(brief),
          reasoning: '',
          createdAt: DateTime.now(),
        ),
      );
    } on OperationCancelledException {
      _insertTaskAssistantMessage('Task brief refinement cancelled.');
    } catch (e) {
      dispatchTaskError(e);
      _insertTaskErrorBubble('Failed to refine task brief: $e');
    } finally {
      dispatchTaskBusy(false);
      _endTaskCancellationScope(token);
      dispatchTaskStatusMessage(null);
      _finishTaskModelOutput();
      emitChange();
    }
  }

  Future<void> _continueTaskFromCommand(String rawCommand) async {
    if (!await _taskSystemEnabled()) {
      _session.insertUserAndAssistant(
        rawCommand,
        'Structured tasks are disabled in Settings.',
      );
      return;
    }

    _adoptActiveModelIfRestoreDismissed();
    messageStore.upsert(
      Bubble(
        id: uuid.v7(),
        role: MessageRole.user,
        text: rawCommand,
        reasoning: '',
        createdAt: DateTime.now(),
      ),
    );

    final currentWorkspace = workspace;
    if (currentWorkspace == null || currentWorkspace.missing) {
      messageStore.upsert(
        Bubble(
          id: uuid.v7(),
          role: MessageRole.assistant,
          text:
              '`/continue` needs an attached workspace with a saved task under `.agent/tasks`.',
          reasoning: '',
          createdAt: DateTime.now(),
        ),
      );
      return;
    }

    final scopeId = _taskScopeId;
    if (activeTask == null) {
      dispatchActiveTask(
        await _recoverTaskSnapshot(
          currentWorkspace,
          await _taskQueries.loadLatestTask(
            currentWorkspace,
            chatSessionId: scopeId,
          ),
        ),
      );
    }
    await reloadTasks();
    if (activeTask == null) {
      messageStore.upsert(
        Bubble(
          id: uuid.v7(),
          role: MessageRole.assistant,
          text: 'No saved task was found for this chat.',
          reasoning: '',
          createdAt: DateTime.now(),
        ),
      );
      return;
    }

    await _runTaskInternal();
  }

  Future<void> _continueProjectFromCommand(String rawCommand) async {
    if (!await _taskSystemEnabled()) {
      _session.insertUserAndAssistant(
        rawCommand,
        'Structured tasks are disabled in Settings.',
      );
      return;
    }

    _adoptActiveModelIfRestoreDismissed();
    messageStore.upsert(
      Bubble(
        id: uuid.v7(),
        role: MessageRole.user,
        text: rawCommand,
        reasoning: '',
        createdAt: DateTime.now(),
      ),
    );

    final currentWorkspace = workspace;
    if (currentWorkspace == null || currentWorkspace.missing) {
      messageStore.upsert(
        Bubble(
          id: uuid.v7(),
          role: MessageRole.assistant,
          text:
              '`/continue-project` needs an attached workspace with a saved project under `.agent/projects`.',
          reasoning: '',
          createdAt: DateTime.now(),
        ),
      );
      return;
    }

    final scopeId = _taskScopeId;
    if (activeProject == null) {
      dispatchActiveProject(
        (await _recoverProject(
          currentWorkspace,
          await _projectQueries.loadLatestProject(
            currentWorkspace,
            chatSessionId: scopeId,
          ),
        ))?.project,
      );
    }
    await reloadTasks();
    if (activeProject == null) {
      messageStore.upsert(
        Bubble(
          id: uuid.v7(),
          role: MessageRole.assistant,
          text: 'No saved project was found for this chat.',
          reasoning: '',
          createdAt: DateTime.now(),
        ),
      );
      return;
    }

    await _runProjectInternal();
  }

  Future<void> _startProjectFromPrompt(
    String prompt, {
    required bool runAfterCreation,
  }) async {
    final currentWorkspace = workspace;
    final client = serverManager.completionProvider;
    if (client == null) return;
    final settings = await _refreshTaskSystemSettings();
    if (!settings.enabled) {
      _session.insertUserAndAssistant(
        prompt,
        'Structured tasks are disabled in Settings.',
      );
      return;
    }

    _adoptActiveModelIfRestoreDismissed();
    messageStore.upsert(
      Bubble(
        id: uuid.v7(),
        role: MessageRole.user,
        text: prompt,
        reasoning: '',
        createdAt: DateTime.now(),
      ),
    );

    if (currentWorkspace == null || currentWorkspace.missing) {
      messageStore.upsert(
        Bubble(
          id: uuid.v7(),
          role: MessageRole.assistant,
          text:
              'Project mode needs an attached workspace so it can persist `.agent/projects` and `.agent/tasks` artifacts. Attach a workspace and try again.',
          reasoning: '',
          createdAt: DateTime.now(),
        ),
      );
      return;
    }

    final scopeId = await _ensureTaskScopeId();
    final existingProject =
        activeProject ??
        (await _recoverProject(
          currentWorkspace,
          await _projectQueries.loadLatestProject(
            currentWorkspace,
            chatSessionId: scopeId,
          ),
        ))?.project;
    if (existingProject != null && !existingProject.isTerminal) {
      dispatchActiveProject(
        await _projectPlanning.addUserContext(
          workspace: currentWorkspace,
          snapshot: existingProject,
          text: prompt,
        ),
      );
      dispatchActiveTask(null);
      await reloadTasks();
      _insertTaskAssistantMessage(_projectStatusMessage(activeProject!));
      if (runAfterCreation) {
        await _runProjectInternal();
      }
      return;
    }

    dispatchTaskBusy(true);
    final token = _beginTaskCancellationScope();
    dispatchTaskError(null);
    dispatchTaskStatusMessage(
      runAfterCreation
          ? 'Creating project and preparing first task...'
          : 'Creating project...',
    );
    _beginTaskModelOutput('Project Creation Model Output');
    emitChange();

    try {
      final project = await _projectPlanning.createProject(
        workspace: currentWorkspace,
        userPrompt: prompt,
        chatSessionId: scopeId,
        client: client,
        baseSystemPrompt: _buildSystemPrompt(currentUserRequest: prompt),
        maxIterations: settings.maxProjectIterations,
        onModelOutput: _handleTaskModelOutput,
        cancellationToken: token,
        questionAutonomy: settings.questionAutonomy,
      );
      dispatchActiveProject(project);
      dispatchActiveTask(null);
      await reloadTasks();
      _insertTaskAssistantMessage(_projectCreatedMessage(project));

      if (runAfterCreation) {
        dispatchActiveProject(project);
        await _runProjectInternal(keepBusy: true);
      }
    } on OperationCancelledException {
      _insertTaskAssistantMessage('Project creation cancelled.');
    } catch (e) {
      dispatchTaskError(e);
      _insertTaskErrorBubble('Failed to create project: $e');
    } finally {
      dispatchTaskBusy(false);
      _endTaskCancellationScope(token);
      dispatchTaskStatusMessage(null);
      _finishTaskModelOutput();
      emitChange();
    }
  }

  Future<void> _runProjectInternal({
    bool keepBusy = false,
    int? maxNewTasks,
  }) async {
    final currentWorkspace = workspace;
    final client = serverManager.completionProvider;
    final snapshot = activeProject;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        client == null ||
        snapshot == null ||
        taskBusy && !keepBusy) {
      return;
    }

    final token = _beginTaskCancellationScope(reuseExisting: keepBusy);

    if (!keepBusy) {
      dispatchTaskBusy(true);
      dispatchTaskError(null);
      _beginTaskModelOutput('Project Run Model Output');
      emitChange();
    }
    final settings = await _refreshTaskSystemSettings();
    dispatchTaskStatusMessage('Running project...');
    emitChange();

    try {
      final compactionSettings = await _preferencesService
          .getCompactionSettings();
      final result = await _projectExecution.executeUntilStop(
        ProjectExecutionRequest(
          client: client,
          workspace: currentWorkspace,
          snapshot: snapshot,
          baseSystemPrompt: _buildProjectSystemPrompt(snapshot),
          maxNewTasks: maxNewTasks ?? settings.maxProjectTasksPerRun,
          maxIterations: settings.maxProjectIterations,
          requirePhaseApproval: settings.requireApprovalBeforeFileEdits,
          questionAutonomy: settings.questionAutonomy,
          planApprovalPolicy: settings.planApprovalPolicy,
          compactionSettings: compactionSettings,
          contextLimitTokens: _diagnosticsContextLimit,
          onCompactionStatus: (status) {
            dispatchTaskStatusMessage(status);
            emitChange();
          },
          onModelOutput: _handleTaskModelOutput,
          onTaskUpdated: (task) {
            dispatchActiveTask(task);
            emitChange();
          },
          cancellationToken: token,
        ),
        boundedRun: maxNewTasks != null,
      );
      dispatchActiveProject(result.project);
      dispatchActiveTask(result.activeTask);
      dispatchActiveProjectPersistenceDiagnostics(
        result.persistenceDiagnostics,
      );
      emitChange();
      await reloadTasks();
      _insertTaskAssistantMessage(_projectStatusMessage(activeProject!));
    } on OperationCancelledException {
      _insertTaskAssistantMessage('Project run cancelled.');
    } catch (e) {
      dispatchTaskError(e);
      _insertTaskErrorBubble('Failed to run project: $e');
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

  Future<void> _runNextTaskStepInternal({bool keepBusy = false}) async {
    final currentWorkspace = workspace;
    final client = serverManager.completionProvider;
    final snapshot = activeTask;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        client == null ||
        snapshot == null ||
        taskBusy && !keepBusy) {
      return;
    }

    final nextStep = snapshot.nextRunnableStep;
    if (nextStep == null) {
      _insertTaskAssistantMessage(
        'Task `${snapshot.title}` has no pending steps.',
      );
      return;
    }

    final token = _beginTaskCancellationScope(reuseExisting: keepBusy);

    if (!keepBusy) {
      dispatchTaskBusy(true);
      dispatchTaskError(null);
      _beginTaskModelOutput('Task Step Model Output');
      emitChange();
    }
    dispatchTaskStatusMessage('Running step ${nextStep.id}: ${nextStep.title}');
    emitChange();

    try {
      final compactionSettings = await _preferencesService
          .getCompactionSettings();
      final updated = await _taskExecution.runNextStep(
        client: client,
        workspace: currentWorkspace,
        snapshot: snapshot,
        baseSystemPrompt: _buildTaskSystemPrompt(snapshot),
        requirePhaseApproval: taskSystemSettings.requireApprovalBeforeFileEdits,
        questionAutonomy: taskSystemSettings.questionAutonomy,
        compactionSettings: compactionSettings,
        contextLimitTokens: _diagnosticsContextLimit,
        onCompactionStatus: (status) {
          dispatchTaskStatusMessage(status);
          emitChange();
        },
        onModelOutput: _handleTaskModelOutput,
        cancellationToken: token,
      );
      dispatchActiveTask(updated);
      await reloadTasks();
      _insertTaskAssistantMessage(_stepFinishedMessage(updated));
    } on OperationCancelledException {
      _insertTaskAssistantMessage('Task step cancelled.');
    } catch (e) {
      dispatchTaskError(e);
      _insertTaskErrorBubble('Failed to run task step: $e');
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

  // ── Task creation (shared by send() in task/project mode and slash commands) ──

  Future<void> _startTaskFromPrompt(
    String prompt, {
    required bool runFirstPhase,
  }) async {
    final currentWorkspace = workspace;
    final client = serverManager.completionProvider;
    if (client == null) return;
    final settings = await _refreshTaskSystemSettings();
    if (!settings.enabled) {
      _session.insertUserAndAssistant(
        prompt,
        'Structured tasks are disabled in Settings.',
      );
      return;
    }

    _adoptActiveModelIfRestoreDismissed();
    messageStore.upsert(
      Bubble(
        id: uuid.v7(),
        role: MessageRole.user,
        text: prompt,
        reasoning: '',
        createdAt: DateTime.now(),
      ),
    );

    if (currentWorkspace == null || currentWorkspace.missing) {
      messageStore.upsert(
        Bubble(
          id: uuid.v7(),
          role: MessageRole.assistant,
          text:
              'Task mode needs an attached workspace so it can persist `.agent/tasks` artifacts. Attach a workspace and try again.',
          reasoning: '',
          createdAt: DateTime.now(),
        ),
      );
      return;
    }

    dispatchTaskBusy(true);
    final token = _beginTaskCancellationScope();
    dispatchTaskError(null);
    dispatchTaskStatusMessage(
      runFirstPhase
          ? 'Creating task plan and preparing first phase...'
          : 'Creating task plan...',
    );
    _beginTaskModelOutput('Task Creation Model Output');
    emitChange();

    try {
      final scopeId = await _ensureTaskScopeId();
      final snapshot = await _taskPlanning.createTask(
        client: client,
        workspace: currentWorkspace,
        userPrompt: prompt,
        selectedMode: ExecutionMode.task,
        baseSystemPrompt: _buildSystemPrompt(currentUserRequest: prompt),
        chatSessionId: scopeId,
        onModelOutput: _handleTaskModelOutput,
        cancellationToken: token,
      );
      dispatchActiveTask(snapshot);
      await reloadTasks();
      _insertTaskAssistantMessage(_taskCreatedMessage(snapshot));

      if (runFirstPhase) {
        dispatchActiveTask(snapshot);
        await _runTaskInternal(keepBusy: true);
      }
    } on OperationCancelledException {
      _insertTaskAssistantMessage('Task creation cancelled.');
    } catch (e) {
      dispatchTaskError(e);
      _insertTaskErrorBubble('Failed to create task: $e');
    } finally {
      dispatchTaskBusy(false);
      _endTaskCancellationScope(token);
      dispatchTaskStatusMessage(null);
      _finishTaskModelOutput();
      emitChange();
    }
  }

  // ── Business operations delegated to other services ─────────────────────

  Future<void> replanRemainingTask() async {
    final currentWorkspace = workspace;
    final client = serverManager.completionProvider;
    final snapshot = activeTask;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        client == null ||
        snapshot == null ||
        taskBusy) {
      return;
    }

    dispatchTaskBusy(true);
    final token = _beginTaskCancellationScope();
    dispatchTaskError(null);
    dispatchTaskStatusMessage('Replanning unfinished work...');
    _beginTaskModelOutput('Replan Model Output');
    emitChange();
    try {
      dispatchActiveTask(
        await _taskPlanning.replanUnfinished(
          client: client,
          workspace: currentWorkspace,
          snapshot: snapshot,
          baseSystemPrompt: _buildTaskSystemPrompt(snapshot),
          onModelOutput: _handleTaskModelOutput,
          cancellationToken: token,
        ),
      );
      await reloadTasks();
      _insertTaskAssistantMessage(
        'Unfinished work replanned for **${activeTask!.title}**. Next step: `${activeTask!.currentStepId ?? 'none'}`.',
      );
    } on OperationCancelledException {
      _insertTaskAssistantMessage('Replan cancelled.');
    } catch (e) {
      dispatchTaskError(e);
      rethrow;
    } finally {
      dispatchTaskBusy(false);
      _endTaskCancellationScope(token);
      dispatchTaskStatusMessage(null);
      _finishTaskModelOutput();
      emitChange();
    }
  }

  Future<void> updateTaskTaskBrief(TaskPlanUpdateCommand command) async {
    await updateTaskPlan(command);
  }

  Future<void> updateTaskSpec(TaskPlanUpdateCommand command) async {
    await updateTaskPlan(command);
  }

  Future<void> updateTaskPlan(TaskPlanUpdateCommand command) async {
    final currentWorkspace = workspace;
    final snapshot = activeTask;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null ||
        taskBusy) {
      return;
    }

    dispatchTaskBusy(true);
    dispatchTaskError(null);
    dispatchTaskStatusMessage('Updating task plan...');
    emitChange();
    try {
      dispatchActiveTask(
        await _taskPlanning.updateTaskPlan(
          workspace: currentWorkspace,
          snapshot: snapshot,
          command: command,
        ),
      );
      await reloadTasks();
      _insertTaskAssistantMessage(
        'Task plan updated for **${activeTask!.title}**.',
      );
    } catch (e) {
      dispatchTaskError(e);
      rethrow;
    } finally {
      dispatchTaskBusy(false);
      dispatchTaskStatusMessage(null);
      emitChange();
    }
  }

  Future<void> updateProjectPlan(ProjectUpdateCommand command) async {
    final currentWorkspace = workspace;
    final snapshot = activeProject;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null ||
        taskBusy) {
      return;
    }

    dispatchTaskBusy(true);
    dispatchTaskError(null);
    dispatchTaskStatusMessage('Updating project...');
    emitChange();
    try {
      dispatchActiveProject(
        await _projectCommands.updateProject(
          workspace: currentWorkspace,
          snapshot: snapshot,
          command: command,
        ),
      );
      await reloadTasks();
      _insertTaskAssistantMessage(
        'Project updated for **${activeProject!.title}**.',
      );
    } catch (e) {
      dispatchTaskError(e);
      rethrow;
    } finally {
      dispatchTaskBusy(false);
      dispatchTaskStatusMessage(null);
      emitChange();
    }
  }

  Future<String> readTaskArtifact(String artifactPath) async {
    final currentWorkspace = workspace;
    if (currentWorkspace == null || currentWorkspace.missing) {
      throw StateError('No active workspace is attached.');
    }
    return _taskPresentation.readArtifact(
      workspace: currentWorkspace,
      artifactPath: artifactPath,
    );
  }

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

  // ── Slash command parsing ───────────────────────────────────────────────

  _SlashCommand? _parseSlashCommand(String text) {
    final match = RegExp(
      r'^/(continue-project|project|task|plan|refine|continue)\b(.*)$',
    ).firstMatch(text.trim());
    if (match == null) return null;
    return _SlashCommand(
      name: match.group(1)!.toLowerCase(),
      argument: match.group(2)?.trim() ?? '',
      raw: text,
    );
  }

  void _markWorkspaceChanged() {
    _markPersistableChange();
    emitChange();
  }

  void _adoptActiveModelIfRestoreDismissed() {
    if (pendingModelRestore != null) return;

    final activeSnapshot = _activeServerSnapshot;
    if (activeSnapshot == null ||
        activeSnapshot.matches(currentModelSnapshot)) {
      return;
    }

    dispatchCurrentModelSnapshot(activeSnapshot);
    _requestContextEstimateUpdate(immediate: true);
    _markPersistableChange();
    emitChange();
  }

  // ── Status message builders ─────────────────────────────────────────────

  String _taskBriefMessage(RefinedTaskBrief brief) {
    final buffer = StringBuffer()
      ..writeln('Task brief refined: **${brief.title}**')
      ..writeln()
      ..writeln('Goal:')
      ..writeln(brief.goal)
      ..writeln()
      ..writeln('Success criteria:');
    for (final item in brief.successCriteria) {
      buffer.writeln('- $item');
    }
    if (brief.constraints.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Constraints:');
      for (final item in brief.constraints) {
        buffer.writeln('- $item');
      }
    }
    if (brief.assumptions.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Assumptions:');
      for (final item in brief.assumptions) {
        buffer.writeln('- $item');
      }
    }
    if (brief.questions.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Questions:');
      for (final question in brief.questions.take(3)) {
        buffer.writeln('- $question');
      }
    }
    return buffer.toString().trim();
  }

  String _taskCreatedMessage(Task snapshot) {
    final buffer = StringBuffer()
      ..writeln('Task created: **${snapshot.title}**')
      ..writeln()
      ..writeln('Status: `${TaskStatusWire(snapshot.status).wire}`')
      ..writeln()
      ..writeln('Steps:');
    for (var i = 0; i < snapshot.steps.length; i++) {
      final step = snapshot.steps[i];
      buffer.writeln('${i + 1}. ${step.title}');
    }
    buffer
      ..writeln()
      ..writeln('Task state is stored under `.agent/tasks/${snapshot.id}/`.');
    return buffer.toString().trim();
  }

  String _projectCreatedMessage(ProjectAggregate snapshot) {
    final buffer = StringBuffer()
      ..writeln('Project created: **${snapshot.title}**')
      ..writeln()
      ..writeln('Status: `${ProjectStatusWire(snapshot.status).wire}`')
      ..writeln()
      ..writeln('Goal:')
      ..writeln(snapshot.refinedGoal)
      ..writeln()
      ..writeln(
        'Project state is stored under `.agent/projects/${snapshot.id}/`.',
      );
    return buffer.toString().trim();
  }

  String _projectStatusMessage(ProjectAggregate snapshot) {
    final buffer = StringBuffer()
      ..writeln('Project status: **${snapshot.title}**')
      ..writeln()
      ..writeln('Status: `${ProjectStatusWire(snapshot.status).wire}`');
    if (_projectHasTransportFailure(snapshot)) {
      buffer
        ..writeln()
        ..writeln(
          'Model transport was interrupted. Resume the project to retry the current step.',
        );
    } else if (snapshot.completionSummary.trim().isNotEmpty) {
      buffer
        ..writeln()
        ..writeln(snapshot.completionSummary.trim());
    } else if (snapshot.blocker != null) {
      buffer
        ..writeln()
        ..writeln('Blocked: ${snapshot.blocker!.message}');
    } else if (snapshot.tasks.isNotEmpty) {
      final latest = snapshot.tasks.last;
      buffer
        ..writeln()
        ..writeln(
          'Latest task: `${latest.id}` - '
          '${latest.status.wire}',
        );
    }
    return buffer.toString().trim();
  }

  String _stepFinishedMessage(Task snapshot) {
    final latestRun = snapshot.runs.isEmpty ? null : snapshot.runs.last;
    final buffer = StringBuffer()
      ..writeln('Task step finished: **${latestRun?.stepId ?? 'step'}**')
      ..writeln()
      ..writeln('Task status: `${snapshot.status.wire}`');
    if (_taskHasTransportFailure(snapshot)) {
      buffer
        ..writeln()
        ..writeln(
          'Model transport was interrupted. Resume the task to retry this step.',
        );
    } else if (latestRun != null) {
      buffer
        ..writeln()
        ..writeln(
          latestRun.summary.trim().isEmpty
              ? 'The task is paused. Resume it when ready.'
              : latestRun.summary,
        );
    }
    final artifacts = latestRun?.artifacts ?? const [];
    if (artifacts.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Artifacts:');
      for (final artifact in artifacts.take(8)) {
        buffer.writeln('- `${artifact.path}`');
      }
    }
    final gateResults = latestRun?.gateResults ?? const [];
    if (gateResults.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Gates:');
      for (final result in gateResults.take(8)) {
        buffer.writeln(
          '- `${result.gateId}` ${result.status.wire}: ${result.summary}',
        );
      }
    }
    return buffer.toString().trim();
  }

  bool _taskHasTransportFailure(Task? snapshot) {
    if (snapshot == null ||
        snapshot.status != TaskStatus.paused ||
        snapshot.runs.isEmpty) {
      return false;
    }
    final latestRun = snapshot.runs.last;
    return latestRun.status == TaskRunStatus.failed &&
        latestRun.error?.contains('Model transport failed') == true;
  }

  bool _projectHasTransportFailure(ProjectAggregate snapshot) {
    if (snapshot.status != ProjectStatus.paused ||
        snapshot.activeTaskId == null) {
      return false;
    }
    final task = activeTask;
    if (task == null ||
        task.id != snapshot.activeTaskId ||
        task.projectId != snapshot.id) {
      return false;
    }
    return _taskHasTransportFailure(task);
  }

  bool _taskNeedsInterventionBeforeContinuing(Task snapshot) {
    if (snapshot.status != TaskStatus.paused) return false;
    if (snapshot.pendingApproval != null || snapshot.pendingQuestion != null) {
      return true;
    }
    final latestRun = snapshot.runs.isEmpty ? null : snapshot.runs.last;
    if (latestRun == null) return true;
    return latestRun.status != TaskRunStatus.completed &&
        latestRun.status != TaskRunStatus.replanned &&
        latestRun.status != TaskRunStatus.skipped;
  }

  // ── Disposable ──────────────────────────────────────────────────────────

  Future<void> quiesceForExit({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (_disposed) return;
    await _stopActiveWork().timeout(timeout);
    _session.flushPendingTokens();
  }

  Future<void> _stopActiveWork() async {
    if (chatStream.isStreaming) await cancelGeneration();
    if (!taskBusy) return;
    await cancelTaskRun();
    if (taskBusy) await _waitForTaskIdle();
  }

  Future<void> _waitForTaskIdle() {
    if (!taskBusy) return Future.value();
    final completer = Completer<void>();
    late VoidCallback listener;
    listener = () {
      if (taskBusy || completer.isCompleted) return;
      removeListener(listener);
      completer.complete();
    };
    addListener(listener);
    return completer.future.whenComplete(() => removeListener(listener));
  }

  // ignore: must_call_super, super.dispose is called by _dispose after async cleanup.
  Future<void> disposeAsync() => _startDispose(saveChanges: true);

  Future<void> disposeWithoutSavingAsync() => _startDispose(saveChanges: false);

  Future<void> _startDispose({required bool saveChanges}) {
    if (_disposed) return Future.value();
    final pending = _disposeFuture;
    if (pending != null) return pending;

    late final Future<void> operation;
    operation = _dispose(saveChanges: saveChanges).whenComplete(() {
      if (!_disposed && identical(_disposeFuture, operation)) {
        _disposeFuture = null;
      }
    });
    _disposeFuture = operation;
    return operation;
  }

  Future<void> _dispose({required bool saveChanges}) async {
    if (saveChanges) {
      await quiesceForExit();
      await flushCurrentChat();
    } else {
      try {
        await quiesceForExit();
      } catch (error, stackTrace) {
        _reportDisposalFailure(error, stackTrace);
      }
    }

    _disposed = true;
    messageStore.removeListener(_handleMessagesChanged);
    _preferencesService.removeListener(_handlePreferencesChanged);
    _contextEstimateScheduler.cancel();
    _taskModelOutputNotifier.cancel();
    _autosaveTimer?.cancel();
    try {
      await _deleteTransientTasksForCurrentScope();
    } catch (error, stackTrace) {
      _reportDisposalFailure(error, stackTrace);
    }
    try {
      await _deleteTransientProjectsForCurrentScope();
    } catch (error, stackTrace) {
      _reportDisposalFailure(error, stackTrace);
    }
    messageStore.clearCurrentId();
    messageStore.clearToolBuffers();
    try {
      await chatStream.stop();
    } finally {
      try {
        await _session.dispose();
      } finally {
        _disposeChangeNotifier();
      }
    }
  }

  void _reportDisposalFailure(Object error, StackTrace stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'hermes chat disposal',
        context: ErrorDescription('while disposing chat tab $tabId'),
      ),
    );
  }
}
