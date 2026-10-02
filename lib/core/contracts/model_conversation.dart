/// Framework-neutral conversation contracts shared by model and workflow
/// runtimes.
///
/// These values describe the application-facing model protocol. Wire JSON,
/// chat bubbles, and persistence snapshots are deliberately kept outside
/// this module.
enum MessageRole { user, assistant, system, tool }

extension MessageRoleWire on MessageRole {
  String get wire => switch (this) {
    MessageRole.user => 'user',
    MessageRole.assistant => 'assistant',
    MessageRole.system => 'system',
    MessageRole.tool => 'tool',
  };
}

/// Immutable model message passed between application services and a model
/// completion capability.
class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.content,
    this.reasoningContent = '',
    this.toolCallId = '',
    this.toolCalls = const [],
  });

  final String role;
  final String content;
  final String reasoningContent;
  final String toolCallId;
  final List<ChatToolCall> toolCalls;
}

/// Typed function arguments. JSON parsing and model-wire encoding remain in
/// protocol adapters.
class ChatToolArguments {
  const ChatToolArguments.fromValues(this._values);

  const ChatToolArguments.empty() : _values = const {};

  final Map<String, Object?> _values;

  Map<String, Object?> get values => Map.unmodifiable(_values);
}

/// Typed function tool call used by model request messages.
class ChatToolCall {
  const ChatToolCall({
    required this.id,
    required this.name,
    this.arguments = const ChatToolArguments.empty(),
    this.type = 'function',
  });

  final String id;
  final String name;
  final ChatToolArguments arguments;
  final String type;
}

/// A model stream delta. It contains no transport or framework types.
class ChatToken {
  const ChatToken({this.content, this.reasoning, this.tool});

  final String? content;
  final String? reasoning;
  final ToolCallDelta? tool;
}

class ToolCallDelta {
  const ToolCallDelta({
    required this.index,
    this.id,
    this.name,
    this.argumentsChunk,
  });

  final int index;
  final String? id;
  final String? name;
  final String? argumentsChunk;
}

/// Shared context-compaction policy used by chat, task, and project model
/// workflows. Serialization remains owned by the preferences adapter.
class CompactionSettings {
  final bool enabled;
  final double triggerThreshold;
  final double hardLimitThreshold;
  final int recentWindowUnits;
  final bool allowEmergencyPayloadTruncation;

  const CompactionSettings({
    this.enabled = true,
    this.triggerThreshold = 0.80,
    this.hardLimitThreshold = 0.95,
    this.recentWindowUnits = 6,
    this.allowEmergencyPayloadTruncation = false,
  });

  CompactionSettings copyWith({
    bool? enabled,
    double? triggerThreshold,
    double? hardLimitThreshold,
    int? recentWindowUnits,
    bool? allowEmergencyPayloadTruncation,
  }) => CompactionSettings(
    enabled: enabled ?? this.enabled,
    triggerThreshold: triggerThreshold ?? this.triggerThreshold,
    hardLimitThreshold: hardLimitThreshold ?? this.hardLimitThreshold,
    recentWindowUnits: recentWindowUnits ?? this.recentWindowUnits,
    allowEmergencyPayloadTruncation:
        allowEmergencyPayloadTruncation ?? this.allowEmergencyPayloadTruncation,
  ).normalised();

  CompactionSettings normalised() {
    final trigger = triggerThreshold.clamp(0.60, 0.90).toDouble();
    final hard = hardLimitThreshold.clamp(trigger, 0.99).toDouble();
    return CompactionSettings(
      enabled: enabled,
      triggerThreshold: trigger,
      hardLimitThreshold: hard,
      recentWindowUnits: recentWindowUnits.clamp(2, 10).toInt(),
      allowEmergencyPayloadTruncation: allowEmergencyPayloadTruncation,
    );
  }
}
