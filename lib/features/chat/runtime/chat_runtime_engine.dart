import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hermes/shared_kernel/message_role.dart';
import 'package:hermes/shared_kernel/context_estimator.dart';
import 'package:hermes/shared_kernel/throttled_scheduler.dart';
import 'package:hermes/shared_kernel/uuid.dart';
import 'package:hermes/shared_kernel/bubble.dart';
import 'package:hermes/shared_kernel/chat_token.dart';
import 'package:hermes/shared_kernel/chat_persistence.dart';
import 'package:hermes/shared_kernel/project.dart';
import 'package:hermes/shared_kernel/task.dart';
import 'package:hermes/shared_kernel/task_system_settings.dart';
import 'package:hermes/shared_kernel/model_configuration.dart';
import 'package:hermes/shared_kernel/saved_chat.dart';
import 'package:hermes/shared_kernel/system_prompt.dart';
import 'package:hermes/shared_kernel/workspace.dart';
import 'package:hermes/shared_kernel/assistant_ops.dart';
import 'package:hermes/shared_kernel/content_normaliser.dart';
import 'package:hermes/features/chat/application/chat_library_service.dart';
import 'package:hermes/features/chat/runtime/chat_application/chat_session_manager.dart';
import 'package:hermes/features/chat/runtime/chat_session_host.dart';
import 'package:hermes/features/chat/runtime/chat_application/chat_command_coordinator.dart';
import 'package:hermes/features/chat/application/chat_view_state.dart';
import 'package:hermes/features/chat/domain/chat_state.dart';
import 'package:hermes/features/chat/runtime/chat_application/chat_tool_execution_service.dart';
import 'package:hermes/features/chat/runtime/chat_application/chat_stream.dart';
import 'package:hermes/features/chat/runtime/chat_application/message_store.dart';
import 'package:hermes/shared_kernel/cancellation.dart';
import 'package:hermes/features/project/application/project_application/project_ports.dart';
import 'package:hermes/shared_kernel/project_runtime_contracts.dart';
import 'package:hermes/shared_kernel/persistence_contracts.dart';
import 'package:hermes/shared_kernel/model_output.dart';
import 'package:hermes/features/task/application/task_application/task_ports.dart';
import 'package:hermes/shared_kernel/task_summary.dart';
import 'package:hermes/features/model/application/model_server_port.dart';
import 'package:hermes/shared_kernel/preferences_port.dart';
import 'package:hermes/shared_kernel/payload_builder.dart';
import 'package:hermes/shared_kernel/prompt_assembler.dart';
import 'package:hermes/shared_kernel/tool_contracts.dart';
import 'package:hermes/shared_kernel/workspace_ports.dart';

import 'package:hermes/shared_kernel/disposable.dart';

part 'chat_application_context.dart';

part 'chat_session_operations.dart';

part 'chat_work_operations.dart';

part 'chat_persistence_operations.dart';

part 'chat_prompt_operations.dart';

part 'chat_lifecycle_operations.dart';

part 'chat_operation_models.dart';

