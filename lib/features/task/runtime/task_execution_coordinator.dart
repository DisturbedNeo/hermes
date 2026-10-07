library;

import 'dart:async';
import 'dart:convert';

import 'package:hermes/features/tools/application/protocol/tool_call_protocol_adapter.dart';
import 'package:hermes/features/tools/application/tool_protocol_adapter.dart';
import 'package:hermes/core/json_parsing.dart';
import 'package:hermes/core/uuid.dart';
import 'package:hermes/core/contracts/model_conversation.dart';
import 'package:hermes/features/chat/application/protocol/chat_message_wire_adapter.dart';
import 'package:hermes/features/task/domain/task.dart';
import 'package:hermes/features/task/application/contracts/task_summary.dart';
import 'package:hermes/features/task/application/contracts/task_commands.dart';
import 'package:hermes/features/task/application/contracts/task_planning_models.dart';
import 'package:hermes/features/task/application/contracts/planning_metrics.dart';
import 'package:hermes/core/contracts/execution_settings.dart';
import 'package:hermes/features/tools/application/tool_contracts.dart';
import 'package:hermes/features/workspace/application/workspace.dart';
import 'package:hermes/features/model/application/model_completion_port.dart';
import 'package:hermes/features/model/application/model_completion.dart';
import 'package:hermes/features/model/application/model_errors.dart';
import 'package:hermes/core/cancellation.dart';
import 'package:hermes/features/task/application/contracts/question_policy_service.dart';
import 'package:hermes/features/task/application/protocol/question_protocol_adapter.dart';
import 'package:hermes/features/workspace/application/sandbox_policy.dart';
import 'package:hermes/features/task/runtime/task_gate_evaluator.dart';
import 'package:hermes/features/persistence/application/task_json.dart';
import 'package:hermes/features/model/application/model_output.dart';
import 'package:hermes/features/task/runtime/task_planning_tools.dart';
import 'package:hermes/features/task/runtime/task_planning_coordinator.dart';
import 'package:hermes/features/task/runtime/task_persistence_store.dart';
import 'package:hermes/features/task/runtime/task_command_service.dart';
import 'package:hermes/features/task/runtime/task_step_runner.dart';
import 'package:hermes/features/task/runtime/task_model_completion_service.dart';
import 'package:hermes/features/task/runtime/task_tool_execution_service.dart';
import 'package:hermes/features/task/runtime/task_recovery_service.dart';
import 'package:hermes/features/task/runtime/task_view_service.dart';
import 'package:hermes/features/task/runtime/task_execution_policy.dart';
import 'package:hermes/features/workspace/application/workspace_ports.dart';
import 'package:hermes/features/workspace/application/workspace_discovery.dart';
import 'package:hermes/core/model_json.dart';
import 'package:hermes/features/tools/application/protocol/tool_error.dart';
import 'package:path/path.dart' as path;
import 'package:hermes/features/task/runtime/task_execution_models.dart';

export 'task_execution_models.dart' show TaskRuntimeDependencies;

part 'task_step_execution_loop.dart';
part 'task_execution_operations.dart';
part 'task_execution_planning.dart';
part 'task_command_use_case.dart';
part 'task_persistence_use_case.dart';
part 'task_planning_use_case.dart';
part 'task_execution_use_case.dart';
part 'task_execution_context.dart';

const String _refinerSystemInstruction = '''
You refine user requests for a long-horizon AI task runner.
Do not perform the task.
Prefer useful assumptions over broad questioning.
Ask at most three questions.
Return only valid JSON.
''';

