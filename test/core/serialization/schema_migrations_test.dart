import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/features/persistence/application/schema_migrations.dart';

void main() {
  test('project migration derives task ids and is idempotent', () {
    final legacy = <String, dynamic>{
      'schemaVersion': 1,
      'tasks': [
        {'id': 'task_1'},
        {'id': 'task_2'},
      ],
    };

    final migrated = projectSchemaMigrations.migrate(legacy);
    expect(migrated['schemaVersion'], 2);
    expect(migrated['taskIds'], ['task_1', 'task_2']);
    expect(projectSchemaMigrations.migrate(migrated), migrated);
  });

  test('missing schema versions retain current compatibility semantics', () {
    final document = {'id': 'legacy', 'title': 'Old'};
    expect(taskSchemaMigrations.migrate(document), document);
    expect(chatSchemaMigrations.migrate(document), document);
  });

  test('newer and malformed versions fail with actionable diagnostics', () {
    expect(
      () => taskSchemaMigrations.migrate({'schemaVersion': 99}),
      throwsA(isA<SchemaMigrationException>()),
    );
    expect(
      () => taskSchemaMigrations.migrate({'schemaVersion': 'two'}),
      throwsA(isA<SchemaMigrationException>()),
    );
  });
}
