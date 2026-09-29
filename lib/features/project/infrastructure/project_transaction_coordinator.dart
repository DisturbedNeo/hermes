import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hermes/shared_kernel/model_json.dart';
import 'package:hermes/shared_kernel/atomic_json_snapshot_store.dart';
import 'package:hermes/shared_kernel/persistence_contracts.dart';
import 'package:hermes/shared_kernel/project.dart';
import 'package:hermes/features/project/project_aggregate_repository_port.dart';
import 'package:hermes/features/project/project_repository_port.dart';
import 'package:hermes/shared_kernel/project_checkpoint.dart';
import 'package:hermes/shared_kernel/task.dart';
import 'package:hermes/shared_kernel/task_persistence_ports.dart';
import 'package:path/path.dart' as path;

/// Owns aggregate transaction manifests, commit ordering, and recovery.
/// ProjectAggregateRepository delegates these concerns here and remains a
/// reader/coordinator for aggregate snapshots.
class ProjectTransactionCoordinator {
  ProjectTransactionCoordinator({
    required ProjectRepositoryPort projectRepository,
    required TaskPersistencePort taskRepository,
    this.onTransactionPhase,
    AtomicJsonSnapshotStore snapshots = const AtomicJsonSnapshotStore(),
  }) : _projects = projectRepository,
       _tasks = taskRepository,
       _snapshots = snapshots;

  static const String transactionsDirectoryName = '.agent/transactions';

  final ProjectRepositoryPort _projects;
  final TaskPersistencePort _tasks;
  final AtomicJsonSnapshotStore _snapshots;
  final FutureOr<void> Function(String phase)? onTransactionPhase;

