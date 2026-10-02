part of 'chat_session_orchestrator.dart';

/// Narrow runtime context used by chat application use cases.
///
/// The context is assembled by the stable notifier facade. Use cases depend
/// on this capability surface, not on the concrete facade, so they can be
/// tested and composed without inheriting the facade's mutable state object.
abstract interface class ChatUseCaseContext implements ChatSessionHost {
  String get tabId;
  ModelServerPort get serverManager;
  MessageStore get messageStore;
  ChatStream<ChatToken> get chatStream;
  Bubble get systemPrompt;
  void emitChange();
  void addListener(VoidCallback listener);
  void removeListener(VoidCallback listener);

  String? get currentChatId;
  void dispatchCurrentChatId(String? value);
  SavedChat? get currentSavedChat;
  void dispatchCurrentSavedChat(SavedChat? value);
  void dispatchCurrentModelSnapshot(ModelConfigurationSnapshot? value);
  ModelConfigurationSnapshot? get pendingModelRestore;
  void dispatchPendingModelRestore(ModelConfigurationSnapshot? value);
  void dispatchPendingModelRestoreIssue(String? value);
  void dispatchWorkspace(WorkspaceAttachment? value);
  void dispatchCurrentSystemPromptSnapshot(SystemPromptSnapshot? value);
  SystemPromptSnapshot? get currentSystemPromptSnapshot;
  ExecutionMode get executionMode;
  void dispatchExecutionMode(ExecutionMode value);
  ProjectAggregate? get activeProject;
  void dispatchActiveProject(ProjectAggregate? value);
  void dispatchActiveProjectPersistenceDiagnostics(
    ProjectPersistenceDiagnostics? value,
  );
  List<ProjectSummary> get availableProjects;
  void dispatchAvailableProjects(List<ProjectSummary> value);
  Task? get activeTask;
  void dispatchActiveTask(Task? value);
  List<TaskSummary> get availableTasks;
  void dispatchAvailableTasks(List<TaskSummary> value);
  TaskSystemSettings get taskSystemSettings;
  void dispatchTaskSystemSettings(TaskSystemSettings value);
  bool get taskBusy;
  void dispatchTaskBusy(bool value);
  void dispatchTaskCancellationRequested(bool value);
  void dispatchTaskStatusMessage(String? value);
  void dispatchTaskError(Object? value);
  String? get taskModelOutputTitle;
  void dispatchTaskModelOutputTitle(String? value);
  bool get taskModelOutputActive;
  void dispatchTaskModelOutputActive(bool value);

  Future<void> flushCurrentChat();
  Future<void> cancelGeneration();
  Future<void> cancelTaskRun();
  Future<void> reloadTasks();
  void updateCurrentModelSnapshot(ModelConfigurationSnapshot snapshot);
  Future<void> refreshModelRestorePrompt();

  ChatLibraryService get _chatLibrary;
  TaskQueryPort get _taskQueries;
  TaskPresentationPort get _taskPresentation;
  TaskPlanningPort get _taskPlanning;
  TaskExecutionPort get _taskExecution;
  TaskRecoveryPort get _taskRecovery;
  ProjectQueryPort get _projectQueries;
  ProjectPlanningPort get _projectPlanning;
  ProjectCommandPort get _projectCommands;
  ProjectExecutionPort get _projectExecution;
  ChatRuntimePreferencesPort get _preferencesService;
  ChatCommandCoordinator get _commandCoordinator;
  ChatAutosaveCoordinator get _autosave;
  ChatCommandDispatcher get _commandDispatcher;
  ChatTaskCommandCoordinator get _taskCommandCoordinator;
  ChatProjectCommandCoordinator get _projectCommandCoordinator;
  ChatSessionManager get _session;
  ChatWorkspaceLifecycleCoordinator get _workspaceLifecycle;
  ChatPresentationMessageBuilder get _presentationMessages;
  ChatPanelProtocolAdapter get _panelProtocol;
  ThrottledScheduler get _contextEstimateScheduler;
  ThrottledScheduler get _taskModelOutputNotifier;

