import 'dart:convert';
import 'dart:io';

import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/serialization/model_json.dart';
import 'package:hermes/core/services/task_system/task_summary.dart';
import 'package:path/path.dart' as path;

class TaskRepository {
  static const String tasksRoot = '.agent/tasks';
  static const String documentFileName = 'task.json';

  final JsonEncoder _encoder = const JsonEncoder.withIndent('  ');

  Future<List<TaskSummary>> listTasks(
    String workspaceRoot, {
    String? chatSessionId,
    String? projectId,
  }) async {
    final root = Directory(path.join(workspaceRoot, tasksRoot));
    if (!await root.exists()) return const [];

    final summaries = <TaskSummary>[];
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final file = File(path.join(entity.path, documentFileName));
      if (!await file.exists()) continue;

      try {
        final task = ModelJson.decode<TaskDocument>(await _readMap(file));
        if (task.schemaVersion != TaskDocument.currentSchemaVersion) continue;
        if (chatSessionId != null && task.chatSessionId != chatSessionId) {
          continue;
        }
        if (projectId != null && task.projectId != projectId) continue;
        summaries.add(
          TaskSummary(
            id: task.id,
            title: task.title,
            chatSessionId: task.chatSessionId,
            projectId: task.projectId,
            status: task.status,
            updatedAt: task.updatedAt,
            currentPhaseId: task.currentStepId,
          ),
        );
      } catch (_) {
        continue;
      }
    }

    summaries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return summaries;
  }

  Future<TaskDocument?> loadLatestTask(
    String workspaceRoot, {
    String? chatSessionId,
    String? projectId,
  }) async {
    final tasks = await listTasks(
      workspaceRoot,
      chatSessionId: chatSessionId,
      projectId: projectId,
    );
    if (tasks.isEmpty) return null;
    return loadTask(
      workspaceRoot,
      tasks.first.id,
      chatSessionId: chatSessionId,
    );
  }

  Future<TaskDocument?> loadTask(
    String workspaceRoot,
    String taskId, {
    String? chatSessionId,
    String? projectId,
  }) async {
    final file = File(
      path.join(_taskDirectory(workspaceRoot, taskId).path, documentFileName),
    );
    if (!await file.exists()) return null;

    final task = ModelJson.decode<TaskDocument>(await _readMap(file));
    if (task.schemaVersion != TaskDocument.currentSchemaVersion) return null;
    if (chatSessionId != null && task.chatSessionId != chatSessionId) {
      return null;
    }
    if (projectId != null && task.projectId != projectId) return null;
    return task;
  }

  Future<void> saveSnapshot(String workspaceRoot, TaskDocument task) async {
    final dir = _taskDirectory(workspaceRoot, task.id);
    await dir.create(recursive: true);
    await _writeMap(
      File(path.join(dir.path, documentFileName)),
      ModelJson.encode(task),
    );
  }

  Future<bool> deleteTask(String workspaceRoot, String taskId) async {
    final root = Directory(path.join(workspaceRoot, tasksRoot));
    final dir = _taskDirectory(workspaceRoot, taskId);
    _throwIfOutsideTasksRoot(root, dir);
    if (!await dir.exists()) return false;
    await dir.delete(recursive: true);
    return true;
  }

  Future<int> deleteTasksForChatSession(
    String workspaceRoot, {
    required String chatSessionId,
  }) async {
    final tasks = await listTasks(workspaceRoot, chatSessionId: chatSessionId);
    var deleted = 0;
    for (final task in tasks) {
      if (await deleteTask(workspaceRoot, task.id)) deleted++;
    }
    return deleted;
  }

  Future<int> deleteOrphanedChatTasks(
    String workspaceRoot, {
    required Set<String> retainedChatSessionIds,
  }) async {
    final tasks = await listTasks(workspaceRoot);
    var deleted = 0;
    for (final task in tasks) {
      final chatSessionId = task.chatSessionId;
      if (chatSessionId == null ||
          retainedChatSessionIds.contains(chatSessionId)) {
        continue;
      }
      if (await deleteTask(workspaceRoot, task.id)) deleted++;
    }
    return deleted;
  }

  Future<void> saveLog(
    String workspaceRoot,
    String taskId,
    String name,
    String content,
  ) async {
    final dir = Directory(
      path.join(_taskDirectory(workspaceRoot, taskId).path, 'logs'),
    );
    await dir.create(recursive: true);
    await _writeText(File(path.join(dir.path, name)), content);
  }

  String taskRelativePath(String taskId, String fileName) {
    return path.posix.join(tasksRoot, taskId, fileName);
  }

  Directory _taskDirectory(String workspaceRoot, String taskId) {
    return Directory(path.join(workspaceRoot, tasksRoot, taskId));
  }

  void _throwIfOutsideTasksRoot(Directory root, Directory dir) {
    final rootPath = path.normalize(path.absolute(root.path));
    final dirPath = path.normalize(path.absolute(dir.path));
    if (!path.isWithin(rootPath, dirPath)) {
      throw ArgumentError.value(dir.path, 'taskId', 'Task path is invalid');
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
