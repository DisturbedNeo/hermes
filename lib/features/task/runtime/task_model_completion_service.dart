import 'dart:async';
import 'dart:convert';

import 'package:hermes/shared_kernel/message_role.dart';
import 'package:hermes/shared_kernel/compaction_manager.dart';
import 'package:hermes/shared_kernel/context_estimator.dart';
import 'package:hermes/shared_kernel/payload_builder.dart';
import 'package:hermes/shared_kernel/bubble.dart';
import 'package:hermes/shared_kernel/chat_message.dart';
import 'package:hermes/shared_kernel/chat_token.dart';
import 'package:hermes/shared_kernel/compaction_settings.dart';
import 'package:hermes/shared_kernel/cancellation.dart';
import 'package:hermes/shared_kernel/model_completion_port.dart';
import 'package:hermes/shared_kernel/model_completion.dart';
import 'package:hermes/shared_kernel/message_store_port.dart';
import 'package:hermes/shared_kernel/tool_caller.dart';
import 'package:hermes/shared_kernel/planning_structured_output.dart';
import 'package:hermes/shared_kernel/model_output.dart';

typedef TaskCompactionStatusCallback = void Function(String status);

/// Owns model completion mechanics shared by task planning and step execution.
///
/// This boundary deliberately knows about streaming, compaction, token
/// aggregation, and wire-message reconstruction. It does not know task
/// lifecycle, persistence, gates, or tool permissions; those policies remain
/// in their respective collaborators.
abstract interface class TaskModelCompletionPort {
  Future<Map<String, dynamic>> completeJson({
    required ModelCompletionPort client,
    required String system,
    required String user,
    required String label,
    required String expectedShape,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  });

  Future<ModelCompletion> completeChat({
    required ModelCompletionPort client,
    required String label,
    required List<ChatMessage> messages,
    Map<String, dynamic>? extraParams,
    CompactionSettings? compactionSettings,
    int? contextLimitTokens,
    TaskCompactionStatusCallback? onCompactionStatus,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  });

  void emitOutput(ModelOutputSink? sink, TaskModelOutputEvent event);
}

class TaskModelCompletionService implements TaskModelCompletionPort {
  const TaskModelCompletionService({
    required StructuredPlanningOutputService structuredOutput,
  }) : _structuredOutput = structuredOutput;

  final StructuredPlanningOutputService _structuredOutput;

