import 'dart:async';

import 'package:hermes/features/chat/application/contracts/message_role.dart';
import 'package:hermes/features/chat/application/contracts/stream_state.dart';
import 'package:hermes/features/chat/application/protocol/compaction_manager.dart';
import 'package:hermes/features/chat/application/contracts/content_normaliser.dart';
import 'package:hermes/features/tools/application/protocol/tool_call_protocol_adapter.dart';
import 'package:hermes/core/uuid.dart';
import 'package:hermes/features/chat/application/contracts/bubble.dart';
import 'package:hermes/features/chat/application/contracts/chat_token.dart';
import 'package:hermes/features/model/application/model_configuration.dart';
import 'package:hermes/features/model/application/model_completion_port.dart';
import 'package:hermes/features/chat/runtime/chat_application/chat_stream.dart';
import 'package:hermes/core/cancellation.dart';
import 'package:hermes/features/chat/runtime/chat_application/message_store.dart';
import 'package:hermes/features/chat/application/protocol/payload_builder.dart';
import 'package:hermes/features/chat/application/contracts/assistant_ops.dart';
import 'package:hermes/features/chat/application/contracts/buffered_token_writer.dart';
import 'package:hermes/features/chat/application/protocol/chat_tool_call_protocol_adapter.dart';
import 'package:hermes/features/model/application/model_server_port.dart';
import 'package:hermes/features/settings/application/preferences_port.dart';
import 'package:hermes/features/model/application/model_output.dart';
import 'package:hermes/features/tools/application/tool_contracts.dart';
import 'package:hermes/features/tools/application/tool_protocol_adapter.dart';
import 'package:hermes/features/workspace/application/workspace.dart';
import 'package:hermes/features/chat/runtime/chat_session_host.dart';
import 'package:hermes/features/chat/runtime/chat_application/chat_tool_execution_service.dart';

import 'package:hermes/core/disposable.dart';

/// Manages the active chat session's streaming and LLM communication.
///
/// Handles all aspects of LLM interaction: streaming responses, tool execution,
/// context compaction, token handling, and task model output rendering.
/// Delegates state-policy callbacks through [ChatSessionHost], keeping the
/// streaming engine independent from the UI-facing chat façade.
class ChatSessionManager implements Disposable {
  final MessageStore _messageStore;
  final ChatStream<ChatToken> _chatStream;
  final ModelServerPort _serverManager;
  final ToolRegistryPort _toolService;
  final ChatToolExecutionPort _toolExecution;
  final PreferencesPort _preferencesService;
  late final BufferedTokenWriter _tokenWriter;

  final ChatSessionHost _host;
  CancellationToken? _activeGenerationToken;
  int _generationSerial = 0;

  // Session policy depends on mutable chat state. Read it from the owning
  // service so workspace attachment, model changes, and saved-chat loading
  // take effect on the next request without rebuilding the manager.
  WorkspaceAttachment? get workspace => _host.workspace;

  ModelConfigurationSnapshot? get currentModelSnapshot =>
      _host.currentModelSnapshot;

  int? get diagnosticsContextLimit => _host.sessionDiagnosticsContextLimit;

  List<String> get defaultToolIds => _host.defaultToolIds;

  bool get workspaceToolsEnabled => _host.workspaceToolsEnabled;

  // ── Construction ────────────────────────────────────────────────────────

  ChatSessionManager({
    required MessageStore messageStore,
    required ChatStream<ChatToken> chatStream,
    required ModelServerPort serverManager,
    required ToolRegistryPort toolService,
    required ChatToolExecutionPort toolExecution,
    required PreferencesPort preferencesService,
    required ChatSessionHost host,
  }) : _messageStore = messageStore,
       _chatStream = chatStream,
       _serverManager = serverManager,
       _toolService = toolService,
       _toolExecution = toolExecution,
       _preferencesService = preferencesService,
       _host = host {
    _tokenWriter = BufferedTokenWriter(
      messageStore: _messageStore,
      onFlush: requestContextEstimateUpdate,
    );
  }

  // ── Public API ──────────────────────────────────────────────────────────