  Future<ProjectAggregateCommitResult> commit({
    required String workspaceRoot,
    required ProjectDocument project,
    required List<Task> tasks,
    required Set<String> deletedTaskIds,
    required ProjectPersistenceDiagnostics health,
    required ProjectPersistenceCheckpoint checkpoint,
  }) async {
    if (health.isReadOnly) {
      throw ProjectPersistenceBlockedException(health);
    }

    final currentProject = await _projects.revisionOfUnlocked(
      workspaceRoot,
      project.id,
    );
    final expectedProjectRevision = project.persistenceRevision;
    final actualProjectRevision = currentProject?.revision ?? 0;
    if (expectedProjectRevision != actualProjectRevision) {
      throw StaleSnapshotException(
        path: _projects.projectRelativePath(
          project.id,
          ProjectRepositoryPort.documentFileName,
        ),
        expectedRevision: expectedProjectRevision,
        actualRevision: actualProjectRevision,
      );
    }

    final uniqueTasks = <String, Task>{};
    for (final task in tasks) {
      if (uniqueTasks.containsKey(task.id)) continue;
      uniqueTasks[task.id] = task;
    }
    final taskRevisions = await _tasks.revisionOfManyUnlocked(
      workspaceRoot,
      uniqueTasks.keys,
    );
    for (final task in uniqueTasks.values) {
      final current = taskRevisions[task.id];
      final actualRevision = current?.revision ?? 0;
      if (task.persistenceRevision != actualRevision) {
        throw StaleSnapshotException(
          path: _tasks.taskRelativePath(
            task.id,
            TaskStorageLayout.documentFileName,
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

    final transaction = await begin(
      workspaceRoot,
      project: project,
      tasks: uniqueTasks.values,
      deletedTaskIds: deletedTaskIds,
      checkpoint: checkpoint,
    );
    try {
      final persistedTaskEntries =
          await Future.wait<MapEntry<String, PersistedSnapshot<Task>>>([
            for (final task in uniqueTasks.values)
              _saveTask(
                workspaceRoot,
                task,
                currentRevision: taskRevisions[task.id],
              ),
          ]);
      final persistedTasks = Map<String, PersistedSnapshot<Task>>.fromEntries(
        persistedTaskEntries,
      );
      await Future.wait<void>([
        for (final taskId in deletedTaskIds)
          _tasks.deleteTaskUnlocked(workspaceRoot, taskId),
      ]);
      final persistedProject = await _projects.saveSnapshotUnlocked(
        workspaceRoot,
        project,
        expectedRevision: project.persistenceRevision,
        currentRevision: currentProject,
      );
      await markCommitted(transaction);
      await onTransactionPhase?.call('committed');
      await remove(transaction);
      return ProjectAggregateCommitResult(
        project: persistedProject,
        tasks: persistedTasks,
      );
    } catch (_) {
      // Keep the manifest for load-time diagnostics. Recovery is explicit.
      rethrow;
    }
  }

  Future<ProjectTransactionRecoveryResult> recoverInterruptedTransactions(
    String workspaceRoot,
  ) async {
    final root = Directory(path.join(workspaceRoot, transactionsDirectoryName));
    if (!await root.exists()) return const ProjectTransactionRecoveryResult();
    final recovered = <String>[];
    final unresolved = <String>[];
    final issues = <String>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final id = path.basename(entity.path);
      final manifestFile = File(path.join(entity.path, 'manifest.json'));
      if (!await manifestFile.exists()) {
        unresolved.add(id);
        issues.add('Transaction $id has no manifest.');
        continue;
      }
      Map<String, dynamic> manifest;
      try {
        final raw = await _snapshots.readMapWithoutRepair(manifestFile);
        if (raw == null) {
          unresolved.add(id);
          issues.add('Transaction $id has an empty manifest.');
          continue;
        }
        manifest = raw.map;
      } catch (error) {
        unresolved.add(id);
        issues.add('Transaction $id is unreadable: $error');
        continue;
      }
      if (manifest['phase'] == 'committed') {
        await entity.delete(recursive: true);
        recovered.add(id);
        continue;
      }
      final entries = manifest['entries'];
      if (entries is! List) {
        unresolved.add(id);
        issues.add('Transaction $id has no rollback entries.');
        continue;
      }
      var safe = true;
      for (final rawEntry in entries) {
        if (rawEntry is! Map) {
          safe = false;
          issues.add('Transaction $id contains an invalid rollback entry.');
          continue;
        }
        final entry = Map<String, dynamic>.from(rawEntry);
        final relative = entry['path'];
        final operation = entry['operation'];
        if (relative is! String || operation is! String) {
          safe = false;
          issues.add('Transaction $id contains an incomplete rollback entry.');
          continue;
        }
        final restored = await _rollbackEntry(
          workspaceRoot: workspaceRoot,
          relativePath: relative,
          operation: operation,
          expectedRevision: (entry['expectedRevision'] as num?)?.toInt(),
          nextRevision: (entry['nextRevision'] as num?)?.toInt(),
        );
        if (!restored) {
          safe = false;
          issues.add('Transaction $id could not safely roll back $relative.');
        }
      }
      if (safe) {
        await entity.delete(recursive: true);
        recovered.add(id);
      } else {
        unresolved.add(id);
      }
    }
    return ProjectTransactionRecoveryResult(
      recoveredTransactionIds: recovered,
      unresolvedTransactionIds: unresolved,
      issues: issues,
    );
  }

  Future<ProjectPersistenceDiagnostics> transactionDiagnostics(
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
        if (raw.map['phase'] == 'committed') {
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

  Future<ProjectTransaction> begin(
    String workspaceRoot, {
    required ProjectDocument project,
    required Iterable<Task> tasks,
    required Set<String> deletedTaskIds,
    ProjectPersistenceCheckpoint checkpoint =
        ProjectPersistenceCheckpoint.runtime,
    Map<String, int> deletedTaskRevisions = const {},
    bool deletingProject = false,
  }) async {
    final id = 'tx_${DateTime.now().microsecondsSinceEpoch}_$pid';
    final directory = Directory(
      path.join(workspaceRoot, transactionsDirectoryName, id),
    );
    await directory.create(recursive: true);
    final transaction = ProjectTransaction(id: id, directory: directory);
    final entries = <Map<String, dynamic>>[
      {
        'kind': 'project',
        'path': _projects.projectRelativePath(
          project.id,
          ProjectRepositoryPort.documentFileName,
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
            TaskStorageLayout.documentFileName,
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
            TaskStorageLayout.documentFileName,
          ),
          'operation': 'delete',
          'expectedRevision': deletedTaskRevisions[taskId],
        },
    ];
    await _writeManifest(
      transaction,
      phase: 'prepared',
      entries: entries,
      checkpoint: checkpoint,
    );
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

  Future<void> markCommitted(ProjectTransaction transaction) async {
    await _setTransactionPhase(transaction, 'committed');
  }

  Future<void> remove(ProjectTransaction transaction) async {
    if (await transaction.directory.exists()) {
      await transaction.directory.delete(recursive: true);
    }
  }

  Future<MapEntry<String, PersistedSnapshot<Task>>> _saveTask(
    String workspaceRoot,
    Task task, {
    required PersistedRevision? currentRevision,
  }) async {
    final persisted = await _tasks.saveSnapshotUnlocked(
      workspaceRoot,
      task,
      expectedRevision: task.persistenceRevision,
      currentRevision: currentRevision,
    );
    return MapEntry(task.id, persisted);
  }

  Future<bool> _rollbackEntry({
    required String workspaceRoot,
    required String relativePath,
    required String operation,
    required int? expectedRevision,
    required int? nextRevision,
  }) async {
    final primary = File(path.join(workspaceRoot, relativePath));
    final backup = _snapshots.backupFor(primary);
    final currentRevision = await _revisionOfFile(primary);
    if (operation == 'write') {
      if (currentRevision == null || currentRevision == expectedRevision) {
        return true;
      }
      if (nextRevision == null || currentRevision != nextRevision) return false;
      if (await backup.exists()) {
        final backupRevision = await _revisionOfFile(backup);
        if (backupRevision != expectedRevision) return false;
        final decoded = jsonDecode(await backup.readAsString());
        if (decoded is! Map) return false;
        await _snapshots.writeMap(primary, Map<String, dynamic>.from(decoded));
        return true;
      }
      if (expectedRevision == 0) {
        if (await primary.exists()) await primary.delete();
        return true;
      }
      return false;
    }
    if (operation == 'delete') {
      if (currentRevision == null) return true;
      if (!await backup.exists()) return false;
      final backupRevision = await _revisionOfFile(backup);
      if (expectedRevision != null && backupRevision != expectedRevision) {
        return false;
      }
      final decoded = jsonDecode(await backup.readAsString());
      if (decoded is! Map) return false;
      await _snapshots.writeMap(primary, Map<String, dynamic>.from(decoded));
      return true;
    }
    return false;
  }

  Future<int?> _revisionOfFile(File file) async {
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      return SnapshotEnvelope.decode(
        Map<String, dynamic>.from(decoded),
      ).revision;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeManifest(
    ProjectTransaction transaction, {
    required String phase,
    required List<Map<String, dynamic>> entries,
    required ProjectPersistenceCheckpoint checkpoint,
  }) => _snapshots
      .writeMap(File(path.join(transaction.directory.path, 'manifest.json')), {
        'transactionId': transaction.id,
        'phase': phase,
        'checkpoint': checkpoint.wire,
        'entries': entries,
      });

  Future<void> _setTransactionPhase(
    ProjectTransaction transaction,
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
}

class ProjectTransaction {
  const ProjectTransaction({required this.id, required this.directory});

  final String id;
  final Directory directory;
}
