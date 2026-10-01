import 'package:hermes/features/chat/application/contracts/bubble.dart';
import 'package:hermes/features/chat/application/contracts/chat_persistence.dart';
import 'package:hermes/features/chat/application/contracts/saved_chat.dart';
import 'package:hermes/features/chat/application/contracts/system_prompt.dart';
import 'package:hermes/features/chat/domain/chat_panel_read_models.dart';
import 'package:hermes/features/model/application/model_configuration.dart';
import 'package:hermes/features/persistence/application/persistence_contracts.dart';
import 'package:hermes/features/task/application/contracts/task_summary.dart';
import 'package:hermes/features/task/application/contracts/task_system_settings.dart';
import 'package:hermes/features/workspace/application/workspace.dart';

/// Immutable conversation projection owned by [ChatState].
class ChatConversationState {
  ChatConversationState({
    required List<Bubble> messages,
    required this.historyRevision,
  }) : messages = List.unmodifiable(messages);

  final List<Bubble> messages;
  final int historyRevision;

  ChatConversationState copyWith({
    List<Bubble>? messages,
    int? historyRevision,
  }) => ChatConversationState(
    messages: messages ?? this.messages,
    historyRevision: historyRevision ?? this.historyRevision,
  );
}

/// Immutable model-session projection. Lifecycle commands never mutate this
/// object directly; the reducer replaces it in response to typed events.
class ChatModelSessionState {
  const ChatModelSessionState({
    this.currentSnapshot,
    this.pendingRestore,
    this.pendingRestoreIssue,
  });

  final ModelConfigurationSnapshot? currentSnapshot;
  final ModelConfigurationSnapshot? pendingRestore;
  final String? pendingRestoreIssue;

  ChatModelSessionState copyWith({
    Object? currentSnapshot = _sliceUnchanged,
    Object? pendingRestore = _sliceUnchanged,
    Object? pendingRestoreIssue = _sliceUnchanged,
  }) => ChatModelSessionState(
    currentSnapshot: identical(currentSnapshot, _sliceUnchanged)
        ? this.currentSnapshot
        : currentSnapshot as ModelConfigurationSnapshot?,
    pendingRestore: identical(pendingRestore, _sliceUnchanged)
        ? this.pendingRestore
        : pendingRestore as ModelConfigurationSnapshot?,
    pendingRestoreIssue: identical(pendingRestoreIssue, _sliceUnchanged)
        ? this.pendingRestoreIssue
        : pendingRestoreIssue as String?,
  );
}

/// Immutable project-panel projection. It contains only panel read models,
/// never a persistence DTO or project aggregate.
class ChatProjectPanelState {
  ChatProjectPanelState({
    this.activeProject,
    this.persistenceDiagnostics,
    required List<ProjectSummary> availableProjects,
  }) : availableProjects = List.unmodifiable(availableProjects);

  final ProjectPanelReadModel? activeProject;
  final ProjectPersistenceDiagnostics? persistenceDiagnostics;
  final List<ProjectSummary> availableProjects;

  ChatProjectPanelState copyWith({
    Object? activeProject = _sliceUnchanged,
    Object? persistenceDiagnostics = _sliceUnchanged,
    List<ProjectSummary>? availableProjects,
  }) => ChatProjectPanelState(
    activeProject: identical(activeProject, _sliceUnchanged)
        ? this.activeProject
        : activeProject as ProjectPanelReadModel?,
    persistenceDiagnostics: identical(persistenceDiagnostics, _sliceUnchanged)
        ? this.persistenceDiagnostics
        : persistenceDiagnostics as ProjectPersistenceDiagnostics?,
    availableProjects: availableProjects ?? this.availableProjects,
  );
}

/// Immutable task-panel projection.
class ChatTaskPanelState {
  ChatTaskPanelState({
    this.activeTask,
    required List<TaskSummary> availableTasks,
    this.settings = const TaskSystemSettings(),
  }) : availableTasks = List.unmodifiable(availableTasks);

  final TaskPanelReadModel? activeTask;
  final List<TaskSummary> availableTasks;
  final TaskSystemSettings settings;

