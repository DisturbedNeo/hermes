import 'package:hermes/features/task/domain/task.dart';
import 'package:hermes/features/persistence/application/persistence_contracts.dart';
import 'package:hermes/features/task/application/contracts/task_summary.dart';
import 'package:hermes/features/task/application/task_application/task_persistence_ports.dart';

/// Owns all task-document and task-history storage access.
///
/// Task execution and planning deliberately depend on this small boundary
/// instead of reaching into [TaskRepository] for individual writes. The
/// repository remains the durable implementation and retains its optimistic
/// concurrency and history semantics.
class TaskPersistenceStore {
  TaskPersistenceStore({required TaskPersistencePort persistence})
    : _persistence = persistence;

  final TaskPersistencePort _persistence;

  Future<PersistedSnapshot<TaskAggregate>> save(
    String workspaceRoot,
    TaskAggregate task, {
    int? expectedRevision,
  }) => _persistence.saveSnapshot(
    workspaceRoot,
    task,
    expectedRevision: expectedRevision,
  );

  Future<PersistedSnapshot<TaskAggregate>?> load(
    String workspaceRoot,
    String taskId, {
    String? chatSessionId,
    String? projectId,
    bool includeHistory = true,
  }) => _persistence.loadTask(
    workspaceRoot,
    taskId,
    chatSessionId: chatSessionId,
    projectId: projectId,
    includeHistory: includeHistory,
  );

  Future<PersistedSnapshot<TaskAggregate>?> loadSnapshot(
    String workspaceRoot,
    String taskId, {
    String? chatSessionId,
    String? projectId,
    bool includeHistory = true,
  }) => _persistence.loadTaskSnapshot(
    workspaceRoot,
    taskId,
    chatSessionId: chatSessionId,
    projectId: projectId,
    includeHistory: includeHistory,
  );

  Future<List<TaskSummary>> listTasks(
    String workspaceRoot, {
    String? chatSessionId,
    String? projectId,
  }) => list(workspaceRoot, chatSessionId: chatSessionId, projectId: projectId);

  Future<PersistedSnapshot<TaskAggregate>?> loadLatest(
    String workspaceRoot, {
    String? chatSessionId,
    String? projectId,
  }) => _persistence.loadLatestTask(
    workspaceRoot,
    chatSessionId: chatSessionId,
    projectId: projectId,
  );

  Future<List<TaskSummary>> list(
    String workspaceRoot, {
    String? chatSessionId,
    String? projectId,
  }) => _persistence.listTasks(
    workspaceRoot,
    chatSessionId: chatSessionId,
    projectId: projectId,
  );

  Future<int> deleteForChatSession(
    String workspaceRoot, {
    required String chatSessionId,
  }) => _persistence.deleteTasksForChatSession(
    workspaceRoot,
    chatSessionId: chatSessionId,
  );

  Future<int> deleteOrphaned(
    String workspaceRoot, {
    required Set<String> retainedChatSessionIds,
  }) => _persistence.deleteOrphanedChatTasks(
    workspaceRoot,
    retainedChatSessionIds: retainedChatSessionIds,
  );

  Future<bool> delete(String workspaceRoot, TaskAggregate task) =>
      _persistence.deleteTask(workspaceRoot, task.id);

  Future<void> saveLog(
    String workspaceRoot,
    String taskId,
    String name,
    String content,
  ) => _persistence.saveLog(workspaceRoot, taskId, name, content);
}
