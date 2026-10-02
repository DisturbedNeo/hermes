/// Compatibility export for the task application contract.
///
/// The durable aggregate is domain-owned. Mapper-backed persistence DTOs are
/// implemented under the persistence infrastructure boundary; this export
/// remains for callers that have not migrated their import path.
library;

export 'task_state_models.dart' hide TaskSnapshotAggregate, Task;
export '../../domain/task.dart' show TaskAggregate, Task;
