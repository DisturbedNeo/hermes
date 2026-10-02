import 'package:hermes/features/task/domain/task.dart';
import 'package:hermes/features/workspace/application/workspace.dart';
import 'package:hermes/core/cancellation.dart';
import 'package:hermes/features/task/runtime/task_persistence_store.dart';
import 'package:hermes/features/task/runtime/task_recovery_service.dart';

typedef TaskStepExecution =
    Future<TaskAggregate> Function(TaskAggregate recoveredSnapshot);

/// Prepares one task step for execution and hands it to the execution engine.
///
/// Recovery is intentionally performed before the model/tool runner is
/// entered. That guarantees an interrupted `running` snapshot is converted
/// and checkpointed consistently for every caller.
class TaskStepRunner {
  const TaskStepRunner({
    required TaskPersistenceStore persistence,
    required TaskRecoveryService recovery,
  }) : _persistence = persistence,
       _recovery = recovery;

  final TaskPersistenceStore _persistence;
  final TaskRecoveryService _recovery;

  Future<TaskAggregate> run({
    required WorkspaceAttachment workspace,
    required TaskAggregate snapshot,
    required TaskStepExecution execute,
    CancellationToken? cancellationToken,
    bool persist = true,
  }) async {
    cancellationToken?.throwIfCancelled();
    final recovered = _recovery.recover(snapshot);
    final working =
        recovered.status == snapshot.status && identical(recovered, snapshot)
        ? snapshot
        : persist
        ? (await _persistence.save(workspace.rootPath, recovered)).value
        : recovered;
    cancellationToken?.throwIfCancelled();
    return execute(working);
  }
}
