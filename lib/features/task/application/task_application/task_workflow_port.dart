import 'package:hermes/core/cancellation.dart';
import 'package:hermes/core/contracts/execution_settings.dart';
import 'package:hermes/core/contracts/model_conversation.dart';
import 'package:hermes/features/model/application/model_output.dart';
import 'package:hermes/features/model/application/model_capabilities.dart';
import 'package:hermes/features/task/application/contracts/task_commands.dart';
import 'package:hermes/features/task/application/contracts/task_planning_models.dart';
import 'package:hermes/features/task/application/contracts/task_snapshot_models.dart';
import 'package:hermes/features/task/application/contracts/task_summary.dart';
import 'package:hermes/features/workspace/application/workspace.dart';

class TaskWorkflowResult {
  const TaskWorkflowResult({required this.task});

  final TaskSummary task;
}

/// ID-based task execution request. Task hydration is owned by the task
/// runtime; callers exchange only the task identity and execution settings.
class TaskWorkflowExecution {
  const TaskWorkflowExecution({
    required this.client,
    required this.workspace,
    required this.taskId,
    required this.baseSystemPrompt,
    this.requirePhaseApproval = false,
    this.compactionSettings,
    this.contextLimitTokens,
    this.onCompactionStatus,
    this.onModelOutput,
    this.cancellationToken,
    this.questionAutonomy = QuestionAutonomy.balanced,
    this.persist = true,
  });

  final ModelConversationPort client;
  final WorkspaceAttachment workspace;
  final String taskId;
  final String baseSystemPrompt;
  final bool requirePhaseApproval;
  final CompactionSettings? compactionSettings;
  final int? contextLimitTokens;
  final void Function(String status)? onCompactionStatus;
  final ModelOutputSink? onModelOutput;
  final CancellationToken? cancellationToken;
  final QuestionAutonomy questionAutonomy;
  final bool persist;
}

abstract interface class TaskWorkflowPort {
  Future<RefinedTaskBrief> refineTaskBrief({
    required ModelGenerationPort client,
    WorkspaceAttachment? workspace,
    required String userPrompt,
    ExecutionMode selectedMode,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  });

  Future<TaskWorkflowResult> createTask({
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

  Future<TaskWorkflowResult> createProjectTask({
    required WorkspaceAttachment workspace,
    required String userPrompt,
    required String? chatSessionId,
    required String? projectId,
    required TaskPlanningContext planningContext,
    String? canonicalTaskId,
  });

  Future<TaskWorkflowResult> updateTaskPlan({
    required WorkspaceAttachment workspace,
    required String taskId,
    required TaskPlanUpdateCommand command,
  });

  Future<TaskWorkflowResult> replanUnfinished({
    required ModelGenerationPort client,
    required WorkspaceAttachment workspace,
    required String taskId,
    required String baseSystemPrompt,
    String reason,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  });

  Future<TaskWorkflowResult> runNextStep(TaskWorkflowExecution request);
  Future<TaskWorkflowResult> approvePendingStep({
    required WorkspaceAttachment workspace,
    required String taskId,
  });
  Future<TaskWorkflowResult> retryCurrentStep({
    required WorkspaceAttachment workspace,
    required String taskId,
  });
  Future<TaskWorkflowResult> skipCurrentStep({
    required WorkspaceAttachment workspace,
    required String taskId,
  });
  Future<TaskWorkflowResult> stopTask({
    required WorkspaceAttachment workspace,
    required String taskId,
  });
  Future<TaskWorkflowResult> answerOpenQuestion({
    required WorkspaceAttachment workspace,
    required String taskId,
    required String answer,
  });
  Future<TaskWorkflowResult> recoverTask({
    required WorkspaceAttachment workspace,
    required String taskId,
    bool persist,
  });
}
