/// Compatibility export for the project application contract.
///
/// Durable state is owned by `domain/project.dart`; the mapper-backed state
/// types remain available from `project_state_models.dart` until their
/// persistence adapters are fully narrowed.
library;

export 'project_state_models.dart' hide ProjectSnapshotAggregate;
export '../../domain/project.dart' show ProjectAggregate;