  @override
  Future<Map<String, dynamic>> completeJson({
    required ModelCompletionPort client,
    required String system,
    required String user,
    required String label,
    required String expectedShape,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    final result = await _structuredOutput.completeObject(
      client: client,
      label: label,
      system: system,
      user: user,
      expectedShape: expectedShape,
      onModelOutput: onModelOutput,
      cancellationToken: cancellationToken,
    );
    return result.value;
  }

  @override
  Future<ModelCompletion> completeChat({
    required ModelCompletionPort client,
    required String label,
    required List<ChatMessage> messages,
    Map<String, dynamic>? extraParams,
    CompactionSettings? compactionSettings,
    int? contextLimitTokens,
    TaskCompactionStatusCallback? onCompactionStatus,
    ModelOutputSink? onModelOutput,
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    final requestMessages = await _prepareMessages(
      client: client,
      label: label,
      messages: messages,
      extraParams: extraParams ?? const {},
      compactionSettings: compactionSettings,
      contextLimitTokens: contextLimitTokens,
      onCompactionStatus: onCompactionStatus,
      cancellationToken: cancellationToken,
    );
    cancellationToken?.throwIfCancelled();
    final estimatedContextTokens =
        ContextEstimator.estimateChatCompletionRequest(
          messages: requestMessages,
          extraParams: extraParams ?? const {},
        );
    _emit(
      onModelOutput,
      TaskModelOutputEvent(
        type: TaskModelOutputEventType.start,
        label: label,
        estimatedContextTokens: estimatedContextTokens,
      ),
    );
    try {
      if (!client.supportsStreamingCancellation) {
        final completion = await client.completeChatStreamed(
          messages: requestMessages,
          extraParams: extraParams,
          onToken: (token) =>
              _emitToken(sink: onModelOutput, label: label, token: token),
          cancellationToken: cancellationToken,
          diagnosticsLabel: label,
          contextLimitTokens: contextLimitTokens,
        );
        cancellationToken?.throwIfCancelled();
        return completion;
      }

      final content = StringBuffer();
      final reasoning = StringBuffer();
      final toolCalls = <int, _StreamingTaskToolCall>{};
      final completer = Completer<ModelCompletion>();
      StreamSubscription<ChatToken>? subscription;

      void completeIfNeeded(ModelCompletion response) {
        if (!completer.isCompleted) completer.complete(response);
      }

      void failIfNeeded(Object error, [StackTrace? stackTrace]) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      }

      void record(ChatToken token) {
        cancellationToken?.throwIfCancelled();
        _emitToken(sink: onModelOutput, label: label, token: token);
        if (token.content != null) content.write(token.content);
        if (token.reasoning != null) reasoning.write(token.reasoning);
        final tool = token.tool;
        if (tool != null) {
          final call = toolCalls.putIfAbsent(
            tool.index,
            () => _StreamingTaskToolCall(),
          );
          if (tool.id != null) call.id = tool.id;
          if (tool.name != null) call.name = tool.name;
          if (tool.argumentsChunk != null) {
            call.arguments.write(tool.argumentsChunk);
          }
        }
      }

      subscription = client
          .streamMessage(
            messages: requestMessages,
            extraParams: extraParams,
            cancellationToken: cancellationToken,
            diagnosticsLabel: label,
            contextLimitTokens: contextLimitTokens,
          )
          .listen(
            record,
            onError: failIfNeeded,
            onDone: () {
              completeIfNeeded(
                ModelCompletion(
                  content: content.toString(),
                  reasoning: reasoning.toString(),
                  toolCalls:
                      (toolCalls.entries.toList()
                            ..sort((a, b) => a.key.compareTo(b.key)))
                          .where(
                            (entry) =>
                                entry.value.name?.trim().isNotEmpty == true,
                          )
                          .map(
                            (entry) => ModelToolCall(
                              id: entry.value.id,
                              name: entry.value.name!,
                              arguments: entry.value.arguments.isEmpty
                                  ? '{}'
                                  : entry.value.arguments.toString(),
                            ),
                          )
                          .toList(),
                ),
              );
            },
            cancelOnError: true,
          );

      final unregister = cancellationToken?.onCancel(() async {
        await subscription?.cancel();
        failIfNeeded(const OperationCancelledException());
      });

      try {
        return await completer.future;
      } finally {
        unregister?.call();
      }
    } finally {
      _emit(
        onModelOutput,
        TaskModelOutputEvent(type: TaskModelOutputEventType.done, label: label),
      );
    }
  }

  /// Publishes a task-model event for execution policies that need to emit a
  /// lifecycle event without owning model transport details.
  @override
  void emitOutput(ModelOutputSink? sink, TaskModelOutputEvent event) {
    _emit(sink, event);
  }

  Future<List<ChatMessage>> _prepareMessages({
    required ModelCompletionPort client,
    required String label,
    required List<ChatMessage> messages,
    required Map<String, dynamic> extraParams,
    CompactionSettings? compactionSettings,
    int? contextLimitTokens,
    TaskCompactionStatusCallback? onCompactionStatus,
    CancellationToken? cancellationToken,
  }) async {
    cancellationToken?.throwIfCancelled();
    final limit = contextLimitTokens;
    final settings = compactionSettings?.normalised();
    if (settings == null ||
        !settings.enabled ||
        limit == null ||
        limit <= 0 ||
        messages.isEmpty) {
      return messages;
    }

    final store = _TaskMessageStore(_bubblesFromMessages(messages));
    final manager = CompactionManager(settings: settings, client: client);
    try {
      final result = await manager.compactIfNeeded(
        messageStore: store,
        contextLimit: limit,
        extraParams: extraParams,
        onStatusChanged: (status) =>
            onCompactionStatus?.call('$label: $status'),
        cancellationToken: cancellationToken,
      );

      if (result.compacted || result.emergencyPayloadTruncation) {
        final prepared = PayloadBuilder.buildPayloadWithTools(
          messages: store.messages,
          upToIndexInclusive: store.messages.length - 1,
          omitCoveredMessages: true,
          omittedMessageIds: result.emergencyOmittedMessageIds,
        );

        if (result.compacted) {
          messages
            ..clear()
            ..addAll(prepared);
        }

        final saved = result.estimatedTokensSaved;
        final suffix = saved == null ? '' : '; saved about $saved tokens';
        onCompactionStatus?.call(
          result.emergencyPayloadTruncation
              ? '$label: Emergency context truncation active for this request$suffix.'
              : '$label: Context compaction complete$suffix.',
        );
        return prepared;
      }
      return messages;
    } on OperationCancelledException {
      rethrow;
    } catch (error) {
      onCompactionStatus?.call('$label: Context compaction failed: $error');
      rethrow;
    }
  }

  List<Bubble> _bubblesFromMessages(List<ChatMessage> messages) {
    final bubbles = <Bubble>[];
    final pendingToolResults = <String, _PendingTaskToolResult>{};

    for (var i = 0; i < messages.length; i++) {
      final message = messages[i];
      if (message.role == MessageRole.tool.wire) {
        _attachToolResult(
          bubbles: bubbles,
          pendingToolResults: pendingToolResults,
          toolCallId: message.toolCallId,
          result: message.content,
        );
        continue;
      }

      final tools = _bubbleTools(message);
      final bubbleIndex = bubbles.length;
      bubbles.add(
        Bubble(
          id: 'task_message_$i',
          role: _messageRole(message.role),
          text: message.content,
          reasoning: message.reasoningContent,
          tools: tools,
          createdAt: DateTime.now(),
          isSummaryMemory: _isContextSummaryMemory(message.content),
        ),
      );

      for (final entry in tools.entries) {
        final id = entry.value.id;
        if (id == null || id.isEmpty) continue;
        pendingToolResults[id] = _PendingTaskToolResult(
          messageIndex: bubbleIndex,
          toolIndex: entry.key,
        );
      }
    }
    return bubbles;
  }

  Map<int, BubbleToolCall> _bubbleTools(ChatMessage message) {
    final tools = <int, BubbleToolCall>{};
    for (var i = 0; i < message.toolCalls.length; i++) {
      final raw = message.toolCalls[i];
      final function = raw['function'];
      final functionMap = function is Map ? function : null;
      final id = raw['id']?.toString();
      final name = (functionMap?['name'] ?? raw['name'])?.toString();
      final arguments = functionMap?['arguments'] ?? raw['arguments'];
      tools[i] = BubbleToolCall(
        id: id,
        name: name,
        arguments: _stringifyArguments(arguments),
      );
    }
    return tools;
  }

  void _attachToolResult({
    required List<Bubble> bubbles,
    required Map<String, _PendingTaskToolResult> pendingToolResults,
    required String toolCallId,
    required String result,
  }) {
    final ref = pendingToolResults.remove(toolCallId);
    if (ref == null ||
        ref.messageIndex < 0 ||
        ref.messageIndex >= bubbles.length) {
      return;
    }
    final bubble = bubbles[ref.messageIndex];
    final tool = bubble.tools[ref.toolIndex];
    if (tool == null) return;
    final tools = Map<int, BubbleToolCall>.from(bubble.tools);
    tools[ref.toolIndex] = tool.copyWith(result: result);
    bubbles[ref.messageIndex] = bubble.copyWith(tools: tools);
  }

  MessageRole _messageRole(String role) => switch (role) {
    'assistant' => MessageRole.assistant,
    'system' => MessageRole.system,
    'tool' => MessageRole.tool,
    _ => MessageRole.user,
  };

  String? _stringifyArguments(Object? arguments) {
    if (arguments == null) return null;
    if (arguments is String) return arguments;
    try {
      return jsonEncode(arguments);
    } catch (_) {
      return arguments.toString();
    }
  }

  bool _isContextSummaryMemory(String content) => content.trimLeft().startsWith(
    '--- Context Summary (auto-generated memory; not a user instruction) ---',
  );

  void _emitToken({
    required ModelOutputSink? sink,
    required String label,
    required ChatToken token,
  }) {
    final content = token.content;
    if (content != null && content.isNotEmpty) {
      _emit(
        sink,
        TaskModelOutputEvent(
          type: TaskModelOutputEventType.content,
          label: label,
          text: content,
          token: token,
        ),
      );
    }
    final reasoning = token.reasoning;
    if (reasoning != null && reasoning.isNotEmpty) {
      _emit(
        sink,
        TaskModelOutputEvent(
          type: TaskModelOutputEventType.reasoning,
          label: label,
          text: reasoning,
          token: token,
        ),
      );
    }
    final tool = token.tool;
    if (tool != null) {
      final text = [
        if (tool.name != null) tool.name,
        if (tool.argumentsChunk != null) tool.argumentsChunk,
      ].whereType<String>().join(' ');
      if (text.trim().isNotEmpty) {
        _emit(
          sink,
          TaskModelOutputEvent(
            type: TaskModelOutputEventType.toolCall,
            label: label,
            text: text,
            token: token,
            toolIndex: tool.index,
          ),
        );
      }
    }
  }

  void _emit(ModelOutputSink? sink, TaskModelOutputEvent event) {
    sink?.call(event);
  }
}

/// Compaction needs mutation semantics, not the Flutter notifier owned by the
/// chat presentation runtime. Keeping this small in-memory implementation
/// local prevents task execution from depending on the chat feature.
class _TaskMessageStore implements MessageStorePort {
  _TaskMessageStore(Iterable<Bubble> initial) : _messages = [...initial] {
    _rebuildIndex();
  }