  /// Streams an assistant response from the LLM.
  ///
  /// Builds the message payload, initiates streaming via [ModelCompletionPort],
  /// handles incoming tokens, and processes terminal events (errors,
  /// tool calls). Returns a [Future] that completes when streaming ends.
  Future<void> streamAssistantResponse({
    required bool includeToolResults,
    required bool addGenerationPrompt,
    List<String> selectedToolIds = const [],
    String? anchorId,
    String? targetAssistantId,
  }) async {
    _tokenWriter.flush();
    if (_chatStream.isStreaming) return;

    final client = _serverManager.completionProvider;
    if (client == null) return;

    final token = CancellationToken();
    final generationId = ++_generationSerial;
    _activeGenerationToken = token;
    _chatStream.setState(StreamState.streaming);

    await _streamGenerationRequest(
      client: client,
      token: token,
      generationId: generationId,
      includeToolResults: includeToolResults,
      addGenerationPrompt: addGenerationPrompt,
      selectedToolIds: selectedToolIds,
      anchorId: anchorId,
      targetAssistantId: targetAssistantId,
    );
  }

  Future<void> _streamGenerationRequest({
    required ModelCompletionPort client,
    required CancellationToken token,
    required int generationId,
    required bool includeToolResults,
    required bool addGenerationPrompt,
    required List<String> selectedToolIds,
    String? anchorId,
    String? targetAssistantId,
  }) async {
    token.throwIfCancelled();

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
        cancellationToken: token,
      );
      token.throwIfCancelled();

      final targetIndex = targetAssistantId == null
          ? -1
          : _messageStore.messages.indexWhere(
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
                createdAt: DateTime.now(),
              );
              _messageStore.upsert(bubble);
              _messageStore.setCurrentId(bubble.id);

              if (anchorId != null) {
                final index = _messageStore.messages.indexWhere(
                  (m) => m.id == anchorId,
                );
                return index > 0 ? (_messageStore.messages.length - 2) : index;
              }

