import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/project_system/orchestration_contracts.dart';
import 'package:hermes/core/services/project_system/project_recovery_service.dart';
import 'package:hermes/core/services/project_system/project_run_loop.dart';
import 'package:hermes/core/services/task_system/task_command_service.dart';
import 'package:hermes/core/services/task_system/task_persistence_store.dart';
import 'package:hermes/core/services/task_system/task_recovery_service.dart';
import 'package:hermes/core/services/task_system/task_repository.dart';
import 'package:hermes/core/services/task_system/task_step_runner.dart';

void main() {
  late Directory root;
  late WorkspaceAttachment workspace;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('hermes_components_');
    workspace = WorkspaceAttachment(
      rootPath: root.path,
      displayName: 'Components',
      lastOpenedAt: DateTime(2026, 1, 1),
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test(
    'task recovery is deterministic and preserves the interruption reason',
    () {
      final runningStep = _step('step_1', TaskStepStatus.running);
      final task = _task(
        'task_1',
        status: TaskStatus.running,
        steps: [runningStep],
      );

      final recovered = const TaskRecoveryService().recover(
        task,
        now: DateTime(2026, 1, 2),
      );

      expect(recovered.status, TaskStatus.blocked);
      expect(recovered.steps.single.status, TaskStepStatus.blocked);
      expect(
        recovered.memorySummary,
        contains('Recovered an interrupted task'),
      );
    },
  );

  test(
    'task command service persists a terminal stop through the store',
    () async {
      final repository = TaskRepository();
      final store = TaskPersistenceStore(repository: repository);
      final command = TaskCommandService(persistence: store);
      final saved = await store.save(root.path, _task('task_1'));

      final stopped = await command.stopTask(
        workspace: workspace,
        snapshot: saved.value,
      );
      final loaded = await store.load(root.path, stopped.id);

      expect(stopped.status, TaskStatus.cancelled);
      expect(loaded?.value.status, TaskStatus.cancelled);
      expect(loaded?.value.runs, isEmpty);
    },
  );

  test('task step runner recovers and checkpoints before execution', () async {
    final repository = TaskRepository();
    final store = TaskPersistenceStore(repository: repository);
    final runner = TaskStepRunner(
      persistence: store,
      recovery: const TaskRecoveryService(),
    );
    final saved = await store.save(
      root.path,
      _task(
        'task_1',
        status: TaskStatus.running,
        steps: [_step('step_1', TaskStepStatus.running)],
      ),
    );
    Task? received;

    final result = await runner.run(
      workspace: workspace,
      snapshot: saved.value,
      execute: (snapshot) async {
        received = snapshot;
        return snapshot;
      },
    );

    expect(received?.status, TaskStatus.blocked);
    expect(result.status, TaskStatus.blocked);
    expect(
      (await store.load(root.path, 'task_1'))?.value.status,
      TaskStatus.blocked,
    );
  });

  test('project run loop owns automatic continuation policy', () async {
    final initial = _project();
    var calls = 0;
    final result = await const ProjectRunLoop().run(
      _request(initial, workspace),
      boundedRun: false,
      iteration: (request) async {
        calls++;
        final next = calls == 1
            ? request.snapshot.copyWith(status: ProjectStatus.paused)
            : request.snapshot.copyWith(status: ProjectStatus.completed);
        return ProjectCommandResult.fromSnapshot(project: next);
      },
    );

    expect(calls, 2);
    expect(result.project.status, ProjectStatus.completed);
  });

  test('project recovery reconciles the canonical active task', () {
    final task = _task('task_1', status: TaskStatus.running);
    final project = _project(tasks: [task], activeTaskId: task.id);
    final recovered = const ProjectRecoveryService().reconcile(
      project: project,
      recoveredTask: _task('task_1', status: TaskStatus.blocked),
      now: DateTime(2026, 1, 2),
    );

    expect(recovered.status, ProjectStatus.blocked);
    expect(recovered.activeTaskId, task.id);
    expect(recovered.blocker?.type, ProjectBlockerType.taskBlocked);
  });
}

ProjectExecutionRequest _request(
  ProjectDocument project,
  WorkspaceAttachment workspace,
) => ProjectExecutionRequest(
  client: ChatClient(baseUrl: 'http://localhost', model: 'test'),
  workspace: workspace,
  snapshot: project,
  baseSystemPrompt: '',
  maxNewTasks: 1,
);

ProjectDocument _project({
  List<Task> tasks = const [],
  String? activeTaskId,
  ProjectStatus status = ProjectStatus.active,
}) {
  final now = DateTime(2026, 1, 1);
  return ProjectDocument(
    id: 'project_1',
    title: 'Project',
    originalGoal: 'Build it.',
    refinedGoal: 'Build it safely.',
    constraints: const [],
    criteria: [
      ProjectCriterion(
        id: 'criterion_1',
        statement: 'It works.',
        createdAt: now,
        updatedAt: now,
      ),
    ],
    tasks: [for (final task in tasks) ProjectTaskNode.fromTask(task)],
    status: status,
    activeTaskId: activeTaskId,
    createdAt: now,
    updatedAt: now,
  );
}

Task _task(
  String id, {
  TaskStatus status = TaskStatus.queued,
  List<TaskStep> steps = const [],
}) {
  final now = DateTime(2026, 1, 1);
  return Task(
    id: id,
    title: id,
    objective: 'Complete $id.',
    status: status,
    steps: steps,
    createdAt: now,
    updatedAt: now,
  );
}

TaskStep _step(String id, TaskStepStatus status) => TaskStep(
  id: id,
  title: id,
  objective: 'Complete $id.',
  instructions: const [],
  mayEditFiles: false,
  artifacts: const [],
  status: status,
);
