/// Compatibility export for the project application contract.
///
/// Durable state is owned by `domain/project.dart`; mapper-backed persistence
/// DTOs are implemented under the persistence infrastructure boundary. This
/// export remains for callers that have not migrated their import path.
library;

export 'project_state_models.dart' hide ProjectSnapshotAggregate;
export '../../domain/project.dart' show ProjectAggregate;
