import 'dart:convert';
import 'dart:io';

import 'package:hermes/features/chat/application/contracts/chat_token.dart';
import 'package:hermes/features/model/application/model_errors.dart';

class ChatSseParser {
  final List<String> _eventData = [];
  bool _sawDone = false;
  bool _sawFinishReason = false;
  final Uri? _chatUri;

  ChatSseParser([this._chatUri]);

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

  bool get hasValidTerminal => _sawDone || _sawFinishReason;

  /// Parses buffered event data into tokens and clears the buffer.
  ChatSsePayload flush() {
    if (_eventData.isEmpty) return const ChatSsePayload([]);
    final payload = _eventData.join('\n').trim();
    _eventData.clear();

    if (payload == '[DONE]') {
      _sawDone = true;
      return const ChatSsePayload([], done: true);
    }

    late final ChatSsePayload parsed;
    try {
      parsed = parseChatSsePayload(payload, _chatUri);
    } on ChatProtocolException {
      if (_sawFinishReason) return const ChatSsePayload([]);
      rethrow;
    }
    if (parsed.finishReason != null) _sawFinishReason = true;
    return parsed;
  }
}

class ChatSsePayload {
  const ChatSsePayload(
    this.tokens, {
    this.done = false,
    this.finishReason,
    this.telemetry,
  });

  final List<ChatToken> tokens;
  final bool done;
  final String? finishReason;
  final ChatWireTelemetry? telemetry;
}

class ChatWireTelemetry {
  const ChatWireTelemetry({
    this.serverRequestId,
    this.systemFingerprint,
    this.finishReason,
    this.promptTokens,
    this.cachedPromptTokens,
    this.processedPromptTokens,
    this.generatedTokens,
    this.promptProgressTotal,
    this.promptProgressCached,
    this.promptProgressProcessed,
    this.promptProgressMs,
    this.promptMs,
    this.generationMs,
    this.promptTokensPerSecond,
    this.generationTokensPerSecond,
    this.draftTokens,
    this.acceptedDraftTokens,
    this.promptTokenPriority = 0,
  });

  final String? serverRequestId;
  final String? systemFingerprint;
  final String? finishReason;
  final int? promptTokens;
  final int? cachedPromptTokens;
  final int? processedPromptTokens;
  final int? generatedTokens;
  final int? promptProgressTotal;
  final int? promptProgressCached;
  final int? promptProgressProcessed;
  final double? promptProgressMs;
  final double? promptMs;
  final double? generationMs;
  final double? promptTokensPerSecond;
  final double? generationTokensPerSecond;
  final int? draftTokens;
  final int? acceptedDraftTokens;
  final int promptTokenPriority;

  bool get hasServerMeasurements =>
      promptTokens != null ||
      cachedPromptTokens != null ||
      processedPromptTokens != null ||
      generatedTokens != null ||
      promptProgressTotal != null ||
      promptMs != null ||
      generationMs != null;
}

/// Parses an SSE event payload string into a list of [ChatToken]s.
///
/// Throws [ChatProtocolException] for malformed or unrecognized payloads and
/// [HttpException] when the server sends a valid error object.
List<ChatToken> chatTokensFromPayload(String payload, [Uri? chatUri]) {
  return parseChatSsePayload(payload, chatUri).tokens;
}

ChatSsePayload parseChatSsePayload(String payload, Uri? chatUri) {
  final endpoint = chatUri ?? Uri();
  late final Object? decoded;
  try {
    decoded = jsonDecode(payload);
  } on FormatException catch (error) {
    throw ChatProtocolException(
      uri: endpoint,
      reason: 'Malformed JSON event: ${error.message}',
    );
  }

  if (decoded is! Map) {
    throw ChatProtocolException(
      uri: endpoint,
      reason: 'Expected a JSON object event.',
    );
  }

  final error = decoded['error'];
  if (error != null) {
    if (error is! Map || error['message'] is! String) {
      throw ChatProtocolException(
        uri: endpoint,
        reason: 'Malformed server error event.',
      );
    }
    throw HttpException('Stream error: ${error['message']}', uri: chatUri);
  }

  final telemetry = chatTelemetryFromWire(decoded);
  final choices = decoded['choices'];
  if (choices == null) {
    if (telemetry != null) {
      return ChatSsePayload(
        const [],
        finishReason: telemetry.finishReason,
        telemetry: telemetry,
      );
    }
    throw ChatProtocolException(
      uri: endpoint,
      reason: 'Event did not contain choices, usage, or an error.',
    );
  }
  if (choices is! List) {
    throw ChatProtocolException(
      uri: endpoint,
      reason: 'The choices field was not a list.',
    );
  }
  if (choices.isEmpty) {
    if (telemetry != null) {
      return ChatSsePayload(
        const [],
        finishReason: telemetry.finishReason,
        telemetry: telemetry,
      );
    }
    throw ChatProtocolException(
      uri: endpoint,
      reason: 'The choices list was empty without usage metadata.',
    );
  }

  final choice = choices.first;
  if (choice is! Map) {
    throw ChatProtocolException(
      uri: endpoint,
      reason: 'The first choice was not an object.',
    );
  }
  final finishReason = choice['finish_reason']?.toString();
  final delta = choice['delta'];
  if (delta == null && finishReason != null) {
    return ChatSsePayload(
      const [],
      finishReason: finishReason,
      telemetry: telemetry,
    );
  }
  if (delta is! Map) {
    throw ChatProtocolException(
      uri: endpoint,
      reason: 'A choice did not contain a valid delta object.',
    );
  }
  return ChatSsePayload(
    chatTokensFromDelta(delta, chatUri),
    finishReason: finishReason,
    telemetry: telemetry,
  );
}