const String _executorSystemInstruction = '''
You execute one step of a larger linear task.
Use the full plan and memory to keep long-horizon context.
Complete only the current step.
Do not perform future steps early.
Use tools only when needed. When you have enough information, stop using tools and return the requested JSON.
Do not block on prioritization, naming, implementation order, minor layout/design choices, or other reversible preferences; choose a reasonable default, note the assumption, and continue.
Use task_request_user_decision for destructive or irreversible actions, credentials/secrets/accounts/API keys, legal/business/product requirement decisions, scope expansion, constraint conflicts, or high-cost ambiguity with no reasonable default.
You may read artifacts from completed prior steps and any artifact already created during the current step.
Write and report only artifacts declared on the current step.
If the current step needs a different artifact path, call task_request_replan instead of writing it.
If the current step is read-only, you may create only the current step's declared task-owned artifact files under `.agent/tasks/<taskId>/`, and you may run only whitelisted verification terminal commands exposed for the step. Invoke each whitelisted command with the exact command text and working directory shown in the step permissions. Do not add or remove arguments, flags, pipes, redirects, shell wrappers, or combined commands; any variation will be rejected and will not satisfy its command_passes gate. Attempt advisory verification commands when terminal execution is approved; their results are evidence even when they fail. You must not overwrite existing files, edit source files, rename paths, delete paths, or try to use other terminal commands as a workaround.
If a later step is responsible for writing a report or changing files, leave that work for the later step.
If the current plan is wrong or missing necessary follow-up work, call task_request_replan with a concrete reason.
If confirmed workspace evidence contradicts the refined project goal, active milestone, declared task paths, or planner memory, stop bounded diagnostic work and call task_request_replan with the concrete contradiction and affected plan element.
If user input is truly required, call task_request_user_decision with the question and context.
When done, call finish_task_step with only status and summary. Hermes derives artifact provenance from successful workspace calls, evaluates completion gates, and treats model-written evidence claims as advisory.
If finish_task_step is unavailable, return only the requested JSON object.
''';

const String _taskPlanningToolsSystemInstruction = '''
You create a compact linear task plan through explicit task planning tools.
Do not return a complete task JSON document. Start with task_view when context
is needed. The view is bounded; use navigation.pages and call task_view again
with section and next_cursor when a collection has more items. Optionally use
task_set_brief, add one independently executable
step at a time with task_add_step, attach exact verification commands with
task_add_check, and finish with task_commit_plan. If a validation error means
the current uncommitted draft must be replaced, use task_reset_plan first and
then rebuild the corrected draft with commands.

Hermes generates step, artifact, gate, evidence, question, and runtime IDs.
Never provide persistent IDs, statuses, timestamps, run history, fingerprints,
or completion fields. A tool error affects only that command; inspect the
returned error and retry the smallest correction.

Stay inside the task objective, done criteria, out-of-scope boundaries, and
declared read/write paths. Do not expand a bounded Project task to the whole
Project. Keep the number of steps within the supplied limit. Use
task_request_user_decision only for genuinely blocking irreversible choices,
credentials, scope conflicts, or high-cost ambiguity with no safe default.
Use task_request_replan when the current unfinished approach is demonstrably
wrong, and include a concrete reason. A successful task_commit_plan is the
only completion signal.
''';

const int _maxConsecutiveRepeatedToolCalls = 3;

const String _finishTaskStepToolId = 'finish_task_step';
const String _requestTaskUserDecisionToolId = 'task_request_user_decision';
const String _requestTaskReplanToolId = 'task_request_replan';

const ToolDefinition _finishTaskStepToolDefinition = ToolDefinition(
  id: _finishTaskStepToolId,
  name: 'Finish task step',
  description:
      'Finish the current task step with its observed status and a concise summary. Calling this ends the step; do not call workspace tools after it. Use the explicit question or replan tools for those outcomes.',
  schema: ToolSchema({
    'type': 'object',
    'properties': {
      'status': {
        'type': 'string',
        'enum': ['completed', 'failed'],
        'description':
            'Observed final status. Completion is still subject to Hermes gate evaluation.',
      },
      'summary': {
        'type': 'string',
        'description': 'Concise summary of what happened in this step.',
      },
    },
    'required': ['status', 'summary'],
  }),
);

