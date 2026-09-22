import 'dart:io';

import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/services/atomic_json_snapshot_store.dart';
import 'package:hermes/core/services/persistence_contracts.dart';
import 'package:hermes/core/serialization/model_json.dart';
import 'package:hermes/core/services/task_system/task_summary.dart';
import 'package:hermes/core/services/workspace_persistence_coordinator.dart';
import 'package:path/path.dart' as path;

class TaskRepository {
  static const String tasksRoot = '.agent/tasks';
  static const String documentFileName = 'task.json';
  static const String runsDirectoryName = 'runs';

  TaskRepository({WorkspacePersistenceCoordinator? coordinator})
    : _coordinator = coordinator ?? WorkspacePersistenceCoordinator();

  final AtomicJsonSnapshotStore _snapshots = const AtomicJsonSnapshotStore();
  final WorkspacePersistenceCoordinator _coordinator;

  WorkspacePersistenceCoordinator get coordinator => _coordinator;
  final Map<String, _TaskSummaryCacheEntry> _summaryCache = {};
  final Map<String, _TaskCacheEntry> _metadataCache = {};
  final Set<String> _knownCompactTaskFiles = {};

  Future<List<TaskSummary>> listTasks(
    String workspaceRoot, {
    String? chatSessionId,
    String? projectId,
  }) async {
    return _coordinator.synchronized(
      workspaceRoot,
      () => _listTasks(
        workspaceRoot,
        chatSessionId: chatSessionId,
        projectId: projectId,
      ),
    );
  }

