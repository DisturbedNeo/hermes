import 'package:hermes/features/task/domain/task.dart';
import 'package:hermes/features/workspace/domain/workspace.dart';
import 'package:hermes/shared_kernel/model_runtime_port.dart';
import 'package:hermes/features/task/domain/task_summary.dart';
import 'package:hermes/shared_kernel/tool_contracts.dart';

export 'package:hermes/features/task/task_runtime_contracts.dart';

/// Read-only task queries consumed by feature orchestration.
abstract interface class TaskQueryPort {
  Future<List<TaskSummary>> listTasks(
    WorkspaceAttachment workspace, {
    String? chatSessionId,
    String? projectId,
  });

  Future<TaskAggregate?> loadTask(
    WorkspaceAttachment workspace,
    String taskId, {
    String? chatSessionId,
    String? projectId,
  });
}

/// Task planning operations exposed to application collaborators.
abstract interface class TaskPlanningPort {
  Future<TaskAggregate> createTask({
    required ModelRuntimePort model,
    required WorkspaceAttachment workspace,
    required String userPrompt,
  });

  Future<TaskAggregate> updateTaskPlan({
    required WorkspaceAttachment workspace,
    required TaskAggregate task,
    required String rawJson,
  });
}

/// Task execution operations exposed to application collaborators.
abstract interface class TaskExecutionPort {
  Future<TaskAggregate> runNextStep({
    required ModelRuntimePort model,
    required WorkspaceAttachment workspace,
    required TaskAggregate task,
  });
}

/// Task recovery operations exposed to application collaborators.
abstract interface class TaskRecoveryPort {
  Future<TaskAggregate> recoverTask({
    required WorkspaceAttachment workspace,
    required TaskAggregate task,
  });
}

/// Typed tool access available to task use cases.
abstract interface class TaskToolPort {
  ToolRegistryPort get tools;
}
