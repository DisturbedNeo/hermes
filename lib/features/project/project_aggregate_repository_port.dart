import 'package:hermes/features/persistence/application/persistence_contracts.dart';
import 'package:hermes/features/project/application/contracts/project_checkpoint.dart';
import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/features/task/domain/task.dart';

/// Read-only aggregate operations used by project queries and hydration.
abstract interface class ProjectAggregateReadPort {
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
}

/// Recovery operations for interrupted aggregate transactions.
abstract interface class ProjectAggregateRecoveryPort {
  Future<ProjectTransactionRecoveryResult> recoverInterruptedTransactions(
    String workspaceRoot,
  );
}

/// Commit operations for hydrated project aggregates.
abstract interface class ProjectAggregateCommitPort {
  Future<ProjectAggregateCommitResult> commit({
    required String workspaceRoot,
    required ProjectAggregate project,
    required Iterable<TaskAggregate> tasks,
    Set<String> deletedTaskIds = const {},
    ProjectPersistenceDiagnostics? knownHealth,
    ProjectPersistenceCheckpoint checkpoint =
        ProjectPersistenceCheckpoint.runtime,
  });
}

/// Destructive aggregate operations used by cleanup workflows.
abstract interface class ProjectAggregateDeletePort {
  Future<bool> deleteProject(String workspaceRoot, ProjectAggregate project);
}

/// Aggregate capabilities required by hydration and lifecycle cleanup.
/// This intentionally excludes the aggregate commit operation.
abstract interface class ProjectAggregateHydrationPort
    implements
        ProjectAggregateReadPort,
        ProjectAggregateRecoveryPort,
        ProjectAggregateDeletePort {}

/// Composition-only aggregate persistence contract. Feature services should
/// depend on the narrow capability they use rather than this all-capabilities
/// adapter surface.
abstract interface class ProjectAggregateRepositoryPort
    implements
        ProjectAggregateHydrationPort,
        ProjectAggregateCommitPort,
        ProjectAggregateReadPort,
        ProjectAggregateRecoveryPort,
        ProjectAggregateDeletePort {}

class ProjectLoadResult {
  const ProjectLoadResult({
    required this.project,
    required this.diagnostics,
    this.canonicalTasks = const [],
  });

  final ProjectAggregate? project;
  final ProjectPersistenceDiagnostics diagnostics;
  final List<TaskAggregate> canonicalTasks;
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
  final Map<String, PersistedSnapshot<TaskAggregate>> tasks;
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
