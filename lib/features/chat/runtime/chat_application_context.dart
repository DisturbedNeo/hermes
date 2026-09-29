part of 'chat_controller.dart';

class _ChatApplicationContext extends ChangeNotifier
    implements ChatSessionHost {
  static const String defaultSystemPromptName = 'Default';
  static const String defaultSystemPromptText = 'You are a helpful assistant.';
  static const Duration _contextEstimateThrottle = Duration(milliseconds: 500);
  static const Duration _taskModelOutputNotifyThrottle = Duration(
    milliseconds: 100,
  );

  final String tabId;
  final LlamaServerManager serverManager;
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

  String? get currentChatId => _state.currentChatId;
  set currentChatId(String? value) =>
      _state = _state.copyWith(currentChatId: value);

  SavedChat? get currentSavedChat => _state.currentSavedChat;
  set currentSavedChat(SavedChat? value) =>
      _state = _state.copyWith(currentSavedChat: value);

  @override
  ModelConfigurationSnapshot? get currentModelSnapshot =>
      _state.currentModelSnapshot;
  set currentModelSnapshot(ModelConfigurationSnapshot? value) =>
      _state = _state.copyWith(currentModelSnapshot: value);

  ModelConfigurationSnapshot? get pendingModelRestore =>
      _state.pendingModelRestore;
  set pendingModelRestore(ModelConfigurationSnapshot? value) =>
      _state = _state.copyWith(pendingModelRestore: value);

  String? get pendingModelRestoreIssue => _state.pendingModelRestoreIssue;
  set pendingModelRestoreIssue(String? value) =>
      _state = _state.copyWith(pendingModelRestoreIssue: value);

  @override
  WorkspaceAttachment? get workspace => _state.workspace;
  set workspace(WorkspaceAttachment? value) =>
      _state = _state.copyWith(workspace: value);

  SystemPromptSnapshot? get currentSystemPromptSnapshot => _state.systemPrompt;
  set currentSystemPromptSnapshot(SystemPromptSnapshot? value) =>
      _state = _state.copyWith(systemPrompt: value);

  ExecutionMode get executionMode => _state.executionMode;
  set executionMode(ExecutionMode value) =>
      _state = _state.copyWith(executionMode: value);

  ProjectDocument? get activeProject => _state.activeProject;
  set activeProject(ProjectDocument? value) =>
      _state = _state.copyWith(activeProject: value);

  ProjectPersistenceDiagnostics? activeProjectPersistenceDiagnostics;

  List<ProjectSummary> get availableProjects => _state.availableProjects;
  set availableProjects(List<ProjectSummary> value) =>
      _state = _state.copyWith(availableProjects: value);

  Task? get activeTask => _state.activeTask;
  set activeTask(Task? value) => _state = _state.copyWith(activeTask: value);

  List<TaskSummary> get availableTasks => _state.availableTasks;
  set availableTasks(List<TaskSummary> value) =>
      _state = _state.copyWith(availableTasks: value);

  TaskSystemSettings get taskSystemSettings => _state.taskSystemSettings;
  set taskSystemSettings(TaskSystemSettings value) =>
      _state = _state.copyWith(taskSystemSettings: value);

  bool get taskBusy => _state.taskBusy;
  set taskBusy(bool value) =>
      _state = const ChatStateReducer().setTaskBusy(_state, value);

  bool get taskCancellationRequested => _state.taskCancellationRequested;
  set taskCancellationRequested(bool value) => _state = value
      ? const ChatStateReducer().requestTaskCancellation(_state)
      : _state.copyWith(taskCancellationRequested: false);

  String? get taskStatusMessage => _state.taskStatusMessage;
  set taskStatusMessage(String? value) =>
      _state = _state.copyWith(taskStatusMessage: value);

  Object? get taskError => _state.taskError;
  set taskError(Object? value) =>
      _state = const ChatStateReducer().setTaskError(_state, value);

  String? get taskModelOutputTitle => _state.taskModelOutputTitle;
  set taskModelOutputTitle(String? value) =>
      _state = _state.copyWith(taskModelOutputTitle: value);

  @override
  String get taskModelOutputText => _state.taskModelOutputText;
  @override
  set taskModelOutputText(String value) =>
      _state = _state.copyWith(taskModelOutputText: value);

  @override
  String get taskModelOutputReasoning => _state.taskModelOutputReasoning;
  @override
  set taskModelOutputReasoning(String value) =>
      _state = _state.copyWith(taskModelOutputReasoning: value);

  bool get taskModelOutputActive => _state.taskModelOutputActive;
  set taskModelOutputActive(bool value) =>
      _state = _state.copyWith(taskModelOutputActive: value);

  ChatSaveFailure? get saveFailure => _state.saveFailure;
  set saveFailure(ChatSaveFailure? value) =>
      _state = _state.copyWith(saveFailure: value);
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
    _state = _state.copyWith(messages: messageStore.messages);

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

    currentModelSnapshot = _activeServerSnapshot;

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