const ToolDefinition _requestTaskUserDecisionToolDefinition = ToolDefinition(
  id: _requestTaskUserDecisionToolId,
  name: 'Request task user decision',
  description:
      'Pause the current task step and ask the user one genuinely blocking question. Calling this ends the step; do not call finish_task_step afterwards.',
  schema: ToolSchema({
    'type': 'object',
    'properties': {
      'question': {'type': 'string', 'description': 'The blocking question.'},
      'reason': {
        'type': 'string',
        'description': 'Why the task cannot safely continue without an answer.',
      },
      'defaultIfUnanswered': {
        'type': 'string',
        'description': 'Safe default, if one exists.',
      },
      'riskOfAssuming': {
        'type': 'string',
        'description': 'Risk of choosing the default without the user.',
      },
      'kind': {
        'type': 'string',
        'enum': ['blocking', 'preference', 'advisory'],
      },
    },
    'required': ['question'],
  }),
);

const ToolDefinition _requestTaskReplanToolDefinition = ToolDefinition(
  id: _requestTaskReplanToolId,
  name: 'Request task replan',
  description:
      'Stop the current task step and request a concrete replan when the current approach is wrong or incomplete. Calling this ends the step; do not call finish_task_step afterwards.',
  schema: ToolSchema({
    'type': 'object',
    'properties': {
      'reason': {
        'type': 'string',
        'description':
            'Concrete contradiction or missing work requiring a replan.',
      },
    },
    'required': ['reason'],
  }),
);

// Task state operations

// Task storage operations

