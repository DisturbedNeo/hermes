import 'package:hermes/features/chat/application/contracts/bubble.dart';
import 'package:hermes/features/chat/application/contracts/chat_persistence.dart';
import 'package:hermes/features/model/application/model_configuration.dart';
import 'package:hermes/features/chat/application/contracts/saved_chat.dart';
import 'package:hermes/features/chat/application/contracts/system_prompt.dart';
import 'package:hermes/features/chat/domain/chat_panel_read_models.dart';
import 'package:hermes/features/chat/domain/chat_state_slices.dart';
import 'package:hermes/features/persistence/application/persistence_contracts.dart';
import 'package:hermes/features/task/application/contracts/task_summary.dart';
import 'package:hermes/features/task/application/contracts/task_system_settings.dart';
import 'package:hermes/features/workspace/application/workspace.dart';

/// Authoritative immutable state for one chat session.
///
/// Controllers may keep effect handles privately, but every user-visible
/// value is represented here. The reducer is the only place where a state
/// transition is constructed, which prevents impossible combinations such as
/// an idle task with an active cancellation request.
class ChatState {
  ChatState({
    required this.tabId,
    required List<Bubble> messages,
    required int historyRevision,
    String? currentChatId,
    SavedChat? currentSavedChat,
    ModelConfigurationSnapshot? currentModelSnapshot,
    ModelConfigurationSnapshot? pendingModelRestore,
    String? pendingModelRestoreIssue,
    WorkspaceAttachment? workspace,
    SystemPromptSnapshot? systemPrompt,
    ExecutionMode executionMode = ExecutionMode.chat,
    ProjectPanelReadModel? activeProject,
    ProjectPersistenceDiagnostics? activeProjectPersistenceDiagnostics,
    List<ProjectSummary> availableProjects = const [],
    TaskPanelReadModel? activeTask,
    List<TaskSummary> availableTasks = const [],
    TaskSystemSettings taskSystemSettings = const TaskSystemSettings(),
    bool taskBusy = false,
    bool taskCancellationRequested = false,
    String? taskStatusMessage,
    Object? taskError,
    String? taskModelOutputTitle,
    String taskModelOutputText = '',
    String taskModelOutputReasoning = '',
    bool taskModelOutputActive = false,
    ChatSaveFailure? saveFailure,
  }) : assert(!taskCancellationRequested || taskBusy),
       conversation = ChatConversationState(
         messages: messages,
         historyRevision: historyRevision,
       ),
       modelSession = ChatModelSessionState(
         currentSnapshot: currentModelSnapshot,
         pendingRestore: pendingModelRestore,
         pendingRestoreIssue: pendingModelRestoreIssue,
       ),
       projectPanel = ChatProjectPanelState(
         activeProject: activeProject,
         persistenceDiagnostics: activeProjectPersistenceDiagnostics,
         availableProjects: availableProjects,
       ),
       taskPanel = ChatTaskPanelState(
         activeTask: activeTask,
         availableTasks: availableTasks,
         settings: taskSystemSettings,
       ),
       persistence = ChatPersistenceState(
         currentChatId: currentChatId,
         currentSavedChat: currentSavedChat,
         saveFailure: saveFailure,
       ),
       operationStatus = ChatTransientOperationState(
         taskBusy: taskBusy,
         taskCancellationRequested: taskCancellationRequested,
         taskStatusMessage: taskStatusMessage,
         taskError: taskError,
         taskModelOutputTitle: taskModelOutputTitle,
         taskModelOutputText: taskModelOutputText,
         taskModelOutputReasoning: taskModelOutputReasoning,
         taskModelOutputActive: taskModelOutputActive,
       ),
       context = ChatContextState(
         workspace: workspace,
         systemPrompt: systemPrompt,
         executionMode: executionMode,
       );

  factory ChatState.initial(String tabId, Bubble systemPrompt) =>
      ChatState(tabId: tabId, messages: [systemPrompt], historyRevision: 0);

  final String tabId;
  final ChatConversationState conversation;
  final ChatModelSessionState modelSession;
  final ChatProjectPanelState projectPanel;
  final ChatTaskPanelState taskPanel;
  final ChatPersistenceState persistence;
  final ChatTransientOperationState operationStatus;
  final ChatContextState context;

