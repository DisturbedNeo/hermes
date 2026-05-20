import 'dart:convert';
import 'dart:io';

import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/models/chat_token.dart';
import 'package:http/http.dart' as http;

class ChatClient {
  final String _baseUrl;
  final String _model;
  final http.Client _client = http.Client();

  ChatClient({required String baseUrl, required String model, String? apiKey})
    : _model = model,
      _baseUrl = baseUrl;

  bool get supportsStreamingCancellation => runtimeType == ChatClient;

  void dispose() {
    _client.close();
  }

  Future<String> completeMessage({
    required List<ChatMessage> messages,
    Map<String, dynamic>? extraParams,
  }) async {
    final completion = await completeChat(
      messages: messages,
      extraParams: extraParams,
    );
    if (completion.content.isNotEmpty) return completion.content;
    return completion.reasoning;
  }

  Future<ChatCompletionResponse> completeChat({
    required List<ChatMessage> messages,
    Map<String, dynamic>? extraParams,
  }) async {
    final body = {
      'model': _model,
      'messages': messages.map((m) => m.toJson()).toList(),
      'stream': false,
      if (extraParams != null) ...extraParams,
    };

    final chatUri = Uri.parse('$_baseUrl/v1/chat/completions');
    final response = await _client.post(
      chatUri,
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwHttpException(response.statusCode, response.body, chatUri);
    }

    return _completionFromBody(response.body, chatUri);
  }

  Future<ChatCompletionResponse> completeChatStreamed({
    required List<ChatMessage> messages,
    Map<String, dynamic>? extraParams,
    void Function(ChatToken token)? onToken,
  }) async {
    if (runtimeType != ChatClient) {
      final completion = await completeChat(
        messages: messages,
        extraParams: extraParams,
      );
      _emitCompletionTokens(completion, onToken);
      return completion;
    }

    final body = {
      'model': _model,
      'messages': messages.map((m) => m.toJson()).toList(),
      'stream': true,
      if (extraParams != null) ...extraParams,
    };

    final chatUri = Uri.parse('$_baseUrl/v1/chat/completions');
    final req = http.Request('POST', chatUri)
      ..headers.addAll(const {
        'Accept': 'text/event-stream',
        'Content-Type': 'application/json',
      })
      ..body = jsonEncode(body);

    final streamed = await _client.send(req);

    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      final responseBody = await streamed.stream.bytesToString();
      _throwHttpException(streamed.statusCode, responseBody, chatUri);
    }

    final contentType = streamed.headers['content-type'] ?? '';
    if (!contentType.toLowerCase().contains('text/event-stream')) {
      final responseBody = await streamed.stream.bytesToString();
      final completion = _completionFromBody(responseBody, chatUri);
      _emitCompletionTokens(completion, onToken);
      return completion;
    }

    final content = StringBuffer();
    final reasoning = StringBuffer();
    final toolCalls = <int, _StreamingToolCall>{};

    void record(ChatToken token) {
      onToken?.call(token);
      final contentToken = token.content;
      if (contentToken != null) content.write(contentToken);
      final reasoningToken = token.reasoning;
      if (reasoningToken != null) reasoning.write(reasoningToken);

      final tool = token.tool;
      if (tool != null) {
        final call = toolCalls.putIfAbsent(
          tool.index,
          () => _StreamingToolCall(),
        );
        if (tool.id != null) call.id = tool.id;
        if (tool.name != null) call.name = tool.name;
        if (tool.argumentsChunk != null) {
          call.arguments.write(tool.argumentsChunk);
        }
      }
    }

    final lines = streamed.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    final eventData = <String>[];
    var sawDone = false;

    void flushEvent() {
      if (eventData.isEmpty) return;
      final payload = eventData.join('\n').trim();
      eventData.clear();
      if (payload.trim() == '[DONE]') {
        sawDone = true;
        return;
      }
      for (final token in _tokensFromStreamPayload(payload, chatUri)) {
        record(token);
      }
    }

    await for (final line in lines) {
      if (line.isEmpty) {
        flushEvent();
        if (sawDone) break;
        continue;
      }
      if (line.startsWith(':')) continue;
      if (line.startsWith('data:')) {
        var v = line.substring(5);
        if (v.startsWith(' ')) v = v.substring(1);
        eventData.add(v);
      }
    }
    flushEvent();

