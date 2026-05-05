import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/helpers/chat/content_normaliser.dart';
import 'package:hermes/core/models/bubble.dart';

void main() {
  group('ContentNormaliser', () {
    test('removes multiple empty think tags without joining words', () {
      final normalised = ContentNormaliser.normalise(
        const Bubble(
          id: 'assistant',
          role: MessageRole.assistant,
          text:
              'The electric<think>\n\n</think>\n\n hum continued and her body<think>\n\n</think>\n\n glowed.',
          reasoning: '',
        ),
      );

      expect(
        normalised.text,
        'The electric hum continued and her body glowed.',
      );
      expect(normalised.reasoning, isEmpty);
    });

    test('moves non-empty think tags to reasoning', () {
      final normalised = ContentNormaliser.normalise(
        const Bubble(
          id: 'assistant',
          role: MessageRole.assistant,
          text: 'Visible<think>hidden reasoning</think> text.',
          reasoning: '',
        ),
      );

      expect(normalised.text, 'Visible text.');
      expect(normalised.reasoning, 'hidden reasoning');
    });

    test('extracts Qwen-style tool calls from reasoning', () {
      final normalised = ContentNormaliser.normalise(
        const Bubble(
          id: 'assistant',
          role: MessageRole.assistant,
          text: '',
          reasoning: '''
I need to inspect the file.
<tool_call>
<function=read_file>
<parameter=path>
README.md
</parameter>
</function>
</tool_call>
''',
        ),
      );

      expect(normalised.text, isEmpty);
      expect(normalised.reasoning, 'I need to inspect the file.');
      expect(normalised.tools.length, 1);
      expect(normalised.tools[0]?.name, 'read_file');
      expect(jsonDecode(normalised.tools[0]!.arguments!), {
        'path': 'README.md',
      });
    });

    test('extracts JSON tool calls from visible content', () {
      final normalised = ContentNormaliser.normalise(
        const Bubble(
          id: 'assistant',
          role: MessageRole.assistant,
          text: '''
<tool_call>
{"name":"calculator","arguments":{"paramA":2,"paramB":3,"operator":"+"}}
</tool_call>
''',
          reasoning: '',
        ),
      );

      expect(normalised.text, isEmpty);
      expect(normalised.tools.length, 1);
      expect(normalised.tools[0]?.name, 'calculator');
      expect(jsonDecode(normalised.tools[0]!.arguments!), {
        'paramA': 2,
        'paramB': 3,
        'operator': '+',
      });
    });

    test('leaves unrecognised tool call blocks visible', () {
      const raw = '<tool_call>not a structured call</tool_call>';
      final normalised = ContentNormaliser.normalise(
        const Bubble(
          id: 'assistant',
          role: MessageRole.assistant,
          text: raw,
          reasoning: '',
        ),
      );

      expect(normalised.text, raw);
      expect(normalised.tools, isEmpty);
    });
  });
}
