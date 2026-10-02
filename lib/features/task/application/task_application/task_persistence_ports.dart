import 'package:hermes/features/persistence/application/persistence_contracts.dart';
import 'package:hermes/features/task/domain/task.dart';
import 'package:hermes/features/project/application/contracts/project_task_models.dart';
import 'package:hermes/features/task/application/contracts/task_summary.dart';

/// Application-owned conversion boundary for planning-only project nodes.
abstract interface class TaskMaterializerPort {
  TaskAggregate create(
    ProjectTaskNode node, {
    required String projectId,
    String? chatSessionId,
  });

  TaskAggregate apply(
    ProjectTaskNode node,
    TaskAggregate existing, {
    required String projectId,
    String? chatSessionId,
  });

  bool matches(ProjectTaskNode node, TaskAggregate task);
}

/// Read-only task persistence capabilities.
abstract interface class TaskReadPort {
  Future<PersistedSnapshot<TaskAggregate>?> loadTaskSnapshot(
    String workspaceRoot,
    String taskId, {
    String? chatSessionId,
    String? projectId,
    bool includeHistory = true,
  });

  Future<Map<String, PersistedSnapshot<TaskAggregate>?>> loadTaskSnapshots(
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

  Future<PersistedSnapshot<TaskAggregate>?> loadTaskSnapshotUnlocked(
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

  Future<PersistedSnapshot<TaskAggregate>?> loadLatestTask(
    String workspaceRoot, {
    String? chatSessionId,
    String? projectId,
  });

  Future<PersistedSnapshot<TaskAggregate>?> loadTask(
    String workspaceRoot,
    String taskId, {
    String? chatSessionId,
    String? projectId,
    bool includeHistory = true,
  });
}

/// Task snapshot and history writes.
abstract interface class TaskWritePort {
  Future<PersistedSnapshot<TaskAggregate>> saveSnapshotUnlocked(
    String workspaceRoot,
    TaskAggregate task, {
    required int expectedRevision,
    PersistedRevision? currentRevision,
  });

  Future<bool> deleteTaskUnlocked(String workspaceRoot, String taskId);

  Future<PersistedSnapshot<TaskAggregate>> saveSnapshot(
    String workspaceRoot,
    TaskAggregate task, {
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
