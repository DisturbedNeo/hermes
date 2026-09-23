import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hermes/core/helpers/chat/context_estimator.dart';
import 'package:hermes/core/helpers/uuid.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/models/chat_token.dart';
import 'package:hermes/core/models/model_call_diagnostics.dart';
import 'package:hermes/core/serialization/model_json.dart';
import 'package:hermes/core/services/cancellation_token.dart';
import 'package:http/http.dart' as http;

/// Parses SSE (Server-Sent Events) stream payloads into [ChatToken]s.
///
/// Handles line buffering, event aggregation, `[DONE]` detection, and JSON
/// decoding of chat completion deltas including reasoning, content, and tool calls.
class _SseParser {
  final List<String> _eventData = [];
  bool _sawDone = false;
  bool _sawFinishReason = false;
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

  bool get hasValidTerminal => _sawDone || _sawFinishReason;

  /// Parses buffered event data into tokens and clears the buffer.
  _ParsedSsePayload flush() {
    if (_eventData.isEmpty) return const _ParsedSsePayload([]);
    final payload = _eventData.join('\n').trim();
    _eventData.clear();

    if (payload == '[DONE]') {
      _sawDone = true;
      return const _ParsedSsePayload([], done: true);
    }

    late final _ParsedSsePayload parsed;
    try {
      parsed = _parsePayload(payload, _chatUri);
    } on ChatProtocolException {
      if (_sawFinishReason) return const _ParsedSsePayload([]);
      rethrow;
    }
    if (parsed.finishReason != null) _sawFinishReason = true;
    return parsed;
  }
}

class ChatProtocolException implements Exception {
  const ChatProtocolException({required this.uri, required this.reason});

  final Uri uri;
  final String reason;

  @override
  String toString() => 'Invalid model stream from $uri: $reason';
}

class _ParsedSsePayload {
  const _ParsedSsePayload(
    this.tokens, {
    this.done = false,
    this.finishReason,
    this.telemetry,
  });

  final List<ChatToken> tokens;
  final bool done;
  final String? finishReason;
  final _WireTelemetry? telemetry;
}

