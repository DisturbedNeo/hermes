import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/helpers/chat/tool_caller.dart';
import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/core/models/chat_token.dart';

void main() {
  group('ToolCaller', () {
    test('keeps streamed argument buffers isolated by instance', () {
      final first = ToolCaller();
      final second = ToolCaller();

      var firstTools = first.applyDelta(
        messageId: 'same-message-id',
        delta: ToolCallDelta(
          index: 0,
          name: 'read_file',
          argumentsChunk: '{"path"',
        ),
        currentTools: const {},
      );
      var secondTools = second.applyDelta(
        messageId: 'same-message-id',
        delta: ToolCallDelta(
          index: 0,
          name: 'write_file',
          argumentsChunk: '{"content"',
        ),
        currentTools: const {},
      );

      firstTools = first.applyDelta(
        messageId: 'same-message-id',
        delta: ToolCallDelta(index: 0, argumentsChunk: ':"README.md"}'),
        currentTools: firstTools,
      );
      secondTools = second.applyDelta(
        messageId: 'same-message-id',
        delta: ToolCallDelta(index: 0, argumentsChunk: ':"draft"}'),
        currentTools: secondTools,
      );

      expect(firstTools[0]?.name, 'read_file');
      expect(firstTools[0]?.arguments, '{"path":"README.md"}');
      expect(secondTools[0]?.name, 'write_file');
      expect(secondTools[0]?.arguments, '{"content":"draft"}');
    });

    test('returns only pending tool entries in stable index order', () {
      const bubble = Bubble(
        id: 'assistant',
        role: MessageRole.assistant,
        text: '',
        reasoning: '',
        tools: {
          8: BubbleToolCall(name: 'third', arguments: '{}'),
          2: BubbleToolCall(
            name: 'completed',
            arguments: '{}',
            result: '{"ok":true}',
          ),
          4: BubbleToolCall(name: 'second', arguments: '{}'),
        },
      );

      final pending = ToolCaller.extractPendingToolEntries(bubble);

      expect(pending.map((entry) => entry.key), [4, 8]);
      expect(pending.map((entry) => entry.value.name), ['second', 'third']);
    });
  });
}
