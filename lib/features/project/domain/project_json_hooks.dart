part of 'project.dart';

/// Project documents use the single schema supported by the current baseline.
class ProjectStateJsonHook extends JsonModelHook {
  const ProjectStateJsonHook()
    : super(removeKeys: const {'tasks', 'persistenceRevision'});

  @override
  Object? beforeDecode(Object? value) {
    final normalized = super.beforeDecode(value);
    if (normalized is! Map) return normalized;
    final json = Map<String, dynamic>.from(normalized);
    // Legacy embedded tasks are normalized by ProjectAggregateRepository at
    // the load boundary. The mapper must still tolerate the old field while
    // direct project decoding is used by migration and diagnostics.
    return json;
  }
}
