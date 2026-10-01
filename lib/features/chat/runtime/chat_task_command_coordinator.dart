import 'package:hermes/features/task/application/contracts/task_snapshot_models.dart';
import 'package:hermes/features/task/application/task_application/task_ports.dart';
import 'package:hermes/features/workspace/application/workspace.dart';

sealed class ChatTaskCommand {
  const ChatTaskCommand();
}

class RetryTaskPhaseCommand extends ChatTaskCommand {
  const RetryTaskPhaseCommand();
}

class SkipTaskPhaseCommand extends ChatTaskCommand {
  const SkipTaskPhaseCommand();
}

class StopTaskCommand extends ChatTaskCommand {
  const StopTaskCommand();
}

class ApproveTaskStepCommand extends ChatTaskCommand {
  const ApproveTaskStepCommand();
}

class AnswerTaskQuestionCommand extends ChatTaskCommand {
  const AnswerTaskQuestionCommand(this.answer);

  final String answer;
}

/// Executes typed task commands against the task application port.
class ChatTaskCommandCoordinator {
  const ChatTaskCommandCoordinator({required TaskExecutionPort execution})
    : _execution = execution;

  final TaskExecutionPort _execution;

  Future<Task> execute({
    required ChatTaskCommand command,
    required WorkspaceAttachment workspace,
    required Task snapshot,
  }) => switch (command) {
    RetryTaskPhaseCommand() => _execution.retryCurrentStep(
      workspace: workspace,
      snapshot: snapshot,
    ),
    SkipTaskPhaseCommand() => _execution.skipCurrentStep(
      workspace: workspace,
      snapshot: snapshot,
    ),
    StopTaskCommand() => _execution.stopTask(
      workspace: workspace,
      snapshot: snapshot,
    ),
    ApproveTaskStepCommand() => _execution.approvePendingStep(
      workspace: workspace,
      snapshot: snapshot,
    ),
    AnswerTaskQuestionCommand(:final answer) => _execution.answerOpenQuestion(
      workspace: workspace,
      snapshot: snapshot,
      answer: answer,
    ),
  };
}
