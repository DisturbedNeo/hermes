import 'dart:convert';

import 'package:hermes/features/chat/application/contracts/bubble.dart';
import 'package:hermes/features/chat/application/contracts/chat_tool_execution.dart';
import 'package:hermes/features/tools/application/tool_contracts.dart';

/// Decodes persisted/model tool-call wire data into typed chat requests.
class ChatToolCallProtocolAdapter {
  const ChatToolCallProtocolAdapter();

  ChatPendingToolCall decode({
    required int index,
    required BubbleToolCall call,
  }) {
    final raw = call.arguments?.trim() ?? '';
    if (raw.isEmpty) {
      return ChatPendingToolCall(
        index: index,
        id: call.id,
        name: call.name,
        arguments: const ToolArguments(),
      );
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return ChatPendingToolCall(
          index: index,
          id: call.id,
          name: call.name,
          arguments: ToolArguments.fromValues({
            for (final entry in decoded.entries)
              entry.key.toString(): entry.value,
          }),
        );
      }
    } on FormatException {
      // The tool service receives an empty typed argument set for malformed
      // wire input and reports the call-level validation error.
    }
    return ChatPendingToolCall(
      index: index,
      id: call.id,
      name: call.name,
      arguments: const ToolArguments(),
    );
  }
}
