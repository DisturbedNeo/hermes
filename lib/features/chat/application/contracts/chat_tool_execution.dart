import 'package:hermes/features/tools/application/tool_contracts.dart';

/// A validated tool call handed to the chat execution capability.
///
/// Conversion from model/persistence wire data is owned by a chat protocol
/// adapter. Chat runtime ports never receive JSON argument strings.
class ChatPendingToolCall {
  const ChatPendingToolCall({
    required this.index,
    required this.id,
    required this.name,
    required this.arguments,
  });

  final int index;
  final String? id;
  final String? name;
  final ToolArguments arguments;
}

/// Typed result emitted by chat tool execution. The persistence/model wire
/// representation is created only after this result reaches the session.
class ChatToolExecutionResult {
  const ChatToolExecutionResult({required this.index, required this.result});

  final int index;
  final ToolResult result;
}
