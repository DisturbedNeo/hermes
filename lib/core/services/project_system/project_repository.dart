import 'dart:io';

import 'package:hermes/core/models/project.dart';
import 'package:hermes/core/services/atomic_json_snapshot_store.dart';
import 'package:hermes/core/services/persistence_contracts.dart';
import 'package:hermes/core/services/workspace_persistence_coordinator.dart';
import 'package:hermes/core/serialization/model_json.dart';
import 'package:path/path.dart' as path;

/// Repository responsible for all project data access, JSON mapping,
/// and file system interactions.
class ProjectRepository {
  static const String projectsRoot = '.agent/projects';
  static const String documentFileName = 'project.json';

  ProjectRepository({WorkspacePersistenceCoordinator? coordinator})
    : _coordinator = coordinator ?? WorkspacePersistenceCoordinator();

  final AtomicJsonSnapshotStore _snapshots = const AtomicJsonSnapshotStore();
  final WorkspacePersistenceCoordinator _coordinator;

  WorkspacePersistenceCoordinator get coordinator => _coordinator;

  // ── Listing ──────────────────────────────────────────────────────────

  /// Lists project summaries in the given workspace root, optionally
  /// filtered by [chatSessionId]. Returns an empty list when no projects
  /// directory exists.
  Future<List<ProjectSummary>> listProjects(
    String workspaceRoot, {
    String? chatSessionId,
  }) async {
    return _coordinator.synchronized(
      workspaceRoot,
      () => _listProjects(workspaceRoot, chatSessionId: chatSessionId),
    );
  }

  Future<List<ProjectSummary>> _listProjects(
    String workspaceRoot, {
    String? chatSessionId,
  }) async {
    final root = Directory(path.join(workspaceRoot, projectsRoot));
    if (!await root.exists()) return const [];

    final summaries = <ProjectSummary>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final file = File(path.join(entity.path, documentFileName));
      if (!await file.exists()) continue;

      try {
        final raw = await _snapshots.readMapWithoutRepair(
          file,
          isValid: _isEnvelopeMap,
        );
        if (raw == null) continue;
        final snapshot = _decodeProjectSnapshot(raw.map, raw.fromBackup);
        final project = snapshot.value;
        if (chatSessionId != null && project.chatSessionId != chatSessionId) {
          continue;
        }
        summaries.add(
          ProjectSummary(
            id: project.id,
            title: project.title,
            status: project.status,
            updatedAt: project.updatedAt,
            activeTaskId: project.activeTaskId,
            chatSessionId: project.chatSessionId,
          ),
        );
      } catch (error) {
        continue;
      }
    }