    return ChatCompletionResponse(
      content: content.toString(),
      reasoning: reasoning.toString(),
      toolCalls:
          (toolCalls.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
              .where((entry) => entry.value.name?.trim().isNotEmpty == true)
              .map(
                (entry) => ChatCompletionToolCall(
                  id: entry.value.id,
                  name: entry.value.name!,
                  arguments: entry.value.arguments.length == 0
                      ? '{}'
                      : entry.value.arguments.toString(),
                ),
              )
              .toList(),
    );
  }

  ChatCompletionResponse _completionFromBody(String body, Uri chatUri) {
    final decoded = jsonDecode(body);
    final choices = decoded is Map ? decoded['choices'] : null;
    if (choices is! List || choices.isEmpty) {
      throw HttpException('No completion choices returned', uri: chatUri);
    }

    final message = choices.first is Map ? choices.first['message'] : null;
    if (message is! Map) {
      throw HttpException('No completion message returned', uri: chatUri);
    }

    final content = message['content'];
    final reasoning = message['reasoning_content'] ?? message['reasoning'];

    return ChatCompletionResponse(
      content: content is String ? content : '',
      reasoning: reasoning is String ? reasoning : '',
      toolCalls: _completionToolCallsFromWire(message['tool_calls']),
    );
  }

  Stream<ChatToken> streamMessage({
    required List<ChatMessage> messages,
    Map<String, dynamic>? extraParams,
  }) async* {
    final body = {
      'model': _model,
      'messages': messages.map((m) => m.toJson()).toList(),
      'stream': true,
      if (extraParams != null) ...extraParams,
    };

    final chatUri = Uri.parse('$_baseUrl/v1/chat/completions');

    final headers = {
      'Accept': 'text/event-stream',
      'Content-Type': 'application/json',
    };

    final req = http.Request('POST', chatUri)
      ..headers.addAll(headers)
      ..body = jsonEncode(body);

    final streamed = await _client.send(req);

    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      final responseBody = await streamed.stream.bytesToString();
      _throwHttpException(streamed.statusCode, responseBody, chatUri);
    }

    final lines = streamed.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    final eventData = <String>[];
    var sawDone = false;

    List<ChatToken> flushEvent() {
      if (eventData.isEmpty) return const [];
      final payload = eventData.join('\n').trim();
      eventData.clear();

      if (payload.trim() == '[DONE]') {
        sawDone = true;
        return const [];
      }

      try {
        final obj = jsonDecode(payload);

        if (obj is Map && obj['error'] != null) {
          final msg = obj['error']['message'] ?? obj['error'].toString();
          throw HttpException('Stream error: $msg', uri: chatUri);
        }

        final choices = (obj is Map) ? obj['choices'] : null;
        if (choices is List && choices.isNotEmpty) {
          final delta = choices[0]?['delta'];
          if (delta is Map) {
            final tokens = <ChatToken>[];

            final reasoningToken =
                delta['reasoning_content'] ?? delta['reasoning'];
            if (reasoningToken is String && reasoningToken.isNotEmpty) {
              tokens.add(ChatToken(reasoning: reasoningToken));
            }

            final contentToken = delta['content'];
            if (contentToken is String && contentToken.isNotEmpty) {
              tokens.add(ChatToken(content: contentToken));
            }

            final toolCalls = delta['tool_calls'];
            if (toolCalls is List && toolCalls.isNotEmpty) {
              tokens.addAll(
                toolCalls.whereType<Map>().map(_toolDeltaFromWire).whereType(),
              );
            } else if (toolCalls is Map) {
              final token = _toolDeltaFromWire(toolCalls);
              if (token != null) tokens.add(token);
            }

            return tokens;
          }
        }
      } on FormatException {
        return const [];
      }

      return const [];
    }

    await for (final line in lines) {
      if (line.isEmpty) {
        for (final token in flushEvent()) {
          yield token;
        }
        if (sawDone) break;
        continue;
      }

      if (line.startsWith(':')) continue;

      if (line.startsWith('data:')) {
        var v = line.substring(5);
        if (v.startsWith(' ')) v = v.substring(1);
        eventData.add(v);
      }
    }

