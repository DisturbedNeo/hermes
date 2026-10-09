import 'dart:convert';

import 'package:hermes/core/contracts/model_conversation.dart';
import 'package:hermes/features/chat/application/protocol/chat_message_wire_adapter.dart';

/// Keeps long-running planning conversations within a useful context size.
///
/// The planning registries hold the authoritative persisted state, so old tool
/// output can be compacted without making the transcript the source of truth.
/// Compacting the transcript preserves the tool-call protocol and recent
/// working context while keeping current task/project fields available when
/// they are useful for the next planning turn.
class PlannerMessageCompactor {
  const PlannerMessageCompactor._();

  static const _chatMessageAdapter = ChatMessageWireAdapter();

  static const int defaultMaxTranscriptCharacters = 24000;
  static const int defaultRecentMessageCount = 8;

  static List<ChatMessage> compact(
    List<ChatMessage> messages, {
    int maxTranscriptCharacters = defaultMaxTranscriptCharacters,
    int recentMessageCount = defaultRecentMessageCount,
  }) {
    if (messages.length <= 2 ||
        _estimateCharacters(messages) <= maxTranscriptCharacters ||
        recentMessageCount < 1) {
      return messages;
    }

    final firstDynamicMessage = messages.length > 2 ? 2 : messages.length;
    final recentStart = (messages.length - recentMessageCount).clamp(
      firstDynamicMessage,
      messages.length,
    );
    final compacted = <ChatMessage>[...messages.take(firstDynamicMessage)];
    for (var index = firstDynamicMessage; index < recentStart; index++) {
      compacted.add(_compactMessage(messages[index]));
    }
    compacted.addAll(messages.skip(recentStart));
    return compacted;
  }

  static ChatMessage _compactMessage(ChatMessage message) {
    if (message.role == 'tool') {
      return ChatMessage(
        role: message.role,
        content: _compactToolResult(message.content),
        toolCallId: message.toolCallId,
      );
    }
    if (message.role == 'assistant') {
      return ChatMessage(
        role: message.role,
        content: '',
        reasoningContent: '',
        toolCalls: message.toolCalls,
      );
    }
    return message;
  }

  static String _compactToolResult(String content) {
    final compact = <String, dynamic>{
      'ok': true,
      'code': 'planning_history_compacted',
      'message':
          'Earlier planning output was compacted. The planning registry '
          'still contains the authoritative persisted state; the next '
          'planning turn receives the current editable context.',
    };
    try {
      final decoded = jsonDecode(content);
      if (decoded is Map) {
        final originalOk = decoded['ok'];
        if (originalOk is bool) compact['ok'] = originalOk;
        final originalCode = decoded['code'];
        if (originalCode is String && originalCode.isNotEmpty) {
          compact['original_code'] = originalCode;
        }
        final originalMessage = decoded['message'];
        if (originalMessage is String && originalMessage.isNotEmpty) {
          compact['original_message'] = _truncate(originalMessage, 240);
        }
        for (final key in const [
          'changed',
          'awaiting_approval',
          'revision',
          'has_more',
          'next_start_line',
          'task_id',
          'project_id',
          'status',
          'steps',
          'acceptance',
          'inherited_acceptance',
          'local_acceptance',
          'effective_acceptance',
          'dependencies',
          'milestone',
          'metadata',
          'resource',
          'id',
          'ref',
          'persistence_revision',
          'workspace_graph',
        ]) {
          final value = decoded[key];
          if (value is String ||
              value is num ||
              value is bool ||
              value is List ||
              value is Map) {
            compact[key] = value;
          }
        }
      }
    } on FormatException {
      // Keep the compact marker for malformed or non-JSON output.
    }
    return jsonEncode(compact);
  }

  static int _estimateCharacters(List<ChatMessage> messages) {
    var total = 0;
    for (final message in messages) {
      total += message.role.length;
      total += message.content.length;
      total += message.reasoningContent.length;
      total += message.toolCallId.length;
      for (final toolCall in message.toolCalls) {
        total += jsonEncode(
          _chatMessageAdapter.encode(
            ChatMessage(role: 'assistant', content: '', toolCalls: [toolCall]),
          ),
        ).length;
      }
    }
    return total;
  }

  static String _truncate(String value, int maxCharacters) =>
      value.length <= maxCharacters
      ? value
      : '${value.substring(0, maxCharacters)}…';
}
