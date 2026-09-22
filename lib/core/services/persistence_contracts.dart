import 'dart:convert';

/// The only persisted snapshot schema supported by the project system.
const int currentSnapshotSchemaVersion = 1;

/// A decoded document together with the revision read from its envelope.
class PersistedSnapshot<T> {
  const PersistedSnapshot({
    required this.value,
    required this.revision,
    this.fromBackup = false,
  });

  final T value;
  final int revision;
  final bool fromBackup;

  PersistedSnapshot<T> copyWith({T? value, bool? fromBackup}) {
    return PersistedSnapshot<T>(
      value: value ?? this.value,
      revision: revision,
      fromBackup: fromBackup ?? this.fromBackup,
    );
  }
}

/// The persisted wrapper around a project or task document.
class SnapshotEnvelope {
  const SnapshotEnvelope({
    required this.schemaVersion,
    required this.revision,
    required this.document,
  });

  final int schemaVersion;
  final int revision;
  final Map<String, dynamic> document;

  Map<String, dynamic> asMap() => {
    'schemaVersion': schemaVersion,
    'revision': revision,
    'document': document,
  };

  static Map<String, dynamic> encode(
    Map<String, dynamic> document,
    int revision,
  ) {
    if (revision < 1) {
      throw const FormatException('Snapshot revision must be positive');
    }
    return SnapshotEnvelope(
      schemaVersion: currentSnapshotSchemaVersion,
      revision: revision,
      document: Map<String, dynamic>.from(document),
    ).asMap();
  }

  static SnapshotEnvelope decode(Map<String, dynamic> raw) {
    final schemaVersion = raw['schemaVersion'];
    final revision = raw['revision'];
    final document = raw['document'];
    if (schemaVersion is! int ||
        schemaVersion != currentSnapshotSchemaVersion ||
        revision is! int ||
        revision < 1 ||
        document is! Map) {
      throw const FormatException('Snapshot metadata is missing or invalid');
    }
    return SnapshotEnvelope(
      schemaVersion: schemaVersion,
      revision: revision,
      document: Map<String, dynamic>.from(document),
    );
  }

  String encodeString() =>
      '${const JsonEncoder.withIndent('  ').convert(asMap())}\n';
}

class StaleSnapshotException implements Exception {
  const StaleSnapshotException({
    required this.path,
    required this.expectedRevision,
    required this.actualRevision,
  });

  final String path;
  final int expectedRevision;
  final int actualRevision;

  @override
  String toString() =>
      'Stale snapshot: $path (expected revision $expectedRevision, '
      'actual revision $actualRevision)';
}

class ProjectPersistenceBlockedException implements Exception {
  const ProjectPersistenceBlockedException(this.diagnostics);

  final ProjectPersistenceDiagnostics diagnostics;

  @override
  String toString() =>
      'Project persistence is read-only: issues=${diagnostics.issues}; '
      'missing=${diagnostics.missingTaskIds}; '
      'corrupt=${diagnostics.corruptTaskIds}; '
      'transactions=${diagnostics.interruptedTransactionIds}; '
      'backups=${diagnostics.recoveredFromBackup}';
}

class ProjectPersistenceDiagnostics {
  const ProjectPersistenceDiagnostics({
    this.issues = const [],
    this.missingTaskIds = const [],
    this.corruptTaskIds = const [],
    this.interruptedTransactionIds = const [],
    this.recoveredFromBackup = const [],
  });

  final List<String> issues;
  final List<String> missingTaskIds;
  final List<String> corruptTaskIds;
  final List<String> interruptedTransactionIds;
  final List<String> recoveredFromBackup;

  bool get isReadOnly =>
      issues.isNotEmpty ||
      missingTaskIds.isNotEmpty ||
      corruptTaskIds.isNotEmpty ||
      interruptedTransactionIds.isNotEmpty ||
      recoveredFromBackup.isNotEmpty;

  bool get isEmpty => !isReadOnly && recoveredFromBackup.isEmpty;

  ProjectPersistenceDiagnostics merge(ProjectPersistenceDiagnostics other) {
    return ProjectPersistenceDiagnostics(
      issues: [...issues, ...other.issues],
      missingTaskIds: [...missingTaskIds, ...other.missingTaskIds],
      corruptTaskIds: [...corruptTaskIds, ...other.corruptTaskIds],
      interruptedTransactionIds: [
        ...interruptedTransactionIds,
        ...other.interruptedTransactionIds,
      ],
      recoveredFromBackup: [
        ...recoveredFromBackup,
        ...other.recoveredFromBackup,
      ],
    );
  }
}
