import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/services/chat/chat_client.dart';

void main() {
  group('ChatClient stream parsing', () {
    test('parses non-streaming tool calls', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

      final subscription = server.listen((request) async {
        expect(request.uri.path, '/v1/chat/completions');
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write(
            jsonEncode({
              'choices': [
                {
                  'message': {
                    'content': 'I will read it.',
                    'tool_calls': [
                      {
                        'id': 'call_1',
                        'type': 'function',
                        'function': {
                          'name': 'read_file',
                          'arguments': {'path': 'README.md'},
                        },
                      },
                    ],
                  },
                },
              ],
            }),
          );
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

      final completion = await client.completeChat(
        messages: const [ChatMessage(role: 'user', content: 'Read README')],
      );

      expect(completion.content, 'I will read it.');
      expect(completion.toolCalls.single.id, 'call_1');
      expect(completion.toolCalls.single.name, 'read_file');
      expect(completion.toolCalls.single.arguments, '{"path":"README.md"}');
    });

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

    test('reconstructs streamed completions while forwarding tokens', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

      final subscription = server.listen((request) async {
        expect(request.uri.path, '/v1/chat/completions');
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType('text', 'event-stream');

        final first = {
          'choices': [
            {
              'delta': {'reasoning': 'think ', 'content': 'hello '},
            },
          ],
        };
        final second = {
          'choices': [
            {
              'delta': {
                'content': 'world',
                'tool_calls': [
                  {
                    'index': 0,
                    'id': 'call_0',
                    'function': {'name': 'read_file', 'arguments': '{"path":'},
                  },
                ],
              },
            },
          ],
        };
        final third = {
          'choices': [
            {
              'delta': {
                'tool_calls': [
                  {
                    'index': 0,
                    'function': {'arguments': '"README.md"}'},
                  },
                ],
              },
            },
          ],
        };

        request.response
          ..write('data: ${jsonEncode(first)}\n\n')
          ..write('data: ${jsonEncode(second)}\n\n')
          ..write('data: ${jsonEncode(third)}\n\n')
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

      final forwarded = <String>[];
      final completion = await client.completeChatStreamed(
        messages: const [ChatMessage(role: 'user', content: 'Hello')],
        onToken: (token) {
          forwarded.add(token.content ?? token.reasoning ?? '');
        },
      );

      expect(forwarded.where((text) => text.isNotEmpty), [
        'think ',
        'hello ',
        'world',
      ]);
      expect(completion.reasoning, 'think ');
      expect(completion.content, 'hello world');
      expect(completion.toolCalls.single.name, 'read_file');
      expect(completion.toolCalls.single.arguments, '{"path":"README.md"}');
    });
  });
}
