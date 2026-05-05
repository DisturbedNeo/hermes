class ChatMessage {
  final String role;
  final String content;
  final String reasoningContent;
  final String toolCallId;
  final List<Map<String, dynamic>> toolCalls;

  const ChatMessage({
    required this.role,
    required this.content,
    this.reasoningContent = '',
    this.toolCallId = '',
    this.toolCalls = const [],
  });

  Map<String, dynamic> toJson() {
    return {
      'role': role,
      'content': content,
      if (reasoningContent.isNotEmpty) 'reasoning_content': reasoningContent,
      if (toolCallId.isNotEmpty) 'tool_call_id': toolCallId,
      if (toolCalls.isNotEmpty) 'tool_calls': toolCalls,
    };
  }
}
