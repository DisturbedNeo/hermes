import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/helpers/chat/compaction_manager.dart';
import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/core/models/compaction_settings.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/chat/message_store.dart';

void main() {
  group('CompactionManager', () {
    late HttpServer server;
    late StreamSubscription<HttpRequest> serverSub;
    late ChatClient client;
    late List<Map<String, dynamic>> requests;

    setUp(() async {
      requests = [];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      serverSub = server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        requests.add(jsonDecode(body) as Map<String, dynamic>);

        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode({
                    'schema_version': 1,
                    'task': 'Continue the long task.',
                    'current_state': 'Ready for the next user request.',
                    'artifacts': ['Old context was summarised.'],
                  }),
                },
              },
            ],
          }),
        );
        await request.response.close();
      });

      client = ChatClient(
        baseUrl: 'http://${server.address.host}:${server.port}',
        model: 'test-model',
      );
    });

    tearDown(() async {
      client.dispose();
      await serverSub.cancel();
      await server.close(force: true);
    });

    test(
      'inserts summary memory and marks only old candidates covered',
      () async {
        final store = MessageStore();
        final oldText = List.filled(240, 'old context').join(' ');
        store.setMessages([
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
          Bubble(
            id: 'old-assistant-1',
            role: MessageRole.assistant,
            text: oldText,
            reasoning: '',
          ),
          Bubble(
            id: 'old-user-1',
            role: MessageRole.user,
            text: oldText,
            reasoning: '',
          ),
          Bubble(
            id: 'old-assistant-2',
            role: MessageRole.assistant,
            text: oldText,
            reasoning: '',
          ),
          Bubble(
            id: 'old-user-2',
            role: MessageRole.user,
            text: oldText,
            reasoning: '',
          ),
          const Bubble(
            id: 'recent-assistant',
            role: MessageRole.assistant,
            text: 'Recent assistant state',
            reasoning: '',
          ),
          const Bubble(
            id: 'recent-user',
            role: MessageRole.user,
            text: 'Newest request',
            reasoning: '',
          ),
        ]);

        final manager = CompactionManager(
          settings: const CompactionSettings(
            triggerThreshold: 0.01,
            hardLimitThreshold: 0.95,
            recentWindowUnits: 2,
          ),
          client: client,
        );

        expect(
          manager.shouldCompact(
            messages: store.messages,
            contextLimit: 4096,
            extraParams: const {},
          ),
          isTrue,
        );

        final statuses = <String>[];
        final result = await manager.compactIfNeeded(
          messageStore: store,
          contextLimit: 4096,
          extraParams: const {},
          onStatusChanged: statuses.add,
        );

        expect(result.compacted, isTrue);
        expect(result.messagesCovered, 4);

        final summaries = store.messages.where(
          (message) => message.isSummaryMemory,
        );
        expect(summaries, hasLength(1));
        final summary = summaries.single;
        expect(summary.role, MessageRole.user);
        expect(summary.text, contains('Context Summary'));

        expect(store.isCoveredBySummary('old-assistant-1'), isTrue);
        expect(store.isCoveredBySummary('old-user-2'), isTrue);
        expect(store.isCoveredBySummary('recent-assistant'), isFalse);
        expect(store.isCoveredBySummary('recent-user'), isFalse);

        expect(requests, isNotEmpty);
        expect(requests.first['stream'], isFalse);
        expect(requests.first.containsKey('tools'), isFalse);
        final requestMessages = requests.first['messages'] as List<dynamic>;
        expect(requestMessages.map((m) => m['role']).toList(), [
          'system',
          'user',
        ]);
        expect(requestMessages.last['content'], contains('System prompt'));
        expect(requestMessages.last['content'], contains('Original task'));
        expect(requestMessages.last['content'], contains('old-assistant-1'));
      },
    );

    test(
      'summary request still has a user query for assistant-only chunks',
      () async {
        final store = MessageStore();
        final oldText = List.filled(320, 'assistant-only context').join(' ');
        store.setMessages([
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
          Bubble(
            id: 'old-assistant-1',
            role: MessageRole.assistant,
            text: oldText,
            reasoning: '',
          ),
          Bubble(
            id: 'old-assistant-2',
            role: MessageRole.assistant,
            text: oldText,
            reasoning: '',
          ),
          const Bubble(
            id: 'recent-assistant',
            role: MessageRole.assistant,
            text: 'Recent assistant state',
            reasoning: '',
          ),
        ]);

        final manager = CompactionManager(
          settings: const CompactionSettings(
            triggerThreshold: 0.01,
            hardLimitThreshold: 0.95,
            recentWindowUnits: 1,
          ),
          client: client,
        );

        final result = await manager.compactIfNeeded(
          messageStore: store,
          contextLimit: 4096,
          extraParams: const {},
          onStatusChanged: (_) {},
        );

        expect(result.compacted, isTrue);
        expect(store.isCoveredBySummary('old-assistant-1'), isTrue);
        expect(store.isCoveredBySummary('intent'), isFalse);

        for (final request in requests) {
          final requestMessages = request['messages'] as List<dynamic>;
          expect(requestMessages.map((m) => m['role']).toList(), [
            'system',
            'user',
          ]);
          expect(requestMessages.last['content'], contains('Original task'));
        }

        final requestText = requests
            .map((request) => request['messages'] as List<dynamic>)
            .map((messages) => messages.last['content'] as String)
            .join('\n');
        expect(requestText, contains('old-assistant-1'));
        expect(requestText, contains('old-assistant-2'));
      },
    );

    test(
      'does not compact when any active assistant tool call is unresolved',
      () {
        final oldText = List.filled(240, 'old context').join(' ');
        final messages = [
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
          Bubble(
            id: 'old-assistant-with-tool',
            role: MessageRole.assistant,
            text: oldText,
            reasoning: '',
            tools: const {
              0: BubbleToolCall(
                name: 'read_file',
                arguments: '{"path":"README.md"}',
              ),
            },
          ),
          Bubble(
            id: 'old-user',
            role: MessageRole.user,
            text: oldText,
            reasoning: '',
          ),
          const Bubble(
            id: 'recent-assistant',
            role: MessageRole.assistant,
            text: 'Recent assistant state',
            reasoning: '',
          ),
        ];

        final manager = CompactionManager(
          settings: const CompactionSettings(
            triggerThreshold: 0.01,
            hardLimitThreshold: 0.95,
            recentWindowUnits: 1,
          ),
          client: client,
        );

        expect(
          manager.shouldCompact(
            messages: messages,
            contextLimit: 4096,
            extraParams: const {},
          ),
          isFalse,
        );
      },
    );
  });
}
