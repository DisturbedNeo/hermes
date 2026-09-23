import 'dart:async';
import 'dart:io';

import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/serialization/model_json.dart';
import 'package:hermes/core/services/atomic_json_snapshot_store.dart';
import 'package:hermes/core/services/persistence_contracts.dart';
import 'package:hermes/core/services/project_system/project_repository.dart';
import 'package:hermes/core/services/task_system/task_repository.dart';
import 'package:hermes/core/services/workspace_persistence_coordinator.dart';
import 'package:path/path.dart' as path;

/// The result of loading a project together with storage health information.
class ProjectLoadResult {
  const ProjectLoadResult({required this.project, required this.diagnostics});

  final ProjectDocument? project;
  final ProjectPersistenceDiagnostics diagnostics;
}

class ProjectAggregateCommitResult {
  const ProjectAggregateCommitResult({
    required this.project,
    required this.tasks,
  });

  final PersistedSnapshot<ProjectDocument> project;
  final Map<String, PersistedSnapshot<Task>> tasks;
}

/// Commits the project document, canonical task documents, and task history as
/// one in-process coordinated aggregate operation.
class ProjectAggregateRepository {
  ProjectAggregateRepository({
    required ProjectRepository projectRepository,
    required TaskRepository taskRepository,
    required WorkspacePersistenceCoordinator coordinator,
    this.onTransactionPhase,
  }) : _projects = projectRepository,
       _tasks = taskRepository,
       _coordinator = coordinator;

  static const String transactionsDirectoryName = '.agent/transactions';

  final ProjectRepository _projects;
  final TaskRepository _tasks;
  final WorkspacePersistenceCoordinator _coordinator;
  final AtomicJsonSnapshotStore _snapshots = const AtomicJsonSnapshotStore();
  final FutureOr<void> Function(String phase)? onTransactionPhase;

  Future<ProjectLoadResult> loadProject(
    String workspaceRoot,
    String projectId, {
    String? chatSessionId,
  }) {
    return _coordinator.synchronized(
      workspaceRoot,
      () => _loadProjectUnlocked(
        workspaceRoot,
        projectId,
        chatSessionId: chatSessionId,
      ),
    );
  }

  Future<ProjectLoadResult> _loadProjectUnlocked(
    String workspaceRoot,
    String projectId, {
    String? chatSessionId,
  }) async {
    final projectSnapshot = await _projects.loadProjectSnapshotUnlocked(
      workspaceRoot,
      projectId,
      chatSessionId: chatSessionId,
    );
    if (projectSnapshot == null) {
      return const ProjectLoadResult(
        project: null,
        diagnostics: ProjectPersistenceDiagnostics(),
      );
    }

    var diagnostics = await _transactionDiagnostics(workspaceRoot);
    if (projectSnapshot.fromBackup) {
      diagnostics = diagnostics.merge(
        ProjectPersistenceDiagnostics(
          issues: ['Project primary snapshot is corrupt; loaded backup.'],
          recoveredFromBackup: [projectId],
        ),
      );
    }

    final missing = <String>[];
    final corrupt = <String>[];
    final recovered = <String>[];
    for (final taskId in projectSnapshot.value.taskIds) {
      try {
        final task = await _tasks.loadTaskSnapshotUnlocked(
          workspaceRoot,
          taskId,
          includeHistory: true,
        );
        if (task == null) {
          missing.add(taskId);
        } else if (task.fromBackup) {
          recovered.add(taskId);
        }
      } catch (error) {
        corrupt.add(taskId);
        diagnostics = diagnostics.merge(
          ProjectPersistenceDiagnostics(
            issues: ['Task $taskId could not be decoded: $error'],
          ),
        );
      }
    }
    diagnostics = diagnostics.merge(
      ProjectPersistenceDiagnostics(
        missingTaskIds: missing,
        corruptTaskIds: corrupt,
        recoveredFromBackup: recovered,
      ),
    );
    return ProjectLoadResult(
      project: projectSnapshot.value,
      diagnostics: diagnostics,
    );
  }

  Future<ProjectPersistenceDiagnostics> inspect(
    String workspaceRoot,
    ProjectDocument project,
  ) async {
    final loaded = await _coordinator.synchronized(
      workspaceRoot,
      () => _loadProjectUnlocked(workspaceRoot, project.id),
    );
    return loaded.diagnostics;
  }

  Future<ProjectAggregateCommitResult> commit({
    required String workspaceRoot,
    required ProjectDocument project,
    required Iterable<Task> tasks,
    Set<String> deletedTaskIds = const {},
  }) {
    return _coordinator.synchronized(
      workspaceRoot,
      () => _commitUnlocked(
        workspaceRoot: workspaceRoot,
        project: project,
        tasks: tasks.toList(growable: false),
        deletedTaskIds: deletedTaskIds,
      ),
    );
  }

