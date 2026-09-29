import 'package:hermes/core/services/persistence_contracts.dart';
import 'package:hermes/features/project/project_repository_port.dart';
import 'package:hermes/features/project/domain/project.dart';
import 'package:path/path.dart' as path;

/// Deterministic project repository for application and reducer tests.
///
/// It deliberately models revisions and optimistic conflicts while avoiding
/// filesystem construction, backup repair, and transaction side effects.
class InMemoryProjectRepository implements ProjectRepositoryPort {
  final Map<String, Map<String, PersistedSnapshot<ProjectDocument>>> _data = {};

  @override
  Future<List<ProjectSummary>> listProjects(
    String workspaceRoot, {
    String? chatSessionId,
  }) async {
    final projects = _data[workspaceRoot]?.values ?? const [];
    return projects
        .map((snapshot) => snapshot.value)
        .where(
          (project) =>
              chatSessionId == null || project.chatSessionId == chatSessionId,
        )
        .map(
          (project) => ProjectSummary(
            id: project.id,
            title: project.title,
            status: project.status,
            updatedAt: project.updatedAt,
            activeTaskId: project.activeTaskId,
            chatSessionId: project.chatSessionId,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<PersistedSnapshot<ProjectDocument>?> loadProject(
    String workspaceRoot,
    String projectId, {
    String? chatSessionId,
  }) => loadProjectSnapshot(
    workspaceRoot,
    projectId,
    chatSessionId: chatSessionId,
  );

  @override
  Future<PersistedSnapshot<ProjectDocument>?> loadProjectSnapshot(
    String workspaceRoot,
    String projectId, {
    String? chatSessionId,
    bool assumeLocked = false,
  }) async {
    final snapshot = _data[workspaceRoot]?[projectId];
    if (snapshot == null) return null;
    if (chatSessionId != null &&
        snapshot.value.chatSessionId != chatSessionId) {
      return null;
    }
    return snapshot;
  }

  @override
  Future<PersistedRevision?> revisionOfUnlocked(
    String workspaceRoot,
    String projectId,
  ) async {
    final snapshot = _data[workspaceRoot]?[projectId];
    return snapshot == null
        ? null
        : PersistedRevision(revision: snapshot.revision);
  }

  @override
  Future<PersistedSnapshot<ProjectDocument>> saveSnapshot(
    String workspaceRoot,
    ProjectDocument project, {
    int? expectedRevision,
    PersistedRevision? currentRevision,
    bool assumeLocked = false,
  }) async {
    final current =
        currentRevision?.revision ??
        _data[workspaceRoot]?[project.id]?.revision ??
        0;
    final expected = expectedRevision ?? project.persistenceRevision;
    if (expected != current) {
      throw StaleSnapshotException(
        path: projectRelativePath(
          project.id,
          ProjectRepositoryPort.documentFileName,
        ),
        expectedRevision: expected,
        actualRevision: current,
      );
    }
    final persisted = project.copyWith(persistenceRevision: current + 1);
    final snapshot = PersistedSnapshot<ProjectDocument>(
      value: persisted,
      revision: current + 1,
    );
    (_data[workspaceRoot] ??= {})[project.id] = snapshot;
    return snapshot;
  }

  @override
  Future<PersistedSnapshot<ProjectDocument>?> loadProjectSnapshotUnlocked(
    String workspaceRoot,
    String projectId, {
    String? chatSessionId,
  }) => loadProjectSnapshot(
    workspaceRoot,
    projectId,
    chatSessionId: chatSessionId,
    assumeLocked: true,
  );

  @override
  Future<PersistedSnapshot<ProjectDocument>> saveSnapshotUnlocked(
    String workspaceRoot,
    ProjectDocument project, {
    required int expectedRevision,
    PersistedRevision? currentRevision,
  }) => saveSnapshot(
    workspaceRoot,
    project,
    expectedRevision: expectedRevision,
    currentRevision: currentRevision,
    assumeLocked: true,
  );

  @override
  Future<bool> deleteProject(String workspaceRoot, String projectId) async {
    return _data[workspaceRoot]?.remove(projectId) != null;
  }

  @override
  Future<bool> deleteProjectUnlocked(String workspaceRoot, String projectId) =>
      deleteProject(workspaceRoot, projectId);

  @override
  Future<int> deleteProjectsForChatSession(
    String workspaceRoot, {
    required String chatSessionId,
  }) async {
    final ids = (await listProjects(
      workspaceRoot,
      chatSessionId: chatSessionId,
    )).map((project) => project.id).toList();
    for (final id in ids) {
      await deleteProject(workspaceRoot, id);
    }
    return ids.length;
  }

  @override
  Future<int> deleteOrphanedChatProjects(
    String workspaceRoot, {
    required Set<String> retainedChatSessionIds,
  }) async {
    final ids = (await listProjects(workspaceRoot))
        .where(
          (project) =>
              project.chatSessionId == null ||
              !retainedChatSessionIds.contains(project.chatSessionId),
        )
        .map((project) => project.id)
        .toList();
    for (final id in ids) {
      await deleteProject(workspaceRoot, id);
    }
    return ids.length;
  }

  @override
  String projectRelativePath(String projectId, String fileName) =>
      path.posix.join(ProjectRepositoryPort.projectsRoot, projectId, fileName);

  @override
  String projectSnapshotPath(String workspaceRoot, String projectId) =>
      path.join(
        workspaceRoot,
        projectRelativePath(projectId, ProjectRepositoryPort.documentFileName),
      );

  @override
  Future<void> saveLog(
    String workspaceRoot,
    String projectId,
    String name,
    String content,
  ) async {}
}
