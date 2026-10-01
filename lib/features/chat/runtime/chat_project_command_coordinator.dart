import 'package:hermes/features/project/application/contracts/project_snapshot_models.dart';
import 'package:hermes/features/project/application/project_application/project_ports.dart';
import 'package:hermes/features/workspace/application/workspace.dart';

sealed class ChatProjectCommand {
  const ChatProjectCommand();
}

class AnswerProjectQuestionCommand extends ChatProjectCommand {
  const AnswerProjectQuestionCommand(this.answer);

  final String answer;
}

class StopProjectCommand extends ChatProjectCommand {
  const StopProjectCommand();
}

class PauseProjectCommand extends ChatProjectCommand {
  const PauseProjectCommand();
}

class RetryProjectRecoveryCommand extends ChatProjectCommand {
  const RetryProjectRecoveryCommand(this.incidentId);

  final String incidentId;
}

class ApproveProjectPlanCommand extends ChatProjectCommand {
  const ApproveProjectPlanCommand();
}

class RejectProjectPlanCommand extends ChatProjectCommand {
  const RejectProjectPlanCommand();
}

class RequestProjectReplanCommand extends ChatProjectCommand {
  const RequestProjectReplanCommand(this.reason);

  final String reason;
}

/// Executes typed project commands against planning, command, and recovery
/// ports. Chat state updates remain in the session orchestrator.
class ChatProjectCommandCoordinator {
  const ChatProjectCommandCoordinator({
    required ProjectPlanningPort planning,
    required ProjectCommandPort commands,
    required ProjectRecoveryCommandsPort recovery,
  }) : _planning = planning,
       _commands = commands,
       _recovery = recovery;

  final ProjectPlanningPort _planning;
  final ProjectCommandPort _commands;
  final ProjectRecoveryCommandsPort _recovery;

  Future<ProjectAggregate> execute({
    required ChatProjectCommand command,
    required WorkspaceAttachment workspace,
    required ProjectAggregate snapshot,
  }) => switch (command) {
    AnswerProjectQuestionCommand(:final answer) => _commands.answerOpenQuestion(
      workspace: workspace,
      snapshot: snapshot,
      answer: answer,
    ),
    StopProjectCommand() => _commands.stopProject(
      workspace: workspace,
      snapshot: snapshot,
    ),
    PauseProjectCommand() => _commands.pauseProject(
      workspace: workspace,
      snapshot: snapshot,
    ),
    RetryProjectRecoveryCommand(:final incidentId) =>
      _recovery.retryRecoveryIncident(
        workspace: workspace,
        snapshot: snapshot,
        incidentId: incidentId,
      ),
    ApproveProjectPlanCommand() => _commands.approvePlanRevision(
      workspace: workspace,
      snapshot: snapshot,
    ),
    RejectProjectPlanCommand() => _commands.rejectPlanRevision(
      workspace: workspace,
      snapshot: snapshot,
    ),
    RequestProjectReplanCommand(:final reason) => _planning.requestScopeChange(
      workspace: workspace,
      snapshot: snapshot,
      context: reason.trim().isEmpty
          ? 'User explicitly requested a roadmap revision.'
          : reason,
    ),
  };
}
