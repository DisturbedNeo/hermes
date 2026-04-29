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
  });
}
