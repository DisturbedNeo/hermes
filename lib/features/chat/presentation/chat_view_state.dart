import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/core/models/chat_persistence.dart';
import 'package:hermes/core/models/model_configuration_snapshot.dart';
import 'package:hermes/core/models/saved_chat.dart';
import 'package:hermes/core/models/system_prompt.dart';
import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/features/task/domain/task.dart';
import 'package:hermes/features/task/domain/task_system_settings.dart';
import 'package:hermes/features/task/application/task_application/task_summary.dart';
import 'package:hermes/features/workspace/domain/workspace.dart';

/// Immutable presentation snapshot for one chat tab.
class ChatViewState {
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
  final ProjectDocument? activeProject;
  final List<ProjectSummary> availableProjects;
  final Task? activeTask;
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

  ChatViewState({
    required this.tabId,
    required List<Bubble> messages,
    required this.historyRevision,
    required this.currentChatId,
    required this.currentSavedChat,
    required this.currentModelSnapshot,
    required this.pendingModelRestore,
    required this.pendingModelRestoreIssue,
    required this.workspace,
    required this.systemPrompt,
    required this.executionMode,
    required this.activeProject,
    required List<ProjectSummary> availableProjects,
    required this.activeTask,
    required List<TaskSummary> availableTasks,
    required this.taskSystemSettings,
    required this.taskBusy,
    required this.taskCancellationRequested,
    required this.taskStatusMessage,
    required this.taskError,
    required this.taskModelOutputTitle,
    required this.taskModelOutputText,
    required this.taskModelOutputReasoning,
    required this.taskModelOutputActive,
    required this.saveFailure,
  }) : messages = List.unmodifiable(messages),
       availableProjects = List.unmodifiable(availableProjects),
       availableTasks = List.unmodifiable(availableTasks);
}
