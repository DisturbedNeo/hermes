import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hermes/features/chat/application/contracts/message_role.dart';
import 'package:hermes/features/chat/application/contracts/bubble.dart';
import 'package:hermes/features/chat/application/contracts/chat_token.dart';
import 'package:hermes/features/chat/application/contracts/chat_persistence.dart';
import 'package:hermes/features/project/application/contracts/project_snapshot_models.dart';
import 'package:hermes/features/task/application/contracts/task_snapshot_models.dart';
import 'package:hermes/core/contracts/execution_settings.dart';
import 'package:hermes/features/model/application/model_configuration.dart';
import 'package:hermes/features/chat/application/contracts/saved_chat.dart';
import 'package:hermes/features/chat/application/contracts/system_prompt.dart';
import 'package:hermes/features/workspace/application/workspace.dart';
import 'package:hermes/features/chat/application/chat_library_service.dart';
import 'package:hermes/features/chat/runtime/chat_session_host.dart';
import 'package:hermes/features/chat/runtime/chat_application/chat_command_coordinator.dart';
import 'package:hermes/features/chat/application/chat_view_state.dart';
import 'package:hermes/features/chat/domain/chat_panel_read_models.dart';
import 'package:hermes/features/chat/domain/chat_state.dart';
import 'package:hermes/features/chat/runtime/chat_application/chat_tool_execution_service.dart';
import 'package:hermes/features/chat/runtime/chat_application/chat_stream.dart';
import 'package:hermes/features/chat/runtime/chat_application/message_store.dart';
import 'package:hermes/features/project/application/project_application/project_ports.dart';
import 'package:hermes/features/persistence/application/persistence_contracts.dart';
import 'package:hermes/features/task/application/task_application/task_ports.dart';
import 'package:hermes/features/task/application/contracts/task_commands.dart';
import 'package:hermes/features/project/application/contracts/project_commands.dart';
import 'package:hermes/features/task/application/contracts/task_summary.dart';
import 'package:hermes/features/model/application/model_server_port.dart';
import 'package:hermes/features/settings/application/preferences_port.dart';
import 'package:hermes/features/tools/application/tool_contracts.dart';
import 'package:hermes/features/tools/application/tool_protocol_adapter.dart';
import 'package:hermes/features/workspace/application/workspace_ports.dart';

import 'package:hermes/core/disposable.dart';

import 'package:hermes/features/chat/runtime/chat_session_runtime.dart';
import 'package:hermes/features/chat/infrastructure/chat_panel_protocol_adapter.dart';