  bool get _disposed;
  set _disposed(bool value);
  bool get loadingSnapshot;
  set loadingSnapshot(bool value);
  Future<void>? get _disposeFuture;
  set _disposeFuture(Future<void>? value);
  String get _chatSessionScopeId;
  set _chatSessionScopeId(String value);
  int get _historyRevision;
  set _historyRevision(int value);
  bool get isSystemPromptLocked;

  ModelConfigurationSnapshot? get _activeServerSnapshot;
  bool get _hasPendingPersistence;
  int get _currentPersistenceRevision;
  int get _persistedRevision;
  String get _taskScopeId;
  Future<bool> _taskSystemEnabled();
  Future<String> _ensureTaskScopeId();

  void Function() get _handleMessagesChanged;
  void Function() get _handlePreferencesChanged;
  void _disposeChangeNotifier();

  Future<Task?> _recoverTaskSnapshot(
    WorkspaceAttachment current,
    Task? snapshot,
  );
  Future<ProjectCommandResult?> _recoverProject(
    WorkspaceAttachment current,
    ProjectAggregate? snapshot,
  );
  Future<Task?> _taskForActiveProject(
    WorkspaceAttachment current,
    ProjectAggregate? project,
  );
  Future<void> runTaskInternal({bool keepBusy = false});
  Future<void> _refinePromptFromCommand(ChatSlashCommand command);
  Future<void> _continueTaskFromCommand(String rawCommand);
  Future<void> _continueProjectFromCommand(String rawCommand);
  Future<void> _startProjectFromPrompt(
    String prompt, {
    required bool runAfterCreation,
  });
  Future<void> _runProjectInternal({int? maxNewTasks});
  Future<void> runNextTaskStepInternal({bool keepBusy = false});
  Future<void> _startTaskFromPrompt(
    String prompt, {
    required bool runFirstPhase,
  });

  Future<TaskSystemSettings> _refreshTaskSystemSettings();
  Future<void> _deleteTransientTasksForCurrentScope();
  Future<void> _deleteTransientProjectsForCurrentScope();
  List<WorkspaceAttachment> _workspacesForSavedChatDeletion(
    String chatId,
    WorkspaceAttachment? savedWorkspace,
  );
  Future<void> _deleteTasksForChatSessionInWorkspaces(
    String chatSessionId,
    Iterable<WorkspaceAttachment> workspaces,
  );
  Future<void> _deleteProjectsForChatSessionInWorkspaces(
    String chatSessionId,
    Iterable<WorkspaceAttachment> workspaces,
  );
  Future<void> _clearProjectTaskBlocker();
  CancellationToken beginTaskCancellationScope({bool reuseExisting = false});
  void _endTaskCancellationScope(CancellationToken token);
  void _beginTaskModelOutput(String title);
  void _clearTaskModelOutput({bool notify = true});
  void _handleTaskModelOutput(TaskModelOutputEvent event);
  void _finishTaskModelOutput();
  void _insertTaskAssistantMessage(String text);
  void _insertTaskErrorBubble(String text);
  void _requestContextEstimateUpdate({bool immediate = false});
  void _markPersistableChange();
  void _resetPersistenceRevisions();
  Future<SavedChat> _queueSave({String? title, bool force = false});
  Future<void> _prepareModelRestorePrompt(ModelConfigurationSnapshot? snapshot);
  void _clearSavedState();
  Future<WorkspaceAttachment?> _restoreWorkspace(WorkspaceAttachment? saved);
  String buildSystemPromptInternal({
    required String? currentUserRequest,
    List<String> additionalModuleIds = const [],
  });
  String _buildTaskSystemPrompt(Task snapshot);
  String _buildProjectSystemPrompt(ProjectAggregate snapshot);
  List<Bubble> _withCurrentSystemPrompt(
    List<Bubble> messages, {
    required String? currentUserRequest,
  });
  void _syncSystemPrompt();
  void _markWorkspaceChanged();
  void _adoptActiveModelIfRestoreDismissed();
}

/// Composition adapter for [ChatUseCaseContext]. It is the only object that
/// knows the concrete facade; individual use cases remain facade-agnostic.
final class _ChatUseCaseContextAdapter implements ChatUseCaseContext {
  _ChatUseCaseContextAdapter(this._host);

  final ChatSessionOrchestrator _host;