class TaskExecutionCoordinator {
  TaskExecutionCoordinator({required TaskRuntimeDependencies dependencies})
    : _toolService = dependencies.toolService,
      _planningCoordinator = dependencies.planningCoordinator,
      _persistenceStore = dependencies.persistenceStore,
      _sandbox = dependencies.sandbox,
      _profileService = dependencies.profileService,
      _gateEvaluator = dependencies.gateEvaluator,
      _recoveryService = dependencies.recoveryService,
      _modelCompletion = dependencies.modelCompletion,
      _toolExecution = dependencies.toolExecution,
      _commandService = dependencies.commandService,
      _stepRunner = dependencies.stepRunner,
      _taskViewService = dependencies.taskViewService,
      _questionPolicy = dependencies.questionPolicy,
      _encoder = dependencies.encoder {
    _stepLoop = TaskStepExecutionLoop(
      toolService: _toolService,
      modelCompletion: _modelCompletion,
      toolExecution: _toolExecution,
      executionPolicy: _executionPolicy,
      encoder: _encoder,
      terminalToolCall:
          ({
            required String callName,
            required Object args,
            required TaskAggregate task,
            required TaskStep step,
            required List<TaskToolCallRecord> existingToolCalls,
            required TaskExecutionRequest executionRequest,
          }) => _executionUseCase._terminalTaskToolCall(
            callName: callName,
            args: args,
            task: task,
            step: step,
            existingToolCalls: existingToolCalls,
            executionRequest: executionRequest,
          ),
      parseStepOutput: (raw, task, step, toolCalls, executionRequest) =>
          _planningUseCase._parseStepOutput(
            raw,
            task,
            step,
            toolCalls,
            executionRequest,
          ),
      persistenceStore: _persistenceStore,
      buildStepPrompt: (task, step, workspace, executionRequest) =>
          _planningUseCase._buildStepPrompt(
            task,
            step,
            workspace,
            executionRequest,
          ),
      structuredToolResult: (toolName, resultJson) =>
          _planningUseCase._structuredToolResult(toolName, resultJson),
      toolErrorInfoForCall: (toolName, result) =>
          _planningUseCase._toolErrorInfoForCall(toolName, result),
      toolCallOutcome: (result, error) =>
          _planningUseCase._toolCallOutcome(result, error),
      operationKey: (toolName, rawArguments) =>
          _planningUseCase._operationKey(toolName, rawArguments),
      cap: (value, maxChars) => _planningUseCase._cap(value, maxChars),
    );
    late final Future<TaskAggregate> Function(String, TaskAggregate)
    persistTask;
    persistTask = (workspaceRoot, task) async {
      final persisted = await _persistenceStore.save(workspaceRoot, task);
      return persisted.value;
    };
    final useCaseContext = TaskUseCaseContext(
      toolService: _toolService,
      planningCoordinator: _planningCoordinator,
      persistenceStore: _persistenceStore,
      sandbox: _sandbox,
      profileService: _profileService,
      recoveryService: _recoveryService,
      gateEvaluator: _gateEvaluator,
      modelCompletion: _modelCompletion,
      toolExecution: _toolExecution,
      stepLoop: _stepLoop,
      stepRunner: _stepRunner,
      commandService: _commandService,
      taskViewService: _taskViewService,
      questionPolicy: _questionPolicy,
      encoder: _encoder,
      persistTask: persistTask,
      newTaskId: (prompt) => _planningUseCase._newTaskId(prompt),
      collectWorkspaceMetadata: (workspace, {String? chatSessionId}) =>
          _executionUseCase._collectWorkspaceMetadata(
            workspace,
            chatSessionId: chatSessionId,
          ),
      completeTaskPlanWithCommands:
          ({
            required client,
            required workspace,
            required baseSystemPrompt,
            required taskId,
            required userPrompt,
            required metadata,
            required planningContext,
            required now,
            required chatSessionId,
            required projectId,
            onModelOutput,
            cancellationToken,
          }) => _planningUseCase._completeTaskPlanWithCommands(
            client: client,
            workspace: workspace,
            baseSystemPrompt: baseSystemPrompt,
            taskId: taskId,
            userPrompt: userPrompt,
            metadata: metadata,
            planningContext: planningContext,
            now: now,
            chatSessionId: chatSessionId,
            projectId: projectId,
            onModelOutput: onModelOutput,
            cancellationToken: cancellationToken,
          ),
      fallbackTask:
          ({
            required taskId,
            required userPrompt,
            required chatSessionId,
            required projectId,
            required now,
          }) => _planningUseCase._fallbackTask(
            taskId: taskId,
            userPrompt: userPrompt,
            chatSessionId: chatSessionId,
            projectId: projectId,
            now: now,
          ),
      fallbackProjectBoundedTask:
          ({
            required taskId,
            required userPrompt,
            required chatSessionId,
            required projectId,
            required planningContext,
            required now,
          }) => _planningUseCase._fallbackProjectBoundedTask(
            taskId: taskId,
            userPrompt: userPrompt,
            chatSessionId: chatSessionId,
            projectId: projectId,
            planningContext: planningContext,
            now: now,
          ),
      normaliseEditedTask: (candidate, original, now) =>
          _planningUseCase._normaliseEditedTask(candidate, original, now),
      markCompleted: (snapshot) => _planningUseCase._markCompleted(snapshot),
      completeStep: (snapshot, step, output, now) =>
          _planningUseCase._completeStep(snapshot, step, output, now),
      blockStep: (snapshot, step, output, now) =>
          _planningUseCase._blockStep(snapshot, step, output, now),
      failStep: (snapshot, step, output, now) =>
          _planningUseCase._failStep(snapshot, step, output, now),
      replaceStep: (snapshot, stepId, step) =>
          _planningUseCase._replaceStep(snapshot, stepId, step),
      replaceLastRun: (snapshot, run) =>
          _planningUseCase._replaceLastRun(snapshot, run),
      appendMemory: (current, update) =>
          _planningUseCase._appendMemory(current, update),
      fallbackReplannedTask: (snapshot, reason, {required planningMetrics}) =>
          _planningUseCase._fallbackReplannedTask(
            snapshot,
            reason,
            planningMetrics: planningMetrics,
          ),
      taskPlanningStepLimit: (task) =>
          _planningUseCase._taskPlanningStepLimit(task),
      parseStepExecutionStatus: (raw) =>
          _planningUseCase._parseStepExecutionStatusStrict(raw),
      evidenceClaimsFromJson:
          (value, allowedCriterionIds, {expectedEvidence = const []}) =>
              _planningUseCase._evidenceClaimsFromJson(
                value,
                allowedCriterionIds,
                expectedEvidence: expectedEvidence,
              ),
      taskToolErrorJson:
          ({
            required code,
            required message,
            required disposition,
            details = const {},
          }) => _planningUseCase._taskToolErrorJson(
            code: code,
            message: message,
            disposition: disposition,
            details: details,
          ),
      normaliseBrief: (brief, prompt) =>
          _planningUseCase._normaliseBrief(brief, prompt),
      fallbackBrief: (prompt) => _planningUseCase._fallbackBrief(prompt),
    );
    _commandUseCase = TaskCommandUseCase(useCaseContext);
    _persistenceUseCase = TaskPersistenceUseCase(useCaseContext);
    _planningUseCase = TaskPlanningUseCase(useCaseContext);
    _executionUseCase = TaskExecutionUseCase(useCaseContext);
  }

