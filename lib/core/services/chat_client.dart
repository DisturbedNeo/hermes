import 'dart:convert';
import 'dart:io';

import 'package:hermes/core/models/chat_message.dart';
import 'package:http/http.dart' as http;

class ChatClient {
  final String baseUrl;
  final String model;
  final String? apiKey;
  final http.Client client = http.Client();

  ChatClient({
    required this.baseUrl,
    required this.model,
    this.apiKey,
  });

  void dispose() {
    client.close();
  }

  Stream<String> streamMessage({
    required List<ChatMessage> messages,
    Map<String, dynamic>? extraParams
  }) async* {
    final body = {
      'model': model,
      'messages': messages.map((m) => m.toJson()).toList(),
      'stream': true,
      if (extraParams != null) ...extraParams
    };

    final chatUri = Uri.parse('$baseUrl/v1/chat/completions');

    final headers = {
      'Content-Type': 'application/json'
    };

    final req = http.Request('POST', chatUri)
      ..headers.addAll(headers)
      ..body = jsonEncode(body);

    final streamed = await client.send(req);

    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      final responseBody = await streamed.stream.bytesToString();

      try {
        final error = jsonDecode(responseBody);
        final message = error['error']?['message'] ?? error.toString();
        throw HttpException('${streamed.statusCode}: $message', uri: chatUri);
      } catch (_) {
        throw HttpException('${streamed.statusCode}: $responseBody', uri: chatUri);
      }
    }

    final lines = streamed.stream.transform(utf8.decoder).transform(const LineSplitter());

    await for (final line in lines) {
      final trimmed = line.trimLeft();

      if (!trimmed.startsWith('data:')) continue;

      final payload = trimmed.substring(5).trim();

      if (payload == '[DONE]') break;

      try {
        final json = jsonDecode(payload) as Map<String, dynamic>;
        final delta = json['choices'][0]['delta'];
        final token = (delta?['content'] as String?) ?? '';
        if (token.isNotEmpty) yield token;
      } catch (_) {}
    }
  }
}
