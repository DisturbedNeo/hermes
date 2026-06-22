import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/services/task_system/task_storage_service.dart';
import 'package:path/path.dart' as path;

void main() {
  group('TaskStorageService v2', () {
    late Directory root;
    late TaskStorageService storage;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('hermes_task_storage_');
      storage = TaskStorageService();
    });

    tearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    test('saves and loads a single task document', () async {
      final task = _task(id: 'task_test');

      await storage.saveSnapshot(root.path, task);

      final file = File(
        path.join(root.path, '.agent', 'tasks', 'task_test', 'task.json'),
      );
      expect(file.existsSync(), isTrue);

      final loaded = await storage.loadTask(root.path, 'task_test');
      expect(loaded?.id, 'task_test');
      expect(loaded?.steps.single.title, 'Step 1');
      expect(loaded?.status, TaskStatus.paused);
    });

    test('lists v2 tasks newest first and ignores legacy folders', () async {
      final oldTaskDir = Directory(
        path.join(root.path, '.agent', 'tasks', 'legacy_task'),
      );
      await oldTaskDir.create(recursive: true);
      await File(
        path.join(oldTaskDir.path, 'task-spec.yaml'),
      ).writeAsString('{}');

      await storage.saveSnapshot(
        root.path,
        _task(id: 'task_old', updatedAt: DateTime(2026, 1, 1)),
      );
      await storage.saveSnapshot(
        root.path,
        _task(id: 'task_new', updatedAt: DateTime(2026, 1, 2)),
      );

      final tasks = await storage.listTasks(root.path);

      expect(tasks.map((task) => task.id), ['task_new', 'task_old']);
    });

    test('filters and deletes by chat session', () async {
      await storage.saveSnapshot(
        root.path,
        _task(id: 'task_a', chatSessionId: 'chat_a'),
      );
      await storage.saveSnapshot(
        root.path,
        _task(id: 'task_b', chatSessionId: 'chat_b'),
      );

      expect(
        (await storage.listTasks(
          root.path,
          chatSessionId: 'chat_a',
        )).map((task) => task.id),
        ['task_a'],
      );

      final deleted = await storage.deleteTasksForChatSession(
        root.path,
        chatSessionId: 'chat_a',
      );

      expect(deleted, 1);
      expect(await storage.loadTask(root.path, 'task_a'), isNull);
      expect(await storage.loadTask(root.path, 'task_b'), isNotNull);
    });

    test('round-trips the raw task json shape', () async {
      final task = _task(id: 'task_json');
      await storage.saveSnapshot(root.path, task);

      final file = File(
        path.join(root.path, '.agent', 'tasks', 'task_json', 'task.json'),
      );
      final decoded = jsonDecode(await file.readAsString());

      expect(decoded['schemaVersion'], 2);
      expect(decoded['steps'], isA<List>());
      expect(decoded['runs'], isA<List>());
    });
  });
}

TaskDocument _task({
  required String id,
  DateTime? updatedAt,
  String? chatSessionId,
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
    createdAt: now,
    updatedAt: updatedAt ?? now,
  );
}
