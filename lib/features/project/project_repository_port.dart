import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/features/persistence/application/persistence_contracts.dart';

/// Read-only project snapshot capabilities used by project queries and
/// hydration. Filesystem layout remains outside this contract.
abstract interface class ProjectReadPort {
  Future<List<ProjectSummary>> listProjects(
    String workspaceRoot, {
    String? chatSessionId,
  });

  Future<PersistedSnapshot<ProjectAggregate>?> loadProject(
    String workspaceRoot,
    String projectId, {
    String? chatSessionId,
  });

  Future<PersistedSnapshot<ProjectAggregate>?> loadProjectSnapshot(
    String workspaceRoot,
    String projectId, {
    String? chatSessionId,
    bool assumeLocked = false,
  });

  Future<PersistedRevision?> revisionOfUnlocked(
    String workspaceRoot,
    String projectId,
  );

  Future<PersistedSnapshot<ProjectAggregate>?> loadProjectSnapshotUnlocked(
    String workspaceRoot,
    String projectId, {
    String? chatSessionId,
  });
}

/// Project snapshot writes and history-log access.
abstract interface class ProjectWritePort {
  Future<PersistedSnapshot<ProjectAggregate>> saveSnapshot(
    String workspaceRoot,
    ProjectAggregate project, {
    int? expectedRevision,
    PersistedRevision? currentRevision,
    bool assumeLocked = false,
  });

  Future<PersistedSnapshot<ProjectAggregate>> saveSnapshotUnlocked(
    String workspaceRoot,
    ProjectAggregate project, {
    required int expectedRevision,
    PersistedRevision? currentRevision,
  });

  Future<void> saveLog(
    String workspaceRoot,
    String projectId,
    String name,
    String content,
  );
}

/// Project cleanup capabilities associated with chat/workspace lifecycle.
abstract interface class ProjectCleanupPort {
  Future<bool> deleteProject(String workspaceRoot, String projectId);

  Future<bool> deleteProjectUnlocked(String workspaceRoot, String projectId);

  Future<int> deleteProjectsForChatSession(
    String workspaceRoot, {
    required String chatSessionId,
  });

  Future<int> deleteOrphanedChatProjects(
    String workspaceRoot, {
    required Set<String> retainedChatSessionIds,
  });
}

/// Composition-only project persistence contract. Feature services should
/// depend on [ProjectReadPort], [ProjectWritePort], or [ProjectCleanupPort]
/// rather than this all-capabilities adapter surface.
///
/// File names and transaction paths are retained here only for the aggregate
/// persistence protocol. The implementation that resolves them to disk lives
/// in [ProjectRepository]. Project use cases depend on this contract, which
/// also makes in-memory project stores possible in unit tests.
abstract interface class ProjectRepositoryPort
    implements ProjectReadPort, ProjectWritePort, ProjectCleanupPort {}