  Future<ProjectAggregateCommitResult> _commitUnlocked({
    required String workspaceRoot,
    required ProjectDocument project,
    required List<Task> tasks,
    required Set<String> deletedTaskIds,
  }) async {
    final health = (await _loadProjectUnlocked(
      workspaceRoot,
      project.id,
    )).diagnostics;
    if (health.isReadOnly) {
      throw ProjectPersistenceBlockedException(health);
    }

    final currentProject = await _projects.loadProjectSnapshotUnlocked(
      workspaceRoot,
      project.id,
    );
    final expectedProjectRevision = project.persistenceRevision;
    final actualProjectRevision = currentProject?.revision ?? 0;
    if (expectedProjectRevision != actualProjectRevision) {
      throw StaleSnapshotException(
        path: _projects.projectRelativePath(
          project.id,
          ProjectRepository.documentFileName,
        ),
        expectedRevision: expectedProjectRevision,
        actualRevision: actualProjectRevision,
      );
    }

    final uniqueTasks = <String, Task>{};
    for (final task in tasks) {
      if (uniqueTasks.containsKey(task.id)) continue;
      uniqueTasks[task.id] = task;
      final current = await _tasks.loadTaskSnapshotUnlocked(
        workspaceRoot,
        task.id,
        includeHistory: true,
      );
      final actualRevision = current?.revision ?? 0;
      if (task.persistenceRevision != actualRevision) {
        throw StaleSnapshotException(
          path: _tasks.taskRelativePath(
            task.id,
            TaskRepository.documentFileName,
          ),
          expectedRevision: task.persistenceRevision,
          actualRevision: actualRevision,
        );
      }
    }

    for (final taskId in deletedTaskIds) {
      if (project.taskIds.contains(taskId)) {
        throw ArgumentError(
          'Deleted task $taskId is still referenced by project',
        );
      }
    }

    final transaction = await _beginTransaction(
      workspaceRoot,
      project: project,
      tasks: uniqueTasks.values,
      deletedTaskIds: deletedTaskIds,
    );
    try {
      final persistedTasks = <String, PersistedSnapshot<Task>>{};
      for (final task in uniqueTasks.values) {
        await _tasks.saveSnapshot(workspaceRoot, task);
        final persisted = await _tasks.loadTaskSnapshotUnlocked(
          workspaceRoot,
          task.id,
          includeHistory: true,
        );
        if (persisted == null) {
          throw const FormatException('Task disappeared after aggregate write');
        }
        persistedTasks[task.id] = persisted;
      }
      for (final taskId in deletedTaskIds) {
        await _tasks.deleteTaskUnlocked(workspaceRoot, taskId);
      }
      final persistedProject = await _projects.saveSnapshotUnlocked(
        workspaceRoot,
        project,
        expectedRevision: project.persistenceRevision,
      );
      await _markCommitted(transaction);
      await onTransactionPhase?.call('committed');
      await _removeTransaction(transaction);
      return ProjectAggregateCommitResult(
        project: persistedProject,
        tasks: persistedTasks,
      );
    } catch (_) {
      // The manifest deliberately remains for load-time diagnostics. No
      // replay or repair is attempted here.
      rethrow;
    }
  }

  Future<bool> deleteProject(String workspaceRoot, ProjectDocument project) {
    return _coordinator.synchronized(workspaceRoot, () async {
      final transactionDiagnostics = await _transactionDiagnostics(
        workspaceRoot,
      );
      if (transactionDiagnostics.issues.isNotEmpty ||
          transactionDiagnostics.interruptedTransactionIds.isNotEmpty) {
        throw ProjectPersistenceBlockedException(transactionDiagnostics);
      }
      final current = await _projects.loadProjectSnapshotUnlocked(
        workspaceRoot,
        project.id,
      );
      final expected = project.persistenceRevision;
      final actual = current?.revision ?? 0;
      if (expected != actual) {
        throw StaleSnapshotException(
          path: _projects.projectRelativePath(
            project.id,
            ProjectRepository.documentFileName,
          ),
          expectedRevision: expected,
          actualRevision: actual,
        );
      }
      final taskIds = <String>{...project.taskIds};
      final taskSummaries = await _tasks.listTasks(
        workspaceRoot,
        projectId: project.id,
      );
      taskIds.addAll(taskSummaries.map((task) => task.id));
      final taskRevisions = <String, int>{};
      for (final taskId in taskIds) {
        final task = await _tasks.loadTaskSnapshotUnlocked(
          workspaceRoot,
          taskId,
          includeHistory: false,
        );
        if (task != null) taskRevisions[taskId] = task.revision;
      }
      final transaction = await _beginTransaction(
        workspaceRoot,
        project: project,
        tasks: const [],
        deletedTaskIds: taskIds,
        deletedTaskRevisions: taskRevisions,
        deletingProject: true,
      );
      try {
        for (final taskId in taskIds) {
          await _tasks.deleteTaskUnlocked(workspaceRoot, taskId);
        }
        final deleted = await _projects.deleteProjectUnlocked(
          workspaceRoot,
          project.id,
        );
        await _markCommitted(transaction);
        await onTransactionPhase?.call('committed');
        await _removeTransaction(transaction);
        return deleted;
      } catch (_) {
        rethrow;
      }
    });
  }