  List<Bubble> get messages => conversation.messages;
  int get historyRevision => conversation.historyRevision;
  String? get currentChatId => persistence.currentChatId;
  SavedChat? get currentSavedChat => persistence.currentSavedChat;
  ModelConfigurationSnapshot? get currentModelSnapshot =>
      modelSession.currentSnapshot;
  ModelConfigurationSnapshot? get pendingModelRestore =>
      modelSession.pendingRestore;
  String? get pendingModelRestoreIssue => modelSession.pendingRestoreIssue;
  WorkspaceAttachment? get workspace => context.workspace;
  SystemPromptSnapshot? get systemPrompt => context.systemPrompt;
  ExecutionMode get executionMode => context.executionMode;
  ProjectPanelReadModel? get activeProject => projectPanel.activeProject;
  ProjectPersistenceDiagnostics? get activeProjectPersistenceDiagnostics =>
      projectPanel.persistenceDiagnostics;
  List<ProjectSummary> get availableProjects => projectPanel.availableProjects;
  TaskPanelReadModel? get activeTask => taskPanel.activeTask;
  List<TaskSummary> get availableTasks => taskPanel.availableTasks;
  TaskSystemSettings get taskSystemSettings => taskPanel.settings;
  bool get taskBusy => operationStatus.taskBusy;
  bool get taskCancellationRequested =>
      operationStatus.taskCancellationRequested;
  String? get taskStatusMessage => operationStatus.taskStatusMessage;
  Object? get taskError => operationStatus.taskError;
  String? get taskModelOutputTitle => operationStatus.taskModelOutputTitle;
  String get taskModelOutputText => operationStatus.taskModelOutputText;
  String get taskModelOutputReasoning =>
      operationStatus.taskModelOutputReasoning;
  bool get taskModelOutputActive => operationStatus.taskModelOutputActive;
  ChatSaveFailure? get saveFailure => persistence.saveFailure;

  ChatState copyWith({
    Object? currentChatId = _unchanged,
    Object? currentSavedChat = _unchanged,
    Object? currentModelSnapshot = _unchanged,
    Object? pendingModelRestore = _unchanged,
    Object? pendingModelRestoreIssue = _unchanged,
    Object? workspace = _unchanged,
    Object? systemPrompt = _unchanged,
    ExecutionMode? executionMode,
    Object? activeProject = _unchanged,
    Object? activeProjectPersistenceDiagnostics = _unchanged,
    List<ProjectSummary>? availableProjects,
    Object? activeTask = _unchanged,
    List<TaskSummary>? availableTasks,
    TaskSystemSettings? taskSystemSettings,
    bool? taskBusy,
    bool? taskCancellationRequested,
    Object? taskStatusMessage = _unchanged,
    Object? taskError = _unchanged,
    Object? taskModelOutputTitle = _unchanged,
    String? taskModelOutputText,
    String? taskModelOutputReasoning,
    bool? taskModelOutputActive,
    Object? saveFailure = _unchanged,
    List<Bubble>? messages,
    int? historyRevision,
  }) => ChatState(
    tabId: tabId,
    messages: messages ?? this.messages,
    historyRevision: historyRevision ?? this.historyRevision,
    currentChatId: identical(currentChatId, _unchanged)
        ? this.currentChatId
        : currentChatId as String?,
    currentSavedChat: identical(currentSavedChat, _unchanged)
        ? this.currentSavedChat
        : currentSavedChat as SavedChat?,
    currentModelSnapshot: identical(currentModelSnapshot, _unchanged)
        ? this.currentModelSnapshot
        : currentModelSnapshot as ModelConfigurationSnapshot?,
    pendingModelRestore: identical(pendingModelRestore, _unchanged)
        ? this.pendingModelRestore
        : pendingModelRestore as ModelConfigurationSnapshot?,
    pendingModelRestoreIssue: identical(pendingModelRestoreIssue, _unchanged)
        ? this.pendingModelRestoreIssue
        : pendingModelRestoreIssue as String?,
    workspace: identical(workspace, _unchanged)
        ? this.workspace
        : workspace as WorkspaceAttachment?,
    systemPrompt: identical(systemPrompt, _unchanged)
        ? this.systemPrompt
        : systemPrompt as SystemPromptSnapshot?,
    executionMode: executionMode ?? this.executionMode,
    activeProject: identical(activeProject, _unchanged)
        ? this.activeProject
        : activeProject as ProjectPanelReadModel?,
    activeProjectPersistenceDiagnostics:
        identical(activeProjectPersistenceDiagnostics, _unchanged)
        ? this.activeProjectPersistenceDiagnostics
        : activeProjectPersistenceDiagnostics as ProjectPersistenceDiagnostics?,
    availableProjects: availableProjects ?? this.availableProjects,
    activeTask: identical(activeTask, _unchanged)
        ? this.activeTask
        : activeTask as TaskPanelReadModel?,
    availableTasks: availableTasks ?? this.availableTasks,
    taskSystemSettings: taskSystemSettings ?? this.taskSystemSettings,
    taskBusy: taskBusy ?? this.taskBusy,
    taskCancellationRequested:
        taskCancellationRequested ?? this.taskCancellationRequested,
    taskStatusMessage: identical(taskStatusMessage, _unchanged)
        ? this.taskStatusMessage
        : taskStatusMessage as String?,
    taskError: identical(taskError, _unchanged) ? this.taskError : taskError,
    taskModelOutputTitle: identical(taskModelOutputTitle, _unchanged)
        ? this.taskModelOutputTitle
        : taskModelOutputTitle as String?,
    taskModelOutputText: taskModelOutputText ?? this.taskModelOutputText,
    taskModelOutputReasoning:
        taskModelOutputReasoning ?? this.taskModelOutputReasoning,
    taskModelOutputActive: taskModelOutputActive ?? this.taskModelOutputActive,
    saveFailure: identical(saveFailure, _unchanged)
        ? this.saveFailure
        : saveFailure as ChatSaveFailure?,
  );
}

