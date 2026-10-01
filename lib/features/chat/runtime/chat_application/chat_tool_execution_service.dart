import 'package:hermes/core/cancellation.dart';
import 'package:hermes/features/chat/application/contracts/chat_tool_execution.dart';
import 'package:hermes/features/tools/application/tool_contracts.dart';
import 'package:hermes/features/tools/application/tool_protocol_adapter.dart';
import 'package:hermes/features/workspace/application/workspace.dart';

abstract interface class ChatToolExecutionPort {
  Future<void> executePendingCalls({
    required List<ChatPendingToolCall> calls,
    required WorkspaceAttachment? workspace,
    required CancellationToken cancellationToken,
    required void Function(ChatToolExecutionResult result) onResult,
  });
}

/// Executes chat tool calls without owning model continuation or chat state.
///
/// The service consumes and emits typed values. JSON encoding remains inside
/// the protocol adapter used by the session when it persists tool results.
class ChatToolExecutionService implements ChatToolExecutionPort {
  const ChatToolExecutionService({required ToolProtocolAdapter protocol})
    : _protocol = protocol;

  final ToolProtocolAdapter _protocol;

  @override
  Future<void> executePendingCalls({
    required List<ChatPendingToolCall> calls,
    required WorkspaceAttachment? workspace,
    required CancellationToken cancellationToken,
    required void Function(ChatToolExecutionResult result) onResult,
  }) async {
    for (final call in calls) {
      cancellationToken.throwIfCancelled();
      final result = call.name == null || call.name!.trim().isEmpty
          ? const ToolFailure(
              code: 'invalid_tool_call',
              message: 'Tool call is missing a tool name.',
            )
          : await _protocol.executeRequest(
              ToolRequest(
                toolId: call.name!,
                arguments: call.arguments,
                context: workspace == null || workspace.missing
                    ? null
                    : ToolContext(
                        workspace: ToolWorkspace(
                          rootPath: workspace.rootPath,
                          displayName: workspace.displayName,
                          missing: workspace.missing,
                          commandExecutionApproved:
                              workspace.commandExecutionApproved,
                        ),
                        permission: _protocol.permissionFor(call.name!),
                        cancellationToken: cancellationToken,
                      ),
              ),
            );
      onResult(ChatToolExecutionResult(index: call.index, result: result));
    }
  }
}
