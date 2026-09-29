import 'package:hermes/shared_kernel/cancellation.dart';
import 'package:hermes/shared_kernel/model_provider.dart';
import 'package:hermes/shared_kernel/model_output.dart';
import 'package:hermes/features/task/runtime/task_planning_service.dart';
import 'package:hermes/features/task/runtime/task_planning_tools.dart';

abstract interface class TaskPlanningCoordinatorPort {
  Future<TaskPlanningResult> plan({
    required ModelProvider client,
    required TaskPlanningToolContext context,
    required String label,
    required String system,
    required String user,
    TaskModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  });

  Future<TaskPlanningResult> replan({
    required ModelProvider client,
    required TaskPlanningToolContext context,
    required String label,
    required String system,
    required String user,
    TaskModelOutputSink? onModelOutput,
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
    required ModelProvider client,
    required TaskPlanningToolContext context,
    required String label,
    required String system,
    required String user,
    TaskModelOutputSink? onModelOutput,
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
    required ModelProvider client,
    required TaskPlanningToolContext context,
    required String label,
    required String system,
    required String user,
    TaskModelOutputSink? onModelOutput,
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
