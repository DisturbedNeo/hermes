import 'dart:convert';

class ChatMessage {
  final String role;
  final String content;
  final String toolCallId;
  final List<Map<String, dynamic>> toolCalls;

  const ChatMessage({ required this.role, required this.content, this.toolCallId = '', this.toolCalls = const [] });

  Map<String, dynamic> toJson() => { 'role': role, 'content': content, 'toolCallId': toolCallId, 'toolCalls': jsonEncode(toolCalls) };
}
