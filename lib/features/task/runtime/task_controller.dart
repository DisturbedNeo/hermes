import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hermes/core/helpers/chat/tool_caller.dart';
import 'package:hermes/core/helpers/json_parsing.dart';
import 'package:hermes/core/helpers/sentinel.dart' show kSentinel, resolve;
import 'package:hermes/core/helpers/uuid.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/models/compaction_settings.dart';
import 'package:hermes/features/task/domain/task.dart';
import 'package:hermes/features/task/domain/task_planning_models.dart';
import 'package:hermes/core/models/planning_metrics.dart';
import 'package:hermes/shared_kernel/task_system_settings.dart';
import 'package:hermes/core/models/tool_definition.dart';
import 'package:hermes/features/workspace/domain/workspace.dart';
import 'package:hermes/features/model/domain/model_provider.dart';
import 'package:hermes/features/model/domain/model_completion.dart';
import 'package:hermes/features/model/domain/model_errors.dart';
import 'package:hermes/core/services/cancellation_token.dart';
import 'package:hermes/core/services/planning_structured_output.dart';
import 'package:hermes/core/services/question_policy_service.dart';
import 'package:hermes/core/services/sandbox_policy.dart';
import 'package:hermes/features/task/runtime/task_gate_evaluator.dart';
import 'package:hermes/features/task/runtime/task_json.dart';
import 'package:hermes/shared_kernel/model_output.dart';
import 'package:hermes/features/task/runtime/task_planning_tools.dart';
import 'package:hermes/features/task/runtime/task_planning_service.dart';
import 'package:hermes/features/task/runtime/task_planning_coordinator.dart';
import 'package:hermes/features/task/runtime/task_persistence_store.dart';
import 'package:hermes/features/task/runtime/task_command_service.dart';
import 'package:hermes/features/task/runtime/task_step_runner.dart';
import 'package:hermes/features/task/runtime/task_model_completion_service.dart';
import 'package:hermes/features/task/runtime/task_tool_execution_service.dart';
import 'package:hermes/features/task/runtime/task_recovery_service.dart';
import 'package:hermes/features/task/runtime/in_memory_task_repository.dart';
import 'package:hermes/features/task/domain/task_summary.dart';
import 'package:hermes/features/task/task_runtime_contracts.dart';
import 'package:hermes/features/task/runtime/task_view_service.dart';
import 'package:hermes/core/services/terminal_command_parser.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/core/services/workspace_sandbox.dart';
import 'package:hermes/core/services/workspace_discovery_profile.dart';
import 'package:hermes/core/serialization/model_json.dart';
import 'package:hermes/core/tools/tool_error.dart';
import 'package:path/path.dart' as path;

part 'task_context.dart';

part 'task_storage_operations.dart';

part 'task_planning_operations.dart';

part 'task_execution_operations.dart';

part 'task_state_operations.dart';

class TaskRuntimeController implements TaskApplicationPort {
  TaskRuntimeController({
    required ToolService toolService,
    required WorkspaceSandbox sandbox,
    TaskRepositoryPort? repository,
    TaskPersistenceStore? persistenceStore,
    TaskRecoveryService recoveryService = const TaskRecoveryService(),
    TaskPlanner planner = const TaskPlanningService(),
    TaskPlanningCoordinatorPort? planningCoordinator,
    TaskModelCompletionPort? modelCompletion,
    TaskToolExecutionPort? toolExecution,
    StructuredPlanningOutputService structuredOutput =
        const StructuredPlanningOutputService(),
    WorkspaceDiscoveryProfileService profileService =
        const WorkspaceDiscoveryProfileService(),
  }) : _delegate = _TaskApplicationContext(
         toolService: toolService,
         sandbox: sandbox,
         repository: repository,
         persistenceStore: persistenceStore,
         recoveryService: recoveryService,
         planner: planner,
         planningCoordinator: planningCoordinator,
         modelCompletion: modelCompletion,
         toolExecution: toolExecution,
         structuredOutput: structuredOutput,
         profileService: profileService,
       );

  final _TaskApplicationContext _delegate;

  @override
  TaskRepositoryPort get repository => _delegate.repository;

  @override
  ToolService get toolService => _delegate.toolService;

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
  Future<Task> updateTaskChatSessionId({
    required WorkspaceAttachment workspace,
    required Task snapshot,
    required String chatSessionId,
  }) => _delegate.updateTaskChatSessionId(
    workspace: workspace,
    snapshot: snapshot,
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
  String encodeTask(Task task) => _delegate.encodeTask(task);

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
    required ModelProvider client,
    WorkspaceAttachment? workspace,
    required String userPrompt,
    ExecutionMode selectedMode = ExecutionMode.refine,
    TaskModelOutputSink? onModelOutput,
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
    required String rawJson,
  }) => _delegate.updateTaskPlan(
    workspace: workspace,
    snapshot: snapshot,
    rawJson: rawJson,
  );

  @override
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
    required ModelProvider client,
    required WorkspaceAttachment workspace,
    required Task snapshot,
    required String baseSystemPrompt,
    String reason = 'User requested a replan of unfinished work.',
    TaskModelOutputSink? onModelOutput,
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
