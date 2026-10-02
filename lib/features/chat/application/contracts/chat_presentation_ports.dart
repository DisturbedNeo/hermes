import 'package:hermes/core/contracts/notification.dart';
import 'package:hermes/core/contracts/conversation_store.dart';
import 'package:hermes/core/contracts/model_conversation.dart';
import 'package:hermes/features/chat/application/chat_view_state.dart';
import 'package:hermes/features/chat/application/contracts/chat_persistence.dart';
import 'package:hermes/features/chat/application/contracts/chat_workspace_contracts.dart';
import 'package:hermes/features/chat/application/contracts/message_store_port.dart';
import 'package:hermes/features/chat/application/contracts/stream_state.dart';
import 'package:hermes/features/chat/application/contracts/saved_chat.dart';
import 'package:hermes/features/chat/application/contracts/system_prompt.dart';
import 'package:hermes/features/chat/domain/chat_panel_read_models.dart';
import 'package:hermes/features/model/application/model_configuration.dart';
import 'package:hermes/features/model/application/model_server_port.dart';
import 'package:hermes/features/persistence/application/persistence_contracts.dart';
import 'package:hermes/core/contracts/execution_settings.dart';
import 'package:hermes/features/project/application/contracts/project_commands.dart';
import 'package:hermes/features/task/application/contracts/task_commands.dart';
import 'package:hermes/features/task/application/contracts/task_summary.dart';
import 'package:hermes/features/workspace/application/workspace.dart';

/// Presentation-safe view of the mutable message collection.
abstract interface class ChatPresentationMessageStorePort
    implements MessageStorePort, NotificationPort {
  int get displayRevision;
  Bubble? messageById(String id);
  Bubble get first;
  Bubble get last;
  bool get isEmpty;
  bool removeById(String id);
  bool removeFromId(String id);
}

/// Presentation-safe stream state capability.
abstract interface class ChatStreamPresentationPort
    implements NotificationPort {
  StreamState get state;
  bool get isStreaming;
}

/// Focused application surface for one chat tab. It intentionally exposes
/// projections and commands, never the runtime session implementation.
abstract interface class ChatTabPresentationPort implements NotificationPort {
  String get tabId;
  ChatPresentationMessageStorePort get messageStore;
  ChatStreamPresentationPort get chatStream;
  ChatViewState get viewState;
  ActiveModelSessionPort get activeModelSession;
  ModelServerLifecyclePort get serverLifecycle;

  String? get currentChatId;
  ModelConfigurationSnapshot? get currentModelSnapshot;
  ModelConfigurationSnapshot? get pendingModelRestore;
  String? get pendingModelRestoreIssue;
  SystemPromptSnapshot? get currentSystemPromptSnapshot;
  WorkspaceAttachment? get workspace;
  ExecutionMode get executionMode;
  String get executionModeLabel;
  ProjectPanelReadModel? get activeProject;
  ProjectPersistenceDiagnostics? get activeProjectPersistenceDiagnostics;
  List<ProjectSummary> get availableProjects;
  TaskPanelReadModel? get activeTask;
  List<TaskSummary> get availableTasks;
  TaskSystemSettings get taskSystemSettings;
  bool get taskBusy;
  bool get taskCancellationRequested;
  String? get taskStatusMessage;
  Object? get taskError;
  String? get taskModelOutputTitle;
  String get taskModelOutputText;
  String get taskModelOutputReasoning;
  bool get taskModelOutputActive;
  ChatSaveFailure? get saveFailure;
  int get historyRevision;
  bool get isDirty;
  bool get isUnsavedNonEmpty;
  bool get isSystemPromptLocked;
  bool get hasActiveWorkspace;
  bool get workspaceToolsEnabled;
  String? get activeTaskJson;
  String? get activeProjectJson;
  List<String> get defaultToolIds;
  String get displayTitle;

