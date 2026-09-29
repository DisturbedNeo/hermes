import 'package:hermes/shared_kernel/task.dart';

/// Converts an interrupted running task into a durable, resumable state.
///
/// This service does not decide whether recovery should be attempted; the
/// command/application layer makes that decision. Keeping the transformation
/// here makes recovery testable without a model client or workspace tools.
class TaskRecoveryService {
  const TaskRecoveryService();

  Task recover(Task snapshot, {DateTime? now}) {
    if (snapshot.status != TaskStatus.running) return snapshot;
    final timestamp = now ?? DateTime.now();
    final steps = snapshot.steps.map((step) {
      if (step.status == TaskStepStatus.running) {
        return step.copyWith(status: TaskStepStatus.blocked);
      }
      return step;
    }).toList();
    return snapshot.copyWith(
      status: TaskStatus.blocked,
      steps: steps,
      updatedAt: timestamp,
      memorySummary: _appendMemory(
        snapshot.memorySummary,
        'Recovered an interrupted task. Review the current step before continuing.',
      ),
    );
  }

  String _appendMemory(String current, String update) {
    final trimmed = update.trim();
    if (trimmed.isEmpty) return current;
    if (current.trim().isEmpty) return trimmed;
    final lines = current.split('\n');
    if (lines.contains(trimmed)) return current;
    return [...lines, trimmed].join('\n');
  }
}
