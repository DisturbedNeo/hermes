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
import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/features/task/domain/task.dart';
import 'package:hermes/core/contracts/execution_settings.dart';
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
import 'package:hermes/features/chat/runtime/chat_presentation_message_builder.dart';
import 'package:hermes/features/chat/runtime/chat_autosave_coordinator.dart';
import 'package:hermes/features/chat/runtime/chat_workspace_lifecycle_coordinator.dart';
import 'package:hermes/features/chat/runtime/chat_command_dispatcher.dart';
import 'package:hermes/features/chat/runtime/chat_task_command_coordinator.dart';
import 'package:hermes/features/chat/runtime/chat_project_command_coordinator.dart';
import 'package:hermes/features/chat/runtime/chat_session_host.dart';
import 'package:hermes/features/chat/runtime/chat_application/chat_command_coordinator.dart';
import 'package:hermes/features/chat/application/chat_view_state.dart';
import 'package:hermes/features/chat/domain/chat_state.dart';
import 'package:hermes/features/chat/domain/chat_panel_read_models.dart';
import 'package:hermes/features/chat/application/chat_panel_projection.dart';
import 'package:hermes/features/chat/runtime/chat_application/chat_tool_execution_service.dart';
import 'package:hermes/features/chat/runtime/chat_application/chat_stream.dart';
import 'package:hermes/features/chat/runtime/chat_application/message_store.dart';
import 'package:hermes/core/cancellation.dart';
import 'package:hermes/features/project/application/project_application/project_ports.dart';
import 'package:hermes/features/project/application/project_application/project_workflow_port.dart';
import 'package:hermes/features/project/application/project_application/project_execution_port.dart';
import 'package:hermes/features/persistence/application/persistence_contracts.dart';
import 'package:hermes/features/model/application/model_output.dart';
import 'package:hermes/features/task/application/task_application/task_ports.dart';
import 'package:hermes/features/task/application/task_application/task_workflow_port.dart';
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

// Chat session operations

// Chat work operations

// Chat persistence operations

// Chat prompt operations

// Chat lifecycle operations

// Chat operation models

part 'chat_session_operations.dart';
part 'chat_session_commands.dart';
part 'chat_session_state_operations.dart';
part 'chat_task_plan_use_case.dart';
part 'chat_task_replan_use_case.dart';
part 'chat_exit_use_case.dart';
part 'chat_session_lifecycle_use_case.dart';
part 'chat_work_use_case.dart';
part 'chat_state_mutation_use_case.dart';
part 'chat_use_case_context.dart';

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

/// Runtime-only aggregate handles used while commands execute. The UI never
/// reads this object; it receives the value snapshots stored in [ChatState].
class _ChatExecutionContext {
  ProjectAggregate? project;
  TaskAggregate? task;
}

