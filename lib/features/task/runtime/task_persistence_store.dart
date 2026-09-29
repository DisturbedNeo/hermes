import 'package:hermes/shared_kernel/task.dart';
import 'package:hermes/shared_kernel/persistence_contracts.dart';
import 'package:hermes/shared_kernel/task_summary.dart';

/// Owns all task-document and task-history storage access.
///
/// Task execution and planning deliberately depend on this small boundary
/// instead of reaching into [TaskRepository] for individual writes. The
/// repository remains the durable implementation and retains its optimistic
/// concurrency and history semantics.
class TaskPersistenceStore {
  TaskPersistenceStore({required dynamic repository})
    : _repository = repository;

  final dynamic _repository;

  dynamic get repository => _repository;

  Future<PersistedSnapshot<Task>> save(
    String workspaceRoot,
    Task task, {
    int? expectedRevision,
  }) => _repository.saveSnapshot(
    workspaceRoot,
    task,
    expectedRevision: expectedRevision,
  );

  Future<PersistedSnapshot<Task>?> load(
    String workspaceRoot,
    String taskId, {
    String? chatSessionId,
    String? projectId,
    bool includeHistory = true,
  }) => _repository.loadTask(
    workspaceRoot,
    taskId,
    chatSessionId: chatSessionId,
    projectId: projectId,
    includeHistory: includeHistory,
  );

  Future<PersistedSnapshot<Task>?> loadLatest(
    String workspaceRoot, {
    String? chatSessionId,
    String? projectId,
  }) => _repository.loadLatestTask(
    workspaceRoot,
    chatSessionId: chatSessionId,
    projectId: projectId,
  );

  Future<List<TaskSummary>> list(
    String workspaceRoot, {
    String? chatSessionId,
    String? projectId,
  }) => _repository.listTasks(
    workspaceRoot,
    chatSessionId: chatSessionId,
    projectId: projectId,
  );

  Future<int> deleteForChatSession(
    String workspaceRoot, {
    required String chatSessionId,
  }) => _repository.deleteTasksForChatSession(
    workspaceRoot,
    chatSessionId: chatSessionId,
  );

  Future<int> deleteOrphaned(
    String workspaceRoot, {
    required Set<String> retainedChatSessionIds,
  }) => _repository.deleteOrphanedChatTasks(
    workspaceRoot,
    retainedChatSessionIds: retainedChatSessionIds,
  );

  Future<bool> delete(String workspaceRoot, Task task) =>
      _repository.deleteTask(workspaceRoot, task.id);
}
