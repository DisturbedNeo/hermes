import 'dart:async';

import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/shared_kernel/persistence_contracts.dart';
import 'package:hermes/features/project/infrastructure/project_snapshot_migrator.dart';
import 'package:hermes/features/project/infrastructure/project_transaction_coordinator.dart';
import 'package:hermes/features/project/project_aggregate_repository_port.dart';
import 'package:hermes/features/project/project_repository_port.dart';
import 'package:hermes/shared_kernel/project_checkpoint.dart';
import 'package:hermes/features/task/domain/task.dart';
import 'package:hermes/features/task/application/task_application/task_persistence_ports.dart';
import 'package:hermes/shared_kernel/workspace_ports.dart';

/// Reads and coordinates project aggregates while delegating migration and
/// transaction mechanics to focused infrastructure collaborators.
class ProjectAggregateRepository implements ProjectAggregateRepositoryPort {
  ProjectAggregateRepository({
    required ProjectRepositoryPort projectRepository,
    required TaskPersistencePort taskRepository,
    required PersistencePort coordinator,
    this.onTransactionPhase,
  }) : _projects = projectRepository,
       _tasks = taskRepository,
       _coordinator = coordinator,
       _migrator = ProjectSnapshotMigrator(
         projectRepository: projectRepository,
         taskRepository: taskRepository,
       ),
       _transactions = ProjectTransactionCoordinator(
         projectRepository: projectRepository,
         taskRepository: taskRepository,
         onTransactionPhase: onTransactionPhase,
       );

  final ProjectRepositoryPort _projects;
  final TaskPersistencePort _tasks;
  final PersistencePort _coordinator;
  final ProjectSnapshotMigrator _migrator;
  final ProjectTransactionCoordinator _transactions;
  final FutureOr<void> Function(String phase)? onTransactionPhase;

  @override
  Future<ProjectLoadResult> loadProject(
    String workspaceRoot,
    String projectId, {
    String? chatSessionId,
    bool includeHistory = true,
  }) => _coordinator.synchronized(
    workspaceRoot,
    () => _loadProjectUnlocked(
      workspaceRoot,
      projectId,
      chatSessionId: chatSessionId,
      includeHistory: includeHistory,
    ),
  );

  Future<ProjectLoadResult> _loadProjectUnlocked(
    String workspaceRoot,
    String projectId, {
    String? chatSessionId,
    bool includeHistory = true,
  }) async {
    await _migrator.migrateLegacyEmbeddedTasks(workspaceRoot, projectId);
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
    var diagnostics = await _transactions.transactionDiagnostics(workspaceRoot);
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
    final reads = await Future.wait<_TaskLoadRead>([
      for (final taskId in projectSnapshot.value.taskIds)
        _readTask(workspaceRoot, taskId, includeHistory: includeHistory),
    ]);
    final canonicalTasks = <Task>[];
    for (final read in reads) {
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

  @override
  Future<ProjectRevisionCheckResult> checkRevisions(
    String workspaceRoot,
    ProjectAggregate project,
  ) => _coordinator.synchronized(
    workspaceRoot,
    () => _checkRevisionsUnlocked(workspaceRoot, project),
  );

  Future<ProjectRevisionCheckResult> _checkRevisionsUnlocked(
    String workspaceRoot,
    ProjectAggregate project,
  ) async {
    var diagnostics = await _transactions.transactionDiagnostics(workspaceRoot);
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
    final revisions = <String, PersistedRevision?>{};
    final reads = await Future.wait<_TaskRevisionRead>([
      for (final taskId in taskIds) _readTaskRevision(workspaceRoot, taskId),
    ]);
    for (final read in reads) {
      revisions[read.taskId] = read.revision;
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
      taskRevisions: revisions,
      diagnostics: diagnostics,
    );
  }

  @override
  Future<ProjectPersistenceDiagnostics> inspect(
    String workspaceRoot,
    ProjectAggregate project,
  ) async {
    final loaded = await _coordinator.synchronized(
      workspaceRoot,
      () => _loadProjectUnlocked(workspaceRoot, project.id),
    );
    return loaded.diagnostics;
  }

  @override
  Future<ProjectTransactionRecoveryResult> recoverInterruptedTransactions(
    String workspaceRoot,
  ) => _coordinator.synchronized(
    workspaceRoot,
    () => _transactions.recoverInterruptedTransactions(workspaceRoot),
  );

  @override
  Future<ProjectAggregateCommitResult> commit({
    required String workspaceRoot,
    required ProjectAggregate project,
    required Iterable<Task> tasks,
    Set<String> deletedTaskIds = const {},
    ProjectPersistenceDiagnostics? knownHealth,
    ProjectPersistenceCheckpoint checkpoint =
        ProjectPersistenceCheckpoint.runtime,
  }) => _coordinator.synchronized(workspaceRoot, () async {
    final health =
        knownHealth ??
        (await _loadProjectUnlocked(workspaceRoot, project.id)).diagnostics;
    return _transactions.commit(
      workspaceRoot: workspaceRoot,
      project: project,
      tasks: tasks.toList(growable: false),
      deletedTaskIds: deletedTaskIds,
      health: health,
      checkpoint: checkpoint,
    );
  });

  @override
  Future<bool> deleteProject(String workspaceRoot, ProjectAggregate project) =>
      _coordinator.synchronized(workspaceRoot, () async {
        final diagnostics = await _transactions.transactionDiagnostics(
          workspaceRoot,
        );
        if (diagnostics.issues.isNotEmpty ||
            diagnostics.interruptedTransactionIds.isNotEmpty) {
          throw ProjectPersistenceBlockedException(diagnostics);
        }
        final current = await _projects.loadProjectSnapshotUnlocked(
          workspaceRoot,
          project.id,
        );
        final actual = current?.revision ?? 0;
        if (project.persistenceRevision != actual) {
          throw StaleSnapshotException(
            path: _projects.projectRelativePath(
              project.id,
              ProjectRepositoryPort.documentFileName,
            ),
            expectedRevision: project.persistenceRevision,
            actualRevision: actual,
          );
        }
        final taskIds = <String>{...project.taskIds};
        final summaries = await _tasks.listTasks(
          workspaceRoot,
          projectId: project.id,
        );
        taskIds.addAll([
          for (final task in summaries as Iterable<dynamic>) task.id.toString(),
        ]);
        final taskRevisions = <String, int>{};
        for (final taskId in taskIds) {
          final task = await _tasks.loadTaskSnapshotUnlocked(
            workspaceRoot,
            taskId,
            includeHistory: false,
          );
          if (task != null) taskRevisions[taskId] = task.revision;
        }
        final transaction = await _transactions.begin(
          workspaceRoot,
          project: project,
          tasks: const [],
          deletedTaskIds: taskIds,
          deletedTaskRevisions: taskRevisions,
          deletingProject: true,
        );
        for (final taskId in taskIds) {
          await _tasks.deleteTaskUnlocked(workspaceRoot, taskId);
        }
        final deleted = await _projects.deleteProjectUnlocked(
          workspaceRoot,
          project.id,
        );
        await _transactions.markCommitted(transaction);
        await onTransactionPhase?.call('committed');
        await _transactions.remove(transaction);
        return deleted;
      });

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
