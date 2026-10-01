import 'dart:convert';

import 'package:hermes/core/cancellation.dart';
import 'package:hermes/features/tools/application/tool_contracts.dart';
import 'package:hermes/features/workspace/application/workspace.dart';

/// Converts model/tool wire calls into the typed [ToolRegistryPort].
/// JSON strings are intentionally confined to this adapter.
class ToolProtocolAdapter {
  const ToolProtocolAdapter({required ToolRegistryPort registry})
    : _registry = registry;

  final ToolRegistryPort _registry;

  Future<ToolResult> executeTyped({
    required String toolId,
    required String argumentsJson,
    WorkspaceToolContext? context,
  }) async {
    final toolContext = context == null
        ? null
        : ToolContext(
            workspace: ToolWorkspace(
              rootPath: context.workspace.rootPath,
              displayName: context.workspace.displayName,
              missing: context.workspace.missing,
              commandExecutionApproved:
                  context.workspace.commandExecutionApproved,
            ),
            permission: _registry.permissionFor(toolId),
            cancellationToken: context.cancellationToken,
            subagentService: context.subagentService,
          );
    try {
      final decoded = jsonDecode(argumentsJson);
      if (decoded is! Map) {
        throw const FormatException('Tool arguments must be a JSON object.');
      }
      final request = ToolRequest(
        toolId: toolId,
        arguments: ToolArguments({
          for (final entry in decoded.entries)
            entry.key.toString(): entry.value,
        }),
        context: toolContext,
      );
      return _registry.executeTyped(request);
    } on FormatException catch (error) {
      return ToolFailure(
        code: 'invalid_tool_arguments',
        message: error.toString(),
      );
    } on OperationCancelledException {
      return const ToolFailure(
        code: 'cancelled',
        message: 'Tool execution was cancelled.',
      );
    }
  }

  Future<ToolResult> executeRequest(ToolRequest request) =>
      _registry.executeTyped(request);

  ToolPermission permissionFor(String toolId) =>
      _registry.permissionFor(toolId);

  Future<String> execute({
    required String toolId,
    required String argumentsJson,
    WorkspaceToolContext? context,
  }) async => encodeResult(
    await executeTyped(
      toolId: toolId,
      argumentsJson: argumentsJson,
      context: context,
    ),
  );

  static String encodeResult(ToolResult result) => jsonEncode(switch (result) {
    ToolSuccess(:final value) => value.toValues(),
    ToolFailure(:final code, :final message, :final details) => {
      'error': message,
      'error_code': code,
      ...details.toValues(),
    },
  });
}
