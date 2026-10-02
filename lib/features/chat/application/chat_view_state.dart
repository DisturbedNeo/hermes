import 'package:hermes/features/chat/application/contracts/bubble.dart';
import 'package:hermes/features/chat/application/contracts/chat_persistence.dart';
import 'package:hermes/features/model/application/model_configuration.dart';
import 'package:hermes/features/persistence/application/persistence_contracts.dart';
import 'package:hermes/features/chat/application/contracts/saved_chat.dart';
import 'package:hermes/features/chat/application/contracts/system_prompt.dart';
import 'package:hermes/features/chat/domain/chat_panel_read_models.dart';
import 'package:hermes/features/chat/domain/chat_state_slices.dart';
import 'package:hermes/core/contracts/execution_settings.dart';
import 'package:hermes/features/task/application/contracts/task_summary.dart';
import 'package:hermes/features/workspace/application/workspace.dart';

/// Immutable presentation snapshot for one chat tab.
///
/// Compatibility getters retain the existing widget-facing API, while the
/// slice fields make ownership explicit for new consumers.
class ChatViewState {
  ChatViewState({
    required this.tabId,
    required List<Bubble> messages,
    required int historyRevision,
    required String? currentChatId,
    required SavedChat? currentSavedChat,
    required ModelConfigurationSnapshot? currentModelSnapshot,
    required ModelConfigurationSnapshot? pendingModelRestore,
    required String? pendingModelRestoreIssue,
    required WorkspaceAttachment? workspace,
    required SystemPromptSnapshot? systemPrompt,
    required ExecutionMode executionMode,
    required ProjectPanelReadModel? activeProject,
    required ProjectPersistenceDiagnostics? activeProjectPersistenceDiagnostics,
    required List<ProjectSummary> availableProjects,
    required TaskPanelReadModel? activeTask,
    required List<TaskSummary> availableTasks,
    required TaskSystemSettings taskSystemSettings,
    required bool taskBusy,
    required bool taskCancellationRequested,
    required String? taskStatusMessage,
    required Object? taskError,
    required String? taskModelOutputTitle,
    required String taskModelOutputText,
    required String taskModelOutputReasoning,
    required bool taskModelOutputActive,
    required ChatSaveFailure? saveFailure,
  }) : conversation = ChatConversationState(
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
}
