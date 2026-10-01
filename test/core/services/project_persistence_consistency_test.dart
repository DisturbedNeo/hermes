import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/features/project/application/contracts/project_snapshot_models.dart';
import 'package:hermes/features/task/application/contracts/task_snapshot_models.dart';
import 'package:hermes/features/persistence/application/persistence_contracts.dart';
import 'package:hermes/features/project/infrastructure/project_aggregate_repository.dart';
import 'package:hermes/features/project/application/contracts/project_checkpoint.dart';
import 'package:hermes/features/project/infrastructure/project_repository.dart';
import 'package:hermes/features/task/infrastructure/task_repository.dart';
import 'package:hermes/features/persistence/infrastructure/workspace_persistence_coordinator.dart';
import 'package:hermes/core/model_json.dart';
import 'package:path/path.dart' as path;

void main() {
  late Directory root;
  late WorkspacePersistenceCoordinator coordinator;
  late ProjectRepository projects;
  late TaskRepository tasks;
  late ProjectAggregateRepository aggregate;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('hermes_persistence_');
    coordinator = WorkspacePersistenceCoordinator();
    projects = ProjectRepository(coordinator: coordinator);
    tasks = TaskRepository(coordinator: coordinator);
    aggregate = ProjectAggregateRepository(
      projectRepository: projects,
      taskRepository: tasks,
      coordinator: coordinator,
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'revisioned repositories reject stale writes before changing files',
    () async {
      final project = _project('project_1');
      final first = await projects.saveSnapshot(root.path, project);
      expect(first.revision, 1);

      final second = await projects.saveSnapshot(
        root.path,
        project.copyWith(
          title: 'new title',
          persistenceRevision: first.revision,
        ),
      );
      expect(second.revision, 2);

      await expectLater(
        projects.saveSnapshot(root.path, project.copyWith(title: 'stale')),
        throwsA(isA<StaleSnapshotException>()),
      );
      final loaded = await projects.loadProjectSnapshot(root.path, project.id);
      expect(loaded?.revision, 2);
      expect(loaded?.value.title, 'new title');
    },
  );

  test(
    'two tab-like saves are serialized by the workspace coordinator',
    () async {
      final first = await projects.saveSnapshot(
        root.path,
        _project('project_1'),
      );
      final candidate = first.value.copyWith(
        title: 'candidate',
        persistenceRevision: first.revision,
      );
      final outcomes = <String>[];
      Future<void> attempt(String title) async {
        try {
          await projects.saveSnapshot(
            root.path,
            candidate.copyWith(title: title),
            expectedRevision: first.revision,
          );
          outcomes.add('saved');
        } on StaleSnapshotException {
          outcomes.add('stale');
        }
      }

      await Future.wait([attempt('tab-a'), attempt('tab-b')]);
      expect(outcomes.where((outcome) => outcome == 'saved'), hasLength(1));
      expect(outcomes.where((outcome) => outcome == 'stale'), hasLength(1));
      expect(
        (await projects.loadProjectSnapshot(root.path, 'project_1'))?.revision,
        2,
      );
    },
  );

  test(
    'aggregate commits project and canonical task envelopes together',
    () async {
      final task = _task('task_1');
      final project = _project('project_1', tasks: [task]);
      final committed = await aggregate.commit(
        workspaceRoot: root.path,
        project: project,
        tasks: [task],
      );

      expect(committed.project.revision, 1);
      expect(committed.tasks['task_1']?.revision, 1);
      final raw =
          jsonDecode(
                await File(
                  path.join(
                    root.path,
                    '.agent/projects/project_1/project.json',
                  ),
                ).readAsString(),
              )
              as Map<String, dynamic>;
      expect(raw, isNot(contains('schemaVersion')));
      expect(raw['revision'], 1);
      expect((raw['document'] as Map<String, dynamic>)['tasks'], isNull);

      final loaded = await aggregate.loadProject(root.path, project.id);
      expect(loaded.project?.tasks, isEmpty);
      expect(loaded.diagnostics.isEmpty, isTrue);
    },
  );

  test(
    'migrates legacy embedded tasks into canonical task documents',
    () async {
      final task = _task('legacy_task');
      final project = _project('legacy_project');
      final document = ModelJson.encode(project)
        ..['tasks'] = [ModelJson.encode(task)]
        ..['taskIds'] = <String>[];
      final file = File(
        path.join(
          root.path,
          ProjectRepository.projectsRoot,
          project.id,
          ProjectRepository.documentFileName,
        ),
      );
      await file.parent.create(recursive: true);
      await file.writeAsString(
        jsonEncode(SnapshotEnvelope.encode(document, 1)),
      );

      final loaded = await aggregate.loadProject(root.path, project.id);

      expect(loaded.project?.taskIds, ['legacy_task']);
      expect(loaded.canonicalTasks.single.id, 'legacy_task');
      expect(loaded.canonicalTasks.single.title, task.title);
      final normalized = jsonDecode(await file.readAsString()) as Map;
      final normalizedDocument = normalized['document'] as Map;
      expect(normalizedDocument, isNot(contains('tasks')));
      expect(
        await File(
          path.join(
            root.path,
            TaskRepository.tasksRoot,
            'legacy_task',
            TaskRepository.documentFileName,
          ),
        ).exists(),
        isTrue,
      );
    },
  );

  test(
    'backup fallback is diagnostic and does not repair the primary',
    () async {
      final task = _task('task_1');
      final project = _project('project_1', tasks: [task]);
      final committed = await aggregate.commit(
        workspaceRoot: root.path,
        project: project,
        tasks: [task],
      );
      await projects.saveSnapshot(
        root.path,
        committed.project.value.copyWith(
          title: 'second revision',
          persistenceRevision: committed.project.revision,
        ),
      );
      final primary = File(
        path.join(root.path, '.agent/projects/project_1/project.json'),
      );
      await primary.writeAsString('{}');

      final loaded = await aggregate.loadProject(root.path, project.id);
      expect(loaded.project, isNotNull);
      expect(loaded.diagnostics.recoveredFromBackup, contains('project_1'));
      expect(loaded.diagnostics.isDegraded, isTrue);
      expect(loaded.diagnostics.isReadOnly, isFalse);
      expect(await primary.readAsString(), '{}');
    },
  );

  test(
    'missing referenced tasks keep taskIds and make a project read-only',
    () async {
      final project = _project('project_1', tasks: [_task('missing_task')]);
      await projects.saveSnapshot(root.path, project);

      final loaded = await aggregate.loadProject(root.path, project.id);
      expect(loaded.project?.taskIds, ['missing_task']);
      expect(loaded.project?.tasks, isEmpty);
      expect(loaded.diagnostics.missingTaskIds, ['missing_task']);
      expect(loaded.diagnostics.isReadOnly, isTrue);
    },
  );

  test(
    'interrupted aggregate transactions are reported without replay',
    () async {
      final task = _task('task_1');
      final project = _project('project_1', tasks: [task]);
      final committed = await aggregate.commit(
        workspaceRoot: root.path,
        project: project,
        tasks: [task],
      );
      final failing = ProjectAggregateRepository(
        projectRepository: projects,
        taskRepository: tasks,
        coordinator: coordinator,
        onTransactionPhase: (phase) {
          if (phase == 'committing') throw StateError('injected failure');
        },
      );
      final updatedTask = committed.tasks['task_1']!.value.copyWith(
        title: 'changed task',
      );
      final updatedProject = committed.project.value.copyWith(
        title: 'changed project',
        tasks: [ProjectTaskNode.fromTask(updatedTask)],
      );
      await expectLater(
        failing.commit(
          workspaceRoot: root.path,
          project: updatedProject,
          tasks: [updatedTask],
          checkpoint: ProjectPersistenceCheckpoint.planRevision,
        ),
        throwsStateError,
      );

      final transactionRoot = Directory(
        path.join(root.path, '.agent/transactions'),
      );
      final transactionDirectories = await transactionRoot.list().toList();
      expect(transactionDirectories, isNotEmpty);
      final manifest = File(
        path.join(
          (transactionDirectories.single as Directory).path,
          'manifest.json',
        ),
      );
      final manifestMap = jsonDecode(await manifest.readAsString()) as Map;
      expect(manifestMap['checkpoint'], 'plan_revision');

      final loaded = await aggregate.loadProject(root.path, project.id);
      expect(loaded.diagnostics.interruptedTransactionIds, isNotEmpty);
      expect(loaded.diagnostics.isReadOnly, isTrue);
      expect(loaded.project?.title, project.title);

      final recovery = await aggregate.recoverInterruptedTransactions(
        root.path,
      );
      expect(recovery.recoveredTransactionIds, isNotEmpty);
      expect(recovery.unresolvedTransactionIds, isEmpty);

      final recovered = await aggregate.loadProject(root.path, project.id);
      expect(recovered.diagnostics.interruptedTransactionIds, isEmpty);
      expect(recovered.diagnostics.isReadOnly, isFalse);
    },
  );

  test(
    'aggregate deletion removes project, canonical task, and history directory',
    () async {
      final task = _task('task_1', runs: [_run()]);
      final project = _project('project_1', tasks: [task]);
      final committed = await aggregate.commit(
        workspaceRoot: root.path,
        project: project,
        tasks: [task],
      );

      expect(
        await aggregate.deleteProject(root.path, committed.project.value),
        isTrue,
      );
      expect(await projects.loadProject(root.path, project.id), isNull);
      expect(await tasks.loadTask(root.path, task.id), isNull);
    },
  );
}