    for (final token in flushEvent()) {
      yield token;
    }
  }

  static List<ChatToken> _tokensFromStreamPayload(String payload, Uri chatUri) {
    try {
      final obj = jsonDecode(payload);

      if (obj is Map && obj['error'] != null) {
        final msg = obj['error']['message'] ?? obj['error'].toString();
        throw HttpException('Stream error: $msg', uri: chatUri);
      }

      final choices = (obj is Map) ? obj['choices'] : null;
      if (choices is List && choices.isNotEmpty) {
        final delta = choices[0]?['delta'];
        if (delta is Map) {
          final tokens = <ChatToken>[];

          final reasoningToken =
              delta['reasoning_content'] ?? delta['reasoning'];
          if (reasoningToken is String && reasoningToken.isNotEmpty) {
            tokens.add(ChatToken(reasoning: reasoningToken));
          }

          final contentToken = delta['content'];
          if (contentToken is String && contentToken.isNotEmpty) {
            tokens.add(ChatToken(content: contentToken));
          }

          final toolCalls = delta['tool_calls'];
          if (toolCalls is List && toolCalls.isNotEmpty) {
            tokens.addAll(
              toolCalls.whereType<Map>().map(_toolDeltaFromWire).whereType(),
            );
          } else if (toolCalls is Map) {
            final token = _toolDeltaFromWire(toolCalls);
            if (token != null) tokens.add(token);
          }

          return tokens;
        }
      }
    } on FormatException {
      return const [];
    }

    return const [];
  }

  static ChatToken? _toolDeltaFromWire(Map tc) {
    final rawIndex = tc['index'];
    final index = rawIndex is int
        ? rawIndex
        : int.tryParse(rawIndex?.toString() ?? '') ?? 0;
    final id = tc['id']?.toString();

    String? name;
    String? argsChunk;

    final func = tc['function'];
    Object? args;
    if (func is Map) {
      name = func['name']?.toString();
      args = func['arguments'];
    } else {
      name = tc['name']?.toString() ?? tc['tool_name']?.toString();
      args = tc['arguments'] ?? tc['parameters'];
    }

    if (args is String && args.isNotEmpty) {
      argsChunk = args;
    } else if (args != null) {
      argsChunk = jsonEncode(args);
    }

    if (id == null && name == null && argsChunk == null) return null;

    return ChatToken(
      tool: ToolCallDelta(
        index: index,
        id: id,
        name: name,
        argumentsChunk: argsChunk,
      ),
    );
  }

  static List<ChatCompletionToolCall> _completionToolCallsFromWire(
    Object? raw,
  ) {
    if (raw is! List) return const [];

    return raw
        .whereType<Map>()
        .map((tc) {
          final id = tc['id']?.toString();
          final func = tc['function'];
          String? name;
          Object? args;

          if (func is Map) {
            name = func['name']?.toString();
            args = func['arguments'];
          } else {
            name = tc['name']?.toString() ?? tc['tool_name']?.toString();
            args = tc['arguments'] ?? tc['parameters'];
          }

          if (name == null || name.trim().isEmpty) return null;
          return ChatCompletionToolCall(
            id: id,
            name: name,
            arguments: _argumentsJson(args),
          );
        })
        .whereType<ChatCompletionToolCall>()
        .toList();
  }

  static String _argumentsJson(Object? rawArgs) {
    if (rawArgs == null) return '{}';
    if (rawArgs is String) {
      final trimmed = rawArgs.trim();
      return trimmed.isEmpty ? '{}' : trimmed;
    }
    return jsonEncode(rawArgs);
  }

  static void _emitCompletionTokens(
    ChatCompletionResponse completion,
    void Function(ChatToken token)? onToken,
  ) {
    if (onToken == null) return;
    if (completion.reasoning.isNotEmpty) {
      onToken(ChatToken(reasoning: completion.reasoning));
    }
    if (completion.content.isNotEmpty) {
      onToken(ChatToken(content: completion.content));
    }
    for (var i = 0; i < completion.toolCalls.length; i++) {
      final call = completion.toolCalls[i];
      onToken(
        ChatToken(
          tool: ToolCallDelta(
            index: i,
            id: call.id,
            name: call.name,
            argumentsChunk: call.arguments,
          ),
        ),
      );
    }
  }

  Never _throwHttpException(int statusCode, String responseBody, Uri uri) {
    String message;
    try {
      final error = jsonDecode(responseBody);
      message = error['error']?['message'] ?? error.toString();
    } catch (_) {
      message = responseBody;
    }
    throw HttpException('$statusCode: $message', uri: uri);
  }
}

class _StreamingToolCall {
  String? id;
  String? name;
  final StringBuffer arguments = StringBuffer();
}

class ChatCompletionResponse {
  final String content;
  final String reasoning;
  final List<ChatCompletionToolCall> toolCalls;

  const ChatCompletionResponse({
    required this.content,
    this.reasoning = '',
    this.toolCalls = const [],
  });
}

class ChatCompletionToolCall {
  final String? id;
  final String name;
  final String arguments;

  const ChatCompletionToolCall({
    required this.name,
    this.id,
    this.arguments = '{}',
  });
}
