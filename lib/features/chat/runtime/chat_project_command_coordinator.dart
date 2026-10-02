import 'package:hermes/features/project/application/project_application/project_workflow_port.dart';
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
    required ProjectWorkflowPort planning,
    required ProjectWorkflowPort commands,
    required ProjectWorkflowPort recovery,
  }) : _planning = planning,
       _commands = commands,
       _recovery = recovery;

  final ProjectWorkflowPort _planning;
  final ProjectWorkflowPort _commands;
  final ProjectWorkflowPort _recovery;

  Future<ProjectWorkflowResult> execute({
    required ChatProjectCommand command,
    required WorkspaceAttachment workspace,
    required String projectId,
  }) => switch (command) {
    AnswerProjectQuestionCommand(:final answer) => _commands.answerOpenQuestion(
      workspace: workspace,
      projectId: projectId,
      answer: answer,
    ),
    StopProjectCommand() => _commands.stopProject(
      workspace: workspace,
      projectId: projectId,
    ),
    PauseProjectCommand() => _commands.pauseProject(
      workspace: workspace,
      projectId: projectId,
    ),
    RetryProjectRecoveryCommand(:final incidentId) =>
      _recovery.retryRecoveryIncident(
        workspace: workspace,
        projectId: projectId,
        incidentId: incidentId,
      ),
    ApproveProjectPlanCommand() => _commands.approvePlanRevision(
      workspace: workspace,
      projectId: projectId,
    ),
    RejectProjectPlanCommand() => _commands.rejectPlanRevision(
      workspace: workspace,
      projectId: projectId,
    ),
    RequestProjectReplanCommand(:final reason) => _planning.requestScopeChange(
      workspace: workspace,
      projectId: projectId,
      context: reason.trim().isEmpty
          ? 'User explicitly requested a roadmap revision.'
          : reason,
    ),
  };
}