const _unchanged = Object();

/// Pure state transition boundary used by the chat controller and tests.
class ChatStateReducer {
  const ChatStateReducer();

  ChatState reduce(ChatState state, ChatStateEvent event) => switch (event) {
    ChatMessagesChanged(:final messages) => state.copyWith(messages: messages),
    ChatHistoryRevisionChanged(:final revision) => state.copyWith(
      historyRevision: revision,
    ),
    ChatCurrentChatChanged(:final id) => state.copyWith(currentChatId: id),
    ChatSavedChatChanged(:final chat) => state.copyWith(currentSavedChat: chat),
    ChatModelSnapshotChanged(:final snapshot) => state.copyWith(
      currentModelSnapshot: snapshot,
    ),
    ChatPendingModelRestoreChanged(:final snapshot) => state.copyWith(
      pendingModelRestore: snapshot,
    ),
    ChatPendingModelRestoreIssueChanged(:final issue) => state.copyWith(
      pendingModelRestoreIssue: issue,
    ),
    ChatWorkspaceChanged(:final workspace) => state.copyWith(
      workspace: workspace,
    ),
    ChatSystemPromptChanged(:final prompt) => state.copyWith(
      systemPrompt: prompt,
    ),
    ChatExecutionModeChanged(:final mode) => state.copyWith(
      executionMode: mode,
    ),
    ChatProjectChanged(:final project) => state.copyWith(
      activeProject: project,
    ),
    ChatProjectDiagnosticsChanged(:final diagnostics) => state.copyWith(
      activeProjectPersistenceDiagnostics: diagnostics,
    ),
    ChatProjectsChanged(:final projects) => state.copyWith(
      availableProjects: projects,
    ),
    ChatTaskChanged(:final task) => state.copyWith(activeTask: task),
    ChatTasksChanged(:final tasks) => state.copyWith(availableTasks: tasks),
    ChatTaskSettingsChanged(:final settings) => state.copyWith(
      taskSystemSettings: settings,
    ),
    ChatTaskBusyChanged(:final busy) => dispatchTaskBusy(state, busy),
    ChatTaskCancellationChanged(:final requested) =>
      requested
          ? requestTaskCancellation(state)
          : state.copyWith(taskCancellationRequested: false),
    ChatTaskStatusMessageChanged(:final message) => state.copyWith(
      taskStatusMessage: message,
    ),
    ChatTaskErrorChanged(:final error) => dispatchTaskError(state, error),
    ChatTaskModelOutputTitleChanged(:final title) => state.copyWith(
      taskModelOutputTitle: title,
    ),
    ChatTaskModelOutputTextChanged(:final text) => state.copyWith(
      taskModelOutputText: text,
    ),
    ChatTaskModelOutputReasoningChanged(:final reasoning) => state.copyWith(
      taskModelOutputReasoning: reasoning,
    ),
    ChatTaskModelOutputActiveChanged(:final active) => state.copyWith(
      taskModelOutputActive: active,
    ),
    ChatSaveFailureChanged(:final failure) => state.copyWith(
      saveFailure: failure,
    ),
  };

  ChatState dispatchTaskBusy(ChatState state, bool busy) => state.copyWith(
    taskBusy: busy,
    taskCancellationRequested: busy ? state.taskCancellationRequested : false,
  );

