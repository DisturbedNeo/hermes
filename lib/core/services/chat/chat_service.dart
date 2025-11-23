import 'dart:async';

import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/enums/stream_state.dart';
import 'package:hermes/core/services/chat/chat_stream.dart';
import 'package:hermes/core/helpers/uuid.dart';
import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/core/models/chat_token.dart';
import 'package:hermes/core/helpers/chat/assistant_ops.dart';
import 'package:hermes/core/helpers/chat/content_normaliser.dart';
import 'package:hermes/core/services/chat/message_store.dart';
import 'package:hermes/core/helpers/chat/tool_caller.dart';
import 'package:hermes/core/services/llama_server_manager.dart';
import 'package:hermes/core/helpers/chat/payload_builder.dart';
import 'package:hermes/core/services/service_provider.dart';
import 'package:hermes/core/services/tool_service.dart';

class ChatService {
  final LlamaServerManager serverManager = LlamaServerManager();
  final MessageStore messageStore = MessageStore();
  final ChatStream chatStream = ChatStream<ChatToken>();

  final ToolService _toolService = serviceProvider.get<ToolService>();

  final Bubble systemPrompt = Bubble(
    id: uuid.v7(),
    role: MessageRole.system,
    text: 'You are a helpful assistant.',
    reasoning: '',
  );

  bool _disposed = false;

  ChatService() {
    messageStore.setMessages([systemPrompt]);
  }

  Future<void> newChat() async {
    if (chatStream.isStreaming) {
      messageStore.clearCurrentId();
      await chatStream.stop();
    }

    messageStore.setMessages([systemPrompt]);
  }

  void openChat(String id) {}

  void insertMessage(String text, MessageRole role) {
    if (chatStream.isStreaming) return;

    final t = text.trim();

    if (t.isEmpty) return;

    messageStore.upsert(
      Bubble(id: uuid.v7(), role: role, text: t, reasoning: ''),
    );
  }

  Future<void> send(String text, {List<String>? tools = const []}) async {
    if (chatStream.isStreaming) return;

    final t = text.trim();
    if (t.isEmpty) return;

    messageStore.upsert(
      Bubble(id: uuid.v7(), role: MessageRole.user, text: t, reasoning: ''),
    );

    await _streamAssistantResponse(
      includeToolResults: false,
      addGenerationPrompt: true,
      selectedToolIds: tools ?? const [],
      anchorId: null,
    );
  }

  Future<void> generateOrContinue({List<String>? tools = const []}) async {
    if (chatStream.isStreaming || messageStore.isEmpty) return;

    final lastMessage = messageStore.last;

    await _streamAssistantResponse(
      includeToolResults: false,
      addGenerationPrompt: lastMessage.role != MessageRole.assistant,
      selectedToolIds: tools ?? const [],
      anchorId: null,
    );
  }

  Future<void> _streamAssistantResponse({
    required bool includeToolResults,
    required bool addGenerationPrompt,
    List<String> selectedToolIds = const [],
    String? anchorId,
  }) async {
    if (chatStream.isStreaming) return;
    final client = serverManager.chatClient;
    if (client == null) return;

    chatStream.setState(StreamState.streaming);

    final bubble = Bubble(
      id: uuid.v7(),
      role: MessageRole.assistant,
      text: '',
      reasoning: '',
    );
    messageStore.upsert(bubble);
    messageStore.setCurrentId(bubble.id);

    final contextIndex = () {
      if (anchorId != null) {
        final index = messageStore.messages.indexWhere((m) => m.id == anchorId);
        return index > 0 ? (messageStore.messages.length - 2) : index;
      }
      return messageStore.messages.length - 2;
    }();

    final extraParams = ToolCaller.buildExtraParams(
      addGenerationPrompt: addGenerationPrompt, 
      toolDefs: selectedToolIds.isNotEmpty
        ? _toolService.getToolDefinitions(ids: selectedToolIds)
        : const [],
      );

    final payload = includeToolResults
      ? PayloadBuilder.buildPayloadWithTools(messages: messageStore.messages, upToIndexInclusive: contextIndex)
      : PayloadBuilder.buildPayload(messages: messageStore.messages, upToIndexInclusive: contextIndex);

    final sub = client.streamMessage(messages: payload, extraParams: extraParams);

    chatStream.attach(
      sub.listen(
        messageStore.appendToken,
        onError: (e, _) async => await _handleStreamTerminal(error: e),
        onDone: () async => await _handleStreamTerminal(),
        cancelOnError: true,
      )
    );
  }

  Future<void> _runToolsAndContinue(List<BubbleToolCall> calls) async {
    final assistantBubble = messageStore.currentMessage;

    if (assistantBubble == null) {
      messageStore.clearCurrentId();
      return;
    }

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

    messageStore.upsert(assistantBubble.copyWith(tools: updated));

    final toolDisplay = ToolCaller.buildReadableToolResult(updated);

    if (toolDisplay.isNotEmpty) {
      messageStore.upsert(
        Bubble(
          id: uuid.v7(),
          role: MessageRole.tool,
          text: toolDisplay,
          reasoning: '',
        ),
      );
    }

    await _streamAssistantResponse(
      includeToolResults: true, 
      addGenerationPrompt: false,
      selectedToolIds: const [],
      anchorId: assistantBubble.id,
    );
  }

  Future<void> _handleStreamTerminal({Object? error}) async {
    if (error != null) {
      messageStore.appendCurrentError(error);
      messageStore.clearCurrentId();
      chatStream.stop(next: StreamState.error);
      return;
    }

    if (messageStore.currentMessage != null) {
      messageStore.upsert(
        ContentNormaliser.normalise(messageStore.currentMessage!),
      );
    }

    chatStream.stop();

    final toolCalls = ToolCaller.extractToolCalls(messageStore.currentMessage);
    if (toolCalls.isNotEmpty) {
      try {
        await _runToolsAndContinue(toolCalls);
      } catch (e) {
        messageStore.appendCurrentError(e);
        messageStore.clearCurrentId();
        chatStream.stop(next: StreamState.error);
      }

      return;
    }

    messageStore.clearCurrentId();
  }

  void dispose() {
    if (_disposed) return;
    messageStore.clearCurrentId();
    chatStream.stop();
    serverManager.dispose();
    _disposed = true;
  }
}