  @override
  String get tabId => _host.tabId;
  @override
  ModelServerPort get serverManager => _host.serverManager;
  @override
  MessageStore get messageStore => _host.messageStore;
  @override
  ChatStream<ChatToken> get chatStream => _host.chatStream;
  @override
  Bubble get systemPrompt => _host.systemPrompt;

  @override
  WorkspaceAttachment? get workspace => _host.workspace;
  @override
  ModelConfigurationSnapshot? get currentModelSnapshot =>
      _host.currentModelSnapshot;
  @override
  int? get sessionDiagnosticsContextLimit =>
      _host.sessionDiagnosticsContextLimit;
  @override
  List<String> get defaultToolIds => _host.defaultToolIds;
  @override
  bool get workspaceToolsEnabled => _host.workspaceToolsEnabled;
  @override
  String get taskModelOutputText => _host.taskModelOutputText;
  @override
  void dispatchTaskModelOutputText(String value) =>
      _host.dispatchTaskModelOutputText(value);
  @override
  void appendTaskModelOutputText(String value) =>
      _host.appendTaskModelOutputText(value);
  @override
  String get taskModelOutputReasoning => _host.taskModelOutputReasoning;
  @override
  void dispatchTaskModelOutputReasoning(String value) =>
      _host.dispatchTaskModelOutputReasoning(value);
  @override
  void appendTaskModelOutputReasoning(String value) =>
      _host.appendTaskModelOutputReasoning(value);
  @override
  void markWorkspaceChanged() => _host.markWorkspaceChanged();
  @override
  void sessionNotifyListeners() => _host.sessionNotifyListeners();
  @override
  void requestContextEstimateUpdate({bool immediate = false}) =>
      _host.requestContextEstimateUpdate(immediate: immediate);
  @override
  String buildSystemPrompt({String? currentUserRequest}) =>
      _host.buildSystemPrompt(currentUserRequest: currentUserRequest);
  @override
  String? sessionTaskModelOutputLabel() => _host.sessionTaskModelOutputLabel();
  @override
  void updateSessionTaskModelOutputLabel(String? value) =>
      _host.updateSessionTaskModelOutputLabel(value);
  @override
  String? sessionTaskModelOutputTextSection() =>
      _host.sessionTaskModelOutputTextSection();
  @override
  void updateSessionTaskModelOutputTextSection(String? value) =>
      _host.updateSessionTaskModelOutputTextSection(value);
  @override
  String? sessionTaskModelOutputReasoningLabel() =>
      _host.sessionTaskModelOutputReasoningLabel();
  @override
  void updateSessionTaskModelOutputReasoningLabel(String? value) =>
      _host.updateSessionTaskModelOutputReasoningLabel(value);

  @override
  ChatLibraryService get _chatLibrary => _host._chatLibrary;
  @override
  TaskQueryPort get _taskQueries => _host._taskQueries;
  @override
  @override
  TaskPresentationPort get _taskPresentation => _host._taskPresentation;
  @override
  TaskPlanningPort get _taskPlanning => _host._taskPlanning;
  @override
  TaskExecutionPort get _taskExecution => _host._taskExecution;
  @override
  TaskRecoveryPort get _taskRecovery => _host._taskRecovery;
  @override
  ProjectQueryPort get _projectQueries => _host._projectQueries;
  @override
  ProjectPlanningPort get _projectPlanning => _host._projectPlanning;
  @override
  ProjectCommandPort get _projectCommands => _host._projectCommands;
  @override
  ProjectExecutionPort get _projectExecution => _host._projectExecution;
  @override
  ChatRuntimePreferencesPort get _preferencesService =>
      _host._preferencesService;
  @override
  ChatCommandCoordinator get _commandCoordinator => _host._commandCoordinator;
  @override
  ChatAutosaveCoordinator get _autosave => _host._autosave;
  @override
  ChatCommandDispatcher get _commandDispatcher => _host._commandDispatcher;
  @override
  ChatTaskCommandCoordinator get _taskCommandCoordinator =>
      _host._taskCommandCoordinator;
  @override
  ChatProjectCommandCoordinator get _projectCommandCoordinator =>
      _host._projectCommandCoordinator;
  @override
  ChatSessionManager get _session => _host._session;
  @override
  ChatWorkspaceLifecycleCoordinator get _workspaceLifecycle =>
      _host._workspaceLifecycle;
  @override
  ChatPresentationMessageBuilder get _presentationMessages =>
      _host._presentationMessages;
  @override
  ChatPanelProtocolAdapter get _panelProtocol => _host._panelProtocol;
  @override
  ThrottledScheduler get _contextEstimateScheduler =>
      _host._contextEstimateScheduler;
  @override
  ThrottledScheduler get _taskModelOutputNotifier =>
      _host._taskModelOutputNotifier;

