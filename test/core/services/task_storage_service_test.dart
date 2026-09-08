import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/services/atomic_json_snapshot_store.dart';
import 'package:hermes/core/services/task_system/task_repository.dart';
import 'package:path/path.dart' as path;

void main() {
  group('TaskRepository v3', () {
    late Directory root;
    late TaskRepository repository;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('hermes_task_storage_');
      repository = TaskRepository();
    });

    tearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    test('saves and loads a single task document', () async {
      final task = _task(id: 'task_test');

      await repository.saveSnapshot(root.path, task);

      final file = File(
        path.join(root.path, '.agent', 'tasks', 'task_test', 'task.json'),
      );
      expect(file.existsSync(), isTrue);

      final loaded = await repository.loadTask(root.path, 'task_test');
      expect(loaded?.id, 'task_test');
      expect(loaded?.steps.single.title, 'Step 1');
      expect(loaded?.status, TaskStatus.paused);
    });

    test(
      'lists current tasks newest first and ignores legacy folders',
      () async {
        final oldTaskDir = Directory(
          path.join(root.path, '.agent', 'tasks', 'legacy_task'),
        );
        await oldTaskDir.create(recursive: true);
        await File(
          path.join(oldTaskDir.path, 'task-spec.yaml'),
        ).writeAsString('{}');

        await repository.saveSnapshot(
          root.path,
          _task(id: 'task_old', updatedAt: DateTime(2026, 1, 1)),
        );
        await repository.saveSnapshot(
          root.path,
          _task(id: 'task_new', updatedAt: DateTime(2026, 1, 2)),
        );

        final tasks = await repository.listTasks(root.path);

        expect(tasks.map((task) => task.id), ['task_new', 'task_old']);
      },
    );

    test('filters and deletes by chat session', () async {
      await repository.saveSnapshot(
        root.path,
        _task(id: 'task_a', chatSessionId: 'chat_a'),
      );
      await repository.saveSnapshot(
        root.path,
        _task(id: 'task_b', chatSessionId: 'chat_b'),
      );

      expect(
        (await repository.listTasks(
          root.path,
          chatSessionId: 'chat_a',
        )).map((task) => task.id),
        ['task_a'],
      );

      final deleted = await repository.deleteTasksForChatSession(
        root.path,
        chatSessionId: 'chat_a',
      );

      expect(deleted, 1);
      expect(await repository.loadTask(root.path, 'task_a'), isNull);
      expect(await repository.loadTask(root.path, 'task_b'), isNotNull);
    });

    test('filters by project id', () async {
      await repository.saveSnapshot(
        root.path,
        _task(id: 'task_a', projectId: 'project_a'),
      );
      await repository.saveSnapshot(
        root.path,
        _task(id: 'task_b', projectId: 'project_b'),
      );

      expect(
        (await repository.listTasks(
          root.path,
          projectId: 'project_a',
        )).map((task) => task.id),
        ['task_a'],
      );

      expect(
        await repository.loadTask(root.path, 'task_b', projectId: 'project_a'),
        isNull,
      );
    });

    test('round-trips the raw task json shape', () async {
      final task = _task(id: 'task_json');
      await repository.saveSnapshot(root.path, task);

      final file = File(
        path.join(root.path, '.agent', 'tasks', 'task_json', 'task.json'),
      );
      final decoded = jsonDecode(await file.readAsString());

      expect(decoded['schemaVersion'], TaskDocument.currentSchemaVersion);
      expect(decoded['steps'], isA<List>());
      expect(decoded['runs'], isA<List>());
      expect(decoded['projectId'], isNull);
    });

    test('migrates schema-v2 tasks and writes a one-time backup', () async {
      await repository.saveSnapshot(root.path, _task(id: 'task_migration'));
      final directory = Directory(
        path.join(root.path, '.agent', 'tasks', 'task_migration'),
      );
      final file = File(path.join(directory.path, 'task.json'));
      final raw =
          Map<String, dynamic>.from(
              jsonDecode(await file.readAsString()) as Map,
            )
            ..['schemaVersion'] = 2
            ..remove('projectCriterionIds');
      await file.writeAsString(jsonEncode(raw));

      final migrated = await repository.loadTask(root.path, 'task_migration');
      final backup = File(
        path.join(directory.path, TaskRepository.v2BackupFileName),
      );

      expect(migrated?.schemaVersion, TaskDocument.currentSchemaVersion);
      expect(migrated, isNotNull);
      expect(jsonDecode(await file.readAsString())['schemaVersion'], 3);
      expect(jsonDecode(await backup.readAsString())['schemaVersion'], 2);
    });

    test(
      'refuses a newer task schema without restoring or rewriting it',
      () async {
        await repository.saveSnapshot(root.path, _task(id: 'task_future'));
        await repository.saveSnapshot(root.path, _task(id: 'task_future'));
        final file = File(
          path.join(root.path, '.agent', 'tasks', 'task_future', 'task.json'),
        );
        final raw =
            Map<String, dynamic>.from(
                jsonDecode(await file.readAsString()) as Map,
              )
              ..['schemaVersion'] = TaskDocument.currentSchemaVersion + 1
              ..['futureOnly'] = {'preserve': true};
        final futureContent = jsonEncode(raw);
        await file.writeAsString(futureContent);

        await expectLater(
          repository.loadTask(root.path, 'task_future'),
          throwsA(
            isA<UnsupportedSnapshotSchemaException>()
                .having(
                  (error) => error.foundVersion,
                  'foundVersion',
                  TaskDocument.currentSchemaVersion + 1,
                )
                .having(
                  (error) => error.supportedVersion,
                  'supportedVersion',
                  TaskDocument.currentSchemaVersion,
                ),
          ),
        );
        expect(await file.readAsString(), futureContent);
      },
    );

    test('recovers and repairs a corrupt primary from its backup', () async {
      await repository.saveSnapshot(
        root.path,
        _task(id: 'task_recovery', updatedAt: DateTime(2026, 1, 1)),
      );
      await repository.saveSnapshot(
        root.path,
        _task(id: 'task_recovery', updatedAt: DateTime(2026, 1, 2)),
      );
      final file = File(
        path.join(root.path, '.agent', 'tasks', 'task_recovery', 'task.json'),
      );
      await file.writeAsString('{broken');

      final recovered = await repository.loadTask(root.path, 'task_recovery');

      expect(recovered?.updatedAt, DateTime(2026, 1, 1));
      expect(jsonDecode(await file.readAsString()), isA<Map>());
    });

    test('throws a typed error when primary and backup are corrupt', () async {
      await repository.saveSnapshot(root.path, _task(id: 'task_corrupt'));
      await repository.saveSnapshot(root.path, _task(id: 'task_corrupt'));
      final file = File(
        path.join(root.path, '.agent', 'tasks', 'task_corrupt', 'task.json'),
      );
      await file.writeAsString('{}');
      await File('${file.path}.bak').writeAsString('{broken');

      await expectLater(
        repository.loadTask(root.path, 'task_corrupt'),
        throwsA(isA<SnapshotCorruptionException>()),
      );
      expect(await repository.listTasks(root.path), isEmpty);
    });

    test('ignores a stale interrupted temporary snapshot', () async {
      await repository.saveSnapshot(root.path, _task(id: 'task_stable'));
      final directory = Directory(
        path.join(root.path, '.agent', 'tasks', 'task_stable'),
      );
      await File(
        path.join(directory.path, 'task.json.tmp.interrupted'),
      ).writeAsString('{partial');

      final loaded = await repository.loadTask(root.path, 'task_stable');

      expect(loaded?.id, 'task_stable');
    });

    test('validates task ids and log names for every path API', () async {
      expect(
        repository.saveSnapshot(root.path, _task(id: '../outside')),
        throwsArgumentError,
      );
      expect(repository.loadTask(root.path, '../outside'), throwsArgumentError);
      expect(
        repository.saveLog(root.path, 'task_test', '../task.json', '{}'),
        throwsArgumentError,
      );
      expect(
        () => repository.taskRelativePath('../outside', 'task.json'),
        throwsArgumentError,
      );
    });
  });
}

TaskDocument _task({
  required String id,
  DateTime? updatedAt,
  String? chatSessionId,
  String? projectId,
}) {
  final now = DateTime(2026, 1, 1);
  return TaskDocument(
    id: id,
    title: 'Test task',
    originalPrompt: 'Run the task',
    goal: 'Run the task',
    constraints: const ['Stay in workspace'],
    successCriteria: const ['Finish'],
    steps: const [
      TaskStep(
        id: 'step_1',
        title: 'Step 1',
        objective: 'Do step 1',
        instructions: ['Work carefully'],
        mayEditFiles: false,
        artifacts: [],
        status: TaskStepStatus.pending,
      ),
    ],
    status: TaskStatus.paused,
    currentStepId: 'step_1',
    memorySummary: '',
    runs: const [],
    chatSessionId: chatSessionId,
    projectId: projectId,
    createdAt: now,
    updatedAt: updatedAt ?? now,
  );
}