  Future<List<TaskSummary>> _listTasks(
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
        final stat = await file.stat();
        final cached = _summaryCache[file.path];
        final summary = cached != null && cached.matches(stat)
            ? cached.summary
            : _summaryFromMap(
                await _snapshots
                    .readMapWithoutRepair(file, isValid: _isEnvelopeMap)
                    .then((value) => value?.map),
              );
        if (summary == null) continue;
        if (cached == null || !cached.matches(stat)) {
          _summaryCache[file.path] = _TaskSummaryCacheEntry(stat, summary);
        }
        if (chatSessionId != null && summary.chatSessionId != chatSessionId) {
          continue;
        }
        if (projectId != null && summary.projectId != projectId) continue;
        summaries.add(summary);
      } catch (_) {
        continue;
      }
    }

    summaries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return summaries;
  }

  Future<PersistedSnapshot<Task>?> loadLatestTask(
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

  Future<PersistedSnapshot<Task>?> loadTask(
    String workspaceRoot,
    String taskId, {
    String? chatSessionId,
    String? projectId,
    bool includeHistory = true,
  }) async {
    final snapshot = await loadTaskSnapshot(
      workspaceRoot,
      taskId,
      chatSessionId: chatSessionId,
      projectId: projectId,
      includeHistory: includeHistory,
    );
    return snapshot;
  }

  Future<PersistedSnapshot<Task>?> loadTaskSnapshot(
    String workspaceRoot,
    String taskId, {
    String? chatSessionId,
    String? projectId,
    bool includeHistory = true,
    bool assumeLocked = false,
  }) async {
    if (!assumeLocked) {
      return _coordinator.synchronized(
        workspaceRoot,
        () => loadTaskSnapshot(
          workspaceRoot,
          taskId,
          chatSessionId: chatSessionId,
          projectId: projectId,
          includeHistory: includeHistory,
          assumeLocked: true,
        ),
      );
    }
    return _loadTaskSnapshotUnlocked(
      workspaceRoot,
      taskId,
      chatSessionId: chatSessionId,
      projectId: projectId,
      includeHistory: includeHistory,
    );
  }

  Future<PersistedSnapshot<Task>?> _loadTaskSnapshotUnlocked(
    String workspaceRoot,
    String taskId, {
    String? chatSessionId,
    String? projectId,
    bool includeHistory = true,
  }) async {
    final dir = _validatedTaskDirectory(workspaceRoot, taskId);
    final file = File(path.join(dir.path, documentFileName));
    final metadataStat = includeHistory ? null : await _statIfPresent(file);
    if (!includeHistory && metadataStat != null) {
      final cached = _metadataCache[file.path];
      if (cached != null && cached.matches(metadataStat)) {
        final task = cached.task.copyWith(persistenceRevision: cached.revision);
        if (chatSessionId != null && task.chatSessionId != chatSessionId) {
          return null;
        }
        if (projectId != null && task.projectId != projectId) return null;
        return PersistedSnapshot(
          value: task,
          revision: task.persistenceRevision,
        );
      }
    }
    final raw = await _snapshots.readMapWithoutRepair(
      file,
      isValid: _isEnvelopeMap,
    );
    if (raw == null) return null;
    final envelope = SnapshotEnvelope.decode(raw.map);
    final decoded = ModelJson.decode<Task>(
      envelope.document,
    ).copyWith(persistenceRevision: envelope.revision);
    final task = includeHistory
        ? decoded
        : _cachedMetadataTask(
            file,
            metadataStat ?? await file.stat(),
            envelope.document,
            envelope.revision,
          ).copyWith(persistenceRevision: envelope.revision);
    if (chatSessionId != null && task.chatSessionId != chatSessionId) {
      return null;
    }
    if (projectId != null && task.projectId != projectId) return null;
    if (!includeHistory) {
      return PersistedSnapshot(value: task, revision: envelope.revision);
    }
    final runs = await _loadRuns(dir);
    return PersistedSnapshot(
      value: runs.isEmpty ? task : task.copyWith(runs: runs),
      revision: envelope.revision,
      fromBackup: raw.fromBackup,
    );
  }

  Future<PersistedSnapshot<Task>> saveSnapshot(
    String workspaceRoot,
    Task task, {
    int? expectedRevision,
    bool assumeLocked = false,
  }) async {
    if (!assumeLocked) {
      return _coordinator.synchronized(
        workspaceRoot,
        () => saveSnapshot(
          workspaceRoot,
          task,
          expectedRevision: expectedRevision,
          assumeLocked: true,
        ),
      );
    }
    return _saveSnapshotUnlocked(
      workspaceRoot,
      task,
      expectedRevision: expectedRevision,
    );
  }

  Future<PersistedSnapshot<Task>> _saveSnapshotUnlocked(
    String workspaceRoot,
    Task task, {
    int? expectedRevision,
  }) async {
    final dir = _validatedTaskDirectory(workspaceRoot, task.id);
    await dir.create(recursive: true);
    final file = File(path.join(dir.path, documentFileName));
    final current = await _loadTaskSnapshotUnlocked(
      workspaceRoot,
      task.id,
      includeHistory: true,
    );
    final actualRevision = current?.revision ?? 0;
    final requiredRevision = expectedRevision ?? task.persistenceRevision;
    if (requiredRevision != actualRevision) {
      throw StaleSnapshotException(
        path: file.path,
        expectedRevision: requiredRevision,
        actualRevision: actualRevision,
      );
    }
    final nextRevision = actualRevision + 1;
    final fileExists = await file.exists();
    final historyDir = Directory(path.join(dir.path, runsDirectoryName));
    final hasHistory = await historyDir.exists();
    final runsToPersist = !fileExists || !hasHistory
        ? task.runs
        : task.runs.isEmpty
        ? const <TaskRun>[]
        : [task.runs.last];

    for (final run in runsToPersist) {
      await _saveRun(historyDir, run);
    }

    await _snapshots.writeMap(
      file,
      SnapshotEnvelope.encode(_compactTaskMap(task), nextRevision),
      isValid: _isEnvelopeMap,
    );
    _invalidateTaskCaches(file);
    _knownCompactTaskFiles.add(file.path);
    return PersistedSnapshot(
      value: task.copyWith(persistenceRevision: nextRevision),
      revision: nextRevision,
    );
  }

  Future<PersistedSnapshot<Task>?> loadTaskSnapshotUnlocked(
    String workspaceRoot,
    String taskId, {
    String? chatSessionId,
    String? projectId,
    bool includeHistory = true,
  }) => _loadTaskSnapshotUnlocked(
    workspaceRoot,
    taskId,
    chatSessionId: chatSessionId,
    projectId: projectId,
    includeHistory: includeHistory,
  );

  Future<PersistedSnapshot<Task>> saveSnapshotUnlocked(
    String workspaceRoot,
    Task task, {
    required int expectedRevision,
  }) => _saveSnapshotUnlocked(
    workspaceRoot,
    task,
    expectedRevision: expectedRevision,
  );

  Future<bool> deleteTask(String workspaceRoot, String taskId) async {
    return _coordinator.synchronized(
      workspaceRoot,
      () => deleteTaskUnlocked(workspaceRoot, taskId),
    );
  }

  Future<bool> deleteTaskUnlocked(String workspaceRoot, String taskId) async {
    final dir = _validatedTaskDirectory(workspaceRoot, taskId);
    if (!await dir.exists()) return false;
    await dir.delete(recursive: true);
    _invalidateTaskCaches(File(path.join(dir.path, documentFileName)));
    _knownCompactTaskFiles.remove(path.join(dir.path, documentFileName));
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
    await _coordinator.synchronized(workspaceRoot, () async {
      final taskDir = _validatedTaskDirectory(workspaceRoot, taskId);
      _validateFileName(name, 'name');
      final dir = Directory(path.join(taskDir.path, 'logs'));
      await dir.create(recursive: true);
      await _writeText(File(path.join(dir.path, name)), content);
    });
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

  TaskSummary? _summaryFromMap(Map<String, dynamic>? raw) {
    if (raw == null) return null;
    try {
      final envelope = SnapshotEnvelope.decode(raw);
      final task = ModelJson.decode<Task>(_withoutRuns(envelope.document));
      return TaskSummary(
        id: task.id,
        title: task.title,
        chatSessionId: task.chatSessionId,
        projectId: task.projectId,
        status: task.status,
        updatedAt: task.updatedAt,
        currentPhaseId: task.currentStepId,
      );
    } catch (_) {
      return null;
    }
  }

  Task _cachedMetadataTask(
    File file,
    FileStat stat,
    Map<String, dynamic> raw,
    int revision,
  ) {
    final cached = _metadataCache[file.path];
    if (cached != null && cached.matches(stat)) {
      return cached.task.copyWith(persistenceRevision: cached.revision);
    }
    final task = ModelJson.decode<Task>(_withoutRuns(raw));
    _metadataCache[file.path] = _TaskCacheEntry(stat, task, revision);
    return task;
  }

  Map<String, dynamic> _compactTaskMap(Task task) {
    final map = ModelJson.encode(
      task.copyWith(runs: const [], persistenceRevision: 0),
    );
    map.remove('runs');
    map.remove('persistenceRevision');
    return map;
  }

  Map<String, dynamic> _withoutRuns(Map<String, dynamic> raw) {
    final compact = Map<String, dynamic>.from(raw);
    compact.remove('runs');
    return compact;
  }

  Future<void> _saveRun(Directory historyDir, TaskRun run) async {
    _validatePathSegment(run.runId, 'runId');
    await historyDir.create(recursive: true);
    await _snapshots.writeMap(
      File(path.join(historyDir.path, '${run.runId}.json')),
      ModelJson.encode(run),
      isValid: _isTaskRunMap,
    );
  }

  Future<List<TaskRun>> _loadRuns(Directory taskDir) async {
    final historyDir = Directory(path.join(taskDir.path, runsDirectoryName));
    if (!await historyDir.exists()) return const [];
    final runs = <TaskRun>[];
    await for (final entity in historyDir.list(followLinks: false)) {
      if (entity is! File || path.extension(entity.path) != '.json') continue;
      final raw = await _snapshots.readMapWithoutRepair(entity);
      if (raw == null) continue;
      runs.add(ModelJson.decode<TaskRun>(raw.map));
    }
    runs.sort((a, b) {
      final started = a.startedAt.compareTo(b.startedAt);
      return started != 0 ? started : a.runId.compareTo(b.runId);
    });
    return runs;
  }

  bool _isTaskRunMap(Map<String, dynamic> map) {
    try {
      final run = ModelJson.decode<TaskRun>(map);
      return run.runId.trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  bool _isEnvelopeMap(Map<String, dynamic> map) {
    try {
      final envelope = SnapshotEnvelope.decode(map);
      final task = ModelJson.decode<Task>(envelope.document);
      return task.id.trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  void _invalidateTaskCaches(File file) {
    _summaryCache.remove(file.path);
    _metadataCache.remove(file.path);
  }

  Future<FileStat?> _statIfPresent(File file) async {
    try {
      return await file.stat();
    } on FileSystemException {
      return null;
    }
  }
}

class _TaskSummaryCacheEntry {
  final FileStat stat;
  final TaskSummary summary;

  const _TaskSummaryCacheEntry(this.stat, this.summary);

  bool matches(FileStat other) =>
      stat.modified == other.modified && stat.size == other.size;
}

class _TaskCacheEntry {
  final FileStat stat;
  final Task task;
  final int revision;

  const _TaskCacheEntry(this.stat, this.task, this.revision);

  bool matches(FileStat other) =>
      stat.modified == other.modified && stat.size == other.size;
}