  @override
  bool get _disposed => _host._disposed;
  @override
  set _disposed(bool value) => _host._disposed = value;
  @override
  bool get loadingSnapshot => _host._loadingSnapshot;
  @override
  set loadingSnapshot(bool value) => _host._loadingSnapshot = value;
  @override
  Future<void>? get _disposeFuture => _host._disposeFuture;
  @override
  set _disposeFuture(Future<void>? value) => _host._disposeFuture = value;
  @override
  String get _chatSessionScopeId => _host._chatSessionScopeId;
  @override
  set _chatSessionScopeId(String value) => _host._chatSessionScopeId = value;
  @override
  int get _historyRevision => _host._historyRevision;
  @override
  set _historyRevision(int value) => _host._historyRevision = value;
  @override
  bool get isSystemPromptLocked => _host.isSystemPromptLocked;
  @override
  ModelConfigurationSnapshot? get _activeServerSnapshot =>
      _host._activeServerSnapshot;
  @override
  bool get _hasPendingPersistence => _host._hasPendingPersistence;
  @override
  int get _currentPersistenceRevision => _host._currentPersistenceRevision;
  @override
  int get _persistedRevision => _host._persistedRevision;
  @override
  String get _taskScopeId => _host._taskScopeId;
  @override
  Future<bool> _taskSystemEnabled() => _host._taskSystemEnabled();
  @override
  Future<String> _ensureTaskScopeId() => _host._ensureTaskScopeId();
  @override
  void Function() get _handleMessagesChanged => _host._handleMessagesChanged;
  @override
  void Function() get _handlePreferencesChanged =>
      _host._handlePreferencesChanged;
  @override
  void _disposeChangeNotifier() => _host._disposeChangeNotifier();

  @override
  Future<Task?> _recoverTaskSnapshot(
    WorkspaceAttachment current,
    Task? snapshot,
  ) => _host._recoverTaskSnapshot(current, snapshot);
  @override
  Future<ProjectCommandResult?> _recoverProject(
    WorkspaceAttachment current,
    ProjectAggregate? snapshot,
  ) => _host._recoverProject(current, snapshot);
  @override
  Future<Task?> _taskForActiveProject(
    WorkspaceAttachment current,
    ProjectAggregate? project,
  ) => _host._taskForActiveProject(current, project);
  @override
  Future<void> runTaskInternal({bool keepBusy = false}) =>
      _host._runTaskInternal(keepBusy: keepBusy);
  @override
  Future<void> _refinePromptFromCommand(ChatSlashCommand command) =>
      _host._refinePromptFromCommand(command);
  @override
  Future<void> _continueTaskFromCommand(String rawCommand) =>
      _host._continueTaskFromCommand(rawCommand);
  @override
  Future<void> _continueProjectFromCommand(String rawCommand) =>
      _host._continueProjectFromCommand(rawCommand);
  @override
  Future<void> _startProjectFromPrompt(
    String prompt, {
    required bool runAfterCreation,
  }) =>
      _host._startProjectFromPrompt(prompt, runAfterCreation: runAfterCreation);
  @override
  Future<void> _runProjectInternal({int? maxNewTasks}) =>
      _host._runProjectInternal(maxNewTasks: maxNewTasks);
  @override
  Future<void> runNextTaskStepInternal({bool keepBusy = false}) =>
      _host._runNextTaskStepInternal(keepBusy: keepBusy);
  @override
  Future<void> _startTaskFromPrompt(
    String prompt, {
    required bool runFirstPhase,
  }) => _host._startTaskFromPrompt(prompt, runFirstPhase: runFirstPhase);