ChatWireTelemetry? chatTelemetryFromWire(Map decoded) {
  final usage = decoded['usage'];
  final timings = decoded['timings'];
  final progress = decoded['prompt_progress'];
  final choice =
      decoded['choices'] is List && (decoded['choices'] as List).isNotEmpty
      ? (decoded['choices'] as List).first
      : null;
  final finishReason = choice is Map
      ? choice['finish_reason']?.toString()
      : null;

  final usageMap = usage is Map ? usage : null;
  final details = usageMap?['prompt_tokens_details'];
  final detailsMap = details is Map ? details : null;
  final timingsMap = timings is Map ? timings : null;
  final progressMap = progress is Map ? progress : null;

  final promptFromUsage = chatWireInt(usageMap?['prompt_tokens']);
  final cacheFromUsage = chatWireInt(detailsMap?['cached_tokens']);
  final cacheFromTimings = chatWireInt(timingsMap?['cache_n']);
  final processedFromTimings = chatWireInt(timingsMap?['prompt_n']);
  final promptFromTimings =
      cacheFromTimings != null && processedFromTimings != null
      ? cacheFromTimings + processedFromTimings
      : null;

  final value = ChatWireTelemetry(
    serverRequestId: decoded['id']?.toString(),
    systemFingerprint: decoded['system_fingerprint']?.toString(),
    finishReason: finishReason,
    promptTokens:
        promptFromUsage ??
        chatWireInt(progressMap?['total']) ??
        promptFromTimings,
    cachedPromptTokens:
        cacheFromUsage ??
        chatWireInt(progressMap?['cache']) ??
        cacheFromTimings,
    processedPromptTokens:
        processedFromTimings ?? chatWireInt(progressMap?['processed']),
    generatedTokens:
        chatWireInt(usageMap?['completion_tokens']) ??
        chatWireInt(timingsMap?['predicted_n']),
    promptProgressTotal: chatWireInt(progressMap?['total']),
    promptProgressCached: chatWireInt(progressMap?['cache']),
    promptProgressProcessed: chatWireInt(progressMap?['processed']),
    promptProgressMs: chatWireDouble(progressMap?['time_ms']),
    promptMs: chatWireDouble(timingsMap?['prompt_ms']),
    generationMs: chatWireDouble(timingsMap?['predicted_ms']),
    promptTokensPerSecond:
        chatWireDouble(timingsMap?['prompt_per_second']) ??
        chatProgressTokensPerSecond(progressMap),
    generationTokensPerSecond: chatWireDouble(
      timingsMap?['predicted_per_second'],
    ),
    draftTokens: chatWireInt(timingsMap?['draft_n']),
    acceptedDraftTokens: chatWireInt(timingsMap?['draft_n_accepted']),
    promptTokenPriority: promptFromUsage != null
        ? 5
        : chatWireInt(progressMap?['total']) != null
        ? 4
        : promptFromTimings != null
        ? 3
        : 0,
  );

  final hasIdentity =
      value.serverRequestId != null || value.systemFingerprint != null;
  if (!hasIdentity &&
      value.finishReason == null &&
      !value.hasServerMeasurements) {
    return null;
  }
  return value;
}

int? chatWireInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

double? chatWireDouble(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

double? chatProgressTokensPerSecond(Map? progress) {
  final processed = chatWireInt(progress?['processed']);
  final milliseconds = chatWireDouble(progress?['time_ms']);
  if (processed == null || milliseconds == null || milliseconds <= 0) {
    return null;
  }
  return processed * 1000 / milliseconds;
}

List<ChatToken> chatTokensFromDelta(Map delta, Uri? chatUri) {
  final tokens = <ChatToken>[];

  final role = delta['role'];
  if (role != null && role is! String) {
    throw ChatProtocolException(
      uri: chatUri ?? Uri(),
      reason: 'A delta role was not a string.',
    );
  }

  final reasoningToken = delta['reasoning_content'] ?? delta['reasoning'];
  if (reasoningToken != null && reasoningToken is! String) {
    throw ChatProtocolException(
      uri: chatUri ?? Uri(),
      reason: 'A reasoning delta was not a string.',
    );
  }
  if (reasoningToken is String && reasoningToken.isNotEmpty) {
    tokens.add(ChatToken(reasoning: reasoningToken));
  }

  final contentToken = delta['content'];
  if (contentToken != null && contentToken is! String) {
    throw ChatProtocolException(
      uri: chatUri ?? Uri(),
      reason: 'A content delta was not a string.',
    );
  }
  if (contentToken is String && contentToken.isNotEmpty) {
    tokens.add(ChatToken(content: contentToken));
  }

  final toolCalls = delta['tool_calls'];
  if (toolCalls is List && toolCalls.isNotEmpty) {
    if (toolCalls.any((item) => item is! Map)) {
      throw ChatProtocolException(
        uri: chatUri ?? Uri(),
        reason: 'A tool-call delta was not an object.',
      );
    }
    tokens.addAll(
      toolCalls.whereType<Map>().map(chatToolDeltaFromWire).whereType(),
    );
  } else if (toolCalls is Map) {
    final token = chatToolDeltaFromWire(toolCalls);
    if (token != null) tokens.add(token);
  } else if (toolCalls != null) {
    throw ChatProtocolException(
      uri: chatUri ?? Uri(),
      reason: 'The tool_calls delta was not a list or object.',
    );
  }

  return tokens;
}

ChatToken? chatToolDeltaFromWire(Map tc) {
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
