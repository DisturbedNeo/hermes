import 'package:hermes/features/persistence/application/persistence_contracts.dart';
import 'package:hermes/features/project/application/contracts/project_checkpoint.dart';
import 'package:hermes/features/project/application/contracts/project_snapshot_models.dart';
import 'package:hermes/features/task/application/contracts/task_snapshot_models.dart';

/// Read/write contract for the project aggregate persistence boundary.
///
/// The application layer consumes aggregate results and commit operations;
/// transaction manifests and filesystem recovery are implemented by the
/// infrastructure adapter.
abstract interface class ProjectAggregateRepositoryPort {
  Future<ProjectLoadResult> loadProject(
    String workspaceRoot,
    String projectId, {
    String? chatSessionId,
    bool includeHistory = true,
  });

  Future<ProjectRevisionCheckResult> checkRevisions(
    String workspaceRoot,
    ProjectAggregate project,
  );

  Future<ProjectPersistenceDiagnostics> inspect(
    String workspaceRoot,
    ProjectAggregate project,
  );

  Future<ProjectTransactionRecoveryResult> recoverInterruptedTransactions(
    String workspaceRoot,
  );

  Future<ProjectAggregateCommitResult> commit({
    required String workspaceRoot,
    required ProjectAggregate project,
    required Iterable<Task> tasks,
    Set<String> deletedTaskIds = const {},
    ProjectPersistenceDiagnostics? knownHealth,
    ProjectPersistenceCheckpoint checkpoint =
        ProjectPersistenceCheckpoint.runtime,
  });

  Future<bool> deleteProject(String workspaceRoot, ProjectAggregate project);
}

class ProjectLoadResult {
  const ProjectLoadResult({
    required this.project,
    required this.diagnostics,
    this.canonicalTasks = const [],
  });

  final ProjectAggregate? project;
  final ProjectPersistenceDiagnostics diagnostics;
  final List<Task> canonicalTasks;
}

class ProjectRevisionCheckResult {
  const ProjectRevisionCheckResult({
    required this.projectRevision,
    required this.taskRevisions,
    required this.diagnostics,
  });

  final PersistedRevision? projectRevision;
  final Map<String, PersistedRevision?> taskRevisions;
  final ProjectPersistenceDiagnostics diagnostics;
}

class ProjectAggregateCommitResult {
  const ProjectAggregateCommitResult({
    required this.project,
    required this.tasks,
  });

  final PersistedSnapshot<ProjectAggregate> project;
  final Map<String, PersistedSnapshot<Task>> tasks;
}

class ProjectTransactionRecoveryResult {
  const ProjectTransactionRecoveryResult({
    this.recoveredTransactionIds = const [],
    this.unresolvedTransactionIds = const [],
    this.issues = const [],
  });

  final List<String> recoveredTransactionIds;
  final List<String> unresolvedTransactionIds;
  final List<String> issues;

  bool get complete => unresolvedTransactionIds.isEmpty && issues.isEmpty;

  ProjectPersistenceDiagnostics get diagnostics =>
      ProjectPersistenceDiagnostics(
        issues: issues,
        interruptedTransactionIds: unresolvedTransactionIds,
      );
}
