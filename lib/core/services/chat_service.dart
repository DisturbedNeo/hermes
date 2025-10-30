import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:hermes/core/enums/delete_choice.dart';
import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/enums/stream_state.dart';
import 'package:hermes/core/helpers/throttled_scheduler.dart';
import 'package:hermes/core/helpers/uuid.dart';
import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/models/chat_token.dart';
import 'package:hermes/core/models/tool_definition.dart';
import 'package:hermes/core/services/llama_server_manager.dart';
import 'package:hermes/core/services/service_provider.dart';
import 'package:hermes/core/services/tool_service.dart';

class ChatService extends ChangeNotifier {
  final LlamaServerManager serverManager = LlamaServerManager();
  final ToolService _toolService = serviceProvider.get<ToolService>();
  late final ThrottledScheduler _scheduler;

  final Bubble systemPrompt = Bubble(
    id: uuid.v7(),
    role: MessageRole.system,
    text: 'You are a helpful assistant.',
    reasoning: '',
  );

  UnmodifiableListView<Bubble>? _messageCache;
  UnmodifiableListView<Bubble> get messages =>
      _messageCache ??= UnmodifiableListView(_messages);
  final List<Bubble> _messages = [];

  final Map<String, Map<int, StringBuffer>> _toolBuffers = {};

  StreamState _streamState = StreamState.idle;
  StreamState get streamState => _streamState;
  set streamState(StreamState newState) {
    if (_streamState == newState) return;
    _streamState = newState;
    _notifyIfNotDisposed();
  }

  bool get isStreaming => _streamState == StreamState.streaming;

  StreamSubscription<ChatToken>? _streamSub;
  String? _currentAssistantId;
  int get _currentAssistantIndex =>
      _messages.indexWhere((m) => m.id == _currentAssistantId);

  bool _disposed = false;

  ChatService() {
    _scheduler = ThrottledScheduler(
      interval: const Duration(milliseconds: 33),
      onTick: () {
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
    double temperature,
    double topP,
    int topK,
    int batch,
    int uBatch,
    int mirostat,
  ) async {
    await serverManager.start(
      llamaCppDirectory: llamaCppDirectory,
      modelPath: modelPath,
      modelName: modelName,
      nCtx: contextSize,
      nThreads: numThreads,
      nGpuLayers: numGpuLayers,
      temperature: temperature,
      topP: topP,
      topK: topK,
      nBatch: batch,
      nUBatch: uBatch,
      mirostat: mirostat,
    );
  }

  void newChat() {
    if (streamState == StreamState.streaming) {
      stopStreaming();
    }

    _messages.clear();
    _messages.add(systemPrompt);

    _notifyIfNotDisposed();
  }

  void openChat(String id) {}

  void insertMessage(String text, MessageRole role) {
    if (isStreaming) return;

    final t = text.trim();

    if (t.isEmpty) return;

    _messages.add(Bubble(id: uuid.v7(), role: role, text: t, reasoning: ''));
    _notifyIfNotDisposed();
  }

  Future<void> send(String text, {List<String>? tools = const []}) async {
    if (isStreaming) return;

    final t = text.trim();
    if (t.isEmpty) return;

    _messages.add(
      Bubble(id: uuid.v7(), role: MessageRole.user, text: t, reasoning: ''),
    );
    _notifyIfNotDisposed();

    await _streamAssistantResponse(
      assistantId: null,
      addGenerationPrompt: true,
      selectedToolIds: tools ?? [],
    );
  }

  Future<void> generateOrContinue({List<String>? tools = const []}) async {
    if (isStreaming || _messages.isEmpty) return;

    await _streamAssistantResponse(
      assistantId: _messages.last.role == MessageRole.assistant
          ? _messages.last.id
          : null,
      addGenerationPrompt: _messages.last.role != MessageRole.assistant,
      selectedToolIds: tools ?? [],
    );
  }

  void setToolResultForMessage(String messageId, int index, String resultJson) {
    final msgIdx = _messages.indexWhere((m) => m.id == messageId);
    if (msgIdx == -1) return;

    final bubble = _messages[msgIdx];
    final tools = Map<int, BubbleToolCall>.from(bubble.tools);
    final existing = tools[index];
    if (existing == null) return;

    tools[index] = existing.copyWith(
      arguments: '${existing.arguments}\n→ result: $resultJson',
    );

    _messages[msgIdx] = bubble.copyWith(tools: tools);
    _notifyIfNotDisposed();
  }

  Future<void> stopStreaming({
    StreamState newStreamState = StreamState.idle,
  }) async {
    _scheduler.cancel();

    final sub = _streamSub;
    _streamSub = null;
    _currentAssistantId = null;

    await sub?.cancel();
    streamState = newStreamState;
  }

  void updateMessage(Bubble message, String newReasoning, String newText) {
    final index = _messages.indexWhere((m) => m.id == message.id);

    if (index == -1 || message.id == _currentAssistantId) return;

    _messages[index] = _messages[index].copyWith(
      reasoning: newReasoning,
      text: newText,
    );

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
    List<String> selectedToolIds = const [],
  }) async {
    if (isStreaming) return;
    final client = serverManager.chatClient;
    if (client == null) return;

    streamState = StreamState.streaming;

    final targetId = _ensureAssistantTarget(assistantId);
    final targetIndex = _messages.indexWhere((m) => m.id == targetId);

    final payload = _buildPayload(upToIndexInclusive: targetIndex);

    final List<ToolDefinition> selectedTools = _resolveToolDefinitions(
      selectedToolIds,
    );
    final openAITools = selectedTools.map((t) {
      return {
        'type': 'function',
        'function': {
          'name': t.id,
          'description': t.description,
          'parameters': t.schema,
        },
      };
    }).toList();

    final extraParams = {
      if (addGenerationPrompt) 'add_generation_prompt': true,
      if (openAITools.isNotEmpty) 'tools': openAITools,
      if (openAITools.isNotEmpty) 'tool_choice': 'auto',
    };

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

  void _onStreamToken(ChatToken token) {
    if (token.tool != null) {
      _appendToolDeltaToCurrentAssistant(token.tool!);
      _scheduler.schedule();
      return;
    }

    if (token.reasoning != null) {
      _appendToCurrentAssistant(token.reasoning!, true);
    } else if (token.content != null) {
      _appendToCurrentAssistant(token.content!, false);
    } else {
      return;
    }

    _scheduler.schedule();
  }

  void _handleStreamTerminal({Object? error}) {
    _scheduler.cancel();

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

  List<ToolDefinition> _resolveToolDefinitions(List<String> ids) {
    if (ids.isEmpty) return const [];
    return _toolService.getToolDefinitions(ids: ids);
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
        Bubble(
          id: uuid.v7(),
          role: MessageRole.assistant,
          text: err,
          reasoning: '',
        ),
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
        reasoning: '',
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
          reasoning: '',
        );
        _messages.add(bubble);
        targetId = bubble.id;
        _notifyIfNotDisposed();
      }
    }

    _currentAssistantId = targetId;

    return targetId;
  }

