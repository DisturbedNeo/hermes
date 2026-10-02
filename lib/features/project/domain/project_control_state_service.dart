import 'package:hermes/features/project/domain/project.dart';

/// The single deterministic reducer for project command boundaries.
///
/// Derives the project control outcome from the lifecycle fields when a
/// boundary has not yet been materialized. Callers should not duplicate this
/// precedence order.
class ProjectControlStateMachine {
  const ProjectControlStateMachine();

  ProjectBoundary read(ProjectAggregate project, {DateTime? now}) {
    final existing = project.boundary;
    if (existing != null) return existing;
    return _deriveBoundary(project, now: now);
  }

  ProjectBoundary _deriveBoundary(ProjectAggregate project, {DateTime? now}) {
    final timestamp = now ?? project.updatedAt;
    final outcome = _deriveOutcome(project);
    final blocker = project.blocker;
    final question = project.openQuestions.firstOrNull;
    return ProjectBoundary(
      outcome: outcome,
      message: blocker?.message ?? question?.question ?? '',
      action: actionFor(outcome),
      reasonCode: blocker?.type.wire,
      taskId: blocker?.taskId ?? project.activeTaskId,
      occurredAt: timestamp,
    );
  }

  ProjectControlOutcome outcomeFor(ProjectAggregate project) {
    final boundary = project.boundary;
    if (boundary != null) return boundary.outcome;
    return _deriveOutcome(project);
  }

  ProjectControlOutcome _deriveOutcome(ProjectAggregate project) {
    if (project.status == ProjectStatus.initializing) {
      return ProjectControlOutcome.initializing;
    }
    if (project.status == ProjectStatus.completed) {
      return ProjectControlOutcome.completed;
    }
    if (project.status == ProjectStatus.cancelled) {
      return ProjectControlOutcome.cancelled;
    }
    if (project.status == ProjectStatus.failed) {
      return ProjectControlOutcome.failed;
    }
    if (project.pendingPlanApproval != null ||
        project.blocker?.type == ProjectBlockerType.planApproval) {
      return ProjectControlOutcome.awaitingPlanApproval;
    }
    if (project.openQuestions.isNotEmpty ||
        _isUserActionable(project.blocker)) {
      return ProjectControlOutcome.awaitingUserInput;
    }
    if (project.blocker?.type == ProjectBlockerType.budget) {
      return ProjectControlOutcome.pausedByBudget;
    }
    if (project.blocker?.type == ProjectBlockerType.validation) {
      return ProjectControlOutcome.blockedValidation;
    }
    if (project.status == ProjectStatus.paused) {
      return ProjectControlOutcome.paused;
    }
    return ProjectControlOutcome.running;
  }

  String? actionFor(ProjectControlOutcome outcome) => switch (outcome) {
    ProjectControlOutcome.awaitingUserInput => 'answer_question',
    ProjectControlOutcome.awaitingPlanApproval => 'approve_or_reject_plan',
    ProjectControlOutcome.blockedValidation => 'revise_plan',
    ProjectControlOutcome.pausedByBudget => 'resume_or_adjust_budget',
    ProjectControlOutcome.degradedPlanning => 'retry_planning',
    ProjectControlOutcome.paused => 'resume',
    _ => null,
  };

  bool _isUserActionable(ProjectBlocker? blocker) => switch (blocker?.type) {
    ProjectBlockerType.question ||
    ProjectBlockerType.taskEditApproval ||
    ProjectBlockerType.taskBlocked ||
    ProjectBlockerType.taskFailed ||
    ProjectBlockerType.planApproval => true,
    _ => false,
  };
}

/// Owns the durable, application-facing command boundary for a project.
///
/// Owns the durable, application-facing command boundary for a project.
class ProjectControlStateService {
  const ProjectControlStateService({
    this.machine = const ProjectControlStateMachine(),
  });

  final ProjectControlStateMachine machine;

  ProjectAggregate synchronise(ProjectAggregate project, {DateTime? now}) {
    // Once written, the boundary is canonical. A routine checkpoint must not
    // reconstruct it from lifecycle fields and accidentally erase an
    // explicit stop reason or recovery action.
    final boundary = project.boundary;
    if (boundary != null && _boundaryMatchesLifecycle(project, boundary)) {
      return project;
    }
    return materializeBoundary(project, now: now);
  }

  bool _boundaryMatchesLifecycle(
    ProjectAggregate project,
    ProjectBoundary boundary,
  ) => switch (boundary.outcome) {
    // These outcomes are command-level decisions and must remain durable even
    // when lifecycle fields have not yet caught up with them.
    ProjectControlOutcome.degradedPlanning ||
    ProjectControlOutcome.awaitingUserInput ||
    ProjectControlOutcome.awaitingPlanApproval ||
    ProjectControlOutcome.blockedValidation => true,
    ProjectControlOutcome.initializing =>
      project.status == ProjectStatus.initializing,
    ProjectControlOutcome.paused || ProjectControlOutcome.pausedByBudget =>
      project.status == ProjectStatus.paused,
    ProjectControlOutcome.completed =>
      project.status == ProjectStatus.completed,
    ProjectControlOutcome.failed => project.status == ProjectStatus.failed,
    ProjectControlOutcome.cancelled =>
      project.status == ProjectStatus.cancelled,
    ProjectControlOutcome.running =>
      project.status == ProjectStatus.active ||
          project.status == ProjectStatus.runningTask ||
          project.status == ProjectStatus.reviewingTask,
  };

  /// Materializes the boundary from the lifecycle fields.
  ///
  /// This is intentionally called only by deserialization and lifecycle
  /// transition code. Ordinary persistence uses [synchronise], which preserves
  /// an already-reduced boundary.
  ProjectAggregate materializeBoundary(
    ProjectAggregate project, {
    DateTime? now,
  }) {
    return project.copyWith(
      boundary: machine._deriveBoundary(project, now: now),
    );
  }

  ProjectAggregate withOutcome(
    ProjectAggregate project, {
    required ProjectControlOutcome outcome,
    String message = '',
    String? action,
    String? reasonCode,
    String? taskId,
    DateTime? now,
  }) {
    return reduce(
      project,
      outcome: outcome,
      message: message,
      action: action,
      reasonCode: reasonCode,
      taskId: taskId,
      now: now,
    );
  }

  /// Canonical reducer entry point for explicit command outcomes.
  ProjectAggregate reduce(
    ProjectAggregate project, {
    required ProjectControlOutcome outcome,
    String message = '',
    String? action,
    String? reasonCode,
    String? taskId,
    DateTime? now,
  }) => project.copyWith(
    boundary: ProjectBoundary(
      outcome: outcome,
      message: message.trim(),
      action: action,
      reasonCode: reasonCode,
      taskId: taskId,
      occurredAt: now ?? DateTime.now(),
    ),
  );

  ProjectBoundary derive(ProjectAggregate project, {DateTime? now}) {
    return machine.read(project, now: now);
  }
}
