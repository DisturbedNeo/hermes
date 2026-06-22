class TaskSystemSettings {
  final bool enabled;

  /// Whether to require manual approval before executing a task's first phase.
  /// When true (default), submitting a task in the composer creates a plan and
  /// waits for the user to explicitly start it. When false, the task runs
  /// immediately after planning.
  final bool requireApprovalBeforeExecution;

  /// Whether to require manual approval before file edits by tasks during
  /// step execution.
  final bool requireApprovalBeforeFileEdits;
  final bool showTaskMessagesInChat;
  final int maxProjectTasksPerRun;

  const TaskSystemSettings({
    this.enabled = true,
    this.requireApprovalBeforeExecution = true,
    this.requireApprovalBeforeFileEdits = true,
    this.showTaskMessagesInChat = true,
    this.maxProjectTasksPerRun = 5,
  });

  TaskSystemSettings copyWith({
    bool? enabled,
    bool? requireApprovalBeforeExecution,
    bool? requireApprovalBeforeFileEdits,
    bool? showTaskMessagesInChat,
    int? maxProjectTasksPerRun,
  }) {
    return TaskSystemSettings(
      enabled: enabled ?? this.enabled,
      requireApprovalBeforeExecution:
          requireApprovalBeforeExecution ?? this.requireApprovalBeforeExecution,
      requireApprovalBeforeFileEdits:
          requireApprovalBeforeFileEdits ?? this.requireApprovalBeforeFileEdits,
      showTaskMessagesInChat:
          showTaskMessagesInChat ?? this.showTaskMessagesInChat,
      maxProjectTasksPerRun:
          maxProjectTasksPerRun ?? this.maxProjectTasksPerRun,
    );
  }

  TaskSystemSettings normalised() => copyWith(
    maxProjectTasksPerRun: maxProjectTasksPerRun.clamp(1, 25).toInt(),
  );

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is TaskSystemSettings &&
            enabled == other.enabled &&
            requireApprovalBeforeExecution ==
                other.requireApprovalBeforeExecution &&
            requireApprovalBeforeFileEdits ==
                other.requireApprovalBeforeFileEdits &&
            showTaskMessagesInChat == other.showTaskMessagesInChat &&
            maxProjectTasksPerRun == other.maxProjectTasksPerRun;
  }

  @override
  int get hashCode => Object.hash(
    enabled,
    requireApprovalBeforeExecution,
    requireApprovalBeforeFileEdits,
    showTaskMessagesInChat,
    maxProjectTasksPerRun,
  );
}