  ChatTaskPanelState copyWith({
    Object? activeTask = _sliceUnchanged,
    List<TaskSummary>? availableTasks,
    TaskSystemSettings? settings,
  }) => ChatTaskPanelState(
    activeTask: identical(activeTask, _sliceUnchanged)
        ? this.activeTask
        : activeTask as TaskPanelReadModel?,
    availableTasks: availableTasks ?? this.availableTasks,
    settings: settings ?? this.settings,
  );
}

/// Persistence projection for the current chat record.
class ChatPersistenceState {
  const ChatPersistenceState({
    this.currentChatId,
    this.currentSavedChat,
    this.saveFailure,
  });

  final String? currentChatId;
  final SavedChat? currentSavedChat;
  final ChatSaveFailure? saveFailure;

  ChatPersistenceState copyWith({
    Object? currentChatId = _sliceUnchanged,
    Object? currentSavedChat = _sliceUnchanged,
    Object? saveFailure = _sliceUnchanged,
  }) => ChatPersistenceState(
    currentChatId: identical(currentChatId, _sliceUnchanged)
        ? this.currentChatId
        : currentChatId as String?,
    currentSavedChat: identical(currentSavedChat, _sliceUnchanged)
        ? this.currentSavedChat
        : currentSavedChat as SavedChat?,
    saveFailure: identical(saveFailure, _sliceUnchanged)
        ? this.saveFailure
        : saveFailure as ChatSaveFailure?,
  );
}

/// Transient operation status. This slice is deliberately separate from
/// durable task/project state and is cleared by reducer transitions.
class ChatTransientOperationState {
  const ChatTransientOperationState({
    this.taskBusy = false,
    this.taskCancellationRequested = false,
    this.taskStatusMessage,
    this.taskError,
    this.taskModelOutputTitle,
    this.taskModelOutputText = '',
    this.taskModelOutputReasoning = '',
    this.taskModelOutputActive = false,
  }) : assert(!taskCancellationRequested || taskBusy);

  final bool taskBusy;
  final bool taskCancellationRequested;
  final String? taskStatusMessage;
  final Object? taskError;
  final String? taskModelOutputTitle;
  final String taskModelOutputText;
  final String taskModelOutputReasoning;
  final bool taskModelOutputActive;

  ChatTransientOperationState copyWith({
    bool? taskBusy,
    bool? taskCancellationRequested,
    Object? taskStatusMessage = _sliceUnchanged,
    Object? taskError = _sliceUnchanged,
    Object? taskModelOutputTitle = _sliceUnchanged,
    String? taskModelOutputText,
    String? taskModelOutputReasoning,
    bool? taskModelOutputActive,
  }) => ChatTransientOperationState(
    taskBusy: taskBusy ?? this.taskBusy,
    taskCancellationRequested:
        taskCancellationRequested ?? this.taskCancellationRequested,
    taskStatusMessage: identical(taskStatusMessage, _sliceUnchanged)
        ? this.taskStatusMessage
        : taskStatusMessage as String?,
    taskError: identical(taskError, _sliceUnchanged)
        ? this.taskError
        : taskError,
    taskModelOutputTitle: identical(taskModelOutputTitle, _sliceUnchanged)
        ? this.taskModelOutputTitle
        : taskModelOutputTitle as String?,
    taskModelOutputText: taskModelOutputText ?? this.taskModelOutputText,
    taskModelOutputReasoning:
        taskModelOutputReasoning ?? this.taskModelOutputReasoning,
    taskModelOutputActive: taskModelOutputActive ?? this.taskModelOutputActive,
  );
}

/// Session context that is not part of persistence, but is not an operation
/// status either.
class ChatContextState {
  const ChatContextState({
    this.workspace,
    this.systemPrompt,
    this.executionMode = ExecutionMode.chat,
  });

  final WorkspaceAttachment? workspace;
  final SystemPromptSnapshot? systemPrompt;
  final ExecutionMode executionMode;

  ChatContextState copyWith({
    Object? workspace = _sliceUnchanged,
    Object? systemPrompt = _sliceUnchanged,
    ExecutionMode? executionMode,
  }) => ChatContextState(
    workspace: identical(workspace, _sliceUnchanged)
        ? this.workspace
        : workspace as WorkspaceAttachment?,
    systemPrompt: identical(systemPrompt, _sliceUnchanged)
        ? this.systemPrompt
        : systemPrompt as SystemPromptSnapshot?,
    executionMode: executionMode ?? this.executionMode,
  );
}

const _sliceUnchanged = Object();
