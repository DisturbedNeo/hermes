import 'package:hermes/core/cancellation.dart';
import 'package:hermes/core/contracts/model_conversation.dart';
import 'package:hermes/features/model/application/model_completion_port.dart';
import 'package:hermes/features/model/application/model_output.dart';
import 'package:hermes/features/task/application/contracts/task_summary.dart';
import 'package:hermes/core/contracts/execution_settings.dart';
import 'package:hermes/features/workspace/application/workspace.dart';
import 'package:hermes/features/task/domain/task.dart';
import 'package:hermes/features/task/application/contracts/task_planning_models.dart';
import 'package:hermes/features/task/application/contracts/task_commands.dart';

/// Stable cross-feature projection query. It returns detached summaries only.
abstract interface class TaskSummaryQueryPort {
  Future<List<TaskSummary>> listTasks(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
    String? projectId,
  });
}

/// Owning-feature task hydration seam. Runtime workflows use this explicitly;
/// presentation and saved-task lists should use summaries.
abstract interface class TaskAggregateQueryPort {
  Future<TaskAggregate?> loadLatestTask(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
    String? projectId,
  });

  Future<TaskAggregate?> loadTask(
    WorkspaceAttachment workspace,
    String taskId, {
    String? chatSessionId,
    String? projectId,
    bool includeHistory = true,
  });
}

/// Summary-only query surface for feature-facing callers.
abstract interface class TaskQueryPort implements TaskSummaryQueryPort {}

/// Internal workflow query surface that composes summary and owner-bound task
/// hydration for runtime orchestration.
abstract interface class TaskWorkflowQueryPort
    implements TaskSummaryQueryPort, TaskAggregateQueryPort {}

abstract interface class TaskSessionPort {
  Future<int> deleteTasksForChatSession(
    WorkspaceAttachment workspace, {
    required String chatSessionId,
  });

  Future<int> deleteOrphanedChatTasks(
    WorkspaceAttachment workspace, {
    required Set<String> retainedChatSessionIds,
  });

  Future<void> updateTaskChatSessionId({
    required WorkspaceAttachment workspace,
    required String taskId,
    required String sourceChatSessionId,
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
    required ModelGenerationPort client,
    WorkspaceAttachment? workspace,
    required String userPrompt,
    ExecutionMode selectedMode = ExecutionMode.refine,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  });

  Future<TaskAggregate> createTask({
    required ModelGenerationPort client,
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

  Future<TaskAggregate> updateTaskPlan({
    required WorkspaceAttachment workspace,
    required TaskAggregate snapshot,
    required TaskPlanUpdateCommand command,
  });

  Future<TaskAggregate> replanUnfinished({
    required ModelGenerationPort client,
    required WorkspaceAttachment workspace,
    required TaskAggregate snapshot,
    required String baseSystemPrompt,
    String reason = 'User requested a replan of unfinished work.',
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  });
}

abstract interface class TaskProjectPlanningPort {
  Future<TaskAggregate> createProjectTask({
    required WorkspaceAttachment workspace,
    required String userPrompt,
    required String? chatSessionId,
    required String? projectId,
    required TaskPlanningContext planningContext,
    String? canonicalTaskId,
  });
}

abstract interface class TaskExecutionPort {
  Future<TaskAggregate> runNextStep({
    required ModelConversationPort client,
    required WorkspaceAttachment workspace,
    required TaskAggregate snapshot,
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

  Future<TaskAggregate> approvePendingStep({
    required WorkspaceAttachment workspace,
    required TaskAggregate snapshot,
  });

  Future<TaskAggregate> retryCurrentStep({
    required WorkspaceAttachment workspace,
    required TaskAggregate snapshot,
  });

  Future<TaskAggregate> skipCurrentStep({
    required WorkspaceAttachment workspace,
    required TaskAggregate snapshot,
  });

  Future<TaskAggregate> stopTask({
    required WorkspaceAttachment workspace,
    required TaskAggregate snapshot,
  });

  Future<TaskAggregate> answerOpenQuestion({
    required WorkspaceAttachment workspace,
    required TaskAggregate snapshot,
    required String answer,
  });
}

abstract interface class TaskRecoveryPort {
  Future<TaskAggregate> recoverTask({
    required WorkspaceAttachment workspace,
    required TaskAggregate snapshot,
    bool persist = true,
  });
}
