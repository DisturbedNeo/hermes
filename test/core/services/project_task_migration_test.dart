import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/serialization/model_json.dart';
import 'package:hermes/core/services/project_system/project_service.dart';
import 'package:hermes/core/services/task_system/task_repository.dart';
import 'package:hermes/core/services/task_system/task_service.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/core/services/workspace_sandbox.dart';
import 'package:path/path.dart' as path;

void main() {
  group('ProjectTaskSnapshotMigration', () {
    late Directory root;
    late WorkspaceAttachment workspace;
    late TaskRepository taskRepository;
    late ProjectService projectService;

    setUp(() async {
      root = await Directory.systemTemp.createTemp(
        'hermes_project_task_migration_',
      );
      workspace = WorkspaceAttachment(
        rootPath: root.path,
        displayName: 'Workspace',
        lastOpenedAt: DateTime(2026, 1, 1),
      );
      final sandbox = WorkspaceSandbox();
      final taskService = TaskService(
        toolService: ToolService(workspaceSandbox: sandbox),
        sandbox: sandbox,
      );
      taskRepository = taskService.repository;
      projectService = ProjectService(taskService: taskService);
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test(
      'merges legacy project tasks and task documents into canonical records',
      () async {
        final now = DateTime(2026, 1, 1);
        final project = _project(
          tasks: [
            _plannedTask(
              id: 'task_alpha',
              title: 'Build alpha',
              status: TaskStatus.completed,
              taskDocumentId: 'document_alpha',
              dependsOnTaskIds: const ['document_beta'],
            ),
            _plannedTask(
              id: 'task_beta',
              title: 'Build beta',
              taskDocumentId: 'document_beta',
            ),
          ],
          taskIds: const ['task_alpha', 'task_beta'],
          activeTaskId: 'document_alpha',
          status: ProjectStatus.reviewingTask,
          artifacts: [
            TaskArtifact(
              path: '.agent/tasks/document_alpha/report.md',
              description: 'Legacy report',
              taskId: 'document_alpha',
              createdAt: now,
            ),
          ],
          evidence: [
            ProjectEvidence(
              id: 'evidence_alpha',
              type: ProjectEvidenceType.artifact,
              taskId: 'document_alpha',
              sourceRef: '.agent/tasks/document_alpha/report.md',
              summary: 'The alpha report exists.',
              createdAt: now,
            ),
          ],
        );
        final executedTask = _executedTask(
          id: 'document_alpha',
          createdAt: now,
        );
        await _writeLegacyTask(root, executedTask);
        await taskRepository.saveLog(
          root.path,
          'document_alpha',
          'execution.log',
          'legacy execution history',
        );
        await _writeLegacyTask(
          root,
          _executedTask(id: 'document_orphan', createdAt: now),
        );
        final projectFile = await _writeLegacyProject(root, project);

        final migrated = await projectService.loadProject(
          workspace,
          project.id,
        );

        expect(migrated?.taskIds, ['task_alpha', 'task_beta']);
        expect(migrated?.activeTaskId, 'task_alpha');
        expect(migrated?.tasks.map((task) => task.id), [
          'task_alpha',
          'task_beta',
        ]);
        expect(migrated?.tasks[0].status, TaskStatus.completed);
        expect(migrated?.tasks[0].taskDocumentId, isNull);
        expect(migrated?.tasks[0].projectId, project.id);
        expect(migrated?.tasks[0].runs.single.summary, 'Legacy run');
        expect(
          migrated?.tasks[0].runs.single.artifacts.single.path,
          '.agent/tasks/task_alpha/report.md',
        );
        expect(migrated?.tasks[1].title, 'Build beta');
        expect(migrated?.tasks[1].status, TaskStatus.queued);
        expect(migrated?.tasks[0].dependsOnTaskIds, ['task_beta']);
        expect(migrated?.artifacts.single.taskId, 'task_alpha');
        expect(migrated?.artifacts.single.taskId, 'task_alpha');
        expect(
          migrated?.artifacts.single.path,
          '.agent/tasks/task_alpha/report.md',
        );
        expect(migrated?.evidence.single.taskId, 'task_alpha');

        final canonicalFile = File(
          path.join(root.path, '.agent', 'tasks', 'task_alpha', 'task.json'),
        );
        final legacyFile = File(
          path.join(
            root.path,
            '.agent',
            'tasks',
            'document_alpha',
            'task.json',
          ),
        );
        expect(canonicalFile.existsSync(), isTrue);
        expect(legacyFile.existsSync(), isFalse);
        expect(
          File(
            path.join(
              root.path,
              '.agent',
              'tasks',
              'task_alpha',
              'logs',
              'execution.log',
            ),
          ).readAsStringSync(),
          'legacy execution history',
        );
        expect(
          File(
            path.join(
              root.path,
              '.agent',
              'tasks',
              'document_orphan',
              'task.json',
            ),
          ).existsSync(),
          isTrue,
        );

        final rawProject = jsonDecode(await projectFile.readAsString());
        expect(rawProject['taskIds'], ['task_alpha', 'task_beta']);
        expect(rawProject['activeTaskId'], 'task_alpha');
        expect(rawProject.containsKey('tasks'), isFalse);

        final firstMigration = await projectFile.readAsString();
        final loadedAgain = await projectService.loadProject(
          workspace,
          project.id,
        );
        expect(loadedAgain?.tasks.map((task) => task.id), [
          'task_alpha',
          'task_beta',
        ]);
        expect(await projectFile.readAsString(), firstMigration);
      },
    );

    test(
      'creates a canonical task when the legacy document is missing',
      () async {
        final project = _project(
          tasks: [
            _plannedTask(
              id: 'task_partial',
              title: 'Partial task',
              taskDocumentId: 'document_missing',
            ),
          ],
          taskIds: const ['task_partial'],
        );
        final projectFile = await _writeLegacyProject(root, project);

        final migrated = await projectService.loadProject(
          workspace,
          project.id,
        );

        expect(migrated?.tasks.single.id, 'task_partial');
        expect(migrated?.tasks.single.title, 'Partial task');
        expect(migrated?.tasks.single.steps, isEmpty);
        expect(migrated?.tasks.single.projectId, project.id);
        expect(
          await taskRepository.loadTask(root.path, 'task_partial'),
          isNotNull,
        );
        expect(
          await taskRepository.loadTask(root.path, 'document_missing'),
          isNull,
        );
        expect(jsonDecode(await projectFile.readAsString())['tasks'], isNull);
      },
    );

    test('leaves an already-migrated project and task unchanged', () async {
      final task =
          _executedTask(
            id: 'task_canonical',
            createdAt: DateTime(2026, 1, 1),
          ).copyWith(
            projectId: 'project_migration',
            chatSessionId: 'chat_migration',
          );
      await taskRepository.saveSnapshot(root.path, task);
      final project = _project(
        tasks: const [],
        taskIds: const ['task_canonical'],
      );
      final projectFile = await _writeProject(root, project);
      final before = await projectFile.readAsString();

      final loaded = await projectService.loadProject(workspace, project.id);

      expect(loaded?.tasks.single.id, 'task_canonical');
      expect(loaded?.tasks.single.runs.single.summary, 'Legacy run');
      expect(await projectFile.readAsString(), before);
    });
  });
}

Future<File> _writeLegacyProject(
  Directory root,
  ProjectDocument project,
) async {
  final raw = ModelJson.encode(project);
  raw.remove('taskIds');
  raw['tasks'] = [for (final task in project.tasks) _legacyProjectTask(task)];
  raw['artifacts'] = [
    for (final value in (raw['artifacts'] as List? ?? const []))
      _legacyRelationship(value),
  ];
  raw['evidence'] = [
    for (final value in (raw['evidence'] as List? ?? const []))
      _legacyRelationship(value),
  ];
  return _writeRawProject(root, raw, project.id);
}

Map<String, dynamic> _legacyRelationship(Object value) {
  final raw = Map<String, dynamic>.from(value as Map);
  final taskId = raw.remove('taskId');
  if (taskId != null) raw['taskDocumentId'] = taskId;
  final runId = raw.remove('runId');
  if (runId != null) raw['taskRunId'] = runId;
  return raw;
}

Future<File> _writeProject(Directory root, ProjectDocument project) {
  return _writeRawProject(root, ModelJson.encode(project), project.id);
}

Future<File> _writeRawProject(
  Directory root,
  Map<String, dynamic> raw,
  String projectId,
) async {
  final file = File(
    path.join(root.path, '.agent', 'projects', projectId, 'project.json'),
  );
  await file.parent.create(recursive: true);
  await file.writeAsString(jsonEncode(raw));
  return file;
}

Future<void> _writeLegacyTask(Directory root, Task task) async {
  final raw = Map<String, dynamic>.from(ModelJson.encode(task))
    ..remove('objective')
    ..remove('criterionIds')
    ..remove('milestoneId')
    ..remove('dependsOnTaskIds')
    ..remove('priority')
    ..remove('risk')
    ..remove('riskReduction')
    ..remove('effort')
    ..remove('selectionRationale')
    ..remove('revisionIntroduced')
    ..remove('revisionUpdated')
    ..remove('expectedEvidence')
    ..remove('readPaths')
    ..remove('writePaths')
    ..remove('legacyWriteAccess')
    ..remove('doneCriteria')
    ..remove('outOfScope')
    ..remove('context')
    ..remove('expectedArtifacts')
    ..remove('recoveryIncidentId')
    ..remove('fingerprint')
    ..remove('rejectionReason')
    ..remove('failure');
  raw['goal'] = task.objective;
  final file = File(
    path.join(
      root.path,
      '.agent',
      'tasks',
      task.id,
      TaskRepository.documentFileName,
    ),
  );
  await file.parent.create(recursive: true);
  await file.writeAsString(jsonEncode(raw));
}

Map<String, dynamic> _legacyProjectTask(Task task) {
  final raw = Map<String, dynamic>.from(ModelJson.encode(task))
    ..remove('schemaVersion')
    ..remove('originalPrompt')
    ..remove('steps')
    ..remove('gates')
    ..remove('currentStepId')
    ..remove('memorySummary')
    ..remove('runs')
    ..remove('pendingApproval')
    ..remove('pendingQuestion')
    ..remove('chatSessionId')
    ..remove('projectId')
    ..remove('completedAt');
  if (task.taskDocumentId != null) {
    raw['taskDocumentId'] = task.taskDocumentId;
  }
  return raw;
}

ProjectDocument _project({
  required List<Task> tasks,
  required List<String> taskIds,
  String? activeTaskId,
  ProjectStatus status = ProjectStatus.active,
  List<TaskArtifact> artifacts = const [],
  List<ProjectEvidence> evidence = const [],
}) {
  final now = DateTime(2026, 1, 1);
  return ProjectDocument(
    id: 'project_migration',
    title: 'Migration project',
    originalGoal: 'Migrate the project safely.',
    refinedGoal: 'Migrate the project safely.',
    criteria: [
      ProjectCriterion(
        id: 'criterion_migration',
        statement: 'The project is migrated.',
        createdAt: now,
        updatedAt: now,
      ),
    ],
    constraints: const [],
    tasks: tasks,
    taskIds: taskIds,
    artifacts: artifacts,
    evidence: evidence,
    status: status,
    activeTaskId: activeTaskId,
    chatSessionId: 'chat_migration',
    createdAt: now,
    updatedAt: now,
  );
}

Task _plannedTask({
  required String id,
  required String title,
  TaskStatus status = TaskStatus.queued,
  String? taskDocumentId,
  List<String> dependsOnTaskIds = const [],
}) {
  final now = DateTime(2026, 1, 1);
  return Task(
    id: id,
    title: title,
    objective: '$title objective.',
    criterionIds: const ['criterion_migration'],
    dependsOnTaskIds: dependsOnTaskIds,
    doneCriteria: const ['The task is complete.'],
    fingerprint: '$id-fingerprint',
    status: status,
    taskDocumentId: taskDocumentId,
    createdAt: now,
    updatedAt: now,
  );
}

Task _executedTask({required String id, required DateTime createdAt}) {
  final run = TaskRun(
    runId: 'run_$id',
    stepId: 'step_execute',
    status: TaskRunStatus.completed,
    summary: 'Legacy run',
    memoryUpdate: 'Legacy history preserved.',
    toolCalls: const [],
    artifacts: [
      TaskArtifact(
        path: '.agent/tasks/$id/report.md',
        description: 'Legacy report',
      ),
    ],
    startedAt: createdAt,
    completedAt: createdAt,
  );
  return Task(
    id: id,
    title: 'Executed task',
    objective: 'Execute the task.',
    constraints: const ['Stay in workspace.'],
    successCriteria: const ['The task is complete.'],
    steps: const [
      TaskStep(
        id: 'step_execute',
        title: 'Execute',
        objective: 'Execute the task.',
        instructions: ['Run the task.'],
        mayEditFiles: false,
        status: TaskStepStatus.completed,
        artifacts: [TaskArtifact(path: '.agent/tasks/report.md')],
      ),
    ],
    status: TaskStatus.completed,
    currentStepId: 'step_execute',
    memorySummary: 'Legacy memory.',
    runs: [run],
    completedAt: createdAt,
    createdAt: createdAt,
    updatedAt: createdAt,
  );
}
