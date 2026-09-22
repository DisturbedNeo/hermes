import 'package:hermes/core/models/planning_metrics.dart';
import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/services/cancellation_token.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/planning_runtime.dart';
import 'package:hermes/core/services/task_system/task_model_output.dart';
import 'package:hermes/core/services/task_system/task_planning_tools.dart';

class TaskPlanningResult {
  final Task? task;
  final bool committed;
  final PlanningMetrics planningMetrics;
  final int modelCalls;
  final String? error;

  const TaskPlanningResult({
    this.task,
    this.committed = false,
    this.planningMetrics = const PlanningMetrics(),
    this.modelCalls = 0,
    this.error,
  });
}

/// Domain adapter for task planning. It owns no repository and only mutates
/// the in-memory [TaskPlanningToolContext] supplied for one planning session.
abstract interface class TaskPlanner {
  Future<TaskPlanningResult> plan({
    required ChatClient client,
    required TaskPlanningToolContext context,
    required String label,
    required String system,
    required String user,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  });

  Future<TaskPlanningResult> replan({
    required ChatClient client,
    required TaskPlanningToolContext context,
    required String label,
    required String system,
    required String user,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  });
}

class TaskPlanningService implements TaskPlanner {
  const TaskPlanningService({
    this.runner = const PlanningToolCallRunner(),
  });

  final PlanningToolCallRunner runner;

  @override
  Future<TaskPlanningResult> plan({
    required ChatClient client,
    required TaskPlanningToolContext context,
    required String label,
    required String system,
    required String user,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) => _run(
    client: client,
    context: context,
    label: label,
    system: system,
    user: user,
    onModelOutput: onModelOutput,
    cancellationToken: cancellationToken,
  );

  @override
  Future<TaskPlanningResult> replan({
    required ChatClient client,
    required TaskPlanningToolContext context,
    required String label,
    required String system,
    required String user,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) => _run(
    client: client,
    context: context,
    label: label,
    system: system,
    user: user,
    onModelOutput: onModelOutput,
    cancellationToken: cancellationToken,
  );

  Future<TaskPlanningResult> _run({
    required ChatClient client,
    required TaskPlanningToolContext context,
    required String label,
    required String system,
    required String user,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    final registry = TaskPlanningToolRegistry(context: context);
    final result = await runner.complete(
      PlanningRunRequest(
        client: client,
        registry: registry,
        label: label,
        system: system,
        user: user,
        onModelOutput: onModelOutput,
        cancellationToken: cancellationToken,
      ),
    );
    return TaskPlanningResult(
      task: context.committedTask,
      committed: result.committed && context.committedTask != null,
      planningMetrics: result.planningMetrics,
      modelCalls: result.modelCalls,
      error: result.ok ? null : result.message ?? result.code,
    );
  }
}
