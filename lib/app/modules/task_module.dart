import 'dart:convert';

import 'package:hermes/features/task/application/protocol/planning_runtime.dart';
import 'package:hermes/features/task/application/protocol/planning_structured_output.dart';
import 'package:hermes/features/task/application/contracts/question_policy_service.dart';
import 'package:hermes/features/task/application/task_application/task_controller.dart';
import 'package:hermes/features/task/runtime/task_command_service.dart';
import 'package:hermes/features/task/runtime/task_gate_evaluator.dart';
import 'package:hermes/features/task/runtime/task_model_completion_service.dart';
import 'package:hermes/features/task/runtime/task_persistence_store.dart';
import 'package:hermes/features/task/runtime/task_planning_coordinator.dart';
import 'package:hermes/features/task/runtime/task_planning_service.dart';
import 'package:hermes/features/task/runtime/task_recovery_service.dart';
import 'package:hermes/features/task/runtime/task_step_execution_runtime.dart';
import 'package:hermes/features/task/runtime/task_step_runner.dart';
import 'package:hermes/features/task/runtime/task_tool_execution_service.dart';
import 'package:hermes/features/task/runtime/task_view_service.dart';
import 'package:hermes/platform/yaml_document_validator.dart';
import 'package:hermes/app/modules/persistence_module.dart';
import 'package:hermes/app/modules/workspace_tools_module.dart';

/// Task planning, step execution, recovery, and persistence capabilities.
class TaskModule {
  TaskModule._({required this.controller});

  factory TaskModule.create({
    required PersistenceModule persistence,
    required WorkspaceToolsModule workspace,
  }) {
    const planningRunner = PlanningToolCallRunner();
    const structuredOutput = StructuredPlanningOutputService();
    const planner = TaskPlanningService(runner: planningRunner);
    final planningCoordinator = TaskPlanningCoordinator(planner: planner);
    const recovery = TaskRecoveryService();
    final modelCompletion = TaskModelCompletionService(
      structuredOutput: structuredOutput,
    );
    final toolExecution = TaskToolExecutionService(
      protocol: workspace.toolProtocol,
      sandbox: workspace.sandbox,
    );
    final persistenceStore = TaskPersistenceStore(
      persistence: persistence.tasks,
    );
    final dependencies = TaskRuntimeDependencies(
      toolService: workspace.tools,
      sandbox: workspace.sandbox,
      planningCoordinator: planningCoordinator,
      persistenceStore: persistenceStore,
      profileService: workspace.discovery,
      gateEvaluator: TaskGateEvaluator(
        sandbox: workspace.sandbox,
        yamlValidator: const YamlDocumentValidator(),
      ),
      recoveryService: recovery,
      modelCompletion: modelCompletion,
      toolExecution: toolExecution,
      commandService: TaskCommandService(persistence: persistenceStore),
      stepRunner: TaskStepRunner(
        persistence: persistenceStore,
        recovery: recovery,
      ),
      taskViewService: const TaskViewService(),
      questionPolicy: const QuestionPolicyService(),
      encoder: const JsonEncoder.withIndent('  '),
    );
    return TaskModule._(controller: TaskController(dependencies: dependencies));
  }

  final TaskController controller;
}
