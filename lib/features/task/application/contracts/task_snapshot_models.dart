/// Compatibility export for the task application contract.
///
/// The durable aggregate is domain-owned. Execution-facing snapshot types are
/// retained in `task_state_models.dart` while persistence adapters migrate to
/// explicit DTO conversion.
library;

export 'task_state_models.dart' hide TaskSnapshotAggregate, Task;
export '../../domain/task.dart' show TaskAggregate, Task;
