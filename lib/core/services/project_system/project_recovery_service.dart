import 'package:hermes/core/models/project.dart';

/// Reconciles an interrupted task back into its owning project.
///
/// The service is deterministic and model-free. It preserves the canonical
/// task id, records the task's current persistence revision, and creates a
/// durable blocker for approval/question/interruption states.
class ProjectRecoveryService {
  const ProjectRecoveryService();

  ProjectDocument reconcile({
    required ProjectDocument project,
    required Task recoveredTask,
    required DateTime now,
  }) {
    final current = project.activeTaskId == null
        ? null
        : project.taskById(project.activeTaskId!);
    if (current == null) return project;
    final nextStatus = switch (recoveredTask.status) {
      TaskStatus.completed => TaskStatus.completed,
      TaskStatus.failed => TaskStatus.failed,
      TaskStatus.cancelled => TaskStatus.cancelled,
      _ => TaskStatus.running,
    };
    final tasks = [
      for (final task in project.tasks)
        task.id == current.id
            ? current.copyWith(
                status: nextStatus,
                persistenceRevision: recoveredTask.persistenceRevision,
                updatedAt: now,
              )
            : task,
    ];
    final synced = project.copyWith(
      tasks: tasks,
      activeTaskId: recoveredTask.isTerminal ? null : current.id,
      updatedAt: now,
    );
    final blocker = _blockerFor(recoveredTask, now, current.id);
    if (blocker == null) {
      return synced.copyWith(status: ProjectStatus.active, blocker: null);
    }
    return synced.copyWith(status: ProjectStatus.blocked, blocker: blocker);
  }

  ProjectBlocker? _blockerFor(Task task, DateTime now, String taskId) {
    if (task.pendingApproval != null) {
      return ProjectBlocker(
        type: ProjectBlockerType.taskEditApproval,
        message: task.pendingApproval!.reason,
        taskId: taskId,
        createdAt: now,
      );
    }
    if (task.pendingQuestion != null) {
      return ProjectBlocker(
        type: ProjectBlockerType.taskBlocked,
        message: task.pendingQuestion!.question,
        taskId: taskId,
        createdAt: now,
      );
    }
    if (task.status == TaskStatus.blocked) {
      return ProjectBlocker(
        type: ProjectBlockerType.taskBlocked,
        message: 'Task `${task.title}` is blocked.',
        taskId: taskId,
        createdAt: now,
      );
    }
    return null;
  }
}