  Future<_Transaction> _beginTransaction(
    String workspaceRoot, {
    required ProjectDocument project,
    required Iterable<Task> tasks,
    required Set<String> deletedTaskIds,
    Map<String, int> deletedTaskRevisions = const {},
    bool deletingProject = false,
  }) async {
    final id = 'tx_${DateTime.now().microsecondsSinceEpoch}_$pid';
    final directory = Directory(
      path.join(workspaceRoot, transactionsDirectoryName, id),
    );
    await directory.create(recursive: true);
    final transaction = _Transaction(id: id, directory: directory);
    final entries = <Map<String, dynamic>>[
      {
        'kind': 'project',
        'path': _projects.projectRelativePath(
          project.id,
          ProjectRepository.documentFileName,
        ),
        'operation': deletingProject ? 'delete' : 'write',
        'expectedRevision': project.persistenceRevision,
        'nextRevision': deletingProject
            ? null
            : project.persistenceRevision + 1,
      },
      for (final task in tasks)
        {
          'kind': 'task',
          'path': _tasks.taskRelativePath(
            task.id,
            TaskRepository.documentFileName,
          ),
          'operation': 'write',
          'expectedRevision': task.persistenceRevision,
          'nextRevision': task.persistenceRevision + 1,
        },
      for (final taskId in deletedTaskIds)
        {
          'kind': 'task',
          'path': _tasks.taskRelativePath(
            taskId,
            TaskRepository.documentFileName,
          ),
          'operation': 'delete',
          'expectedRevision': deletedTaskRevisions[taskId],
        },
    ];
    await _writeManifest(transaction, phase: 'prepared', entries: entries);
    await onTransactionPhase?.call('prepared');

    final staged = Directory(path.join(directory.path, 'staged'));
    await staged.create(recursive: true);
    await _snapshots.writeMap(
      File(path.join(staged.path, 'manifest-input.json')),
      {
        'project': ModelJson.encode(project.copyWith(persistenceRevision: 0)),
        'tasks': [
          for (final task in tasks)
            ModelJson.encode(task.copyWith(persistenceRevision: 0)),
        ],
      },
    );
    await onTransactionPhase?.call('staged');
    await _setTransactionPhase(transaction, 'committing');
    await onTransactionPhase?.call('committing');
    return transaction;
  }

  Future<void> _writeManifest(
    _Transaction transaction, {
    required String phase,
    required List<Map<String, dynamic>> entries,
  }) async {
    await _snapshots.writeMap(
      File(path.join(transaction.directory.path, 'manifest.json')),
      {'transactionId': transaction.id, 'phase': phase, 'entries': entries},
    );
  }

  Future<void> _markCommitted(_Transaction transaction) async {
    await _setTransactionPhase(transaction, 'committed');
  }

  Future<void> _setTransactionPhase(
    _Transaction transaction,
    String phase,
  ) async {
    final manifest = File(
      path.join(transaction.directory.path, 'manifest.json'),
    );
    final raw = await _snapshots.readMapWithoutRepair(manifest);
    final map = raw?.map ?? <String, dynamic>{};
    map['phase'] = phase;
    await _snapshots.writeMap(manifest, map);
  }

  Future<void> _removeTransaction(_Transaction transaction) async {
    if (await transaction.directory.exists()) {
      await transaction.directory.delete(recursive: true);
    }
  }

  Future<ProjectPersistenceDiagnostics> _transactionDiagnostics(
    String workspaceRoot,
  ) async {
    final root = Directory(path.join(workspaceRoot, transactionsDirectoryName));
    if (!await root.exists()) return const ProjectPersistenceDiagnostics();
    final interrupted = <String>[];
    final issues = <String>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final manifest = File(path.join(entity.path, 'manifest.json'));
      if (!await manifest.exists()) {
        issues.add(
          'Transaction ${path.basename(entity.path)} has no manifest.',
        );
        continue;
      }
      try {
        final raw = await _snapshots.readMapWithoutRepair(manifest);
        if (raw == null) continue;
        final phase = raw.map['phase'];
        if (phase == 'committed') {
          await entity.delete(recursive: true);
        } else {
          interrupted.add(path.basename(entity.path));
        }
      } catch (error) {
        interrupted.add(path.basename(entity.path));
        issues.add(
          'Transaction ${path.basename(entity.path)} is unreadable: $error',
        );
      }
    }
    return ProjectPersistenceDiagnostics(
      issues: issues,
      interruptedTransactionIds: interrupted,
    );
  }
}

class _Transaction {
  const _Transaction({required this.id, required this.directory});

  final String id;
  final Directory directory;
}
