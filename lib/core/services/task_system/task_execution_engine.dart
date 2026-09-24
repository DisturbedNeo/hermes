import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/cancellation_token.dart';
import 'package:hermes/core/services/task_system/task_step_runner.dart';

/// Application boundary for executing one task step.
///
/// The engine owns the step-runner lifecycle and exposes the model/tool-heavy
/// implementation as an injected callback. This keeps recovery/checkpoint
/// policy replaceable without duplicating the safety-sensitive executor.
class TaskExecutionEngine {
  TaskExecutionEngine({required TaskStepRunner stepRunner})
    : _stepRunner = stepRunner;

  final TaskStepRunner _stepRunner;

  Future<Task> runNextStep({
    required WorkspaceAttachment workspace,
    required Task snapshot,
    required TaskStepExecution execute,
    CancellationToken? cancellationToken,
    bool persist = true,
  }) => _stepRunner.run(
    workspace: workspace,
    snapshot: snapshot,
    cancellationToken: cancellationToken,
    persist: persist,
    execute: execute,
  );
}
