import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/services/project_system/orchestration_contracts.dart';

enum TaskLifecycleTrigger {
  planning,
  scheduler,
  execution,
  recovery,
  approval,
  answerQuestion,
  retry,
  planManagement,
  cancel,
  system,
}

class TaskTransitionResult {
  final Task task;
  final TaskStatus from;
  final TaskStatus to;
  final TaskLifecycleTrigger trigger;
  final DateTime occurredAt;

  const TaskTransitionResult({
    required this.task,
    required this.from,
    required this.to,
    required this.trigger,
    required this.occurredAt,
  });
}

/// Pure top-level task transition guards and transformations.
class TaskLifecycleService {
  const TaskLifecycleService();

  TaskTransitionResult transition({
    required Task snapshot,
    required TaskStatus to,
    required TaskLifecycleTrigger trigger,
    String reason = '',
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();
    final from = snapshot.status;
    if (from != to) _validate(snapshot, to, trigger, reason);
    var task = snapshot.copyWith(status: to, updatedAt: timestamp);
    if (to == TaskStatus.completed || to == TaskStatus.cancelled) {
      task = task.copyWith(currentStepId: null, completedAt: timestamp);
    }
    if (to == TaskStatus.running) {
      task = task.copyWith(completedAt: null);
    }
    return TaskTransitionResult(
      task: task,
      from: from,
      to: to,
      trigger: trigger,
      occurredAt: timestamp,
    );
  }

  void _validate(
    Task task,
    TaskStatus to,
    TaskLifecycleTrigger trigger,
    String reason,
  ) {
    final from = task.status;
    final valid = switch (to) {
      TaskStatus.queued || TaskStatus.planned =>
        from == TaskStatus.draft ||
            from == TaskStatus.deferred ||
            trigger == TaskLifecycleTrigger.planning,
      TaskStatus.running =>
        from == TaskStatus.queued ||
            from == TaskStatus.planned ||
            from == TaskStatus.paused ||
            from == TaskStatus.blocked,
      TaskStatus.paused =>
        from == TaskStatus.running ||
            from == TaskStatus.blocked ||
            (from == TaskStatus.failed &&
                trigger == TaskLifecycleTrigger.retry),
      TaskStatus.blocked =>
        from == TaskStatus.running || from == TaskStatus.paused,
      TaskStatus.completed =>
        from == TaskStatus.running || from == TaskStatus.paused,
      TaskStatus.failed =>
        from == TaskStatus.running || from == TaskStatus.paused,
      TaskStatus.cancelled => !task.isTerminal,
      TaskStatus.rejected ||
      TaskStatus.split ||
      TaskStatus.deferred ||
      TaskStatus.obsolete =>
        !task.isTerminal && trigger == TaskLifecycleTrigger.planManagement,
      TaskStatus.draft => from == TaskStatus.draft,
    };
    if (valid) return;
    throw InvalidTaskTransitionException(
      from: from,
      to: to,
      reason: reason.trim().isEmpty
          ? 'Transition is not permitted for trigger ${trigger.name}.'
          : reason,
    );
  }
}
