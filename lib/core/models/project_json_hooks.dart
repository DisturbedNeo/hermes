part of 'project.dart';

/// Project snapshots are intentionally clean-slate at schema v5. Old data is
/// rejected instead of being silently interpreted through a compatibility
/// migration.
class ProjectStateJsonHook extends JsonModelHook {
  const ProjectStateJsonHook()
    : super(outputOverrides: const {'schemaVersion': ProjectState.currentSchemaVersion});

  @override
  Object? beforeDecode(Object? value) {
    final normalized = super.beforeDecode(value);
    if (normalized is! Map) return normalized;
    final json = Map<String, dynamic>.from(normalized);
    final version = jsonInt(json['schemaVersion']);
    if (version != ProjectState.currentSchemaVersion) {
      throw FormatException(
        'Unsupported project schema version $version; expected '
        '${ProjectState.currentSchemaVersion}.',
      );
    }
    return json;
  }
}

class ProjectTaskJsonHook extends JsonModelHook {
  const ProjectTaskJsonHook()
    : super(outputOverrides: const {});

  @override
  Object? afterDecode(Object? value) {
    if (value is! ProjectTask || value.fingerprint.isNotEmpty) return value;
    return value.copyWith(
      fingerprint: projectTaskFingerprint(value.objective, value.criterionIds),
    );
  }
}

class ProjectArtifactJsonHook extends JsonModelHook {
  const ProjectArtifactJsonHook();

  @override
  Object? afterDecode(Object? value) {
    if (value is! ProjectArtifact || value.id.isNotEmpty) return value;
    return value.copyWith(id: value.path);
  }
}
