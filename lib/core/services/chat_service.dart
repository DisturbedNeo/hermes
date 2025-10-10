import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:hermes/core/enums/delete_choice.dart';
import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/enums/stream_state.dart';
import 'package:hermes/core/helpers/throttled_scheduler.dart';
import 'package:hermes/core/helpers/utf_16_stream_assembler.dart';
import 'package:hermes/core/helpers/uuid.dart';
import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/services/llama_server_manager.dart';

class ChatService extends ChangeNotifier {
  final LlamaServerManager serverManager = LlamaServerManager();
  late final Utf16StreamAssembler _assembler;
  late final ThrottledScheduler _scheduler;

  final Bubble systemPrompt = Bubble(
    id: uuid.v7(),
    role: MessageRole.system,
    text: 'You are a helpful assistant.',
  );

  UnmodifiableListView<Bubble>? _messageCache;
  UnmodifiableListView<Bubble> get messages => _messageCache ??= UnmodifiableListView(_messages);
  final List<Bubble> _messages = [];

  StreamState _streamState = StreamState.idle;
  StreamState get streamState => _streamState;
  set streamState(StreamState newState) {
    if (_streamState == newState) return;
    _streamState = newState;
    _notifyIfNotDisposed();
  }

  bool get isStreaming => _streamState == StreamState.streaming;

  StreamSubscription<String>? _streamSub;
  String? _currentAssistantId;
  int get _currentAssistantIndex =>
      _messages.indexWhere((m) => m.id == _currentAssistantId);

  bool _disposed = false;

  ChatService() {
    _assembler = Utf16StreamAssembler(onChunk: _appendToCurrentAssistant);
    _scheduler = ThrottledScheduler(
      interval: const Duration(milliseconds: 33),
      onTick: () {
        _assembler.flush();
        _notifyIfNotDisposed();
      },
    );
    _messages.add(systemPrompt);
  }

  Future<void> startServer(
    String llamaCppDirectory,
    String modelPath,
    String modelName,
    int contextSize,
    int numThreads,
    int numGpuLayers,
  ) async {
    await serverManager.start(
      llamaCppDirectory: llamaCppDirectory,
      modelPath: modelPath,
      modelName: modelName,
      nCtx: contextSize,
      nThreads: numThreads,
      nGpuLayers: numGpuLayers,
    );
  }

  Future<void> send(String text) async {
    if (isStreaming) return;

    final t = text.trim();

    if (t.isEmpty) return;

    _messages.add(Bubble(id: uuid.v7(), role: MessageRole.user, text: t));
    _notifyIfNotDisposed();

    await _streamAssistantResponse(assistantId: null);
  }

  Future<void> generateOrContinue() async {
    if (isStreaming || _messages.isEmpty) return;

    await _streamAssistantResponse(
      assistantId: _messages.last.role == MessageRole.assistant
          ? _messages.last.id
          : null,
      addGenerationPrompt: _messages.last.role != MessageRole.user,
    );
  }

  Future<void> stopStreaming({
    StreamState newStreamState = StreamState.idle,
  }) async {
    _scheduler.cancel();
    _assembler.flush();
    _assembler.clear();

    final sub = _streamSub;
    _streamSub = null;
    _currentAssistantId = null;

    await sub?.cancel();
    streamState = newStreamState;
  }

  void updateMessage(Bubble message, String newText) {
    final index = _messages.indexWhere((m) => m.id == message.id);

    if (index == -1 || message.id == _currentAssistantId) return;

    _messages[index] = _messages[index].copyWith(text: newText);

    _notifyIfNotDisposed();
  }

  void deleteMessages(
    String messageId, {
    DeleteChoice deleteChoice = DeleteChoice.thisOnly,
  }) {
    final index = _messages.indexWhere((m) => m.id == messageId);

    if (index == -1 ||
        messageId == _currentAssistantId ||
        (isStreaming && deleteChoice == DeleteChoice.includeSubsequent)) {
      return;
    }

    switch (deleteChoice) {
      case DeleteChoice.thisOnly:
        _messages.removeAt(index);
        break;
      case DeleteChoice.includeSubsequent:
        _messages.removeRange(index, _messages.length);
        break;
    }

    _notifyIfNotDisposed();
  }