  void _appendToCurrentAssistant(String chunk, bool isReasoning) {
    if (chunk.isEmpty) return;

    final index = _currentAssistantIndex;

    if (index < 0 || index >= _messages.length) return;

    if (isReasoning) {
      _messages[index] = _messages[index].copyWith(
        reasoning: _messages[index].reasoning + chunk,
      );
    } else {
      _messages[index] = _messages[index].copyWith(
        text: _messages[index].text + chunk,
      );
    }
  }

  void _appendToolDeltaToCurrentAssistant(ToolCallDelta delta) {
    final idx = _currentAssistantIndex;
    if (idx < 0 || idx >= _messages.length) return;

    final bubble = _messages[idx];
    final bubbleId = bubble.id;

    final buffersForMsg = _toolBuffers.putIfAbsent(
      bubbleId,
      () => <int, StringBuffer>{},
    );

    final buf = buffersForMsg.putIfAbsent(delta.index, () => StringBuffer());

    if (delta.argumentsChunk != null && delta.argumentsChunk!.isNotEmpty) {
      buf.write(delta.argumentsChunk);
    }

    final currentTools = Map<int, BubbleToolCall>.from(bubble.tools);
    final existing = currentTools[delta.index];

    final updatedTool = (existing ?? BubbleToolCall()).copyWith(
      id: delta.id ?? existing?.id,
      name: delta.name ?? existing?.name,
      arguments: buf.toString(),
    );

    currentTools[delta.index] = updatedTool;

    _messages[idx] = bubble.copyWith(tools: currentTools);
  }

  List<ChatMessage> _buildPayload({required int upToIndexInclusive}) {
    if (_messages.isEmpty || upToIndexInclusive < 0) {
      return [];
    }

    final clamped = upToIndexInclusive.clamp(0, _messages.length - 1);
    final conversation = _messages.take(clamped + 1);

    final payload = conversation
        .map((m) => ChatMessage(role: m.role.wire, content: m.text))
        .toList();

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