  ChatState requestTaskCancellation(ChatState state) =>
      state.taskBusy ? state.copyWith(taskCancellationRequested: true) : state;

  ChatState dispatchTaskError(ChatState state, Object? error) => state.copyWith(
    taskError: error,
    taskBusy: error == null ? state.taskBusy : false,
    taskCancellationRequested: error == null
        ? state.taskCancellationRequested
        : false,
  );
}

sealed class ChatStateEvent {
  const ChatStateEvent();
}

class ChatMessagesChanged extends ChatStateEvent {
  const ChatMessagesChanged(this.messages);

  final List<Bubble> messages;
}

class ChatHistoryRevisionChanged extends ChatStateEvent {
  const ChatHistoryRevisionChanged(this.revision);

  final int revision;
}

class ChatCurrentChatChanged extends ChatStateEvent {
  const ChatCurrentChatChanged(this.id);

  final String? id;
}

class ChatSavedChatChanged extends ChatStateEvent {
  const ChatSavedChatChanged(this.chat);

  final SavedChat? chat;
}

class ChatModelSnapshotChanged extends ChatStateEvent {
  const ChatModelSnapshotChanged(this.snapshot);

  final ModelConfigurationSnapshot? snapshot;
}

class ChatPendingModelRestoreChanged extends ChatStateEvent {
  const ChatPendingModelRestoreChanged(this.snapshot);

  final ModelConfigurationSnapshot? snapshot;
}

class ChatPendingModelRestoreIssueChanged extends ChatStateEvent {
  const ChatPendingModelRestoreIssueChanged(this.issue);

  final String? issue;
}

class ChatWorkspaceChanged extends ChatStateEvent {
  const ChatWorkspaceChanged(this.workspace);

  final WorkspaceAttachment? workspace;
}

class ChatSystemPromptChanged extends ChatStateEvent {
  const ChatSystemPromptChanged(this.prompt);

  final SystemPromptSnapshot? prompt;
}

class ChatExecutionModeChanged extends ChatStateEvent {
  const ChatExecutionModeChanged(this.mode);

  final ExecutionMode mode;
}

class ChatProjectChanged extends ChatStateEvent {
  const ChatProjectChanged(this.project);

  final ProjectPanelReadModel? project;
}

class ChatProjectDiagnosticsChanged extends ChatStateEvent {
  const ChatProjectDiagnosticsChanged(this.diagnostics);

  final ProjectPersistenceDiagnostics? diagnostics;
}

class ChatProjectsChanged extends ChatStateEvent {
  const ChatProjectsChanged(this.projects);

  final List<ProjectSummary> projects;
}

class ChatTaskChanged extends ChatStateEvent {
  const ChatTaskChanged(this.task);

  final TaskPanelReadModel? task;
}

class ChatTasksChanged extends ChatStateEvent {
  const ChatTasksChanged(this.tasks);

  final List<TaskSummary> tasks;
}

class ChatTaskSettingsChanged extends ChatStateEvent {
  const ChatTaskSettingsChanged(this.settings);

  final TaskSystemSettings settings;
}

class ChatTaskBusyChanged extends ChatStateEvent {
  const ChatTaskBusyChanged(this.busy);

  final bool busy;
}

class ChatTaskCancellationChanged extends ChatStateEvent {
  const ChatTaskCancellationChanged(this.requested);

  final bool requested;
}

class ChatTaskStatusMessageChanged extends ChatStateEvent {
  const ChatTaskStatusMessageChanged(this.message);

  final String? message;
}

class ChatTaskErrorChanged extends ChatStateEvent {
  const ChatTaskErrorChanged(this.error);

  final Object? error;
}

class ChatTaskModelOutputTitleChanged extends ChatStateEvent {
  const ChatTaskModelOutputTitleChanged(this.title);

  final String? title;
}

class ChatTaskModelOutputTextChanged extends ChatStateEvent {
  const ChatTaskModelOutputTextChanged(this.text);

  final String text;
}

class ChatTaskModelOutputReasoningChanged extends ChatStateEvent {
  const ChatTaskModelOutputReasoningChanged(this.reasoning);

  final String reasoning;
}

class ChatTaskModelOutputActiveChanged extends ChatStateEvent {
  const ChatTaskModelOutputActiveChanged(this.active);

  final bool active;
}

class ChatSaveFailureChanged extends ChatStateEvent {
  const ChatSaveFailureChanged(this.failure);

  final ChatSaveFailure? failure;
}
