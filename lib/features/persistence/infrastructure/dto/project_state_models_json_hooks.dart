part of 'project_state_models.dart';

/// Project documents use the single schema supported by the current baseline.
class ProjectSnapshotAggregateJsonHook extends JsonModelHook {
  const ProjectSnapshotAggregateJsonHook()
    : super(removeKeys: const {'tasks', 'persistenceRevision'});

  @override
  Object? beforeDecode(Object? value) {
    final normalized = super.beforeDecode(value);
    if (normalized is! Map) return normalized;
    final json = Map<String, dynamic>.from(normalized);
    // Legacy embedded tasks are normalized by ProjectSnapshotAggregateRepository at
    // the load boundary. The mapper must still tolerate the old field while
    // direct project decoding is used by migration and diagnostics.
    return json;
  }
}
