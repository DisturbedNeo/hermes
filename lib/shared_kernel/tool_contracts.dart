import 'dart:convert';

import 'package:hermes/core/services/cancellation_token.dart';

/// Typed request crossing an application/tool boundary. JSON is decoded once
/// at the protocol adapter and is not passed through the application graph.
class ToolRequest {
  const ToolRequest({
    required this.toolId,
    this.arguments = const {},
    this.context,
  });

  final String toolId;
  final Map<String, Object?> arguments;
  final ToolContext? context;

  ToolRequest copyWith({
    String? toolId,
    Map<String, Object?>? arguments,
    ToolContext? context,
  }) => ToolRequest(
    toolId: toolId ?? this.toolId,
    arguments: arguments ?? this.arguments,
    context: context ?? this.context,
  );

  factory ToolRequest.decode(String raw, {ToolContext? context}) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('Tool request must be a JSON object.');
    }
    final toolId = decoded['tool'] ?? decoded['name'] ?? decoded['id'];
    final arguments = decoded['arguments'] ?? decoded['args'] ?? const {};
    if (toolId is! String || toolId.trim().isEmpty) {
      throw const FormatException('Tool request is missing a tool id.');
    }
    if (arguments is! Map) {
      throw const FormatException('Tool arguments must be a JSON object.');
    }
    return ToolRequest(
      toolId: toolId,
      arguments: {
        for (final entry in arguments.entries)
          entry.key.toString(): entry.value,
      },
      context: context,
    );
  }
}

/// Framework-neutral workspace identity used by application ports.
class ToolWorkspace {
  const ToolWorkspace({
    required this.rootPath,
    this.displayName = '',
    this.missing = false,
    this.commandExecutionApproved = false,
  });

  final String rootPath;
  final String displayName;
  final bool missing;
  final bool commandExecutionApproved;
}

enum ToolPermission { none, readWorkspace, writeWorkspace, executeCommand }

class ToolContext {
  const ToolContext({
    this.workspace,
    this.permission = ToolPermission.none,
    this.cancellationToken,
  });

  final ToolWorkspace? workspace;
  final ToolPermission permission;
  final CancellationToken? cancellationToken;

  bool allows(ToolPermission required) => permission.index >= required.index;
}

sealed class ToolResult {
  const ToolResult();

  bool get isSuccess => this is ToolSuccess;

  Map<String, Object?> toMap();

  String encode() => jsonEncode(toMap());

  factory ToolResult.decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return const ToolFailure(
        code: 'malformed_result',
        message: 'Tool result must be a JSON object.',
      );
    }
    final error = decoded['error']?.toString();
    if (error != null && error.isNotEmpty) {
      return ToolFailure(
        code: decoded['error_code']?.toString() ?? 'tool_error',
        message: error,
        details: Map<String, Object?>.from(decoded),
      );
    }
    return ToolSuccess(Map<String, Object?>.from(decoded));
  }
}

class ToolSuccess extends ToolResult {
  const ToolSuccess(this.value);

  final Map<String, Object?> value;

  @override
  Map<String, Object?> toMap() => value;
}

class ToolFailure extends ToolResult {
  const ToolFailure({
    required this.code,
    required this.message,
    this.details = const {},
  });

  final String code;
  final String message;
  final Map<String, Object?> details;

  @override
  Map<String, Object?> toMap() => {
    'error': message,
    'error_code': code,
    ...details,
  };
}