  Future<void> _streamAssistantResponse({
    required String? assistantId,
    bool addGenerationPrompt = false,
  }) async {
    if (isStreaming) return;
    final client = serverManager.chatClient;
    if (client == null) return;

    streamState = StreamState.streaming;

    final targetId = _ensureAssistantTarget(assistantId);
    final targetIndex = _messages.indexWhere((m) => m.id == targetId);

    final upToIndexInclusive =
        (targetIndex >= 0 &&
            _messages[targetIndex].role == MessageRole.assistant)
        ? targetIndex - 1
        : targetIndex;

    final payload = _buildPayload(upToIndexInclusive: upToIndexInclusive);

    final extraParams = {
      if (addGenerationPrompt) 'add_generation_prompt': true,
    };

    _assembler.clear();
    _scheduler.cancel();

    final sub = client.streamMessage(
      messages: payload,
      extraParams: extraParams,
    );
    _streamSub = sub.listen(
      _onStreamToken,
      onError: (e, st) => _handleStreamTerminal(error: e),
      onDone: () => _handleStreamTerminal(),
      cancelOnError: true,
    );

    try {
      await _streamSub?.asFuture<void>();
      await stopStreaming();
    } catch (_) {
      await stopStreaming(newStreamState: StreamState.error);
    }
  }

  void _onStreamToken(String token) {
    if (token.isEmpty) return;

    _assembler.add(token);
    _scheduler.schedule();
  }

  void _handleStreamTerminal({Object? error}) {
    _scheduler.cancel();
    _assembler.flush();
    _assembler.clear();

    if (error != null) {
      _appendErrorToCurrentAssistant(error);
      streamState = StreamState.error;
    } else {
      streamState = StreamState.idle;
    }

    final sub = _streamSub;
    _streamSub = null;
    _currentAssistantId = null;
    sub?.cancel();

    _notifyIfNotDisposed();
  }

  void _appendErrorToCurrentAssistant(Object e) {
    final index = _currentAssistantIndex;
    final err = '\n\n Something went wrong: \n$e';
    if (index >= 0 &&
        index < _messages.length &&
        _messages[index].role == MessageRole.assistant) {
      _messages[index] = _messages[index].copyWith(
        text: _messages[index].text + err,
      );
    } else {
      _messages.add(
        Bubble(id: uuid.v7(), role: MessageRole.assistant, text: err),
      );
    }
  }

  String _ensureAssistantTarget(String? assistantId) {
    String? targetId = assistantId;

    if (targetId == null) {
      final bubble = Bubble(
        id: uuid.v7(),
        role: MessageRole.assistant,
        text: '',
      );
      _messages.add(bubble);
      targetId = bubble.id;
      _notifyIfNotDisposed();
    } else {
      final index = _messages.indexWhere((m) => m.id == targetId);
      if (index == -1 || _messages[index].role != MessageRole.assistant) {
        final bubble = Bubble(
          id: uuid.v7(),
          role: MessageRole.assistant,
          text: '',
        );
        _messages.add(bubble);
        targetId = bubble.id;
        _notifyIfNotDisposed();
      }
    }

    _currentAssistantId = targetId;

    return targetId;
  }

  void _appendToCurrentAssistant(String chunk) {
    if (chunk.isEmpty) return;

    final index = _currentAssistantIndex;

    if (index < 0 || index >= _messages.length) return;

    _messages[index] = _messages[index].copyWith(
      text: _messages[index].text + chunk,
    );
  }

  List<ChatMessage> _buildPayload({required int upToIndexInclusive}) {
    if (_messages.isEmpty || upToIndexInclusive < 0) {
      return [
        systemPrompt,
      ].map((m) => ChatMessage(role: m.role.wire, content: m.text)).toList();
    }

    final clamped = upToIndexInclusive.clamp(0, _messages.length - 1);
    final conversation = _messages.take(clamped + 1);

    final payload = [
      systemPrompt,
      ...conversation,
    ].map((m) => ChatMessage(role: m.role.wire, content: m.text)).toList();

    if (payload.isNotEmpty &&
        payload.last.role == MessageRole.assistant.wire &&
        payload.last.content.isEmpty) {
      payload.removeLast();
    }

    return payload;
  }

  void _notifyIfNotDisposed() {
    _messageCache = null;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    unawaited(stopStreaming());
    serverManager.dispose();
    _disposed = true;
    super.dispose();
  }
}
