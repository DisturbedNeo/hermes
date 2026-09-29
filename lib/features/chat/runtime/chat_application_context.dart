part of 'chat_runtime_engine.dart';

class _ChatApplicationContext extends ChangeNotifier
    implements ChatSessionHost {
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
  final TaskChatPort _taskController;
  final ProjectChatPort _projectApplication;
  final ChatLibraryService _chatLibrary;
  final WorkspacePort _workspaceService;
  final PreferencesPort _preferencesService;
  final ChatCommandCoordinator _commandCoordinator;
  final PromptAssembler _promptAssembler = const PromptAssembler();

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

  /// The only authoritative user-visible state for this tab.
  ChatState get state => _state;

  void _dispatchChatState(ChatState next, {bool notify = true}) {
    _state = next;
    if (notify) notifyListeners();
  }

  String? get currentChatId => _state.currentChatId;
  void setCurrentChatId(String? value) =>
      _dispatchChatState(_state.copyWith(currentChatId: value));

  SavedChat? get currentSavedChat => _state.currentSavedChat;
  void setCurrentSavedChat(SavedChat? value) =>
      _dispatchChatState(_state.copyWith(currentSavedChat: value));

  @override
  ModelConfigurationSnapshot? get currentModelSnapshot =>
      _state.currentModelSnapshot;
  void dispatchCurrentModelSnapshot(ModelConfigurationSnapshot? value) =>
      _dispatchChatState(_state.copyWith(currentModelSnapshot: value));

  ModelConfigurationSnapshot? get pendingModelRestore =>
      _state.pendingModelRestore;
  void setPendingModelRestore(ModelConfigurationSnapshot? value) =>
      _dispatchChatState(_state.copyWith(pendingModelRestore: value));

  String? get pendingModelRestoreIssue => _state.pendingModelRestoreIssue;
  void setPendingModelRestoreIssue(String? value) =>
      _dispatchChatState(_state.copyWith(pendingModelRestoreIssue: value));

  @override
  WorkspaceAttachment? get workspace => _state.workspace;
  void setWorkspace(WorkspaceAttachment? value) =>
      _dispatchChatState(_state.copyWith(workspace: value));

  SystemPromptSnapshot? get currentSystemPromptSnapshot => _state.systemPrompt;
  void setCurrentSystemPromptSnapshot(SystemPromptSnapshot? value) =>
      _dispatchChatState(_state.copyWith(systemPrompt: value));

  ExecutionMode get executionMode => _state.executionMode;
  void dispatchExecutionMode(ExecutionMode value) =>
      _dispatchChatState(_state.copyWith(executionMode: value));

  ProjectDocument? get activeProject => _state.activeProject;
  void setActiveProject(ProjectDocument? value) =>
      _dispatchChatState(_state.copyWith(activeProject: value));

  ProjectPersistenceDiagnostics? _activeProjectPersistenceDiagnostics;
  ProjectPersistenceDiagnostics? get activeProjectPersistenceDiagnostics =>
      _activeProjectPersistenceDiagnostics;
  void setActiveProjectPersistenceDiagnostics(
    ProjectPersistenceDiagnostics? value,
  ) {
    _activeProjectPersistenceDiagnostics = value;
  }

  List<ProjectSummary> get availableProjects => _state.availableProjects;
  void setAvailableProjects(List<ProjectSummary> value) =>
      _dispatchChatState(_state.copyWith(availableProjects: value));

  Task? get activeTask => _state.activeTask;
  void setActiveTask(Task? value) =>
      _dispatchChatState(_state.copyWith(activeTask: value));

  List<TaskSummary> get availableTasks => _state.availableTasks;
  void setAvailableTasks(List<TaskSummary> value) =>
      _dispatchChatState(_state.copyWith(availableTasks: value));

  TaskSystemSettings get taskSystemSettings => _state.taskSystemSettings;
  void setTaskSystemSettings(TaskSystemSettings value) =>
      _dispatchChatState(_state.copyWith(taskSystemSettings: value));

  bool get taskBusy => _state.taskBusy;
  void setTaskBusy(bool value) =>
      _dispatchChatState(const ChatStateReducer().setTaskBusy(_state, value));

  bool get taskCancellationRequested => _state.taskCancellationRequested;
  void setTaskCancellationRequested(bool value) => _dispatchChatState(
    value
        ? const ChatStateReducer().requestTaskCancellation(_state)
        : _state.copyWith(taskCancellationRequested: false),
  );

  String? get taskStatusMessage => _state.taskStatusMessage;
  void setTaskStatusMessage(String? value) =>
      _dispatchChatState(_state.copyWith(taskStatusMessage: value));

  Object? get taskError => _state.taskError;
  void setTaskError(Object? value) =>
      _dispatchChatState(const ChatStateReducer().setTaskError(_state, value));

  String? get taskModelOutputTitle => _state.taskModelOutputTitle;
  void setTaskModelOutputTitle(String? value) =>
      _dispatchChatState(_state.copyWith(taskModelOutputTitle: value));

  @override
  String get taskModelOutputText => _state.taskModelOutputText;
  void setTaskModelOutputText(String value) =>
      _dispatchChatState(_state.copyWith(taskModelOutputText: value));
  void appendTaskModelOutputText(String value) =>
      setTaskModelOutputText('$taskModelOutputText$value');

  @override
  String get taskModelOutputReasoning => _state.taskModelOutputReasoning;
  void setTaskModelOutputReasoning(String value) =>
      _dispatchChatState(_state.copyWith(taskModelOutputReasoning: value));
  void appendTaskModelOutputReasoning(String value) =>
      setTaskModelOutputReasoning('$taskModelOutputReasoning$value');

  bool get taskModelOutputActive => _state.taskModelOutputActive;
  void setTaskModelOutputActive(bool value) =>
      _dispatchChatState(_state.copyWith(taskModelOutputActive: value));

  ChatSaveFailure? get saveFailure => _state.saveFailure;
  void setSaveFailure(ChatSaveFailure? value) =>
      _dispatchChatState(_state.copyWith(saveFailure: value));
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

  @override
  int? get sessionDiagnosticsContextLimit => _diagnosticsContextLimit;

  @override
  String? sessionTaskModelOutputLabel() => _taskModelOutputLabel;

  @override
  void setSessionTaskModelOutputLabel(String? value) {
    _taskModelOutputLabel = value;
  }

  @override
  String? sessionTaskModelOutputTextSection() => _taskModelOutputTextSection;

  @override
  void setSessionTaskModelOutputTextSection(String? value) {
    _taskModelOutputTextSection = value;
  }

  @override
  String? sessionTaskModelOutputReasoningLabel() =>
      _taskModelOutputReasoningLabel;

  @override
  void setSessionTaskModelOutputReasoningLabel(String? value) {
    _taskModelOutputReasoningLabel = value;
  }

  @override
  String buildSystemPrompt({String? currentUserRequest}) =>
      _buildSystemPrompt(currentUserRequest: currentUserRequest);

  @override
  void markWorkspaceChanged() {
    _markPersistableChange();
    notifyListeners();
  }

  @override
  void sessionNotifyListeners() => notifyListeners();

  @override
  void requestContextEstimateUpdate({bool immediate = false}) {
    _requestContextEstimateUpdate(immediate: immediate);
  }

  @override
  bool get workspaceToolsEnabled => hasActiveWorkspace;

  @override
  List<String> get defaultToolIds => workspaceToolsEnabled
      ? _toolService.defaultToolIds(includeWorkspaceTools: true)
      : const [];

  void _disposeChangeNotifier() => super.dispose();

  _ChatApplicationContext({
    String? tabId,
    required this.serverManager,
    required ToolRegistryPort toolService,
    required TaskChatPort taskController,
    required ProjectChatPort projectApplication,
    required ChatLibraryService chatLibrary,
    required WorkspacePort workspaceService,
    required PreferencesPort preferencesService,
    ChatCommandCoordinator? commandCoordinator,
    ChatToolExecutionPort? toolExecution,
    SystemPromptSnapshot? initialSystemPromptSnapshot,
  }) : tabId = tabId ?? uuid.v7(),
       _toolService = toolService,
       _chatLibrary = chatLibrary,
       _workspaceService = workspaceService,
       _preferencesService = preferencesService,
       _taskController = taskController,
       _projectApplication = projectApplication,
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
    _dispatchChatState(_state.copyWith(messages: messageStore.messages));

    _contextEstimateScheduler = ThrottledScheduler(
      interval: _contextEstimateThrottle,
      onTick: _updateContextEstimate,
    );
    _taskModelOutputNotifier = ThrottledScheduler(
      interval: _taskModelOutputNotifyThrottle,
      onTick: () {
        if (!_disposed) notifyListeners();
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
      preferencesService: _preferencesService,
      host: this,
      toolExecution: toolExecution,
    );
  }
}
