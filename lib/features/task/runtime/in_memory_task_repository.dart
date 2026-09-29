import 'package:hermes/shared_kernel/persistence_contracts.dart';
import 'package:hermes/shared_kernel/task_persistence_ports.dart';
import 'package:hermes/shared_kernel/task_summary.dart';
import 'package:hermes/shared_kernel/task.dart';
import 'package:hermes/shared_kernel/workspace_ports.dart';
import 'package:path/path.dart' as path;

/// In-memory task persistence double that retains optimistic revision checks.
class InMemoryTaskRepository
    implements TaskReadPort, TaskWritePort, TaskCleanupPort {
  InMemoryTaskRepository({PersistencePort? coordinator})
    : _coordinator = coordinator ?? const _InMemoryPersistence();

  final PersistencePort _coordinator;
  final Map<String, Map<String, PersistedSnapshot<Task>>> _data = {};

  @override
  PersistencePort get coordinator => _coordinator;

  @override
  Future<List<TaskSummary>> listTasks(
    String workspaceRoot, {
    String? chatSessionId,
    String? projectId,
  }) async {
    final tasks = _data[workspaceRoot]?.values ?? const [];
    return tasks
        .map((snapshot) => snapshot.value)
        .where(
          (task) =>
              (chatSessionId == null || task.chatSessionId == chatSessionId) &&
              (projectId == null || task.projectId == projectId),
        )
        .map(
          (task) => TaskSummary(
            id: task.id,
            title: task.title,
            status: task.status,
            updatedAt: task.updatedAt,
            currentPhaseId: task.currentStepId,
            chatSessionId: task.chatSessionId,
            projectId: task.projectId,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<PersistedSnapshot<Task>?> loadLatestTask(
    String workspaceRoot, {
    String? chatSessionId,
    String? projectId,
  }) async {
    final summaries = await listTasks(
      workspaceRoot,
      chatSessionId: chatSessionId,
      projectId: projectId,
    );
    if (summaries.isEmpty) return null;
    return loadTask(workspaceRoot, summaries.first.id);
  }

  @override
  Future<PersistedSnapshot<Task>?> loadTask(
    String workspaceRoot,
    String taskId, {
    String? chatSessionId,
    String? projectId,
    bool includeHistory = true,
  }) => loadTaskSnapshot(
    workspaceRoot,
    taskId,
    chatSessionId: chatSessionId,
    projectId: projectId,
    includeHistory: includeHistory,
  );

  @override
  Future<PersistedSnapshot<Task>?> loadTaskSnapshot(
    String workspaceRoot,
    String taskId, {
    String? chatSessionId,
    String? projectId,
    bool includeHistory = true,
  }) async {
    final snapshot = _data[workspaceRoot]?[taskId];
    if (snapshot == null) return null;
    final task = snapshot.value;
    if (chatSessionId != null && task.chatSessionId != chatSessionId) {
      return null;
    }
    if (projectId != null && task.projectId != projectId) return null;
    return snapshot;
  }

  @override
  Future<Map<String, PersistedSnapshot<Task>?>> loadTaskSnapshots(
    String workspaceRoot,
    Iterable<String> taskIds, {
    String? chatSessionId,
    String? projectId,
    bool includeHistory = true,
  }) async => {
    for (final id in taskIds)
      id: await loadTaskSnapshot(
        workspaceRoot,
        id,
        chatSessionId: chatSessionId,
        projectId: projectId,
        includeHistory: includeHistory,
      ),
  };

  @override
  Future<PersistedRevision?> revisionOfUnlocked(
    String workspaceRoot,
    String taskId,
  ) async {
    final snapshot = _data[workspaceRoot]?[taskId];
    return snapshot == null
        ? null
        : PersistedRevision(revision: snapshot.revision);
  }

  @override
  Future<Map<String, PersistedRevision?>> revisionOfManyUnlocked(
    String workspaceRoot,
    Iterable<String> taskIds,
  ) async => {
    for (final id in taskIds) id: await revisionOfUnlocked(workspaceRoot, id),
  };

  @override
  Future<PersistedSnapshot<Task>?> loadTaskSnapshotUnlocked(
    String workspaceRoot,
    String taskId, {
    String? chatSessionId,
    String? projectId,
    bool includeHistory = true,
  }) => loadTaskSnapshot(
    workspaceRoot,
    taskId,
    chatSessionId: chatSessionId,
    projectId: projectId,
    includeHistory: includeHistory,
  );

  @override
  Future<PersistedSnapshot<Task>> saveSnapshotUnlocked(
    String workspaceRoot,
    Task task, {
    required int expectedRevision,
    PersistedRevision? currentRevision,
  }) => saveSnapshot(
    workspaceRoot,
    task,
    expectedRevision: expectedRevision,
    assumeLocked: true,
  );

  @override
  Future<PersistedSnapshot<Task>> saveSnapshot(
    String workspaceRoot,
    Task task, {
    int? expectedRevision,
    bool assumeLocked = false,
  }) async {
    final current = _data[workspaceRoot]?[task.id]?.revision ?? 0;
    final expected = expectedRevision ?? task.persistenceRevision;
    if (current != expected) {
      throw StaleSnapshotException(
        path: taskRelativePath(task.id, TaskStorageLayout.documentFileName),
        expectedRevision: expected,
        actualRevision: current,
      );
    }
    final persisted = task.copyWith(persistenceRevision: current + 1);
    final snapshot = PersistedSnapshot<Task>(
      value: persisted,
      revision: current + 1,
    );
    (_data[workspaceRoot] ??= {})[task.id] = snapshot;
    return snapshot;
  }

  @override
  Future<bool> deleteTask(String workspaceRoot, String taskId) async =>
      _data[workspaceRoot]?.remove(taskId) != null;

  @override
  Future<bool> deleteTaskUnlocked(String workspaceRoot, String taskId) =>
      deleteTask(workspaceRoot, taskId);

  @override
  Future<void> saveLog(
    String workspaceRoot,
    String taskId,
    String name,
    String content,
  ) async {}

  @override
  Future<int> deleteTasksForChatSession(
    String workspaceRoot, {
    required String chatSessionId,
  }) async {
    final ids = (await listTasks(
      workspaceRoot,
      chatSessionId: chatSessionId,
    )).map((task) => task.id).toList();
    for (final id in ids) {
      await deleteTask(workspaceRoot, id);
    }
    return ids.length;
  }

  @override
  Future<int> deleteOrphanedChatTasks(
    String workspaceRoot, {
    required Set<String> retainedChatSessionIds,
  }) async {
    final ids = (await listTasks(workspaceRoot))
        .where(
          (task) =>
              task.chatSessionId == null ||
              !retainedChatSessionIds.contains(task.chatSessionId),
        )
        .map((task) => task.id)
        .toList();
    for (final id in ids) {
      await deleteTask(workspaceRoot, id);
    }
    return ids.length;
  }

  @override
  String taskRelativePath(String taskId, String fileName) =>
      path.posix.join(TaskStorageLayout.tasksRoot, taskId, fileName);
}

class _InMemoryPersistence implements PersistencePort {
  const _InMemoryPersistence();

  @override
  String canonicalWorkspacePath(String workspaceRoot) => workspaceRoot;

  @override
  Future<T> synchronized<T>(
    String workspaceRoot,
    Future<T> Function() operation,
  ) => operation();
}
