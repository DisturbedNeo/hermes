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
    if (json.containsKey('tasks')) {
      throw const FormatException(
        'Embedded project tasks are not supported; use taskIds.',
      );
    }
    return json;
  }
}
