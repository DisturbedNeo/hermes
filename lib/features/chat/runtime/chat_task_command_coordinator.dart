import 'package:hermes/features/task/application/task_application/task_workflow_port.dart';
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
  const ChatTaskCommandCoordinator({required TaskWorkflowPort execution})
    : _execution = execution;

  final TaskWorkflowPort _execution;

  Future<TaskWorkflowResult> execute({
    required ChatTaskCommand command,
    required WorkspaceAttachment workspace,
    required String taskId,
  }) => switch (command) {
    RetryTaskPhaseCommand() => _execution.retryCurrentStep(
      workspace: workspace,
      taskId: taskId,
    ),
    SkipTaskPhaseCommand() => _execution.skipCurrentStep(
      workspace: workspace,
      taskId: taskId,
    ),
    StopTaskCommand() => _execution.stopTask(
      workspace: workspace,
      taskId: taskId,
    ),
    ApproveTaskStepCommand() => _execution.approvePendingStep(
      workspace: workspace,
      taskId: taskId,
    ),
    AnswerTaskQuestionCommand(:final answer) => _execution.answerOpenQuestion(
      workspace: workspace,
      taskId: taskId,
      answer: answer,
    ),
  };
}
