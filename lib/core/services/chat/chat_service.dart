import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/helpers/chat/context_estimator.dart';
import 'package:hermes/core/helpers/chat/throttled_scheduler.dart';
import 'package:hermes/core/helpers/uuid.dart';
import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/core/models/chat_token.dart';
import 'package:hermes/core/models/chat_persistence.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/models/task_system_settings.dart';
import 'package:hermes/core/models/model_configuration_snapshot.dart';
import 'package:hermes/core/models/saved_chat.dart';
import 'package:hermes/core/models/system_prompt.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/helpers/chat/assistant_ops.dart';
import 'package:hermes/core/helpers/chat/content_normaliser.dart';
import 'package:hermes/core/services/chat/chat_library_service.dart';
import 'package:hermes/core/services/chat/chat_session_manager.dart';
import 'package:hermes/core/services/chat/chat_stream.dart';
import 'package:hermes/core/services/chat/message_store.dart';
import 'package:hermes/core/services/cancellation_token.dart';
import 'package:hermes/core/services/project_system/project_service.dart';
import 'package:hermes/core/services/task_system/task_model_output.dart';
import 'package:hermes/core/services/task_system/task_service.dart';
import 'package:hermes/core/services/task_system/task_summary.dart';
import 'package:hermes/core/services/llama_server_manager.dart';
import 'package:hermes/core/services/preferences_service.dart';
import 'package:hermes/core/helpers/chat/payload_builder.dart';
import 'package:hermes/core/services/prompt_assembler.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/core/services/workspace_service.dart';

import '../disposable.dart';

class ChatService extends ChangeNotifier implements Disposable {
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

  final ToolService _toolService;
  final TaskService _taskService;
  final ProjectService _projectService;
  final ChatLibraryService _chatLibrary;
  final WorkspaceService _workspaceService;
  final PreferencesService _preferencesService;
  final PromptAssembler _promptAssembler = const PromptAssembler();

  late final Bubble systemPrompt = Bubble(
    id: uuid.v7(),
    role: MessageRole.system,
    text: _buildSystemPrompt(),
    reasoning: '',
    createdAt: DateTime.now(),
  );

  bool _disposed = false;
  bool _loadingSnapshot = false;
  int _currentPersistenceRevision = 0;
  int _persistedRevision = 0;
  int _historyRevision = 0;
  Timer? _autosaveTimer;
  Future<void> _saveChain = Future.value();
  _PendingScopeMigration? _pendingScopeMigration;
  Future<void>? _disposeFuture;
  String _chatSessionScopeId = uuid.v7();

  // ── ChatSessionManager instance ─────────────────────────────────────────

  late final ChatSessionManager _session;

  String? currentChatId;
  SavedChat? currentSavedChat;
  ModelConfigurationSnapshot? currentModelSnapshot;
  ModelConfigurationSnapshot? pendingModelRestore;
  String? pendingModelRestoreIssue;
  WorkspaceAttachment? workspace;
  SystemPromptSnapshot? currentSystemPromptSnapshot;
  ExecutionMode executionMode = ExecutionMode.chat;
  ProjectSnapshot? activeProject;
  List<ProjectSummary> availableProjects = const [];
  TaskSnapshot? activeTask;
  List<TaskSummary> availableTasks = const [];
  TaskSystemSettings taskSystemSettings = const TaskSystemSettings();
  bool taskBusy = false;
  bool taskCancellationRequested = false;
  String? taskStatusMessage;
  Object? taskError;
  String? taskModelOutputTitle;
  String taskModelOutputText = '';
  String taskModelOutputReasoning = '';
  bool taskModelOutputActive = false;
  ChatSaveFailure? saveFailure;
  String? _taskModelOutputLabel;
  String? _taskModelOutputTextSection;
  String? _taskModelOutputReasoningLabel;
  int? _taskModelOutputContextEstimate;
  CancellationToken? _taskCancellationToken;
  late final ThrottledScheduler _contextEstimateScheduler;
  late final ThrottledScheduler _taskModelOutputNotifier;

  /// Changes when this tab replaces its entire displayed conversation.
  int get historyRevision => _historyRevision;

