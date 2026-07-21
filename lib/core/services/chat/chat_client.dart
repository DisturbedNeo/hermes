import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/serialization/model_json.dart';
import 'package:hermes/core/models/chat_token.dart';
import 'package:http/http.dart' as http;

/// Parses SSE (Server-Sent Events) stream payloads into [ChatToken]s.
///
/// Handles line buffering, event aggregation, `[DONE]` detection, and JSON
/// decoding of chat completion deltas including reasoning, content, and tool calls.
class _SseParser {
  final List<String> _eventData = [];
  bool _sawDone = false;
  final Uri? _chatUri;

  _SseParser([this._chatUri]);

  /// Accumulates a single line from the SSE stream.
  void addLine(String line) {
    if (line.startsWith(':')) return; // comment
    if (line.startsWith('data:')) {
      var value = line.substring(5);
      if (value.startsWith(' ')) value = value.substring(1);
      _eventData.add(value);
    }
  }

  bool get sawDone => _sawDone;

  /// Parses buffered event data into tokens and clears the buffer.
  List<ChatToken> flush() {
    if (_eventData.isEmpty) return const [];
    final payload = _eventData.join('\n').trim();
    _eventData.clear();

    if (payload == '[DONE]') {
      _sawDone = true;
      return const [];
    }

    return _chatUri != null
        ? tokensFromPayload(payload, _chatUri)
        : tokensFromPayload(payload);
  }
}

/// Parses an SSE event payload string into a list of [ChatToken]s.
///
/// Returns an empty list for malformed JSON or unrecognized structures.
/// Throws [HttpException] if the payload contains an error field.
List<ChatToken> tokensFromPayload(String payload, [Uri? chatUri]) {
  try {
    final obj = jsonDecode(payload);

    if (obj is Map && obj['error'] != null) {
      final msg = obj['error']['message'] ?? obj['error'].toString();
      if (chatUri != null) {
        throw HttpException('Stream error: $msg', uri: chatUri);
      }
      // No URI available — log and skip.
      return const [];
    }

    final choices = (obj is Map) ? obj['choices'] : null;
    if (choices is List && choices.isNotEmpty) {
      final delta = choices[0]?['delta'];
      if (delta is Map) return _tokensFromDelta(delta, chatUri);
    }
  } on FormatException {
    // Malformed JSON — silently skip.
  }

  return const [];
}

