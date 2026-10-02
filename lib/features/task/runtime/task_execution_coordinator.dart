library;

import 'dart:async';
import 'dart:convert';

import 'package:hermes/features/tools/application/protocol/tool_call_protocol_adapter.dart';
import 'package:hermes/features/tools/application/tool_protocol_adapter.dart';
import 'package:hermes/core/json_parsing.dart';
import 'package:hermes/core/sentinel.dart' show kSentinel, resolve;
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

part 'task_step_execution_loop.dart';
part 'task_execution_operations.dart';

// TaskStepExecutionRuntime

class TaskRuntimeDependencies {
  const TaskRuntimeDependencies({
    required this.toolService,
    required this.sandbox,
    required this.planningCoordinator,
    required this.persistenceStore,
    required this.profileService,
    required this.gateEvaluator,
    required this.recoveryService,
    required this.modelCompletion,
    required this.toolExecution,
    required this.commandService,
    required this.stepRunner,
    required this.taskViewService,
    required this.questionPolicy,
    required this.encoder,
  });

  final ToolRegistryPort toolService;
  final WorkspaceReadPort sandbox;
  final TaskPlanningCoordinatorPort planningCoordinator;
  final TaskPersistenceStore persistenceStore;
  final WorkspaceDiscoveryPort profileService;
  final TaskGateEvaluator gateEvaluator;
  final TaskRecoveryService recoveryService;
  final TaskModelCompletionPort modelCompletion;
  final TaskToolExecutionPort toolExecution;
  final TaskCommandService commandService;
  final TaskStepRunner stepRunner;
  final TaskViewService taskViewService;
  final QuestionPolicyService questionPolicy;
  final JsonEncoder encoder;
}

// Task execution operations

enum _StepExecutionStatus { completed, blocked, needsReplan, failed }

class _StepExecutionOutput {
  final _StepExecutionStatus status;
  final TaskRunStatus runStatus;
  final String summary;
  final String memoryUpdate;
  final List<TaskArtifact> artifacts;
  final List<TaskToolCallRecord> toolCalls;
  final List<TaskGateResult> gateResults;
  final List<TaskEvidenceClaim> evidenceClaims;
  final String? userQuestion;
  final AgentQuestion? agentQuestion;
  final String? replanRequest;
  final String? error;

  const _StepExecutionOutput({
    required this.status,
    required this.runStatus,
    required this.summary,
    required this.memoryUpdate,
    required this.artifacts,
    required this.toolCalls,
    this.gateResults = const [],
    this.evidenceClaims = const [],
    this.userQuestion,
    this.agentQuestion,
    this.replanRequest,
    this.error,
  });

  _StepExecutionOutput copyWith({
    _StepExecutionStatus? status,
    TaskRunStatus? runStatus,
    String? summary,
    String? memoryUpdate,
    List<TaskArtifact>? artifacts,
    List<TaskToolCallRecord>? toolCalls,
    List<TaskGateResult>? gateResults,
    List<TaskEvidenceClaim>? evidenceClaims,
    Object? userQuestion = kSentinel,
    Object? agentQuestion = kSentinel,
    Object? replanRequest = kSentinel,
    Object? error = kSentinel,
  }) {
    return _StepExecutionOutput(
      status: status ?? this.status,
      runStatus: runStatus ?? this.runStatus,
      summary: summary ?? this.summary,
      memoryUpdate: memoryUpdate ?? this.memoryUpdate,
      artifacts: artifacts ?? this.artifacts,
      toolCalls: toolCalls ?? this.toolCalls,
      gateResults: gateResults ?? this.gateResults,
      evidenceClaims: evidenceClaims ?? this.evidenceClaims,
      userQuestion: resolve(userQuestion, this.userQuestion),
      agentQuestion: resolve(agentQuestion, this.agentQuestion),
      replanRequest: resolve(replanRequest, this.replanRequest),
      error: resolve(error, this.error),
    );
  }
}

class _TaskTerminalToolCallResult {
  final String resultJson;
  final String finalContent;
  final _StepExecutionOutput output;
  final String? error;

  const _TaskTerminalToolCallResult({
    required this.resultJson,
    required this.finalContent,
    required this.output,
    this.error,
  });
}

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
is needed, optionally use task_set_brief, add one independently executable
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

// Task planning operations

class _IncrementalTaskPlanAttempt {
  final Task? task;
  final bool usedPlanningTools;
  final PlanningMetrics planningMetrics;
  final String? planningError;

  const _IncrementalTaskPlanAttempt({
    this.task,
    this.usedPlanningTools = false,
    this.planningMetrics = const PlanningMetrics(),
    this.planningError,
  });
}

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
    _stepLoop = _TaskStepExecutionLoop(
      toolService: _toolService,
      modelCompletion: _modelCompletion,
      toolExecution: _toolExecution,
      executionPolicy: _executionPolicy,
      encoder: _encoder,
      terminalToolCall: _terminalTaskToolCall,
      parseStepOutput: _parseStepOutput,
      persistenceStore: _persistenceStore,
      buildStepPrompt: _buildStepPrompt,
      structuredToolResult: _structuredToolResult,
      toolErrorInfoForCall: _toolErrorInfoForCall,
      toolCallOutcome: _toolCallOutcome,
      operationKey: _operationKey,
      cap: _cap,
    );
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
  late final _TaskStepExecutionLoop _stepLoop;
}
