class ChatMessage {
  final String role;
  final String content;
  final String toolCallId;
  final List<Map<String, dynamic>> toolCalls;

  const ChatMessage({
    required this.role,
    required this.content,
    this.toolCallId = '',
    this.toolCalls = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'role': role,
      'content': content,
      if (toolCallId.isNotEmpty) 'tool_call_id': toolCallId,
      if (toolCalls.isNotEmpty) 'tool_calls': toolCalls,
    };
  }
}
