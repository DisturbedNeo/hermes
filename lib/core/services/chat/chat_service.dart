import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hermes/core/enums/message_role.dart';
import 'package:hermes/core/enums/stream_state.dart';
import 'package:hermes/core/services/chat/chat_stream.dart';
import 'package:hermes/core/helpers/chat/compaction_manager.dart';
import 'package:hermes/core/helpers/chat/context_estimator.dart';
import 'package:hermes/core/helpers/uuid.dart';
import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/core/models/chat_token.dart';
import 'package:hermes/core/models/model_configuration_snapshot.dart';
import 'package:hermes/core/models/saved_chat.dart';
import 'package:hermes/core/models/system_prompt.dart';
import 'package:hermes/core/models/workspace.dart';
import 'package:hermes/core/helpers/chat/assistant_ops.dart';
import 'package:hermes/core/helpers/chat/content_normaliser.dart';
import 'package:hermes/core/services/chat/chat_client.dart';
import 'package:hermes/core/services/chat/chat_library_service.dart';
import 'package:hermes/core/services/chat/message_store.dart';
import 'package:hermes/core/helpers/chat/tool_caller.dart';
import 'package:hermes/core/services/llama_server_manager.dart';
import 'package:hermes/core/services/preferences_service.dart';
import 'package:hermes/core/helpers/chat/payload_builder.dart';
import 'package:hermes/core/services/prompt_assembler.dart';
import 'package:hermes/core/services/tool_service.dart';
import 'package:hermes/core/services/workspace_service.dart';

class ChatService extends ChangeNotifier {
  static const String defaultSystemPromptName = 'Default';
  static const String defaultSystemPromptText = 'You are a helpful assistant.';

  final String tabId;
  final LlamaServerManager serverManager;
  final MessageStore messageStore = MessageStore();
  final ChatStream chatStream = ChatStream<ChatToken>();

  final ToolService _toolService;
  final ChatLibraryService _chatLibrary;
  final WorkspaceService _workspaceService;
  final PreferencesService _preferencesService;
  final PromptAssembler _promptAssembler = const PromptAssembler();

