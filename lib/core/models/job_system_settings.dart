class JobSystemSettings {
  final bool enabled;
  final bool requireApprovalBeforeFileEdits;
  final bool showJobMessagesInChat;

  const JobSystemSettings({
    this.enabled = true,
    this.requireApprovalBeforeFileEdits = true,
    this.showJobMessagesInChat = true,
  });

  JobSystemSettings copyWith({
    bool? enabled,
    bool? requireApprovalBeforeFileEdits,
    bool? showJobMessagesInChat,
  }) {
    return JobSystemSettings(
      enabled: enabled ?? this.enabled,
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
            requireApprovalBeforeFileEdits ==
                other.requireApprovalBeforeFileEdits &&
            showJobMessagesInChat == other.showJobMessagesInChat;
  }

  @override
  int get hashCode => Object.hash(
    enabled,
    requireApprovalBeforeFileEdits,
    showJobMessagesInChat,
  );
}
