import 'package:hermes/shared_kernel/cancellation.dart';
import 'package:hermes/shared_kernel/compaction_settings.dart';
import 'package:hermes/shared_kernel/model_provider.dart';
import 'package:hermes/shared_kernel/model_output.dart';
import 'package:hermes/shared_kernel/task_summary.dart';
import 'package:hermes/shared_kernel/task_system_settings.dart';
import 'package:hermes/shared_kernel/tool_contracts.dart';
import 'package:hermes/shared_kernel/workspace.dart';
import 'package:hermes/shared_kernel/task.dart';
import 'package:hermes/shared_kernel/task_planning_models.dart';
import 'package:hermes/shared_kernel/task_persistence_ports.dart';

abstract interface class TaskQueryPort {
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
}

abstract interface class TaskPlanningPort {
  Future<Task> updateTaskPlan({
    required WorkspaceAttachment workspace,
    required Task snapshot,
    required String rawJson,
  });
}

abstract interface class TaskExecutionPort {
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
}

abstract interface class TaskRecoveryPort {
  Future<Task> recoverTask({
    required WorkspaceAttachment workspace,
    required Task snapshot,
    bool persist = true,
  });
}

abstract interface class TaskChatPort
    implements
        TaskQueryPort,
        TaskPlanningPort,
        TaskExecutionPort,
        TaskRecoveryPort {
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

abstract interface class TaskProjectPort implements TaskQueryPort {
  TaskPersistencePort get persistence;
  ToolRegistryPort get tools;
  TaskMaterializerPort get materializer;

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

  Future<Task> recoverTask({
    required WorkspaceAttachment workspace,
    required Task snapshot,
    bool persist = true,
  });
}

abstract interface class TaskToolPort {
  ToolRegistryPort get tools;
}
