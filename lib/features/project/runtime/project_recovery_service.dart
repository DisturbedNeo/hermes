import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/features/task/application/contracts/task_snapshot_models.dart';
import 'package:hermes/features/project/runtime/project_lifecycle_service.dart';

/// Reconciles an interrupted task back into its owning project.
///
/// The service is deterministic and model-free. It preserves the canonical
/// task id, records the task's current persistence revision, and creates a
/// durable blocker for approval/question/interruption states.
class ProjectRecoveryService {
  const ProjectRecoveryService({
    this.lifecycle = const ProjectLifecycleService(),
  });

  final ProjectLifecycleService lifecycle;

  ProjectAggregate reconcile({
    required ProjectAggregate project,
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
            ? current.copyWith(status: nextStatus, updatedAt: now)
            : task,
    ];
    final synced = project.copyWith(
      tasks: tasks,
      activeTaskId: recoveredTask.isTerminal ? null : current.id,
      updatedAt: now,
    );
    final blocker = _blockerFor(recoveredTask, now, current.id);
    if (blocker == null) {
      return lifecycle
          .transition(
            snapshot: synced.copyWith(blocker: null),
            to: ProjectStatus.active,
            trigger: ProjectLifecycleTrigger.recovery,
            now: now,
          )
          .project;
    }
    return lifecycle
        .transition(
          snapshot: synced,
          to: ProjectStatus.blocked,
          trigger: ProjectLifecycleTrigger.recovery,
          reason: blocker.message,
          taskId: blocker.taskId,
          blocker: blocker,
          now: now,
        )
        .project;
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
