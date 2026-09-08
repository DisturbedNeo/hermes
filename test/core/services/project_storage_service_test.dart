import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/services/atomic_json_snapshot_store.dart';
import 'package:hermes/core/services/project_system/project_repository.dart';
import 'package:path/path.dart' as path;

void main() {
  group('ProjectRepository', () {
    late Directory root;
    late ProjectRepository repository;

    setUp(() async {
      root = await Directory.systemTemp.createTemp(
        'hermes_project_repository_',
      );
      repository = ProjectRepository();
    });

    tearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    test('saves and loads a single project document', () async {
      final project = _project(id: 'project_test');

      await repository.saveSnapshot(root.path, project);

      final file = File(
        path.join(
          root.path,
          '.agent',
          'projects',
          'project_test',
          'project.json',
        ),
      );
      expect(file.existsSync(), isTrue);

      final loaded = await repository.loadProject(root.path, 'project_test');
      expect(loaded?.id, 'project_test');
      expect(loaded?.title, 'Test project');
      expect(loaded?.status, ProjectStatus.paused);
    });

    test('lists projects newest first', () async {
      await repository.saveSnapshot(
        root.path,
        _project(id: 'project_old', updatedAt: DateTime(2026, 1, 1)),
      );
      await repository.saveSnapshot(
        root.path,
        _project(id: 'project_new', updatedAt: DateTime(2026, 1, 2)),
      );

      final projects = await repository.listProjects(root.path);

      expect(projects.map((project) => project.id), [
        'project_new',
        'project_old',
      ]);
    });

    test('filters and deletes by chat session', () async {
      await repository.saveSnapshot(
        root.path,
        _project(id: 'project_a', chatSessionId: 'chat_a'),
      );
      await repository.saveSnapshot(
        root.path,
        _project(id: 'project_b', chatSessionId: 'chat_b'),
      );

      expect(
        (await repository.listProjects(
          root.path,
          chatSessionId: 'chat_a',
        )).map((project) => project.id),
        ['project_a'],
      );

      final deleted = await repository.deleteProjectsForChatSession(
        root.path,
        chatSessionId: 'chat_a',
      );

      expect(deleted, 1);
      expect(await repository.loadProject(root.path, 'project_a'), isNull);
      expect(await repository.loadProject(root.path, 'project_b'), isNotNull);
    });

    test('deletes orphaned chat projects', () async {
      await repository.saveSnapshot(
        root.path,
        _project(id: 'project_saved', chatSessionId: 'chat_saved'),
      );
      await repository.saveSnapshot(
        root.path,
        _project(id: 'project_orphaned', chatSessionId: 'chat_deleted'),
      );

      final deleted = await repository.deleteOrphanedChatProjects(
        root.path,
        retainedChatSessionIds: {'chat_saved'},
      );

      expect(deleted, 1);
      expect(
        await repository.loadProject(root.path, 'project_saved'),
        isNotNull,
      );
      expect(
        await repository.loadProject(root.path, 'project_orphaned'),
        isNull,
      );
    });

    test('round-trips the raw project json shape', () async {
      final project = _project(id: 'project_json');
      await repository.saveSnapshot(root.path, project);

      final file = File(
        path.join(
          root.path,
          '.agent',
          'projects',
          'project_json',
          'project.json',
        ),
      );
      final decoded = jsonDecode(await file.readAsString());

      expect(decoded['schemaVersion'], ProjectDocument.currentSchemaVersion);
      expect(decoded['criteria'], isA<List>());
      expect(decoded['memory'], isA<List>());
      expect(decoded.containsKey('successCriteria'), isFalse);
      expect(decoded.containsKey('knownFacts'), isFalse);
      expect(decoded['tasks'], isA<List>());
      expect(decoded.containsKey('backlog'), isFalse);
      expect(decoded.containsKey('completedTasks'), isFalse);
      expect(decoded.containsKey('failedTasks'), isFalse);
      expect(decoded['decisions'], isA<List>());
    });

    test(
      'refuses unsupported project schemas without restoring or rewriting them',
      () async {
        await repository.saveSnapshot(
          root.path,
          _project(id: 'project_future'),
        );
        await repository.saveSnapshot(
          root.path,
          _project(id: 'project_future'),
        );
        final file = File(
          path.join(
            root.path,
            '.agent',
            'projects',
            'project_future',
            'project.json',
          ),
        );
        final raw =
            Map<String, dynamic>.from(
                jsonDecode(await file.readAsString()) as Map,
              )
              ..['schemaVersion'] = ProjectDocument.currentSchemaVersion + 1
              ..['futureOnly'] = {'preserve': true};
        final futureContent = jsonEncode(raw);
        await file.writeAsString(futureContent);

        await expectLater(
          repository.loadProject(root.path, 'project_future'),
          throwsA(
            isA<UnsupportedSnapshotSchemaException>()
                .having(
                  (error) => error.foundVersion,
                  'foundVersion',
                  ProjectDocument.currentSchemaVersion + 1,
                )
                .having(
                  (error) => error.supportedVersion,
                  'supportedVersion',
                  ProjectDocument.currentSchemaVersion,
                ),
          ),
        );
        expect(await file.readAsString(), futureContent);
      },
    );

    test('rejects an old project schema without migration', () async {
      final file = File(
        path.join(
          root.path,
          '.agent',
          'projects',
          'project_old',
          'project.json',
        ),
      )..parent.createSync(recursive: true);
      const oldContent = '{"schemaVersion": 4, "id": "project_old"}';
      await file.writeAsString(oldContent);

      await expectLater(
        repository.loadProject(root.path, 'project_old'),
        throwsA(
          isA<UnsupportedSnapshotSchemaException>()
              .having((error) => error.foundVersion, 'foundVersion', 4)
              .having(
                (error) => error.supportedVersion,
                'supportedVersion',
                ProjectDocument.currentSchemaVersion,
              ),
        ),
      );
      expect(await file.readAsString(), oldContent);
    });

    test('rejects delete paths outside project root', () async {
      expect(
        repository.deleteProject(root.path, '../outside'),
        throwsArgumentError,
      );
    });

    test('rejects log names outside the project log folder', () async {
      expect(
        repository.saveLog(root.path, 'project_test', '../project.json', '{}'),
        throwsArgumentError,
      );
    });

    test('recovers and repairs a corrupt primary from its backup', () async {
      await repository.saveSnapshot(
        root.path,
        _project(id: 'project_recovery', updatedAt: DateTime(2026, 1, 1)),
      );
      await repository.saveSnapshot(
        root.path,
        _project(id: 'project_recovery', updatedAt: DateTime(2026, 1, 2)),
      );
      final file = File(
        path.join(
          root.path,
          '.agent',
          'projects',
          'project_recovery',
          'project.json',
        ),
      );
      await file.writeAsString('{}');

      final recovered = await repository.loadProject(
        root.path,
        'project_recovery',
      );

      expect(recovered?.updatedAt, DateTime(2026, 1, 1));
      expect(jsonDecode(await file.readAsString()), isA<Map>());
    });

    test('throws a typed error when primary and backup are corrupt', () async {
      await repository.saveSnapshot(root.path, _project(id: 'project_corrupt'));
      await repository.saveSnapshot(root.path, _project(id: 'project_corrupt'));
      final file = File(
        path.join(
          root.path,
          '.agent',
          'projects',
          'project_corrupt',
          'project.json',
        ),
      );
      await file.writeAsString('{}');
      await File('${file.path}.bak').writeAsString('{broken');

      await expectLater(
        repository.loadProject(root.path, 'project_corrupt'),
        throwsA(isA<SnapshotCorruptionException>()),
      );
      expect(await repository.listProjects(root.path), isEmpty);
    });

    test('validates project ids across save, load, and relative paths', () {
      expect(
        repository.saveSnapshot(root.path, _project(id: '../outside')),
        throwsArgumentError,
      );
      expect(
        repository.loadProject(root.path, '../outside'),
        throwsArgumentError,
      );
      expect(
        () => repository.projectRelativePath('../outside', 'project.json'),
        throwsArgumentError,
      );
    });
  });
}

ProjectDocument _project({
  required String id,
  DateTime? updatedAt,
  String? chatSessionId,
}) {
  final now = DateTime(2026, 1, 1);
  return ProjectDocument(
    id: id,
    title: 'Test project',
    originalGoal: 'Build the app',
    refinedGoal: 'Build the app',
    constraints: const ['Stay in workspace'],
    criteria: const [],
    status: ProjectStatus.paused,
    activeTaskId: null,
    completionSummary: '',
    tasks: const [],
    decisions: const [],
    chatSessionId: chatSessionId,
    createdAt: now,
    updatedAt: updatedAt ?? now,
  );
}
