import 'dart:async';

import 'package:hermes/features/task/application/task_application/task_ports.dart';
import 'package:hermes/features/task/application/contracts/task_commands.dart';
import 'package:hermes/core/contracts/model_conversation.dart';
import 'package:hermes/features/task/domain/task.dart';
import 'package:hermes/features/task/application/contracts/task_planning_models.dart';
import 'package:hermes/core/contracts/execution_settings.dart';
import 'package:hermes/features/workspace/application/workspace.dart';
import 'package:hermes/features/model/application/model_completion_port.dart';
import 'package:hermes/core/cancellation.dart';
import 'package:hermes/features/model/application/model_output.dart';
import 'package:hermes/features/task/application/contracts/task_summary.dart';

import 'package:hermes/features/task/runtime/task_step_execution_runtime.dart';

class TaskRuntimeController
    implements
        TaskWorkflowQueryPort,
        TaskSessionPort,
        TaskPresentationPort,
        TaskPlanningPort,
        TaskProjectPlanningPort,
        TaskExecutionPort,
        TaskRecoveryPort {
  TaskRuntimeController({required TaskRuntimeDependencies dependencies})
    : _delegate = TaskStepExecutionRuntime(dependencies: dependencies);

  final TaskStepExecutionRuntime _delegate;

  @override
  Future<List<TaskSummary>> listTasks(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
    String? projectId,
  }) => _delegate.listTasks(
    workspace,
    chatSessionId: chatSessionId,
    projectId: projectId,
  );

  @override
  Future<Task?> loadLatestTask(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
    String? projectId,
  }) => _delegate.loadLatestTask(
    workspace,
    chatSessionId: chatSessionId,
    projectId: projectId,
  );

  @override
  Future<Task?> loadTask(
    WorkspaceAttachment workspace,
    String taskId, {
    String? chatSessionId,
    String? projectId,
    bool includeHistory = true,
  }) => _delegate.loadTask(
    workspace,
    taskId,
    chatSessionId: chatSessionId,
    projectId: projectId,
    includeHistory: includeHistory,
  );

  @override
  Future<int> deleteTasksForChatSession(
    WorkspaceAttachment workspace, {
    required String chatSessionId,
  }) => _delegate.deleteTasksForChatSession(
    workspace,
    chatSessionId: chatSessionId,
  );

  @override
  Future<int> deleteOrphanedChatTasks(
    WorkspaceAttachment workspace, {
    required Set<String> retainedChatSessionIds,
  }) => _delegate.deleteOrphanedChatTasks(
    workspace,
    retainedChatSessionIds: retainedChatSessionIds,
  );

  @override
  Future<void> updateTaskChatSessionId({
    required WorkspaceAttachment workspace,
    required String taskId,
    required String sourceChatSessionId,
    required String chatSessionId,
  }) => _delegate.updateTaskChatSessionId(
    workspace: workspace,
    taskId: taskId,
    sourceChatSessionId: sourceChatSessionId,
    chatSessionId: chatSessionId,
  );

  @override
  Future<Task> recoverTask({
    required WorkspaceAttachment workspace,
    required Task snapshot,
    bool persist = true,
  }) => _delegate.recoverTask(
    workspace: workspace,
    snapshot: snapshot,
    persist: persist,
  );

  @override
  @override
  Future<String> readArtifact({
    required WorkspaceAttachment workspace,
    required String artifactPath,
    CancellationToken? cancellationToken,
  }) => _delegate.readArtifact(
    workspace: workspace,
    artifactPath: artifactPath,
    cancellationToken: cancellationToken,
  );

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
  Future<Task> createTask({
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
  }) => _delegate.createTask(
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
  );

  @override
  Future<Task> createProjectTask({
    required WorkspaceAttachment workspace,
    required String userPrompt,
    required String? chatSessionId,
    required String? projectId,
    required TaskPlanningContext planningContext,
    String? canonicalTaskId,
  }) => _delegate.createProjectTask(
    workspace: workspace,
    userPrompt: userPrompt,
    chatSessionId: chatSessionId,
    projectId: projectId,
    planningContext: planningContext,
    canonicalTaskId: canonicalTaskId,
  );

  @override
  Future<Task> updateTaskPlan({
    required WorkspaceAttachment workspace,
    required Task snapshot,
    required TaskPlanUpdateCommand command,
  }) => _delegate.updateTaskPlan(
    workspace: workspace,
    snapshot: snapshot,
    command: command,
  );

  @override
  Future<Task> runNextStep({
    required ModelConversationPort client,
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
  }) => _delegate.runNextStep(
    client: client,
    workspace: workspace,
    snapshot: snapshot,
    baseSystemPrompt: baseSystemPrompt,
    requirePhaseApproval: requirePhaseApproval,
    compactionSettings: compactionSettings,
    contextLimitTokens: contextLimitTokens,
    onCompactionStatus: onCompactionStatus,
    onModelOutput: onModelOutput,
    cancellationToken: cancellationToken,
    questionAutonomy: questionAutonomy,
    executionRequest: executionRequest,
    persist: persist,
  );

  @override
  Future<Task> approvePendingStep({
    required WorkspaceAttachment workspace,
    required Task snapshot,
  }) => _delegate.approvePendingStep(workspace: workspace, snapshot: snapshot);

  @override
  Future<Task> retryCurrentStep({
    required WorkspaceAttachment workspace,
    required Task snapshot,
  }) => _delegate.retryCurrentStep(workspace: workspace, snapshot: snapshot);

  @override
  Future<Task> skipCurrentStep({
    required WorkspaceAttachment workspace,
    required Task snapshot,
  }) => _delegate.skipCurrentStep(workspace: workspace, snapshot: snapshot);

  @override
  Future<Task> stopTask({
    required WorkspaceAttachment workspace,
    required Task snapshot,
  }) => _delegate.stopTask(workspace: workspace, snapshot: snapshot);

  @override
  Future<Task> answerOpenQuestion({
    required WorkspaceAttachment workspace,
    required Task snapshot,
    required String answer,
  }) => _delegate.answerOpenQuestion(
    workspace: workspace,
    snapshot: snapshot,
    answer: answer,
  );

  @override
  Future<Task> replanUnfinished({
    required ModelGenerationPort client,
    required WorkspaceAttachment workspace,
    required Task snapshot,
    required String baseSystemPrompt,
    String reason = 'User requested a replan of unfinished work.',
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) => _delegate.replanUnfinished(
    client: client,
    workspace: workspace,
    snapshot: snapshot,
    baseSystemPrompt: baseSystemPrompt,
    reason: reason,
    onModelOutput: onModelOutput,
    cancellationToken: cancellationToken,
  );
}
