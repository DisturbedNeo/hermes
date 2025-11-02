import 'dart:async';
import 'dart:collection';
import 'dart:convert';

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

    await _finaliseStream();

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
      onError: (e, st) async => await _handleStreamTerminal(error: e),
      onDone: () async => await _handleStreamTerminal(),
      cancelOnError: true,
    );
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

  Future<void> _handleStreamTerminal({Object? error}) async {
    _scheduler.cancel();

    if (error != null) {
      _appendErrorToCurrentAssistant(error);
      streamState = StreamState.error;
      await _finaliseStream();
      return;
    }

    _normaliseAssistantContent();

    final toolCalls = _extractToolCallsFromCurrentAssistant();
    if (toolCalls.isNotEmpty) {
      try {
        await _runToolsAndContinue(toolCalls);
      } catch (e) {
        _appendErrorToCurrentAssistant(e);
        streamState = StreamState.error;
        await _finaliseStream();
      }

      return;
    }

    streamState = StreamState.idle;
    await _finaliseStream();
  }

  List<BubbleToolCall> _extractToolCallsFromCurrentAssistant() {
    final index = _currentAssistantIndex;
    if (index < 0 || index >= _messages.length) return const [];

    final bubble = _messages[index];
    if (bubble.tools.isEmpty) return const [];

    final calls =
        bubble.tools.entries.where((t) => t.value.result == null).toList()
          ..sort((a, b) => a.key.compareTo(b.key));

    return calls.map((c) => c.value).toList();
  }

  Future<void> _runToolsAndContinue(List<BubbleToolCall> calls) async {
    final idx = _currentAssistantIndex;
    if (idx < 0 || idx >= _messages.length) {
      await _finaliseStream();
      return;
    }

    final assistantBubble = _messages[idx];
    final Map<int, BubbleToolCall> updated = Map.of(assistantBubble.tools);

    for (final entry in assistantBubble.tools.entries) {
      final toolIndex = entry.key;
      final toolCall = entry.value;

      final toolName = toolCall.name;
      final argsJson = toolCall.arguments;

      if (toolName == null || argsJson == null) {
        updated[toolIndex] = toolCall.copyWith(
          result: '{"error":"missing tool name or args"}',
        );
        continue;
      }

      final resultJson = await _toolService.execute(
        toolId: toolName,
        argumentsJson: argsJson,
      );

      updated[toolIndex] = toolCall.copyWith(result: resultJson);
    }

    _messages[idx] = assistantBubble.copyWith(tools: updated);

    final toolDisplay = _buildReadableToolResult(updated);

    if (toolDisplay.isNotEmpty) {
      _messages.add(
        Bubble(
          id: uuid.v7(),
          role: MessageRole.assistant,
          text: toolDisplay,
          reasoning: '',
        ),
      );
    }

    _notifyIfNotDisposed();

    await _continueAfterTools(_messages[idx]);
  }

  Future<void> _continueAfterTools(Bubble assistantBubble) async {
    final client = serverManager.chatClient;
    if (client == null) {
      streamState = StreamState.idle;
      await _finaliseStream();
      return;
    }

    streamState = StreamState.streaming;

    final followUp = Bubble(
      id: uuid.v7(),
      role: MessageRole.assistant,
      text: '',
      reasoning: '',
    );
    _messages.add(followUp);
    _currentAssistantId = followUp.id;
    _notifyIfNotDisposed();

    final targetIndex = _messages.indexWhere((m) => m.id == assistantBubble.id);
    final payload = _buildPayloadWithTools(targetIndex);

    final sub = client.streamMessage(messages: payload);

    _streamSub = sub.listen(
      _onStreamToken,
      onError: (e, st) => _handleStreamTerminal(error: e),
      onDone: () => _handleStreamTerminal(),
      cancelOnError: true,
    );
  }

  List<ToolDefinition> _resolveToolDefinitions(List<String> ids) {
    if (ids.isEmpty) return const [];
    return _toolService.getToolDefinitions(ids: ids);
  }

  String _buildReadableToolResult(Map<int, BubbleToolCall> tools) {
    final sb = StringBuffer();
    for (final entry in tools.entries) {
      final tc = entry.value;
      if (tc.result == null) continue;
      final name = tc.name ?? 'tool';
      sb.writeln('🔧 **$name**');
      sb.writeln(tc.result);
      sb.writeln();
    }
    return sb.toString().trim();
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

  void _normaliseAssistantContent() {
    final idx = _currentAssistantIndex;
    if (idx < 0 || idx >= _messages.length) return;

    final bubble = _messages[idx];
    if (bubble.role != MessageRole.assistant) return;

    final raw = bubble.text;

    if (raw.isEmpty) return;

    String remaining = raw;
    String reasoning = bubble.reasoning;

    final thinkRegex = RegExp(r'<think>([\s\S]*?)</think>', multiLine: true);
    final thinkMatch = thinkRegex.firstMatch(remaining);

    if (thinkMatch != null) {
      final thinkContent = thinkMatch.group(1)?.trim() ?? '';
      reasoning = ('$reasoning\n$thinkContent').trim();
      remaining = remaining
          .replaceRange(thinkMatch.start, thinkMatch.end, '')
          .trim();
    }

    final toolsMap = Map<int, BubbleToolCall>.from(bubble.tools);
    var toolIndex = toolsMap.length;

    final xmlToolRegex = RegExp(
      r'<tool_call>([\s\S]*?)</tool_call>',
      multiLine: true,
    );
    final xmlToolMatches = xmlToolRegex.allMatches(remaining).toList();

    for (final m in xmlToolMatches) {
      final inner = m.group(1) ?? '';
      final parsed = _parseXmlToolCallBody(inner);
      if (parsed != null) {
        toolsMap[toolIndex++] = parsed;
      }
    }

    remaining = remaining.replaceAll(xmlToolRegex, '').trim();

    _messages[idx] = bubble.copyWith(
      reasoning: reasoning,
      text: remaining,
      tools: toolsMap,
    );
  }

  BubbleToolCall? _parseXmlToolCallBody(String body) {
    final lines = body
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return null;

    final toolName = lines.first;
    final rest = lines.skip(1).join('\n');

    final keyRegex = RegExp(r'<arg_key>([^<]+)</arg_key>');
    final valRegex = RegExp(r'<arg_value>([^<]+)</arg_value>');

    final keyMatches = keyRegex.allMatches(rest).toList();
    final valMatches = valRegex.allMatches(rest).toList();

    final args = <String, String>{};
    final len = keyMatches.length < valMatches.length
        ? keyMatches.length
        : valMatches.length;

    for (var i = 0; i < len; i++) {
      final k = keyMatches[i].group(1)?.trim();
      final v = valMatches[i].group(1)?.trim();
      if (k != null && v != null) {
        args[k] = v;
      }
    }

    return BubbleToolCall(name: toolName, arguments: jsonEncode(args));
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

  List<ChatMessage> _buildPayloadWithTools(int upToIndexInclusive) {
    final clamped = upToIndexInclusive.clamp(0, _messages.length - 1);
    final conversation = _messages.take(clamped + 1);

    final result = <ChatMessage>[];

    for (final b in conversation) {
      if (b.role == MessageRole.assistant && b.tools.isNotEmpty) {
        final toolCalls = b.tools.entries.map((entry) {
          final index = entry.key;
          final tc = entry.value;
          final callId = tc.id ?? 'call_$index';
          return {
            'id': callId,
            'type': 'function',
            'function': {'name': tc.name, 'arguments': tc.arguments ?? '{}'},
          };
        }).toList();

        result.add(
          ChatMessage(
            role: 'assistant',
            content: b.text.isEmpty ? '' : b.text,
            toolCalls: toolCalls,
          ),
        );

        for (MapEntry<int, BubbleToolCall> entry in b.tools.entries) {
          final index = entry.key;
          final tc = entry.value;
          final callId = tc.id ?? 'call_$index';
          if (tc.result == null) continue;

          result.add(
            ChatMessage(
              role: 'tool',
              content: tc.result ?? '',
              toolCallId: callId,
            ),
          );
        }

        continue;
      }

      result.add(ChatMessage(role: b.role.wire, content: b.text));
    }

    return result;
  }

  Future<void> _finaliseStream() async {
    final sub = _streamSub;
    _streamSub = null;

    if (_currentAssistantId != null) {
      _toolBuffers.remove(_currentAssistantId);
    }

    _currentAssistantId = null;
    await sub?.cancel();

    _notifyIfNotDisposed();
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