  @override
  Future<TaskSystemSettings> _refreshTaskSystemSettings() =>
      _host._refreshTaskSystemSettings();
  @override
  Future<void> _deleteTransientTasksForCurrentScope() =>
      _host._deleteTransientTasksForCurrentScope();
  @override
  Future<void> _deleteTransientProjectsForCurrentScope() =>
      _host._deleteTransientProjectsForCurrentScope();
  @override
  List<WorkspaceAttachment> _workspacesForSavedChatDeletion(
    String chatId,
    WorkspaceAttachment? savedWorkspace,
  ) => _host._workspacesForSavedChatDeletion(chatId, savedWorkspace);
  @override
  Future<void> _deleteTasksForChatSessionInWorkspaces(
    String chatSessionId,
    Iterable<WorkspaceAttachment> workspaces,
  ) => _host._deleteTasksForChatSessionInWorkspaces(chatSessionId, workspaces);
  @override
  Future<void> _deleteProjectsForChatSessionInWorkspaces(
    String chatSessionId,
    Iterable<WorkspaceAttachment> workspaces,
  ) => _host._deleteProjectsForChatSessionInWorkspaces(
    chatSessionId,
    workspaces,
  );
  @override
  Future<void> _clearProjectTaskBlocker() => _host._clearProjectTaskBlocker();
  @override
  CancellationToken beginTaskCancellationScope({bool reuseExisting = false}) =>
      _host._beginTaskCancellationScope(reuseExisting: reuseExisting);
  @override
  void _endTaskCancellationScope(CancellationToken token) =>
      _host._endTaskCancellationScope(token);
  @override
  void _beginTaskModelOutput(String title) =>
      _host._beginTaskModelOutput(title);
  @override
  void _clearTaskModelOutput({bool notify = true}) =>
      _host._clearTaskModelOutput(notify: notify);
  @override
  void _handleTaskModelOutput(TaskModelOutputEvent event) =>
      _host._handleTaskModelOutput(event);
  @override
  void _finishTaskModelOutput() => _host._finishTaskModelOutput();
  @override
  void _insertTaskAssistantMessage(String text) =>
      _host._insertTaskAssistantMessage(text);
  @override
  void _insertTaskErrorBubble(String text) =>
      _host._insertTaskErrorBubble(text);
  @override
  void _requestContextEstimateUpdate({bool immediate = false}) =>
      _host._requestContextEstimateUpdate(immediate: immediate);
  @override
  void _markPersistableChange() => _host._markPersistableChange();
  @override
  void _resetPersistenceRevisions() => _host._resetPersistenceRevisions();
  @override
  Future<SavedChat> _queueSave({String? title, bool force = false}) =>
      _host._queueSave(title: title, force: force);
  @override
  Future<void> _prepareModelRestorePrompt(
    ModelConfigurationSnapshot? snapshot,
  ) => _host._prepareModelRestorePrompt(snapshot);
  @override
  void _clearSavedState() => _host._clearSavedState();
  @override
  Future<WorkspaceAttachment?> _restoreWorkspace(WorkspaceAttachment? saved) =>
      _host._restoreWorkspace(saved);
  @override
  String buildSystemPromptInternal({
    String? currentUserRequest,
    List<String> additionalModuleIds = const [],
  }) => _host._buildSystemPrompt(
    currentUserRequest: currentUserRequest,
    additionalModuleIds: additionalModuleIds,
  );
  @override
  String _buildTaskSystemPrompt(Task snapshot) =>
      _host._buildTaskSystemPrompt(snapshot);
  @override
  String _buildProjectSystemPrompt(ProjectAggregate snapshot) =>
      _host._buildProjectSystemPrompt(snapshot);
  @override
  List<Bubble> _withCurrentSystemPrompt(
    List<Bubble> messages, {
    required String? currentUserRequest,
  }) => _host._withCurrentSystemPrompt(
    messages,
    currentUserRequest: currentUserRequest,
  );
  @override
  void _syncSystemPrompt() => _host._syncSystemPrompt();
  @override
  void _markWorkspaceChanged() => _host._markWorkspaceChanged();
  @override
  void _adoptActiveModelIfRestoreDismissed() =>
      _host._adoptActiveModelIfRestoreDismissed();

