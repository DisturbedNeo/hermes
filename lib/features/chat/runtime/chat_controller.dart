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
import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/features/task/domain/task.dart';
import 'package:hermes/shared_kernel/task_system_settings.dart';
import 'package:hermes/core/models/model_configuration_snapshot.dart';
import 'package:hermes/core/models/saved_chat.dart';
import 'package:hermes/core/models/system_prompt.dart';
import 'package:hermes/features/workspace/domain/workspace.dart';
import 'package:hermes/core/helpers/chat/assistant_ops.dart';
import 'package:hermes/core/helpers/chat/content_normaliser.dart';
import 'package:hermes/features/chat/runtime/chat_application/chat_library_service.dart';
import 'package:hermes/features/chat/runtime/chat_application/chat_session_manager.dart';
import 'package:hermes/features/chat/runtime/chat_session_host.dart';
import 'package:hermes/features/chat/runtime/chat_application/chat_command_coordinator.dart';
import 'package:hermes/features/chat/presentation/chat_view_state.dart';
import 'package:hermes/features/chat/domain/chat_state.dart';
import 'package:hermes/features/chat/runtime/chat_application/chat_tool_execution_service.dart';
import 'package:hermes/features/chat/runtime/chat_application/chat_stream.dart';
import 'package:hermes/features/chat/runtime/chat_application/message_store.dart';
import 'package:hermes/core/services/cancellation_token.dart';
import 'package:hermes/features/project/runtime/project_ports.dart';
import 'package:hermes/features/project/project_runtime_contracts.dart';
import 'package:hermes/core/services/persistence_contracts.dart';
import 'package:hermes/shared_kernel/model_output.dart';
import 'package:hermes/features/task/task_runtime_contracts.dart';
import 'package:hermes/features/task/domain/task_summary.dart';
import 'package:hermes/core/services/llama_server_manager.dart';
import 'package:hermes/shared_kernel/preferences_port.dart';
import 'package:hermes/core/helpers/chat/payload_builder.dart';
import 'package:hermes/core/services/prompt_assembler.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/core/services/workspace_service.dart';

import 'package:hermes/core/services/disposable.dart';

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
    required LlamaServerManager serverManager,
    required ToolService toolService,
    required TaskApplicationPort taskController,
    required ProjectApplicationPort projectApplication,
    required ChatLibraryService chatLibrary,
    required WorkspaceService workspaceService,
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
  LlamaServerManager get serverManager => _delegate.serverManager;
  MessageStore get messageStore => _delegate.messageStore;
  ChatStream<ChatToken> get chatStream => _delegate.chatStream;
  Bubble get systemPrompt => _delegate.systemPrompt;
  ChatState get state => _delegate.state;

  String? get currentChatId => _delegate.currentChatId;
  set currentChatId(String? value) => _delegate.currentChatId = value;

  SavedChat? get currentSavedChat => _delegate.currentSavedChat;
  set currentSavedChat(SavedChat? value) => _delegate.currentSavedChat = value;

  @override
  ModelConfigurationSnapshot? get currentModelSnapshot =>
      _delegate.currentModelSnapshot;
  set currentModelSnapshot(ModelConfigurationSnapshot? value) =>
      _delegate.currentModelSnapshot = value;

  ModelConfigurationSnapshot? get pendingModelRestore =>
      _delegate.pendingModelRestore;
  set pendingModelRestore(ModelConfigurationSnapshot? value) =>
      _delegate.pendingModelRestore = value;

  String? get pendingModelRestoreIssue => _delegate.pendingModelRestoreIssue;
  set pendingModelRestoreIssue(String? value) =>
      _delegate.pendingModelRestoreIssue = value;

  @override
  WorkspaceAttachment? get workspace => _delegate.workspace;
  set workspace(WorkspaceAttachment? value) => _delegate.workspace = value;

  SystemPromptSnapshot? get currentSystemPromptSnapshot =>
      _delegate.currentSystemPromptSnapshot;
  set currentSystemPromptSnapshot(SystemPromptSnapshot? value) =>
      _delegate.currentSystemPromptSnapshot = value;

  ExecutionMode get executionMode => _delegate.executionMode;
  set executionMode(ExecutionMode value) => _delegate.executionMode = value;

  ProjectDocument? get activeProject => _delegate.activeProject;
  set activeProject(ProjectDocument? value) => _delegate.activeProject = value;

  ProjectPersistenceDiagnostics? get activeProjectPersistenceDiagnostics =>
      _delegate.activeProjectPersistenceDiagnostics;
  set activeProjectPersistenceDiagnostics(
    ProjectPersistenceDiagnostics? value,
  ) {
    _delegate.activeProjectPersistenceDiagnostics = value;
  }

  List<ProjectSummary> get availableProjects => _delegate.availableProjects;
  set availableProjects(List<ProjectSummary> value) =>
      _delegate.availableProjects = value;

  Task? get activeTask => _delegate.activeTask;
  set activeTask(Task? value) => _delegate.activeTask = value;

  List<TaskSummary> get availableTasks => _delegate.availableTasks;
  set availableTasks(List<TaskSummary> value) =>
      _delegate.availableTasks = value;

  TaskSystemSettings get taskSystemSettings => _delegate.taskSystemSettings;
  set taskSystemSettings(TaskSystemSettings value) =>
      _delegate.taskSystemSettings = value;

  bool get taskBusy => _delegate.taskBusy;
  set taskBusy(bool value) => _delegate.taskBusy = value;

  bool get taskCancellationRequested => _delegate.taskCancellationRequested;
  set taskCancellationRequested(bool value) =>
      _delegate.taskCancellationRequested = value;

  String? get taskStatusMessage => _delegate.taskStatusMessage;
  set taskStatusMessage(String? value) => _delegate.taskStatusMessage = value;

  Object? get taskError => _delegate.taskError;
  set taskError(Object? value) => _delegate.taskError = value;

  String? get taskModelOutputTitle => _delegate.taskModelOutputTitle;
  set taskModelOutputTitle(String? value) =>
      _delegate.taskModelOutputTitle = value;

  @override
  String get taskModelOutputText => _delegate.taskModelOutputText;
  @override
  set taskModelOutputText(String value) =>
      _delegate.taskModelOutputText = value;

  @override
  String get taskModelOutputReasoning => _delegate.taskModelOutputReasoning;
  @override
  set taskModelOutputReasoning(String value) =>
      _delegate.taskModelOutputReasoning = value;

  bool get taskModelOutputActive => _delegate.taskModelOutputActive;
  set taskModelOutputActive(bool value) =>
      _delegate.taskModelOutputActive = value;

  ChatSaveFailure? get saveFailure => _delegate.saveFailure;
  set saveFailure(ChatSaveFailure? value) => _delegate.saveFailure = value;

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
