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
      try {
        final error = jsonDecode(responseBody);
        final message = error['error']?['message'] ?? error.toString();
        throw HttpException('${streamed.statusCode}: $message', uri: chatUri);
      } catch (_) {
        throw HttpException(
          '${streamed.statusCode}: $responseBody',
          uri: chatUri,
        );
      }
    }

    final lines = streamed.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    final eventData = <String>[];
    var sawDone = false;

    ChatToken? flushEvent() {
      if (eventData.isEmpty) return null;
      final payload = eventData.join('\n').trim();
      eventData.clear();

      if (payload.trim() == '[DONE]') {
        sawDone = true;
        return null;
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
            final reasoningToken = delta['reasoning_content'];
            if (reasoningToken is String && reasoningToken.isNotEmpty) {
              return ChatToken(reasoning: reasoningToken);
            }

            final contentToken = delta['content'];
            if (contentToken is String && contentToken.isNotEmpty) {
              return ChatToken(content: contentToken);
            }

            final toolCalls = delta['tool_calls'];
            if (toolCalls is List && toolCalls.isNotEmpty) {
              final tc = toolCalls.first;
              if (tc is Map) {
                final index = tc['index'] is int ? tc['index'] as int : 0;
                final id = tc['id'] as String?;

                String? name;
                String? argsChunk;

                final func = tc['function'];
                if (func is Map) {
                  name = func['name'] as String?;
                  final args = func['arguments'];
                  if (args is String && args.isNotEmpty) {
                    argsChunk = args;
                  }
                }

                return ChatToken(
                  tool: ToolCallDelta(
                    index: index,
                    id: id,
                    name: name,
                    argumentsChunk: argsChunk,
                  ),
                );
              }
            }
          }
        }
      } on FormatException {
        return null;
      }

      return null;
    }

    await for (final line in lines) {
      if (line.isEmpty) {
        final token = flushEvent();
        if (token != null) yield token;
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

    final tailToken = flushEvent();
    if (tailToken != null) yield tailToken;
  }
}
