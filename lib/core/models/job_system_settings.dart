class JobSystemSettings {
  final bool enabled;
  /// Whether to require manual approval before executing a job's first phase.
  /// When true (default), submitting a job in the composer creates a plan and
  /// waits for the user to explicitly start it. When false, the job runs
  /// immediately after planning.
  final bool requireApprovalBeforeExecution;
  /// Whether to require manual approval before file edits by jobs during
  /// step execution.
  final bool requireApprovalBeforeFileEdits;
  final bool showJobMessagesInChat;

  const JobSystemSettings({
    this.enabled = true,
    this.requireApprovalBeforeExecution = true,
    this.requireApprovalBeforeFileEdits = true,
    this.showJobMessagesInChat = true,
  });

  JobSystemSettings copyWith({
    bool? enabled,
    bool? requireApprovalBeforeExecution,
    bool? requireApprovalBeforeFileEdits,
    bool? showJobMessagesInChat,
  }) {
    return JobSystemSettings(
      enabled: enabled ?? this.enabled,
      requireApprovalBeforeExecution:
          requireApprovalBeforeExecution ?? this.requireApprovalBeforeExecution,
      requireApprovalBeforeFileEdits:
          requireApprovalBeforeFileEdits ?? this.requireApprovalBeforeFileEdits,
      showJobMessagesInChat:
          showJobMessagesInChat ?? this.showJobMessagesInChat,
    );
  }

  JobSystemSettings normalised() => this;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is JobSystemSettings &&
            enabled == other.enabled &&
            requireApprovalBeforeExecution ==
                other.requireApprovalBeforeExecution &&
            requireApprovalBeforeFileEdits ==
                other.requireApprovalBeforeFileEdits &&
            showJobMessagesInChat == other.showJobMessagesInChat;
  }

  @override
  int get hashCode => Object.hash(
    enabled,
    requireApprovalBeforeExecution,
    requireApprovalBeforeFileEdits,
    showJobMessagesInChat,
  );
}