  Future<void> newChat({SystemPromptSnapshot? systemPromptSnapshot});
  Future<bool> openChat(String id);
  Future<SavedChat> saveCurrentChat({String? title});
  Future<SavedChat> retrySave();
  Future<void> deleteSavedChat(String chatId);
  Future<void> resetIfCurrentSavedChatDeleted(String chatId);
  Future<void> flushCurrentChat();
  void updateCurrentModelSnapshot(ModelConfigurationSnapshot snapshot);
  Future<void> restorePendingModel();
  void dismissPendingModelRestore();
  void updateSystemPromptSnapshot(SystemPromptSnapshot snapshot);
  Future<void> refreshModelRestorePrompt();
  void insertMessage(String text, MessageRole role);
  Future<void> attachWorkspace(String folderPath);
  Future<void> detachWorkspace();
  void updateCommandExecutionApproval(bool approved);
  void updateExecutionMode(ExecutionMode mode);
  Future<void> send(String text, {List<String>? tools});
  Future<void> generateOrContinue({List<String>? tools, bool preferActiveWork});
  Future<void> cancelGeneration();
  Future<void> cancelTaskRun();
  Future<void> reloadTasks();
  Future<void> resumeLatestTask();
  Future<void> loadTask(String taskId);
  Future<void> resumeLatestProject();
  Future<void> loadProject(String projectId);
  Future<void> runNextProjectTask();
  Future<void> runProject();
  Future<void> runNextTaskPhase();
  Future<void> runTask();
  Future<void> planActiveTask({bool runAfterPlanning});
  Future<void> retryTaskPhase();
  Future<void> skipTaskPhase();
  Future<void> stopTask();
  Future<void> answerTaskQuestion(String answer);
  Future<void> approveTaskStep();
  Future<void> answerProjectQuestion(String answer);
  Future<void> stopProject();
  Future<void> pauseProject();
  Future<void> retryProjectRecovery(String incidentId);
  Future<void> approveProjectPlanRevision();
  Future<void> rejectProjectPlanRevision();
  Future<void> replanProject([String reason]);
  Future<void> replanRemainingTask();
  Future<void> updateTaskTaskBrief(TaskPlanUpdateCommand command);
  Future<void> updateTaskSpec(TaskPlanUpdateCommand command);
  Future<void> updateTaskPlan(TaskPlanUpdateCommand command);
  Future<void> updateProjectPlan(ProjectUpdateCommand command);
  Future<String> readTaskArtifact(String artifactPath);
  Future<void> quiesceForExit({Duration timeout});
}

/// Workspace-level presentation capability. Concrete tab/controller types are
/// deliberately absent from this surface.
abstract interface class ChatWorkspacePresentationPort
    implements NotificationPort {
  List<ChatTabPresentationPort> get presentationTabs;
  ChatTabPresentationPort? get presentationActiveChat;
  String? get activeTabId;

  ChatTabPresentationPort newTab({SystemPromptSnapshot? systemPromptSnapshot});
  Future<void> selectTab(String tabId);
  bool isSavedChatOpen(String chatId);
  Future<bool> openSavedChat(String chatId, {required OpenChatTarget target});
  Future<void> saveCurrentChat({String? title});
  Future<void> deleteSavedChat(String chatId);
  Future<void> saveAndCloseTab(String tabId);
  Future<void> closeTab(String tabId);
  Future<void> loadPromptPresetIntoActiveChat(
    PromptPreset preset, {
    List<String> selectedOptionalModuleIds,
  });
  Future<void> prepareForExit(NewChatExitPolicy newChatPolicy);
}

/// Capability surface consumed by the saved-chat presentation widgets.
abstract interface class ChatLibraryPresentationPort
    implements NotificationPort {
  Future<List<SavedChat>> listChats();
  Future<List<SavedChat>> searchChats(String query);
  Future<void> renameChat(String chatId, String title);
}

/// Capability surface consumed by the prompt-library presentation widgets.
abstract interface class SystemPromptLibraryPresentationPort
    implements NotificationPort {
  Future<List<PromptPreset>> listPresets();
  Future<List<PromptPreset>> searchPresets(String query);
  Future<PromptPreset> createPreset({
    required String name,
    List<String> baseModuleIds,
    List<String> optionalModuleIds,
    String customInstructions,
  });
  Future<PromptPreset> updatePreset({
    required String id,
    required String name,
    required List<String> baseModuleIds,
    required List<String> optionalModuleIds,
    required String customInstructions,
  });
  Future<PromptPreset> duplicatePreset(String id);
  Future<void> deletePreset(String id);

  Future<List<PromptModule>> listModules();
  Future<List<PromptModule>> searchModules(String query);
  Future<PromptModule> createModule({
    required String name,
    required String category,
    required String content,
    required int priority,
    List<String> requiredModuleIds,
    List<String> conflictingModuleIds,
  });
  Future<PromptModule> updateModule({
    required String id,
    required String name,
    required String category,
    required String content,
    required int priority,
    required List<String> requiredModuleIds,
    required List<String> conflictingModuleIds,
  });
  Future<PromptModule> duplicateModule(String id);
  Future<void> deleteModule(String id);

  Future<PromptAssemblyResult> assemblePreset(
    PromptPreset preset, {
    List<String> selectedOptionalModuleIds,
    WorkspaceAttachment? workspace,
    String? currentUserRequest,
  });

  Future<SystemPromptSnapshot> snapshotForPreset(
    PromptPreset preset, {
    List<String> selectedOptionalModuleIds,
    WorkspaceAttachment? workspace,
    String? currentUserRequest,
  });
}
