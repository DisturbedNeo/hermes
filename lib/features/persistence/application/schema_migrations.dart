typedef SchemaMigration =
    Map<String, dynamic> Function(Map<String, dynamic> document);

class SchemaMigrationException implements Exception {
  const SchemaMigrationException({
    required this.entity,
    required this.version,
    required this.message,
  });

  final String entity;
  final int version;
  final String message;

  @override
  String toString() => '$entity schema v$version: $message';
}

/// Applies explicit, ordered document migrations without coupling persistence
/// adapters to the model mapper implementation.
class SchemaMigrationRegistry {
  SchemaMigrationRegistry({
    required this.entity,
    required this.currentVersion,
    Map<int, SchemaMigration> migrations = const {},
  }) : _migrations = Map.unmodifiable(migrations);

  final String entity;
  final int currentVersion;
  final Map<int, SchemaMigration> _migrations;

  Map<String, dynamic> migrate(Map<String, dynamic> input) {
    var version = _readVersion(input);
    var document = Map<String, dynamic>.from(input);
    while (version < currentVersion) {
      final migration = _migrations[version];
      if (migration == null) {
        throw SchemaMigrationException(
          entity: entity,
          version: version,
          message: 'No migration is registered for this version.',
        );
      }
      document = Map<String, dynamic>.from(migration(document));
      version++;
    }
    if (version > currentVersion) {
      throw SchemaMigrationException(
        entity: entity,
        version: version,
        message: 'Snapshot is newer than this application.',
      );
    }
    return document;
  }

  int _readVersion(Map<String, dynamic> document) {
    final value = document['schemaVersion'];
    if (value == null) return currentVersion;
    if (value is int && value >= 0) return value;
    throw SchemaMigrationException(
      entity: entity,
      version: -1,
      message: 'schemaVersion must be a non-negative integer.',
    );
  }
}

final projectSchemaMigrations = SchemaMigrationRegistry(
  entity: 'project',
  currentVersion: 2,
  migrations: {
    1: (document) {
      final migrated = Map<String, dynamic>.from(document);
      if (migrated['taskIds'] is! List && migrated['tasks'] is List) {
        migrated['taskIds'] = [
          for (final task in migrated['tasks'] as List)
            if (task is Map && task['id'] is String) task['id'],
        ];
      }
      migrated['schemaVersion'] = 2;
      return migrated;
    },
  },
);

final taskSchemaMigrations = SchemaMigrationRegistry(
  entity: 'task',
  currentVersion: 2,
  migrations: {
    1: (document) {
      final migrated = Map<String, dynamic>.from(document);
      migrated.putIfAbsent('runs', () => const <Object?>[]);
      migrated['schemaVersion'] = 2;
      return migrated;
    },
  },
);

final chatSchemaMigrations = SchemaMigrationRegistry(
  entity: 'chat',
  currentVersion: 1,
);

final settingsSchemaMigrations = SchemaMigrationRegistry(
  entity: 'settings',
  currentVersion: 1,
);
