import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/helpers/chat/buffered_token_writer.dart';
import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/core/models/chat_token.dart';
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

  group('MessageStore display revision', () {
    test('does not change for message content updates', () {
      final store = MessageStore();
      store.setMessages([
        const Bubble(
          id: 'assistant',
          role: MessageRole.assistant,
          text: 'Hel',
          reasoning: '',
        ),
      ]);
      final revision = store.displayRevision;

      store.upsert(
        const Bubble(
          id: 'assistant',
          role: MessageRole.assistant,
          text: 'Hello',
          reasoning: '',
        ),
      );

      expect(store.displayRevision, revision);
      expect(store.messageById('assistant')?.text, 'Hello');
    });

    test('changes for display structure updates', () {
      final store = MessageStore();
      store.setMessages([
        const Bubble(
          id: 'user',
          role: MessageRole.user,
          text: 'Hello',
          reasoning: '',
        ),
      ]);
      final revision = store.displayRevision;

      store.upsert(
        const Bubble(
          id: 'assistant',
          role: MessageRole.assistant,
          text: 'Hi',
          reasoning: '',
        ),
      );

      expect(store.displayRevision, greaterThan(revision));
    });
  });

  group('BufferedTokenWriter', () {
    test('publishes a large token burst with one notification', () {
      final store = MessageStore();
      store.setMessages([
        const Bubble(
          id: 'assistant',
          role: MessageRole.assistant,
          text: '',
          reasoning: '',
        ),
      ], currentId: 'assistant');
      var notifications = 0;
      store.addListener(() => notifications++);
      final writer = BufferedTokenWriter(messageStore: store);

      for (var i = 0; i < 1000; i++) {
        writer.add(ChatToken(content: 'x'));
      }
      writer.add(ChatToken(reasoning: 'thought'));
      writer.flush();

      expect(store.currentMessage?.text, List.filled(1000, 'x').join());
      expect(store.currentMessage?.reasoning, 'thought');
      expect(notifications, 1);
      writer.dispose();
    });

    test('preserves tool delta order and flushes on disposal', () {
      final store = MessageStore();
      store.setMessages([
        const Bubble(
          id: 'assistant',
          role: MessageRole.assistant,
          text: '',
          reasoning: '',
        ),
      ], currentId: 'assistant');
      final writer = BufferedTokenWriter(messageStore: store)
        ..add(
          ChatToken(
            tool: ToolCallDelta(
              index: 0,
              id: 'call_1',
              name: 'read_file',
              argumentsChunk: '{"path":',
            ),
          ),
        )
        ..add(
          ChatToken(
            tool: ToolCallDelta(index: 0, argumentsChunk: '"README.md"}'),
          ),
        );

      writer.dispose();

      expect(store.currentMessage?.tools[0]?.name, 'read_file');
      expect(store.currentMessage?.tools[0]?.arguments, '{"path":"README.md"}');
    });
  });
}
