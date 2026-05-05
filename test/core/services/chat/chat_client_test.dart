import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/services/chat/chat_client.dart';

void main() {
  group('ChatClient stream parsing', () {
    test('emits every reasoning, content, and tool token in a delta', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

      final subscription = server.listen((request) async {
        expect(request.uri.path, '/v1/chat/completions');
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType('text', 'event-stream');

        final event = {
          'choices': [
            {
              'delta': {
                'reasoning': 'hidden',
                'content': 'visible',
                'tool_calls': [
                  {
                    'index': 0,
                    'id': 'call_0',
                    'function': {
                      'name': 'read_file',
                      'arguments': {'path': 'README.md'},
                    },
                  },
                  {
                    'index': 1,
                    'function': {
                      'name': 'calculator',
                      'arguments': '{"paramA":2,"paramB":3,"operator":"+"}',
                    },
                  },
                ],
              },
            },
          ],
        };

        request.response
          ..write('data: ${jsonEncode(event)}\n\n')
          ..write('data: [DONE]\n\n');
        await request.response.close();
      });

      addTearDown(() async {
        await subscription.cancel();
        await server.close(force: true);
      });

      final client = ChatClient(
        baseUrl: 'http://127.0.0.1:${server.port}',
        model: 'test-model',
      );
      addTearDown(client.dispose);

      final tokens = await client
          .streamMessage(
            messages: const [ChatMessage(role: 'user', content: 'Hello')],
          )
          .toList();

      expect(tokens.length, 4);
      expect(tokens[0].reasoning, 'hidden');
      expect(tokens[1].content, 'visible');
      expect(tokens[2].tool?.name, 'read_file');
      expect(tokens[2].tool?.argumentsChunk, '{"path":"README.md"}');
      expect(tokens[3].tool?.name, 'calculator');
      expect(
        tokens[3].tool?.argumentsChunk,
        '{"paramA":2,"paramB":3,"operator":"+"}',
      );
    });
  });
}
