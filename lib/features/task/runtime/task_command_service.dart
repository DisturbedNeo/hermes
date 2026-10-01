import 'package:hermes/core/uuid.dart';
import 'package:hermes/features/task/application/contracts/task_snapshot_models.dart';
import 'package:hermes/features/workspace/application/workspace.dart';
import 'package:hermes/features/task/runtime/task_persistence_store.dart';

/// Handles user/task commands that mutate a task without invoking a model.
///
/// Keeping these transitions separate from the tool-call runner prevents UI
/// commands such as retry, skip, stop, and answer from acquiring execution
/// concerns while preserving the same durable checkpoint after each command.
class TaskCommandService {
  const TaskCommandService({required TaskPersistenceStore persistence})
    : _persistence = persistence;

  final TaskPersistenceStore _persistence;

  Future<Task> approvePendingStep({
    required WorkspaceAttachment workspace,
    required Task snapshot,
  }) async {
    final approval = snapshot.pendingApproval;
    if (approval == null) return snapshot;
    final step = snapshot.stepById(approval.stepId);
    if (step == null) return snapshot;
    final updated =
        _replaceStep(
          snapshot,
          step.id,
          step.copyWith(status: TaskStepStatus.approved),
        ).copyWith(
          status: TaskStatus.paused,
          currentStepId: step.id,
          pendingApproval: null,
          updatedAt: DateTime.now(),
        );
    return _save(workspace, updated);
  }

  Future<Task> retryCurrentStep({
    required WorkspaceAttachment workspace,
    required Task snapshot,
  }) async {
    final step = snapshot.currentStep ?? snapshot.nextRunnableStep;
    if (step == null) return snapshot;
    final updated =
        _replaceStep(
          snapshot,
          step.id,
          step.copyWith(status: TaskStepStatus.pending),
        ).copyWith(
          status: TaskStatus.paused,
          currentStepId: step.id,
          pendingApproval: null,
          pendingQuestion: null,
          updatedAt: DateTime.now(),
        );
    return _save(workspace, updated);
  }

  Future<Task> skipCurrentStep({
    required WorkspaceAttachment workspace,
    required Task snapshot,
  }) async {
    final step = snapshot.currentStep ?? snapshot.nextRunnableStep;
    if (step == null) return snapshot;
    final now = DateTime.now();
    var updated = _replaceStep(
      snapshot,
      step.id,
      step.copyWith(status: TaskStepStatus.skipped),
    );
    updated = _advanceAfterStep(updated, now).copyWith(
      runs: [
        ...updated.runs,
        TaskRun(
          runId: 'run_${uuid.v7()}',
          stepId: step.id,
          status: TaskRunStatus.skipped,
          summary: 'Step skipped by the user.',
          memoryUpdate: '',
          toolCalls: const [],
          artifacts: const [],
          startedAt: now,
          completedAt: now,
        ),
      ],
    );
    return _save(workspace, updated);
  }

  Future<Task> stopTask({
    required WorkspaceAttachment workspace,
    required Task snapshot,
  }) => _save(
    workspace,
    snapshot.copyWith(
      status: TaskStatus.cancelled,
      currentStepId: null,
      pendingApproval: null,
      pendingQuestion: null,
      completedAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ),
  );

  Future<Task> answerOpenQuestion({
    required WorkspaceAttachment workspace,
    required Task snapshot,
    required String answer,
  }) async {
    final question = snapshot.pendingQuestion;
    final trimmed = answer.trim();
    if (question == null || trimmed.isEmpty) return snapshot;
    final step = snapshot.stepById(question.stepId);
    final updated =
        _replaceStep(
          snapshot,
          question.stepId,
          (step ?? snapshot.nextRunnableStep)?.copyWith(
                status: TaskStepStatus.pending,
              ) ??
              TaskStep(
                id: question.stepId,
                title: question.stepId,
                objective: '',
                instructions: const [],
                mayEditFiles: false,
                artifacts: const [],
                status: TaskStepStatus.pending,
              ),
        ).copyWith(
          status: TaskStatus.paused,
          pendingQuestion: null,
          memorySummary: _appendMemory(
            snapshot.memorySummary,
            'User answered: ${question.question}\nAnswer: $trimmed',
          ),
          updatedAt: DateTime.now(),
        );
    return _save(workspace, updated);
  }

  Future<Task> _save(WorkspaceAttachment workspace, Task task) async =>
      (await _persistence.save(workspace.rootPath, task)).value;

  Task _replaceStep(Task task, String stepId, TaskStep replacement) =>
      task.copyWith(
        steps: () {
          final index = task.steps.indexWhere((step) => step.id == stepId);
          if (index < 0) return task.steps;
          final steps = [...task.steps];
          steps[index] = replacement;
          return steps;
        }(),
      );

  Task _advanceAfterStep(Task snapshot, DateTime now) {
    final next = snapshot.steps.firstWhere(
      (step) =>
          step.status == TaskStepStatus.pending ||
          step.status == TaskStepStatus.approved ||
          step.status == TaskStepStatus.blocked ||
          step.status == TaskStepStatus.failed,
      orElse: () => const TaskStep(
        id: '',
        title: '',
        objective: '',
        instructions: [],
        mayEditFiles: false,
        artifacts: [],
        status: TaskStepStatus.skipped,
      ),
    );
    if (next.id.isEmpty) {
      return snapshot.copyWith(
        status: TaskStatus.completed,
        currentStepId: null,
        pendingApproval: null,
        pendingQuestion: null,
        completedAt: now,
        updatedAt: now,
      );
    }
    return snapshot.copyWith(
      status: TaskStatus.paused,
      currentStepId: next.id,
      pendingApproval: null,
      pendingQuestion: null,
      completedAt: null,
      updatedAt: now,
    );
  }

  String _appendMemory(String current, String update) {
    if (current.trim().isEmpty) return update;
    return '$current\n$update';
  }
}
