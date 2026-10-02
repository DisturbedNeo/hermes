import 'package:hermes/core/cancellation.dart';
import 'package:hermes/features/model/application/model_output.dart';
import 'package:hermes/features/model/application/model_capabilities.dart';
import 'package:hermes/features/task/application/contracts/task_commands.dart';
import 'package:hermes/features/task/application/contracts/task_planning_models.dart';
import 'package:hermes/features/task/application/contracts/task_snapshot_models.dart';
import 'package:hermes/features/task/application/contracts/task_summary.dart';
import 'package:hermes/features/task/application/task_application/task_ports.dart';
import 'package:hermes/features/task/application/task_application/task_workflow_port.dart';
import 'package:hermes/features/workspace/application/workspace.dart';

/// Bridges the pre-migration aggregate-shaped task ports at the owning
/// feature boundary. Chat and other consumers receive only workflow results.
class TaskWorkflowCompatibilityAdapter implements TaskWorkflowPort {
  const TaskWorkflowCompatibilityAdapter({
    required TaskAggregateQueryPort queries,
    required TaskPlanningPort planning,
    required TaskProjectPlanningPort projectPlanning,
    required TaskExecutionPort execution,
    required TaskRecoveryPort recovery,
  }) : _queries = queries,
       _planning = planning,
       _projectPlanning = projectPlanning,
       _execution = execution,
       _recovery = recovery;

  final TaskAggregateQueryPort _queries;
  final TaskPlanningPort _planning;
  final TaskProjectPlanningPort _projectPlanning;
  final TaskExecutionPort _execution;
  final TaskRecoveryPort _recovery;

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

  Future<Task> _load(WorkspaceAttachment workspace, String taskId) async {
    final task = await _queries.loadTask(workspace, taskId);
    if (task == null) throw StateError('Task $taskId could not be loaded.');
    return task;
  }

  @override
  Future<RefinedTaskBrief> refineTaskBrief({
    required ModelGenerationPort client,
    WorkspaceAttachment? workspace,
    required String userPrompt,
    ExecutionMode selectedMode = ExecutionMode.refine,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) => _planning.refineTaskBrief(
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
    await _planning.createTask(
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
    await _projectPlanning.createProjectTask(
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
    await _planning.updateTaskPlan(
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
    await _planning.replanUnfinished(
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
        await _execution.runNextStep(
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
    await _execution.approvePendingStep(
      workspace: workspace,
      snapshot: await _load(workspace, taskId),
    ),
  );

  @override
  Future<TaskWorkflowResult> retryCurrentStep({
    required WorkspaceAttachment workspace,
    required String taskId,
  }) async => _result(
    await _execution.retryCurrentStep(
      workspace: workspace,
      snapshot: await _load(workspace, taskId),
    ),
  );

  @override
  Future<TaskWorkflowResult> skipCurrentStep({
    required WorkspaceAttachment workspace,
    required String taskId,
  }) async => _result(
    await _execution.skipCurrentStep(
      workspace: workspace,
      snapshot: await _load(workspace, taskId),
    ),
  );

  @override
  Future<TaskWorkflowResult> stopTask({
    required WorkspaceAttachment workspace,
    required String taskId,
  }) async => _result(
    await _execution.stopTask(
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
    await _execution.answerOpenQuestion(
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
    await _recovery.recoverTask(
      workspace: workspace,
      snapshot: await _load(workspace, taskId),
      persist: persist,
    ),
  );
}

TaskWorkflowPort adaptTaskWorkflowDependencies({
  required Object planning,
  required Object execution,
  required Object recovery,
}) {
  if (planning is TaskWorkflowPort &&
      execution is TaskWorkflowPort &&
      recovery is TaskWorkflowPort) {
    return planning;
  }
  if (planning is TaskPlanningPort &&
      planning is TaskProjectPlanningPort &&
      planning is TaskAggregateQueryPort &&
      execution is TaskExecutionPort &&
      recovery is TaskRecoveryPort) {
    final queryOwner = planning as TaskAggregateQueryPort;
    final projectPlanningOwner = planning as TaskProjectPlanningPort;
    return TaskWorkflowCompatibilityAdapter(
      queries: queryOwner,
      planning: planning,
      projectPlanning: projectPlanningOwner,
      execution: execution,
      recovery: recovery,
    );
  }
  throw ArgumentError('Unsupported task workflow dependency set.');
}
