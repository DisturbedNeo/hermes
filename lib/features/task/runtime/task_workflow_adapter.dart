import 'package:hermes/core/cancellation.dart';
import 'package:hermes/features/model/application/model_capabilities.dart';
import 'package:hermes/features/model/application/model_output.dart';
import 'package:hermes/features/task/application/contracts/task_commands.dart';
import 'package:hermes/features/task/application/contracts/task_planning_models.dart';
import 'package:hermes/features/task/application/contracts/task_summary.dart';
import 'package:hermes/features/task/application/contracts/task_snapshot_models.dart';
import 'package:hermes/features/task/application/task_application/task_workflow_port.dart';
import 'package:hermes/features/task/domain/task.dart';
import 'package:hermes/features/task/runtime/task_runtime_engine.dart';
import 'package:hermes/features/workspace/application/workspace.dart';

/// Converts the owner-internal task runtime into the aggregate-free workflow
/// capability used by chat and other feature consumers.
class TaskWorkflowAdapter implements TaskWorkflowPort {
  const TaskWorkflowAdapter({required TaskRuntimeController delegate})
    : _delegate = delegate;

  final TaskRuntimeController _delegate;

  Future<Task> _load(WorkspaceAttachment workspace, String taskId) async {
    final task = await _delegate.loadTask(workspace, taskId);
    if (task == null) throw StateError('Task $taskId could not be loaded.');
    return task;
  }

  TaskSummary _summary(Task task) => TaskSummary(
    id: task.id,
    title: task.title,
    status: task.status,
    updatedAt: task.updatedAt,
    currentPhaseId: task.currentStepId,
    chatSessionId: task.chatSessionId,
    projectId: task.projectId,
  );

  TaskWorkflowResult _result(Task task) =>
      TaskWorkflowResult(task: _summary(task));

  @override
  Future<RefinedTaskBrief> refineTaskBrief({
    required ModelGenerationPort client,
    WorkspaceAttachment? workspace,
    required String userPrompt,
    ExecutionMode selectedMode = ExecutionMode.refine,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) => _delegate.refineTaskBrief(
    client: client,
    workspace: workspace,
    userPrompt: userPrompt,
    selectedMode: selectedMode,
    onModelOutput: onModelOutput,
    cancellationToken: cancellationToken,
  );

  @override
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
  }) async => _result(
    await _delegate.createTask(
      client: client,
      workspace: workspace,
      userPrompt: userPrompt,
      selectedMode: selectedMode,
      baseSystemPrompt: baseSystemPrompt,
      chatSessionId: chatSessionId,
      projectId: projectId,
      canonicalTaskId: canonicalTaskId,
      planningContext: planningContext,
      onModelOutput: onModelOutput,
      cancellationToken: cancellationToken,
    ),
  );

  @override
  Future<TaskWorkflowResult> createProjectTask({
    required WorkspaceAttachment workspace,
    required String userPrompt,
    required String? chatSessionId,
    required String? projectId,
    required TaskPlanningContext planningContext,
    String? canonicalTaskId,
  }) async => _result(
    await _delegate.createProjectTask(
      workspace: workspace,
      userPrompt: userPrompt,
      chatSessionId: chatSessionId,
      projectId: projectId,
      planningContext: planningContext,
      canonicalTaskId: canonicalTaskId,
    ),
  );

  @override
  Future<TaskWorkflowResult> updateTaskPlan({
    required WorkspaceAttachment workspace,
    required String taskId,
    required TaskPlanUpdateCommand command,
  }) async => _result(
    await _delegate.updateTaskPlan(
      workspace: workspace,
      snapshot: await _load(workspace, taskId),
      command: command,
    ),
  );

  @override
  Future<TaskWorkflowResult> replanUnfinished({
    required ModelGenerationPort client,
    required WorkspaceAttachment workspace,
    required String taskId,
    required String baseSystemPrompt,
    String reason = 'User requested a replan of unfinished work.',
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async => _result(
    await _delegate.replanUnfinished(
      client: client,
      workspace: workspace,
      snapshot: await _load(workspace, taskId),
      baseSystemPrompt: baseSystemPrompt,
      reason: reason,
      onModelOutput: onModelOutput,
      cancellationToken: cancellationToken,
    ),
  );

  @override
  Future<TaskWorkflowResult> runNextStep(TaskWorkflowExecution request) async =>
      _result(
        await _delegate.runNextStep(
          client: request.client,
          workspace: request.workspace,
          snapshot: await _load(request.workspace, request.taskId),
          baseSystemPrompt: request.baseSystemPrompt,
          requirePhaseApproval: request.requirePhaseApproval,
          compactionSettings: request.compactionSettings,
          contextLimitTokens: request.contextLimitTokens,
          onCompactionStatus: request.onCompactionStatus,
          onModelOutput: request.onModelOutput,
          cancellationToken: request.cancellationToken,
          questionAutonomy: request.questionAutonomy,
          persist: request.persist,
        ),
      );

  @override
  Future<TaskWorkflowResult> approvePendingStep({
    required WorkspaceAttachment workspace,
    required String taskId,
  }) async => _result(
    await _delegate.approvePendingStep(
      workspace: workspace,
      snapshot: await _load(workspace, taskId),
    ),
  );

  @override
  Future<TaskWorkflowResult> retryCurrentStep({
    required WorkspaceAttachment workspace,
    required String taskId,
  }) async => _result(
    await _delegate.retryCurrentStep(
      workspace: workspace,
      snapshot: await _load(workspace, taskId),
    ),
  );

  @override
  Future<TaskWorkflowResult> skipCurrentStep({
    required WorkspaceAttachment workspace,
    required String taskId,
  }) async => _result(
    await _delegate.skipCurrentStep(
      workspace: workspace,
      snapshot: await _load(workspace, taskId),
    ),
  );

  @override
  Future<TaskWorkflowResult> stopTask({
    required WorkspaceAttachment workspace,
    required String taskId,
  }) async => _result(
    await _delegate.stopTask(
      workspace: workspace,
      snapshot: await _load(workspace, taskId),
    ),
  );

  @override
  Future<TaskWorkflowResult> answerOpenQuestion({
    required WorkspaceAttachment workspace,
    required String taskId,
    required String answer,
  }) async => _result(
    await _delegate.answerOpenQuestion(
      workspace: workspace,
      snapshot: await _load(workspace, taskId),
      answer: answer,
    ),
  );

  @override
  Future<TaskWorkflowResult> recoverTask({
    required WorkspaceAttachment workspace,
    required String taskId,
    bool persist = true,
  }) async => _result(
    await _delegate.recoverTask(
      workspace: workspace,
      snapshot: await _load(workspace, taskId),
      persist: persist,
    ),
  );
}
