enum QuestionAutonomy {
  conservative,
  balanced,
  autonomous;

  String get wire => name;

  String get label => switch (this) {
    QuestionAutonomy.conservative => 'Conservative',
    QuestionAutonomy.balanced => 'Balanced',
    QuestionAutonomy.autonomous => 'Autonomous',
  };

  static QuestionAutonomy parse(Object? value) {
    final raw = value?.toString().trim().toLowerCase();
    return switch (raw) {
      'conservative' => QuestionAutonomy.conservative,
      'autonomous' => QuestionAutonomy.autonomous,
      _ => QuestionAutonomy.balanced,
    };
  }
}

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
  final int maxProjectIterations;
  final QuestionAutonomy questionAutonomy;

  const TaskSystemSettings({
    this.enabled = true,
    this.requireApprovalBeforeExecution = true,
    this.requireApprovalBeforeFileEdits = true,
    this.showTaskMessagesInChat = true,
    this.maxProjectTasksPerRun = 5,
    this.maxProjectIterations = 25,
    this.questionAutonomy = QuestionAutonomy.balanced,
  });

  TaskSystemSettings copyWith({
    bool? enabled,
    bool? requireApprovalBeforeExecution,
    bool? requireApprovalBeforeFileEdits,
    bool? showTaskMessagesInChat,
    int? maxProjectTasksPerRun,
    int? maxProjectIterations,
    QuestionAutonomy? questionAutonomy,
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
      maxProjectIterations: maxProjectIterations ?? this.maxProjectIterations,
      questionAutonomy: questionAutonomy ?? this.questionAutonomy,
    );
  }

  TaskSystemSettings normalised() => copyWith(
    maxProjectTasksPerRun: maxProjectTasksPerRun < 0
        ? 0
        : maxProjectTasksPerRun,
    maxProjectIterations: maxProjectIterations < 0 ? 0 : maxProjectIterations,
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
            maxProjectTasksPerRun == other.maxProjectTasksPerRun &&
            maxProjectIterations == other.maxProjectIterations &&
            questionAutonomy == other.questionAutonomy;
  }

  @override
  int get hashCode => Object.hash(
    enabled,
    requireApprovalBeforeExecution,
    requireApprovalBeforeFileEdits,
    showTaskMessagesInChat,
    maxProjectTasksPerRun,
    maxProjectIterations,
    questionAutonomy,
  );
}
