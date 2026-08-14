import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/models/chat_token.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/cancellation_token.dart';
import 'package:http/http.dart' as http;

void main() {
  group('ChatClient stream parsing', () {
    test(
      'accepts finish_reason and tokenless metadata as termination',
      () async {
        final client = ChatClient(
          baseUrl: 'http://localhost',
          model: 'test-model',
          clientFactory: () => _ScriptedClient(
            (_) async => _sseResponse(
              'data: ${jsonEncode({
                'choices': [
                  {
                    'delta': {'role': 'assistant'},
                    'finish_reason': null,
                  },
                ],
              })}\n\n'
              'data: ${jsonEncode({
                'choices': <Object?>[],
                'usage': {'completion_tokens': 1},
              })}\n\n'
              'data: ${jsonEncode({
                'choices': [
                  {'delta': <String, Object?>{}, 'finish_reason': 'stop'},
                ],
              })}\n\n',
            ),
          ),
        );

        expect(
          await client.streamMessage(messages: const []).toList(),
          isEmpty,
        );
      },
    );

    test('rejects malformed and unterminated event streams', () async {
      final malformed = ChatClient(
        baseUrl: 'http://localhost',
        model: 'test-model',
        clientFactory: () =>
            _ScriptedClient((_) async => _sseResponse('data: {not-json}\n\n')),
      );
      await expectLater(
        malformed.streamMessage(messages: const []).toList(),
        throwsA(isA<ChatProtocolException>()),
      );

      final unterminated = ChatClient(
        baseUrl: 'http://localhost',
        model: 'test-model',
        clientFactory: () => _ScriptedClient(
          (_) async => _sseResponse(
            'data: ${jsonEncode({
              'choices': [
                {
                  'delta': {'content': 'partial'},
                },
              ],
            })}\n\n',
          ),
        ),
      );
      final tokens = <ChatToken>[];
      final completed = unterminated
          .streamMessage(messages: const [])
          .listen(tokens.add)
          .asFuture<void>();

      await expectLater(completed, throwsA(isA<ChatProtocolException>()));
      expect(tokens.single.content, 'partial');
    });

    test('rejects malformed choice and error structures', () async {
      for (final payload in [
        {'choices': 'invalid'},
        {
          'choices': [42],
        },
        {'error': 'invalid'},
        {'unexpected': true},
      ]) {
        final client = ChatClient(
          baseUrl: 'http://localhost',
          model: 'test-model',
          clientFactory: () => _ScriptedClient(
            (_) async => _sseResponse('data: ${jsonEncode(payload)}\n\n'),
          ),
        );
        await expectLater(
          client.streamMessage(messages: const []).toList(),
          throwsA(isA<ChatProtocolException>()),
        );
      }
    });

    test('parses non-streaming tool calls', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

      final subscription = server.listen((request) async {
        expect(request.uri.path, '/v1/chat/completions');
        expect(request.headers.value(HttpHeaders.connectionHeader), 'close');
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
        expect(request.headers.value(HttpHeaders.connectionHeader), 'close');
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
        expect(request.headers.value(HttpHeaders.connectionHeader), 'close');
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

  group('ChatClient transport recovery', () {
    test('uses one-shot clients and closes every request', () async {
      final clients = <_ScriptedClient>[];
      final client = ChatClient(
        baseUrl: 'http://localhost',
        model: 'test-model',
        clientFactory: () {
          final scripted = _ScriptedClient((request) async {
            expect(request.persistentConnection, isFalse);
            expect(request.headers['Connection'], 'close');
            return _jsonResponse('ok');
          });
          clients.add(scripted);
          return scripted;
        },
      );

      await client.completeChat(
        messages: const [ChatMessage(role: 'user', content: 'one')],
      );
      await client.completeChat(
        messages: const [ChatMessage(role: 'user', content: 'two')],
      );

      expect(clients, hasLength(2));
      expect(clients.every((item) => item.closed), isTrue);
    });

    test('retries one socket failure on a fresh client', () async {
      final events = <ChatTransportEvent>[];
      final clients = <_ScriptedClient>[];
      final client = ChatClient(
        baseUrl: 'http://localhost',
        model: 'test-model',
        onTransportEvent: events.add,
        clientFactory: () {
          final index = clients.length;
          final scripted = _ScriptedClient((request) async {
            if (index == 0) throw _brokenPipe();
            return _jsonResponse('recovered');
          });
          clients.add(scripted);
          return scripted;
        },
      );

      final completion = await client.completeChat(
        messages: const [ChatMessage(role: 'user', content: 'retry')],
      );

      expect(completion.content, 'recovered');
      expect(clients, hasLength(2));
      expect(clients.every((item) => item.closed), isTrue);
      expect(events.single.kind, ChatTransportFailureKind.brokenPipe);
      expect(events.single.willRetry, isTrue);
    });

    test('exposes a typed failure after the second socket error', () async {
      final events = <ChatTransportEvent>[];
      final client = ChatClient(
        baseUrl: 'http://localhost',
        model: 'test-model',
        onTransportEvent: events.add,
        clientFactory: () => _ScriptedClient((_) async => throw _brokenPipe()),
      );

      await expectLater(
        client.completeChat(
          messages: const [ChatMessage(role: 'user', content: 'fail')],
        ),
        throwsA(
          isA<ChatTransportException>()
              .having((error) => error.attempts, 'attempts', 2)
              .having((error) => error.outputStarted, 'outputStarted', isFalse),
        ),
      );
      expect(events.map((event) => event.willRetry), [true, false]);
    });

    test('does not retry a stream failure after the first token', () async {
      var clientCount = 0;
      final events = <ChatTransportEvent>[];
      final client = ChatClient(
        baseUrl: 'http://localhost',
        model: 'test-model',
        onTransportEvent: events.add,
        clientFactory: () {
          clientCount++;
          return _ScriptedClient((_) async {
            final controller = StreamController<List<int>>();
            scheduleMicrotask(() {
              controller.add(
                utf8.encode(
                  'data: ${jsonEncode({
                    'choices': [
                      {
                        'delta': {'content': 'started'},
                      },
                    ],
                  })}\n\n',
                ),
              );
              controller.addError(_brokenPipe());
              controller.close();
            });
            return http.StreamedResponse(
              controller.stream,
              HttpStatus.ok,
              headers: {'content-type': 'text/event-stream'},
            );
          });
        },
      );
      final tokens = <ChatToken>[];

      final done = client
          .streamMessage(
            messages: const [ChatMessage(role: 'user', content: 'stream')],
          )
          .listen(tokens.add)
          .asFuture<void>();

      await expectLater(
        done,
        throwsA(
          isA<ChatTransportException>().having(
            (error) => error.outputStarted,
            'outputStarted',
            isTrue,
          ),
        ),
      );
      expect(tokens.single.content, 'started');
      expect(clientCount, 1);
      expect(events.single.willRetry, isFalse);
    });

    test(
      'retries a stream failure before output without duplicating tokens',
      () async {
        var clientCount = 0;
        final client = ChatClient(
          baseUrl: 'http://localhost',
          model: 'test-model',
          clientFactory: () {
            final index = clientCount++;
            return _ScriptedClient((_) async {
              if (index == 0) throw _brokenPipe();
              return http.StreamedResponse(
                Stream.value(
                  utf8.encode(
                    'data: ${jsonEncode({
                      'choices': [
                        {
                          'delta': {'content': 'recovered'},
                        },
                      ],
                    })}\n\ndata: [DONE]\n\n',
                  ),
                ),
                HttpStatus.ok,
                headers: {'content-type': 'text/event-stream'},
              );
            });
          },
        );

        final tokens = await client
            .streamMessage(
              messages: const [ChatMessage(role: 'user', content: 'stream')],
            )
            .toList();

        expect(clientCount, 2);
        expect(tokens.map((token) => token.content).whereType<String>(), [
          'recovered',
        ]);
      },
    );

    test('keeps concurrent request lifetimes isolated', () async {
      final responseCompleters = <Completer<http.StreamedResponse>>[];
      final clients = <_ScriptedClient>[];
      final client = ChatClient(
        baseUrl: 'http://localhost',
        model: 'test-model',
        clientFactory: () {
          final response = Completer<http.StreamedResponse>();
          responseCompleters.add(response);
          final scripted = _ScriptedClient((_) => response.future);
          clients.add(scripted);
          return scripted;
        },
      );

      final first = client.completeChat(
        messages: const [ChatMessage(role: 'user', content: 'first')],
      );
      final second = client.completeChat(
        messages: const [ChatMessage(role: 'user', content: 'second')],
      );
      expect(clients, hasLength(2));

      responseCompleters.first.complete(_jsonResponse('first'));
      expect((await first).content, 'first');
      expect(clients.first.closed, isTrue);
      expect(clients.last.closed, isFalse);

      responseCompleters.last.complete(_jsonResponse('second'));
      expect((await second).content, 'second');
      expect(clients.last.closed, isTrue);
    });

    test('does not retry HTTP failures', () async {
      var clientCount = 0;
      final client = ChatClient(
        baseUrl: 'http://localhost',
        model: 'test-model',
        clientFactory: () {
          clientCount++;
          return _ScriptedClient(
            (_) async => http.StreamedResponse(
              Stream.value(utf8.encode('unavailable')),
              HttpStatus.serviceUnavailable,
            ),
          );
        },
      );

      await expectLater(
        client.completeChat(
          messages: const [ChatMessage(role: 'user', content: 'fail')],
        ),
        throwsA(isA<HttpException>()),
      );
      expect(clientCount, 1);
    });

    test('does not retry cancellation or malformed responses', () async {
      var cancellationClients = 0;
      final cancelled = ChatClient(
        baseUrl: 'http://localhost',
        model: 'test-model',
        clientFactory: () {
          cancellationClients++;
          return _ScriptedClient(
            (request) async => throw http.RequestAbortedException(request.url),
          );
        },
      );
      await expectLater(
        cancelled.completeChat(
          messages: const [ChatMessage(role: 'user', content: 'cancel')],
        ),
        throwsA(isA<http.RequestAbortedException>()),
      );
      expect(cancellationClients, 1);

      var malformedClients = 0;
      final malformed = ChatClient(
        baseUrl: 'http://localhost',
        model: 'test-model',
        clientFactory: () {
          malformedClients++;
          return _ScriptedClient(
            (_) async => http.StreamedResponse(
              Stream.value(utf8.encode('{not-json')),
              HttpStatus.ok,
            ),
          );
        },
      );
      await expectLater(
        malformed.completeChat(
          messages: const [ChatMessage(role: 'user', content: 'malformed')],
        ),
        throwsA(isA<FormatException>()),
      );
      expect(malformedClients, 1);
    });

    test(
      'remains reliable across llama-style idle windows and concurrency',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0)
          ..idleTimeout = const Duration(seconds: 5);
        final remotePorts = <int>{};
        final subscription = server.listen((request) async {
          remotePorts.add(request.connectionInfo!.remotePort);
          expect(request.headers.value(HttpHeaders.connectionHeader), 'close');
          request.response
            ..statusCode = HttpStatus.ok
            ..headers.contentType = ContentType.json
            ..write(
              jsonEncode({
                'choices': [
                  {
                    'message': {'content': 'ok'},
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

        await client.completeChat(
          messages: const [ChatMessage(role: 'user', content: 'before idle')],
        );
        await Future<void>.delayed(const Duration(milliseconds: 5100));
        await client.completeChat(
          messages: const [ChatMessage(role: 'user', content: 'after idle')],
        );
        await Future.wait([
          client.completeChat(
            messages: const [ChatMessage(role: 'user', content: 'parallel 1')],
          ),
          client.completeChat(
            messages: const [ChatMessage(role: 'user', content: 'parallel 2')],
          ),
        ]);

        expect(remotePorts, hasLength(4));
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test(
      'counts the exact input token request with completion parameters',
      () async {
        Map<String, dynamic>? requestBody;
        final client = ChatClient(
          baseUrl: 'http://localhost',
          model: 'test-model',
          clientFactory: () => _ScriptedClient((request) async {
            requestBody = jsonDecode(await request.finalize().bytesToString());
            expect(request.url.path, '/v1/chat/completions/input_tokens');
            return http.StreamedResponse(
              Stream.value(utf8.encode('{"input_tokens":321}')),
              HttpStatus.ok,
            );
          }),
        );

        final count = await client.countInputTokens(
          messages: const [ChatMessage(role: 'user', content: 'hello')],
          extraParams: const {'tools': [], 'add_generation_prompt': true},
        );

        expect(count, 321);
        expect(requestBody?['model'], 'test-model');
        expect(requestBody?['messages'], hasLength(1));
        expect(requestBody?['add_generation_prompt'], isTrue);
      },
    );

    test('caches definitive token-count endpoint incompatibility', () async {
      var requests = 0;
      final client = ChatClient(
        baseUrl: 'http://localhost',
        model: 'test-model',
        clientFactory: () => _ScriptedClient((_) async {
          requests++;
          return http.StreamedResponse(
            const Stream.empty(),
            HttpStatus.notFound,
          );
        }),
      );

      expect(await client.countInputTokens(messages: const []), isNull);
      expect(await client.countInputTokens(messages: const []), isNull);
      expect(requests, 1);
    });

    test('times out a model request after an inactivity window', () async {
      final client = ChatClient(
        baseUrl: 'http://localhost',
        model: 'test-model',
        inactivityTimeout: const Duration(milliseconds: 30),
        clientFactory: () =>
            _ScriptedClient((_) => Completer<http.StreamedResponse>().future),
      );

      await expectLater(
        client.completeChat(
          messages: const [ChatMessage(role: 'user', content: 'wait')],
        ),
        throwsA(isA<ChatRequestTimeoutException>()),
      );
    });

    test(
      'resets the inactivity timeout whenever response data arrives',
      () async {
        final controller = StreamController<List<int>>();
        final timer = Timer.periodic(const Duration(milliseconds: 20), (timer) {
          switch (timer.tick) {
            case 1:
              controller.add(utf8.encode('{"choices":['));
            case 2:
              controller.add(utf8.encode('{"message":{"content":"ok"}}'));
            default:
              controller.add(utf8.encode(']}'));
              unawaited(controller.close());
              timer.cancel();
          }
        });
        addTearDown(() {
          timer.cancel();
          return controller.close();
        });
        final client = ChatClient(
          baseUrl: 'http://localhost',
          model: 'test-model',
          inactivityTimeout: const Duration(milliseconds: 35),
          clientFactory: () => _ScriptedClient(
            (_) async =>
                http.StreamedResponse(controller.stream, HttpStatus.ok),
          ),
        );

        final completion = await client.completeChat(
          messages: const [ChatMessage(role: 'user', content: 'stream slowly')],
        );

        expect(completion.content, 'ok');
      },
    );

    test('falls back when token counting fails transiently', () async {
      var requests = 0;
      final client = ChatClient(
        baseUrl: 'http://localhost',
        model: 'test-model',
        clientFactory: () => _ScriptedClient((_) async {
          requests++;
          return http.StreamedResponse(
            const Stream.empty(),
            HttpStatus.serviceUnavailable,
          );
        }),
      );

      expect(await client.countInputTokens(messages: const []), isNull);
      expect(await client.countInputTokens(messages: const []), isNull);
      expect(requests, 2);
    });

    test(
      'cancelling one request leaves a concurrent request running',
      () async {
        final pending = Completer<http.StreamedResponse>();
        var clientIndex = 0;
        final clients = <_ScriptedClient>[];
        final client = ChatClient(
          baseUrl: 'http://localhost',
          model: 'test-model',
          clientFactory: () {
            final index = clientIndex++;
            late final _ScriptedClient scripted;
            scripted = _ScriptedClient(
              (_) => index == 0
                  ? pending.future
                  : Future.value(_jsonResponse('second')),
              onClose: () {
                if (index == 0 && !pending.isCompleted) {
                  pending.completeError(
                    http.RequestAbortedException(Uri.parse('http://localhost')),
                  );
                }
              },
            );
            clients.add(scripted);
            return scripted;
          },
        );
        final token = CancellationToken();

        final first = client.completeChat(
          messages: const [ChatMessage(role: 'user', content: 'first')],
          cancellationToken: token,
        );
        final second = client.completeChat(
          messages: const [ChatMessage(role: 'user', content: 'second')],
        );
        final firstExpectation = expectLater(
          first,
          throwsA(isA<OperationCancelledException>()),
        );
        await token.cancel();

        await firstExpectation;
        expect((await second).content, 'second');
        expect(clients.first.closed, isTrue);
        expect(clients.last.closed, isTrue);
      },
    );
  });
}

http.StreamedResponse _jsonResponse(String content) {
  return http.StreamedResponse(
    Stream.value(
      utf8.encode(
        jsonEncode({
          'choices': [
            {
              'message': {'content': content},
            },
          ],
        }),
      ),
    ),
    HttpStatus.ok,
    headers: {'content-type': 'application/json'},
  );
}

http.StreamedResponse _sseResponse(String body) {
  return http.StreamedResponse(
    Stream.value(utf8.encode(body)),
    HttpStatus.ok,
    headers: {'content-type': 'text/event-stream'},
  );
}

SocketException _brokenPipe() =>
    const SocketException('Write failed', osError: OSError('Broken pipe', 32));

class _ScriptedClient extends http.BaseClient {
  final Future<http.StreamedResponse> Function(http.BaseRequest request)
  _handler;
  bool closed = false;
  final void Function()? onClose;

  _ScriptedClient(this._handler, {this.onClose});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _handler(request);
  }

  @override
  void close() {
    closed = true;
    onClose?.call();
  }
}
