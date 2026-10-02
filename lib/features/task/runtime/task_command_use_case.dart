part of 'task_execution_coordinator.dart';

/// Owns user-directed task-step commands. The task execution kernel remains
/// responsible for step mechanics, while this use case delegates validated
/// command transitions to the focused task command service.
class TaskCommandUseCase {
  TaskCommandUseCase(TaskCommandCapabilities context) : _context = context;

  final TaskCommandCapabilities _context;

  TaskCommandService get _commandService => _context.commandService;

  Future<Task> approvePendingStep({
    required WorkspaceAttachment workspace,
    required Task snapshot,
  }) => _commandService.approvePendingStep(
    workspace: workspace,
    snapshot: snapshot,
  );

  Future<Task> retryCurrentStep({
    required WorkspaceAttachment workspace,
    required Task snapshot,
  }) => _commandService.retryCurrentStep(
    workspace: workspace,
    snapshot: snapshot,
  );

  Future<Task> skipCurrentStep({
    required WorkspaceAttachment workspace,
    required Task snapshot,
  }) =>
      _commandService.skipCurrentStep(workspace: workspace, snapshot: snapshot);

  Future<Task> stopTask({
    required WorkspaceAttachment workspace,
    required Task snapshot,
  }) => _commandService.stopTask(workspace: workspace, snapshot: snapshot);

  Future<Task> answerOpenQuestion({
    required WorkspaceAttachment workspace,
    required Task snapshot,
    required String answer,
  }) => _commandService.answerOpenQuestion(
    workspace: workspace,
    snapshot: snapshot,
    answer: answer,
  );
}
