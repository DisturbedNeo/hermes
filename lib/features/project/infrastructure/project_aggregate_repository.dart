import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/features/task/domain/task.dart';
import 'package:hermes/core/serialization/model_json.dart';
import 'package:hermes/core/services/atomic_json_snapshot_store.dart';
import 'package:hermes/core/services/persistence_contracts.dart';
import 'package:hermes/features/project/application/project_application/project_checkpoint.dart';
import 'package:hermes/features/project/application/project_application/project_aggregate_repository_port.dart';
import 'package:hermes/features/project/application/project_application/project_repository_port.dart';
import 'package:hermes/features/task/application/task_application/task_ports.dart';
import 'package:hermes/features/workspace/application/workspace_ports.dart';
import 'package:path/path.dart' as path;

/// Commits the project document, canonical task documents, and task history as
/// one in-process coordinated aggregate operation.
class ProjectAggregateRepository implements ProjectAggregateRepositoryPort {
  ProjectAggregateRepository({
    required ProjectRepositoryPort projectRepository,
    required TaskRepositoryPort taskRepository,
    required PersistencePort coordinator,
    this.onTransactionPhase,
  }) : _projects = projectRepository,
       _tasks = taskRepository,
       _coordinator = coordinator;

  static const String transactionsDirectoryName = '.agent/transactions';

  final ProjectRepositoryPort _projects;
  final TaskRepositoryPort _tasks;
  final PersistencePort _coordinator;
  final AtomicJsonSnapshotStore _snapshots = const AtomicJsonSnapshotStore();
  final FutureOr<void> Function(String phase)? onTransactionPhase;

  Future<ProjectLoadResult> loadProject(
    String workspaceRoot,
    String projectId, {
    String? chatSessionId,
    bool includeHistory = true,
  }) {
    return _coordinator.synchronized(
      workspaceRoot,
      () => _loadProjectUnlocked(
        workspaceRoot,
        projectId,
        chatSessionId: chatSessionId,
        includeHistory: includeHistory,
      ),
    );
  }

  /// Checks aggregate health and revisions using only snapshot envelopes.
  ///
  /// This is the cheap path used before a command starts. Full aggregate
  /// decoding remains available through [loadProject] and [inspect].
  Future<ProjectRevisionCheckResult> checkRevisions(
    String workspaceRoot,
    ProjectDocument project,
  ) {
    return _coordinator.synchronized(
      workspaceRoot,
      () => _checkRevisionsUnlocked(workspaceRoot, project),
    );
  }