    summaries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return summaries;
  }

  /// Loads the most recently updated project in [workspaceRoot],
  /// optionally filtered by [chatSessionId]. Returns `null` when no
  /// matching project exists.
  Future<PersistedSnapshot<ProjectDocument>?> loadLatestProject(
    String workspaceRoot, {
    String? chatSessionId,
  }) async {
    final projects = await listProjects(
      workspaceRoot,
      chatSessionId: chatSessionId,
    );
    if (projects.isEmpty) return null;
    return loadProject(
      workspaceRoot,
      projects.first.id,
      chatSessionId: chatSessionId,
    );
  }

  // ── Loading ──────────────────────────────────────────────────────────

  /// Loads a single project by [projectId] from the given workspace root.
  /// Returns `null` when the project does not exist or its
  /// [chatSessionId] does not match (when provided).
  Future<PersistedSnapshot<ProjectDocument>?> loadProject(
    String workspaceRoot,
    String projectId, {
    String? chatSessionId,
  }) async {
    final snapshot = await loadProjectSnapshot(
      workspaceRoot,
      projectId,
      chatSessionId: chatSessionId,
    );
    return snapshot;
  }

  Future<PersistedSnapshot<ProjectDocument>?> loadProjectSnapshot(
    String workspaceRoot,
    String projectId, {
    String? chatSessionId,
    bool assumeLocked = false,
  }) async {
    if (!assumeLocked) {
      return _coordinator.synchronized(
        workspaceRoot,
        () => loadProjectSnapshot(
          workspaceRoot,
          projectId,
          chatSessionId: chatSessionId,
          assumeLocked: true,
        ),
      );
    }
    return _loadProjectSnapshotUnlocked(
      workspaceRoot,
      projectId,
      chatSessionId: chatSessionId,
    );
  }

  Future<PersistedSnapshot<ProjectDocument>?> _loadProjectSnapshotUnlocked(
    String workspaceRoot,
    String projectId, {
    String? chatSessionId,
  }) async {
    final dir = _validatedProjectDirectory(workspaceRoot, projectId);
    final file = File(path.join(dir.path, documentFileName));
    final raw = await _snapshots.readMapWithoutRepair(
      file,
      isValid: _isEnvelopeMap,
    );
    if (raw == null) return null;
    final snapshot = _decodeProjectSnapshot(raw.map, raw.fromBackup);
    final project = snapshot.value;
    if (chatSessionId != null && project.chatSessionId != chatSessionId) {
      return null;
    }
    return snapshot;
  }

  // ── Saving ───────────────────────────────────────────────────────────

  /// Persists [project] to disk under the given workspace root. Creates
  /// the project directory if it does not already exist.
  Future<PersistedSnapshot<ProjectDocument>> saveSnapshot(
    String workspaceRoot,
    ProjectDocument project, {
    int? expectedRevision,
    bool assumeLocked = false,
  }) async {
    if (!assumeLocked) {
      return _coordinator.synchronized(
        workspaceRoot,
        () => saveSnapshot(
          workspaceRoot,
          project,
          expectedRevision: expectedRevision,
          assumeLocked: true,
        ),
      );
    }
    final dir = _validatedProjectDirectory(workspaceRoot, project.id);
    await dir.create(recursive: true);
    final file = File(path.join(dir.path, documentFileName));
    final current = await _loadProjectSnapshotUnlocked(
      workspaceRoot,
      project.id,
    );
    final actualRevision = current?.revision ?? 0;
    final requiredRevision = expectedRevision ?? project.persistenceRevision;
    if (requiredRevision != actualRevision) {
      throw StaleSnapshotException(
        path: file.path,
        expectedRevision: requiredRevision,
        actualRevision: actualRevision,
      );
    }
    final nextRevision = actualRevision + 1;
    await _snapshots.writeMap(
      file,
      SnapshotEnvelope.encode(_documentMap(project), nextRevision),
      isValid: _isEnvelopeMap,
    );
    final persisted = project.copyWith(persistenceRevision: nextRevision);
    return PersistedSnapshot(value: persisted, revision: nextRevision);
  }

  /// Internal aggregate-commit entry point. The caller must hold the shared
  /// workspace coordinator lock.
  Future<PersistedSnapshot<ProjectDocument>?> loadProjectSnapshotUnlocked(
    String workspaceRoot,
    String projectId, {
    String? chatSessionId,
  }) => _loadProjectSnapshotUnlocked(
    workspaceRoot,
    projectId,
    chatSessionId: chatSessionId,
  );

  Future<PersistedSnapshot<ProjectDocument>> saveSnapshotUnlocked(
    String workspaceRoot,
    ProjectDocument project, {
    required int expectedRevision,
  }) => saveSnapshot(
    workspaceRoot,
    project,
    expectedRevision: expectedRevision,
    assumeLocked: true,
  );

  // ── Deletion ─────────────────────────────────────────────────────────

  /// Deletes a single project directory. Returns `true` when the project
  /// was deleted, `false` when it did not exist. Throws [ArgumentError]
  /// if [projectId] resolves outside the projects root (path traversal).
  Future<bool> deleteProject(String workspaceRoot, String projectId) async {
    return _coordinator.synchronized(
      workspaceRoot,
      () => deleteProjectUnlocked(workspaceRoot, projectId),
    );
  }

  Future<bool> deleteProjectUnlocked(
    String workspaceRoot,
    String projectId,
  ) async {
    final dir = _validatedProjectDirectory(workspaceRoot, projectId);
    if (!await dir.exists()) return false;
    await dir.delete(recursive: true);
    return true;
  }

  /// Deletes all projects associated with [chatSessionId]. Returns the
  /// number of projects deleted.
  Future<int> deleteProjectsForChatSession(
    String workspaceRoot, {
    required String chatSessionId,
  }) async {
    final projects = await listProjects(
      workspaceRoot,
      chatSessionId: chatSessionId,
    );
    var deleted = 0;
    for (final project in projects) {
      if (await deleteProject(workspaceRoot, project.id)) deleted++;
    }
    return deleted;
  }

  /// Deletes all projects whose [chatSessionId] is not in
  /// [retainedChatSessionIds]. Returns the number of projects deleted.
  Future<int> deleteOrphanedChatProjects(
    String workspaceRoot, {
    required Set<String> retainedChatSessionIds,
  }) async {
    final projects = await listProjects(workspaceRoot);
    var deleted = 0;
    for (final project in projects) {
      final chatSessionId = project.chatSessionId;
      if (chatSessionId == null ||
          retainedChatSessionIds.contains(chatSessionId)) {
        continue;
      }
      if (await deleteProject(workspaceRoot, project.id)) deleted++;
    }
    return deleted;
  }

  // ── Auxiliary paths ──────────────────────────────────────────────────

  /// Returns a POSIX-style relative path for a file inside a project's
  /// directory (e.g. `".agent/projects/<id>/<fileName>"`).
  String projectRelativePath(String projectId, String fileName) {
    _validatePathSegment(projectId, 'projectId');
    _validateFileName(fileName, 'fileName');
    return path.posix.join(projectsRoot, projectId, fileName);
  }

  /// Writes [content] to a log file named [name] inside the given
  /// project's `logs/` directory. Throws [ArgumentError] if [name] is
  /// not a plain filename (contains slashes or is absolute).
  Future<void> saveLog(
    String workspaceRoot,
    String projectId,
    String name,
    String content,
  ) async {
    await _coordinator.synchronized(workspaceRoot, () async {
      _validateFileName(name, 'name');
      final projectDir = _validatedProjectDirectory(workspaceRoot, projectId);
      final dir = Directory(path.join(projectDir.path, 'logs'));
      await dir.create(recursive: true);
      await _writeText(File(path.join(dir.path, name)), content);
    });
  }

  // ── Private helpers ──────────────────────────────────────────────────

  Directory _projectDirectory(String workspaceRoot, String projectId) {
    return Directory(path.join(workspaceRoot, projectsRoot, projectId));
  }

  Directory _validatedProjectDirectory(String workspaceRoot, String projectId) {
    _validatePathSegment(projectId, 'projectId');
    final root = Directory(path.join(workspaceRoot, projectsRoot));
    final dir = _projectDirectory(workspaceRoot, projectId);
    _throwIfOutsideProjectsRoot(root, dir);
    return dir;
  }

  void _validatePathSegment(String value, String argumentName) {
    if (value.isEmpty ||
        path.isAbsolute(value) ||
        path.basename(value) != value ||
        value == '.' ||
        value == '..') {
      throw ArgumentError.value(value, argumentName, 'Path segment is invalid');
    }
  }

  void _validateFileName(String value, String argumentName) {
    _validatePathSegment(value, argumentName);
  }

  void _throwIfOutsideProjectsRoot(Directory root, Directory dir) {
    final rootPath = path.normalize(path.absolute(root.path));
    final dirPath = path.normalize(path.absolute(dir.path));
    if (!path.isWithin(rootPath, dirPath)) {
      throw ArgumentError.value(
        dir.path,
        'projectId',
        'Project path is invalid',
      );
    }
  }

  Future<void> _writeText(File file, String content) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }

  PersistedSnapshot<ProjectDocument> _decodeProjectSnapshot(
    Map<String, dynamic> raw,
    bool fromBackup,
  ) {
    final envelope = SnapshotEnvelope.decode(raw);
    final project = ModelJson.decode<ProjectDocument>(envelope.document);
    if (project.id.trim().isEmpty) {
      throw const FormatException('Project snapshot has no id');
    }
    return PersistedSnapshot(
      value: project.copyWith(persistenceRevision: envelope.revision),
      revision: envelope.revision,
      fromBackup: fromBackup,
    );
  }

  Map<String, dynamic> _documentMap(ProjectDocument project) {
    final map = ModelJson.encode(project.copyWith(persistenceRevision: 0));
    map.remove('persistenceRevision');
    return map;
  }

  bool _isEnvelopeMap(Map<String, dynamic> map) {
    try {
      final envelope = SnapshotEnvelope.decode(map);
      final project = ModelJson.decode<ProjectDocument>(envelope.document);
      return project.id.trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
