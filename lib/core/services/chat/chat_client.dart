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

  void dispose() {
    _client.close();
  }

  Future<String> completeMessage({
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

    final decoded = jsonDecode(response.body);
    final choices = decoded is Map ? decoded['choices'] : null;
    if (choices is! List || choices.isEmpty) {
      throw HttpException('No completion choices returned', uri: chatUri);
    }

    final message = choices.first is Map ? choices.first['message'] : null;
    if (message is! Map) {
      throw HttpException('No completion message returned', uri: chatUri);
    }

    final content = message['content'];
    if (content is String && content.isNotEmpty) return content;

    final reasoning = message['reasoning_content'] ?? message['reasoning'];
    if (reasoning is String && reasoning.isNotEmpty) return reasoning;

    return '';
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