  final ToolRegistryPort _toolService;
  final TaskPlanningCoordinatorPort _planningCoordinator;
  final TaskPersistenceStore _persistenceStore;
  final WorkspaceReadPort _sandbox;
  final WorkspaceDiscoveryPort _profileService;
  final TaskGateEvaluator _gateEvaluator;
  final TaskRecoveryService _recoveryService;
  final TaskModelCompletionPort _modelCompletion;
  final TaskToolExecutionPort _toolExecution;
  final TaskCommandService _commandService;
  final TaskStepRunner _stepRunner;
  final TaskViewService _taskViewService;
  final QuestionPolicyService _questionPolicy;
  final JsonEncoder _encoder;
  final TaskExecutionPolicy _executionPolicy = const TaskExecutionPolicy();
  late final TaskStepExecutionLoop _stepLoop;
  late final TaskCommandUseCase _commandUseCase;
  late final TaskPersistenceUseCase _persistenceUseCase;
  late final TaskPlanningUseCase _planningUseCase;
  late final TaskExecutionUseCase _executionUseCase;

  Future<TaskAggregate> approvePendingStep({
    required WorkspaceAttachment workspace,
    required TaskAggregate snapshot,
  }) => _commandUseCase.approvePendingStep(
    workspace: workspace,
    snapshot: snapshot,
  );

  Future<TaskAggregate> retryCurrentStep({
    required WorkspaceAttachment workspace,
    required TaskAggregate snapshot,
  }) => _commandUseCase.retryCurrentStep(
    workspace: workspace,
    snapshot: snapshot,
  );

  Future<TaskAggregate> skipCurrentStep({
    required WorkspaceAttachment workspace,
    required TaskAggregate snapshot,
  }) =>
      _commandUseCase.skipCurrentStep(workspace: workspace, snapshot: snapshot);

  Future<TaskAggregate> stopTask({
    required WorkspaceAttachment workspace,
    required TaskAggregate snapshot,
  }) => _commandUseCase.stopTask(workspace: workspace, snapshot: snapshot);

  Future<TaskAggregate> answerOpenQuestion({
    required WorkspaceAttachment workspace,
    required TaskAggregate snapshot,
    required String answer,
  }) => _commandUseCase.answerOpenQuestion(
    workspace: workspace,
    snapshot: snapshot,
    answer: answer,
  );