List<ChatToken> _tokensFromDelta(Map delta, Uri? chatUri) {
  final tokens = <ChatToken>[];

  final reasoningToken = delta['reasoning_content'] ?? delta['reasoning'];
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

typedef ChatHttpClientFactory = http.Client Function();

enum ChatTransportFailureKind {
  brokenPipe,
  connectionReset,
  connectionRefused,
  connectionClosed,
  socket,
}

class ChatTransportEvent {
  final DateTime timestamp;
  final ChatTransportFailureKind kind;
  final Uri uri;
  final int attempt;
  final bool willRetry;
  final bool outputStarted;
  final Object error;
  final StackTrace stackTrace;

  ChatTransportEvent({
    required this.kind,
    required this.uri,
    required this.attempt,
    required this.willRetry,
    required this.outputStarted,
    required this.error,
    required this.stackTrace,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

class ChatTransportException implements Exception {
  final ChatTransportFailureKind kind;
  final Uri uri;
  final int attempts;
  final bool outputStarted;
  final Object cause;
  final StackTrace causeStackTrace;

  const ChatTransportException({
    required this.kind,
    required this.uri,
    required this.attempts,
    required this.outputStarted,
    required this.cause,
    required this.causeStackTrace,
  });

  @override
  String toString() {
    final phase = outputStarted ? ' after model output began' : '';
    return 'Model transport failed$phase after $attempts attempt(s): $cause';
  }
}

class ChatClient {
  static const Duration _retryDelay = Duration(milliseconds: 100);
  static const int _maxAttempts = 2;

  final String _baseUrl;
  final String _model;
  final ChatHttpClientFactory _clientFactory;
  final void Function(ChatTransportEvent)? _onTransportEvent;
  final Set<http.Client> _activeClients = {};
  bool _isDisposed = false;

  ChatClient({
    required String baseUrl,
    required String model,
    String? apiKey,
    ChatHttpClientFactory? clientFactory,
    void Function(ChatTransportEvent)? onTransportEvent,
  }) : _model = model,
       _baseUrl = baseUrl,
       _clientFactory = clientFactory ?? http.Client.new,
       _onTransportEvent = onTransportEvent;

  bool get supportsStreamingCancellation => runtimeType == ChatClient;

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    for (final client in _activeClients.toList()) {
      client.close();
    }
    _activeClients.clear();
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
      'messages': messages.map(ModelJson.encode).toList(),
      'stream': false,
      ...?extraParams,
    };

    final chatUri = Uri.parse('$_baseUrl/v1/chat/completions');
    return _runBeforeOutputRetry(chatUri, (client) async {
      final request = _request(chatUri, accept: 'application/json', body: body);
      final streamed = await client.send(request);
      final responseBody = await streamed.stream.bytesToString();
      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        _throwHttpException(streamed.statusCode, responseBody, chatUri);
      }
      return _completionFromBody(responseBody, chatUri);
    });
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

    await for (final token in streamMessage(
      messages: messages,
      extraParams: extraParams,
    )) {
      record(token);
    }

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
      'messages': messages.map(ModelJson.encode).toList(),
      'stream': true,
      ...?extraParams,
    };

    final chatUri = Uri.parse('$_baseUrl/v1/chat/completions');

    var outputStarted = false;
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        await for (final token in _streamAttempt(chatUri, body)) {
          outputStarted = true;
          yield token;
        }
        return;
      } catch (error, stackTrace) {
        final kind = _transportKind(error);
        if (kind == null) rethrow;
        final willRetry = !outputStarted && attempt < _maxAttempts;
        _emitTransportEvent(
          ChatTransportEvent(
            kind: kind,
            uri: chatUri,
            attempt: attempt,
            willRetry: willRetry,
            outputStarted: outputStarted,
            error: error,
            stackTrace: stackTrace,
          ),
        );
        if (!willRetry) {
          throw ChatTransportException(
            kind: kind,
            uri: chatUri,
            attempts: attempt,
            outputStarted: outputStarted,
            cause: error,
            causeStackTrace: stackTrace,
          );
        }
        await Future<void>.delayed(_retryDelay);
      }
    }
  }

  Stream<ChatToken> _streamAttempt(
    Uri chatUri,
    Map<String, dynamic> body,
  ) async* {
    final client = _openClient();
    try {
      final request = _request(
        chatUri,
        accept: 'text/event-stream',
        body: body,
      );
      final streamed = await client.send(request);
      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        final responseBody = await streamed.stream.bytesToString();
        _throwHttpException(streamed.statusCode, responseBody, chatUri);
      }

      final contentType = streamed.headers['content-type'] ?? '';
      if (!contentType.toLowerCase().contains('text/event-stream')) {
        final responseBody = await streamed.stream.bytesToString();
        final completion = _completionFromBody(responseBody, chatUri);
        if (completion.reasoning.isNotEmpty) {
          yield ChatToken(reasoning: completion.reasoning);
        }
        if (completion.content.isNotEmpty) {
          yield ChatToken(content: completion.content);
        }
        for (var i = 0; i < completion.toolCalls.length; i++) {
          final call = completion.toolCalls[i];
          yield ChatToken(
            tool: ToolCallDelta(
              index: i,
              id: call.id,
              name: call.name,
              argumentsChunk: call.arguments,
            ),
          );
        }
        return;
      }

      final lines = streamed.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      final parser = _SseParser(chatUri);
      await for (final line in lines) {
        parser.addLine(line);
        if (line.isEmpty) {
          for (final token in parser.flush()) {
            yield token;
          }
          if (parser.sawDone) break;
        }
      }
      for (final token in parser.flush()) {
        yield token;
      }
    } finally {
      _closeClient(client);
    }
  }

  Future<T> _runBeforeOutputRetry<T>(
    Uri uri,
    Future<T> Function(http.Client client) operation,
  ) async {
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        return await _withClient(operation);
      } catch (error, stackTrace) {
        final kind = _transportKind(error);
        if (kind == null) rethrow;
        final willRetry = attempt < _maxAttempts;
        _emitTransportEvent(
          ChatTransportEvent(
            kind: kind,
            uri: uri,
            attempt: attempt,
            willRetry: willRetry,
            outputStarted: false,
            error: error,
            stackTrace: stackTrace,
          ),
        );
        if (!willRetry) {
          throw ChatTransportException(
            kind: kind,
            uri: uri,
            attempts: attempt,
            outputStarted: false,
            cause: error,
            causeStackTrace: stackTrace,
          );
        }
        await Future<void>.delayed(_retryDelay);
      }
    }
    throw StateError('Unreachable retry state');
  }

  Future<T> _withClient<T>(
    Future<T> Function(http.Client client) operation,
  ) async {
    final client = _openClient();
    try {
      return await operation(client);
    } finally {
      _closeClient(client);
    }
  }

  http.Client _openClient() {
    if (_isDisposed) {
      throw StateError('ChatClient is already disposed.');
    }
    final client = _clientFactory();
    _activeClients.add(client);
    return client;
  }

  void _closeClient(http.Client client) {
    _activeClients.remove(client);
    client.close();
  }

  http.Request _request(
    Uri uri, {
    required String accept,
    required Map<String, dynamic> body,
  }) {
    return http.Request('POST', uri)
      ..persistentConnection = false
      ..headers.addAll({
        'Accept': accept,
        'Content-Type': 'application/json',
        'Connection': 'close',
      })
      ..body = jsonEncode(body);
  }

  ChatTransportFailureKind? _transportKind(Object error) {
    if (error is http.RequestAbortedException) return null;
    if (error is SocketException) {
      return switch (error.osError?.errorCode) {
        32 => ChatTransportFailureKind.brokenPipe,
        54 || 104 => ChatTransportFailureKind.connectionReset,
        61 || 111 => ChatTransportFailureKind.connectionRefused,
        _ => ChatTransportFailureKind.socket,
      };
    }
    if (error is http.ClientException) {
      final message = error.message.toLowerCase();
      if (message.contains('connection closed') ||
          message.contains('closed before')) {
        return ChatTransportFailureKind.connectionClosed;
      }
    }
    return null;
  }

  void _emitTransportEvent(ChatTransportEvent event) {
    try {
      _onTransportEvent?.call(event);
    } catch (_) {
      // Observability must never interfere with model requests.
    }
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

/// Converts a tool delta from wire format into a [ChatToken].
///
/// Handles both the newer `function`/`arguments` naming and the older
/// `name`/`parameters` variants used by some LLM servers.
ChatToken? _toolDeltaFromWire(Map tc) {
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
