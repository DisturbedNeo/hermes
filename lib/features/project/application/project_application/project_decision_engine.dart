import 'package:hermes/features/project/domain/project.dart';
import 'package:hermes/features/project/application/project_application/project_control_state_service.dart';

/// The deterministic action selected by the project runtime.
///
/// Model calls and task execution are effects performed after this decision;
/// this type deliberately contains no I/O or model-specific state.
enum ProjectExecutionAction {
  executeTask,
  revisePlan,
  recoverTask,
  awaitUserInput,
  awaitPlanApproval,
  pause,
  complete,
  block,
  evaluateCompletion,
}

class ProjectDecisionInput {
  const ProjectDecisionInput({
    required this.project,
    this.candidate,
    this.replanTriggers = const [],
    this.runIterations = 0,
    this.allowedIterations,
    this.recoveryRequested = false,
  });

  final ProjectDocument project;
  final ProjectTaskNode? candidate;
  final List<ProjectPlanRevisionTrigger> replanTriggers;
  final int runIterations;
  final int? allowedIterations;
  final bool recoveryRequested;
}

class ProjectDecision {
  const ProjectDecision({
    required this.action,
    required this.reason,
    this.task,
    this.blockerType,
  });

  final ProjectExecutionAction action;
  final String reason;
  final ProjectTaskNode? task;
  final ProjectBlockerType? blockerType;
}

/// Pure top-level project execution policy.
///
/// The runtime may still need to perform preparatory work around a decision,
/// but it no longer needs to rediscover the main command boundary from a
/// mixture of nullable fields and loop-local counters.
class ProjectDecisionEngine {
  const ProjectDecisionEngine({
    this.controlMachine = const ProjectControlStateMachine(),
  });

  final ProjectControlStateMachine controlMachine;

  ProjectDecision decide(ProjectDecisionInput input) {
    final project = input.project;
    final control = controlMachine.read(project);
    switch (control.outcome) {
      case ProjectControlOutcome.completed:
        return const ProjectDecision(
          action: ProjectExecutionAction.complete,
          reason: 'The project is already complete.',
        );
      case ProjectControlOutcome.cancelled:
      case ProjectControlOutcome.failed:
        return ProjectDecision(
          action: ProjectExecutionAction.block,
          reason: 'The project is terminal with status ${project.status.name}.',
        );
      case ProjectControlOutcome.awaitingPlanApproval:
        return const ProjectDecision(
          action: ProjectExecutionAction.awaitPlanApproval,
          reason: 'A plan revision is waiting for approval.',
        );
      case ProjectControlOutcome.awaitingUserInput:
        return const ProjectDecision(
          action: ProjectExecutionAction.awaitUserInput,
          reason: 'The project is waiting for user input.',
        );
      case ProjectControlOutcome.pausedByBudget:
        return ProjectDecision(
          action: ProjectExecutionAction.pause,
          reason: project.blocker?.message ?? 'The project is blocked.',
          blockerType: project.blocker?.type,
        );
      case ProjectControlOutcome.blockedValidation:
        return ProjectDecision(
          action: ProjectExecutionAction.block,
          reason: project.blocker?.message ?? 'The project is blocked.',
          blockerType: project.blocker?.type,
        );
      case ProjectControlOutcome.paused:
        return const ProjectDecision(
          action: ProjectExecutionAction.pause,
          reason: 'The project is paused.',
        );
      case ProjectControlOutcome.initializing:
        return const ProjectDecision(
          action: ProjectExecutionAction.block,
          reason: 'The project is still initializing.',
        );
      case ProjectControlOutcome.degradedPlanning:
      case ProjectControlOutcome.running:
        break;
    }
    if (project.maxIterations > 0 &&
        project.iterationCount >= project.maxIterations) {
      return const ProjectDecision(
        action: ProjectExecutionAction.block,
        reason: 'The project reached its maximum iteration limit.',
        blockerType: ProjectBlockerType.budget,
      );
    }
    if (input.allowedIterations != null &&
        input.runIterations >= input.allowedIterations!) {
      return const ProjectDecision(
        action: ProjectExecutionAction.pause,
        reason: 'The bounded command run reached its iteration budget.',
      );
    }
    if (input.recoveryRequested) {
      return ProjectDecision(
        action: ProjectExecutionAction.recoverTask,
        reason: 'The project has an interrupted task to recover.',
        task: input.candidate,
      );
    }
    if (input.candidate != null &&
        (project.activeTaskId != null || input.replanTriggers.isEmpty)) {
      return ProjectDecision(
        action: ProjectExecutionAction.executeTask,
        reason: 'A validated task is ready for execution.',
        task: input.candidate,
      );
    }
    if (input.replanTriggers.isNotEmpty) {
      return ProjectDecision(
        action: ProjectExecutionAction.revisePlan,
        reason: 'The project has explicit plan revision triggers.',
      );
    }
    return const ProjectDecision(
      action: ProjectExecutionAction.evaluateCompletion,
      reason: 'There is no selected task; completion should be evaluated.',
    );
  }
}
