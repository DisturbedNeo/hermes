import 'package:hermes/core/cancellation.dart';
import 'package:hermes/features/chat/application/contracts/compaction_settings.dart';
import 'package:hermes/features/model/application/model_completion_port.dart';
import 'package:hermes/features/model/application/model_output.dart';
import 'package:hermes/features/task/application/contracts/task_summary.dart';
import 'package:hermes/features/task/application/contracts/task_system_settings.dart';
import 'package:hermes/features/workspace/application/workspace.dart';
import 'package:hermes/features/task/application/contracts/task_snapshot_models.dart';
import 'package:hermes/features/task/application/contracts/task_planning_models.dart';
import 'package:hermes/features/task/application/contracts/task_commands.dart';

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

abstract interface class TaskSessionPort {
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
}

abstract interface class TaskPresentationPort {
  Future<String> readArtifact({
    required WorkspaceAttachment workspace,
    required String artifactPath,
    CancellationToken? cancellationToken,
  });
}

abstract interface class TaskPlanningPort {
  Future<RefinedTaskBrief> refineTaskBrief({
    required ModelCompletionPort client,
    WorkspaceAttachment? workspace,
    required String userPrompt,
    ExecutionMode selectedMode = ExecutionMode.refine,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  });

  Future<Task> createTask({
    required ModelCompletionPort client,
    required WorkspaceAttachment workspace,
    required String userPrompt,
    required ExecutionMode selectedMode,
    required String baseSystemPrompt,
    String? chatSessionId,
    String? projectId,
    String? canonicalTaskId,
    TaskPlanningContext? planningContext,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  });

  Future<Task> updateTaskPlan({
    required WorkspaceAttachment workspace,
    required Task snapshot,
    required TaskPlanUpdateCommand command,
  });

  Future<Task> replanUnfinished({
    required ModelCompletionPort client,
    required WorkspaceAttachment workspace,
    required Task snapshot,
    required String baseSystemPrompt,
    String reason = 'User requested a replan of unfinished work.',
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  });
}

abstract interface class TaskProjectPlanningPort {
  Future<Task> createProjectTask({
    required WorkspaceAttachment workspace,
    required String userPrompt,
    required String? chatSessionId,
    required String? projectId,
    required TaskPlanningContext planningContext,
    String? canonicalTaskId,
  });
}

abstract interface class TaskExecutionPort {
  Future<Task> runNextStep({
    required ModelCompletionPort client,
    required WorkspaceAttachment workspace,
    required Task snapshot,
    required String baseSystemPrompt,
    bool requirePhaseApproval = false,
    CompactionSettings? compactionSettings,
    int? contextLimitTokens,
    TaskCompactionStatusSink? onCompactionStatus,
    ModelOutputSink? onModelOutput,
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
}

abstract interface class TaskRecoveryPort {
  Future<Task> recoverTask({
    required WorkspaceAttachment workspace,
    required Task snapshot,
    bool persist = true,
  });
}
