import 'package:hermes/shared_kernel/persistence_contracts.dart';
import 'package:hermes/features/project/project_aggregate_repository_port.dart';
import 'package:hermes/shared_kernel/project_checkpoint.dart';
import 'package:hermes/features/project/project_repository_port.dart';
import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/features/task/domain/task.dart';
import 'package:hermes/features/task/application/task_application/task_persistence_ports.dart';

/// In-memory aggregate double used by application-only construction and tests.
/// It preserves the repository revision protocol without transaction files.
class InMemoryProjectAggregateRepository
    implements ProjectAggregateRepositoryPort {
  InMemoryProjectAggregateRepository({
    required ProjectRepositoryPort projectRepository,
    required TaskPersistencePort taskRepository,
  }) : _projects = projectRepository,
       _tasks = taskRepository;

  final ProjectRepositoryPort _projects;
  final TaskPersistencePort _tasks;

  @override
  Future<ProjectLoadResult> loadProject(
    String workspaceRoot,
    String projectId, {
    String? chatSessionId,
    bool includeHistory = true,
  }) async {
    final snapshot = await _projects.loadProjectSnapshot(
      workspaceRoot,
      projectId,
      chatSessionId: chatSessionId,
    );
    if (snapshot == null) {
      return const ProjectLoadResult(
        project: null,
        diagnostics: ProjectPersistenceDiagnostics(),
      );
    }
    final taskSnapshots = await _tasks.loadTaskSnapshots(
      workspaceRoot,
      snapshot.value.taskIds,
      chatSessionId: snapshot.value.chatSessionId,
      projectId: snapshot.value.id,
      includeHistory: includeHistory,
    );
    final tasks = <Task>[
      for (final taskId in snapshot.value.taskIds)
        if (taskSnapshots[taskId] != null) taskSnapshots[taskId]!.value,
    ];
    return ProjectLoadResult(
      project: snapshot.value,
      diagnostics: const ProjectPersistenceDiagnostics(),
      canonicalTasks: tasks,
    );
  }

  @override
  Future<ProjectRevisionCheckResult> checkRevisions(
    String workspaceRoot,
    ProjectDocument project,
  ) async {
    final taskRevisions = await _tasks.revisionOfManyUnlocked(
      workspaceRoot,
      project.taskIds,
    );
    return ProjectRevisionCheckResult(
      projectRevision: await _projects.revisionOfUnlocked(
        workspaceRoot,
        project.id,
      ),
      taskRevisions: taskRevisions,
      diagnostics: const ProjectPersistenceDiagnostics(),
    );
  }

  @override
  Future<ProjectPersistenceDiagnostics> inspect(
    String workspaceRoot,
    ProjectDocument project,
  ) async => (await loadProject(workspaceRoot, project.id)).diagnostics;

  @override
  Future<ProjectTransactionRecoveryResult> recoverInterruptedTransactions(
    String workspaceRoot,
  ) async => const ProjectTransactionRecoveryResult();

  @override
  Future<ProjectAggregateCommitResult> commit({
    required String workspaceRoot,
    required ProjectDocument project,
    required Iterable<Task> tasks,
    Set<String> deletedTaskIds = const {},
    ProjectPersistenceDiagnostics? knownHealth,
    ProjectPersistenceCheckpoint checkpoint =
        ProjectPersistenceCheckpoint.runtime,
  }) async {
    final persistedTasks = <String, PersistedSnapshot<Task>>{};
    for (final task in tasks) {
      final current = await _tasks.loadTaskSnapshot(
        workspaceRoot,
        task.id,
        includeHistory: false,
      );
      if (current?.value == task) {
        persistedTasks[task.id] = current!;
        continue;
      }
      final saved = await _tasks.saveSnapshot(
        workspaceRoot,
        task,
        expectedRevision: task.persistenceRevision,
      );
      persistedTasks[task.id] = saved;
    }
    for (final taskId in deletedTaskIds) {
      await _tasks.deleteTask(workspaceRoot, taskId);
    }
    final persistedProject = await _projects.saveSnapshot(
      workspaceRoot,
      project,
      expectedRevision: project.persistenceRevision,
    );
    return ProjectAggregateCommitResult(
      project: persistedProject,
      tasks: persistedTasks,
    );
  }

  @override
  Future<bool> deleteProject(
    String workspaceRoot,
    ProjectDocument project,
  ) async {
    final taskIds = <String>{
      ...project.taskIds,
      ...project.tasks.map((t) => t.id),
    };
    for (final taskId in taskIds) {
      await _tasks.deleteTask(workspaceRoot, taskId);
    }
    return _projects.deleteProject(workspaceRoot, project.id);
  }
}
