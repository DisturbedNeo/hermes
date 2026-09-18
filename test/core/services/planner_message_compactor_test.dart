import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/services/planner_message_compactor.dart';

void main() {
  test('compacts old planning output while preserving tool call structure', () {
    final messages = [
      const ChatMessage(role: 'system', content: 'System prompt'),
      const ChatMessage(role: 'user', content: 'User request'),
      const ChatMessage(
        role: 'assistant',
        content: 'Old reasoning',
        reasoningContent: 'Old reasoning details',
        toolCalls: [
          {
            'id': 'old-call',
            'type': 'function',
            'function': {'name': 'project_view', 'arguments': '{}'},
          },
        ],
      ),
      const ChatMessage(
        role: 'tool',
        content: '{"ok":true,"draft_step_count":12}',
        toolCallId: 'old-call',
      ),
      const ChatMessage(role: 'assistant', content: 'Recent reasoning'),
      const ChatMessage(
        role: 'tool',
        content: '{"ok":true}',
        toolCallId: 'new-call',
      ),
    ];

    final compacted = PlannerMessageCompactor.compact(
      messages,
      maxTranscriptCharacters: 10,
      recentMessageCount: 2,
    );

    expect(compacted[0], same(messages[0]));
    expect(compacted[1], same(messages[1]));
    expect(compacted[2].content, isEmpty);
    expect(compacted[2].reasoningContent, isEmpty);
    expect(compacted[2].toolCalls, messages[2].toolCalls);
    expect(compacted[2].toolCallId, isEmpty);

    final compactedTool = jsonDecode(compacted[3].content) as Map;
    expect(compactedTool['code'], 'planning_history_compacted');
    expect(compactedTool['original_code'], isNull);
    expect(compactedTool['draft_step_count'], 12);
    expect(compacted[3].toolCallId, 'old-call');
    expect(compacted[4], same(messages[4]));
    expect(compacted[5], same(messages[5]));
  });

  test('does not copy or alter a short planning transcript', () {
    final messages = [
      const ChatMessage(role: 'system', content: 'System prompt'),
      const ChatMessage(role: 'user', content: 'User request'),
    ];

    expect(PlannerMessageCompactor.compact(messages), same(messages));
  });
}
