import 'dart:io';

import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/services/atomic_json_snapshot_store.dart';
import 'package:hermes/core/serialization/model_json.dart';
import 'package:hermes/core/services/task_system/task_summary.dart';
import 'package:path/path.dart' as path;

class TaskRepository {
  static const String tasksRoot = '.agent/tasks';
  static const String documentFileName = 'task.json';
  static const String v2BackupFileName = 'task.v2.json';

  final AtomicJsonSnapshotStore _snapshots = const AtomicJsonSnapshotStore();

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
        final raw = await _snapshots.readMap(file, isValid: _isTaskMap);
        if (raw == null) continue;
        final task = ModelJson.decode<TaskDocument>(raw);
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
    final dir = _validatedTaskDirectory(workspaceRoot, taskId);
    final file = File(path.join(dir.path, documentFileName));
    final raw = await _snapshots.readMap(file, isValid: _isTaskMap);
    if (raw == null) return null;
    final rawVersion = _rawSchemaVersion(raw);
    if (rawVersion > TaskDocument.currentSchemaVersion) {
      throw UnsupportedSnapshotSchemaException(
        path: file.path,
        foundVersion: rawVersion,
        supportedVersion: TaskDocument.currentSchemaVersion,
      );
    }
    final task = ModelJson.decode<TaskDocument>(raw);
    if (chatSessionId != null && task.chatSessionId != chatSessionId) {
      return null;
    }
    if (projectId != null && task.projectId != projectId) return null;
    if (rawVersion != TaskDocument.currentSchemaVersion) {
      if (rawVersion == 2) {
        await _writeV2MigrationBackup(dir, raw);
      }
      await saveSnapshot(workspaceRoot, task);
    }
    return task;
  }

  Future<void> saveSnapshot(String workspaceRoot, TaskDocument task) async {
    final dir = _validatedTaskDirectory(workspaceRoot, task.id);
    await dir.create(recursive: true);
    await _snapshots.writeMap(
      File(path.join(dir.path, documentFileName)),
      ModelJson.encode(task),
      isValid: _isTaskMap,
    );
  }

  Future<void> _writeV2MigrationBackup(
    Directory taskDirectory,
    Map<String, dynamic> raw,
  ) async {
    final backup = File(path.join(taskDirectory.path, v2BackupFileName));
    if (await backup.exists()) return;
    await _snapshots.writeMap(backup, raw, isValid: _isTaskMap);
  }

  int _rawSchemaVersion(Map<String, dynamic> map) {
    final value = map['schemaVersion'] ?? map['schema_version'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  Future<bool> deleteTask(String workspaceRoot, String taskId) async {
    final dir = _validatedTaskDirectory(workspaceRoot, taskId);
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
    final taskDir = _validatedTaskDirectory(workspaceRoot, taskId);
    _validateFileName(name, 'name');
    final dir = Directory(path.join(taskDir.path, 'logs'));
    await dir.create(recursive: true);
    await _writeText(File(path.join(dir.path, name)), content);
  }

  String taskRelativePath(String taskId, String fileName) {
    _validatePathSegment(taskId, 'taskId');
    _validateFileName(fileName, 'fileName');
    return path.posix.join(tasksRoot, taskId, fileName);
  }

  Directory _taskDirectory(String workspaceRoot, String taskId) {
    return Directory(path.join(workspaceRoot, tasksRoot, taskId));
  }

  Directory _validatedTaskDirectory(String workspaceRoot, String taskId) {
    _validatePathSegment(taskId, 'taskId');
    final root = Directory(path.join(workspaceRoot, tasksRoot));
    final dir = _taskDirectory(workspaceRoot, taskId);
    _throwIfOutsideTasksRoot(root, dir);
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

  void _throwIfOutsideTasksRoot(Directory root, Directory dir) {
    final rootPath = path.normalize(path.absolute(root.path));
    final dirPath = path.normalize(path.absolute(dir.path));
    if (!path.isWithin(rootPath, dirPath)) {
      throw ArgumentError.value(dir.path, 'taskId', 'Task path is invalid');
    }
  }

  Future<void> _writeText(File file, String content) async {
    await file.parent.create(recursive: true);
    await file.writeAsString(content);
  }

  bool _isTaskMap(Map<String, dynamic> map) {
    if (_rawSchemaVersion(map) > TaskDocument.currentSchemaVersion) {
      return (map['id'] ?? '').toString().trim().isNotEmpty;
    }
    try {
      final task = ModelJson.decode<TaskDocument>(map);
      return task.id.trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