              return _messageStore.messages.length - 2;
            }();

      if (targetIndex >= 0) {
        _messageStore.setCurrentId(targetAssistantId);
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

      final exactTokens = await client.countInputTokens(
        messages: payload,
        extraParams: extraParams,
        cancellationToken: token,
      );
      token.throwIfCancelled();

      final sub = client.streamMessage(
        messages: payload,
        extraParams: extraParams,
        cancellationToken: token,
        diagnosticsLabel: includeToolResults
            ? 'Tool continuation'
            : 'Chat response',
        contextLimitTokens: currentModelSnapshot?.nCtx,
        inputTokensHint: exactTokens,
      );

      var terminalHandled = false;
      Future<void> terminal({Object? error}) async {
        if (terminalHandled) return;
        terminalHandled = true;
        await _handleStreamTerminal(
          error: error,
          token: token,
          generationId: generationId,
        );
      }

      _chatStream.attach(
        sub.listen(
          (value) {
            if (_isActiveGeneration(token, generationId)) {
              _handleStreamToken(value);
            }
          },
          onError: (e, _) async => terminal(error: e),
          onDone: () async => terminal(),
          cancelOnError: true,
        ),
      );
    } on OperationCancelledException {
      await _finishCancelledGeneration(token, generationId);
    } catch (e) {
      if (!_isActiveGeneration(token, generationId)) return;
      _serverManager.telemetry.recordCompactionFailed(e);
      _messageStore.clearCurrentId();
      await _chatStream.stop(next: StreamState.error);
      _activeGenerationToken = null;
      requestContextEstimateUpdate(immediate: true);
    }
  }

  /// Cancels the current streaming operation and normalizes the current message.
  Future<void> cancelGeneration() async {
    final token = _activeGenerationToken;
    if (token == null) return;

    _tokenWriter.flush();
    final current = _messageStore.currentMessage;
    if (current != null) {
      _messageStore.upsert(
        ContentNormaliser.normalise(_withCancelledPendingTools(current)),
      );
    }

    await token.cancel();
    _messageStore.clearCurrentId();
    await _chatStream.stop();
    if (identical(_activeGenerationToken, token)) {
      _activeGenerationToken = null;
    }
    requestContextEstimateUpdate(immediate: true);
  }

  /// Inserts a user message followed by an assistant acknowledgment.
  void insertUserAndAssistant(String userText, String assistantText) {
    _tokenWriter.flush();
    _messageStore
      ..upsert(
        Bubble(
          id: uuid.v7(),
          role: MessageRole.user,
          text: userText,
          reasoning: '',
          createdAt: DateTime.now(),
        ),
      )
      ..upsert(
        Bubble(
          id: uuid.v7(),
          role: MessageRole.assistant,
          text: assistantText,
          reasoning: '',
          createdAt: DateTime.now(),
        ),
      );
  }

  /// Updates workspace state and marks the session as dirty (triggers autosave).
  void markWorkspaceChanged() {
    _host.markWorkspaceChanged();
  }

  // ── Streaming internals ─────────────────────────────────────────────────

  Future<Set<String>> _compactContextIfNeeded({
    required ModelCompletionPort client,
    required ModelRequestOptions extraParams,
    CancellationToken? cancellationToken,
  }) async {
    final snapshot = currentModelSnapshot;
    if (snapshot == null) return const {};

    final settings = await _preferencesService.getCompactionSettings();
    final manager = CompactionManager(settings: settings, client: client);
    void status(String message) {
      if (_serverManager.diagnostics.compactionActive) {
        _serverManager.telemetry.recordCompactionStatus(message);
      } else {
        _serverManager.telemetry.recordCompactionStarted(message);
      }
      _host.sessionNotifyListeners();
    }

    final result = await manager.compactIfNeeded(
      messageStore: _messageStore,
      contextLimit: snapshot.nCtx,
      extraParams: extraParams,
      onStatusChanged: status,
      cancellationToken: cancellationToken,
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

    _serverManager.telemetry.recordCompactionFinished(
      status: finishStatus,
      tokensSaved: savedTokens,
      messagesCovered: affectedMessages,
    );

    return result.emergencyOmittedMessageIds;
  }

  void _handleStreamToken(ChatToken token) {
    _tokenWriter.add(token);
  }

  Future<void> _handleStreamTerminal({
    Object? error,
    required CancellationToken token,
    required int generationId,
  }) async {
    if (!_isActiveGeneration(token, generationId)) return;
    _tokenWriter.flush();
    if (token.isCancelled || error is OperationCancelledException) {
      await _finishCancelledGeneration(token, generationId);
      return;
    }
    if (error != null) {
      _messageStore.appendCurrentError(error);
      _messageStore.clearCurrentId();
      await _chatStream.stop(next: StreamState.error);
      _activeGenerationToken = null;
      requestContextEstimateUpdate(immediate: true);
      return;
    }

    if (_messageStore.currentMessage != null) {
      _messageStore.upsert(
        ContentNormaliser.normalise(_messageStore.currentMessage!),
      );
    }

    await _chatStream.detach();
    requestContextEstimateUpdate(immediate: true);

    final toolCalls = ToolCaller.extractPendingToolEntries(
      _messageStore.currentMessage,
    );
    if (toolCalls.isNotEmpty) {
      try {
        await _runToolsAndContinue(
          toolCalls,
          token: token,
          generationId: generationId,
        );
      } on OperationCancelledException {
        await _finishCancelledGeneration(token, generationId);
      } catch (e) {
        if (!_isActiveGeneration(token, generationId)) return;
        _messageStore.appendCurrentError(e);
        _messageStore.clearCurrentId();
        await _chatStream.stop(next: StreamState.error);
        _activeGenerationToken = null;
        requestContextEstimateUpdate(immediate: true);
      }

      return;
    }

    _messageStore.clearCurrentId();
    _activeGenerationToken = null;
    await _chatStream.stop();
  }

  Future<void> _runToolsAndContinue(
    List<MapEntry<int, BubbleToolCall>> calls, {
    required CancellationToken token,
    required int generationId,
  }) async {
    await _toolExecution.executePendingCalls(
      calls: [
        for (final entry in calls)
          const ChatToolCallProtocolAdapter().decode(
            index: entry.key,
            call: entry.value,
          ),
      ],
      workspace: workspace,
      cancellationToken: token,
      onResult: (result) {
        final currentBubble = _messageStore.currentMessage;
        if (currentBubble == null) return;
        final existing = currentBubble.tools[result.index];
        if (existing == null) return;
        final tools = Map<int, BubbleToolCall>.from(currentBubble.tools);
        tools[result.index] = existing.copyWith(
          result: ToolProtocolAdapter.encodeResult(result.result),
        );
        _messageStore.upsert(currentBubble.copyWith(tools: tools));
      },
    );
    final currentBubble = _messageStore.currentMessage;
    if (currentBubble == null) return;

    token.throwIfCancelled();
    await _streamGenerationRequest(
      client: _serverManager.completionProvider!,
      token: token,
      generationId: generationId,
      includeToolResults: true,
      addGenerationPrompt: true,
      selectedToolIds: const [],
      anchorId: currentBubble.id,
    );
  }

  bool _isActiveGeneration(CancellationToken token, int generationId) =>
      identical(_activeGenerationToken, token) &&
      generationId == _generationSerial;

  Bubble _withCancelledPendingTools(Bubble bubble) {
    if (bubble.tools.isEmpty) return bubble;
    final tools = Map<int, BubbleToolCall>.from(bubble.tools);
    for (final entry in tools.entries.toList()) {
      if (entry.value.result != null) continue;
      tools[entry.key] = entry.value.copyWith(
        result:
            '{"error":"tool execution cancelled","code":"operation_cancelled","warning":"An interrupted command may have made partial changes."}',
      );
    }
    return bubble.copyWith(tools: tools);
  }

  Future<void> _finishCancelledGeneration(
    CancellationToken token,
    int generationId,
  ) async {
    if (!_isActiveGeneration(token, generationId)) return;
    final current = _messageStore.currentMessage;
    if (current != null) {
      _messageStore.upsert(
        ContentNormaliser.normalise(_withCancelledPendingTools(current)),
      );
    }
    _messageStore.clearCurrentId();
    _activeGenerationToken = null;
    await _chatStream.stop();
    requestContextEstimateUpdate(immediate: true);
  }

  void finishTaskModelOutputBubble({required bool clearCurrent}) {
    final id = taskModelOutputMessageId;
    if (id == null) return;
    normaliseTaskModelOutputBubble();
    final index = _messageStore.messages.indexWhere(
      (message) => message.id == id,
    );
    if (index >= 0) {
      final message = _messageStore.messages[index];
      if (message.text.trim().isEmpty &&
          message.reasoning.trim().isEmpty &&
          message.tools.isEmpty) {
        _messageStore.removeById(id);
      }
    }
    if (clearCurrent && _messageStore.currentMessage?.id == id) {
      _messageStore.clearCurrentId();
    }
    clearTaskModelOutputBubble();
  }

  // ── Task model output bubble management ─────────────────────────────────

  void startTaskModelOutputBubble() {
    _tokenWriter.flush();
    finishTaskModelOutputBubble(clearCurrent: true);
    final bubble = Bubble(
      id: uuid.v7(),
      role: MessageRole.assistant,
      text: '',
      reasoning: '',
      createdAt: DateTime.now(),
    );
    _messageStore.upsert(bubble);
    _messageStore.setCurrentId(bubble.id);
    _taskModelOutputMessageId = bubble.id;
  }

  void appendTaskModelToken(TaskModelOutputEvent event) {
    final token = event.token;
    if (token == null) return;
    if (!_taskModelOutputCurrentBubbleIsActive()) {
      startTaskModelOutputBubble();
    }
    _tokenWriter.add(switch (event.type) {
      TaskModelOutputEventType.content => ChatToken(content: token.content),
      TaskModelOutputEventType.reasoning => ChatToken(
        reasoning: token.reasoning,
      ),
      TaskModelOutputEventType.toolCall => ChatToken(tool: token.tool),
      _ => token,
    });
  }

  void appendTaskToolResult(TaskModelOutputEvent event) {
    _tokenWriter.flush();
    if (!_taskModelOutputCurrentBubbleIsActive()) return;
    final current = _messageStore.currentMessage;
    final index = event.toolIndex;
    if (current == null || index == null) return;
    final updated = Map<int, BubbleToolCall>.from(current.tools);
    final existing = updated[index] ?? const BubbleToolCall();
    updated[index] = existing.copyWith(result: event.text);
    _messageStore.upsert(current.copyWith(tools: updated));
  }

  bool _taskModelOutputCurrentBubbleIsActive() {
    final id = _taskModelOutputMessageId;
    final current = _messageStore.currentMessage;
    return id != null && current != null && current.id == id;
  }

  void normaliseTaskModelOutputBubble() {
    _tokenWriter.flush();
    final id = _taskModelOutputMessageId;
    if (id == null) return;
    final index = _messageStore.messages.indexWhere(
      (message) => message.id == id,
    );
    if (index < 0) return;
    final message = _messageStore.messages[index];
    if (message.role == MessageRole.assistant) {
      _messageStore.upsert(ContentNormaliser.normalise(message));
    }
  }

  String? _taskModelOutputMessageId;

  // ── Context estimation ──────────────────────────────────────────────────

  /// Requests that the service layer update context estimation.
  void requestContextEstimateUpdate({bool immediate = false}) {
    _host.requestContextEstimateUpdate(immediate: immediate);
  }

  // ── Message helpers ─────────────────────────────────────────────────────

  List<Bubble> _payloadMessages({String? currentUserRequest}) {
    return _withCurrentSystemPrompt(
      _messageStore.messages,
      currentUserRequest: currentUserRequest,
    );
  }

  String? _currentUserRequestFor(int contextIndex) {
    final end = contextIndex.clamp(0, _messageStore.messages.length - 1);
    for (var i = end; i >= 0; i--) {
      final message = _messageStore.messages[i];
      if (message.role == MessageRole.user && message.text.trim().isNotEmpty) {
        return message.text.trim();
      }
    }
    return null;
  }

  List<Bubble> _withCurrentSystemPrompt(
    List<Bubble> messages, {
    String? currentUserRequest,
  }) {
    final promptText = _host.buildSystemPrompt(
      currentUserRequest: currentUserRequest,
    );
    if (messages.isEmpty) {
      return [
        Bubble(
          id: uuid.v7(),
          role: MessageRole.system,
          text: promptText,
          reasoning: '',
          createdAt: DateTime.now(),
        ),
      ];
    }

    final copy = List<Bubble>.of(messages);
    if (copy.first.role == MessageRole.system) {
      copy[0] = copy.first.copyWith(text: promptText);
    } else {
      copy.insert(
        0,
        Bubble(
          id: uuid.v7(),
          role: MessageRole.system,
          text: promptText,
          reasoning: '',
          createdAt: DateTime.now(),
        ),
      );
    }
    return copy;
  }

  // ── Task model output helpers ───────────────────────────────────────────

  void ensureTaskModelTextSection(String label, String section) {
    if (_host.sessionTaskModelOutputLabel() != label) {
      _host.updateSessionTaskModelOutputLabel(label);
      _host.updateSessionTaskModelOutputTextSection(null);
      _host.appendTaskModelOutputText('\n\n## $label\n');
    }
    if (_host.sessionTaskModelOutputTextSection() == section) return;
    _host.updateSessionTaskModelOutputTextSection(section);
    switch (section) {
      case 'output':
      case 'tool-call':
      case 'tool-result':
      case 'error':
        _host.appendTaskModelOutputText('\n');
    }
  }

  void ensureTaskModelReasoningSection(String label) {
    if (_host.sessionTaskModelOutputReasoningLabel() == label) return;
    _host.updateSessionTaskModelOutputReasoningLabel(label);
    final current = _host.taskModelOutputReasoning;
    _host.dispatchTaskModelOutputReasoning(
      '${current.trim().isEmpty ? '' : '\n\n'}## $label\n',
    );
  }

  void appendTaskModelText(String text) {
    _host.appendTaskModelOutputText(text);
  }

  void finishTaskModelOutputBubbleFromService({required bool clearCurrent}) {
    // This method is called by the façade to delegate bubble finishing.
    // The session manager owns the actual bubble lifecycle.
    finishTaskModelOutputBubble(clearCurrent: clearCurrent);
  }

  /// Returns the current task model output bubble ID, or null if inactive.
  String? get taskModelOutputMessageId => _taskModelOutputMessageId;

  /// Clears the active task model output bubble.
  void clearTaskModelOutputBubble() {
    _taskModelOutputMessageId = null;
  }

  /// Publishes any buffered model output before state is read or persisted.
  void flushPendingTokens() => _tokenWriter.flush();

  // ── Disposable ──────────────────────────────────────────────────────────

  bool _disposed = false;

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _tokenWriter.dispose();
    try {
      await _chatStream.stop();
    } finally {}
  }
}
