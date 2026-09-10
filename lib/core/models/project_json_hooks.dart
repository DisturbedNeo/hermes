part of 'project.dart';

/// Project snapshots use a clean-slate schema with a narrow compatibility
/// window for the Phase 2 snapshot. Phase 4 only adds optional batch state, so
/// schema v5 projects can be upgraded at the persistence boundary.
class ProjectStateJsonHook extends JsonModelHook {
  const ProjectStateJsonHook()
    : super(
        outputOverrides: const {
          'schemaVersion': ProjectState.currentSchemaVersion,
        },
        removeKeys: const {'tasks'},
      );

  @override
  Object? beforeDecode(Object? value) {
    final normalized = super.beforeDecode(value);
    if (normalized is! Map) return normalized;
    final json = Map<String, dynamic>.from(normalized);
    final version = jsonInt(json['schemaVersion']);
    if (version < ProjectState.minimumSupportedSchemaVersion ||
        version > ProjectState.currentSchemaVersion) {
      throw FormatException(
        'Unsupported project schema version $version; supported versions are '
        '${ProjectState.minimumSupportedSchemaVersion}-'
        '${ProjectState.currentSchemaVersion}.',
      );
    }
    // Phase 2 stores the ordered task relationship on the project. Embedded
    // task objects remain a decode-only compatibility path for old snapshots.
    if (!json.containsKey('taskIds') && json['tasks'] is List) {
      json['taskIds'] = [
        for (final item in json['tasks'] as List)
          if (item is Map && item['id'] != null) item['id'].toString(),
      ];
    }
    return json..['schemaVersion'] = ProjectState.currentSchemaVersion;
  }
}
