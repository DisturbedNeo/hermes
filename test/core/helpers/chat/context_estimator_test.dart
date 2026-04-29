import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/helpers/chat/context_estimator.dart';
import 'package:hermes/core/helpers/chat/payload_builder.dart';
import 'package:hermes/core/helpers/chat/tool_caller.dart';
import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/models/tool_definition.dart';

void main() {
  group('ContextEstimator', () {
    test('counts serialized tool call metadata', () {
      final estimate = ContextEstimator.estimateChatCompletionRequest(
        messages: [
          ChatMessage(
            role: MessageRole.assistant.wire,
            content: '',
            toolCalls: [
              {
                'id': 'call_1',
                'type': 'function',
                'function': {
                  'name': 'read_file',
                  'arguments': jsonEncode({
                    'path': 'lib/core/services/chat/chat_service.dart',
                  }),
                },
              },
            ],
          ),
        ],
      );

      expect(estimate, greaterThan(0));
    });

    test('counts tool result messages in payloads', () {
      final messagesWithoutResult = PayloadBuilder.buildPayloadWithTools(
        messages: [
          const Bubble(
            id: 'assistant',
            role: MessageRole.assistant,
            text: '',
            reasoning: '',
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

      final messagesWithResult = PayloadBuilder.buildPayloadWithTools(
        messages: [
          const Bubble(
            id: 'assistant',
            role: MessageRole.assistant,
            text: '',
            reasoning: '',
            tools: {
              0: BubbleToolCall(
                id: 'call_1',
                name: 'read_file',
                arguments: '{"path":"README.md"}',
                result:
                    '{"path":"README.md","content":"This result is sent back to the model."}',
              ),
            },
          ),
        ],
        upToIndexInclusive: 0,
      );

      final estimateWithoutResult =
          ContextEstimator.estimateChatCompletionRequest(
            messages: messagesWithoutResult,
          );
      final estimateWithResult = ContextEstimator.estimateChatCompletionRequest(
        messages: messagesWithResult,
      );

      expect(estimateWithResult, greaterThan(estimateWithoutResult));
    });

    test('counts tool definitions sent with the request', () {
      final messages = [
        ChatMessage(role: MessageRole.user.wire, content: 'Read README.md'),
      ];
      final withoutTools = ContextEstimator.estimateChatCompletionRequest(
        messages: messages,
      );

      final withTools = ContextEstimator.estimateChatCompletionRequest(
        messages: messages,
        extraParams: ToolCaller.buildExtraParams(
          addGenerationPrompt: true,
          toolDefs: const [
            ToolDefinition(
              id: 'read_file',
              name: 'Read file',
              description: 'Read a file from the active workspace.',
              schema: {
                'type': 'object',
                'properties': {
                  'path': {'type': 'string'},
                },
                'required': ['path'],
              },
            ),
          ],
        ),
      );

      expect(withTools, greaterThan(withoutTools));
    });
  });
}