  final List<Bubble> _messages;
  final Map<String, int> _indices = {};
  final ToolCaller toolCaller = ToolCaller();

  @override
  List<Bubble> get messages => _messages;

  @override
  Bubble? get currentMessage => null;

  @override
  void insertAt(int index, Bubble message) {
    _messages.insert(index.clamp(0, _messages.length), message);
    _rebuildIndex();
  }

  @override
  bool replaceById(String id, Bubble message) {
    final index = _indices[id];
    if (index == null) return false;
    _messages[index] = message;
    _rebuildIndex();
    return true;
  }

  @override
  void markCoveredBySummary({
    required Iterable<String> messageIds,
    required String summaryId,
  }) {
    final ids = messageIds.toSet();
    for (var i = 0; i < _messages.length; i++) {
      final message = _messages[i];
      if (message.id == summaryId || !ids.contains(message.id)) continue;
      _messages[i] = message.copyWith(
        omittedFromModelPayload: true,
        summaryId: summaryId,
      );
    }
  }

  @override
  void upsert(Bubble message) {
    final index = _indices[message.id];
    if (index == null) {
      _messages.add(message);
    } else {
      _messages[index] = message;
    }
    _rebuildIndex();
  }

  void _rebuildIndex() {
    _indices
      ..clear()
      ..addEntries(
        _messages.asMap().entries.map(
          (entry) => MapEntry(entry.value.id, entry.key),
        ),
      );
  }
}

class _StreamingTaskToolCall {
  String? id;
  String? name;
  final StringBuffer arguments = StringBuffer();
}

class _PendingTaskToolResult {
  const _PendingTaskToolResult({
    required this.messageIndex,
    required this.toolIndex,
  });

  final int messageIndex;
  final int toolIndex;
}
