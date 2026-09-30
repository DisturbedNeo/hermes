import 'package:hermes/shared_kernel/bubble.dart';
import 'package:hermes/shared_kernel/chat_persistence.dart';
import 'package:hermes/shared_kernel/model_configuration.dart';
import 'package:hermes/shared_kernel/saved_chat.dart';
import 'package:hermes/shared_kernel/system_prompt.dart';
import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/shared_kernel/task_summary.dart';
import 'package:hermes/features/task/domain/task.dart';
import 'package:hermes/shared_kernel/task_system_settings.dart';
import 'package:hermes/shared_kernel/workspace.dart';

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
    required this.historyRevision,
    this.currentChatId,
    this.currentSavedChat,
    this.currentModelSnapshot,
    this.pendingModelRestore,
    this.pendingModelRestoreIssue,
    this.workspace,
    this.systemPrompt,
    this.executionMode = ExecutionMode.chat,
    this.activeProject,
    List<ProjectSummary> availableProjects = const [],
    this.activeTask,
    List<TaskSummary> availableTasks = const [],
    this.taskSystemSettings = const TaskSystemSettings(),
    this.taskBusy = false,
    this.taskCancellationRequested = false,
    this.taskStatusMessage,
    this.taskError,
    this.taskModelOutputTitle,
    this.taskModelOutputText = '',
    this.taskModelOutputReasoning = '',
    this.taskModelOutputActive = false,
    this.saveFailure,
  }) : assert(!taskCancellationRequested || taskBusy),
       messages = List.unmodifiable(messages),
       availableProjects = List.unmodifiable(availableProjects),
       availableTasks = List.unmodifiable(availableTasks);

  factory ChatState.initial(String tabId, Bubble systemPrompt) =>
      ChatState(tabId: tabId, messages: [systemPrompt], historyRevision: 0);

  final String tabId;
  final List<Bubble> messages;
  final int historyRevision;
  final String? currentChatId;
  final SavedChat? currentSavedChat;
  final ModelConfigurationSnapshot? currentModelSnapshot;
  final ModelConfigurationSnapshot? pendingModelRestore;
  final String? pendingModelRestoreIssue;
  final WorkspaceAttachment? workspace;
  final SystemPromptSnapshot? systemPrompt;
  final ExecutionMode executionMode;
  final ProjectAggregate? activeProject;
  final List<ProjectSummary> availableProjects;
  final TaskAggregate? activeTask;
  final List<TaskSummary> availableTasks;
  final TaskSystemSettings taskSystemSettings;
  final bool taskBusy;
  final bool taskCancellationRequested;
  final String? taskStatusMessage;
  final Object? taskError;
  final String? taskModelOutputTitle;
  final String taskModelOutputText;
  final String taskModelOutputReasoning;
  final bool taskModelOutputActive;
  final ChatSaveFailure? saveFailure;

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
        : activeProject as ProjectAggregate?,
    availableProjects: availableProjects ?? this.availableProjects,
    activeTask: identical(activeTask, _unchanged)
        ? this.activeTask
        : activeTask as TaskAggregate?,
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
    ChatWorkspaceChanged(:final workspace) => state.copyWith(
      workspace: workspace,
    ),
    ChatProjectChanged(:final project) => state.copyWith(
      activeProject: project,
    ),
    ChatTaskChanged(:final task) => state.copyWith(activeTask: task),
    ChatTaskBusyChanged(:final busy) => setTaskBusy(state, busy),
    ChatTaskErrorChanged(:final error) => setTaskError(state, error),
  };

  ChatState setTaskBusy(ChatState state, bool busy) => state.copyWith(
    taskBusy: busy,
    taskCancellationRequested: busy ? state.taskCancellationRequested : false,
  );

  ChatState requestTaskCancellation(ChatState state) =>
      state.taskBusy ? state.copyWith(taskCancellationRequested: true) : state;

  ChatState setTaskError(ChatState state, Object? error) => state.copyWith(
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

class ChatWorkspaceChanged extends ChatStateEvent {
  const ChatWorkspaceChanged(this.workspace);

  final WorkspaceAttachment? workspace;
}

class ChatProjectChanged extends ChatStateEvent {
  const ChatProjectChanged(this.project);

  final ProjectAggregate? project;
}

class ChatTaskChanged extends ChatStateEvent {
  const ChatTaskChanged(this.task);

  final TaskAggregate? task;
}

class ChatTaskBusyChanged extends ChatStateEvent {
  const ChatTaskBusyChanged(this.busy);

  final bool busy;
}

class ChatTaskErrorChanged extends ChatStateEvent {
  const ChatTaskErrorChanged(this.error);

  final Object? error;
}
