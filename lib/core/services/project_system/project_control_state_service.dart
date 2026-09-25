import 'package:hermes/core/models/project.dart';

/// The single deterministic reducer for project command boundaries.
///
/// Persistence still carries the legacy status/blocker/question fields, but
/// every new control decision is derived here. Callers should not duplicate
/// this precedence order.
class ProjectControlStateMachine {
  const ProjectControlStateMachine();

  ProjectBoundary read(ProjectDocument project, {DateTime? now}) {
    final timestamp = now ?? project.updatedAt;
    final outcome = outcomeFor(project);
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

  ProjectControlOutcome outcomeFor(ProjectDocument project) {
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
/// The older status/blocker/question fields remain readable for persistence
/// compatibility, but new callers can use [ProjectBoundary] without knowing
/// which combination of those fields represents a stop condition.
class ProjectControlStateService {
  const ProjectControlStateService({
    this.machine = const ProjectControlStateMachine(),
  });

  final ProjectControlStateMachine machine;

  ProjectDocument synchronise(ProjectDocument project, {DateTime? now}) {
    // A degraded planning boundary is deliberately sticky until an explicit
    // command resumes or retries planning. Otherwise a routine checkpoint
    // would immediately erase the diagnostic that the caller needs to act on.
    if (project.boundary?.outcome == ProjectControlOutcome.degradedPlanning &&
        !project.isTerminal &&
        project.blocker == null &&
        project.pendingPlanApproval == null &&
        project.openQuestions.isEmpty) {
      return project;
    }
    return project.copyWith(boundary: machine.read(project, now: now));
  }

  ProjectDocument withOutcome(
    ProjectDocument project, {
    required ProjectControlOutcome outcome,
    String message = '',
    String? action,
    String? reasonCode,
    String? taskId,
    DateTime? now,
  }) {
    return project.copyWith(
      boundary: ProjectBoundary(
        outcome: outcome,
        message: message.trim(),
        action: action,
        reasonCode: reasonCode,
        taskId: taskId,
        occurredAt: now ?? DateTime.now(),
      ),
    );
  }

  ProjectBoundary derive(ProjectDocument project, {DateTime? now}) {
    return machine.read(project, now: now);
  }
}
