part of 'task_execution_coordinator.dart';

/// Owns user-directed task-step commands. The task execution kernel remains
/// responsible for step mechanics, while this use case delegates validated
/// command transitions to the focused task command service.
class TaskCommandUseCase {
  TaskCommandUseCase(TaskCommandCapabilities context) : _context = context;

  final TaskCommandCapabilities _context;

  TaskCommandService get _commandService => _context.commandService;

  Future<TaskAggregate> approvePendingStep({
    required WorkspaceAttachment workspace,
    required TaskAggregate snapshot,
  }) => _commandService.approvePendingStep(
    workspace: workspace,
    snapshot: snapshot,
  );

  Future<TaskAggregate> retryCurrentStep({
    required WorkspaceAttachment workspace,
    required TaskAggregate snapshot,
  }) => _commandService.retryCurrentStep(
    workspace: workspace,
    snapshot: snapshot,
  );

  Future<TaskAggregate> skipCurrentStep({
    required WorkspaceAttachment workspace,
    required TaskAggregate snapshot,
  }) =>
      _commandService.skipCurrentStep(workspace: workspace, snapshot: snapshot);

  Future<TaskAggregate> stopTask({
    required WorkspaceAttachment workspace,
    required TaskAggregate snapshot,
  }) => _commandService.stopTask(workspace: workspace, snapshot: snapshot);

  Future<TaskAggregate> answerOpenQuestion({
    required WorkspaceAttachment workspace,
    required TaskAggregate snapshot,
    required String answer,
  }) => _commandService.answerOpenQuestion(
    workspace: workspace,
    snapshot: snapshot,
    answer: answer,
  );
}
