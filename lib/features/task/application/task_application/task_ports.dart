import 'package:hermes/core/models/compaction_settings.dart';
import 'package:hermes/core/services/cancellation_token.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/core/services/persistence_contracts.dart';
import 'package:hermes/features/model/domain/model_provider.dart';
import 'package:hermes/features/task/application/task_application/task_model_output.dart';
import 'package:hermes/features/task/application/task_application/task_summary.dart';
import 'package:hermes/features/task/domain/task.dart';
import 'package:hermes/features/task/domain/task_planning_models.dart';
import 'package:hermes/shared_kernel/task_system_settings.dart';
import 'package:hermes/features/workspace/domain/workspace.dart';
import 'package:hermes/features/workspace/application/workspace_ports.dart';

class TaskStorageLayout {
  static const String tasksRoot = '.agent/tasks';
  static const String documentFileName = 'task.json';
  static const String runsDirectoryName = 'runs';
}

typedef TaskCompactionStatusSink = void Function(String status);

/// Persistence capabilities needed by the project application boundary.
///
/// The project feature does not need to know about the concrete task
/// controller. Keeping this contract beside the task feature also prevents a
/// reverse project -> task orchestration dependency from leaking into chat.
abstract interface class TaskRepositoryPort {
  PersistencePort get coordinator;

  Future<PersistedSnapshot<Task>?> loadTaskSnapshot(
    String workspaceRoot,
    String taskId, {
    String? chatSessionId,
    String? projectId,
    bool includeHistory = true,
  });

  Future<Map<String, PersistedSnapshot<Task>?>> loadTaskSnapshots(
    String workspaceRoot,
    Iterable<String> taskIds, {
    String? chatSessionId,
    String? projectId,
    bool includeHistory = true,
  });

  Future<PersistedRevision?> revisionOfUnlocked(
    String workspaceRoot,
    String taskId,
  );

  Future<Map<String, PersistedRevision?>> revisionOfManyUnlocked(
    String workspaceRoot,
    Iterable<String> taskIds,
  );

  Future<PersistedSnapshot<Task>?> loadTaskSnapshotUnlocked(
    String workspaceRoot,
    String taskId, {
    String? chatSessionId,
    String? projectId,
    bool includeHistory = true,
  });

  Future<PersistedSnapshot<Task>> saveSnapshotUnlocked(
    String workspaceRoot,
    Task task, {
    required int expectedRevision,
    PersistedRevision? currentRevision,
  });

  Future<bool> deleteTaskUnlocked(String workspaceRoot, String taskId);

  String taskRelativePath(String taskId, String fileName);

  Future<List<TaskSummary>> listTasks(
    String workspaceRoot, {
    String? chatSessionId,
    String? projectId,
  });

  Future<PersistedSnapshot<Task>?> loadLatestTask(
    String workspaceRoot, {
    String? chatSessionId,
    String? projectId,
  });

  Future<PersistedSnapshot<Task>?> loadTask(
    String workspaceRoot,
    String taskId, {
    String? chatSessionId,
    String? projectId,
    bool includeHistory = true,
  });

  Future<PersistedSnapshot<Task>> saveSnapshot(
    String workspaceRoot,
    Task task, {
    int? expectedRevision,
    bool assumeLocked = false,
  });

  Future<bool> deleteTask(String workspaceRoot, String taskId);

  Future<void> saveLog(
    String workspaceRoot,
    String taskId,
    String name,
    String content,
  );

  Future<int> deleteTasksForChatSession(
    String workspaceRoot, {
    required String chatSessionId,
  });

  Future<int> deleteOrphanedChatTasks(
    String workspaceRoot, {
    required Set<String> retainedChatSessionIds,
  });
}

/// Narrow task use-case port consumed by chat and project orchestration.
abstract interface class TaskApplicationPort {
  TaskRepositoryPort get repository;
  ToolService get toolService;

  Future<List<TaskSummary>> listTasks(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
    String? projectId,
  });

  Future<Task?> loadLatestTask(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
    String? projectId,
  });

  Future<Task?> loadTask(
    WorkspaceAttachment workspace,
    String taskId, {
    String? chatSessionId,
    String? projectId,
    bool includeHistory = true,
  });

  Future<int> deleteTasksForChatSession(
    WorkspaceAttachment workspace, {
    required String chatSessionId,
  });

  Future<int> deleteOrphanedChatTasks(
    WorkspaceAttachment workspace, {
    required Set<String> retainedChatSessionIds,
  });

  Future<Task> updateTaskChatSessionId({
    required WorkspaceAttachment workspace,
    required Task snapshot,
    required String chatSessionId,
  });

  Future<Task> recoverTask({
    required WorkspaceAttachment workspace,
    required Task snapshot,
    bool persist = true,
  });

  String encodeTask(Task task);

  Future<String> readArtifact({
    required WorkspaceAttachment workspace,
    required String artifactPath,
    CancellationToken? cancellationToken,
  });

  Future<RefinedTaskBrief> refineTaskBrief({
    required ModelProvider client,
    WorkspaceAttachment? workspace,
    required String userPrompt,
    ExecutionMode selectedMode = ExecutionMode.refine,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  });

  Future<Task> createTask({
    required ModelProvider client,
    required WorkspaceAttachment workspace,
    required String userPrompt,
    required ExecutionMode selectedMode,
    required String baseSystemPrompt,
    String? chatSessionId,
    String? projectId,
    String? canonicalTaskId,
    TaskPlanningContext? planningContext,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  });

  Future<Task> createProjectTask({
    required WorkspaceAttachment workspace,
    required String userPrompt,
    required String? chatSessionId,
    required String? projectId,
    required TaskPlanningContext planningContext,
    String? canonicalTaskId,
  });

  Future<Task> updateTaskPlan({
    required WorkspaceAttachment workspace,
    required Task snapshot,
    required String rawJson,
  });

  Future<Task> runNextStep({
    required ModelProvider client,
    required WorkspaceAttachment workspace,
    required Task snapshot,
    required String baseSystemPrompt,
    bool requirePhaseApproval = false,
    CompactionSettings? compactionSettings,
    int? contextLimitTokens,
    TaskCompactionStatusSink? onCompactionStatus,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
    QuestionAutonomy questionAutonomy = QuestionAutonomy.balanced,
    TaskExecutionRequest executionRequest = const TaskExecutionRequest(),
    bool persist = true,
  });

  Future<Task> approvePendingStep({
    required WorkspaceAttachment workspace,
    required Task snapshot,
  });

  Future<Task> retryCurrentStep({
    required WorkspaceAttachment workspace,
    required Task snapshot,
  });

  Future<Task> skipCurrentStep({
    required WorkspaceAttachment workspace,
    required Task snapshot,
  });

  Future<Task> stopTask({
    required WorkspaceAttachment workspace,
    required Task snapshot,
  });

  Future<Task> answerOpenQuestion({
    required WorkspaceAttachment workspace,
    required Task snapshot,
    required String answer,
  });

  Future<Task> replanUnfinished({
    required ModelProvider client,
    required WorkspaceAttachment workspace,
    required Task snapshot,
    required String baseSystemPrompt,
    String reason = 'User requested a replan of unfinished work.',
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  });
}
