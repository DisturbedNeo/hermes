import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/core/services/chat/message_store.dart';

void main() {
  group('MessageStore compaction metadata', () {
    test('marks messages as covered by a summary', () {
      final store = MessageStore();
      store.setMessages([
        const Bubble(
          id: 'summary',
          role: MessageRole.system,
          text: 'Summary',
          reasoning: '',
          isSummaryMemory: true,
        ),
        const Bubble(
          id: 'old',
          role: MessageRole.assistant,
          text: 'Old answer',
          reasoning: '',
        ),
      ]);

      store.markCoveredBySummary(
        messageIds: const ['old'],
        summaryId: 'summary',
      );

      expect(store.isCoveredBySummary('old'), isTrue);
      expect(store.summaryIdFor('old'), 'summary');
      expect(store.coveredMessageIdsForSummary('summary'), ['old']);
    });

    test('removing a summary clears coverage metadata', () {
      final store = MessageStore();
      store.setMessages([
        const Bubble(
          id: 'summary',
          role: MessageRole.system,
          text: 'Summary',
          reasoning: '',
          isSummaryMemory: true,
        ),
        const Bubble(
          id: 'old',
          role: MessageRole.assistant,
          text: 'Old answer',
          reasoning: '',
          omittedFromModelPayload: true,
          summaryId: 'summary',
        ),
      ]);

      store.removeById('summary');

      expect(store.messages.map((message) => message.id).toList(), ['old']);
      expect(store.isCoveredBySummary('old'), isFalse);
      expect(store.summaryIdFor('old'), isNull);
    });

    test('editing a covered message invalidates the stale summary', () {
      final store = MessageStore();
      store.setMessages([
        const Bubble(
          id: 'summary',
          role: MessageRole.system,
          text: 'Summary',
          reasoning: '',
          isSummaryMemory: true,
        ),
        const Bubble(
          id: 'old',
          role: MessageRole.assistant,
          text: 'Old answer',
          reasoning: '',
          omittedFromModelPayload: true,
          summaryId: 'summary',
        ),
      ]);

      store.upsert(
        const Bubble(
          id: 'old',
          role: MessageRole.assistant,
          text: 'Edited answer',
          reasoning: '',
          omittedFromModelPayload: true,
          summaryId: 'summary',
        ),
      );

      expect(store.messages.map((message) => message.id).toList(), ['old']);
      expect(store.messages.single.text, 'Edited answer');
      expect(store.messages.single.omittedFromModelPayload, isFalse);
      expect(store.messages.single.summaryId, isNull);
    });

    test('clears stale coverage when loading without a matching summary', () {
      final store = MessageStore();
      store.setMessages([
        const Bubble(
          id: 'old',
          role: MessageRole.assistant,
          text: 'Old answer',
          reasoning: '',
          omittedFromModelPayload: true,
          summaryId: 'missing',
        ),
      ]);

      expect(store.messages.single.omittedFromModelPayload, isFalse);
      expect(store.messages.single.summaryId, isNull);
    });
  });
}
