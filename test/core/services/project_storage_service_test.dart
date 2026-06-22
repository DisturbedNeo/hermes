import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/services/project_system/project_storage_service.dart';
import 'package:path/path.dart' as path;

void main() {
  group('ProjectStorageService', () {
    late Directory root;
    late ProjectStorageService storage;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('hermes_project_storage_');
      storage = ProjectStorageService();
    });

    tearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    test('saves and loads a single project document', () async {
      final project = _project(id: 'project_test');

      await storage.saveSnapshot(root.path, project);

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

      final loaded = await storage.loadProject(root.path, 'project_test');
      expect(loaded?.id, 'project_test');
      expect(loaded?.title, 'Test project');
      expect(loaded?.status, ProjectStatus.paused);
    });

    test('lists projects newest first', () async {
      await storage.saveSnapshot(
        root.path,
        _project(id: 'project_old', updatedAt: DateTime(2026, 1, 1)),
      );
      await storage.saveSnapshot(
        root.path,
        _project(id: 'project_new', updatedAt: DateTime(2026, 1, 2)),
      );

      final projects = await storage.listProjects(root.path);

      expect(projects.map((project) => project.id), [
        'project_new',
        'project_old',
      ]);
    });

    test('filters and deletes by chat session', () async {
      await storage.saveSnapshot(
        root.path,
        _project(id: 'project_a', chatSessionId: 'chat_a'),
      );
      await storage.saveSnapshot(
        root.path,
        _project(id: 'project_b', chatSessionId: 'chat_b'),
      );

      expect(
        (await storage.listProjects(
          root.path,
          chatSessionId: 'chat_a',
        )).map((project) => project.id),
        ['project_a'],
      );

      final deleted = await storage.deleteProjectsForChatSession(
        root.path,
        chatSessionId: 'chat_a',
      );

      expect(deleted, 1);
      expect(await storage.loadProject(root.path, 'project_a'), isNull);
      expect(await storage.loadProject(root.path, 'project_b'), isNotNull);
    });

    test('deletes orphaned chat projects', () async {
      await storage.saveSnapshot(
        root.path,
        _project(id: 'project_saved', chatSessionId: 'chat_saved'),
      );
      await storage.saveSnapshot(
        root.path,
        _project(id: 'project_orphaned', chatSessionId: 'chat_deleted'),
      );

      final deleted = await storage.deleteOrphanedChatProjects(
        root.path,
        retainedChatSessionIds: {'chat_saved'},
      );

      expect(deleted, 1);
      expect(await storage.loadProject(root.path, 'project_saved'), isNotNull);
      expect(await storage.loadProject(root.path, 'project_orphaned'), isNull);
    });

    test('round-trips the raw project json shape', () async {
      final project = _project(id: 'project_json');
      await storage.saveSnapshot(root.path, project);

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

      expect(decoded['schemaVersion'], 2);
      expect(decoded['backlog'], isA<List>());
      expect(decoded['completedTasks'], isA<List>());
      expect(decoded['decisions'], isA<List>());
    });

    test('rejects delete paths outside project root', () async {
      expect(
        storage.deleteProject(root.path, '../outside'),
        throwsArgumentError,
      );
    });

    test('rejects log names outside the project log folder', () async {
      expect(
        storage.saveLog(root.path, 'project_test', '../project.json', '{}'),
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
    originalPrompt: 'Build the app',
    goal: 'Build the app',
    constraints: const ['Stay in workspace'],
    successCriteria: const ['Finish'],
    status: ProjectStatus.paused,
    activeTaskId: null,
    memorySummary: '',
    completionSummary: '',
    tasks: const [],
    decisions: const [],
    chatSessionId: chatSessionId,
    createdAt: now,
    updatedAt: updatedAt ?? now,
  );
}
