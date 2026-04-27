import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/enums/stream_state.dart';
import 'package:hermes/core/services/chat/chat_stream.dart';
import 'package:hermes/core/helpers/uuid.dart';
import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/core/models/chat_message.dart';
import 'package:hermes/core/models/chat_token.dart';
import 'package:hermes/core/models/model_configuration_snapshot.dart';
import 'package:hermes/core/models/saved_chat.dart';
import 'package:hermes/core/helpers/chat/assistant_ops.dart';
import 'package:hermes/core/helpers/chat/content_normaliser.dart';
import 'package:hermes/core/services/chat/chat_library_service.dart';
import 'package:hermes/core/services/chat/message_store.dart';
import 'package:hermes/core/helpers/chat/tool_caller.dart';
import 'package:hermes/core/services/llama_server_manager.dart';
import 'package:hermes/core/helpers/chat/payload_builder.dart';
import 'package:hermes/core/services/service_provider.dart';
import 'package:hermes/core/services/tool_service.dart';

class ChatService extends ChangeNotifier {
  final LlamaServerManager serverManager = LlamaServerManager();
  final MessageStore messageStore = MessageStore();
  final ChatStream chatStream = ChatStream<ChatToken>();

  final ToolService _toolService = serviceProvider.get<ToolService>();
  final ChatLibraryService _chatLibrary = serviceProvider
      .get<ChatLibraryService>();

  final Bubble systemPrompt = Bubble(
    id: uuid.v7(),
    role: MessageRole.system,
    text: 'You are a helpful assistant.',
    reasoning: '',
  );

  bool _disposed = false;
  bool _loadingSnapshot = false;
  bool _dirty = false;
  Timer? _autosaveTimer;
  Future<void> _saveChain = Future.value();

  String? currentChatId;
  SavedChat? currentSavedChat;
  ModelConfigurationSnapshot? currentModelSnapshot;
  ModelConfigurationSnapshot? pendingModelRestore;
  String? pendingModelRestoreIssue;

  ChatService() {
    messageStore.setMessages([systemPrompt]);
    messageStore.addListener(_handleMessagesChanged);
    chatStream.onStop = serverManager.diagnostics.recordStreamEnded;
  }

  Future<void> newChat() async {
    await flushCurrentChat();

    if (chatStream.isStreaming) {
      messageStore.clearCurrentId();
      await chatStream.stop();
    }

    _clearSavedState();
    messageStore.setMessages([systemPrompt]);
  }

  Future<void> openChat(String id) async {
    await flushCurrentChat();

    if (chatStream.isStreaming) {
      messageStore.clearCurrentId();
      await chatStream.stop();
    }

    final snapshot = await _chatLibrary.getChat(id);
    if (snapshot == null) return;

    _loadingSnapshot = true;
    try {
      currentChatId = snapshot.chat.id;
      currentSavedChat = snapshot.chat;
      _dirty = false;
      messageStore.setMessages(snapshot.messages);
      await _chatLibrary.markOpened(snapshot.chat.id);
      await _prepareModelRestorePrompt(snapshot.chat.modelSnapshot);
    } finally {
      _loadingSnapshot = false;
    }

    notifyListeners();
  }

  Future<SavedChat> saveCurrentChat({String? title}) async {
    return _queueSave(title: title, force: true);
  }

  Future<void> deleteSavedChat(String chatId) async {
    await _chatLibrary.deleteChat(chatId);
    if (currentChatId == chatId) {
      _clearSavedState();
      await newChat();
    }
  }

  Future<void> flushCurrentChat() async {
    _autosaveTimer?.cancel();
    _autosaveTimer = null;
    if (currentChatId != null && _dirty) {
      await _queueSave(force: true);
    }
    await _saveChain;
  }

  void setCurrentModelSnapshot(ModelConfigurationSnapshot snapshot) {
    currentModelSnapshot = snapshot;
    _updateContextEstimate();
    if (currentChatId != null) {
      _dirty = true;
      _scheduleAutosave();
    }

    if (pendingModelRestore?.matches(snapshot) ?? false) {
      pendingModelRestore = null;
      pendingModelRestoreIssue = null;
    }

    notifyListeners();
  }

  Future<void> restorePendingModel() async {
    final snapshot = pendingModelRestore;
    if (snapshot == null) return;

    if (!await File(snapshot.modelPath).exists()) {
      throw FlutterError('Saved model file not found: ${snapshot.modelPath}');
    }

    pendingModelRestore = null;
    pendingModelRestoreIssue = null;
    notifyListeners();

    await serverManager.startWithSnapshot(snapshot);
    setCurrentModelSnapshot(snapshot);
  }

  void dismissPendingModelRestore() {
    pendingModelRestore = null;
    pendingModelRestoreIssue = null;
    notifyListeners();
  }

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
        ? PayloadBuilder.buildPayloadWithTools(
            messages: messageStore.messages,
            upToIndexInclusive: contextIndex,
          )
        : PayloadBuilder.buildPayload(
            messages: messageStore.messages,
            upToIndexInclusive: contextIndex,
          );