  Future<List<TaskSummary>> listTasks(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
    String? projectId,
  }) => _persistenceUseCase.listTasks(
    workspace,
    chatSessionId: chatSessionId,
    projectId: projectId,
  );

  Future<TaskAggregate?> loadLatestTask(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
    String? projectId,
  }) => _persistenceUseCase.loadLatestTask(
    workspace,
    chatSessionId: chatSessionId,
    projectId: projectId,
  );

  Future<TaskAggregate?> loadTask(
    WorkspaceAttachment workspace,
    String taskId, {
    String? chatSessionId,
    String? projectId,
    bool includeHistory = true,
  }) => _persistenceUseCase.loadTask(
    workspace,
    taskId,
    chatSessionId: chatSessionId,
    projectId: projectId,
    includeHistory: includeHistory,
  );

  Future<int> deleteTasksForChatSession(
    WorkspaceAttachment workspace, {
    required String chatSessionId,
  }) => _persistenceUseCase.deleteTasksForChatSession(
    workspace,
    chatSessionId: chatSessionId,
  );

  Future<int> deleteOrphanedChatTasks(
    WorkspaceAttachment workspace, {
    required Set<String> retainedChatSessionIds,
  }) => _persistenceUseCase.deleteOrphanedChatTasks(
    workspace,
    retainedChatSessionIds: retainedChatSessionIds,
  );

  Future<void> updateTaskChatSessionId({
    required WorkspaceAttachment workspace,
    required String taskId,
    required String sourceChatSessionId,
    required String chatSessionId,
  }) => _persistenceUseCase.updateTaskChatSessionId(
    workspace: workspace,
    taskId: taskId,
    sourceChatSessionId: sourceChatSessionId,
    chatSessionId: chatSessionId,
  );

  Future<TaskAggregate> recoverTask({
    required WorkspaceAttachment workspace,
    required TaskAggregate snapshot,
    bool persist = true,
  }) => _persistenceUseCase.recoverTask(
    workspace: workspace,
    snapshot: snapshot,
    persist: persist,
  );

  Future<String> readArtifact({
    required WorkspaceAttachment workspace,
    required String artifactPath,
    CancellationToken? cancellationToken,
  }) => _persistenceUseCase.readArtifact(
    workspace: workspace,
    artifactPath: artifactPath,
    cancellationToken: cancellationToken,
  );

  Future<RefinedTaskBrief> refineTaskBrief({
    required ModelGenerationPort client,
    WorkspaceAttachment? workspace,
    required String userPrompt,
    ExecutionMode selectedMode = ExecutionMode.refine,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) => _persistenceUseCase.refineTaskBrief(
    client: client,
    workspace: workspace,
    userPrompt: userPrompt,
    selectedMode: selectedMode,
    onModelOutput: onModelOutput,
    cancellationToken: cancellationToken,
  );

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
  }) => _planningUseCase.createTask(
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

  Future<TaskAggregate> createProjectTask({
    required WorkspaceAttachment workspace,
    required String userPrompt,
    required String? chatSessionId,
    required String? projectId,
    required TaskPlanningContext planningContext,
    String? canonicalTaskId,
  }) => _planningUseCase.createProjectTask(
    workspace: workspace,
    userPrompt: userPrompt,
    chatSessionId: chatSessionId,
    projectId: projectId,
    planningContext: planningContext,
    canonicalTaskId: canonicalTaskId,
  );

  Future<TaskAggregate> updateTaskPlan({
    required WorkspaceAttachment workspace,
    required TaskAggregate snapshot,
    required TaskPlanUpdateCommand command,
  }) => _planningUseCase.updateTaskPlan(
    workspace: workspace,
    snapshot: snapshot,
    command: command,
  );

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
  }) => _executionUseCase.runNextStep(
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

  Future<TaskAggregate> replanUnfinished({
    required ModelGenerationPort client,
    required WorkspaceAttachment workspace,
    required TaskAggregate snapshot,
    required String baseSystemPrompt,
    String reason = 'User requested a replan of unfinished work.',
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) => _executionUseCase.replanUnfinished(
    client: client,
    workspace: workspace,
    snapshot: snapshot,
    baseSystemPrompt: baseSystemPrompt,
    reason: reason,
    onModelOutput: onModelOutput,
    cancellationToken: cancellationToken,
  );
}
