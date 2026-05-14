import 'package:hermes/core/models/job.dart';

class JobSystemSettings {
  final bool enabled;
  final AutonomyLevel defaultAutonomy;
  final int maxPhaseRetries;
  final bool requireApprovalBeforeFileEdits;
  final bool requireApprovalBeforeTerminal;
  final bool showJobMessagesInChat;

  const JobSystemSettings({
    this.enabled = true,
    this.defaultAutonomy = AutonomyLevel.checkpointed,
    this.maxPhaseRetries = 1,
    this.requireApprovalBeforeFileEdits = true,
    this.requireApprovalBeforeTerminal = false,
    this.showJobMessagesInChat = true,
  });

  JobSystemSettings copyWith({
    bool? enabled,
    AutonomyLevel? defaultAutonomy,
    int? maxPhaseRetries,
    bool? requireApprovalBeforeFileEdits,
    bool? requireApprovalBeforeTerminal,
    bool? showJobMessagesInChat,
  }) {
    return JobSystemSettings(
      enabled: enabled ?? this.enabled,
      defaultAutonomy: defaultAutonomy ?? this.defaultAutonomy,
      maxPhaseRetries: maxPhaseRetries ?? this.maxPhaseRetries,
      requireApprovalBeforeFileEdits:
          requireApprovalBeforeFileEdits ?? this.requireApprovalBeforeFileEdits,
      requireApprovalBeforeTerminal:
          requireApprovalBeforeTerminal ?? this.requireApprovalBeforeTerminal,
      showJobMessagesInChat:
          showJobMessagesInChat ?? this.showJobMessagesInChat,
    );
  }

  JobSystemSettings normalised() {
    return copyWith(maxPhaseRetries: maxPhaseRetries.clamp(0, 5).toInt());
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is JobSystemSettings &&
            enabled == other.enabled &&
            defaultAutonomy == other.defaultAutonomy &&
            maxPhaseRetries == other.maxPhaseRetries &&
            requireApprovalBeforeFileEdits ==
                other.requireApprovalBeforeFileEdits &&
            requireApprovalBeforeTerminal ==
                other.requireApprovalBeforeTerminal &&
            showJobMessagesInChat == other.showJobMessagesInChat;
  }

  @override
  int get hashCode => Object.hash(
    enabled,
    defaultAutonomy,
    maxPhaseRetries,
    requireApprovalBeforeFileEdits,
    requireApprovalBeforeTerminal,
    showJobMessagesInChat,
  );
}
