import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/helpers/chat/payload_builder.dart';
import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/core/serialization/model_json.dart';

void main() {
  group('PayloadBuilder', () {
    test('omits messages covered by summary memory when requested', () {
      final messages = [
        const Bubble(
          id: 'system',
          role: MessageRole.system,
          text: 'System prompt',
          reasoning: '',
        ),
        const Bubble(
          id: 'user',
          role: MessageRole.user,
          text: 'Original task',
          reasoning: '',
        ),
        const Bubble(
          id: 'summary',
          role: MessageRole.system,
          text: 'Summary memory',
          reasoning: '',
          isSummaryMemory: true,
        ),
        const Bubble(
          id: 'covered',
          role: MessageRole.assistant,
          text: 'Old verbose answer',
          reasoning: '',
          omittedFromModelPayload: true,
          summaryId: 'summary',
        ),
        const Bubble(
          id: 'recent',
          role: MessageRole.user,
          text: 'Recent request',
          reasoning: '',
        ),
      ];

      final payload = PayloadBuilder.buildPayloadWithTools(
        messages: messages,
        upToIndexInclusive: messages.length - 1,
        omitCoveredMessages: true,
      );

      expect(payload.map((message) => message.content), [
        'System prompt',
        'Original task',
        'Summary memory',
        'Recent request',
      ]);
    });

    test('keeps covered messages in full transcript payloads by default', () {
      final messages = [
        const Bubble(
          id: 'summary',
          role: MessageRole.system,
          text: 'Summary memory',
          reasoning: '',
          isSummaryMemory: true,
        ),
        const Bubble(
          id: 'covered',
          role: MessageRole.assistant,
          text: 'Old verbose answer',
          reasoning: '',
          omittedFromModelPayload: true,
          summaryId: 'summary',
        ),
      ];

      final payload = PayloadBuilder.buildPayloadWithTools(
        messages: messages,
        upToIndexInclusive: messages.length - 1,
      );

      expect(
        payload.map((message) => message.content),
        contains('Old verbose answer'),
      );
    });

    test('supports one-request emergency omissions', () {
      final messages = [
        const Bubble(
          id: 'user',
          role: MessageRole.user,
          text: 'Original task',
          reasoning: '',
        ),
        const Bubble(
          id: 'old',
          role: MessageRole.assistant,
          text: 'Old answer',
          reasoning: '',
        ),
        const Bubble(
          id: 'recent',
          role: MessageRole.user,
          text: 'Recent request',
          reasoning: '',
        ),
      ];

      final payload = PayloadBuilder.buildPayloadWithTools(
        messages: messages,
        upToIndexInclusive: messages.length - 1,
        omittedMessageIds: const {'old'},
      );

      expect(payload.map((message) => message.content), [
        'Original task',
        'Recent request',
      ]);
    });

    test(
      'serializes summary memory as user role for llama-server templates',
      () {
        final payload = PayloadBuilder.buildPayloadWithTools(
          messages: [
            const Bubble(
              id: 'system',
              role: MessageRole.system,
              text: 'System prompt',
              reasoning: '',
            ),
            const Bubble(
              id: 'intent',
              role: MessageRole.user,
              text: 'Original task',
              reasoning: '',
            ),
            const Bubble(
              id: 'summary',
              role: MessageRole.system,
              text: 'Context summary',
              reasoning: '',
              isSummaryMemory: true,
            ),
            const Bubble(
              id: 'recent',
              role: MessageRole.user,
              text: 'Recent request',
              reasoning: '',
            ),
          ],
          upToIndexInclusive: 3,
          omitCoveredMessages: true,
        );

        expect(payload.map((message) => message.role).toList(), [
          'system',
          'user',
          'user',
          'user',
        ]);
        expect(payload[2].content, 'Context summary');
      },
    );

    test(
      'preserves reasoning and structured args for assistant tool calls',
      () {
        final payload = PayloadBuilder.buildPayloadWithTools(
          messages: [
            const Bubble(
              id: 'assistant',
              role: MessageRole.assistant,
              text: '',
              reasoning: 'I should read the file first.',
              tools: {
                0: BubbleToolCall(
                  id: 'call_1',
                  name: 'read_file',
                  arguments: '{"path":"README.md"}',
                ),
              },
            ),
          ],
          upToIndexInclusive: 0,
        );

        expect(
          payload.single.reasoningContent,
          'I should read the file first.',
        );
        expect(payload.single.toolCalls.single['function'], {
          'name': 'read_file',
          'arguments': {'path': 'README.md'},
        });
        expect(
          jsonEncode(ModelJson.encode(payload.single)),
          contains('reasoning_content'),
        );
      },
    );

    test(
      'coalesces consecutive trailing assistant messages for llama-server',
      () {
        final payload = PayloadBuilder.buildPayload(
          messages: [
            const Bubble(
              id: 'user',
              role: MessageRole.user,
              text: 'Start the project',
              reasoning: '',
            ),
            const Bubble(
              id: 'created',
              role: MessageRole.assistant,
              text: 'Project created.',
              reasoning: '',
            ),
            const Bubble(
              id: 'step',
              role: MessageRole.assistant,
              text: 'Task step finished.',
              reasoning: '',
            ),
            const Bubble(
              id: 'paused',
              role: MessageRole.assistant,
              text: 'Project paused.',
              reasoning: '',
            ),
          ],
          upToIndexInclusive: 3,
        );

        expect(payload.map((message) => message.role), ['user', 'assistant']);
        expect(
          payload.last.content,
          'Project created.\n\nTask step finished.\n\nProject paused.',
        );
      },
    );

    test(
      'keeps assistant tool call messages separate when coalescing tail',
      () {
        final payload = PayloadBuilder.buildPayloadWithTools(
          messages: [
            const Bubble(
              id: 'assistant-tool',
              role: MessageRole.assistant,
              text: 'Reading files.',
              reasoning: '',
              tools: {
                0: BubbleToolCall(
                  id: 'call_1',
                  name: 'read_file',
                  arguments: '{"path":"README.md"}',
                  result: '{"content":"hello"}',
                ),
              },
            ),
            const Bubble(
              id: 'status',
              role: MessageRole.assistant,
              text: 'Task step finished.',
              reasoning: '',
            ),
            const Bubble(
              id: 'paused',
              role: MessageRole.assistant,
              text: 'Project paused.',
              reasoning: '',
            ),
          ],
          upToIndexInclusive: 2,
        );

        expect(payload.map((message) => message.role), [
          'assistant',
          'tool',
          'assistant',
        ]);
        expect(payload.first.toolCalls, isNotEmpty);
        expect(payload.last.content, 'Task step finished.\n\nProject paused.');
      },
    );
  });
}