class ChatSessionOrchestrator extends ChangeNotifier
    implements ChatSessionHost {
  static const String defaultSystemPromptName = 'Default';
  static const String defaultSystemPromptText = 'You are a helpful assistant.';
  static const Duration _contextEstimateThrottle = Duration(milliseconds: 500);
  static const Duration _taskModelOutputNotifyThrottle = Duration(
    milliseconds: 100,
  );

  final String tabId;
  final ModelServerPort serverManager;
  ActiveModelSessionPort get activeModelSession => serverManager;
  ModelServerLifecyclePort get serverLifecycle => serverManager;
  final MessageStore messageStore = MessageStore();
  final ChatStream<ChatToken> chatStream = ChatStream<ChatToken>();

  final ToolRegistryPort _toolService;
  final TaskWorkflowQueryPort _taskQueries;
  final TaskSessionPort _taskSessions;
  final TaskPresentationPort _taskPresentation;
  final ChatPanelProtocolAdapter _panelProtocol;
  final TaskWorkflowPort _taskPlanning;
  final TaskWorkflowPort _taskExecution;
  final TaskWorkflowPort _taskRecovery;
  final ProjectWorkflowQueryPort _projectQueries;
  final ProjectSessionPort _projectSessions;
  final ProjectWorkflowPort _projectPlanning;
  final ProjectWorkflowPort _projectCommands;
  final ProjectWorkflowPort _projectExecution;
  final ProjectWorkflowPort _projectRecovery;
  final ChatLibraryService _chatLibrary;
  final WorkspacePort _workspaceService;
  final ChatRuntimePreferencesPort _preferencesService;
  final ChatCommandCoordinator _commandCoordinator;
  final ChatPromptConstructionService _promptConstruction;
  final ChatPersistenceRuntime _persistenceRuntime;
  final ChatPresentationMessageBuilder _presentationMessages =
      const ChatPresentationMessageBuilder();
  final ChatAutosaveCoordinator _autosave = ChatAutosaveCoordinator();
  final ChatCommandDispatcher _commandDispatcher =
      const ChatCommandDispatcher();
  late final ChatTaskCommandCoordinator _taskCommandCoordinator;
  late final ChatProjectCommandCoordinator _projectCommandCoordinator;
  late final ChatTaskPlanUseCase _taskPlanUseCase;
  late final ChatTaskReplanUseCase _taskReplanUseCase;
  late final ChatExitUseCase _exitUseCase;
  late final ChatSessionLifecycleUseCase _sessionLifecycleUseCase;
  late final ChatWorkUseCase _workUseCase;
  late final ChatStateMutationUseCase _stateMutationUseCase;

  late final Bubble systemPrompt;

  bool _disposed = false;
  bool _loadingSnapshot = false;
  int _currentPersistenceRevision = 0;
  int _persistedRevision = 0;
  int _historyRevision = 0;
  _PendingScopeMove? _pendingScopeMove;
  Future<void>? _disposeFuture;
  String _chatSessionScopeId = uuid.v7();

  // ── ChatSessionManager instance ─────────────────────────────────────────

  late final ChatSessionManager _session;
  late final ChatWorkspaceLifecycleCoordinator _workspaceLifecycle;

  late ChatState _state;
  final _ChatExecutionContext _executionContext = _ChatExecutionContext();
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

  ProjectAggregate? get activeProject => _executionContext.project;
  void dispatchActiveProject(ProjectAggregate? value) {
    _executionContext.project = value;
    _dispatchChatState(
      ChatProjectChanged(
        value == null ? null : ChatPanelProjection.project(value),
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

  TaskAggregate? get activeTask => _executionContext.task;
  void dispatchActiveTask(TaskAggregate? value) {
    _executionContext.task = value;
    _dispatchChatState(
      ChatTaskChanged(value == null ? null : ChatPanelProjection.task(value)),
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

  Future<void> updateTaskTaskBrief(TaskPlanUpdateCommand command) =>
      _taskPlanUseCase.updateTaskTaskBrief(command);

  Future<void> updateTaskSpec(TaskPlanUpdateCommand command) =>
      _taskPlanUseCase.updateTaskSpec(command);

  Future<void> updateTaskPlan(TaskPlanUpdateCommand command) =>
      _taskPlanUseCase.updateTaskPlan(command);

  Future<void> updateProjectPlan(ProjectUpdateCommand command) =>
      _taskPlanUseCase.updateProjectPlan(command);

  Future<String> readTaskArtifact(String artifactPath) =>
      _taskPlanUseCase.readTaskArtifact(artifactPath);

  Future<void> replanRemainingTask() => _taskReplanUseCase.execute();

  Future<void> quiesceForExit({
    Duration timeout = const Duration(seconds: 5),
  }) => _exitUseCase.quiesceForExit(timeout: timeout);

  Future<void> disposeAsync() => _exitUseCase.disposeAsync();

  Future<void> disposeWithoutSavingAsync() =>
      _exitUseCase.disposeWithoutSavingAsync();

  Future<void> newChat({SystemPromptSnapshot? systemPromptSnapshot}) =>
      _sessionLifecycleUseCase.newChat(
        systemPromptSnapshot: systemPromptSnapshot,
      );

  Future<bool> openChat(String id) => _sessionLifecycleUseCase.openChat(id);

  Future<SavedChat> saveCurrentChat({String? title}) =>
      _sessionLifecycleUseCase.saveCurrentChat(title: title);

  Future<SavedChat> retrySave() => _sessionLifecycleUseCase.retrySave();

  Future<void> deleteSavedChat(String chatId) =>
      _sessionLifecycleUseCase.deleteSavedChat(chatId);

  Future<void> resetIfCurrentSavedChatDeleted(String chatId) =>
      _sessionLifecycleUseCase.resetIfCurrentSavedChatDeleted(chatId);

  Future<void> flushCurrentChat() =>
      _sessionLifecycleUseCase.flushCurrentChat();

  Future<void> restorePendingModel() =>
      _sessionLifecycleUseCase.restorePendingModel();

  Future<void> refreshModelRestorePrompt() =>
      _sessionLifecycleUseCase.refreshModelRestorePrompt();

  void updateCurrentModelSnapshot(ModelConfigurationSnapshot snapshot) =>
      _stateMutationUseCase.updateCurrentModelSnapshot(snapshot);

  void dismissPendingModelRestore() =>
      _stateMutationUseCase.dismissPendingModelRestore();

  void updateSystemPromptSnapshot(SystemPromptSnapshot snapshot) =>
      _stateMutationUseCase.updateSystemPromptSnapshot(snapshot);

  String buildSystemPromptForTesting({
    String? currentUserRequest,
    List<String> additionalModuleIds = const [],
  }) => _stateMutationUseCase.buildSystemPromptForTesting(
    currentUserRequest: currentUserRequest,
    additionalModuleIds: additionalModuleIds,
  );

  void insertMessage(String text, MessageRole role) =>
      _stateMutationUseCase.insertMessage(text, role);

  void updateCommandExecutionApproval(bool approved) =>
      _stateMutationUseCase.updateCommandExecutionApproval(approved);

  void updateExecutionMode(ExecutionMode mode) =>
      _stateMutationUseCase.updateExecutionMode(mode);

  Future<void> attachWorkspace(String folderPath) =>
      _workUseCase.attachWorkspace(folderPath);

  Future<void> detachWorkspace() => _workUseCase.detachWorkspace();

  Future<void> send(String text, {List<String>? tools = const []}) =>
      _workUseCase.send(text, tools: tools);

  Future<void> generateOrContinue({
    List<String>? tools = const [],
    bool preferActiveWork = true,
  }) => _workUseCase.generateOrContinue(
    tools: tools,
    preferActiveWork: preferActiveWork,
  );

  Future<void> cancelGeneration() => _workUseCase.cancelGeneration();
  Future<void> cancelTaskRun() => _workUseCase.cancelTaskRun();
  Future<void> reloadTasks() => _workUseCase.reloadTasks();
  Future<void> resumeLatestTask() => _workUseCase.resumeLatestTask();
  Future<void> loadTask(String taskId) => _workUseCase.loadTask(taskId);
  Future<void> resumeLatestProject() => _workUseCase.resumeLatestProject();
  Future<void> loadProject(String projectId) =>
      _workUseCase.loadProject(projectId);
  Future<void> runNextProjectTask() => _workUseCase.runNextProjectTask();
  Future<void> runProject() => _workUseCase.runProject();
  Future<void> runNextTaskPhase() => _workUseCase.runNextTaskPhase();
  Future<void> runTask() => _workUseCase.runTask();
  Future<void> planActiveTask({bool runAfterPlanning = false}) =>
      _workUseCase.planActiveTask(runAfterPlanning: runAfterPlanning);
  Future<void> retryTaskPhase() => _workUseCase.retryTaskPhase();
  Future<void> skipTaskPhase() => _workUseCase.skipTaskPhase();
  Future<void> stopTask() => _workUseCase.stopTask();
  Future<void> answerTaskQuestion(String answer) =>
      _workUseCase.answerTaskQuestion(answer);
  Future<void> approveTaskStep() => _workUseCase.approveTaskStep();
  Future<void> answerProjectQuestion(String answer) =>
      _workUseCase.answerProjectQuestion(answer);
  Future<void> stopProject() => _workUseCase.stopProject();
  Future<void> pauseProject() => _workUseCase.pauseProject();
  Future<void> retryProjectRecovery(String incidentId) =>
      _workUseCase.retryProjectRecovery(incidentId);
  Future<void> approveProjectPlanRevision() =>
      _workUseCase.approveProjectPlanRevision();
  Future<void> rejectProjectPlanRevision() =>
      _workUseCase.rejectProjectPlanRevision();
  Future<void> replanProject([String reason = '']) =>
      _workUseCase.replanProject(reason);

  // Presentation callbacks used by the focused work use case context. The
  // workflow implementations live on ChatWorkUseCase; these methods keep
  // the facade as the coordinator.
  bool get isDirty =>
      currentChatId != null &&
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
      activeTask == null ? null : _panelProtocol.encodeTask(activeTask!);
  String? get activeProjectJson => activeProject == null
      ? null
      : _panelProtocol.encodeProject(activeProject!);
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
  bool get _hasPendingPersistence =>
      _currentPersistenceRevision != _persistedRevision;
  Future<TaskAggregate?> _recoverTaskSnapshot(
    WorkspaceAttachment current,
    TaskAggregate? snapshot,
  ) => _workUseCase._recoverTaskSnapshot(current, snapshot);
  Future<ProjectCommandResult?> _recoverProject(
    WorkspaceAttachment current,
    ProjectAggregate? snapshot,
  ) => _workUseCase._recoverProject(current, snapshot);
  Future<TaskAggregate?> _taskForActiveProject(
    WorkspaceAttachment current,
    ProjectAggregate? project,
  ) => _workUseCase._taskForActiveProject(current, project);
  Future<void> _runTaskInternal({bool keepBusy = false}) =>
      _workUseCase._runTaskInternal(keepBusy: keepBusy);
  Future<void> _refinePromptFromCommand(ChatSlashCommand command) =>
      _workUseCase._refinePromptFromCommand(command);
  Future<void> _continueTaskFromCommand(String rawCommand) =>
      _workUseCase._continueTaskFromCommand(rawCommand);
  Future<void> _continueProjectFromCommand(String rawCommand) =>
      _workUseCase._continueProjectFromCommand(rawCommand);
  Future<void> _startProjectFromPrompt(
    String prompt, {
    required bool runAfterCreation,
  }) => _workUseCase._startProjectFromPrompt(
    prompt,
    runAfterCreation: runAfterCreation,
  );
  Future<void> _runProjectInternal({int? maxNewTasks, bool planOnly = false}) =>
      _workUseCase._runProjectInternal(
        maxNewTasks: maxNewTasks,
        planOnly: planOnly,
      );
  Future<void> _runNextTaskStepInternal({bool keepBusy = false}) =>
      _workUseCase._runNextTaskStepInternal(keepBusy: keepBusy);
  Future<void> _startTaskFromPrompt(
    String prompt, {
    required bool runFirstPhase,
  }) => _workUseCase._startTaskFromPrompt(prompt, runFirstPhase: runFirstPhase);

  bool get workspaceToolsEnabled => hasActiveWorkspace;

  List<String> get defaultToolIds => workspaceToolsEnabled
      ? _toolService.defaultToolIds(includeWorkspaceTools: true)
      : const [];

  void _disposeChangeNotifier() => super.dispose();

  ChatSessionOrchestrator({
    String? tabId,
    required this.serverManager,
    required ToolRegistryPort toolService,
    required ToolProtocolAdapter toolProtocol,
    required ChatToolExecutionPort toolExecution,
    required TaskWorkflowQueryPort taskQueries,
    required TaskSessionPort taskSessions,
    required TaskPresentationPort taskPresentation,
    required ChatPanelProtocolAdapter panelProtocol,
    required TaskWorkflowPort taskPlanning,
    required TaskWorkflowPort taskExecution,
    required TaskWorkflowPort taskRecovery,
    required ProjectWorkflowQueryPort projectQueries,
    required ProjectSessionPort projectSessions,
    required ProjectWorkflowPort projectPlanning,
    required ProjectWorkflowPort projectCommands,
    required ProjectWorkflowPort projectExecution,
    required ProjectWorkflowPort projectRecovery,
    required ChatLibraryService chatLibrary,
    required WorkspacePort workspaceService,
    required ChatRuntimePreferencesPort preferencesService,
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
    _workspaceLifecycle = ChatWorkspaceLifecycleCoordinator(
      workspaceService: _workspaceService,
      taskSessions: _taskSessions,
      projectSessions: _projectSessions,
      taskQueries: _taskQueries,
      projectQueries: _projectQueries,
      recoverProject: _recoverProject,
      recoverTask: _recoverTaskSnapshot,
      taskForActiveProject: _taskForActiveProject,
    );
    _taskCommandCoordinator = ChatTaskCommandCoordinator(
      execution: _taskExecution,
    );
    _projectCommandCoordinator = ChatProjectCommandCoordinator(
      planning: _projectPlanning,
      commands: _projectCommands,
      recovery: _projectRecovery,
    );
    final useCaseContext = _ChatUseCaseContextAdapter(this);
    _taskPlanUseCase = ChatTaskPlanUseCase(useCaseContext);
    _taskReplanUseCase = ChatTaskReplanUseCase(useCaseContext);
    _exitUseCase = ChatExitUseCase(useCaseContext);
    _sessionLifecycleUseCase = ChatSessionLifecycleUseCase(useCaseContext);
    _workUseCase = ChatWorkUseCase(useCaseContext);
    _stateMutationUseCase = ChatStateMutationUseCase(useCaseContext);
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
}
