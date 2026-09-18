import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/services/atomic_json_snapshot_store.dart';
import 'package:hermes/core/services/task_system/task_repository.dart';
import 'package:hermes/core/serialization/model_json.dart';
import 'package:path/path.dart' as path;

void main() {
  group('TaskRepository', () {
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

    test('lists current tasks newest first', () async {
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
    });

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

    test('stores compact task state and separate run history', () async {
      final task = _task(id: 'task_json', runs: [_run()]);
      await repository.saveSnapshot(root.path, task);

      final file = File(
        path.join(root.path, '.agent', 'tasks', 'task_json', 'task.json'),
      );
      final decoded = jsonDecode(await file.readAsString());
      final runFile = File(
        path.join(
          root.path,
          '.agent',
          'tasks',
          'task_json',
          'runs',
          'run_1.json',
        ),
      );

      expect(decoded['steps'], isA<List>());
      expect(decoded['runs'], isNull);
      expect(runFile.existsSync(), isTrue);
      expect(decoded['projectId'], isNull);

      final metadata = await repository.loadTask(
        root.path,
        'task_json',
        includeHistory: false,
      );
      expect(metadata?.runs, isEmpty);

      final loaded = await repository.loadTask(root.path, 'task_json');
      expect(loaded?.runs.single.runId, 'run_1');
    });

    test(
      'migrates legacy embedded run history when the task is saved',
      () async {
        final task = _task(id: 'task_legacy', runs: [_run()]);
        final taskDir = Directory(
          path.join(root.path, '.agent', 'tasks', 'task_legacy'),
        );
        await taskDir.create(recursive: true);
        final file = File(path.join(taskDir.path, 'task.json'));
        await file.writeAsString(jsonEncode(ModelJson.encode(task)));

        final loaded = await repository.loadTask(root.path, 'task_legacy');
        expect(loaded?.runs.single.runId, 'run_1');

        await repository.saveSnapshot(root.path, loaded!);

        final compact = jsonDecode(await file.readAsString());
        expect(compact['runs'], isNull);
        expect(
          File(path.join(taskDir.path, 'runs', 'run_1.json')).existsSync(),
          isTrue,
        );
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

Task _task({
  required String id,
  DateTime? updatedAt,
  String? chatSessionId,
  String? projectId,
  List<TaskRun> runs = const [],
}) {
  final now = DateTime(2026, 1, 1);
  return Task(
    id: id,
    title: 'Test task',
    originalPrompt: 'Run the task',
    objective: 'Run the task',
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
    runs: runs,
    chatSessionId: chatSessionId,
    projectId: projectId,
    createdAt: now,
    updatedAt: updatedAt ?? now,
  );
}

TaskRun _run() {
  final now = DateTime(2026, 1, 1, 12);
  return TaskRun(
    runId: 'run_1',
    stepId: 'step_1',
    status: TaskRunStatus.completed,
    summary: 'Completed the step.',
    memoryUpdate: 'The step completed.',
    toolCalls: const [],
    artifacts: const [],
    startedAt: now,
    completedAt: now.add(const Duration(minutes: 1)),
  );
}
