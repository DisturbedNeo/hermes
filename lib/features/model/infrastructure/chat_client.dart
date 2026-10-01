import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hermes/features/chat/application/protocol/context_estimator.dart';
import 'package:hermes/features/chat/application/protocol/chat_message_wire_adapter.dart';
import 'package:hermes/core/uuid.dart';
import 'package:hermes/features/chat/application/contracts/chat_message.dart';
import 'package:hermes/features/chat/application/contracts/chat_token.dart';
import 'package:hermes/features/model/application/model_call_diagnostics.dart';
import 'package:hermes/core/cancellation.dart';
import 'package:hermes/features/model/application/model_completion.dart';
import 'package:hermes/features/model/application/model_errors.dart';
import 'package:hermes/features/model/domain/model_provider.dart';
import 'package:hermes/features/model/application/model_request.dart';

export 'package:hermes/features/model/application/model_request.dart';
import 'package:http/http.dart' as http;
import 'package:hermes/features/model/infrastructure/chat_model_property_decoder.dart';
import 'package:hermes/features/model/infrastructure/chat_retry_policy.dart';
import 'package:hermes/features/model/infrastructure/chat_sse_parser.dart';

export 'package:hermes/features/model/application/model_completion.dart';
export 'package:hermes/features/model/application/model_errors.dart';

const _chatMessageWireAdapter = ChatMessageWireAdapter();

typedef ChatHttpClientFactory = http.Client Function();
typedef ModelCallDiagnosticsSink = void Function(ModelCallDiagnostics value);

/// Compatibility export for callers that previously imported the parser from
/// ChatClient's library.
List<ChatToken> tokensFromPayload(String payload, [Uri? chatUri]) =>
    chatTokensFromPayload(payload, chatUri);

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

  void apply(ChatWireTelemetry telemetry) {
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

class ChatClient implements ModelProvider {
  static const ChatRetryPolicy _retryPolicy = ChatRetryPolicy();
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

  @override
  bool get supportsStreamingCancellation => runtimeType == ChatClient;

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    for (final client in _activeClients.toList()) {
      client.close();
    }
    _activeClients.clear();
  }

  @override
  Future<String> completeMessage({
    required List<ChatMessage> messages,
    ModelRequestOptions? extraParams,
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

  @override
  Future<ChatCompletionResponse> completeChat({
    required List<ChatMessage> messages,
    ModelRequestOptions? extraParams,
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
      'messages': messages.map(_chatMessageWireAdapter.encode).toList(),
      'stream': false,
      ..._encodeRequestOptions(extraParams),
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

  @override
  Future<ChatCompletionResponse> completeChatStreamed({
    required List<ChatMessage> messages,
    ModelRequestOptions? extraParams,
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
    final telemetry = decoded is Map ? chatTelemetryFromWire(decoded) : null;
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

  @override
  Stream<ChatToken> streamMessage({
    required List<ChatMessage> messages,
    ModelRequestOptions? extraParams,
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
    ModelRequestOptions? extraParams,
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
    for (var attempt = 1; attempt <= _retryPolicy.maxAttempts; attempt++) {
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
        final willRetry = !outputStarted && _retryPolicy.shouldRetry(attempt);
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
        await Future<void>.delayed(_retryPolicy.delayForAttempt(attempt));
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
      final parser = ChatSseParser(chatUri);
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
    required ModelRequestOptions? extraParams,
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
        extraParams: extraParams ?? const ModelRequestOptions.empty(),
      ),
      onSnapshot: _onDiagnostics,
    );
    tracker.initialisePriority(inputTokensHint != null);
    tracker.emit();
    return tracker;
  }

  Map<String, dynamic> _streamBody({
    required List<ChatMessage> messages,
    required ModelRequestOptions? extraParams,
  }) {
    final body = <String, dynamic>{
      ..._encodeRequestOptions(extraParams),
      'model': _model,
      'messages': messages.map(_chatMessageWireAdapter.encode).toList(),
      'stream': true,
    };
    final callerOptions = extraParams?.streamOptions?.custom;
    final streamOptions = <String, dynamic>{
      for (final option in callerOptions ?? const <ModelStreamOption>[])
        option.name: option.value,
      'include_usage': true,
    };
    body['stream_options'] = streamOptions;
    if (_liveDiagnosticsEnabled()) {
      body['timings_per_token'] = true;
      body['return_progress'] = true;
    }
    return body;
  }

  @override
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
        return decoded is Map
            ? const ChatModelPropertyDecoder().decode(decoded)
            : null;
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
    for (var attempt = 1; attempt <= _retryPolicy.maxAttempts; attempt++) {
      try {
        cancellationToken?.throwIfCancelled();
        return await _withClient(operation, cancellationToken);
      } catch (error, stackTrace) {
        cancellationToken?.throwIfCancelled();
        final kind = _transportKind(error);
        if (kind == null) rethrow;
        final willRetry = _retryPolicy.shouldRetry(attempt);
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
        await Future<void>.delayed(_retryPolicy.delayForAttempt(attempt));
        cancellationToken?.throwIfCancelled();
      }
    }
    throw StateError('Unreachable retry state');
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

  @override
  Future<int> countInputTokens({
    required List<ChatMessage> messages,
    ModelRequestOptions? extraParams,
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();

    final uri = Uri.parse('$_baseUrl/v1/chat/completions/input_tokens');
    final body = {
      'model': _model,
      'messages': messages.map(_chatMessageWireAdapter.encode).toList(),
      ..._encodeRequestOptions(extraParams),
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

Map<String, dynamic> _encodeRequestOptions(ModelRequestOptions? options) {
  if (options == null || options.isEmpty) return const {};

  return {
    if (options.addGenerationPrompt != null)
      'add_generation_prompt': options.addGenerationPrompt,
    if (options.tools.isNotEmpty)
      'tools': [
        for (final tool in options.tools)
          {
            'type': 'function',
            'function': {
              'name': tool.id,
              'description': tool.description,
              'parameters': tool.schema.toWire(),
            },
          },
      ],
    if (options.toolChoice != null) 'tool_choice': options.toolChoice,
    if (options.maxTokens != null) 'max_tokens': options.maxTokens,
    if (options.temperature != null) 'temperature': options.temperature,
    if (options.chatTemplate != null)
      'chat_template_kwargs': {
        if (options.chatTemplate!.enableThinking != null)
          'enable_thinking': options.chatTemplate!.enableThinking,
        if (options.chatTemplate!.reasoningBudget != null)
          'reasoning_budget': options.chatTemplate!.reasoningBudget,
      },
  };
}

class _StreamingToolCall {
  String? id;
  String? name;
  final StringBuffer arguments = StringBuffer();
}
