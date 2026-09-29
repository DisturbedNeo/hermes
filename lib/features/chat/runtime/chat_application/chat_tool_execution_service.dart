import 'package:hermes/core/models/bubble.dart';
import 'package:hermes/features/workspace/domain/workspace.dart';
import 'package:hermes/core/services/cancellation_token.dart';
import 'package:hermes/features/chat/runtime/chat_application/message_store.dart';
import 'package:hermes/core/services/tool_service.dart';

abstract interface class ChatToolExecutionPort {
  Future<Bubble?> executePendingCalls({
    required List<MapEntry<int, BubbleToolCall>> calls,
    required WorkspaceAttachment? workspace,
    required CancellationToken cancellationToken,
  });
}

/// Executes and persists chat tool calls without owning model continuation.
///
/// The caller remains responsible for deciding whether and how to ask the
/// model for another completion. This service owns only tool permissions,
/// workspace context, cancellation boundaries, and result persistence.
class ChatToolExecutionService implements ChatToolExecutionPort {
  const ChatToolExecutionService({
    required ToolService toolService,
    required MessageStore messageStore,
  }) : _toolService = toolService,
       _messageStore = messageStore;

  final ToolService _toolService;
  final MessageStore _messageStore;

  @override
  Future<Bubble?> executePendingCalls({
    required List<MapEntry<int, BubbleToolCall>> calls,
    required WorkspaceAttachment? workspace,
    required CancellationToken cancellationToken,
  }) async {
    final currentBubble = _messageStore.currentMessage;
    if (currentBubble == null) {
      _messageStore.clearCurrentId();
      return null;
    }
    var assistantBubble = currentBubble;

    for (final entry in calls) {
      cancellationToken.throwIfCancelled();
      final toolCall = entry.value;
      final resultJson = await _executeCall(
        toolCall: toolCall,
        workspace: workspace,
        cancellationToken: cancellationToken,
      );
      cancellationToken.throwIfCancelled();
      assistantBubble = _persistToolResult(
        assistantBubble,
        entry.key,
        toolCall.copyWith(result: resultJson),
      );
    }

    return assistantBubble;
  }

  Future<String> _executeCall({
    required BubbleToolCall toolCall,
    required WorkspaceAttachment? workspace,
    required CancellationToken cancellationToken,
  }) {
    final toolName = toolCall.name;
    final argsJson = toolCall.arguments;
    if (toolName == null || argsJson == null) {
      return Future.value('{"error":"missing tool name or args"}');
    }

    return _toolService.execute(
      toolId: toolName,
      argumentsJson: argsJson,
      context: workspace != null && !workspace.missing
          ? WorkspaceToolContext(
              workspace: workspace,
              cancellationToken: cancellationToken,
            )
          : null,
    );
  }

  Bubble _persistToolResult(
    Bubble assistantBubble,
    int toolIndex,
    BubbleToolCall result,
  ) {
    final tools = Map<int, BubbleToolCall>.from(assistantBubble.tools);
    tools[toolIndex] = result;
    final updated = assistantBubble.copyWith(tools: tools);
    _messageStore.upsert(updated);
    return updated;
  }
}
