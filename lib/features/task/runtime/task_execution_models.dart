import 'dart:convert';

import 'package:hermes/core/sentinel.dart' show kSentinel, resolve;
import 'package:hermes/features/task/application/contracts/planning_metrics.dart';
import 'package:hermes/features/task/application/contracts/question_policy_service.dart';
import 'package:hermes/features/task/application/contracts/task_snapshot_models.dart';
import 'package:hermes/features/task/domain/task.dart';
import 'package:hermes/features/task/runtime/task_command_service.dart';
import 'package:hermes/features/task/runtime/task_gate_evaluator.dart';
import 'package:hermes/features/task/runtime/task_model_completion_service.dart';
import 'package:hermes/features/task/runtime/task_persistence_store.dart';
import 'package:hermes/features/task/runtime/task_planning_coordinator.dart';
import 'package:hermes/features/task/runtime/task_recovery_service.dart';
import 'package:hermes/features/task/runtime/task_step_runner.dart';
import 'package:hermes/features/task/runtime/task_tool_execution_service.dart';
import 'package:hermes/features/task/runtime/task_view_service.dart';
import 'package:hermes/features/tools/application/tool_contracts.dart';
import 'package:hermes/features/workspace/application/workspace_discovery.dart';
import 'package:hermes/features/workspace/application/workspace_ports.dart';

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

enum TaskStepExecutionStatus { completed, blocked, needsReplan, failed }

class TaskStepExecutionOutput {
  final TaskStepExecutionStatus status;
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

  const TaskStepExecutionOutput({
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

  TaskStepExecutionOutput copyWith({
    TaskStepExecutionStatus? status,
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
  }) => TaskStepExecutionOutput(
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

class TaskTerminalToolCallResult {
  final String resultJson;
  final String finalContent;
  final TaskStepExecutionOutput output;
  final String? error;

  const TaskTerminalToolCallResult({
    required this.resultJson,
    required this.finalContent,
    required this.output,
    this.error,
  });
}

class TaskIncrementalPlanAttempt {
  final Task? task;
  final bool usedPlanningTools;
  final PlanningMetrics planningMetrics;
  final String? planningError;

  const TaskIncrementalPlanAttempt({
    this.task,
    this.usedPlanningTools = false,
    this.planningMetrics = const PlanningMetrics(),
    this.planningError,
  });
}