  ChatService({
    String? tabId,
    required this.serverManager,
    required ToolService toolService,
    required TaskService taskService,
    required ProjectService projectService,
    required ChatLibraryService chatLibrary,
    required WorkspaceService workspaceService,
    required PreferencesService preferencesService,
    SystemPromptSnapshot? initialSystemPromptSnapshot,
  }) : tabId = tabId ?? uuid.v7(),
       _toolService = toolService,
       _chatLibrary = chatLibrary,
       _workspaceService = workspaceService,
       _preferencesService = preferencesService,
       _taskService = taskService,
       _projectService = projectService {
    currentSystemPromptSnapshot = initialSystemPromptSnapshot;
    messageStore.setMessages([systemPrompt]);

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
      chatService: this,
    );
  }

  // Session hooks used by the streaming implementation.
  int? get sessionDiagnosticsContextLimit => _diagnosticsContextLimit;

  String? sessionTaskModelOutputLabel() => _taskModelOutputLabel;
  void setSessionTaskModelOutputLabel(String? value) {
    _taskModelOutputLabel = value;
  }

  String? sessionTaskModelOutputTextSection() => _taskModelOutputTextSection;
  void setSessionTaskModelOutputTextSection(String? value) {
    _taskModelOutputTextSection = value;
  }

  String? sessionTaskModelOutputReasoningLabel() =>
      _taskModelOutputReasoningLabel;
  void setSessionTaskModelOutputReasoningLabel(String? value) {
    _taskModelOutputReasoningLabel = value;
  }

  String buildSystemPrompt({String? currentUserRequest}) =>
      _buildSystemPrompt(currentUserRequest: currentUserRequest);

  void markWorkspaceChanged() {
    _markPersistableChange();
    notifyListeners();
  }

  void sessionNotifyListeners() => notifyListeners();

  void requestContextEstimateUpdate({bool immediate = false}) {
    _requestContextEstimateUpdate(immediate: immediate);
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

  bool get workspaceToolsEnabled => hasActiveWorkspace;

  String? get activeTaskJson =>
      activeTask == null ? null : _taskService.encodeTask(activeTask!);

  String? get activeProjectJson => activeProject == null
      ? null
      : _projectService.encodeProject(activeProject!);

  List<String> get defaultToolIds => workspaceToolsEnabled
      ? _toolService.defaultToolIds(includeWorkspaceTools: true)
      : const [];

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
        activeProject = (await _recoverProjectSnapshot(
          workspace!,
          await _projectService.loadLatestProject(
            workspace!,
            chatSessionId: snapshot.chat.id,
          ),
        ))?.project;
        availableProjects = await _projectService.listProjects(
          workspace!,
          chatSessionId: snapshot.chat.id,
        );
        activeTask = await _taskForActiveProject(workspace!, activeProject);
        if (activeTask == null && activeProject == null) {
          activeTask = await _recoverTaskSnapshot(
            workspace!,
            await _taskService.loadLatestTask(
              workspace!,
              chatSessionId: snapshot.chat.id,
            ),
          );
        }
        availableTasks = await _taskService.listTasks(
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
      await _deleteTasksForChatSessionInWorkspaces(chatId, workspaces);
      await _deleteProjectsForChatSessionInWorkspaces(chatId, workspaces);
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
      await _taskService.deleteTasksForChatSession(
        previousWorkspace,
        chatSessionId: previousScopeId,
      );
      await _projectService.deleteProjectsForChatSession(
        previousWorkspace,
        chatSessionId: previousScopeId,
      );
    }
    workspace = nextWorkspace;
    _syncSystemPrompt();
    final scopeId = _taskScopeId;
    activeProject = (await _recoverProjectSnapshot(
      workspace!,
      await _projectService.loadLatestProject(
        workspace!,
        chatSessionId: scopeId,
      ),
    ))?.project;
    availableProjects = await _projectService.listProjects(
      workspace!,
      chatSessionId: scopeId,
    );
    activeTask = await _taskForActiveProject(workspace!, activeProject);
    if (activeTask == null && activeProject == null) {
      activeTask = await _recoverTaskSnapshot(
        workspace!,
        await _taskService.loadLatestTask(workspace!, chatSessionId: scopeId),
      );
    }
    availableTasks = await _taskService.listTasks(
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
    final token = _taskCancellationToken;
    taskCancellationRequested = true;
    taskStatusMessage = 'Cancelling run...';
    notifyListeners();
    if (token == null) return;
    await token.cancel();
  }

  Future<void> reloadTasks() async {
    final current = workspace;
    if (current == null || current.missing) {
      availableTasks = const [];
      availableProjects = const [];
      activeTask = null;
      activeProject = null;
      notifyListeners();
      return;
    }

    final scopeId = _taskScopeId;
    activeProject = (await _recoverProjectSnapshot(
      current,
      activeProject ??
          await _projectService.loadLatestProject(
            current,
            chatSessionId: scopeId,
          ),
    ))?.project;
    availableProjects = await _projectService.listProjects(
      current,
      chatSessionId: scopeId,
    );
    final activeScopeId = activeTask?.chatSessionId;
    final scopedActiveTask =
        activeTask != null &&
            (activeScopeId == null || activeScopeId == scopeId)
        ? activeTask
        : null;
    activeTask = await _taskForActiveProject(current, activeProject);
    if (activeTask == null && activeProject == null) {
      activeTask = await _recoverTaskSnapshot(
        current,
        scopedActiveTask ??
            await _taskService.loadLatestTask(current, chatSessionId: scopeId),
      );
    }
    availableTasks = await _taskService.listTasks(
      current,
      chatSessionId: scopeId,
    );
    notifyListeners();
  }

  Future<TaskSnapshot?> _recoverTaskSnapshot(
    WorkspaceAttachment current,
    TaskSnapshot? snapshot,
  ) {
    if (snapshot == null) return Future.value();
    return _taskService.recoverTask(workspace: current, snapshot: snapshot);
  }

  Future<ProjectRunResult?> _recoverProjectSnapshot(
    WorkspaceAttachment current,
    ProjectSnapshot? snapshot,
  ) {
    if (snapshot == null) return Future.value();
    return _projectService.recoverProject(
      workspace: current,
      snapshot: snapshot,
      onTaskUpdated: (task) => activeTask = task,
    );
  }

  Future<TaskSnapshot?> _taskForActiveProject(
    WorkspaceAttachment current,
    ProjectSnapshot? project,
  ) async {
    final taskDocumentId = project?.activeTaskDocumentId;
    if (project == null || taskDocumentId == null) return null;
    return _recoverTaskSnapshot(
      current,
      await _taskService.loadTask(
        current,
        taskDocumentId,
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
    activeTask = await _recoverTaskSnapshot(
      current,
      await _taskService.loadLatestTask(current, chatSessionId: scopeId),
    );
    await reloadTasks();
  }

  Future<void> loadTask(String taskId) async {
    final current = workspace;
    final scopeId = _taskScopeId;
    if (current == null || current.missing || taskBusy) {
      return;
    }
    activeTask = await _recoverTaskSnapshot(
      current,
      await _taskService.loadTask(current, taskId, chatSessionId: scopeId),
    );
    await reloadTasks();
  }

  Future<void> resumeLatestProject() async {
    final current = workspace;
    final scopeId = _taskScopeId;
    if (current == null || current.missing || taskBusy) {
      return;
    }
    final result = await _recoverProjectSnapshot(
      current,
      await _projectService.loadLatestProject(current, chatSessionId: scopeId),
    );
    activeProject = result?.project;
    activeTask = result?.activeTask;
    await reloadTasks();
  }

  Future<void> loadProject(String projectId) async {
    final current = workspace;
    final scopeId = _taskScopeId;
    if (current == null || current.missing || taskBusy) {
      return;
    }
    final result = await _recoverProjectSnapshot(
      current,
      await _projectService.loadProject(
        current,
        projectId,
        chatSessionId: scopeId,
      ),
    );
    activeProject = result?.project;
    activeTask = result?.activeTask;
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
    final client = serverManager.chatClient;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        client == null ||
        activeTask == null ||
        taskBusy && !keepBusy) {
      return;
    }

    final token = _beginTaskCancellationScope(reuseExisting: keepBusy);

    if (!keepBusy) {
      taskBusy = true;
      taskError = null;
      _beginTaskModelOutput('Task Run Model Output');
      notifyListeners();
    }
    await _refreshTaskSystemSettings();
    taskStatusMessage = 'Running task...';
    notifyListeners();

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
            updated.status == TaskStatus.paused ||
            updated.status == TaskStatus.blocked ||
            updated.status == TaskStatus.failed ||
            updated.status == TaskStatus.cancelled) {
          break;
        }
      }
    } on OperationCancelledException {
      _insertTaskAssistantMessage('Task run cancelled.');
    } catch (e) {
      taskError = e;
      _insertTaskErrorBubble('Failed to run task: $e');
    } finally {
      if (!keepBusy) {
        taskBusy = false;
        _endTaskCancellationScope(token);
        taskStatusMessage = null;
        _finishTaskModelOutput();
        notifyListeners();
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

    activeTask = await _taskService.retryCurrentStep(
      workspace: currentWorkspace,
      snapshot: snapshot,
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

    activeTask = await _taskService.skipCurrentStep(
      workspace: currentWorkspace,
      snapshot: snapshot,
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

    activeTask = await _taskService.stopTask(
      workspace: currentWorkspace,
      snapshot: snapshot,
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

    activeTask = await _taskService.answerOpenQuestion(
      workspace: currentWorkspace,
      snapshot: snapshot,
      answer: answer,
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

    activeTask = await _taskService.approvePendingStep(
      workspace: currentWorkspace,
      snapshot: snapshot,
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

    activeProject = await _projectService.answerOpenQuestion(
      workspace: currentWorkspace,
      snapshot: snapshot,
      answer: answer,
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

    activeProject = await _projectService.stopProject(
      workspace: currentWorkspace,
      snapshot: snapshot,
    );
    activeTask = null;
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

    activeProject = await _projectService.pauseProject(
      workspace: currentWorkspace,
      snapshot: snapshot,
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

    activeProject = await _projectService.retryRecoveryIncident(
      workspace: currentWorkspace,
      snapshot: snapshot,
      incidentId: incidentId,
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
    activeProject = await _projectService.approvePlanRevision(
      workspace: currentWorkspace,
      snapshot: snapshot,
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
    activeProject = await _projectService.rejectPlanRevision(
      workspace: currentWorkspace,
      snapshot: snapshot,
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
    activeProject = await _projectService.requestScopeChange(
      workspace: currentWorkspace,
      snapshot: snapshot,
      context: reason.trim().isEmpty
          ? 'User explicitly requested a roadmap revision.'
          : reason,
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
    final client = serverManager.chatClient;
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

    taskBusy = true;
    final token = _beginTaskCancellationScope();
    taskError = null;
    taskStatusMessage = 'Refining task brief...';
    _beginTaskModelOutput('Task Brief Model Output');
    notifyListeners();

    try {
      final brief = await _taskService.refineTaskBrief(
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
      taskError = e;
      _insertTaskErrorBubble('Failed to refine task brief: $e');
    } finally {
      taskBusy = false;
      _endTaskCancellationScope(token);
      taskStatusMessage = null;
      _finishTaskModelOutput();
      notifyListeners();
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
    activeTask ??= await _recoverTaskSnapshot(
      currentWorkspace,
      await _taskService.loadLatestTask(
        currentWorkspace,
        chatSessionId: scopeId,
      ),
    );
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
    activeProject ??= (await _recoverProjectSnapshot(
      currentWorkspace,
      await _projectService.loadLatestProject(
        currentWorkspace,
        chatSessionId: scopeId,
      ),
    ))?.project;
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
    final client = serverManager.chatClient;
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
        (await _recoverProjectSnapshot(
          currentWorkspace,
          await _projectService.loadLatestProject(
            currentWorkspace,
            chatSessionId: scopeId,
          ),
        ))?.project;
    if (existingProject != null && !existingProject.isTerminal) {
      activeProject = await _projectService.addUserContext(
        workspace: currentWorkspace,
        snapshot: existingProject,
        text: prompt,
      );
      activeTask = null;
      await reloadTasks();
      _insertTaskAssistantMessage(_projectStatusMessage(activeProject!));
      if (runAfterCreation) {
        await _runProjectInternal();
      }
      return;
    }

    taskBusy = true;
    final token = _beginTaskCancellationScope();
    taskError = null;
    taskStatusMessage = runAfterCreation
        ? 'Creating project and preparing first task...'
        : 'Creating project...';
    _beginTaskModelOutput('Project Creation Model Output');
    notifyListeners();

    try {
      final project = await _projectService.createProject(
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
      activeProject = project;
      activeTask = null;
      await reloadTasks();
      _insertTaskAssistantMessage(_projectCreatedMessage(project));

      if (runAfterCreation) {
        activeProject = project;
        await _runProjectInternal(keepBusy: true);
      }
    } on OperationCancelledException {
      _insertTaskAssistantMessage('Project creation cancelled.');
    } catch (e) {
      taskError = e;
      _insertTaskErrorBubble('Failed to create project: $e');
    } finally {
      taskBusy = false;
      _endTaskCancellationScope(token);
      taskStatusMessage = null;
      _finishTaskModelOutput();
      notifyListeners();
    }
  }

  Future<void> _runProjectInternal({
    bool keepBusy = false,
    int? maxNewTasks,
  }) async {
    final currentWorkspace = workspace;
    final client = serverManager.chatClient;
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
      taskBusy = true;
      taskError = null;
      _beginTaskModelOutput('Project Run Model Output');
      notifyListeners();
    }
    final settings = await _refreshTaskSystemSettings();
    taskStatusMessage = 'Running project...';
    notifyListeners();

    try {
      final compactionSettings = await _preferencesService
          .getCompactionSettings();
      final result = await _projectService.runProject(
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
          taskStatusMessage = status;
          notifyListeners();
        },
        onModelOutput: _handleTaskModelOutput,
        onTaskUpdated: (task) {
          activeTask = task;
          notifyListeners();
        },
        cancellationToken: token,
      );
      activeProject = result.project;
      activeTask = result.activeTask;
      await reloadTasks();
      _insertTaskAssistantMessage(_projectStatusMessage(result.project));
    } on OperationCancelledException {
      _insertTaskAssistantMessage('Project run cancelled.');
    } catch (e) {
      taskError = e;
      _insertTaskErrorBubble('Failed to run project: $e');
    } finally {
      if (!keepBusy) {
        taskBusy = false;
        _endTaskCancellationScope(token);
        taskStatusMessage = null;
        _finishTaskModelOutput();
        notifyListeners();
      }
    }
  }

  Future<void> _runNextTaskStepInternal({bool keepBusy = false}) async {
    final currentWorkspace = workspace;
    final client = serverManager.chatClient;
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
      taskBusy = true;
      taskError = null;
      _beginTaskModelOutput('Task Step Model Output');
      notifyListeners();
    }
    taskStatusMessage = 'Running step ${nextStep.id}: ${nextStep.title}';
    notifyListeners();

    try {
      final compactionSettings = await _preferencesService
          .getCompactionSettings();
      final updated = await _taskService.runNextStep(
        client: client,
        workspace: currentWorkspace,
        snapshot: snapshot,
        baseSystemPrompt: _buildTaskSystemPrompt(snapshot),
        requirePhaseApproval: taskSystemSettings.requireApprovalBeforeFileEdits,
        questionAutonomy: taskSystemSettings.questionAutonomy,
        compactionSettings: compactionSettings,
        contextLimitTokens: _diagnosticsContextLimit,
        onCompactionStatus: (status) {
          taskStatusMessage = status;
          notifyListeners();
        },
        onModelOutput: _handleTaskModelOutput,
        cancellationToken: token,
      );
      activeTask = updated;
      await reloadTasks();
      _insertTaskAssistantMessage(_stepFinishedMessage(updated));
    } on OperationCancelledException {
      _insertTaskAssistantMessage('Task step cancelled.');
    } catch (e) {
      taskError = e;
      _insertTaskErrorBubble('Failed to run task step: $e');
    } finally {
      if (!keepBusy) {
        taskBusy = false;
        _endTaskCancellationScope(token);
        taskStatusMessage = null;
        _finishTaskModelOutput();
        notifyListeners();
      }
    }
  }

  // ── Task creation (shared by send() in task/project mode and slash commands) ──

  Future<void> _startTaskFromPrompt(
    String prompt, {
    required bool runFirstPhase,
  }) async {
    final currentWorkspace = workspace;
    final client = serverManager.chatClient;
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

    taskBusy = true;
    final token = _beginTaskCancellationScope();
    taskError = null;
    taskStatusMessage = runFirstPhase
        ? 'Creating task plan and preparing first phase...'
        : 'Creating task plan...';
    _beginTaskModelOutput('Task Creation Model Output');
    notifyListeners();

    try {
      final scopeId = await _ensureTaskScopeId();
      final snapshot = await _taskService.createTask(
        client: client,
        workspace: currentWorkspace,
        userPrompt: prompt,
        selectedMode: ExecutionMode.task,
        baseSystemPrompt: _buildSystemPrompt(currentUserRequest: prompt),
        chatSessionId: scopeId,
        onModelOutput: _handleTaskModelOutput,
        cancellationToken: token,
      );
      activeTask = snapshot;
      await reloadTasks();
      _insertTaskAssistantMessage(_taskCreatedMessage(snapshot));

      if (runFirstPhase) {
        activeTask = snapshot;
        await _runTaskInternal(keepBusy: true);
      }
    } on OperationCancelledException {
      _insertTaskAssistantMessage('Task creation cancelled.');
    } catch (e) {
      taskError = e;
      _insertTaskErrorBubble('Failed to create task: $e');
    } finally {
      taskBusy = false;
      _endTaskCancellationScope(token);
      taskStatusMessage = null;
      _finishTaskModelOutput();
      notifyListeners();
    }
  }

  // ── Business operations delegated to other services ─────────────────────

  Future<void> replanRemainingTask() async {
    final currentWorkspace = workspace;
    final client = serverManager.chatClient;
    final snapshot = activeTask;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        client == null ||
        snapshot == null ||
        taskBusy) {
      return;
    }

    taskBusy = true;
    final token = _beginTaskCancellationScope();
    taskError = null;
    taskStatusMessage = 'Replanning unfinished work...';
    _beginTaskModelOutput('Replan Model Output');
    notifyListeners();
    try {
      activeTask = await _taskService.replanUnfinished(
        client: client,
        workspace: currentWorkspace,
        snapshot: snapshot,
        baseSystemPrompt: _buildTaskSystemPrompt(snapshot),
        onModelOutput: _handleTaskModelOutput,
        cancellationToken: token,
      );
      await reloadTasks();
      _insertTaskAssistantMessage(
        'Unfinished work replanned for **${activeTask!.title}**. Next step: `${activeTask!.currentStepId ?? 'none'}`.',
      );
    } on OperationCancelledException {
      _insertTaskAssistantMessage('Replan cancelled.');
    } catch (e) {
      taskError = e;
      rethrow;
    } finally {
      taskBusy = false;
      _endTaskCancellationScope(token);
      taskStatusMessage = null;
      _finishTaskModelOutput();
      notifyListeners();
    }
  }

  Future<void> updateTaskTaskBrief(String rawJson) async {
    await updateTaskPlan(rawJson);
  }

  Future<void> updateTaskSpec(String rawJson) async {
    await updateTaskPlan(rawJson);
  }

  Future<void> updateTaskPlan(String rawJson) async {
    final currentWorkspace = workspace;
    final snapshot = activeTask;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null ||
        taskBusy) {
      return;
    }

    taskBusy = true;
    taskError = null;
    taskStatusMessage = 'Updating task plan...';
    notifyListeners();
    try {
      activeTask = await _taskService.updateTaskPlan(
        workspace: currentWorkspace,
        snapshot: snapshot,
        rawJson: rawJson,
      );
      await reloadTasks();
      _insertTaskAssistantMessage(
        'Task plan updated for **${activeTask!.title}**.',
      );
    } catch (e) {
      taskError = e;
      rethrow;
    } finally {
      taskBusy = false;
      taskStatusMessage = null;
      notifyListeners();
    }
  }

  Future<void> updateProjectPlan(String rawJson) async {
    final currentWorkspace = workspace;
    final snapshot = activeProject;
    if (currentWorkspace == null ||
        currentWorkspace.missing ||
        snapshot == null ||
        taskBusy) {
      return;
    }

    taskBusy = true;
    taskError = null;
    taskStatusMessage = 'Updating project...';
    notifyListeners();
    try {
      activeProject = await _projectService.updateProject(
        workspace: currentWorkspace,
        snapshot: snapshot,
        rawJson: rawJson,
      );
      await reloadTasks();
      _insertTaskAssistantMessage(
        'Project updated for **${activeProject!.title}**.',
      );
    } catch (e) {
      taskError = e;
      rethrow;
    } finally {
      taskBusy = false;
      taskStatusMessage = null;
      notifyListeners();
    }
  }

  Future<String> readTaskArtifact(String artifactPath) async {
    final currentWorkspace = workspace;
    if (currentWorkspace == null || currentWorkspace.missing) {
      throw StateError('No active workspace is attached.');
    }
    return _taskService.readArtifact(
      workspace: currentWorkspace,
      artifactPath: artifactPath,
    );
  }

  // ── Session state management ────────────────────────────────────────────

  void _handleMessagesChanged() {
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
    await _taskService.deleteTasksForChatSession(
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
    await _projectService.deleteProjectsForChatSession(
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
      await _taskService.deleteTasksForChatSession(
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
      await _projectService.deleteProjectsForChatSession(
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
    activeProject = await _projectService.clearTaskBlocker(
      workspace: currentWorkspace,
      snapshot: project,
    );
  }

  CancellationToken _beginTaskCancellationScope({bool reuseExisting = false}) {
    if (reuseExisting) {
      final existing = _taskCancellationToken;
      if (existing != null) return existing;
    }
    final token = CancellationToken();
    _taskCancellationToken = token;
    taskCancellationRequested = false;
    return token;
  }

  void _endTaskCancellationScope(CancellationToken token) {
    if (!identical(_taskCancellationToken, token)) return;
    _taskCancellationToken = null;
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
        throw StateError('ChatService is disposed');
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
        _pendingScopeMigration ??= _PendingScopeMigration(
          previousScopeId: previousScopeId,
          savedChatId: saved.id,
          workspace: capturedWorkspace,
          activeTaskId: capturedActiveTaskId,
          activeProjectId: capturedActiveProjectId,
        );
      }
      final pendingMigration = _pendingScopeMigration;
      if (pendingMigration != null &&
          pendingMigration.savedChatId == saved.id) {
        await _migrateTaskScope(
          previousScopeId: pendingMigration.previousScopeId,
          savedChatId: pendingMigration.savedChatId,
          migrationWorkspace: pendingMigration.workspace,
          activeTaskId: pendingMigration.activeTaskId,
        );
        await _migrateProjectScope(
          previousScopeId: pendingMigration.previousScopeId,
          savedChatId: pendingMigration.savedChatId,
          migrationWorkspace: pendingMigration.workspace,
          activeProjectId: pendingMigration.activeProjectId,
        );
        _pendingScopeMigration = null;
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

  Future<void> _migrateTaskScope({
    required String previousScopeId,
    required String savedChatId,
    required WorkspaceAttachment? migrationWorkspace,
    required String? activeTaskId,
  }) async {
    if (previousScopeId == savedChatId) return;
    final currentWorkspace = migrationWorkspace;
    if (currentWorkspace == null || currentWorkspace.missing) return;

    final tasks = await _taskService.listTasks(
      currentWorkspace,
      chatSessionId: previousScopeId,
    );
    for (final task in tasks) {
      final snapshot = await _taskService.loadTask(
        currentWorkspace,
        task.id,
        chatSessionId: previousScopeId,
      );
      if (snapshot == null) continue;
      final updated = await _taskService.updateTaskChatSessionId(
        workspace: currentWorkspace,
        snapshot: snapshot,
        chatSessionId: savedChatId,
      );
      if (updated.id == activeTaskId &&
          workspace?.rootPath == currentWorkspace.rootPath) {
        activeTask = updated;
      }
    }
    final migratedTasks = await _taskService.listTasks(
      currentWorkspace,
      chatSessionId: savedChatId,
    );
    if (workspace?.rootPath == currentWorkspace.rootPath) {
      availableTasks = migratedTasks;
    }
  }

  Future<void> _migrateProjectScope({
    required String previousScopeId,
    required String savedChatId,
    required WorkspaceAttachment? migrationWorkspace,
    required String? activeProjectId,
  }) async {
    if (previousScopeId == savedChatId) return;
    final currentWorkspace = migrationWorkspace;
    if (currentWorkspace == null || currentWorkspace.missing) return;

    final projects = await _projectService.listProjects(
      currentWorkspace,
      chatSessionId: previousScopeId,
    );
    for (final project in projects) {
      final snapshot = await _projectService.loadProject(
        currentWorkspace,
        project.id,
        chatSessionId: previousScopeId,
      );
      if (snapshot == null) continue;
      final updated = await _projectService.updateProjectChatSessionId(
        workspace: currentWorkspace,
        snapshot: snapshot,
        chatSessionId: savedChatId,
      );
      if (updated.id == activeProjectId &&
          workspace?.rootPath == currentWorkspace.rootPath) {
        activeProject = updated;
      }
    }
    final migratedProjects = await _projectService.listProjects(
      currentWorkspace,
      chatSessionId: savedChatId,
    );
    if (workspace?.rootPath == currentWorkspace.rootPath) {
      availableProjects = migratedProjects;
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
    _pendingScopeMigration = null;
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
      commandExecutionApproved: saved.commandExecutionApproved,
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
        : defaultSystemPromptText;
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

  String _buildTaskSystemPrompt(TaskSnapshot snapshot) {
    return _buildSystemPrompt(currentUserRequest: snapshot.originalPrompt);
  }

  String _buildProjectSystemPrompt(ProjectSnapshot snapshot) {
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

  List<String> _autoModuleIdsForWorkspace() {
    final currentWorkspace = workspace;
    if (currentWorkspace == null) return const [];
    return currentWorkspace.missing
        ? const [BuiltInPromptIds.workspaceMissingModule]
        : const [BuiltInPromptIds.workspaceRulesModule];
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
    notifyListeners();
  }

  void _adoptActiveModelIfRestoreDismissed() {
    if (pendingModelRestore != null) return;

    final activeSnapshot = _activeServerSnapshot;
    if (activeSnapshot == null ||
        activeSnapshot.matches(currentModelSnapshot)) {
      return;
    }

    currentModelSnapshot = activeSnapshot;
    _requestContextEstimateUpdate(immediate: true);
    _markPersistableChange();
    notifyListeners();
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

  String _taskCreatedMessage(TaskSnapshot snapshot) {
    final buffer = StringBuffer()
      ..writeln('Task created: **${snapshot.title}**')
      ..writeln()
      ..writeln('Status: `${snapshot.status.wire}`')
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

  String _projectCreatedMessage(ProjectSnapshot snapshot) {
    final buffer = StringBuffer()
      ..writeln('Project created: **${snapshot.title}**')
      ..writeln()
      ..writeln('Status: `${snapshot.status.wire}`')
      ..writeln()
      ..writeln('Goal:')
      ..writeln(snapshot.refinedGoal)
      ..writeln()
      ..writeln(
        'Project state is stored under `.agent/projects/${snapshot.id}/`.',
      );
    return buffer.toString().trim();
  }

  String _projectStatusMessage(ProjectSnapshot snapshot) {
    final buffer = StringBuffer()
      ..writeln('Project status: **${snapshot.title}**')
      ..writeln()
      ..writeln('Status: `${snapshot.status.wire}`');
    if (snapshot.status == ProjectStatus.paused &&
        snapshot.activeTaskId != null) {
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
          'Latest task: `${latest.taskDocumentId ?? latest.id}` - '
          '${latest.status.wire}',
        );
    }
    return buffer.toString().trim();
  }

  String _stepFinishedMessage(TaskSnapshot snapshot) {
    final latestRun = snapshot.runs.isEmpty ? null : snapshot.runs.last;
    final buffer = StringBuffer()
      ..writeln('Task step finished: **${latestRun?.stepId ?? 'step'}**')
      ..writeln()
      ..writeln('Task status: `${snapshot.status.wire}`');
    if (snapshot.status == TaskStatus.paused) {
      buffer
        ..writeln()
        ..writeln(
          'Model transport was interrupted. Resume the task to retry this step.',
        );
    } else if (latestRun != null) {
      buffer
        ..writeln()
        ..writeln(latestRun.summary);
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

  @override
  // ignore: must_call_super, super.dispose is called by _dispose after async cleanup.
  Future<void> dispose() => _startDispose(saveChanges: true);

  Future<void> disposeWithoutSaving() => _startDispose(saveChanges: false);

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
        super.dispose();
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

class _PendingScopeMigration {
  const _PendingScopeMigration({
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