  late final Bubble systemPrompt = Bubble(
    id: uuid.v7(),
    role: MessageRole.system,
    text: _buildSystemPrompt(),
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
  WorkspaceAttachment? workspace;
  SystemPromptSnapshot? currentSystemPromptSnapshot;

  ChatService({
    String? tabId,
    required this.serverManager,
    required ToolService toolService,
    required ChatLibraryService chatLibrary,
    required WorkspaceService workspaceService,
    required PreferencesService preferencesService,
    SystemPromptSnapshot? initialSystemPromptSnapshot,
  }) : tabId = tabId ?? uuid.v7(),
       _toolService = toolService,
       _chatLibrary = chatLibrary,
       _workspaceService = workspaceService,
       _preferencesService = preferencesService {
    currentSystemPromptSnapshot = initialSystemPromptSnapshot;
    messageStore.setMessages([systemPrompt]);
    messageStore.addListener(_handleMessagesChanged);
    chatStream.onStop = serverManager.diagnostics.recordStreamEnded;
    currentModelSnapshot = _activeServerSnapshot;
  }

  bool get isDirty => _dirty;

  bool get hasMeaningfulContent => messageStore.messages.any(
    (message) =>
        message.role != MessageRole.system &&
        (message.text.trim().isNotEmpty ||
            message.reasoning.trim().isNotEmpty ||
            message.tools.isNotEmpty),
  );

  bool get isUnsavedNonEmpty => currentChatId == null && hasMeaningfulContent;

  bool get isSystemPromptLocked =>
      chatStream.isStreaming || hasMeaningfulContent || currentChatId != null;

  bool get hasActiveWorkspace =>
      workspace != null && workspace?.missing != true;

  bool get workspaceToolsEnabled => hasActiveWorkspace;

  List<String> get defaultToolIds => workspaceToolsEnabled
      ? _toolService.defaultToolIds(includeWorkspaceTools: true)
      : const [];

  String get displayTitle {
    final savedTitle = currentSavedChat?.title;
    if (savedTitle != null && savedTitle.trim().isNotEmpty) return savedTitle;

    final first = messageStore.messages
        .where((m) => m.role != MessageRole.system && m.text.trim().isNotEmpty)
        .map((m) => m.text.trim().replaceAll(RegExp(r'\s+'), ' '))
        .firstOrNull;

    if (first == null) return 'New chat';
    return first.length <= 40 ? first : '${first.substring(0, 37)}...';
  }

  ModelConfigurationSnapshot? get _activeServerSnapshot =>
      serverManager.current == null
      ? null
      : serverManager.diagnostics.modelSnapshot;

  Future<void> newChat({SystemPromptSnapshot? systemPromptSnapshot}) async {
    await flushCurrentChat();

    if (chatStream.isStreaming) {
      messageStore.clearCurrentId();
      await chatStream.stop();
    }

    _clearSavedState();
    currentSystemPromptSnapshot = systemPromptSnapshot;
    currentModelSnapshot = _activeServerSnapshot;
    messageStore.setMessages([
      systemPrompt.copyWith(text: _buildSystemPrompt()),
    ]);
  }

  Future<bool> openChat(String id) async {
    await flushCurrentChat();

    if (chatStream.isStreaming) {
      messageStore.clearCurrentId();
      await chatStream.stop();
    }

    final snapshot = await _chatLibrary.getChat(id);
    if (snapshot == null) return false;

    _loadingSnapshot = true;
    try {
      currentChatId = snapshot.chat.id;
      currentSavedChat = snapshot.chat;
      currentModelSnapshot = snapshot.chat.modelSnapshot;
      workspace = await _restoreWorkspace(snapshot.chat.workspace);
      currentSystemPromptSnapshot = snapshot.chat.systemPromptSnapshot;
      _dirty = false;
      messageStore.setMessages(_withCurrentSystemPrompt(snapshot.messages));
      await _chatLibrary.markOpened(snapshot.chat.id);
      await refreshModelRestorePrompt();
    } finally {
      _loadingSnapshot = false;
    }

    notifyListeners();
    return true;
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

  void setSystemPromptSnapshot(SystemPromptSnapshot snapshot) {
    if (isSystemPromptLocked) {
      throw StateError('System prompt is locked for this chat');
    }

    currentSystemPromptSnapshot = snapshot;
    _syncSystemPrompt();
    notifyListeners();
  }

  @visibleForTesting
  String buildSystemPromptForTesting({String? currentUserRequest}) {
    return _buildSystemPrompt(currentUserRequest: currentUserRequest);
  }

  Future<void> refreshModelRestorePrompt() async {
    await _prepareModelRestorePrompt(currentModelSnapshot);
    notifyListeners();
  }

  void insertMessage(String text, MessageRole role) {
    if (chatStream.isStreaming) return;

    final t = text.trim();

    if (t.isEmpty) return;

    _adoptActiveModelIfRestoreDismissed();

    messageStore.upsert(
      Bubble(id: uuid.v7(), role: role, text: t, reasoning: ''),
    );
  }

  Future<void> attachWorkspace(String folderPath) async {
    if (chatStream.isStreaming) return;
    workspace = await _workspaceService.attach(folderPath);
    _syncSystemPrompt();
    _markWorkspaceChanged();
  }

  void detachWorkspace() {
    if (chatStream.isStreaming) return;
    workspace = null;
    _syncSystemPrompt();
    _markWorkspaceChanged();
  }

  void setCommandExecutionApproved(bool approved) {
    final current = workspace;
    if (current == null) return;
    workspace = current.copyWith(commandExecutionApproved: approved);
    _markWorkspaceChanged();
  }

  Future<void> send(String text, {List<String>? tools = const []}) async {
    if (chatStream.isStreaming) return;

    final t = text.trim();
    if (t.isEmpty) return;

    _adoptActiveModelIfRestoreDismissed();

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

    _adoptActiveModelIfRestoreDismissed();

    var lastMessage = messageStore.last;
    if (lastMessage.role == MessageRole.assistant) {
      lastMessage = ContentNormaliser.normalise(lastMessage);
      messageStore.upsert(lastMessage);
    }

    final continuationTargetId =
        lastMessage.role == MessageRole.assistant && lastMessage.tools.isEmpty
        ? lastMessage.id
        : null;

    await _streamAssistantResponse(
      includeToolResults: false,
      addGenerationPrompt: lastMessage.role != MessageRole.assistant,
      selectedToolIds: tools ?? const [],
      anchorId: null,
      targetAssistantId: continuationTargetId,
    );
  }

  Future<void> cancelGeneration() async {
    if (!chatStream.isStreaming) return;

    final current = messageStore.currentMessage;
    if (current != null) {
      messageStore.upsert(ContentNormaliser.normalise(current));
    }

    messageStore.clearCurrentId();
    await chatStream.stop();
  }

  Future<void> _streamAssistantResponse({
    required bool includeToolResults,
    required bool addGenerationPrompt,
    List<String> selectedToolIds = const [],
    String? anchorId,
    String? targetAssistantId,
  }) async {
    if (chatStream.isStreaming) return;
    final client = serverManager.chatClient;
    if (client == null) return;

    chatStream.setState(StreamState.streaming);

    final activeToolIds = selectedToolIds.isEmpty
        ? defaultToolIds
        : selectedToolIds;
    final extraParams = ToolCaller.buildExtraParams(
      addGenerationPrompt: addGenerationPrompt,
      toolDefs: activeToolIds.isNotEmpty
          ? _toolService.getToolDefinitions(
              ids: activeToolIds,
              includeWorkspaceTools: workspaceToolsEnabled,
            )
          : const [],
    );

    try {
      final emergencyOmittedMessageIds = await _compactContextIfNeeded(
        client: client,
        extraParams: extraParams,
      );

      final targetIndex = targetAssistantId == null
          ? -1
          : messageStore.messages.indexWhere(
              (m) =>
                  m.id == targetAssistantId && m.role == MessageRole.assistant,
            );

      final contextIndex = targetIndex >= 0
          ? targetIndex
          : () {
              final bubble = Bubble(
                id: uuid.v7(),
                role: MessageRole.assistant,
                text: '',
                reasoning: '',
              );
              messageStore.upsert(bubble);
              messageStore.setCurrentId(bubble.id);

              if (anchorId != null) {
                final index = messageStore.messages.indexWhere(
                  (m) => m.id == anchorId,
                );
                return index > 0 ? (messageStore.messages.length - 2) : index;
              }

              return messageStore.messages.length - 2;
            }();

      if (targetIndex >= 0) {
        messageStore.setCurrentId(targetAssistantId);
      }

      final currentUserRequest = _currentUserRequestFor(contextIndex);
      final payloadMessages = _payloadMessages(
        currentUserRequest: currentUserRequest,
      );

      final payload = includeToolResults
          ? PayloadBuilder.buildPayloadWithTools(
              messages: payloadMessages,
              upToIndexInclusive: contextIndex,
              omitCoveredMessages: true,
              omittedMessageIds: emergencyOmittedMessageIds,
            )
          : PayloadBuilder.buildPayload(
              messages: payloadMessages,
              upToIndexInclusive: contextIndex,
              omitCoveredMessages: true,
              omittedMessageIds: emergencyOmittedMessageIds,
            );

      serverManager.diagnostics.recordStreamStarted(
        estimatedContextTokens: ContextEstimator.estimateChatCompletionRequest(
          messages: payload,
          extraParams: extraParams,
        ),
        contextLimitTokens: currentModelSnapshot?.nCtx,
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
    } catch (e) {
      serverManager.diagnostics.recordCompactionFailed(e);
      messageStore.clearCurrentId();
      await chatStream.stop(next: StreamState.error);
    }
  }

  Future<Set<String>> _compactContextIfNeeded({
    required ChatClient client,
    required Map<String, dynamic> extraParams,
  }) async {
    final snapshot = currentModelSnapshot;
    if (snapshot == null) return const {};

    final settings = await _preferencesService.getCompactionSettings();
    final manager = CompactionManager(settings: settings, client: client);
    if (!manager.shouldCompact(
      messages: messageStore.messages,
      contextLimit: snapshot.nCtx,
      extraParams: extraParams,
    )) {
      return const {};
    }

    void status(String message) {
      if (serverManager.diagnostics.compactionActive) {
        serverManager.diagnostics.recordCompactionStatus(message);
      } else {
        serverManager.diagnostics.recordCompactionStarted(message);
      }
      notifyListeners();
    }

    final result = await manager.compactIfNeeded(
      messageStore: messageStore,
      contextLimit: snapshot.nCtx,
      extraParams: extraParams,
      onStatusChanged: status,
    );

    final finishStatus = result.emergencyPayloadTruncation
        ? 'Emergency context truncation active for this request.'
        : result.compacted
        ? 'Context compaction complete.'
        : 'Context compaction not needed.';
    final savedTokens = result.compacted || result.emergencyPayloadTruncation
        ? result.estimatedTokensSaved
        : null;
    final affectedMessages = result.compacted
        ? result.messagesCovered
        : result.emergencyPayloadTruncation
        ? result.emergencyOmittedMessageIds.length
        : null;

    serverManager.diagnostics.recordCompactionFinished(
      status: finishStatus,
      tokensSaved: savedTokens,
      messagesCovered: affectedMessages,
    );

    return result.emergencyOmittedMessageIds;
  }

  void _handleStreamToken(ChatToken token) {
    serverManager.diagnostics.recordStreamOutput(_streamedText(token));
    messageStore.appendToken(token);
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
        context: hasActiveWorkspace
            ? WorkspaceToolContext(workspace: workspace!)
            : null,
      );

      updated[toolIndex] = toolCall.copyWith(result: resultJson);
    }

    messageStore.upsert(assistantBubble.copyWith(tools: updated));

    await _streamAssistantResponse(
      includeToolResults: true,
      addGenerationPrompt: true,
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
    messageStore.clearToolBuffers();
    try {
      await chatStream.stop();
    } finally {
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
      messages: _payloadMessages(),
      upToIndexInclusive: messageStore.messages.length - 1,
      omitCoveredMessages: true,
    );
    serverManager.diagnostics.updateContextEstimate(
      ContextEstimator.estimateChatCompletionRequest(messages: payload),
      contextLimitTokens: snapshot.nCtx,
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
        workspace: workspace,
        systemPromptSnapshot: currentSystemPromptSnapshot,
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

    if (snapshot == null || snapshot.matches(_activeServerSnapshot)) return;

    pendingModelRestore = snapshot;
    if (!await File(snapshot.modelPath).exists()) {
      pendingModelRestoreIssue =
          'Saved model file not found: ${snapshot.modelPath}';
    }
  }

  void _clearSavedState() {
    currentChatId = null;
    currentSavedChat = null;
    workspace = null;
    currentSystemPromptSnapshot = null;
    pendingModelRestore = null;
    pendingModelRestoreIssue = null;
    _dirty = false;
    notifyListeners();
  }

  Future<WorkspaceAttachment?> _restoreWorkspace(
    WorkspaceAttachment? saved,
  ) async {
    if (saved == null) return null;
    return _workspaceService.restore(
      rootPath: saved.rootPath,
      displayName: saved.displayName,
      lastOpenedAt: saved.lastOpenedAt,
      commandExecutionApproved: saved.commandExecutionApproved,
    );
  }

  String _buildSystemPrompt({String? currentUserRequest}) {
    final snapshot = currentSystemPromptSnapshot;
    if (snapshot?.preset != null) {
      final result = _promptAssembler.assemble(
        PromptAssemblyRequest.fromSnapshot(
          snapshot!,
          autoModuleIds: _autoModuleIdsForWorkspace(),
          workspaceRootPath: workspace?.rootPath,
          workspaceMissing: workspace?.missing ?? false,
          commandExecutionApproved: workspace?.commandExecutionApproved == true,
          currentUserRequest: currentUserRequest,
        ),
      );
      if (result.text.trim().isNotEmpty) return result.text;
      if (snapshot.text.trim().isNotEmpty) return snapshot.text.trim();
    }

    final basePrompt =
        currentSystemPromptSnapshot?.text.trim().isNotEmpty == true
        ? currentSystemPromptSnapshot!.text.trim()
        : defaultSystemPromptText;
    final currentWorkspace = workspace;
    if (currentWorkspace == null) {
      return basePrompt;
    }

    if (currentWorkspace.missing) {
      return '$basePrompt\n\nA workspace was attached to this chat, but the folder is currently missing, so workspace tools are unavailable.';
    }

    return '''
$basePrompt

This chat has an attached workspace. The workspace root is:
${currentWorkspace.rootPath}

Workspace rules:
- Use workspace tools for file and folder operations.
- Only operate inside the attached workspace and use workspace-relative paths.
- Inspect relevant files before editing them.
- Prefer small, precise changes.
- Explain destructive file operations before performing them.
- Terminal commands are guarded and may be unavailable unless the user enables them for this chat.
'''
        .trim();
  }

  List<Bubble> _withCurrentSystemPrompt(
    List<Bubble> messages, {
    String? currentUserRequest,
  }) {
    final promptText = _buildSystemPrompt(
      currentUserRequest: currentUserRequest,
    );
    if (messages.isEmpty) return [systemPrompt.copyWith(text: promptText)];

    final copy = List<Bubble>.of(messages);
    if (copy.first.role == MessageRole.system) {
      copy[0] = copy.first.copyWith(text: promptText);
    } else {
      copy.insert(0, systemPrompt.copyWith(text: promptText));
    }
    return copy;
  }

  void _syncSystemPrompt() {
    messageStore.setMessages(_withCurrentSystemPrompt(messageStore.messages));
  }

  List<Bubble> _payloadMessages({String? currentUserRequest}) {
    return _withCurrentSystemPrompt(
      messageStore.messages,
      currentUserRequest: currentUserRequest,
    );
  }

  String? _currentUserRequestFor(int contextIndex) {
    final end = contextIndex.clamp(0, messageStore.messages.length - 1);
    for (var i = end; i >= 0; i--) {
      final message = messageStore.messages[i];
      if (message.role == MessageRole.user && message.text.trim().isNotEmpty) {
        return message.text.trim();
      }
    }
    return null;
  }

  List<String> _autoModuleIdsForWorkspace() {
    final currentWorkspace = workspace;
    if (currentWorkspace == null) return const [];
    return currentWorkspace.missing
        ? const [BuiltInPromptIds.workspaceMissingModule]
        : const [BuiltInPromptIds.workspaceRulesModule];
  }

  void _markWorkspaceChanged() {
    if (currentChatId != null) {
      _dirty = true;
      _scheduleAutosave();
    }
    notifyListeners();
  }

  void _adoptActiveModelIfRestoreDismissed() {
    if (pendingModelRestore != null) return;

    final activeSnapshot = _activeServerSnapshot;
    if (activeSnapshot == null ||
        activeSnapshot.matches(currentModelSnapshot)) {
      return;
    }

    currentModelSnapshot = activeSnapshot;
    _updateContextEstimate();
    if (currentChatId != null) {
      _dirty = true;
      _scheduleAutosave();
    }
    notifyListeners();
  }
}