class _WireTelemetry {
  const _WireTelemetry({
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
List<ChatToken> tokensFromPayload(String payload, [Uri? chatUri]) {
  return _parsePayload(payload, chatUri).tokens;
}

_ParsedSsePayload _parsePayload(String payload, Uri? chatUri) {
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

  final telemetry = _telemetryFromWire(decoded);
  final choices = decoded['choices'];
  if (choices == null) {
    if (telemetry != null) {
      return _ParsedSsePayload(
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
      return _ParsedSsePayload(
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
    return _ParsedSsePayload(
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
  return _ParsedSsePayload(
    _tokensFromDelta(delta, chatUri),
    finishReason: finishReason,
    telemetry: telemetry,
  );
}

_WireTelemetry? _telemetryFromWire(Map decoded) {
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

  final promptFromUsage = _wireInt(usageMap?['prompt_tokens']);
  final cacheFromUsage = _wireInt(detailsMap?['cached_tokens']);
  final cacheFromTimings = _wireInt(timingsMap?['cache_n']);
  final processedFromTimings = _wireInt(timingsMap?['prompt_n']);
  final promptFromTimings =
      cacheFromTimings != null && processedFromTimings != null
      ? cacheFromTimings + processedFromTimings
      : null;

  final value = _WireTelemetry(
    serverRequestId: decoded['id']?.toString(),
    systemFingerprint: decoded['system_fingerprint']?.toString(),
    finishReason: finishReason,
    promptTokens:
        promptFromUsage ?? _wireInt(progressMap?['total']) ?? promptFromTimings,
    cachedPromptTokens:
        cacheFromUsage ?? _wireInt(progressMap?['cache']) ?? cacheFromTimings,
    processedPromptTokens:
        processedFromTimings ?? _wireInt(progressMap?['processed']),
    generatedTokens:
        _wireInt(usageMap?['completion_tokens']) ??
        _wireInt(timingsMap?['predicted_n']),
    promptProgressTotal: _wireInt(progressMap?['total']),
    promptProgressCached: _wireInt(progressMap?['cache']),
    promptProgressProcessed: _wireInt(progressMap?['processed']),
    promptProgressMs: _wireDouble(progressMap?['time_ms']),
    promptMs: _wireDouble(timingsMap?['prompt_ms']),
    generationMs: _wireDouble(timingsMap?['predicted_ms']),
    promptTokensPerSecond:
        _wireDouble(timingsMap?['prompt_per_second']) ??
        _progressTokensPerSecond(progressMap),
    generationTokensPerSecond: _wireDouble(timingsMap?['predicted_per_second']),
    draftTokens: _wireInt(timingsMap?['draft_n']),
    acceptedDraftTokens: _wireInt(timingsMap?['draft_n_accepted']),
    promptTokenPriority: promptFromUsage != null
        ? 5
        : _wireInt(progressMap?['total']) != null
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

int? _wireInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

double? _wireDouble(Object? value) {
  if (value is double) return value;
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

double? _progressTokensPerSecond(Map? progress) {
  final processed = _wireInt(progress?['processed']);
  final milliseconds = _wireDouble(progress?['time_ms']);
  if (processed == null || milliseconds == null || milliseconds <= 0) {
    return null;
  }
  return processed * 1000 / milliseconds;
}

LlamaServerProperties _serverPropertiesFromWire(Map decoded) {
  final defaults = decoded['default_generation_settings'];
  final defaultMap = defaults is Map ? defaults : const <dynamic, dynamic>{};
  final model = decoded['model'];
  final modelMap = model is Map ? model : const <dynamic, dynamic>{};
  final capabilities = decoded['chat_template_caps'];
  final modalities = decoded['modalities'];

  return LlamaServerProperties(
    effectiveContextSize:
        _wireInt(decoded['n_ctx']) ??
        _wireInt(defaultMap['n_ctx']) ??
        _wireInt(modelMap['n_ctx_train']),
    totalSlots:
        _wireInt(decoded['total_slots']) ?? _wireInt(decoded['n_slots']),
    modelPath:
        decoded['model_path']?.toString() ?? modelMap['path']?.toString(),
    buildInfo:
        decoded['build_info']?.toString() ??
        decoded['build']?.toString() ??
        decoded['version']?.toString(),
    chatTemplateCapabilities: capabilities is Map
        ? capabilities.map((key, value) => MapEntry(key.toString(), value))
        : const {},
    modalities: modalities is Map
        ? modalities.map((key, value) => MapEntry(key.toString(), value))
        : modalities is List
        ? {'supported': List<Object?>.from(modalities)}
        : const {},
  );
}

List<ChatToken> _tokensFromDelta(Map delta, Uri? chatUri) {
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
      toolCalls.whereType<Map>().map(_toolDeltaFromWire).whereType(),
    );
  } else if (toolCalls is Map) {
    final token = _toolDeltaFromWire(toolCalls);
    if (token != null) tokens.add(token);
  } else if (toolCalls != null) {
    throw ChatProtocolException(
      uri: chatUri ?? Uri(),
      reason: 'The tool_calls delta was not a list or object.',
    );
  }

  return tokens;
}

typedef ChatHttpClientFactory = http.Client Function();
typedef ModelCallDiagnosticsSink = void Function(ModelCallDiagnostics value);

class _CallDiagnosticsTracker {
  _CallDiagnosticsTracker({
    required this.callId,
    required this.label,
    required this.startedAt,
    required this.contextLimitTokens,
    required this.onSnapshot,
    required int? inputTokensHint,
    required int estimatedInputTokens,
  }) : promptTokens = inputTokensHint ?? estimatedInputTokens,
       accuracy = inputTokensHint == null
           ? TelemetryAccuracy.estimated
           : TelemetryAccuracy.exact;

  final String callId;
  final String label;
  final DateTime startedAt;
  final int? contextLimitTokens;
  final ModelCallDiagnosticsSink? onSnapshot;

  ModelCallStatus status = ModelCallStatus.starting;
  TelemetryAccuracy accuracy;
  DateTime? firstOutputAt;
  DateTime? completedAt;
  String? serverRequestId;
  String? systemFingerprint;
  String? finishReason;
  String? error;
  int? promptTokens;
  int? cachedPromptTokens;
  int? processedPromptTokens;
  int? generatedTokens;
  int? promptProgressTotal;
  int? promptProgressCached;
  int? promptProgressProcessed;
  double? promptProgressMs;
  double? promptMs;
  double? generationMs;
  double? promptTokensPerSecond;
  double? generationTokensPerSecond;
  int? draftTokens;
  int? acceptedDraftTokens;
  bool promptTokensExact = false;
  bool generatedTokensExact = false;
  bool cachedPromptTokensExact = false;
  int _outputAsciiBytes = 0;
  int _outputNonAsciiBytes = 0;
  late int _promptTokenPriority;
  bool _finalized = false;

  void initialisePriority(bool hasInputTokensHint) {
    _promptTokenPriority = hasInputTokensHint ? 2 : 1;
    promptTokensExact = hasInputTokensHint;
    if (hasInputTokensHint) accuracy = TelemetryAccuracy.partial;
  }

  ModelCallDiagnostics get snapshot => ModelCallDiagnostics(
    callId: callId,
    label: label,
    status: status,
    startedAt: startedAt,
    firstOutputAt: firstOutputAt,
    completedAt: completedAt,
    serverRequestId: serverRequestId,
    systemFingerprint: systemFingerprint,
    finishReason: finishReason,
    error: error,
    contextLimitTokens: contextLimitTokens,
    promptTokens: promptTokens,
    cachedPromptTokens: cachedPromptTokens,
    processedPromptTokens: processedPromptTokens,
    generatedTokens: generatedTokens,
    promptProgressTotal: promptProgressTotal,
    promptProgressCached: promptProgressCached,
    promptProgressProcessed: promptProgressProcessed,
    promptProgressMs: promptProgressMs,
    promptMs: promptMs,
    generationMs: generationMs,
    promptTokensPerSecond: promptTokensPerSecond,
    generationTokensPerSecond: generationTokensPerSecond,
    draftTokens: draftTokens,
    acceptedDraftTokens: acceptedDraftTokens,
    accuracy: accuracy,
    promptTokensExact: promptTokensExact,
    generatedTokensExact: generatedTokensExact,
    cachedPromptTokensExact: cachedPromptTokensExact,
  );

  bool get isFinalized => _finalized;

  void emit() {
    try {
      onSnapshot?.call(snapshot);
    } catch (_) {
      // Observability must never interfere with model requests.
    }
  }

  void apply(_WireTelemetry telemetry) {
    serverRequestId = telemetry.serverRequestId ?? serverRequestId;
    systemFingerprint = telemetry.systemFingerprint ?? systemFingerprint;
    finishReason = telemetry.finishReason ?? finishReason;
    if (telemetry.promptTokens != null &&
        telemetry.promptTokenPriority >= _promptTokenPriority) {
      promptTokens = telemetry.promptTokens;
      _promptTokenPriority = telemetry.promptTokenPriority;
      promptTokensExact = telemetry.promptTokenPriority >= 3;
    }
    cachedPromptTokens = telemetry.cachedPromptTokens ?? cachedPromptTokens;
    if (telemetry.cachedPromptTokens != null) cachedPromptTokensExact = true;
    processedPromptTokens =
        telemetry.processedPromptTokens ?? processedPromptTokens;
    final generated = telemetry.generatedTokens;
    if (generated != null && generated >= (generatedTokens ?? 0)) {
      generatedTokens = generated;
      generatedTokensExact = true;
    }
    promptProgressTotal = telemetry.promptProgressTotal ?? promptProgressTotal;
    promptProgressCached =
        telemetry.promptProgressCached ?? promptProgressCached;
    promptProgressProcessed =
        telemetry.promptProgressProcessed ?? promptProgressProcessed;
    promptProgressMs = telemetry.promptProgressMs ?? promptProgressMs;
    promptMs = telemetry.promptMs ?? promptMs;
    generationMs = telemetry.generationMs ?? generationMs;
    promptTokensPerSecond =
        telemetry.promptTokensPerSecond ?? promptTokensPerSecond;
    generationTokensPerSecond =
        telemetry.generationTokensPerSecond ?? generationTokensPerSecond;
    draftTokens = telemetry.draftTokens ?? draftTokens;
    acceptedDraftTokens = telemetry.acceptedDraftTokens ?? acceptedDraftTokens;

    _updateAccuracy();
    if ((generatedTokens ?? 0) > 0 || firstOutputAt != null) {
      status = ModelCallStatus.generating;
    } else if (promptProgressTotal != null || processedPromptTokens != null) {
      status = ModelCallStatus.processingPrompt;
    }
    emit();
  }

  void _updateAccuracy() {
    accuracy = promptTokensExact && generatedTokensExact
        ? TelemetryAccuracy.exact
        : promptTokensExact || generatedTokensExact || cachedPromptTokensExact
        ? TelemetryAccuracy.partial
        : TelemetryAccuracy.estimated;
  }

  void recordOutput(ChatToken token) {
    if (_finalized) return;
    firstOutputAt ??= DateTime.now();
    status = ModelCallStatus.generating;
    _recordEstimatedText(token.content);
    _recordEstimatedText(token.reasoning);
    _recordEstimatedText(token.tool?.name);
    _recordEstimatedText(token.tool?.argumentsChunk);
    if (!generatedTokensExact) {
      generatedTokens =
          (_outputAsciiBytes / 3).ceil() + (_outputNonAsciiBytes / 2).ceil();
    }
    emit();
  }

  void _recordEstimatedText(String? text) {
    if (text == null || text.isEmpty) return;
    for (final byte in utf8.encode(text)) {
      if (byte < 0x80) {
        _outputAsciiBytes++;
      } else {
        _outputNonAsciiBytes++;
      }
    }
  }

  void complete() {
    if (_finalized) return;
    _finalized = true;
    status = ModelCallStatus.completed;
    completedAt = DateTime.now();
    emit();
  }

  void fail(Object failure) {
    if (_finalized) return;
    _finalized = true;
    status = ModelCallStatus.failed;
    completedAt = DateTime.now();
    error = failure.toString();
    if (accuracy == TelemetryAccuracy.exact) {
      accuracy = TelemetryAccuracy.partial;
    }
    emit();
  }

  void cancel() {
    if (_finalized) return;
    _finalized = true;
    status = ModelCallStatus.cancelled;
    completedAt = DateTime.now();
    if (accuracy == TelemetryAccuracy.exact) {
      accuracy = TelemetryAccuracy.partial;
    }
    emit();
  }
}

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

class ChatRequestTimeoutException implements Exception {
  final Uri uri;
  final Duration inactivityTimeout;

  const ChatRequestTimeoutException({
    required this.uri,
    required this.inactivityTimeout,
  });

  @override
  String toString() =>
      'Model request received no data for ${inactivityTimeout.inSeconds} seconds: $uri';
}

class ChatClient {
  static const int _maxAttempts = 4;
  static const Duration defaultInactivityTimeout = Duration(minutes: 10);
  static const Duration defaultTokenCountTimeout = Duration(seconds: 5);

  final String _baseUrl;
  final String _model;
  final ChatHttpClientFactory _clientFactory;
  final void Function(ChatTransportEvent)? _onTransportEvent;
  final ModelCallDiagnosticsSink? _onDiagnostics;
  final bool Function() _liveDiagnosticsEnabled;
  final Duration inactivityTimeout;
  final Duration tokenCountTimeout;
  final Set<http.Client> _activeClients = {};
  bool _isDisposed = false;

  ChatClient({
    required String baseUrl,
    required String model,
    String? apiKey,
    ChatHttpClientFactory? clientFactory,
    void Function(ChatTransportEvent)? onTransportEvent,
    ModelCallDiagnosticsSink? onDiagnostics,
    bool Function()? liveDiagnosticsEnabled,
    this.inactivityTimeout = defaultInactivityTimeout,
    this.tokenCountTimeout = defaultTokenCountTimeout,
  }) : _model = model,
       _baseUrl = baseUrl,
       _clientFactory = clientFactory ?? http.Client.new,
       _onTransportEvent = onTransportEvent,
       _onDiagnostics = onDiagnostics,
       _liveDiagnosticsEnabled = liveDiagnosticsEnabled ?? (() => true);

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
    CancellationToken? cancellationToken,
    String diagnosticsLabel = 'Model call',
    int? contextLimitTokens,
    int? inputTokensHint,
  }) async {
    final completion = await completeChat(
      messages: messages,
      extraParams: extraParams,
      cancellationToken: cancellationToken,
      diagnosticsLabel: diagnosticsLabel,
      contextLimitTokens: contextLimitTokens,
      inputTokensHint: inputTokensHint,
    );
    if (completion.content.isNotEmpty) return completion.content;
    return completion.reasoning;
  }

  Future<ChatCompletionResponse> completeChat({
    required List<ChatMessage> messages,
    Map<String, dynamic>? extraParams,
    CancellationToken? cancellationToken,
    String diagnosticsLabel = 'Model call',
    int? contextLimitTokens,
    int? inputTokensHint,
  }) async {
    final tracker = _createDiagnosticsTracker(
      messages: messages,
      extraParams: extraParams,
      label: diagnosticsLabel,
      contextLimitTokens: contextLimitTokens,
      inputTokensHint: inputTokensHint,
    );
    final body = {
      'model': _model,
      'messages': messages.map(ModelJson.encode).toList(),
      'stream': false,
      ...?extraParams,
    };

    final chatUri = Uri.parse('$_baseUrl/v1/chat/completions');
    try {
      final completion = await _runBeforeOutputRetry(
        chatUri,
        cancellationToken,
        (client) async {
          final request = _request(
            chatUri,
            accept: 'application/json',
            body: body,
          );
          final streamed = await _sendWithTimeout(
            client,
            request,
            chatUri,
            inactivityTimeout,
          );
          final responseBody = await _readResponseBody(
            streamed.stream,
            client,
            chatUri,
            inactivityTimeout,
          );
          if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
            _throwHttpException(streamed.statusCode, responseBody, chatUri);
          }
          return _completionFromBody(responseBody, chatUri, tracker: tracker);
        },
      );
      tracker.complete();
      return completion.copyWith(diagnostics: tracker.snapshot);
    } on OperationCancelledException {
      tracker.cancel();
      rethrow;
    } catch (error) {
      if (cancellationToken?.isCancelled == true) {
        tracker.cancel();
      } else {
        tracker.fail(error);
      }
      rethrow;
    }
  }

  Future<ChatCompletionResponse> completeChatStreamed({
    required List<ChatMessage> messages,
    Map<String, dynamic>? extraParams,
    void Function(ChatToken token)? onToken,
    CancellationToken? cancellationToken,
    String diagnosticsLabel = 'Model call',
    int? contextLimitTokens,
    int? inputTokensHint,
  }) async {
    if (runtimeType != ChatClient) {
      final completion = await completeChat(
        messages: messages,
        extraParams: extraParams,
        cancellationToken: cancellationToken,
        diagnosticsLabel: diagnosticsLabel,
        contextLimitTokens: contextLimitTokens,
        inputTokensHint: inputTokensHint,
      );
      _emitCompletionTokens(completion, onToken);
      return completion;
    }

    final tracker = _createDiagnosticsTracker(
      messages: messages,
      extraParams: extraParams,
      label: diagnosticsLabel,
      contextLimitTokens: contextLimitTokens,
      inputTokensHint: inputTokensHint,
    );
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

    await for (final token in _streamMessageWithTracker(
      messages: messages,
      extraParams: extraParams,
      cancellationToken: cancellationToken,
      tracker: tracker,
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
      diagnostics: tracker.snapshot,
    );
  }

  ChatCompletionResponse _completionFromBody(
    String body,
    Uri chatUri, {
    _CallDiagnosticsTracker? tracker,
  }) {
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
    final telemetry = decoded is Map ? _telemetryFromWire(decoded) : null;
    if (telemetry != null) tracker?.apply(telemetry);

    if (tracker != null) {
      if (reasoning is String && reasoning.isNotEmpty) {
        tracker.recordOutput(ChatToken(reasoning: reasoning));
      } else if (content is String && content.isNotEmpty) {
        tracker.recordOutput(ChatToken(content: content));
      }
    }

    return ChatCompletionResponse(
      content: content is String ? content : '',
      reasoning: reasoning is String ? reasoning : '',
      toolCalls: _completionToolCallsFromWire(message['tool_calls']),
      diagnostics: tracker?.snapshot,
    );
  }

  Stream<ChatToken> streamMessage({
    required List<ChatMessage> messages,
    Map<String, dynamic>? extraParams,
    CancellationToken? cancellationToken,
    String diagnosticsLabel = 'Model call',
    int? contextLimitTokens,
    int? inputTokensHint,
  }) async* {
    final tracker = _createDiagnosticsTracker(
      messages: messages,
      extraParams: extraParams,
      label: diagnosticsLabel,
      contextLimitTokens: contextLimitTokens,
      inputTokensHint: inputTokensHint,
    );
    yield* _streamMessageWithTracker(
      messages: messages,
      extraParams: extraParams,
      cancellationToken: cancellationToken,
      tracker: tracker,
    );
  }

  Stream<ChatToken> _streamMessageWithTracker({
    required List<ChatMessage> messages,
    required _CallDiagnosticsTracker tracker,
    Map<String, dynamic>? extraParams,
    CancellationToken? cancellationToken,
  }) async* {
    cancellationToken?.throwIfCancelled();
    final chatUri = Uri.parse('$_baseUrl/v1/chat/completions');
    try {
      final body = _streamBody(messages: messages, extraParams: extraParams);
      await for (final token in _streamWithTransportRetries(
        chatUri: chatUri,
        body: body,
        cancellationToken: cancellationToken,
        tracker: tracker,
      )) {
        yield token;
      }
      tracker.complete();
    } on OperationCancelledException {
      tracker.cancel();
      rethrow;
    } catch (error) {
      if (cancellationToken?.isCancelled == true) {
        tracker.cancel();
      } else {
        tracker.fail(error);
      }
      rethrow;
    } finally {
      if (!tracker.isFinalized) tracker.cancel();
    }
  }

  Stream<ChatToken> _streamWithTransportRetries({
    required Uri chatUri,
    required Map<String, dynamic> body,
    required _CallDiagnosticsTracker tracker,
    CancellationToken? cancellationToken,
  }) async* {
    var outputStarted = false;
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        await for (final token in _streamAttempt(
          chatUri,
          body,
          cancellationToken,
          tracker,
        )) {
          outputStarted = true;
          yield token;
        }
        return;
      } catch (error, stackTrace) {
        cancellationToken?.throwIfCancelled();
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
        await Future<void>.delayed(_retryDelayForAttempt(attempt));
        cancellationToken?.throwIfCancelled();
      }
    }
  }

  Stream<ChatToken> _streamAttempt(
    Uri chatUri,
    Map<String, dynamic> body,
    CancellationToken? cancellationToken,
    _CallDiagnosticsTracker tracker,
  ) async* {
    final client = _openClient();
    final unregister = cancellationToken?.onCancel(client.close);
    try {
      cancellationToken?.throwIfCancelled();
      final request = _request(
        chatUri,
        accept: 'text/event-stream',
        body: body,
      );
      final streamed = await _sendWithTimeout(
        client,
        request,
        chatUri,
        inactivityTimeout,
      );
      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        final responseBody = await _readResponseBody(
          streamed.stream,
          client,
          chatUri,
          inactivityTimeout,
        );
        _throwHttpException(streamed.statusCode, responseBody, chatUri);
      }

      final contentType = streamed.headers['content-type'] ?? '';
      if (!contentType.toLowerCase().contains('text/event-stream')) {
        final responseBody = await _readResponseBody(
          streamed.stream,
          client,
          chatUri,
          inactivityTimeout,
        );
        final completion = _completionFromBody(
          responseBody,
          chatUri,
          tracker: tracker,
        );
        if (completion.reasoning.isNotEmpty) {
          final token = ChatToken(reasoning: completion.reasoning);
          tracker.recordOutput(token);
          yield token;
        }
        if (completion.content.isNotEmpty) {
          final token = ChatToken(content: completion.content);
          tracker.recordOutput(token);
          yield token;
        }
        for (var i = 0; i < completion.toolCalls.length; i++) {
          final call = completion.toolCalls[i];
          final token = ChatToken(
            tool: ToolCallDelta(
              index: i,
              id: call.id,
              name: call.name,
              argumentsChunk: call.arguments,
            ),
          );
          tracker.recordOutput(token);
          yield token;
        }
        return;
      }

      final lines = _responseStreamWithTimeout(
        streamed.stream,
        client,
        chatUri,
        inactivityTimeout,
      ).transform(utf8.decoder).transform(const LineSplitter());
      final parser = _SseParser(chatUri);
      await for (final line in lines) {
        parser.addLine(line);
        if (line.isEmpty) {
          final payload = parser.flush();
          if (payload.telemetry != null) {
            tracker.apply(payload.telemetry!);
          }
          if (payload.finishReason != null) {
            tracker.finishReason = payload.finishReason;
            tracker.emit();
          }
          for (final token in payload.tokens) {
            tracker.recordOutput(token);
            yield token;
          }
          if (parser.sawDone) break;
        }
      }
      final trailing = parser.flush();
      if (trailing.telemetry != null) tracker.apply(trailing.telemetry!);
      if (trailing.finishReason != null) {
        tracker.finishReason = trailing.finishReason;
        tracker.emit();
      }
      for (final token in trailing.tokens) {
        tracker.recordOutput(token);
        yield token;
      }
      if (!parser.hasValidTerminal) {
        throw ChatProtocolException(
          uri: chatUri,
          reason: 'The event stream ended without [DONE] or a finish_reason.',
        );
      }
    } finally {
      unregister?.call();
      _closeClient(client);
    }
  }

  _CallDiagnosticsTracker _createDiagnosticsTracker({
    required List<ChatMessage> messages,
    required Map<String, dynamic>? extraParams,
    required String label,
    required int? contextLimitTokens,
    required int? inputTokensHint,
  }) {
    final tracker = _CallDiagnosticsTracker(
      callId: uuid.v7(),
      label: label,
      startedAt: DateTime.now(),
      contextLimitTokens: contextLimitTokens,
      inputTokensHint: inputTokensHint,
      estimatedInputTokens: ContextEstimator.estimateChatCompletionRequest(
        messages: messages,
        extraParams: extraParams ?? const {},
      ),
      onSnapshot: _onDiagnostics,
    );
    tracker.initialisePriority(inputTokensHint != null);
    tracker.emit();
    return tracker;
  }

  Map<String, dynamic> _streamBody({
    required List<ChatMessage> messages,
    required Map<String, dynamic>? extraParams,
  }) {
    final body = <String, dynamic>{
      ...?extraParams,
      'model': _model,
      'messages': messages.map(ModelJson.encode).toList(),
      'stream': true,
    };
    final callerOptions = extraParams?['stream_options'];
    final streamOptions = <String, dynamic>{
      if (callerOptions is Map)
        for (final entry in callerOptions.entries)
          entry.key.toString(): entry.value,
      'include_usage': true,
    };
    body['stream_options'] = streamOptions;
    if (_liveDiagnosticsEnabled()) {
      body['timings_per_token'] = true;
      body['return_progress'] = true;
    }
    return body;
  }

  Future<LlamaServerProperties?> fetchServerProperties() async {
    if (_isDisposed) return null;
    final uri = Uri.parse('$_baseUrl/props');
    try {
      return await _withClient((client) async {
        final request = http.Request('GET', uri)
          ..persistentConnection = false
          ..headers.addAll({
            'Accept': 'application/json',
            'Connection': 'close',
          });
        final streamed = await _sendWithTimeout(
          client,
          request,
          uri,
          tokenCountTimeout,
        );
        if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
          return null;
        }
        final body = await _readResponseBody(
          streamed.stream,
          client,
          uri,
          tokenCountTimeout,
        );
        final decoded = jsonDecode(body);
        return decoded is Map ? _serverPropertiesFromWire(decoded) : null;
      }, null);
    } catch (_) {
      return null;
    }
  }

  Future<T> _runBeforeOutputRetry<T>(
    Uri uri,
    CancellationToken? cancellationToken,
    Future<T> Function(http.Client client) operation,
  ) async {
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        cancellationToken?.throwIfCancelled();
        return await _withClient(operation, cancellationToken);
      } catch (error, stackTrace) {
        cancellationToken?.throwIfCancelled();
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
        await Future<void>.delayed(_retryDelayForAttempt(attempt));
        cancellationToken?.throwIfCancelled();
      }
    }
    throw StateError('Unreachable retry state');
  }

  static Duration _retryDelayForAttempt(int attempt) {
    final backoffMultiplier = 1 << (attempt - 1);
    return Duration(milliseconds: 100 * backoffMultiplier);
  }

  Future<T> _withClient<T>(
    Future<T> Function(http.Client client) operation,
    CancellationToken? cancellationToken,
  ) async {
    final client = _openClient();
    final unregister = cancellationToken?.onCancel(client.close);
    try {
      cancellationToken?.throwIfCancelled();
      return await operation(client);
    } finally {
      unregister?.call();
      _closeClient(client);
    }
  }

  Future<int> countInputTokens({
    required List<ChatMessage> messages,
    Map<String, dynamic>? extraParams,
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();

    final uri = Uri.parse('$_baseUrl/v1/chat/completions/input_tokens');
    final body = {
      'model': _model,
      'messages': messages.map(ModelJson.encode).toList(),
      ...?extraParams,
    };

    return _runBeforeOutputRetry(uri, cancellationToken, (client) async {
      final request = _request(uri, accept: 'application/json', body: body);
      final streamed = await _sendWithTimeout(
        client,
        request,
        uri,
        tokenCountTimeout,
      );
      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        throw HttpException(
          'HTTP ${streamed.statusCode} from input-token endpoint',
          uri: uri,
        );
      }
      final responseBody = await _readResponseBody(
        streamed.stream,
        client,
        uri,
        tokenCountTimeout,
      );
      final decoded = jsonDecode(responseBody);
      final value = decoded is Map ? decoded['input_tokens'] : null;
      if (value is int) return value;
      if (value is num) return value.toInt();
      final parsed = int.tryParse(value?.toString() ?? '');
      if (parsed != null) return parsed;
      throw const FormatException(
        'Input-token endpoint returned no input_tokens value',
      );
    });
  }

  Future<http.StreamedResponse> _sendWithTimeout(
    http.Client client,
    http.BaseRequest request,
    Uri uri,
    Duration timeout,
  ) {
    return client
        .send(request)
        .timeout(
          timeout,
          onTimeout: () {
            client.close();
            throw ChatRequestTimeoutException(
              uri: uri,
              inactivityTimeout: timeout,
            );
          },
        );
  }

  Stream<List<int>> _responseStreamWithTimeout(
    Stream<List<int>> stream,
    http.Client client,
    Uri uri,
    Duration timeout,
  ) {
    return stream.timeout(
      timeout,
      onTimeout: (sink) {
        client.close();
        sink.addError(
          ChatRequestTimeoutException(uri: uri, inactivityTimeout: timeout),
        );
        sink.close();
      },
    );
  }

  Future<String> _readResponseBody(
    Stream<List<int>> stream,
    http.Client client,
    Uri uri,
    Duration timeout,
  ) async {
    final bytes = await _responseStreamWithTimeout(
      stream,
      client,
      uri,
      timeout,
    ).expand((chunk) => chunk).toList();
    return utf8.decode(bytes);
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
  final ModelCallDiagnostics? diagnostics;

  const ChatCompletionResponse({
    required this.content,
    this.reasoning = '',
    this.toolCalls = const [],
    this.diagnostics,
  });

  ChatCompletionResponse copyWith({ModelCallDiagnostics? diagnostics}) =>
      ChatCompletionResponse(
        content: content,
        reasoning: reasoning,
        toolCalls: toolCalls,
        diagnostics: diagnostics ?? this.diagnostics,
      );
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
