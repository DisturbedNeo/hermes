import 'dart:convert';

import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/core/models/chat_message.dart';

class PayloadBuilder {
  static List<ChatMessage> buildPayload({
    required List<Bubble> messages,
    required int upToIndexInclusive,
    bool omitCoveredMessages = false,
    Set<String> omittedMessageIds = const {},
  }) {
    if (messages.isEmpty || upToIndexInclusive < 0) {
      return [];
    }

    final payload = _buildMessages(
      messages: messages,
      upToIndexInclusive: upToIndexInclusive,
      omitCoveredMessages: omitCoveredMessages,
      omittedMessageIds: omittedMessageIds,
    );

    if (payload.isNotEmpty &&
        payload.last.role == MessageRole.assistant.wire &&
        payload.last.content.trim().isEmpty) {
      payload.removeLast();
    }

    return payload;
  }

  static List<ChatMessage> buildPayloadWithTools({
    required List<Bubble> messages,
    required int upToIndexInclusive,
    bool omitCoveredMessages = false,
    Set<String> omittedMessageIds = const {},
  }) {
    if (messages.isEmpty || upToIndexInclusive < 0) {
      return [];
    }

    return _buildMessages(
      messages: messages,
      upToIndexInclusive: upToIndexInclusive,
      omitCoveredMessages: omitCoveredMessages,
      omittedMessageIds: omittedMessageIds,
    );
  }

  static List<ChatMessage> _buildMessages({
    required List<Bubble> messages,
    required int upToIndexInclusive,
    required bool omitCoveredMessages,
    required Set<String> omittedMessageIds,
  }) {
    final clamped = upToIndexInclusive.clamp(0, messages.length - 1);
    final conversation = messages.take(clamped + 1);

    final result = <ChatMessage>[];

    for (final b in conversation) {
      if (omittedMessageIds.contains(b.id)) {
        continue;
      }

      if (omitCoveredMessages && b.omittedFromModelPayload) {
        continue;
      }

      if (b.role == MessageRole.tool) {
        continue;
      }

      if (b.role == MessageRole.assistant && b.tools.isNotEmpty) {
        final toolCalls = b.tools.entries.map((entry) {
          final index = entry.key;
          final tc = entry.value;
          final callId = tc.id ?? 'call_$index';
          return {
            'id': callId,
            'type': 'function',
            'function': {
              'name': tc.name,
              'arguments': _toolArgumentsForPayload(tc.arguments),
            },
          };
        }).toList();

        result.add(
          ChatMessage(
            role: 'assistant',
            content: b.text,
            reasoningContent: b.reasoning,
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
        result.add(ChatMessage(role: _wireRoleFor(b), content: mergedText));
      }
    }

    return result;
  }

  static String _wireRoleFor(Bubble bubble) {
    if (bubble.isSummaryMemory) {
      return MessageRole.user.wire;
    }

    return bubble.role.wire;
  }

  static dynamic _toolArgumentsForPayload(String? arguments) {
    if (arguments == null || arguments.trim().isEmpty) {
      return <String, dynamic>{};
    }

    try {
      final decoded = jsonDecode(arguments);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return decoded;
    } catch (_) {
      return arguments;
    }
  }
}
