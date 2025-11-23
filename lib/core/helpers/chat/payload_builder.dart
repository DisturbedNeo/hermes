import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/core/models/chat_message.dart';

class PayloadBuilder {
    static List<ChatMessage> buildPayload({ 
      required List<Bubble> messages,
      required int upToIndexInclusive 
    }) {
    if (messages.isEmpty || upToIndexInclusive < 0) {
      return [];
    }

    final clamped = upToIndexInclusive.clamp(0, messages.length - 1);
    final conversation = messages.take(clamped + 1);

    final payload = conversation
        .map((m) { 
          final mergedText = [
            if (m.reasoning.isNotEmpty) m.reasoning,
            m.text
          ].join('\n');

          return ChatMessage(role: m.role.wire, content: mergedText);
        })
        .toList();

    if (payload.isNotEmpty &&
        payload.last.role == MessageRole.assistant.wire &&
        payload.last.content.trim().isEmpty) {
          payload.removeLast();
    }

    return payload;
  }

  static List<ChatMessage> buildPayloadWithTools({ 
    required List<Bubble> messages,
    required int upToIndexInclusive
  }) {
    final clamped = upToIndexInclusive.clamp(0, messages.length - 1);
    final conversation = messages.take(clamped + 1);

    final result = <ChatMessage>[];

    for (final b in conversation) {
      if (b.role == MessageRole.assistant && b.tools.isNotEmpty) {
        final toolCalls = b.tools.entries.map((entry) {
          final index = entry.key;
          final tc = entry.value;
          final callId = tc.id ?? 'call_$index';
          return {
            'id': callId,
            'type': 'function',
            'function': {'name': tc.name, 'arguments': tc.arguments ?? '{}'},
          };
        }).toList();

        result.add(
          ChatMessage(
            role: 'assistant',
            content: b.text.isEmpty ? '' : b.text,
            toolCalls: toolCalls,
          ),
        );

        for (MapEntry<int, BubbleToolCall> entry in b.tools.entries) {
          final index = entry.key;
          final tc = entry.value;
          final callId = tc.id ?? 'call_$index';
          if (tc.result == null) continue;

          result.add(
            ChatMessage(
              role: 'tool',
              content: tc.result ?? '',
              toolCallId: callId,
            ),
          );
        }
      } else {
        final mergedText = [
          if (b.reasoning.isNotEmpty) b.reasoning,
          b.text,
        ].join('\n');
        result.add(ChatMessage(role: b.role.wire, content: mergedText));
      }
    }

    return result;
  }
}
