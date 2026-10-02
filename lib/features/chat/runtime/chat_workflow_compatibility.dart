import 'package:hermes/features/project/application/project_application/project_workflow_port.dart';
import 'package:hermes/features/project/application/project_application/project_workflow_compatibility_adapter.dart';
import 'package:hermes/features/task/application/task_application/task_workflow_port.dart';
import 'package:hermes/features/task/application/task_application/task_workflow_compatibility_adapter.dart';

/// Resolves the feature-facing workflow port while keeping the public chat
/// constructor source-compatible with the pre-migration runtime dependencies.
TaskWorkflowPort resolveTaskWorkflowPort(
  Object planning,
  Object execution,
  Object recovery,
) {
  if (planning is TaskWorkflowPort &&
      execution is TaskWorkflowPort &&
      recovery is TaskWorkflowPort) {
    return planning;
  }
  return adaptTaskWorkflowDependencies(
    planning: planning,
    execution: execution,
    recovery: recovery,
  );
}

/// Resolves the feature-facing project workflow port while preserving the
/// legacy application-facade constructor shape for existing embedders/tests.
ProjectWorkflowPort resolveProjectWorkflowPort(
  Object planning,
  Object commands,
  Object execution,
  Object recovery,
) {
  if (planning is ProjectWorkflowPort &&
      commands is ProjectWorkflowPort &&
      execution is ProjectWorkflowPort &&
      recovery is ProjectWorkflowPort) {
    return planning;
  }
  return adaptProjectWorkflowDependencies(
    planning: planning,
    commands: commands,
    execution: execution,
    recovery: recovery,
  );
}
