import 'dart:convert';

import 'package:hermes/features/chat/application/contracts/chat_message.dart';

/// Owns the llama/OpenAI-compatible representation of chat messages.
///
/// Chat application and model ports exchange [ChatMessage] values only. The
/// nested function object and decoded argument value exist exclusively here.
class ChatMessageWireAdapter {
  const ChatMessageWireAdapter();

  Map<String, Object?> encode(ChatMessage message) => {
    'role': message.role,
    'content': message.content,
    if (message.reasoningContent.isNotEmpty)
      'reasoning_content': message.reasoningContent,
    if (message.toolCallId.isNotEmpty) 'tool_call_id': message.toolCallId,
    if (message.toolCalls.isNotEmpty)
      'tool_calls': [
        for (final call in message.toolCalls)
          {
            'id': call.id,
            'type': call.type,
            'function': {'name': call.name, 'arguments': call.arguments.values},
          },
      ],
  };

  ChatToolCall toolCall({
    required String id,
    required String name,
    required String argumentsJson,
    String type = 'function',
  }) => ChatToolCall(
    id: id,
    name: name,
    type: type,
    arguments: ChatToolArguments.fromValues(_decodeArguments(argumentsJson)),
  );

  Map<String, Object?> _decodeArguments(String value) {
    if (value.trim().isEmpty) return const <String, Object?>{};
    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) {
        return {
          for (final entry in decoded.entries)
            entry.key.toString(): entry.value,
        };
      }
      return const <String, Object?>{};
    } on FormatException {
      return const <String, Object?>{};
    }
  }

  String encodeArgumentsJson(ChatToolArguments arguments) =>
      jsonEncode(arguments.values);
}