class ChatRuntimeController extends ChangeNotifier
    implements Disposable, ChatSessionHost {
  static const String defaultSystemPromptName =
      _ChatApplicationContext.defaultSystemPromptName;
  static const String defaultSystemPromptText =
      _ChatApplicationContext.defaultSystemPromptText;

  ChatRuntimeController({
    String? tabId,
    required ModelServerPort serverManager,
    required ToolRegistryPort toolService,
    required TaskChatPort taskController,
    required ProjectChatPort projectApplication,
    required ChatLibraryService chatLibrary,
    required WorkspacePort workspaceService,
    required PreferencesPort preferencesService,
    ChatCommandCoordinator? commandCoordinator,
    ChatToolExecutionPort? toolExecution,
    SystemPromptSnapshot? initialSystemPromptSnapshot,
  }) : _delegate = _ChatApplicationContext(
         tabId: tabId,
         serverManager: serverManager,
         toolService: toolService,
         taskController: taskController,
         projectApplication: projectApplication,
         chatLibrary: chatLibrary,
         workspaceService: workspaceService,
         preferencesService: preferencesService,
         commandCoordinator: commandCoordinator,
         toolExecution: toolExecution,
         initialSystemPromptSnapshot: initialSystemPromptSnapshot,
       ) {
    _delegate.addListener(_forwardDelegateNotification);
  }

  final _ChatApplicationContext _delegate;
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
  void setWorkspace(WorkspaceAttachment? value) => _delegate.setWorkspace(value);

  SystemPromptSnapshot? get currentSystemPromptSnapshot =>
      _delegate.currentSystemPromptSnapshot;

  ExecutionMode get executionMode => _delegate.executionMode;

  ProjectDocument? get activeProject => _delegate.activeProject;
  void setActiveProject(ProjectDocument? value) => _delegate.setActiveProject(value);

  ProjectPersistenceDiagnostics? get activeProjectPersistenceDiagnostics =>
      _delegate.activeProjectPersistenceDiagnostics;
  void setActiveProjectPersistenceDiagnostics(
    ProjectPersistenceDiagnostics? value,
  ) {
    _delegate.setActiveProjectPersistenceDiagnostics(value);
  }

  List<ProjectSummary> get availableProjects => _delegate.availableProjects;

  Task? get activeTask => _delegate.activeTask;
  void setActiveTask(Task? value) => _delegate.setActiveTask(value);

  List<TaskSummary> get availableTasks => _delegate.availableTasks;

  TaskSystemSettings get taskSystemSettings => _delegate.taskSystemSettings;

  bool get taskBusy => _delegate.taskBusy;

  bool get taskCancellationRequested => _delegate.taskCancellationRequested;

  String? get taskStatusMessage => _delegate.taskStatusMessage;

  Object? get taskError => _delegate.taskError;

  String? get taskModelOutputTitle => _delegate.taskModelOutputTitle;

  @override
  String get taskModelOutputText => _delegate.taskModelOutputText;
  void setTaskModelOutputText(String value) =>
      _delegate.setTaskModelOutputText(value);
  void appendTaskModelOutputText(String value) =>
      _delegate.appendTaskModelOutputText(value);

  @override
  String get taskModelOutputReasoning => _delegate.taskModelOutputReasoning;
  void setTaskModelOutputReasoning(String value) =>
      _delegate.setTaskModelOutputReasoning(value);
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
  void setSessionTaskModelOutputLabel(String? value) =>
      _delegate.setSessionTaskModelOutputLabel(value);

  @override
  String? sessionTaskModelOutputTextSection() =>
      _delegate.sessionTaskModelOutputTextSection();

  @override
  void setSessionTaskModelOutputTextSection(String? value) =>
      _delegate.setSessionTaskModelOutputTextSection(value);

  @override
  String? sessionTaskModelOutputReasoningLabel() =>
      _delegate.sessionTaskModelOutputReasoningLabel();

  @override
  void setSessionTaskModelOutputReasoningLabel(String? value) =>
      _delegate.setSessionTaskModelOutputReasoningLabel(value);

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

  void setCurrentModelSnapshot(ModelConfigurationSnapshot snapshot) =>
      _delegate.setCurrentModelSnapshot(snapshot);

  Future<void> restorePendingModel() => _delegate.restorePendingModel();

  void dismissPendingModelRestore() => _delegate.dismissPendingModelRestore();

  void setSystemPromptSnapshot(SystemPromptSnapshot snapshot) =>
      _delegate.setSystemPromptSnapshot(snapshot);

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

  void setCommandExecutionApproved(bool approved) =>
      _delegate.setCommandExecutionApproved(approved);

  void setExecutionMode(ExecutionMode mode) => _delegate.setExecutionMode(mode);

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

  Future<void> updateTaskTaskBrief(String rawJson) =>
      _delegate.updateTaskTaskBrief(rawJson);

  Future<void> updateTaskSpec(String rawJson) =>
      _delegate.updateTaskSpec(rawJson);

  Future<void> updateTaskPlan(String rawJson) =>
      _delegate.updateTaskPlan(rawJson);

  Future<void> updateProjectPlan(String rawJson) =>
      _delegate.updateProjectPlan(rawJson);

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
