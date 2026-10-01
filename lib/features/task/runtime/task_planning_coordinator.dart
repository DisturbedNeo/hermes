import 'package:hermes/core/cancellation.dart';
import 'package:hermes/features/model/application/model_completion_port.dart';
import 'package:hermes/features/model/application/model_output.dart';
import 'package:hermes/features/task/runtime/task_planning_service.dart';
import 'package:hermes/features/task/runtime/task_planning_tools.dart';

abstract interface class TaskPlanningCoordinatorPort {
  Future<TaskPlanningResult> plan({
    required ModelCompletionPort client,
    required TaskPlanningToolContext context,
    required String label,
    required String system,
    required String user,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  });

  Future<TaskPlanningResult> replan({
    required ModelCompletionPort client,
    required TaskPlanningToolContext context,
    required String label,
    required String system,
    required String user,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  });
}

/// Coordinates one task planning/replanning pass and owns its cancellation
/// boundary. The model-backed planner remains replaceable behind the small
/// port, while task persistence and execution stay outside this component.
class TaskPlanningCoordinator implements TaskPlanningCoordinatorPort {
  const TaskPlanningCoordinator({
    TaskPlanner planner = const TaskPlanningService(),
  }) : _planner = planner;

  final TaskPlanner _planner;

  @override
  Future<TaskPlanningResult> plan({
    required ModelCompletionPort client,
    required TaskPlanningToolContext context,
    required String label,
    required String system,
    required String user,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) {
    cancellationToken?.throwIfCancelled();
    return _planner.plan(
      client: client,
      context: context,
      label: label,
      system: system,
      user: user,
      onModelOutput: onModelOutput,
      cancellationToken: cancellationToken,
    );
  }

  @override
  Future<TaskPlanningResult> replan({
    required ModelCompletionPort client,
    required TaskPlanningToolContext context,
    required String label,
    required String system,
    required String user,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) {
    cancellationToken?.throwIfCancelled();
    return _planner.replan(
      client: client,
      context: context,
      label: label,
      system: system,
      user: user,
      onModelOutput: onModelOutput,
      cancellationToken: cancellationToken,
    );
  }
}