ProjectAggregate _project(String id, {List<Task> tasks = const []}) {
  final now = DateTime(2026, 1, 1);
  return ProjectAggregate(
    id: id,
    title: 'Project',
    originalGoal: 'Goal',
    refinedGoal: 'Goal',
    criteria: const [],
    constraints: const [],
    tasks: [for (final task in tasks) ProjectTaskNode.fromTask(task)],
    status: ProjectStatus.active,
    activeTaskId: null,
    createdAt: now,
    updatedAt: now,
  );
}

Task _task(String id, {List<TaskRun> runs = const []}) {
  final now = DateTime(2026, 1, 1);
  return Task(
    id: id,
    title: 'Task',
    originalPrompt: 'Task',
    objective: 'Task',
    constraints: const [],
    successCriteria: const [],
    steps: const [],
    status: TaskStatus.queued,
    currentStepId: null,
    runs: runs,
    createdAt: now,
    updatedAt: now,
  );
}

TaskRun _run() {
  final now = DateTime(2026, 1, 1);
  return TaskRun(
    runId: 'run_1',
    stepId: 'step_1',
    status: TaskRunStatus.completed,
    summary: 'done',
    memoryUpdate: '',
    toolCalls: const [],
    artifacts: const [],
    startedAt: now,
    completedAt: now,
  );
}
