/// Immutable model message passed between chat application services and the
/// model completion capability.
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

/// Typed tool-call arguments. JSON parsing and model-wire encoding are owned
/// by the chat protocol adapter.
/// Typed function arguments. JSON parsing and model-wire encoding remain in
/// chat protocol adapters.
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
