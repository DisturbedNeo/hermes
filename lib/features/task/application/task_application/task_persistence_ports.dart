import 'package:hermes/features/persistence/application/persistence_contracts.dart';
import 'package:hermes/features/task/application/contracts/task_snapshot_models.dart';
import 'package:hermes/features/task/application/contracts/task_summary.dart';
import 'package:hermes/features/workspace/application/workspace_ports.dart';
import 'package:hermes/features/project/application/contracts/project_task_models.dart';

class TaskStorageLayout {
  static const String tasksRoot = '.agent/tasks';
  static const String documentFileName = 'task.json';
  static const String runsDirectoryName = 'runs';
}

/// Application-owned conversion boundary for planning-only project nodes.
abstract interface class TaskMaterializerPort {
  Task create(
    ProjectTaskNode node, {
    required String projectId,
    String? chatSessionId,
  });

  Task apply(
    ProjectTaskNode node,
    Task existing, {
    required String projectId,
    String? chatSessionId,
  });

  bool matches(ProjectTaskNode node, Task task);
}

/// Read-only task persistence capabilities.
abstract interface class TaskReadPort {
  PersistencePort get coordinator;

  Future<PersistedSnapshot<Task>?> loadTaskSnapshot(
    String workspaceRoot,
    String taskId, {
    String? chatSessionId,
    String? projectId,
    bool includeHistory = true,
  });

  Future<Map<String, PersistedSnapshot<Task>?>> loadTaskSnapshots(
    String workspaceRoot,
    Iterable<String> taskIds, {
    String? chatSessionId,
    String? projectId,
    bool includeHistory = true,
  });

  Future<PersistedRevision?> revisionOfUnlocked(
    String workspaceRoot,
    String taskId,
  );

  Future<Map<String, PersistedRevision?>> revisionOfManyUnlocked(
    String workspaceRoot,
    Iterable<String> taskIds,
  );

  Future<PersistedSnapshot<Task>?> loadTaskSnapshotUnlocked(
    String workspaceRoot,
    String taskId, {
    String? chatSessionId,
    String? projectId,
    bool includeHistory = true,
  });

  Future<List<TaskSummary>> listTasks(
    String workspaceRoot, {
    String? chatSessionId,
    String? projectId,
  });

  Future<PersistedSnapshot<Task>?> loadLatestTask(
    String workspaceRoot, {
    String? chatSessionId,
    String? projectId,
  });

  Future<PersistedSnapshot<Task>?> loadTask(
    String workspaceRoot,
    String taskId, {
    String? chatSessionId,
    String? projectId,
    bool includeHistory = true,
  });
}

/// Task snapshot and history writes.
abstract interface class TaskWritePort {
  Future<PersistedSnapshot<Task>> saveSnapshotUnlocked(
    String workspaceRoot,
    Task task, {
    required int expectedRevision,
    PersistedRevision? currentRevision,
  });

  String taskRelativePath(String taskId, String fileName);

  Future<bool> deleteTaskUnlocked(String workspaceRoot, String taskId);

  Future<PersistedSnapshot<Task>> saveSnapshot(
    String workspaceRoot,
    Task task, {
    int? expectedRevision,
    bool assumeLocked = false,
  });

  Future<bool> deleteTask(String workspaceRoot, String taskId);

  Future<void> saveLog(
    String workspaceRoot,
    String taskId,
    String name,
    String content,
  );
}

/// Task cleanup operations associated with chat/workspace lifecycle.
abstract interface class TaskCleanupPort {
  Future<int> deleteTasksForChatSession(
    String workspaceRoot, {
    required String chatSessionId,
  });

  Future<int> deleteOrphanedChatTasks(
    String workspaceRoot, {
    required Set<String> retainedChatSessionIds,
  });
}

/// Narrow task persistence capability used by project aggregate infrastructure.
abstract interface class TaskPersistencePort
    implements TaskReadPort, TaskWritePort, TaskCleanupPort {}