class ChatRuntimeController extends ChangeNotifier
    implements Disposable, ChatSessionHost {
  static const String defaultSystemPromptName =
      ChatSessionRuntime.defaultSystemPromptName;
  static const String defaultSystemPromptText =
      ChatSessionRuntime.defaultSystemPromptText;

  ChatRuntimeController({
    String? tabId,
    required ModelServerPort serverManager,
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
    required ChatRuntimePreferencesPort preferencesService,
    ChatCommandCoordinator? commandCoordinator,
    SystemPromptSnapshot? initialSystemPromptSnapshot,
  }) : _delegate = ChatSessionRuntime(
         tabId: tabId,
         serverManager: serverManager,
         toolService: toolService,
         toolProtocol: toolProtocol,
         toolExecution: toolExecution,
         taskQueries: taskQueries,
         taskSessions: taskSessions,
         taskPresentation: taskPresentation,
         panelProtocol: panelProtocol,
         taskPlanning: taskPlanning,
         taskExecution: taskExecution,
         taskRecovery: taskRecovery,
         projectQueries: projectQueries,
         projectSessions: projectSessions,
         projectPlanning: projectPlanning,
         projectCommands: projectCommands,
         projectExecution: projectExecution,
         projectRecovery: projectRecovery,
         chatLibrary: chatLibrary,
         workspaceService: workspaceService,
         preferencesService: preferencesService,
         commandCoordinator: commandCoordinator,
         initialSystemPromptSnapshot: initialSystemPromptSnapshot,
       ) {
    _delegate.addListener(_forwardDelegateNotification);
  }

  final ChatSessionRuntime _delegate;
  bool _disposed = false;
  Future<void>? _disposeFuture;

  String get tabId => _delegate.tabId;
  ModelServerPort get serverManager => _delegate.serverManager;
  MessageStore get messageStore => _delegate.messageStore;
  ChatStream<ChatToken> get chatStream => _delegate.chatStream;
  Bubble get systemPrompt => _delegate.systemPrompt;
  ChatState get state => _delegate.state;

  String? get currentChatId => _delegate.currentChatId;

  SavedChat? get currentSavedChat => _delegate.currentSavedChat;

  @override
  ModelConfigurationSnapshot? get currentModelSnapshot =>
      _delegate.currentModelSnapshot;

  ModelConfigurationSnapshot? get pendingModelRestore =>
      _delegate.pendingModelRestore;

  String? get pendingModelRestoreIssue => _delegate.pendingModelRestoreIssue;

  @override
  WorkspaceAttachment? get workspace => _delegate.workspace;
  void dispatchWorkspace(WorkspaceAttachment? value) =>
      _delegate.dispatchWorkspace(value);

  SystemPromptSnapshot? get currentSystemPromptSnapshot =>
      _delegate.currentSystemPromptSnapshot;

  ExecutionMode get executionMode => _delegate.executionMode;

  String get executionModeLabel => switch (executionMode) {
    ExecutionMode.chat => 'Chat',
    ExecutionMode.refine => 'Refine',
    ExecutionMode.task => 'TaskAggregate',
    ExecutionMode.project => 'Project',
    ExecutionMode.continueTask => 'Continue TaskAggregate',
  };

  ProjectPanelReadModel? get activeProject => _delegate.state.activeProject;
  void dispatchActiveProject(ProjectAggregate? value) =>
      _delegate.dispatchActiveProject(value);

  ProjectPersistenceDiagnostics? get activeProjectPersistenceDiagnostics =>
      _delegate.activeProjectPersistenceDiagnostics;
  void dispatchActiveProjectPersistenceDiagnostics(
    ProjectPersistenceDiagnostics? value,
  ) {
    _delegate.dispatchActiveProjectPersistenceDiagnostics(value);
  }

  List<ProjectSummary> get availableProjects => _delegate.availableProjects;

  TaskPanelReadModel? get activeTask => _delegate.state.activeTask;
  void dispatchActiveTask(Task? value) => _delegate.dispatchActiveTask(value);

  List<TaskSummary> get availableTasks => _delegate.availableTasks;

  TaskSystemSettings get taskSystemSettings => _delegate.taskSystemSettings;

  bool get taskBusy => _delegate.taskBusy;

  bool get taskCancellationRequested => _delegate.taskCancellationRequested;

  String? get taskStatusMessage => _delegate.taskStatusMessage;

  Object? get taskError => _delegate.taskError;

  String? get taskModelOutputTitle => _delegate.taskModelOutputTitle;

  @override
  String get taskModelOutputText => _delegate.taskModelOutputText;
  void dispatchTaskModelOutputText(String value) =>
      _delegate.dispatchTaskModelOutputText(value);
  void appendTaskModelOutputText(String value) =>
      _delegate.appendTaskModelOutputText(value);

  @override
  String get taskModelOutputReasoning => _delegate.taskModelOutputReasoning;
  void dispatchTaskModelOutputReasoning(String value) =>
      _delegate.dispatchTaskModelOutputReasoning(value);
  void appendTaskModelOutputReasoning(String value) =>
      _delegate.appendTaskModelOutputReasoning(value);

  bool get taskModelOutputActive => _delegate.taskModelOutputActive;

  ChatSaveFailure? get saveFailure => _delegate.saveFailure;

  int get historyRevision => _delegate.historyRevision;
  ChatViewState get viewState => _delegate.viewState;

  bool get isDirty => _delegate.isDirty;
  bool get hasMeaningfulContent => _delegate.hasMeaningfulContent;
  bool get isUnsavedNonEmpty => _delegate.isUnsavedNonEmpty;
  bool get isSystemPromptLocked => _delegate.isSystemPromptLocked;
  bool get hasActiveWorkspace => _delegate.hasActiveWorkspace;

  @override
  bool get workspaceToolsEnabled => _delegate.workspaceToolsEnabled;

  String? get activeTaskJson => _delegate.activeTaskJson;
  String? get activeProjectJson => _delegate.activeProjectJson;

  @override
  List<String> get defaultToolIds => _delegate.defaultToolIds;

  String get displayTitle => _delegate.displayTitle;

  @override
  int? get sessionDiagnosticsContextLimit =>
      _delegate.sessionDiagnosticsContextLimit;

  @override
  String? sessionTaskModelOutputLabel() =>
      _delegate.sessionTaskModelOutputLabel();

  @override
  void updateSessionTaskModelOutputLabel(String? value) =>
      _delegate.updateSessionTaskModelOutputLabel(value);

  @override
  String? sessionTaskModelOutputTextSection() =>
      _delegate.sessionTaskModelOutputTextSection();

  @override
  void updateSessionTaskModelOutputTextSection(String? value) =>
      _delegate.updateSessionTaskModelOutputTextSection(value);

  @override
  String? sessionTaskModelOutputReasoningLabel() =>
      _delegate.sessionTaskModelOutputReasoningLabel();

  @override
  void updateSessionTaskModelOutputReasoningLabel(String? value) =>
      _delegate.updateSessionTaskModelOutputReasoningLabel(value);

  @override
  String buildSystemPrompt({String? currentUserRequest}) =>
      _delegate.buildSystemPrompt(currentUserRequest: currentUserRequest);

  @override
  void markWorkspaceChanged() => _delegate.markWorkspaceChanged();

  @override
  void sessionNotifyListeners() => _delegate.sessionNotifyListeners();

  @override
  void requestContextEstimateUpdate({bool immediate = false}) =>
      _delegate.requestContextEstimateUpdate(immediate: immediate);

  Future<void> newChat({SystemPromptSnapshot? systemPromptSnapshot}) =>
      _delegate.newChat(systemPromptSnapshot: systemPromptSnapshot);

  Future<bool> openChat(String id) => _delegate.openChat(id);

  Future<SavedChat> saveCurrentChat({String? title}) =>
      _delegate.saveCurrentChat(title: title);

  Future<SavedChat> retrySave() => _delegate.retrySave();

  Future<void> deleteSavedChat(String chatId) =>
      _delegate.deleteSavedChat(chatId);

  Future<void> resetIfCurrentSavedChatDeleted(String chatId) =>
      _delegate.resetIfCurrentSavedChatDeleted(chatId);

  Future<void> flushCurrentChat() => _delegate.flushCurrentChat();

  void updateCurrentModelSnapshot(ModelConfigurationSnapshot snapshot) =>
      _delegate.updateCurrentModelSnapshot(snapshot);

  Future<void> restorePendingModel() => _delegate.restorePendingModel();

  void dismissPendingModelRestore() => _delegate.dismissPendingModelRestore();

  void updateSystemPromptSnapshot(SystemPromptSnapshot snapshot) =>
      _delegate.updateSystemPromptSnapshot(snapshot);

  @visibleForTesting
  String buildSystemPromptForTesting({
    String? currentUserRequest,
    List<String> additionalModuleIds = const [],
  }) => _delegate.buildSystemPromptForTesting(
    currentUserRequest: currentUserRequest,
    additionalModuleIds: additionalModuleIds,
  );

  Future<void> refreshModelRestorePrompt() =>
      _delegate.refreshModelRestorePrompt();

  void insertMessage(String text, MessageRole role) =>
      _delegate.insertMessage(text, role);

  Future<void> attachWorkspace(String folderPath) =>
      _delegate.attachWorkspace(folderPath);

  Future<void> detachWorkspace() => _delegate.detachWorkspace();

  void updateCommandExecutionApproval(bool approved) =>
      _delegate.updateCommandExecutionApproval(approved);

  void updateExecutionMode(ExecutionMode mode) =>
      _delegate.updateExecutionMode(mode);

  Future<void> send(String text, {List<String>? tools = const []}) =>
      _delegate.send(text, tools: tools);

  Future<void> generateOrContinue({
    List<String>? tools = const [],
    bool preferActiveWork = true,
  }) => _delegate.generateOrContinue(
    tools: tools,
    preferActiveWork: preferActiveWork,
  );

  Future<void> cancelGeneration() => _delegate.cancelGeneration();

  Future<void> cancelTaskRun() => _delegate.cancelTaskRun();

  Future<void> reloadTasks() => _delegate.reloadTasks();

  Future<void> resumeLatestTask() => _delegate.resumeLatestTask();

  Future<void> loadTask(String taskId) => _delegate.loadTask(taskId);

  Future<void> resumeLatestProject() => _delegate.resumeLatestProject();

  Future<void> loadProject(String projectId) =>
      _delegate.loadProject(projectId);

  Future<void> runNextProjectTask() => _delegate.runNextProjectTask();

  Future<void> runProject() => _delegate.runProject();

  Future<void> runNextTaskPhase() => _delegate.runNextTaskPhase();

  Future<void> runTask() => _delegate.runTask();

  Future<void> planActiveTask({bool runAfterPlanning = false}) =>
      _delegate.planActiveTask(runAfterPlanning: runAfterPlanning);

  Future<void> retryTaskPhase() => _delegate.retryTaskPhase();

  Future<void> skipTaskPhase() => _delegate.skipTaskPhase();

  Future<void> stopTask() => _delegate.stopTask();

  Future<void> answerTaskQuestion(String answer) =>
      _delegate.answerTaskQuestion(answer);

  Future<void> approveTaskStep() => _delegate.approveTaskStep();

  Future<void> answerProjectQuestion(String answer) =>
      _delegate.answerProjectQuestion(answer);

  Future<void> stopProject() => _delegate.stopProject();

  Future<void> pauseProject() => _delegate.pauseProject();

  Future<void> retryProjectRecovery(String incidentId) =>
      _delegate.retryProjectRecovery(incidentId);

  Future<void> approveProjectPlanRevision() =>
      _delegate.approveProjectPlanRevision();

  Future<void> rejectProjectPlanRevision() =>
      _delegate.rejectProjectPlanRevision();

  Future<void> replanProject([String reason = '']) =>
      _delegate.replanProject(reason);

  Future<void> replanRemainingTask() => _delegate.replanRemainingTask();

  Future<void> updateTaskTaskBrief(TaskPlanUpdateCommand command) =>
      _delegate.updateTaskTaskBrief(command);

  Future<void> updateTaskSpec(TaskPlanUpdateCommand command) =>
      _delegate.updateTaskSpec(command);

  Future<void> updateTaskPlan(TaskPlanUpdateCommand command) =>
      _delegate.updateTaskPlan(command);

  Future<void> updateProjectPlan(ProjectUpdateCommand command) =>
      _delegate.updateProjectPlan(command);

  Future<String> readTaskArtifact(String artifactPath) =>
      _delegate.readTaskArtifact(artifactPath);

  Future<void> quiesceForExit({
    Duration timeout = const Duration(seconds: 5),
  }) => _delegate.quiesceForExit(timeout: timeout);

  void _forwardDelegateNotification() {
    if (!_disposed) notifyListeners();
  }

  @override
  // ignore: must_call_super, super.dispose is called after async cleanup.
  Future<void> dispose() {
    final existing = _disposeFuture;
    if (existing != null) return existing;
    late final Future<void> operation;
    operation = _disposeDelegate(saveChanges: true).whenComplete(() {
      if (!_disposed && identical(_disposeFuture, operation)) {
        _disposeFuture = null;
      }
    });
    _disposeFuture = operation;
    return operation;
  }

  Future<void> disposeWithoutSaving() {
    final existing = _disposeFuture;
    if (existing != null) return existing;
    late final Future<void> operation;
    operation = _disposeDelegate(saveChanges: false).whenComplete(() {
      if (!_disposed && identical(_disposeFuture, operation)) {
        _disposeFuture = null;
      }
    });
    _disposeFuture = operation;
    return operation;
  }

  Future<void> _disposeDelegate({required bool saveChanges}) async {
    if (saveChanges) {
      await _delegate.disposeAsync();
    } else {
      await _delegate.disposeWithoutSavingAsync();
    }
    _disposed = true;
    _delegate.removeListener(_forwardDelegateNotification);
    super.dispose();
  }
}
