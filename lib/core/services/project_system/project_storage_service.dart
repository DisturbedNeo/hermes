import 'dart:convert';
import 'dart:io';

import 'package:hermes/core/models/project.dart';
import 'package:path/path.dart' as path;

class ProjectStorageService {
  static const String projectsRoot = '.agent/projects';
  static const String documentFileName = 'project.json';

  final JsonEncoder _encoder = const JsonEncoder.withIndent('  ');

  Future<List<ProjectSummary>> listProjects(
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
        final project = ProjectDocument.fromJson(await _readMap(file));
        if (project.schemaVersion != ProjectDocument.currentSchemaVersion) {
          continue;
        }
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
      } catch (_) {
        continue;
      }
    }

    summaries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return summaries;
  }

  Future<ProjectDocument?> loadLatestProject(
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

  Future<ProjectDocument?> loadProject(
    String workspaceRoot,
    String projectId, {
    String? chatSessionId,
  }) async {
    final file = File(
      path.join(
        _projectDirectory(workspaceRoot, projectId).path,
        documentFileName,
      ),
    );
    if (!await file.exists()) return null;

    final project = ProjectDocument.fromJson(await _readMap(file));
    if (project.schemaVersion != ProjectDocument.currentSchemaVersion) {
      return null;
    }
    if (chatSessionId != null && project.chatSessionId != chatSessionId) {
      return null;
    }
    return project;
  }

  Future<void> saveSnapshot(
    String workspaceRoot,
    ProjectDocument project,
  ) async {
    final dir = _projectDirectory(workspaceRoot, project.id);
    await dir.create(recursive: true);
    await _writeMap(
      File(path.join(dir.path, documentFileName)),
      project.toJson(),
    );
  }

  Future<bool> deleteProject(String workspaceRoot, String projectId) async {
    final root = Directory(path.join(workspaceRoot, projectsRoot));
    final dir = _projectDirectory(workspaceRoot, projectId);
    _throwIfOutsideProjectsRoot(root, dir);
    if (!await dir.exists()) return false;
    await dir.delete(recursive: true);
    return true;
  }

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

  String projectRelativePath(String projectId, String fileName) {
    return path.posix.join(projectsRoot, projectId, fileName);
  }

  Directory _projectDirectory(String workspaceRoot, String projectId) {
    return Directory(path.join(workspaceRoot, projectsRoot, projectId));
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

  Future<Map<String, dynamic>> _readMap(File file) async {
    final content = await file.readAsString();
    final decoded = jsonDecode(content);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw const FormatException('Expected a JSON object');
  }

  Future<void> _writeMap(File file, Map<String, dynamic> map) {
    return _writeText(file, '${_encoder.convert(map)}\n');
  }

  Future<void> _writeText(File file, String content) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }
}
