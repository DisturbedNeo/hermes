import 'package:hermes/core/models/task.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/services/task_system/task_service.dart';

/// Application-facing boundary for standalone task lifecycle commands.
class TaskOrchestrator {
  final TaskService _service;

  const TaskOrchestrator({required TaskService service}) : _service = service;

  TaskService get service => _service;

  Future<Task> recoverTask({
    required WorkspaceAttachment workspace,
    required Task snapshot,
  }) => _service.recoverTask(workspace: workspace, snapshot: snapshot);

  Future<Task> stopTask({
    required WorkspaceAttachment workspace,
    required Task snapshot,
  }) => _service.stopTask(workspace: workspace, snapshot: snapshot);

  Future<Task> answerOpenQuestion({
    required WorkspaceAttachment workspace,
    required Task snapshot,
    required String answer,
  }) => _service.answerOpenQuestion(
    workspace: workspace,
    snapshot: snapshot,
    answer: answer,
  );

  Future<Task> approvePendingStep({
    required WorkspaceAttachment workspace,
    required Task snapshot,
  }) => _service.approvePendingStep(workspace: workspace, snapshot: snapshot);

  Future<Task> retryCurrentStep({
    required WorkspaceAttachment workspace,
    required Task snapshot,
  }) => _service.retryCurrentStep(workspace: workspace, snapshot: snapshot);

  Future<Task> skipCurrentStep({
    required WorkspaceAttachment workspace,
    required Task snapshot,
  }) => _service.skipCurrentStep(workspace: workspace, snapshot: snapshot);
}