    serverManager.diagnostics.recordStreamStarted(
      estimatedContextTokens: _estimateContextTokens(payload),
    );

    final sub = client.streamMessage(
      messages: payload,
      extraParams: extraParams,
    );

    chatStream.attach(
      sub.listen(
        _handleStreamToken,
        onError: (e, _) async => await _handleStreamTerminal(error: e),
        onDone: () async => await _handleStreamTerminal(),
        cancelOnError: true,
      ),
    );
  }

  void _handleStreamToken(ChatToken token) {
    serverManager.diagnostics.recordStreamOutput(_streamedText(token));
    messageStore.appendToken(token);
  }

  int _estimateContextTokens(List<ChatMessage> messages) {
    var characters = 0;

    for (final message in messages) {
      characters += message.content.length;
    }

    return (characters / 4).ceil();
  }

  String _streamedText(ChatToken token) {
    return [
      token.content,
      token.reasoning,
      token.tool?.name,
      token.tool?.argumentsChunk,
    ].whereType<String>().join();
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

    await _streamAssistantResponse(
      includeToolResults: true,
      addGenerationPrompt: false,
      selectedToolIds: const [],
      anchorId: assistantBubble.id,
    );
  }

  Future<void> _handleStreamTerminal({Object? error}) async {
    if (error != null) {
      serverManager.diagnostics.recordStreamError(error);
      messageStore.appendCurrentError(error);
      messageStore.clearCurrentId();
      await chatStream.stop(next: StreamState.error);
      return;
    }

    if (messageStore.currentMessage != null) {
      messageStore.upsert(
        ContentNormaliser.normalise(messageStore.currentMessage!),
      );
    }

    await chatStream.stop();
    serverManager.diagnostics.recordStreamEnded();

    final toolCalls = ToolCaller.extractToolCalls(messageStore.currentMessage);
    if (toolCalls.isNotEmpty) {
      try {
        await _runToolsAndContinue(toolCalls);
      } catch (e) {
        messageStore.appendCurrentError(e);
        messageStore.clearCurrentId();
        await chatStream.stop(next: StreamState.error);
      }

      return;
    }

    messageStore.clearCurrentId();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;

    messageStore.removeListener(_handleMessagesChanged);
    _autosaveTimer?.cancel();
    await flushCurrentChat();
    _disposed = true;
    messageStore.clearCurrentId();
    try {
      await chatStream.stop();
    } finally {
      await serverManager.dispose();
      super.dispose();
    }
  }

  void _handleMessagesChanged() {
    _updateContextEstimate();
    if (_disposed || _loadingSnapshot || currentChatId == null) return;
    _dirty = true;
    _scheduleAutosave();
  }

  void _updateContextEstimate() {
    final snapshot = currentModelSnapshot;
    if (snapshot == null || messageStore.messages.isEmpty) {
      serverManager.diagnostics.updateContextEstimate(null);
      return;
    }

    final payload = PayloadBuilder.buildPayloadWithTools(
      messages: messageStore.messages,
      upToIndexInclusive: messageStore.messages.length - 1,
    );
    serverManager.diagnostics.updateContextEstimate(
      _estimateContextTokens(payload),
    );
  }

  void _scheduleAutosave() {
    _autosaveTimer?.cancel();
    _autosaveTimer = Timer(
      const Duration(milliseconds: 600),
      () => unawaited(_queueSave(force: true)),
    );
  }

  Future<SavedChat> _queueSave({String? title, bool force = false}) {
    _autosaveTimer?.cancel();
    _autosaveTimer = null;

    final completer = Completer<SavedChat>();

    final operation = _saveChain.then((_) async {
      if (_disposed) {
        throw StateError('ChatService is disposed');
      }

      if (!force && currentChatId != null && !_dirty) {
        return currentSavedChat!;
      }

      final saved = await _chatLibrary.saveChatSnapshot(
        chatId: currentChatId,
        title: title,
        messages: messageStore.messages.toList(),
        modelSnapshot: currentModelSnapshot,
      );

      currentChatId = saved.id;
      currentSavedChat = saved;
      _dirty = false;
      notifyListeners();
      return saved;
    });

    _saveChain = operation.then<void>((_) {});
    operation.then(completer.complete, onError: completer.completeError);
    return completer.future;
  }

  Future<void> _prepareModelRestorePrompt(
    ModelConfigurationSnapshot? snapshot,
  ) async {
    pendingModelRestore = null;
    pendingModelRestoreIssue = null;

    if (snapshot == null || snapshot.matches(currentModelSnapshot)) return;

    pendingModelRestore = snapshot;
    if (!await File(snapshot.modelPath).exists()) {
      pendingModelRestoreIssue =
          'Saved model file not found: ${snapshot.modelPath}';
    }
  }

  void _clearSavedState() {
    currentChatId = null;
    currentSavedChat = null;
    pendingModelRestore = null;
    pendingModelRestoreIssue = null;
    _dirty = false;
    notifyListeners();
  }
}
