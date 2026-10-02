library;

import 'package:hermes/features/task/runtime/task_execution_coordinator.dart';

export 'task_execution_coordinator.dart'
    show TaskRuntimeDependencies, TaskExecutionOperations;

/// Stable runtime facade retained for application and test callers.
///
/// Task execution responsibilities live in [TaskExecutionCoordinator] and its
/// typed planning, step-loop, gate, recovery, and persistence collaborators.
class TaskStepExecutionRuntime extends TaskExecutionCoordinator {
  TaskStepExecutionRuntime({required super.dependencies});
}
