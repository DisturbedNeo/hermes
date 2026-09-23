import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/persistence_contracts.dart';
import 'package:hermes/core/services/project_system/orchestration_contracts.dart';
import 'package:hermes/core/services/project_system/project_completion_service.dart';
import 'package:hermes/core/services/project_system/project_lifecycle_service.dart';
import 'package:hermes/core/services/project_system/project_orchestrator.dart';
import 'package:hermes/core/services/task_system/task_lifecycle_service.dart';
import 'package:hermes/core/services/task_system/task_service.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/core/services/workspace_sandbox.dart';

void main() {
  late Directory root;
  late TaskService taskService;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('hermes_orchestration_');
    final sandbox = WorkspaceSandbox();
    taskService = TaskService(
      toolService: ToolService(workspaceSandbox: sandbox),
      sandbox: sandbox,
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('project lifecycle transitions enforce task and completion guards', () {
    final lifecycle = const ProjectLifecycleService();
    final task = _task('task_1');
    final project = _project(tasks: [task]);

    final running = lifecycle.transition(
      snapshot: project,
      to: ProjectStatus.runningTask,
      trigger: ProjectLifecycleTrigger.startTask,
      taskId: task.id,
    );
    expect(running.project.status, ProjectStatus.runningTask);
    expect(running.project.activeTaskId, task.id);

    final reviewing = lifecycle.transition(
      snapshot: running.project,
      to: ProjectStatus.reviewingTask,
      trigger: ProjectLifecycleTrigger.taskReview,
      taskId: task.id,
    );
    expect(reviewing.project.status, ProjectStatus.reviewingTask);

    expect(
      () => lifecycle.transition(
        snapshot: reviewing.project,
        to: ProjectStatus.completed,
        trigger: ProjectLifecycleTrigger.completion,
      ),
      throwsA(isA<InvalidProjectTransitionException>()),
    );
    expect(reviewing.project.status, ProjectStatus.reviewingTask);
  });

  test(
    'task lifecycle permits explicit retry but rejects generic terminal exits',
    () {
      final lifecycle = const TaskLifecycleService();
      final failed = _task('task_1', status: TaskStatus.failed);

      final retried = lifecycle.transition(
        snapshot: failed,
        to: TaskStatus.paused,
        trigger: TaskLifecycleTrigger.retry,
      );
      expect(retried.task.status, TaskStatus.paused);

      expect(
        () => lifecycle.transition(
          snapshot: failed,
          to: TaskStatus.running,
          trigger: TaskLifecycleTrigger.execution,
        ),
        throwsA(isA<InvalidTaskTransitionException>()),
      );
    },
  );

  test('completion service is the only successful completion boundary', () {
    final now = DateTime(2026, 1, 1);
    final project = _project(
      criteria: [
        ProjectCriterion(
          id: 'criterion_1',
          statement: 'The work is complete.',
          status: ProjectCriterionStatus.satisfied,
          createdAt: now,
          updatedAt: now,
        ),
      ],
    );

    final completed = const ProjectCompletionService().completeFromEvidence(
      project: project,
      summary: 'Verified.',
      now: now,
    );
    expect(completed.project.status, ProjectStatus.completed);
    expect(completed.project.completionSummary, 'Verified.');
    expect(completed.transition.to, ProjectStatus.completed);
  });

  test('orchestrator rejects a stale revision before execution', () async {
    var executionCalls = 0;
    final orchestrator = ProjectOrchestrator(
      taskService: taskService,
      executionOverride: (request) async {
        executionCalls++;
        return ProjectCommandResult.fromSnapshot(project: request.snapshot);
      },
    );
    final saved = await orchestrator.repository.saveSnapshot(
      root.path,
      _project(),
    );
    final stale = saved.value.copyWith(persistenceRevision: 0);

    await expectLater(
      orchestrator.execute(_request(stale, root.path)),
      throwsA(isA<StaleSnapshotException>()),
    );
    expect(executionCalls, 0);
  });

  test(
    'orchestrator executes and recovers through canonical commands',
    () async {
      var executionCalls = 0;
      var recoveryCalls = 0;
      final orchestrator = ProjectOrchestrator(
        taskService: taskService,
        executionOverride: (request) async {
          executionCalls++;
          return ProjectCommandResult.fromSnapshot(project: request.snapshot);
        },
        recoveryOverride: (request) async {
          recoveryCalls++;
          return ProjectCommandResult.fromSnapshot(project: request.snapshot);
        },
      );
      final saved = await orchestrator.repository.saveSnapshot(
        root.path,
        _project(),
      );
      final workspace = WorkspaceAttachment(
        rootPath: root.path,
        displayName: 'Workspace',
        lastOpenedAt: DateTime(2026, 1, 1),
      );

      final executed = await orchestrator.execute(
        _request(saved.value, root.path),
      );
      final recovered = await orchestrator.recover(
        ProjectRecoveryRequest(
          workspace: workspace,
          snapshot: executed.project,
        ),
      );

      expect(executed, isA<ProjectCommandResult>());
      expect(recovered, isA<ProjectCommandResult>());
      expect(executionCalls, 1);
      expect(recoveryCalls, 1);
    },
  );

  test(
    'orchestrator rejects a second command for the same project as busy',
    () async {
      final release = Completer<ProjectCommandResult>();
      final orchestrator = ProjectOrchestrator(
        taskService: taskService,
        executionOverride: (request) => release.future,
      );
      final saved = await orchestrator.repository.saveSnapshot(
        root.path,
        _project(),
      );
      final first = orchestrator.execute(_request(saved.value, root.path));

      await expectLater(
        orchestrator.execute(_request(saved.value, root.path)),
        throwsA(isA<ProjectBusyException>()),
      );

      release.complete(ProjectCommandResult.fromSnapshot(project: saved.value));
      await first;
    },
  );
}

ProjectExecutionRequest _request(ProjectDocument project, String rootPath) =>
    ProjectExecutionRequest(
      client: ChatClient(baseUrl: 'http://localhost', model: 'test'),
      workspace: WorkspaceAttachment(
        rootPath: rootPath,
        displayName: 'Workspace',
        lastOpenedAt: DateTime(2026, 1, 1),
      ),
      snapshot: project,
      baseSystemPrompt: '',
      maxNewTasks: 1,
    );

ProjectDocument _project({
  List<Task> tasks = const [],
  List<ProjectCriterion>? criteria,
}) {
  final now = DateTime(2026, 1, 1);
  return ProjectDocument(
    id: 'project_1',
    title: 'Project',
    originalGoal: 'Build the project.',
    refinedGoal: 'Build the project safely.',
    criteria:
        criteria ??
        [
          ProjectCriterion(
            id: 'criterion_1',
            statement: 'The work is complete.',
            createdAt: now,
            updatedAt: now,
          ),
        ],
    constraints: const [],
    tasks: tasks,
    status: ProjectStatus.active,
    activeTaskId: null,
    createdAt: now,
    updatedAt: now,
  );
}

Task _task(String id, {TaskStatus status = TaskStatus.queued}) {
  final now = DateTime(2026, 1, 1);
  return Task(
    id: id,
    title: id,
    objective: 'Complete $id.',
    status: status,
    createdAt: now,
    updatedAt: now,
  );
}
