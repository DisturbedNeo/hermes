import 'package:hermes/features/project/application/contracts/project_snapshot_models.dart';
import 'package:hermes/features/persistence/application/persistence_contracts.dart';

/// Application-facing project persistence contract.
///
/// File names and transaction paths are retained here only for the aggregate
/// persistence protocol. The implementation that resolves them to disk lives
/// in [ProjectRepository]. Project use cases depend on this contract, which
/// also makes in-memory project stores possible in unit tests.
abstract interface class ProjectRepositoryPort {
  static const String projectsRoot = '.agent/projects';
  static const String documentFileName = 'project.json';

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

  Future<PersistedSnapshot<ProjectAggregate>> saveSnapshot(
    String workspaceRoot,
    ProjectAggregate project, {
    int? expectedRevision,
    PersistedRevision? currentRevision,
    bool assumeLocked = false,
  });

  Future<PersistedSnapshot<ProjectAggregate>?> loadProjectSnapshotUnlocked(
    String workspaceRoot,
    String projectId, {
    String? chatSessionId,
  });

  Future<PersistedSnapshot<ProjectAggregate>> saveSnapshotUnlocked(
    String workspaceRoot,
    ProjectAggregate project, {
    required int expectedRevision,
    PersistedRevision? currentRevision,
  });

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

  String projectRelativePath(String projectId, String fileName);

  String projectSnapshotPath(String workspaceRoot, String projectId);

  Future<void> saveLog(
    String workspaceRoot,
    String projectId,
    String name,
    String content,
  );
}