  @override
  void emitChange() => _host.emitChange();
  @override
  void addListener(VoidCallback listener) => _host.addListener(listener);
  @override
  void removeListener(VoidCallback listener) => _host.removeListener(listener);
  @override
  String? get currentChatId => _host.currentChatId;
  @override
  void dispatchCurrentChatId(String? value) =>
      _host.dispatchCurrentChatId(value);
  @override
  SavedChat? get currentSavedChat => _host.currentSavedChat;
  @override
  void dispatchCurrentSavedChat(SavedChat? value) =>
      _host.dispatchCurrentSavedChat(value);
  @override
  void dispatchCurrentModelSnapshot(ModelConfigurationSnapshot? value) =>
      _host.dispatchCurrentModelSnapshot(value);
  @override
  ModelConfigurationSnapshot? get pendingModelRestore =>
      _host.pendingModelRestore;
  @override
  void dispatchPendingModelRestore(ModelConfigurationSnapshot? value) =>
      _host.dispatchPendingModelRestore(value);
  @override
  void dispatchPendingModelRestoreIssue(String? value) =>
      _host.dispatchPendingModelRestoreIssue(value);
  @override
  void dispatchWorkspace(WorkspaceAttachment? value) =>
      _host.dispatchWorkspace(value);
  @override
  void dispatchCurrentSystemPromptSnapshot(SystemPromptSnapshot? value) =>
      _host.dispatchCurrentSystemPromptSnapshot(value);
  @override
  SystemPromptSnapshot? get currentSystemPromptSnapshot =>
      _host.currentSystemPromptSnapshot;
  @override
  ExecutionMode get executionMode => _host.executionMode;
  @override
  void dispatchExecutionMode(ExecutionMode value) =>
      _host.dispatchExecutionMode(value);
  @override
  ProjectAggregate? get activeProject => _host.activeProject;
  @override
  void dispatchActiveProject(ProjectAggregate? value) =>
      _host.dispatchActiveProject(value);
  @override
  void dispatchActiveProjectPersistenceDiagnostics(
    ProjectPersistenceDiagnostics? value,
  ) => _host.dispatchActiveProjectPersistenceDiagnostics(value);
  @override
  List<ProjectSummary> get availableProjects => _host.availableProjects;
  @override
  void dispatchAvailableProjects(List<ProjectSummary> value) =>
      _host.dispatchAvailableProjects(value);
  @override
  Task? get activeTask => _host.activeTask;
  @override
  void dispatchActiveTask(Task? value) => _host.dispatchActiveTask(value);
  @override
  List<TaskSummary> get availableTasks => _host.availableTasks;
  @override
  void dispatchAvailableTasks(List<TaskSummary> value) =>
      _host.dispatchAvailableTasks(value);
  @override
  TaskSystemSettings get taskSystemSettings => _host.taskSystemSettings;
  @override
  void dispatchTaskSystemSettings(TaskSystemSettings value) =>
      _host.dispatchTaskSystemSettings(value);
  @override
  bool get taskBusy => _host.taskBusy;
  @override
  void dispatchTaskBusy(bool value) => _host.dispatchTaskBusy(value);
  @override
  void dispatchTaskCancellationRequested(bool value) =>
      _host.dispatchTaskCancellationRequested(value);
  @override
  void dispatchTaskStatusMessage(String? value) =>
      _host.dispatchTaskStatusMessage(value);
  @override
  void dispatchTaskError(Object? value) => _host.dispatchTaskError(value);
  @override
  String? get taskModelOutputTitle => _host.taskModelOutputTitle;
  @override
  void dispatchTaskModelOutputTitle(String? value) =>
      _host.dispatchTaskModelOutputTitle(value);
  @override
  bool get taskModelOutputActive => _host.taskModelOutputActive;
  @override
  void dispatchTaskModelOutputActive(bool value) =>
      _host.dispatchTaskModelOutputActive(value);
  @override
  Future<void> flushCurrentChat() => _host.flushCurrentChat();
  @override
  Future<void> cancelGeneration() => _host.cancelGeneration();
  @override
  Future<void> cancelTaskRun() => _host.cancelTaskRun();
  @override
  Future<void> reloadTasks() => _host.reloadTasks();
  @override
  void updateCurrentModelSnapshot(ModelConfigurationSnapshot snapshot) =>
      _host.updateCurrentModelSnapshot(snapshot);
  @override
  Future<void> refreshModelRestorePrompt() => _host.refreshModelRestorePrompt();
}
