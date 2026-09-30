import 'package:hermes/shared_kernel/sentinel.dart';
import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/features/project/application/project_application/project_execution_port.dart';
import 'package:hermes/features/project/domain/project_control_state_service.dart';

enum ProjectLifecycleTrigger {
  initialization,
  startTask,
  taskReview,
  recovery,
  answerQuestion,
  userContext,
  approval,
  planRevision,
  completion,
  pause,
  cancel,
  failure,
  system,
}

class ProjectTransitionResult {
  final ProjectAggregate project;
  final ProjectLifecycleTransition transition;

  const ProjectTransitionResult({
    required this.project,
    required this.transition,
  });
}

/// Pure project state transition guards and transformations.
class ProjectLifecycleService {
  const ProjectLifecycleService({
    this.controlState = const ProjectControlStateService(),
  });

  final ProjectControlStateService controlState;

  ProjectTransitionResult transition({
    required ProjectAggregate snapshot,
    required ProjectStatus to,
    required ProjectLifecycleTrigger trigger,
    String reason = '',
    String? taskId,
    ProjectBlocker? blocker,
    bool completionApproved = false,
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();
    final from = snapshot.status;
    if (from == to) {
      final project = controlState.migrateLegacy(snapshot, now: timestamp);
      return ProjectTransitionResult(
        project: project,
        transition: ProjectLifecycleTransition(
          from: from,
          to: to,
          trigger: trigger.name,
          reason: reason,
          occurredAt: timestamp,
          taskId: taskId ?? snapshot.activeTaskId,
        ),
      );
    }
    if (snapshot.isTerminal) {
      throw InvalidProjectTransitionException(
        from: from,
        to: to,
        reason: 'Terminal projects cannot transition.',
      );
    }
    _validate(
      snapshot: snapshot,
      to: to,
      trigger: trigger,
      taskId: taskId,
      blocker: blocker,
      completionApproved: completionApproved,
    );

    var project = snapshot.copyWith(status: to, updatedAt: timestamp);
    if (to == ProjectStatus.runningTask || to == ProjectStatus.reviewingTask) {
      project = project.copyWith(activeTaskId: taskId ?? snapshot.activeTaskId);
    }
    if (to == ProjectStatus.completed || to == ProjectStatus.cancelled) {
      project = project.copyWith(
        activeTaskId: kSentinel,
        blocker: kSentinel,
        openQuestions: const [],
        completedAt: timestamp,
      );
    } else if (to == ProjectStatus.failed) {
      project = project.copyWith(activeTaskId: kSentinel);
    }
    if (to == ProjectStatus.blocked && blocker != null) {
      project = project.copyWith(blocker: blocker);
    }
    if (to == ProjectStatus.active &&
        trigger != ProjectLifecycleTrigger.system) {
      project = project.copyWith(blocker: kSentinel);
    }
    if (to == ProjectStatus.waitingForUser && blocker != null) {
      project = project.copyWith(blocker: blocker);
    }
    project = controlState.migrateLegacy(project, now: timestamp);
    return ProjectTransitionResult(
      project: project,
      transition: ProjectLifecycleTransition(
        from: from,
        to: to,
        trigger: trigger.name,
        reason: reason,
        occurredAt: timestamp,
        taskId: taskId ?? project.activeTaskId,
      ),
    );
  }

  void _validate({
    required ProjectAggregate snapshot,
    required ProjectStatus to,
    required ProjectLifecycleTrigger trigger,
    required String? taskId,
    required ProjectBlocker? blocker,
    required bool completionApproved,
  }) {
    final from = snapshot.status;
    final valid = switch (to) {
      ProjectStatus.active =>
        from == ProjectStatus.initializing ||
            from == ProjectStatus.paused ||
            from == ProjectStatus.blocked ||
            from == ProjectStatus.waitingForUser ||
            from == ProjectStatus.reviewingTask ||
            from == ProjectStatus.runningTask,
      ProjectStatus.runningTask =>
        (from == ProjectStatus.active || from == ProjectStatus.paused) &&
            _hasTask(snapshot, taskId),
      ProjectStatus.reviewingTask =>
        (from == ProjectStatus.runningTask || from == ProjectStatus.active) &&
            _hasTask(snapshot, taskId),
      ProjectStatus.waitingForUser =>
        !snapshot.isTerminal &&
            (snapshot.openQuestions.isNotEmpty ||
                _isUserActionableBlocker(blocker?.type) ||
                _isUserActionableBlocker(snapshot.blocker?.type)),
      ProjectStatus.blocked =>
        !snapshot.isTerminal && (blocker != null || snapshot.blocker != null),
      ProjectStatus.paused =>
        from == ProjectStatus.initializing ||
            from == ProjectStatus.active ||
            from == ProjectStatus.runningTask ||
            from == ProjectStatus.reviewingTask ||
            from == ProjectStatus.waitingForUser ||
            from == ProjectStatus.blocked,
      ProjectStatus.completed =>
        (from == ProjectStatus.reviewingTask ||
                from == ProjectStatus.active ||
                from == ProjectStatus.paused) &&
            completionApproved,
      ProjectStatus.failed => !snapshot.isTerminal,
      ProjectStatus.cancelled => !snapshot.isTerminal,
      ProjectStatus.initializing => from == ProjectStatus.initializing,
    };
    if (valid) return;
    throw InvalidProjectTransitionException(
      from: from,
      to: to,
      reason: _reason(
        snapshot: snapshot,
        to: to,
        trigger: trigger,
        taskId: taskId,
        completionApproved: completionApproved,
      ),
    );
  }

  bool _hasTask(ProjectAggregate project, String? taskId) {
    final id = taskId ?? project.activeTaskId;
    return id != null && project.taskById(id) != null;
  }

  bool _isUserActionableBlocker(ProjectBlockerType? type) => switch (type) {
    ProjectBlockerType.question ||
    ProjectBlockerType.taskEditApproval ||
    ProjectBlockerType.taskBlocked ||
    ProjectBlockerType.taskFailed ||
    ProjectBlockerType.planApproval => true,
    _ => false,
  };

  String _reason({
    required ProjectAggregate snapshot,
    required ProjectStatus to,
    required ProjectLifecycleTrigger trigger,
    required String? taskId,
    required bool completionApproved,
  }) {
    if (to == ProjectStatus.completed && !completionApproved) {
      return 'Completion must be approved by ProjectCompletionService.';
    }
    if (to == ProjectStatus.runningTask && !_hasTask(snapshot, taskId)) {
      return 'A valid active task is required.';
    }
    if (to == ProjectStatus.waitingForUser) {
      return 'A user question or user-actionable blocker is required.';
    }
    if (to == ProjectStatus.blocked) {
      return 'A blocker must be supplied.';
    }
    return 'Transition is not permitted for trigger ${trigger.name}.';
  }
}