  Future<ProjectLoadResult> _loadProjectUnlocked(
    String workspaceRoot,
    String projectId, {
    String? chatSessionId,
    bool includeHistory = true,
  }) async {
    await _normalizeLegacyEmbeddedTasksUnlocked(workspaceRoot, projectId);
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
          warnings: ['Project primary snapshot is corrupt; loaded backup.'],
          recoveredFromBackup: [projectId],
        ),
      );
    }

    final missing = <String>[];
    final corrupt = <String>[];
    final recovered = <String>[];
    final canonicalTasks = <Task>[];
    final taskReads = await Future.wait<_TaskLoadRead>([
      for (final taskId in projectSnapshot.value.taskIds)
        _readTask(workspaceRoot, taskId, includeHistory: includeHistory),
    ]);
    for (final read in taskReads) {
      final task = read.snapshot;
      if (read.error != null) {
        corrupt.add(read.taskId);
        diagnostics = diagnostics.merge(
          ProjectPersistenceDiagnostics(
            issues: ['Task ${read.taskId} could not be decoded: ${read.error}'],
          ),
        );
      } else if (task == null) {
        missing.add(read.taskId);
      } else {
        canonicalTasks.add(task.value);
        if (task.fromBackup) recovered.add(read.taskId);
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
      canonicalTasks: List.unmodifiable(canonicalTasks),
    );
  }

  /// One-time compatibility migration for snapshots written before project
  /// and task ownership was separated. The migration reads embedded task
  /// definitions, creates missing canonical task documents, and rewrites the
  /// project document to contain only task IDs. Existing canonical task
  /// documents always win, so loading cannot overwrite executable history.
  Future<void> _normalizeLegacyEmbeddedTasksUnlocked(
    String workspaceRoot,
    String projectId,
  ) async {
    final file = File(_projects.projectSnapshotPath(workspaceRoot, projectId));
    late final SnapshotEnvelope envelope;
    try {
      final raw = await _snapshots.readMapWithoutRepair(file);
      if (raw == null) return;
      envelope = SnapshotEnvelope.decode(raw.map);
    } on FormatException {
      // Leave corruption handling to the repository, which can fall back to
      // the backup snapshot and report diagnostics consistently.
      return;
    } on SnapshotCorruptionException {
      return;
    }
    final embedded = envelope.document['tasks'];
    if (embedded is! List || embedded.isEmpty) return;

    final document = Map<String, dynamic>.from(envelope.document);
    final existingIds = <String>{
      for (final value
          in document['taskIds'] is List
              ? document['taskIds'] as List
              : const [])
        if (value is String && value.trim().isNotEmpty) value,
    };
    final migratedTasks = <Task>[];
    for (final value in embedded) {
      if (value is! Map) continue;
      try {
        final task = ModelJson.decode<Task>(Map<String, dynamic>.from(value));
        if (task.id.trim().isEmpty) continue;
        existingIds.add(task.id);
        final current = await _tasks.revisionOfUnlocked(workspaceRoot, task.id);
        if (current == null) {
          migratedTasks.add(
            task.copyWith(persistenceRevision: 0, projectId: projectId),
          );
        }
      } catch (_) {
        // A malformed legacy task is omitted and will be reported as a
        // missing/corrupt task by the normal aggregate load diagnostics.
      }
    }
    for (final task in migratedTasks) {
      await _tasks.saveSnapshotUnlocked(
        workspaceRoot,
        task,
        expectedRevision: 0,
        currentRevision: null,
      );
    }
    document
      ..remove('tasks')
      ..['taskIds'] = existingIds.toList(growable: false);
    await _snapshots.writeMap(
      file,
      SnapshotEnvelope.encode(document, envelope.revision),
    );
  }

  Future<_TaskLoadRead> _readTask(
    String workspaceRoot,
    String taskId, {
    required bool includeHistory,
  }) async {
    try {
      return _TaskLoadRead(
        taskId,
        await _tasks.loadTaskSnapshotUnlocked(
          workspaceRoot,
          taskId,
          includeHistory: includeHistory,
        ),
      );
    } catch (error) {
      return _TaskLoadRead(taskId, null, error);
    }
  }

  Future<ProjectRevisionCheckResult> _checkRevisionsUnlocked(
    String workspaceRoot,
    ProjectDocument project,
  ) async {
    var diagnostics = await _transactionDiagnostics(workspaceRoot);
    PersistedRevision? projectRevision;
    try {
      projectRevision = await _projects.revisionOfUnlocked(
        workspaceRoot,
        project.id,
      );
      if (projectRevision?.fromBackup == true) {
        diagnostics = diagnostics.merge(
          ProjectPersistenceDiagnostics(
            warnings: ['Project primary snapshot is corrupt; loaded backup.'],
            recoveredFromBackup: [project.id],
          ),
        );
      }
    } catch (error) {
      diagnostics = diagnostics.merge(
        ProjectPersistenceDiagnostics(
          issues: ['Project ${project.id} could not be read: $error'],
        ),
      );
    }

    // A newly-created project may be passed to the runner before its first
    // aggregate commit. There is no canonical task set to validate yet.
    if (projectRevision == null) {
      return ProjectRevisionCheckResult(
        projectRevision: null,
        taskRevisions: const {},
        diagnostics: diagnostics,
      );
    }

    final taskIds = <String>{
      ...project.taskIds,
      ...project.tasks.map((task) => task.id),
    };
    final taskRevisions = <String, PersistedRevision?>{};
    final revisionReads = await Future.wait<_TaskRevisionRead>([
      for (final taskId in taskIds) _readTaskRevision(workspaceRoot, taskId),
    ]);
    for (final read in revisionReads) {
      taskRevisions[read.taskId] = read.revision;
      if (read.error != null) {
        diagnostics = diagnostics.merge(
          ProjectPersistenceDiagnostics(
            corruptTaskIds: [read.taskId],
            issues: ['Task ${read.taskId} could not be read: ${read.error}'],
          ),
        );
      } else if (read.revision == null) {
        diagnostics = diagnostics.merge(
          ProjectPersistenceDiagnostics(missingTaskIds: [read.taskId]),
        );
      } else if (read.revision!.fromBackup) {
        diagnostics = diagnostics.merge(
          ProjectPersistenceDiagnostics(recoveredFromBackup: [read.taskId]),
        );
      }
    }

    return ProjectRevisionCheckResult(
      projectRevision: projectRevision,
      taskRevisions: taskRevisions,
      diagnostics: diagnostics,
    );
  }

  Future<_TaskRevisionRead> _readTaskRevision(
    String workspaceRoot,
    String taskId,
  ) async {
    try {
      return _TaskRevisionRead(
        taskId,
        await _tasks.revisionOfUnlocked(workspaceRoot, taskId),
      );
    } catch (error) {
      return _TaskRevisionRead(taskId, null, error);
    }
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

  /// Rolls back interrupted file transactions when the manifest and snapshot
  /// revisions make the rollback unambiguous. Transactions that cannot be
  /// proven safe remain visible and keep the aggregate read-only.
  Future<ProjectTransactionRecoveryResult> recoverInterruptedTransactions(
    String workspaceRoot,
  ) => _coordinator.synchronized(
    workspaceRoot,
    () => _recoverInterruptedTransactionsUnlocked(workspaceRoot),
  );

  Future<ProjectAggregateCommitResult> commit({
    required String workspaceRoot,
    required ProjectDocument project,
    required Iterable<Task> tasks,
    Set<String> deletedTaskIds = const {},
    ProjectPersistenceDiagnostics? knownHealth,
    ProjectPersistenceCheckpoint checkpoint =
        ProjectPersistenceCheckpoint.runtime,
  }) {
    return _coordinator.synchronized(
      workspaceRoot,
      () => _commitUnlocked(
        workspaceRoot: workspaceRoot,
        project: project,
        tasks: tasks.toList(growable: false),
        deletedTaskIds: deletedTaskIds,
        knownHealth: knownHealth,
        checkpoint: checkpoint,
      ),
    );
  }

  Future<ProjectAggregateCommitResult> _commitUnlocked({
    required String workspaceRoot,
    required ProjectDocument project,
    required List<Task> tasks,
    required Set<String> deletedTaskIds,
    ProjectPersistenceDiagnostics? knownHealth,
    required ProjectPersistenceCheckpoint checkpoint,
  }) async {
    final health =
        knownHealth ??
        (await _loadProjectUnlocked(workspaceRoot, project.id)).diagnostics;
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

    final transaction = await _beginTransaction(
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
      await Future.wait([
        for (final taskId in deletedTaskIds)
          _tasks.deleteTaskUnlocked(workspaceRoot, taskId),
      ]);
      final persistedProject = await _projects.saveSnapshotUnlocked(
        workspaceRoot,
        project,
        expectedRevision: project.persistenceRevision,
        currentRevision: currentProject,
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
            ProjectRepositoryPort.documentFileName,
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

  Future<ProjectTransactionRecoveryResult>
  _recoverInterruptedTransactionsUnlocked(String workspaceRoot) async {
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
      if (nextRevision == null || currentRevision != nextRevision) {
        return false;
      }
      if (await backup.exists()) {
        final backupRevision = await _revisionOfFile(backup);
        if (backupRevision != expectedRevision) return false;
        final content = await backup.readAsString();
        final decoded = jsonDecode(content);
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
      final content = await backup.readAsString();
      final decoded = jsonDecode(content);
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

  Future<_Transaction> _beginTransaction(
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
    final transaction = _Transaction(id: id, directory: directory);
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

  Future<void> _writeManifest(
    _Transaction transaction, {
    required String phase,
    required List<Map<String, dynamic>> entries,
    required ProjectPersistenceCheckpoint checkpoint,
  }) async {
    await _snapshots.writeMap(
      File(path.join(transaction.directory.path, 'manifest.json')),
      {
        'transactionId': transaction.id,
        'phase': phase,
        'checkpoint': checkpoint.wire,
        'entries': entries,
      },
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

class _TaskLoadRead {
  const _TaskLoadRead(this.taskId, this.snapshot, [this.error]);

  final String taskId;
  final PersistedSnapshot<Task>? snapshot;
  final Object? error;
}

class _TaskRevisionRead {
  const _TaskRevisionRead(this.taskId, this.revision, [this.error]);

  final String taskId;
  final PersistedRevision? revision;
  final Object? error;
}

class _Transaction {
  const _Transaction({required this.id, required this.directory});

  final String id;
  final Directory directory;
}
